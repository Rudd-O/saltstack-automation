#!objects

import yaml

from salt://lib/defs.sls import PillarConfigWithDefaults, ShowConfig

defaults = yaml.safe_load("""{}""")

config = PillarConfigWithDefaults("openvpn", defaults)
ShowConfig(config)
