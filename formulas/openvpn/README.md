# OpenVPN formula

This is a very simple formula to set up OpenVPN servers.
The only supported mode is topology subnet with dev tun
(layer 3).

The server is expected to be connected to a LAN and routing
clients to that LAN.  The `local_ip` parameter may be an
IP address that your OpenVPN server already is using.

So long as the OpenVPN server is the default route on the
other side of the network (the LAN), machines on the LAN
LAN side know to talk to VPN clients via the OpenVPN server.

## Pillar reference


You can control the client routes with the parameter
`client_routes`.

More to be documented.