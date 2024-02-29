def services_restarted(name, exclude_services_globs=None, exclude_paths=None):
    exclude_services_globs = exclude_services_globs or []
    exclude_paths = exclude_paths or []

    test = __opts__["test"]
    ret = dict(name=name, result=False, changes={}, comment="")
    r = __salt__["maint.restart_services"](
        test=test,
        exclude_services_globs=exclude_services_globs,
        exclude_paths=exclude_paths,
    )
    kernel = __salt__["maint.get_kernel_reboot_required"]()
    xen = __salt__["maint.get_xen_reboot_required"]()
    comment = ["needs-restart report:\n" + r["report"]]
    if r["failed"]:
        comment.append(
            "Failed services:\n%s"
            % "\n".join(["- %s: %s" % (k, v) for k, v in r["failed"].items()])
        )
    else:
        ret["result"] = True
    if r["restarted"]:
        ret["changes"] = {"restarted": r["restarted"]}
        if test:
            ret["result"] = None
        comment.append(
            "Restarted services:\n%s" % "\n".join(["- %s" % k for k in r["restarted"]])
        )
    if "nonrestartable" in r and r["nonrestartable"]:
        comment.append(
            "Nonrestartable services:\n%s"
            % "\n".join(["- %s" % k for k in r["nonrestartable"]])
        )
    if kernel:
        comment.append(kernel)
    if xen:
        comment.append(xen)
    ret["comment"] = "\n\n".join(comment) if comment else None
    return ret
