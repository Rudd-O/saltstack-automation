#!objects

import yaml

from salt://lib/defs.sls import PillarConfigWithDefaults, ShowConfig

fqdn = grains("fqdn")

defaults = yaml.safe_load("""
master:
  url: http://%s:9090/
  retention: 90GB
  global:
    scrape_interval: 60s
    scrape_timeout: 59s
    evaluation_interval: 60s
  recording_rules: {}
  alerting_rules: {}
  aliases: {}
  scrapers:
    direct: {}
    snmp: {}
    blackbox: {}
alertmanager:
  url: http://%s:9093/
  global: {}
  route:
    group_by: ['alertname']
    group_wait: 30s
    group_interval: 5m
    repeat_interval: 1h
  receivers: []
  inhibit_rules: []
""" % (fqdn, fqdn))

# FYI: the following is the default Alertmanager configuration.
"""
route:
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
if "receiver" not in config.alertmanager.route:
  config.alertmanager.receivers = config.alertmanager.receivers + [
    {
      "name": "web-hook",
      "webhook_configs": [
        {
          "url": "http://127.0.0.1:5001/"
        }
      ]
    }
  ]
  config.alertmanager.route.receiver = "web-hook"

ShowConfig(config)
