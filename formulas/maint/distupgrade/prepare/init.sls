{% if salt['grains.get']("qubes:persistence") in ("full", "") %}

include:
- .marker
- .debugon
- .selinuxpermissive
- .snapshot
- .units

extend:
  Create distupgrade marker:
    file:
    - require_in:
      - cmd: Snapshot root dataset
  Snapshot root dataset:
    cmd:
    - require_in:
      - service: Enable debug shell
      - file: Set SELinux to permissive
      - test: Before disabling units

Preparation complete:
  test.nop:
  - require:
    - service: Enable debug shell
    - cmd: setenforce 0
    - test: After disabling units

{% else %}

Preparation complete:
  test.nop

{% endif %}
