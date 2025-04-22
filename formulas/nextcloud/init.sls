include:
- .database
- .program
- .files_actions

{% if salt['grains.get']("qubes:persistence") in ["rw-only", ""] %}

extend:
  nextcloud:
{%   if salt['grains.get']("qubes:persistence") in [""] %}
    pkg:
{%   else %}
    test:
{%   endif %}
    - require_in:
      - test: Nextcloud database environment not yet defined
  Nextcloud begin setup:
    test:
    - require:
      - test: Nextcloud database environment defined

{% endif %}
