#!objects

from salt://lib/defs.sls import SystemUserContainer


username = "collabora"
id_ = username

SystemUserContainer(
    id_,
    username,
    image="registry.hub.docker.com/collabora/code",
    version=pillar('collabora:version'),
    environment_template="extra_params=--o:ssl.enable=false --o:ssl.termination=true --o:net.service_root=/collabora",
)
