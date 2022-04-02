# Wireguard formula

This is a very simple formula to set up Wireguard among multiple Fedora hosts.

## Pillar reference

Here is what you want each host's pillar data to look like:

```
{% set subnet_map = {
     'a': '10.250.2.1/32, 10.250.0.0/16',
     'b': '10.250.2.3/32',
     'c': '10.250.2.4/32',
} %}
{% set address_map = {
     'a': 'publicip.com',
     'b': 'anotherpublicip.com',
     'c': 'yetanotherpublicip.com',
} %}
{% set pubkey_map = {
     'a': '< pubkey of A >',
     'b': '< pubkey of B >',
     'c': '< pubkey of C >',
} %}
wireguard: # pillar root
  networks: # networks list
    ec2: # name of network
      port: 655 # UDP port to listen to
      netmask: 32 # default netmask for each host
      digest: sha256
      # The following is meant to contain the private key for this specific host.
      # You can probably use a table trick too, like we do above.
      privkey: AAAAAAAAAAAAAAAAAAAAA
      peers:
{% for name, pubkey key in pubkey_map.items() %}
        {{ name }}:
          # This is the public key of the peer.
          pubkey: {{ pubkey }}
          # subnet is a list of IPs allowed to use by the peer (AllowedIPs).
          subnet: {{ subnet_map[name] }}
          # address is where this machine will connect to.
          address: {{ address_map[name] | default(None) | yaml }}
{% endfor %}
```
