# SaltStack automation

This repository contains various SaltStack extension modules as well as formulas you can use.

## Prerequisites

The formulas generally require you deploy the extension modules under [`extmods`](extmods/) to your SaltStack setup (master and minions) — they won't work otherwise:

* You would generally deploy these extension modules under your file roots `states/_<module type>` to be accessible in minions, then synced to the minions using `salt '*' saltutil.sync_all`.
* On the Salt master they would go under the `extmods` directory specified in your master's configuration, then synced into the master's cache using `salt-run saltutil.sync_all`.

## Formula list

Formulas are under [`formulas`](formulas/).  Here is an overview:

* [Matrix](formulas/matrix/) helps you set up a self-contained federated Matrix Synapse instance with VoIP signaling support.  To learn more about how to use this formula, [see the guide](https://rudd-o.com/linux-and-free-software/matrix-in-a-box).

## License

The code contained within is licensed under the GNU GPL v2.
