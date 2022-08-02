#!objects

from salt://prometheus/exporter/node_exporter/config.sls import config
from salt://lib/qubes.sls import template


name = "node_exporter"
textfile_directory = config.paths.textfile_directory

milestone = Test.nop("Collector directory created").requisite

if template():
    File.absent(textfile_directory, require_in=[milestone])
else:
    with File.directory(
        textfile_directory,
        mode="0750",
        user="root",
        group="prometheus",
        watch_in=[milestone],
    ):
        q = Qubes.bind_dirs(
            f'{name} collector directory',
            name="node_exporter-collector",
            directories=[textfile_directory],
            watch_in=[milestone],
        ).requisite
