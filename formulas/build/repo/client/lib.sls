#!objects


def rpm():
    include("build.repo.client.rpm")
    return Test("RPM repo deployed")


def docker():
    include("build.repo.client.docker")
    return Test("Docker repo deployed")
