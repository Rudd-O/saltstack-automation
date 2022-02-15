{% set context = salt['pillar.get'](sls.replace(".", ":"), {}) %}
{% set opts = context.opts | default("-s memory=malloc,256m") %}
{% set listen_addr = context.listen_addr | default(None) %}

include:
- .set_backend

reload systemd for varnish:
  cmd.run:
  - name: systemctl --system daemon-reload
  - onchanges: []

varnish:
  pkg.installed: []
  service.running:
  - enable: true
  - require:
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
