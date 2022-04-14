include:
- plone.content_cache.pkg
- nginx

nginxvarnish:
  customselinux.policy_module_present:
  - source: salt://{{ sls.split(".")[:-1] | join("/") }}/nginxvarnish.te
  - require_in:
    - service: nginx
  - require:
    - pkg: varnishpkg

httpd_can_network_relay for Plone:
  selinux.boolean:
  - name: httpd_can_network_relay
  - value: True
  - require_in:
    - service: nginx
  - require:
    - pkg: nginx
    - pkg: varnishpkg
