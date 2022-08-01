#!objects

import yaml

from salt://lib/defs.sls import PillarConfigWithDefaults, ShowConfig

defaults = yaml.safe_load("""
instance_name: %s
protocol: http
port: 3000
domain: %s
root_url: http://%s:3000
admin_username: admin
""" % (grains("id"), grains("fqdn"), grains("fqdn")))

config = PillarConfigWithDefaults("grafana", defaults)

ShowConfig(config)
