{% if salt['grains.get']("qubes:persistence") in ["rw-only", ""] %}

{% set context = salt['pillar.get']("matrix", {}) %}
{% set datadir = context.synapse.datadir | default("/var/lib/synapse") %}
{% set confdir = context.synapse.confdir | default("/etc/synapse") %}
{% set media_store_path = context.synapse.media_store_path | default(datadir + "/media_store") %}
{% set signing_key_path = context.synapse.signing_key_path | default(
       confdir + "/" + context.synapse.server_name + ".signing.key"
   ) %}

synapse:
  service.dead

{{ signing_key_path }}:
  file.absent:
  - require:
    - service: synapse

{{ media_store_path }}:
  file.absent:
  - require:
    - service: synapse

{{ context.postgresql.name }} database:
  postgres_database.absent:
  - name: {{ context.postgresql.name }}

{{ context.postgresql.user }} user:
  postgres_user.absent:
  - name: {{ context.postgresql.user }}
  - require:
    - postgres_database: {{ context.postgresql.name }} database

{% else %}

Nothing to nuke:
  test.nop

{% endif %}
