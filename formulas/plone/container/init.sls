#!objects

import json

from os.path import join
from shlex import quote
from pprint import pformat

from salt://lib/qubes.sls import template
from salt://build/repo/client/lib.sls import docker_repo


include("plone.content_cache.set_backend")

context = pillar(sls.replace(".", ":"), {})
data_basedir = context.get("directories", {}).get("datadir", "/srv/plone")
default_image = "docker.io/plone/plone-backend:6.0.0b2"
default_zeo_image = "docker.io/plone/plone-zeo:5.3.0"
default_base_port = context.get("base_port", 8080)
default_green_listen_addr_prefix = context.get("green_listen_addr_prefix", "127.0.6.")
default_blue_listen_addr_prefix = context.get("blue_listen_addr_prefix", "127.0.6.")
deployments = context["deployments"]
limit_to = pillar("limit_to", list(deployments.keys()))
user = context["users"]["process"]
director = context.get("director", [])
default_backend_processes = context.get("backend_processes", 2)


def reqs():
    sysreq = Test("system requirements")

    Test.nop(
        "system requirements",
        require=[docker_repo()] if pillar("build:repo:client", "") else [],
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
                howmany=65536,
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
                    howmany=65536,
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


def copy_over(source, destination, **kwargs):
    return Cmd.run(
        f"copy over {source} to {destination}",
        name="""set -e
context=$(ls -Zd %(destination)s/filestorage | cut -f 1 -d ' ' || true)
mkdir -p %(destination)s
rsync -a --delete --inplace %(source)s/filestorage/ %(destination)s/filestorage/
rm -rf %(destination)s/blobstorage
cp -a --reflink=auto %(source)s/blobstorage %(destination)s/blobstorage
chown -R root:root %(destination)s
chmod 755 %(destination)s %(destination)s/blobstorage %(destination)s/filestorage
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


def failover(n, deployment_addresses, director, **kwargs):
    kwargs["require"] = kwargs.get("require", []) + [
        File("/usr/local/bin/varnish-set-backend")
    ]
    return Cmd.run(
        f"fail over {n} to {','.join(deployment_addresses)}",
        name="/usr/local/bin/varnish-set-backend %s %s %s"
        % (
            quote(n),
            quote(json.dumps(deployment_addresses)),
            quote(json.dumps(director)),
        ),
        stateful=True,
        **kwargs,
    )


def delete(n, data, require=None):
    # Returns the requisite of the first task dispatched here.
    datadir = join(data_basedir, n)
    lbnn = Cmd.run(
        f"remove deployment {n} from load balancer",
        name="/usr/local/bin/varnish-set-backend --delete %s" % quote(n),
        stateful=True,
        require=[File("/usr/local/bin/varnish-set-backend")] + (require or []),
    ).requisite
    for color in "blue green".split():
        nc = f"plone-{n}-{color}"
        with Podman.pod_absent(
            f"remove {nc}",
            name=nc,
            require=[lbnn],
        ):
            File.absent(f"{datadir}-{color}")
    return lbnn


def deploy(i, n, processes, data, require=None):
    # Returns the requisite of the last task dispatched here.
    datadir = join(data_basedir, n)
    blue_listen_addr_prefix = data.get("blue_listen_addr_prefix", default_blue_listen_addr_prefix)
    if not blue_listen_addr_prefix.endswith("."):
        blue_listen_addr_prefix += "."
    green_listen_addr_prefix = data.get("green_listen_addr_prefix", default_green_listen_addr_prefix)
    if not green_listen_addr_prefix.endswith("."):
        green_listen_addr_prefix += "."

    port = data.get("base_port", default_base_port)

    def make_containers(nc, datadir, listen_addr, procs):
        pod_options = [
            {"exit-policy": "stop"},
            {"subuidname": "plone"},
            {"subgidname": "plone"},
            {"infra-name": f"{nc}-infra"},
        ]
        containers = [
            [
                {"tls-verify": "false"},
                {"name": f"{nc}-zeo"},
                {"image": deployment_data.get("zeo_image", default_zeo_image)},
                {"stop-signal": "SIGTERM"},
                {"e": "ZEO_ADDRESS=localhost:8100"},
                {"e": "ZEO_SHARED_BLOB_DIR=true"},
                {"restart": "on-failure"},
                {"v": datadir + ":/data:rw,z,shared,U"},
                {"requires": f"{nc}-infra"},
            ]
        ]
        addresses = []
        for nn in range(procs):
            lp = port + nn
            containers.append(
                [
                    {"stop-timeout": "30"},
                    {"tls-verify": "false"},
                    {"name": f"{nc}-backend-{nn}"},
                    {"image": deployment_data.get("image", default_image)},
                    {"stop-signal": "SIGINT"},
                    {"e": "ZEO_ADDRESS=localhost:8100"},
                    {"e": "ZEO_SHARED_BLOB_DIR=true"},
                    {"e": f"LISTEN_PORT={lp}"},
                    {"v": join(datadir, "blobstorage") + ":/data/blobstorage:rw,z,shared,U"},
                    {"restart": "on-failure"},
                    {"health-cmd": f"wget -O/dev/null http://127.0.0.1:{lp}"},
                    {"health-interval": "15s"},
                    {"health-retries": "5"},
                    {"health-start-period": "60s"},
                    {"health-timeout": "5s"},
                ],
            )
            if nn == 0:
                # Allow the first container to initialize the ZODB.
                containers[-1].extend([
                    {"requires": f"{nc}-zeo"},
                ])
            else:
                # Make the next container wait until the last one is healthy.
                containers[-1].extend([
                    {"requires": f"{nc}-backend-{nn - 1}"},
                ])

            pod_options.append({"p": f"{listen_addr}:{lp}:{lp}"})
            addresses.append(f"{listen_addr}:{lp}")
        return pod_options, containers, addresses

    nc_blue = f"plone-{n}-blue"
    nc_green = f"plone-{n}-green"
    blue_datadir = datadir + "-blue"
    green_datadir = datadir + "-green"
    blue_listen_addr = data.get("blue_listen_addr", blue_listen_addr_prefix + str(i * 2 + 1))
    green_listen_addr = data.get("green_listen_addr", green_listen_addr_prefix + str(i * 2 + 2))

    green_pod_options, green_pod_containers, green_addresses = make_containers(nc_green, green_datadir, green_listen_addr, processes)
    blue_pod_options, blue_pod_containers, blue_addresses = make_containers(nc_blue, blue_datadir, blue_listen_addr, processes)
    # Keep the line above this comment in sync with the almost-identical line below.

    if salt.file.directory_exists(green_datadir):

        check_green = Podman.pod_running(
            f"check {nc_green}",
            name=nc_green,
            options=green_pod_options,
            containers=green_pod_containers,
            dryrun=True,
            require=(require or []),
        ).requisite
        blue_dead = Podman.pod_dead(
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
            require=(require or []),
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
            require=(require or []),
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

        # This will be initialized for the first time as blue.  We must reduce the
        # app container processes for the blue instance to 1, in order to afford
        # the correct initialization procedure for the database (the frontend is
        # what initializes the database, and concurrent initialization results in
        # conflict errors which abort startup).
        blue_pod_options, blue_pod_containers, blue_addresses = make_containers(nc_blue, blue_datadir, blue_listen_addr, 1)

    # TODO: pod_running should optionally wait until all health checks passed.
    # Basically podman pod inspect, then get names of containers, then
    # pause until all containers with health checks are in state healthy.

    blue_started = Podman.pod_running(
        f"start {nc_blue}",
        name=nc_blue,
        options=blue_pod_options,
        containers=blue_pod_containers,
        onchanges=co,
    ).requisite
    failover_to_blue = failover(
        n,
        blue_addresses,
        director=director,
        onchanges=[blue_started],
    ).requisite

    # We have failed over to blue.
    # FIXME: at this point we should only stop green once green has reached
    # zero connections (plus the connection used to determine this stat, if any.)
    # Tracking bug https://github.com/Pylons/waitress/issues/182

    green_dead = Podman.pod_dead(
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

    green_started = Podman.pod_running(
        f"start {nc_green}",
        name=nc_green,
        options=green_pod_options,
        containers=green_pod_containers,
        enable=True,
        require=co,
    ).requisite

    failover_to_green = failover(
        n,
        green_addresses,
        director=director,
        require=[green_started],
    ).requisite

    # We have failed over to green.
    # FIXME: at this point we should only stop blue once blue has reached
    # zero connections (plus the connection used to determine this stat, if any.)
    # Tracking bug https://github.com/Pylons/waitress/issues/182

    return Podman.pod_dead(f"stop {nc_blue} again", name=nc_blue, require=[failover_to_green]).requisite


# FIXME FOR QUBES SUPPORT
# Something here must say "if not template()" and use that to decide
# whether to run the deploy or not (we assume the template is not where
# we want that thing).  This also probably means we need to figure out a
# way to enable the container services under the Qubes AppVM that does not
# involve going all the way back to the template to configure the services.
# Also need to bind_dirs the directories where the container data is stored,
# otherwise the containers will have serious trouble restarting after reboot.

preflight = Test.nop("Preflight check complete", require=[sysreq]).requisite

try:
    first_deployment = list(deployments.keys())[0]
except IndexError:
    Test.fail_without_changes("No deployments defined in pillar plone:container.", require_in=[preflight])

unknown_deployments = [
    ent.get("deployment", first_deployment)
    for ent in director
    if (
        ent.get("deployment", first_deployment) not in deployments
        or deployments[ent.get("deployment", first_deployment)].get("delete")
    )
]
if unknown_deployments:
    Test.fail_without_changes(f"Deployments referenced in directors are unknown or deleted: {unknown_deployments}", require_in=[preflight])

deletions = []
creations = []

for i, (deployment_name, deployment_data) in enumerate(deployments.items()):
    if deployment_name not in limit_to:
        continue

    if deployment_data.get("delete"):
        deletions.append(delete(deployment_name, deployment_data, require=[preflight]))
    else:
        procs = deployment_data.get("backend_processes", default_backend_processes)
        creations.append(deploy(i, deployment_name, procs, deployment_data, require=[preflight]))

alldeployments = Test.nop(
    "All needed deployments complete",
    require=creations,
).requisite
Test.nop(
    "All needed deletions begun",
    require=[alldeployments],
    require_in=deletions,
)

"""
{#

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
