#!objects

import json

from os.path import join
from shlex import quote

from salt://lib/qubes.sls import template


include("plone.content_cache.set_backend")

if pillar("build:repo:client", ""):
    include("build.repo.client")


context = pillar(sls.replace(".", ":"), {})
data_basedir = context.get("directories", {}).get("datadir", "/srv/plone")
default_base_port = context.get("base_port", 8080)
default_listen_addr = context.get("listen_addr", "127.0.5.1")
deployments = context["deployments"]
limit_to = pillar("limit_to", list(deployments.keys()))
user = context["users"]["process"]
director = context.get("director", {})


def reqs():
    sysreq = Test("system requirements")

    Test.nop(
        "system requirements",
        require=[Test("repo deployed")] if pillar("build:repo:client", "") else [],
    )

    Pkg.installed(
        "plone-deps",
        pkgs=["podman"],
        require_in=[sysreq],
    )

    if not template():
        File.managed(
            "/usr/local/bin/reset-plone-instance",
            source="salt://" + sls.replace(".", "/") + "/reset-plone-instance",
            mode="0755",
            require_in=[sysreq],
            template="jinja",
            context={"data_basedir": quote(data_basedir)},
        )

    for name, user, home in [
        (
            "process",
            context["users"]["process"],
            join("/var/lib", context["users"]["process"]),
        )
    ]:
        with Group.present(
            "%(name)s user %(user)s" % locals(),
            name=user,
        ):
            Podman.allocate_subgid_range(
                "%(user)s subgid" % locals(),
                name=user,
                howmany=1000,
                require_in=[sysreq],
            )
            with User.present(
                "%(name)s user %(user)s" % locals(),
                name=user,
                gid=user,
                home=home
                if not salt.user.info(user)
                else None,  # Don't set home if already exists.
            ):
                Podman.allocate_subuid_range(
                    "%(user)s subuid" % locals(),
                    name=user,
                    howmany=1000,
                    require_in=[sysreq],
                )

    File.directory(
        data_basedir,
        user=user,
        group=user,
        require=[User("process user %s" % user)],
        require_in=[sysreq],
    )

    Qubes.bind_dirs(
        "plone-container",
        directories=[data_basedir],
        require_in=[sysreq],
        require=[File(data_basedir)],
    )

    return sysreq


sysreq = reqs()


def delete(n, data):
    datadir = join(data_basedir, n)
    lbn = f"remove deployment {n} from load balancer"
    lbnn = Cmd.run(
        lbn,
        name="/usr/local/bin/varnish-set-backend --delete %s" % quote(n),
        stateful=True,
        require=[File("/usr/local/bin/varnish-set-backend")],
    ).requisite
    for color in "blue green".split():
        nc = f"plone-{n}-{color}"
        with Podman.absent(
            f"remove {nc}",
            name=nc,
            require=[lbnn],
        ):
            File.absent(f"{datadir}-{color}")


def copy_over(source, destination, **kwargs):
    return Cmd.run(
        f"copy over {source} to {destination}",
        name="""set -e
context=$(ls -Zd %(destination)s/filestorage | cut -f 1 -d ' ' || true)
rsync -a --delete --inplace %(source)s/filestorage/ %(destination)s/filestorage/
rm -rf %(destination)s/blobstorage
cp -a --reflink=auto %(source)s/blobstorage %(destination)s/blobstorage
if [ "$context" != "" ] ; then
    chcon -R "$context" %(destination)s/blobstorage %(destination)s/filestorage
fi
        """
        % {
            "source": quote(source),
            "destination": quote(destination),
        },
        **kwargs,
    )


def failover(n, deployment_address, director, **kwargs):
    kwargs["require"] = kwargs.get("require", []) + [
        File("/usr/local/bin/varnish-set-backend")
    ]
    return Cmd.run(
        f"fail over {n} to {deployment_address}",
        name="/usr/local/bin/varnish-set-backend %s %s %s"
        % (
            quote(n),
            quote(deployment_address),
            quote(json.dumps(director)),
        ),
        stateful=True,
        **kwargs,
    )


