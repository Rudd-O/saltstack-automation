{% set name = sls.split(".")[-1] %}

include:
- build.repo.client

{{ name }}:
  mypkg.installed:
  - require:
    - test: repo deployed
  service.running:
  - enable: yes
  - watch:
    - mypkg: {{ name }}
    - file: /etc/default/{{ name }}

/etc/default/{{ name }}
  file.managed:
  - contents: |
      PROMETHEUS_VARNISH_EXPORTER_OPTS=""
