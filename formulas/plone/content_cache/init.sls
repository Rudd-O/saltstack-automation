{% set context = salt['pillar.get'](sls.replace(".", ":"), {}) %}

{% if context.get("stevedores") %}
{%   set stevedores = [] %}
{%   for s, v in context.get("stevedores").items() %}
{%     set x = "-s " + s + "=" + v["type"] %}
{%     if v.get("path") %}
{%        set x = x + "," + v["path"] %}
{%     endif %}
{%     if v.get("size") %}
{%        set x = x + "," + v["size"] %}
{%     endif %}
{%     do stevedores.append(x) %}
{%   endfor %}
{%   set stevedores = " ".join(stevedores) %}
{% else %}
{%   set stevedores = "" %}
{% endif %}

{% if context.get("listen_addr") or context.get("opts") or stevedores %}
{%   if context.get("opts") %}
{%     set opts = context.opts + (stevedores | default("-s memory=default,256m")) %}
{%   else %}
{%     set opts = stevedores %}
{%   endif %}
{%   set listen_addr = context.listen_addr | default(":6081") %}
{% else %}
{%   set opts = None %}
{%   set listen_addr = None %}
{% endif %}

Debug Varnish configuration:
  test.nop:
  - name: |
      Stevedores: {{ stevedores | json }}
      Opts: {{ opts | json }}
      Listen addr: {{ listen_addr | json }}

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
    - pkg: varnishpkg
    - cmd: reload systemd for varnish

{% if salt['grains.get']("qubes:vm_type", "") == "" %}
varnishd_connect_any:
  selinux.boolean:
  - value: true
  - persist: true
  - require:
    - pkg: varnishpkg
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

/etc/systemd/system/varnish.service.d/ulimits.conf:
  file.managed:
  - contents: |
      [Service]
      LimitNOFILE=1048576
  - makedirs: True
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
      ExecStart=/usr/sbin/varnishd \
                -a {{ listen_addr }} \
                -f /etc/varnish/default.vcl \
                {%- if grains.osmajorrelease | int >= 37 %}
                -P %t/%N/varnishd.pid \
                {%- endif %}
                -p feature=+http2 \
                {{ opts }}
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
  - template: jinja
  - context:
      purgekey: {{ context.get("purgekey", "") | json }}
      stevedores: {{ context.get("stevedores", {}) | json }}
  - exclude_pat:
    - 50-backends.vcl
  - require:
    - pkg: varnishpkg
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
    - pkg: varnishpkg
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
