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
#    - file: /etc/default/prometheus-xentop

# /etc/default/{{ name }}
#   file.managed:
#   - contents: |
#       ARGS="-bind :9104"
