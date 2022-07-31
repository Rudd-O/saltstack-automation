{% if salt['grains.get']("qubes:persistence") in ("full", "") %}

include:
- .debugon
- .selinuxpermissive
- .snapshot

extend:
  Snapshot root dataset:
    cmd:
    - require_in:
      - service: Enable debug shell
      - file: Set SELinux to permissive

Preparation complete:
  test.nop:
  - require:
    - service: Enable debug shell
    - cmd: setenforce 0

{% else %}

Preparation complete:
  test.nop

{% endif %}
