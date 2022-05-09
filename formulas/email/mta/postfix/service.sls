#!objects

include(".".join(sls.split(".")[:-1]) + ".package")

Service.running("postfix", enable=True, require=[Pkg("postfix-pkg")])
