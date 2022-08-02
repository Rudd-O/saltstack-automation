#!objects

from salt://prometheus/exporter/node_exporter/collectors/lib.sls import collector


collector(sls.split(".")[-1])
