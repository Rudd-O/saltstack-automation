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

# FYI: the following is the default Alertmanager configuration.
"""
route:
  group_by: ['alertname']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 1h
  receiver: 'web.hook'
receivers:
  - name: 'web.hook'
    webhook_configs:
      - url: 'http://127.0.0.1:5001/'
inhibit_rules:
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname', 'dev', 'instance']
"""

config = PillarConfigWithDefaults("prometheus", defaults)

ShowConfig(config)
