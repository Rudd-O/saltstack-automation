#!objects

import yaml

from salt://lib/defs.sls import PillarConfigWithDefaults, ShowConfig

fqdn = grains("fqdn")

defaults = yaml.safe_load("""
master:
  url: http://%s:9090/
  retention: 90GB
  recording_rules: {}
  alerting_rules: {}
  scrapers:
    direct: {}
    snmp: {}
    blackbox: {}
  proxy_addresses: {}
alertmanager:
  url: http://%s:9093/
  global: {}
  route: {}
  receivers: {}
  inhibit_rules: {}
""" % (fqdn, fqdn))

config = PillarConfigWithDefaults("prometheus", defaults)

ShowConfig(config)
