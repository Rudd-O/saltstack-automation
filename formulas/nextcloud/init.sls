include:
- .database
- .program

{% if salt['grains.get']("qubes:persistence") in ["rw-only", ""] %}

extend:
  Nextcloud setup:
    test:
    - require:
      - test: Nextcloud database environment defined

{% endif %}
