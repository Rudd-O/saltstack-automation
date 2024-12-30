#!objects

from salt://lib/defs.sls import Dotdict
from salt://lib/qubes.sls import physical, dom0


textfile_directory = "/var/lib/node_exporter" if physical() or dom0() else "/run/node_exporter"

config = Dotdict(
    {
        "paths": {
            "textfile_directory": textfile_directory,
            "collector_directory": "/usr/lib/node_exporter"
        }
    }
)