def deploy(i, n, data):
    datadir = join(data_basedir, n)
    listen_addr = data.get("listen_addr", default_listen_addr)
    base_port = data.get("base_port", default_base_port)
    port = base_port + (i * 2)
    deployment_address_green = "%s:%d" % (listen_addr, port)
    deployment_address_blue = "%s:%d" % (listen_addr, port + 1)
    green_datadir = datadir + "-green"
    blue_datadir = datadir + "-blue"
    options = [
        {"tls-verify": "false"},
        {"subgidname": user},
        {"subuidname": user},
    ]
    options_blue = options + [
        {"p": deployment_address_blue + ":8080"},
        {"v": join(blue_datadir, "filestorage") + ":/data/filestorage:rw,Z,shared,U"},
        {"v": join(blue_datadir, "blobstorage") + ":/data/blobstorage:rw,Z,shared,U"},
    ]
    options_green = options + [
        {"p": deployment_address_green + ":8080"},
        {"v": join(green_datadir, "filestorage") + ":/data/filestorage:rw,Z,shared,U"},
        {"v": join(green_datadir, "blobstorage") + ":/data/blobstorage:rw,Z,shared,U"},
    ]

    nc_blue = f"plone-{n}-blue"
    nc_green = f"plone-{n}-green"

    if salt.file.directory_exists(green_datadir):

        check_green = Podman.present(
            f"check {nc_green}",
            name=nc_green,
            image=deployment_data["image"],
            dryrun=True,
            options=options_green,
            require=[sysreq],
        ).requisite
        blue_dead = Podman.dead(
            f"stop {nc_blue}",
            name=nc_blue,
            onchanges=[check_green],
        ).requisite
        co = [
            copy_over(
                green_datadir,
                blue_datadir,
                require=[blue_dead],
                onchanges=[check_green],
            ).requisite
        ]

    elif "based_on" in data:

        basedon = data["based_on"]
        basedon_datadir = join(data_basedir, basedon + "-green")
        based_on_green = f"plone-{basedon}-green"
        File.directory(
            f"{blue_datadir}",
            user=user,
            mode="0755",
            require=[sysreq],
            unless="test -d %s" % quote(blue_datadir),
        )
        co = [
            copy_over(
                basedon_datadir,
                blue_datadir,
                require=[Podman(f"start {based_on_green}")],
            ).requisite,
            File(f"{blue_datadir}"),
        ]

    else:

        co = []
        with File.directory(
            f"{blue_datadir}",
            user=user,
            mode="0755",
            require=[sysreq],
            unless="test -d %s" % quote(blue_datadir),
        ):
            for x in ["/filestorage", "/blobstorage"]:
                File.directory(
                    f"{blue_datadir}{x}",
                    user=user,
                    mode="0755",
                    unless="test -d %s" % quote(blue_datadir + x),
                )
            co.append(File(f"{blue_datadir}{x}"))

    blue_started = Podman.present(
        f"start {nc_blue}",
        name=nc_blue,
        image=deployment_data["image"],
        options=options_blue,
        onchanges=co,
    ).requisite
    failover_to_blue = failover(
        n,
        deployment_address_blue,
        director=director,
        onchanges=[blue_started],
    ).requisite

    # We have failed over to blue.

    green_dead = Podman.dead(
        f"stop {nc_green}",
        name=nc_green,
        require=[failover_to_blue],
        onchanges=[blue_started],
    ).requisite

    green_datadir_present = File.directory(
        green_datadir,
        user=user,
        mode="0755",
        unless="test -d %s" % quote(green_datadir),
        require=[green_dead],
    ).requisite

    co = [
        copy_over(
            blue_datadir, green_datadir, onchanges=[green_datadir_present, green_dead]
        ).requisite
    ]

    green_started = Podman.present(
        f"start {nc_green}",
        name=nc_green,
        image=deployment_data["image"],
        enable=True,
        options=options_green,
        require=co,
    ).requisite

    failover_to_green = failover(
        n,
        deployment_address_green,
        director=director,
        require=[green_started],
    ).requisite

    # We have failed over to green.

    Podman.dead(f"stop {nc_blue} again", name=nc_blue, require=[failover_to_green])


# FIXME FOR QUBES SUPPORT
# Something here must say "if not template()" and use that to decide
# whether to run the deploy or not (we assume the template is not where
# we want that thing).  This also probably means we need to figure out a
# way to enable the container services under the Qubes AppVM that does not
# involve going all the way back to the template to configure the services.
# Also need to bind_dirs the directories where the container data is stored,
# otherwise the containers will have serious trouble restarting after reboot.
for i, (deployment_name, deployment_data) in enumerate(deployments.items()):
    if deployment_name not in limit_to:
        continue

    if deployment_data.get("delete"):
        delete(deployment_name, deployment_data)
    else:
        deploy(i, deployment_name, deployment_data)


"""
{#

test {{ deployment_name }}:
{%     if deployment_data.get("unit_test_name") %}
  cmd.run:
  - name: |
      set -e
      cd {{ salt.text.quote(deployment_target_dir) }}
      bin/test -m {{ salt.text.quote(deployment_data.unit_test_name) }}
  - runas: {{ context.users.deployer }}
  - onchanges:
    - cmd: buildout {{ deployment_name }}
{%     else %}
  cmd.wait:
  - name: echo Nothing to do.  This deployment has no unit test.
{%     endif %}
  - require:
    - cmd: buildout {{ deployment_name }}
  - require_in:
    - file: clear rebuild flag for {{ deployment_name }}

{%     if deployment_data.get("upgrade", []) %}


upgrade {{ upgrade.site }} for {{ deployment_name }}:
  cmd.run:
  - name: |
      set -e
      cd {{ salt.text.quote(deployment_target_dir) }}
      bin/{{ salt.text.quote(deployment_data.frontend_script) }} upgrade {{ salt.text.quote(upgrade.site) }} {% for p in upgrade.products %} {{ salt.text.quote(p) }}{% endfor %}
  - runas: {{ context.users.deployer }}
  - onchanges:
    - cmd: buildout {{ deployment_name }}
  - require:
    - cmd: start {{ deployment_name }} database for upgrade
  - require_in:
    - file: clear rebuild flag for {{ deployment_name }}
    - service: plone4-database@{{ deployment_name }}

{%       endfor %}

{%     endif %}

cook JS for site {{ upgrade.site }} in {{ deployment_name }}:
  http.wait_for_successful_query:
  - name: {{ ("http://" + deployment_data.zserver_address + "/" + upgrade.site ) | json }}
  - status: 200
  - request_interval: 5
  - wait_for: 30
  - onchanges:
    - service: plone4-frontend@{{ deployment_name }}
  - require_in:
    - file: clear rebuild flag for {{ deployment_name }}

{%       endfor %}

{%     endif %}

{%   endif %}


{% endfor %}

#}
"""
