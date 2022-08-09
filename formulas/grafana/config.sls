#!objects

import yaml

from salt://lib/defs.sls import PillarConfigWithDefaults, ShowConfig

defaults = yaml.safe_load("""
instance_name: %s
protocol: http
port: 3000
domain: %s
root_url: http://%s:3000
# Set serve_from_sub_path to true if the root_url contains a subpath
# because you are serving Grafana through a frontend proxy.
serve_from_sub_path: false
auth:
  admin_username: admin
  # Set this to true to enable anonymous access.
  # See https://grafana.com/docs/grafana/latest/setup-grafana/configure-security/configure-authentication/grafana/#anonymous-authentication
  anonymous: false
  # Set this to the default organization anonymous users will see.
  anonymous_org: ""
""" % (grains("id"), grains("fqdn"), grains("fqdn")))

config = PillarConfigWithDefaults("grafana", defaults)

ShowConfig(config)
