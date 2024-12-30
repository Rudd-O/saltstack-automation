#!objects

from salt://prometheus/exporter/node_exporter/config.sls import config
from salt://lib/qubes.sls import updateable


name = "node_exporter"
textfile_directory = config.paths.textfile_directory

milestone = Test.nop("Collector directory created").requisite
absent = Qubes.unbind_dirs(f'{name} collector directory', name="node_exporter-collector", directories=["/var/lib/node_exporter"], require_in=[milestone]).requisite
File.absent("Delete bound dir for node exporter", name="/rw/bind-dirs/var/lib/node_exporter", require=[absent], require_in=[milestone])
