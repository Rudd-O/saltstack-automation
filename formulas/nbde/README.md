# Tang and Clevis / key file decryption of LUKS volumes

These formulas allow you to set up a Tang server and enroll
a number of Clevis clients to have them unlock on boot. They
will also add key files to non-Tang+Clevis encrypted devices
so they may decrypt automatically without prompting you for
a passphrase.

Your machines must have a valid network configuration using
NetworkManager or systemd-networkd prior to attempting this.
This network configuration must be DHCP unless you have
manually configured Dracut to give your machines a static
IP address.  They must also list all the block devices to
decrypt on boot in `/etc/crypttab`.  All devices must have
an already-known fallback unlock passphrase in a preexisting
LUKS key slot — this passphrase will be used to enroll all
devices into automatic decryption.

**Devices listed in `/etc/crypttab` which are not mounted
on boot will generally not be successfully decrypted by Tang
and Clevis.  Use key files in conjunction with the
`/etc/cryptsetup-keys.d` facility to decrypt those.
See man page `crypttab(5)` for more information, and read
below for how this formula deals with devices decrypted
through key files.**

Documentation specific to Tang and Clevis is available
[here](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/8/html/security_hardening/configuring-automated-unlocking-of-encrypted-volumes-using-policy-based-decryption_security-hardening).

Most of the logic is implemented in the
[`nbde.py` Salt state module](../../extmods/states/nbde.py).
Some logic resides in the
[`nbde.py` Salt executionmodule](../../extmods/states/nbde.py).

# Contents of the formula

* SLS `nbde.server`: sets up a Tang server.
* SLS `nbde.client`: sets up Clevis on the clients and enrolls them.

# Usage

## Server formula

Set up your Tang server using the aforementioned formula.  Then
ensure your server's TCP port 7500 accepts connections.

## Client formula

Ensure all your clients have the following pillar included:

```
nbde
  client:
    server: http://<your Tang server IP or host name>:7500/
```

Ensure the `/etc/crypttab` file says `none` in the keyfile
field, for all devices to be decrypted using Tang and Clevis.

Ensure the `/etc/crypttab` file says `/etc/cryptsetup-keys.d/X.key`
(`X` is a name of your choice) in the keyfile field, for all
devices to be decrypted using key files.  You don't need to
create the keyfiles — the formula takes care of that.

Then apply the `nbde.client` formula to each machine, with the
following command line:


```
salt <machine> state.sls nbde.client \
  pillar='{nbde: {client: {passphrase: "fallback passphrase"}}}
# You can use salt-ssh if you don't have a central Salt server.
```

This will enroll all block devices in `/etc/crypttab` to the Tang
server you previously set up, if they say `none` in the keyfile
field.  It will also automatically create every nonexistent keyfile
you specified in `/etc/crypttab`, and bind each device to
its respective keyfile.

### What the formula does for non-Tang+Clevis devices

Here is a tip on what to do about each device in question:

1. Looks up the keyfile (normally `/etc/cryptsetup-keys.d/<n>.key`)
   for each one of your non-boot devices listed in `/etc/crypttab`.
2. Perform the following routine:

```
device=/dev/<device>
mkdir -m 700 $(dirname $keyfile)
dd if=/dev/random of=$keyfile bs=32 count=1
chmod 600 $keyfile
cryptsetup luksAddKey $device $keyfile
# that was a simplified sample — the existing recovery passphrase
# is also used in the command above
```
