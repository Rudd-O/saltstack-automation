#!objects

import yaml

from salt://lib/defs.sls import PillarConfigWithDefaults, ShowConfig


defaults = yaml.safe_load("""
server:
  rpm:
    setype: samba_share_t
  docker:
    address: unix:/run/docker-distribution/rw
    debug_address: null
    paths:
      htpasswd: /etc/docker-distribution/registry/htpasswd
client:
  rpm:
    repo_name: dnf-updates
mirror:
  selinux_repo_context: httpd_sys_content_t
  paths:
    root: /srv/repo
""")
defaults["server"]["docker"]["vhost"] = grains("fqdn")
defaults["server"]["rpm"]["vhost"] = grains("fqdn")
defaults["mirror"]["server_name"] = grains("fqdn")

config = PillarConfigWithDefaults("build:repo", defaults)

ShowConfig(config)
