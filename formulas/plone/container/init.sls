{#
will have to

2. change this formula so it deploys plone with containers, and rotates things
   start with high level verbs
   #}


{% if salt['pillar.get']("build.repo.client") %}
include:
- build.repo.client
{% endif %}


{% set context = pillar.plone.container %}
{% set data_basedir = context.get("directories", {}).get("datadir", "/srv/plone") %}


plone-deps:
  pkg.installed:
  - pkgs:
    - podman
  - require_in:
    - test: system requirements

{% for name, user, home in [
    ("process", context.users.process, "/var/lib/" + context.users.process),
   ] %}

{{ name }} user {{ user }}:
  group.present:
  - name: {{ user }}
  user.present:
  - name: {{ user }}
  - gid: {{ user }}
{%   if not salt.user.info(user) %}{# Don't set home if already exists. #}
  - home: {{ home }}
{%   endif %}
  - require:
    - group: {{ name }} user {{ user }}

{{ user }} subgid:
  podman.allocate_subgid_range:
  - name: {{ user }}
  - howmany: 1000
  - require:
    - group: {{ name }} user {{ user }}
  - require_in:
    - test: system requirements

{{ user }} subuid:
  podman.allocate_subuid_range:
  - name: {{ user }}
  - howmany: 1000
  - require:
    - user: {{ name }} user {{ user }}
  - require_in:
    - test: system requirements

{% endfor %}

{{ data_basedir }}:
  file.directory:
  - mode: 0711
  - user: {{ context.users.process }}
  - group: {{ context.users.process }}
  - require:
    - user: process user {{ context.users.process }}
  - require_in:
    - test: system requirements

system requirements:
  test.nop

{% set limit_to = pillar.limit_to | default (context.deployments.keys() | list) %}
{% for deployment_name, deployment_data in context.deployments.items()
     if deployment_name in limit_to %}

{%   if deployment_data.delete | default(False) %}

{%   else %}{# deployment_data.delete #}

{%     set port = deployment_data.base_port + (loop.index0 * 2) %}
{%     set datadir = data_basedir + "/" + deployment_name %}
{%     set options = [
         {"tls-verify": "false"},
         {"subgidname": context.users.process},
         {"subuidname": context.users.process},
       ] %}
{%     set options_blue = options + [
         {"p": "127.0.5.1:" + ((port + 1)|string) + ":8080"},
         {"v": datadir + "-blue/filestorage:/data/filestorage:rw,Z,shared,U"},
         {"v": datadir + "-blue/blobstorage:/data/blobstorage:rw,Z,shared,U"},
       ] %}
{%     set options_green = options + [
         {"p": "127.0.5.1:" + ((port)|string) + ":8080"},
         {"v": datadir + "-green/filestorage:/data/filestorage:rw,Z,shared,U"},
         {"v": datadir + "-green/blobstorage:/data/blobstorage:rw,Z,shared,U"},
       ] %}
{%     set green_datadir = datadir + "-green" %}
{%     set quoted_datadir = salt.text.quote(datadir) %}
{%     set green_exists = salt.file.directory_exists(green_datadir) %}

{%     if green_exists %}

check plone-{{ deployment_name }}-green:
  podman.present:
  - name: plone-{{ deployment_name }}-green
  - image: {{ deployment_data.image }}
  - dryrun: true
  - options: {{ options_green | json }}
  - require:
    - test: system requirements

stop plone-{{ deployment_name }}-blue:
  podman.dead:
  - name: plone-{{ deployment_name }}-blue
  - onchanges:
    - podman: check plone-{{ deployment_name }}-green

copy over {{ deployment_name }} green to blue:
  cmd.run:
  - name: |
      set -e
      rsync -a --delete --inplace {{ quoted_datadir }}-green/filestorage/ {{ quoted_datadir }}-blue/filestorage/
      rm -rf {{ quoted_datadir }}-blue/blobstorage
      cp -al {{ quoted_datadir }}-green/blobstorage {{ quoted_datadir }}-blue/blobstorage
  - require:
    - podman: stop plone-{{ deployment_name }}-blue
  - onchanges:
    - podman: check plone-{{ deployment_name }}-green
  - onchanges_in:
    - podman: start plone-{{ deployment_name }}-blue

{%     else %}

{%       for x in "", "/filestorage", "/blobstorage" %}

{{ datadir }}-blue{{ x }}:
  file.directory:
  - user: {{ context.users.process }}
  - mode: "0755"
{%         if x != "" %}
  - require:
    - file: {{ datadir }}-blue
  - onchanges_in:
    - podman: start plone-{{ deployment_name }}-blue
{%         else %}
  - require:
    - test: system requirements
{%         endif %}
  - unless: test -d {{ quoted_datadir }}-blue{{ x }}

{%       endfor %}

{%     endif %}

start plone-{{ deployment_name }}-blue:
  podman.present:
  - name: plone-{{ deployment_name }}-blue
  - image: {{ deployment_data.image }}
  - options: {{ options_blue | json }}
  - onchanges: []

wait for failover from green to blue:
  cmd.run:
  - name: /bin/true
  - stateful: true
  - onchanges:
    - podman: start plone-{{ deployment_name }}-blue

stop plone-{{ deployment_name }}-green:
  podman.dead:
  - name: plone-{{ deployment_name }}-green
  - require:
    - cmd: wait for failover from green to blue
  - onchanges:
    - podman: start plone-{{ deployment_name }}-blue
  - onchanges_in:
    - cmd: copy over {{ deployment_name }} blue to green

{{ datadir }}-green:
  file.directory:
  - user: {{ context.users.process }}
  - mode: "0755"
  - unless: test -d {{ quoted_datadir }}-green
  - require:
    - podman: stop plone-{{ deployment_name }}-green
  - onchanges_in:
    - cmd: copy over {{ deployment_name }} blue to green

copy over {{ deployment_name }} blue to green:
  cmd.run:
  - name: |
      set -e
      rsync -a --delete --inplace {{ quoted_datadir }}-blue/filestorage/ {{ quoted_datadir }}-green/filestorage/
      rm -rf {{ quoted_datadir }}-green/blobstorage
      cp -al {{ quoted_datadir }}-blue/blobstorage {{ quoted_datadir }}-green/blobstorage
  - onchanges: []

start plone-{{ deployment_name }}-green:
  podman.present:
  - name: plone-{{ deployment_name }}-green
  - image: {{ deployment_data.image }}
  - enable: true
  - options: {{ options_green | json }}
  - require:
    - cmd: copy over {{ deployment_name }} blue to green

wait for failover from blue to green:
  cmd.run:
  - name: /bin/true
  - stateful: true
  - onchanges:
    - podman: start plone-{{ deployment_name }}-green

stop plone-{{ deployment_name }}-blue again:
  podman.dead:
  - name: plone-{{ deployment_name }}-blue
  - require:
    - cmd: wait for failover from blue to green

{%   endif %}{# deployment_data.delete #}

{% endfor %}{# for deployment_name in items #}

{#

{%     endfor %}

{{ deployment_data_dir }}:
  file.absent

{{ deployment_target_dir }}:
  file.absent

{%   else %}

test {{ deployment_name }}:
{%     if deployment_data.get("unit_test_name") %}
  cmd.run:
  - name: |
      set -e
      cd {{ salt.text.quote(deployment_target_dir) }}
      bin/test -m {{ salt.text.quote(deployment_data.unit_test_name) }}
  - runas: {{ context.users.deployer }}
  - onchanges:
    - cmd: buildout {{ deployment_name }}
{%     else %}
  cmd.wait:
  - name: echo Nothing to do.  This deployment has no unit test.
{%     endif %}
  - require:
    - cmd: buildout {{ deployment_name }}
  - require_in:
    - file: clear rebuild flag for {{ deployment_name }}

{%     if deployment_data.get("upgrade", []) %}


upgrade {{ upgrade.site }} for {{ deployment_name }}:
  cmd.run:
  - name: |
      set -e
      cd {{ salt.text.quote(deployment_target_dir) }}
      bin/{{ salt.text.quote(deployment_data.frontend_script) }} upgrade {{ salt.text.quote(upgrade.site) }} {% for p in upgrade.products %} {{ salt.text.quote(p) }}{% endfor %}
  - runas: {{ context.users.deployer }}
  - onchanges:
    - cmd: buildout {{ deployment_name }}
  - require:
    - cmd: start {{ deployment_name }} database for upgrade
  - require_in:
    - file: clear rebuild flag for {{ deployment_name }}
    - service: plone4-database@{{ deployment_name }}

{%       endfor %}

{%     endif %}

cook JS for site {{ upgrade.site }} in {{ deployment_name }}:
  http.wait_for_successful_query:
  - name: {{ ("http://" + deployment_data.zserver_address + "/" + upgrade.site ) | json }}
  - status: 200
  - request_interval: 5
  - wait_for: 30
  - onchanges:
    - service: plone4-frontend@{{ deployment_name }}
  - require_in:
    - file: clear rebuild flag for {{ deployment_name }}

{%       endfor %}

{%     endif %}

{%   endif %}


{% endfor %}

#}