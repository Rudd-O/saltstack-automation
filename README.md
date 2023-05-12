# SaltStack automation

This repository contains various SaltStack extension modules as well as formulas you can use.

## Prerequisites

The formulas generally require you deploy the extension modules under [`extmods`](extmods/) to your SaltStack setup (master and minions) — they won't work otherwise:

* You would generally deploy these extension modules under your file roots `states/_<module type>` to be accessible in minions, then synced to the minions using `salt '*' saltutil.sync_all`.
* On the Salt master they would go under the `extmods` directory specified in your master's configuration, then synced into the master's cache using `salt-run saltutil.sync_all`.

## Formula list

Formulas are under [`formulas`](formulas/).  Here is an overview:

* [Matrix](formulas/matrix/) helps you set up a self-contained federated Matrix Synapse instance with VoIP signaling support.  To learn more about how to use this formula, [see the guide](https://rudd-o.com/linux-and-free-software/matrix-in-a-box).
* [Wireguard](formulas/wireguard/) sets up simple wg-quick Wireguard networks among multiple hosts.  You can set up more than one.  See the `README.md` file in that directory.
* [Email](formulas/email) sets up various e-mail system components.
* [Network block device encryption (Tang+Clevis)](formulas/nbde) sets up server and clients for network-based disk decryption on boot.  See the `README.md` file in that directory.
* [Nextcloud](formulas/nextcloud) sets up a Nextcloud instance.  See the `README.md` file in that directory.

## SaltStack `bombshell-client` adapters for Qubes OS

This program also contains a set of shims that can be used to make `salt-ssh` work against Qubes OS qubes, whether local or remote.  See the  [bin/README.md](bin/README.md) file for more information.

## License

The code contained within is licensed under the GNU GPL v2.
