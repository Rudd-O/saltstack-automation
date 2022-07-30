#!objects

from salt://build/repo/config.sls import config
from salt://lib/defs.sls import Perms


context = config.server
slsp = "/".join(sls.split(".")[:-1])

File.managed(
  "/usr/local/bin/artifactsh",
  source=f"salt://{slsp}/artifactsh.j2",
  template="jinja",
  context={
      "mirror_host": context.rpm.mirror.host,
      "base_dir": context.rpm.paths.root,
  },
  **Perms.dir,
)
