{% set context = pillar.matrix.postgresql %}

Synapse database environment not yet defined:
  test.nop

{{ context.user }} user:
  postgres_user.present:
  - name: {{ context.user }}
  - encrypted: scram-sha-256
  - password: {{ context.password }}
  - require:
    - test: Synapse database environment not yet defined
  - require_in:
    - test: Synapse database environment defined

{{ context.name }} database:
  postgres_database.present:
  - name: {{ context.name }}
  - owner: {{ context.user }}
  - encoding: UTF8
  - lc_ctype: C
  - lc_collate: C
  - template: template0
  - require:
    - postgres_user: {{ context.user + " user" }}
    - test: Synapse database environment not yet defined
  - require_in:
    - test: Synapse database environment defined

Synapse database environment defined:
  test.nop
