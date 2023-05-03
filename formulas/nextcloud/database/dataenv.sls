{% set context = pillar.nextcloud.database %}

Nextcloud database environment not yet defined:
  test.nop

{{ context.name }} database:
  mysql_database.present:
  - name: {{ context.name }}
  - require:
    - test: Nextcloud database environment not yet defined
  - require_in:
    - mysql_user: {{ context.user + " user" }}

{{ context.user }} user:
  mysql_user.present:
  - name: {{ context.user }}
  - host: localhost
  - password: {{ context.password }}
  - require_in:
    - mysql_grants: {{ context.user }} privileges on {{ context.name }}

{{ context.user }} privileges on {{ context.name }}:
  mysql_grants.present:
  - grant: all privileges
  - database: {{ context.name }}.*
  - user: {{ context.user }}
  - host: localhost
  - require_in:
    - test: Nextcloud database environment defined

Nextcloud database environment defined:
  test.nop
