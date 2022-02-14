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

varnishd_connect_any:
  selinux.boolean:
  - value: true
  - require:
    - pkg: varnish
  - require_in:
    - service: varnish

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

/etc/varnish:
  file.recurse:
  - source: salt://{{ sls.replace(".", "/") }}/vcl
  - exclude_pat:
    - backends.vcl
  - require:
    - pkg: varnish
  - require_in:
    - service: varnish
  - onchanges_in:
    - cmd: reload varnish

{% if not salt.file.file_exists("/etc/varnish/backends.vcl") %}
/etc/varnish/backends.vcl:
  file.managed:
  - source: salt://{{ sls.replace(".", "/") }}/vcl/backends.vcl
  - require:
    - pkg: varnish
  - onchanges_in:
    - cmd: reload varnish
  - require_in:
    - service: varnish
{% endif %}

extend:
  /usr/local/bin/varnish-set-backend:
    file:
    - require:
      - service: varnish
