#!objects

from salt://lib/qubes.sls import fully_persistent_or_physical, dom0, physical
from textwrap import dedent


def copr(owner, name):
    if fully_persistent_or_physical():
        return File.managed(
            f"/etc/yum.repos.d/copr-{owner}-{name}.repo",
            contents=dedent(f"""\
            [copr:copr.fedorainfracloud.org:{owner}:{name}]
    name=Copr repo for {name} owned by {name}
    baseurl=https://download.copr.fedorainfracloud.org/results/{owner}/{name}/fedora-$releasever-$basearch/
    type=rpm-md
    skip_if_unavailable=True
    gpgcheck=1
    gpgkey=https://download.copr.fedorainfracloud.org/results/{owner}/{name}/pubkey.gpg
    repo_gpgcheck=0
    enabled=1
    enabled_metadata=1
            """)
        ).requisite
    else:
        return Test.nop(f"/etc/dnf.repos.d/copr-{owner}-{name}.repo").requisite
