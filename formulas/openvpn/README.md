# OpenVPN formula

This is a very simple formula to set up OpenVPN servers.
The only supported mode is topology p2p with dev tun
(layer 3).  Sorry, Windows users.

The server is expected to be connected to a LAN and routing
clients to that LAN.  If the `local_ip` parameter on your
OpenVPN server is part of the LAN subnet, then the machine
should use proxy ARP to allow clients on both the VPN side
and the LAN side to talk to each other.

## Pillar reference

To be done.