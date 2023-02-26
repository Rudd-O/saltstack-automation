#!objects


def rpm_repo():
    include("build.repo.client.rpm")
    return Test("RPM repo deployed")


def docker_repo():
    include("build.repo.client.docker")
    return Test("Docker repo deployed")
