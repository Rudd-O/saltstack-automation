{% from 'lib/selinux.sls' import selinux_module %}

{{ selinux_module('nginxvarnish', 'salt://' + (sls.split(".")[:-1] | join("/")) + '/nginxvarnish.te') }}

include:
- plone.content_cache.pkg

httpd_can_network_relay for Plone:
  selinux.boolean:
  - name: httpd_can_network_relay
  - value: True
  - require_in:
    - service: nginx
  - require:
    - pkg: nginx
    - pkg: varnish
