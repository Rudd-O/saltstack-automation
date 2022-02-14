python3-jinja2:
  pkg.installed

python3-requests:
  pkg.installed

/usr/local/bin/varnish-set-backend:
  file.managed:
  - source: salt://{{ sls.replace(".", "/") }}/varnish-set-backend
  - mode: "0755"
  - require:
    - pkg: python3-jinja2
    - pkg: python3-requests
