{% if salt['grains.get']("qubes:persistence") in ("full", "") %}

include:
- .debugoff
- .selinuxenforcing

Cleanup begun:
  test.nop:
  - require_in:
    - service: Disable debug shell
    - cmd: setenforce 1

Remove distupgrade marker:
  file.absent:
  - name: /.distupgrade
  - require:
    - service: Disable debug shell
    - file: Set SELinux to enforcing

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
