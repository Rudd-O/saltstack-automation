{% if salt['grains.get']("qubes:persistence") in ("full", "") %}

include:
- .marker
- .debugoff
- .selinuxenforcing
- .units

Cleanup begun:
  test.nop:
  - require_in:
    - service: Disable debug shell
    - cmd: setenforce 1
    - test: Before enabling units

extend:
  Remove distupgrade marker:
    file:
    - require:
      - service: Disable debug shell
      - file: Set SELinux to enforcing
      - test: After enabling units

Cleanup complete:
  test.nop:
  - require:
    - file: Remove distupgrade marker

{% else %}

Cleanup begun:
  test.nop:
  - require_in:
    - test: Cleanup complete

Cleanup complete:
  test.nop:

{% endif %}
