podman:
  pkg.installed

{% set subdirs = {
     "": "",
     "logs": "/var/log/onlyoffice",
     "data": "/var/www/onlyoffice/Data",
     "lib": "/var/lib/onlyoffice",
     "db": "/var/lib/postgresql",
   } %}

onlyoffice:
  group.present:
  - system: true
  user.present:
  - system: true
  - gid: onlyoffice
  - shell: /usr/sbin/nologin
  - require:
    - group: onlyoffice
  podman.present:
  - image: docker.io/onlyoffice/documentserver
  - enable: true
  - options:
    - p: 127.0.4.80:7080:80
    - cap-add: net_bind_service
    - subgidname: onlyoffice
    - subuidname: onlyoffice
{% for f, g in subdirs.items() %}{% if f %}
    - v: /srv/onlyoffice/{{ salt.text.quote(f) }}:{{ salt.text.quote(g) }}:rw,Z,shared
{% endif %}{% endfor %}
  - require:
    - pkg: podman
    - podman: onlyoffice subgid
    - podman: onlyoffice subuid

onlyoffice subgid:
  podman.allocate_subgid_range:
  - name: onlyoffice
  - howmany: 1000
  - require:
    - group: onlyoffice

onlyoffice subuid:
  podman.allocate_subuid_range:
  - name: onlyoffice
  - howmany: 1000
  - require:
    - user: onlyoffice

{% for f in subdirs %}
/srv/onlyoffice/{{ f }}:
  file.directory:
  - name: /srv/onlyoffice{% if f %}/{% endif %}{{ f }}
  - user: onlyoffice
  - group: onlyoffice
  - mode: {% if f %}1777{% else %}0771{% endif %}
  - require_in:
    - podman: onlyoffice
  - require:
    - user: onlyoffice
{%   if f %}
    - file: /srv/onlyoffice/
{%   endif %}
{% endfor %}
