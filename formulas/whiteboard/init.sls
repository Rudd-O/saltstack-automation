#!objects

from salt://lib/defs.sls import SystemUserContainer


username = "whiteboard"
id_ = username

ctx = dict(
    domain=pillar("whiteboard:domain"),
    jwt=pillar("whiteboard:jwt_secret_key"),
    payload_size_mb=pillar("whiteboard:payload_size_mb", 50),
)

SystemUserContainer(
    id_,
    username,
    image="ghcr.io/nextcloud-releases/whiteboard",
    version=pillar("whiteboard:version", "release"),
    environment_template="""NEXTCLOUD_URL=https://{{domain}}
MAX_UPLOAD_FILE_SIZE={{payload_size_mb}}
JWT_SECRET_KEY={{jwt}}""",
    environment_context=ctx,
    args=["--logs-dir=/tmp", "--verbose"],
)
