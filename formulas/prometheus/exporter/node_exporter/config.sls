#!objects

from salt://lib/defs.sls import Dotdict


config = Dotdict(
    {
        "paths": {
            "textfile_directory": "/var/lib/node_exporter",
            "collector_directory": "/usr/lib/node_exporter"
        }
    }
)
