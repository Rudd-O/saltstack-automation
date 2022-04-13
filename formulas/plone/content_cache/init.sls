{% set context = salt['pillar.get'](sls.replace(".", ":"), {}) %}
{% if context.get("listen_addr") or context.get("opts") %}
{%   set opts = context.opts | default("-s memory=malloc,256m") %}
{%   set listen_addr = context.listen_addr | default(":6081") %}
{% else %}
{%   set opts = None %}
{%   set listen_addr = None %}
{% endif %}

include:
- .set_backend
- .pkg

reload systemd for varnish:
  cmd.run:
  - name: systemctl --system daemon-reload
  - onchanges: []

varnish:
  service.running:
  - enable: true
  - require:
    - pkg: varnish
    - cmd: reload systemd for varnish

{% if salt['grains.get']("qubes:vm_type", "") == "" %}
varnishd_connect_any:
  selinux.boolean:
  - value: true
  - require:
    - pkg: varnish
  - require_in:
    - service: varnish
{% endif %}

reload varnish:
  cmd.run:
  - name: systemctl --system reload varnish
  - onchanges: []
  - require:
    - service: varnish

/etc/systemd/system/varnish.service.d/port80.conf:
  file.absent:
  - watch_in:
    - service: varnish
  - onchanges_in:
    - cmd: reload systemd for varnish

/etc/systemd/system/varnish.service.d/custom.conf:
{% if listen_addr or opts %}
  file.managed:
  - contents: |
      [Service]
      ExecStart=
      ExecStart=/usr/sbin/varnishd -a {{ listen_addr }} -f /etc/varnish/default.vcl {{ opts }}
  - makedirs: true
{% else %}
  file.absent:
{% endif %}
  - watch_in:
    - service: varnish
  - onchanges_in:
    - cmd: reload systemd for varnish

/etc/varnish/plone:
  file.recurse:
  - source: salt://{{ sls.replace(".", "/") }}/vcl
  - clean: true
  - exclude_pat:
    - 50-backends.vcl
  - require:
    - pkg: varnish
  - require_in:
    - service: varnish
    - cmd: /etc/varnish/plone/default.vcl
    - file: /usr/local/bin/varnish-set-backend
  - onchanges_in:
    - cmd: reload varnish

{% if not salt.file.file_exists("/etc/varnish/plone/50-backends.vcl") %}
/etc/varnish/plone/50-backends.vcl:
  file.managed:
  - source: salt://{{ sls.replace(".", "/") }}/vcl/50-backends.vcl
  - require:
    - pkg: varnish
    - file: /etc/varnish/plone
  - onchanges_in:
    - cmd: reload varnish
  - require_in:
    - service: varnish
    - cmd: /etc/varnish/plone/default.vcl
    - file: /usr/local/bin/varnish-set-backend
{% endif %}

/etc/varnish/plone/default.vcl:
  cmd.script:
  - source: salt://{{ sls.replace(".", "/") }}/generate-default.vcl.py
  - stateful: true
  - require_in:
    - service: varnish
    - file: /usr/local/bin/varnish-set-backend
  - onchanges_in:
    - cmd: reload varnish

extend:
  /usr/local/bin/varnish-set-backend:
    file:
    - require:
      - service: varnish
