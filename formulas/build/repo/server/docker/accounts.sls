#!objects

from salt://build/repo/config.sls import config

context = config.server.docker


milestone = Test.nop("docker-distribution accounts managed").requisite

p = Pkg.installed("htpasswd", pkgs=["httpd-tools"]).requisite

f = File.managed(
    "htpasswd authentication for docker-distribution",
    name=context.paths.htpasswd,
    user="root",
    group="nginx",
    mode="0640",
).requisite

for item in context.accounts:
    Webutil.user_exists(
      f"user account {item.user}",
      name=item.user,
      password=item.password,
      htpasswd_file=context.paths.htpasswd,
      options="B",
      update=True,
      require=[f, p],
      require_in=[milestone],
    )
