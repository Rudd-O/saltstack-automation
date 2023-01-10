# Tang and Clevis decryption of LUKS volumes on boot

These formulas allow you to set up a Tang server and enroll
a number of Clevis clients to have them unlock on boot.

Documentation of Tang and Clevis is available
[here](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/8/html/security_hardening/configuring-automated-unlocking-of-encrypted-volumes-using-policy-based-decryption_security-hardening).

Your machines must have a valid network configuration using
NetworkManager or systemd-networkd prior to attempting this.
This network configuration must be DHCP unless you have
manually configured Dracut to give your machines a static
IP address.  They must also list all the block devices to
decrypt on boot in `/etc/crypttab` with an already-known
fallback unlock passphrase in a preexisting LUKS key slot.

**Devices listed in `/etc/crypttab` which are not mounted
on boot will not be decrypted.  Use key files in conjunction
with the /etc/cryptsetup-keys.d facility to decrypt those.
See man page `crypttab(5)` for more information.**  Here is
a tip on what to do about each device in question:

1. Add path `/etc/cryptsetup-keys.d/<fn>.key` to each one
   of these non-boot devices in `/etc/crypttab`.
2. Perform the following routine:

```
fn=<fn>
device=/dev/<device>
mkdir -m 700 /etc/cryptsetup-keys.d
dd if=/dev/random of=/etc/cryptsetup-keys.d/$fn.key bs=128 count=1
chmod 600 /etc/cryptsetup-keys.d/$fn.key
cryptsetup luksAddKey $device /etc/cryptsetup-keys.d/$fn.key
# now input an existing recovery passphrase
```

# Contents of the formula

* SLS `nbde.server`: sets up a Tang server.
* SLS `nbde.client`: sets up Clevis on the clients and enrolls them.

# Usage

Set up your Tang server using the aforementioned formula.  Then
ensure your server's TCP port 7500 accepts connections.

Then, ensure all your clients have the following pillar included:

```
nbde
  client:
    server: http://<your server IP or host name>:7500/
```

Then apply the `nbde.client` formula to each machine, with the
following command line:


```
salt <machine> state.sls nbde.client \
  pillar='{nbde: {client: {passphrase: "fallback passphrase"}}}
# You can use salt-ssh if you don't have a central Salt server.
```

This will automatically enroll all block devices in `/etc/crypttab`
to the Tang server you previously set up.
