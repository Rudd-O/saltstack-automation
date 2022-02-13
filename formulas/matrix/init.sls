include:
- .postgresql
- .synapse
- .nginx
- .accounts
- .coturn

{% if salt['grains.get']("qubes:persistence") in ["rw-only", ""] %}

extend:
  synapse:
    service:
    - require:
      - test: Synapse database environment defined
  Accounts not yet defined:
    test:
    - require:
      - service: synapse
      - service: nginx

{% endif %}
