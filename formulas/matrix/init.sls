include:
- .postgresql
- .synapse
- .ssl
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
      - service: nginx after obtaining SSL certificate
  Set coturn ACL for certificates:
    cmd:
    - require:
      - cmd: generate certificate
  /etc/letsencrypt/renewal-hooks/post/coturn:
    file:
    - require:
      - cmd: generate certificate
{% endif %}
