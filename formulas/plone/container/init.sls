{#
will have to

2. change this formula so it deploys plone with containers, and rotates things
   start with high level verbs
   #}


{% if salt['pillar.get']("build.repo.client") %}
include:
- build.repo.client
{% endif %}


{% set context = pillar.plone.buildout %}{# FIXME change var. #}
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
{%     set options = [
         {"tls-verify": "false"},
         {"subgidname": context.users.process},
         {"subuidname": context.users.process},
       ] %}
{%     set options_blue = options + [
         {"p": "127.0.5.1:" + ((port + 1)|string) + ":8080"},
         {"v": data_basedir + "/" + deployment_name + "-blue/filestorage:/data/filestorage:rw,Z,shared,U"},
         {"v": data_basedir + "/" + deployment_name + "-blue/blobstorage:/data/blobstorage:rw,Z,shared,U"},
       ] %}
{%     set options_green = options + [
         {"p": "127.0.5.1:" + ((port)|string) + ":8080"},
         {"v": data_basedir + "/" + deployment_name + "-green/filestorage:/data/filestorage:rw,Z,shared,U"},
         {"v": data_basedir + "/" + deployment_name + "-green/blobstorage:/data/blobstorage:rw,Z,shared,U"},
       ] %}
{%     set datadir = data_basedir + "/" + deployment_name %}
{%     set green_datadir = datadir + "-green" %}
{%     set quoted_datadir = salt.text.quote(data_basedir) + "/" + salt.text.quote(deployment_name) %}
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

{{ data_basedir }}/{{ deployment_name }}-blue{{ x }}:
  file.directory:
  - user: {{ context.users.process }}
  - mode: "0755"
{%         if x != "" %}
  - require:
    - file: {{ data_basedir }}/{{ deployment_name }}-blue
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

{{ data_basedir }}/{{ deployment_name }}-green:
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


{%     for unit in ["plone4-database@", "plone4-frontend@"] %}

{{ unit }}{{ deployment_name }}:
  service.dead:
  - enable: False
  - require_in:
    - file: {{ deployment_data_dir }}
    - file: {{ deployment_target_dir }}
    - file: /etc/systemd/system/{{ unit }}{{ deployment_name }}.service
  - require:
    - file: /etc/systemd/system/{{ unit }}.service

/etc/systemd/system/{{ unit }}{{ deployment_name }}.service:
  file.absent

{%     endfor %}

{{ deployment_data_dir }}:
  file.absent

{{ deployment_target_dir }}:
  file.absent

{%   else %}

{%   set _ = deployment_data.update({
       "debug_mode": {True: "on", False: "off"}[deployment_data.get("debug_mode", True)],
       "threads": deployment_data.get("threads", 2),
       "start": deployment_data.get("start", True),
       "render_buildout_cfg": deployment_data.get("render_buildout_cfg", True),
       "frontend_script": deployment_data.get("frontend_script", "client1"),
     }) %}

{%   if deployment_data.bootstrap_from | default(None) and not salt.file.file_exists(deployment_data_dir) %}

{%     set source = data_basedir + "/" + deployment_data.bootstrap_from %}

{{ deployment_name }} bootstrap from {{ source }}:
  cmd.run:
  - name: |
      set -e
      undo() {
        rm -rf {{ salt.text.quote(deployment_data_dir) }}
        exit 1
      }
      trap 'undo' ERR
      mkdir -p -m 0700 {{ salt.text.quote(deployment_data_dir) }}/var/blobstorage
      rsync -a --inplace {{ salt.text.quote(source) }}/var/Data.fs {{ salt.text.quote(deployment_data_dir) }}/var/Data.fs
      cp -al -t {{ salt.text.quote(deployment_data_dir) }}/var/blobstorage {{ salt.text.quote(source) }}/var/blobstorage/*
      if test -f {{ salt.text.quote(source) }}/var/blobstorage/.layout ; then
        cp -a -t {{ salt.text.quote(deployment_data_dir) }}/var/blobstorage {{ salt.text.quote(source) }}/var/blobstorage/.layout
      fi
  - creates: {{ deployment_data_dir }}
  - runas: {{ context.users.process }}
  - require:
    - file: {{ data_basedir }}
    - user: process user {{ context.users.process }}
  - require_in:
    - cmd: check develop for {{ deployment_name }}
  - onchanges_in:
    - cmd: {{ deployment_name }} needs rebuild

{% endif %}

checkout for {{ deployment_name }}:
  git.latest:
  - name: {{ deployment_data.repo }}
  - target: {{ deployment_target_dir }}
  - rev: {{ deployment_data.get("ref", deployment_name) }}
  - branch: {{ deployment_data.get("ref", deployment_name) }}
  - user: {{ context.users.deployer }}
  - submodules: True
  - update_head: True
  - force_fetch: True
  - force_reset: True
  - force_checkout: True
  - require:
    - file: {{ deployments_basedir }}/deployments
    - user: deployer user {{ context.users.deployer }}

template buildout.cfg.j2 for {{ deployment_name }}:
{%     if deployment_data.get("render_buildout_cfg", True) %}
  file.managed:
  - name: {{ deployment_target_dir }}/buildout.cfg
  - source: {{ deployment_target_dir }}/buildout.cfg.j2
  - user: {{ context.users.deployer }}
  - group: {{ context.users.deployer }}
  - template: jinja
  - context:
      deployments_basedir: {{ deployments_basedir }}
      deployment_target_dir: {{ deployment_target_dir }}
      deployment_data_dir: {{ deployment_data_dir }}
      process_user: {{ context.users.process }}
      item:
        key: {{ deployment_name }}
        value: {{ deployment_data | json }}
  - require:
    - user: deployer user {{ context.users.deployer }}
    - git: checkout for {{ deployment_name }}
{%     else %}
  file.absent:
  - name: {{ deployment_target_dir }}/buildout.cfg.j2
{%     endif %}

read marker for {{ deployment_name }}:
{%     if salt.file.file_exists(deployment_target_dir + "/.dirty") %}
  cmd.run:
  - name: |
      test -f {{ salt.text.quote(deployment_target_dir) }}/.dirty && {
        echo changed=yes
      } || {
        echo changed=no
      }
{%     else %}
  cmd.wait:
  - name: |
      echo changed=no comment="'Nothing to do.  The marker file does not exist.'"
{%     endif %}
  - stateful: yes
  - require:
    - git: checkout for {{ deployment_name }}

check develop for {{ deployment_name }}:
  cmd.run:
  - name: |
      set -e
      cd {{ salt.text.quote(deployment_target_dir) }}
      test -x bin/develop || exit 0
      data=$(bin/develop status)
      changed=no
      if echo "$data" | grep -q '^[C!]' ; then
        for product in $( echo "$data" | grep '^[C!]' | awk ' { print $2 } ' ) ; do
          rm -rf src/"$product"
        done
        changed=yes
      fi
      echo
      echo changed=$changed
  - runas: {{ context.users.deployer }}
  - require:
    - cmd: read marker for {{ deployment_name }}
    - file: template buildout.cfg.j2 for {{ deployment_name }}
  
{{ deployment_name }} needs rebuild:
  cmd.run:
  - name: touch {{ salt.text.quote(deployment_target_dir) }}/.dirty
  - onchanges:
    - git: checkout for {{ deployment_name }}
    - cmd: read marker for {{ deployment_name }}
    - cmd: check develop for {{ deployment_name }}
    - file: template buildout.cfg.j2 for {{ deployment_name }}

buildout {{ deployment_name }}:
  cmd.run:
  - name: |
      set -e
      cd {{ salt.text.quote(deployment_target_dir) }}
      flock {{ salt.text.quote(deployments_basedir) }}/.plone-buildout-lock {{ salt.text.quote(deployment_data.buildout) }} -N
  - runas: {{ context.users.deployer }}
  - onchanges:
    - cmd: {{ deployment_name }} needs rebuild
  - require:
    - pkg: plone-deps
    - file: {{ deployments_basedir }}/extends-cache 
    - file: {{ deployments_basedir }}/buildout-cache/eggs 
    - file: {{ deployments_basedir }}/buildout-cache/downloads 
    - file: {{ data_basedir }}

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

start {{ deployment_name }} database for upgrade:
  cmd.run:
  - name: systemctl start plone4-database@{{ salt.text.quote(deployment_name) }}
  - onchanges:
    - cmd: buildout {{ deployment_name }}
  - require:
    - cmd: reload systemd
    - file: /etc/systemd/system/plone4-database@.service
    - file: /etc/systemd/system/plone4-database@{{ deployment_name }}.service.d/command.conf
    - cmd: test {{ deployment_name }}

{%       for upgrade in deployment_data.get("upgrade", []) %}

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

clear rebuild flag for {{ deployment_name }}:
  file.absent:
  - name: {{ deployment_target_dir }}/.dirty
  - require:
    - cmd: buildout {{ deployment_name }}

plone4-database@{{ deployment_name }}:
  service{% if deployment_data.get("start", True) %}.running{% else %}.dead{% endif %}:
  - enable: {% if deployment_data.get("start", True) %}True{% else %}False{% endif %}
  - require:
    - cmd: reload systemd
  - require_in:
    - file: clear rebuild flag for {{ deployment_name }}
  - watch:
    - file: /etc/systemd/system/plone4-database@.service
    - file: /etc/systemd/system/plone4-database@{{ deployment_name }}.service.d/command.conf
    - cmd: buildout {{ deployment_name }}

plone4-frontend@{{ deployment_name }}:
  service{% if deployment_data.get("start", True) %}.running{% else %}.dead{% endif %}:
  - enable: {% if deployment_data.get("start", True) %}True{% else %}False{% endif %}
  - require_in:
    - file: clear rebuild flag for {{ deployment_name }}
  - require:
    - service: plone4-database@{{ deployment_name }}
    - cmd: reload systemd
  - watch:
    - file: /etc/systemd/system/plone4-frontend@.service
    - file: /etc/systemd/system/plone4-frontend@{{ deployment_name }}.service.d/command.conf
    - cmd: buildout {{ deployment_name }}

{%     if deployment_data.debug_mode == "on" %}
 
{%       for upgrade in deployment_data.get("upgrade", []) %}

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