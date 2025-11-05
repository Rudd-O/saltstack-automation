#!objects

import os
import yaml
import salt.utils.dictupdate


class Perms(object):

    dir = {"mode": "0755"}
    file = {"mode": "0644"}
    owner_dir = {"mode": "0700"}
    owner_file = {"mode": "0600"}
    sudoers_file = {"mode": "0400"}

    def __init__(self, user, group=None):
        if not group:
            group = user
        self.dir = self.dir.copy() ; self.dir.update({"user": user, "group": group})
        self.file = self.file.copy() ; self.file.update({"user": user, "group": group})
        self.owner_dir = self.owner_dir.copy() ; self.owner_dir.update({"user": user, "group": group})
        self.owner_file = self.owner_file.copy() ; self.owner_file.update({"user": user, "group": group})


class Dotdict(dict):
    """dot.notation access to dictionary attributes"""

    def __getitem__(self, k):
        v = dict.__getitem__(self, k)
        if isinstance(v, dict) and not getattr(v, "_is_dotdict", False):
            self[k] = v
        elif isinstance(v, list):
            redo = False
            for n, elm in enumerate(v):
                if isinstance(elm, dict) and not getattr(v, "_is_dotdict", False):
                    redo = True
            if redo:
                self[k] = v
        v = dict.__getitem__(self, k)
        return v

    def __deepcopy__(self):
        return Dotdict(self.items())

    def __setitem__(self, k, v):
        if isinstance(v, dict) and not getattr(v, "_is_dotdict", False):
            v = Dotdict(v)
        if isinstance(v, list):
            new_ = []
            done = False
            for elm in v:
                if isinstance(elm, dict) and not getattr(v, "_is_dotdict", False):
                    elm = Dotdict(elm)
                    done = True
                new_.append(elm)
            if done:
                v = new_
        dict.__setitem__(self, k, v)

    def __getattribute__(self, attrname):
        if attrname == "_is_dotdict":
            return True
        elif attrname == "__getitem__":
            return lambda k: Dotdict.__getitem__(self, k)
        elif attrname == "__deepcopy__":
            return lambda k: Dotdict.__deepcopy__(self)
        elif attrname in dict.__dict__:
            return dict.__getattribute__(self, attrname)
        try:
            return self.__getitem__(attrname)
        except KeyError as e:
            raise AttributeError(str(e))

    def items(self):
        res = []
        for k, v in dict.items(self):
            if isinstance(v, dict) and not getattr(v, "_is_dotdict", False):
                v = Dotdict(v)
            res.append((k, v))
        return res

    __setattr__ = dict.__setitem__
    __delattr__ = dict.__delitem__


def as_plain_dict(d):
    if isinstance(d, dict) and getattr(d, "_is_dotdict", False):
        items = list(d.items())
        for n, x in enumerate(items):
            k, v = x
            v = as_plain_dict(v)
            items[n] = (k, v)
        return dict(items)
    if isinstance(d, list):
        new_ = []
        for n, v in enumerate(d):
            v = as_plain_dict(v)
            new_.append(v)
        return new_
    return d


def PillarConfigWithDefaults(pillar_key, defaults, merge_lists=False):
    user = __salt__["pillar.get"](pillar_key, {})
    config = salt.utils.dictupdate.merge(defaults, user, strategy="smart", renderer="yaml", merge_lists=merge_lists)
    return Dotdict(config)


def ShowConfig(pillar_config):
    pillar_config = as_plain_dict(pillar_config)
    return Test.nop("Configuration is:\n%s" % yaml.dump(pillar_config))


def SystemUser(id_, shell=None, **kwargs):
    with Group.present(
        f"{id_} system group",
        name=id_,
        system=True,
    ):
        u = User.present(
            f"{id_} system user",
            system=True,
            name=id_,
            gid=id_,
            createhome=True,
            shell=shell if shell else "/usr/sbin/nologin",
            home=f"/var/lib/{id_}",
            **kwargs,
        ).requisite
    return u


def SystemUserForContainers(id_, shell=None, **kwargs):
    u = SystemUser(id_, shell=shell, **kwargs)

    contexts_needed = Cmd.run(
        f"Verify container contexts need to be created for {id_}",
        name="semanage fcontext -l | grep -q ^/var/lib.*local/share/containers/storage && echo changed=no || echo changed=yes",
        stateful=True,
    ).requisite

    contexts_present = []
    for n, (path_re, setype) in enumerate([
        ('/var/lib/[^/]/[^/]+/\\.local/share/containers/storage/artifacts(/.*)?', 'container_ro_file_t'),
        ('/var/lib/[^/]/[^/]+/\\.local/share/containers/storage/overlay(/.*)?', 'container_ro_file_t') ,
        ('/var/lib/[^/]/[^/]+/\\.local/share/containers/storage/overlay-images(/.*)?', 'container_ro_file_t'),
        ('/var/lib/[^/]/[^/]+/\\.local/share/containers/storage/overlay-layers(/.*)?', 'container_ro_file_t'),
        ('/var/lib/[^/]/[^/]+/\\.local/share/containers/storage/overlay2(/.*)?', 'container_ro_file_t'),
        ('/var/lib/[^/]/[^/]+/\\.local/share/containers/storage/overlay2-images(/.*)?', 'container_ro_file_t'),
        ('/var/lib/[^/]/[^/]+/\\.local/share/containers/storage/overlay2-layers(/.*)?', 'container_ro_file_t'),
        ('/var/lib/[^/]/[^/]+/\\.local/share/containers/storage/volumes/[^/]*/.*', 'container_file_t'),
    ]):
        contexts_present.append(
            Selinux.fcontext_policy_present(
                f"Set up SELinux contexts for containers of {id_} at {n}",
                name=path_re,
                filetype="a",
                sel_user="system_u",
                sel_type=setype,
                onchanges=[contexts_needed],
            ).requisite
        )

    localsharecontainers = File.directory(
        f"/var/lib/{id_}/.local/share/containers",
        user=id_,
        group=id_,
        mode="0700",
        makedirs=True,
        require=[u] + contexts_present,
    ).requisite

    containerbind = Qubes.bind_dirs(
        f'{id_}-containers',
        directories=[f'/var/lib/{id_}/.local/share/containers'],
        require=[localsharecontainers],
    ).requisite

    context_applied = Selinux.fcontext_policy_applied(
        f"Apply SELinux contexts for containers of {id_}",
        name=f"/var/lib/{id_}/.local/share/containers",
        recursive=True,
        onchanges=contexts_present + [contexts_needed] + [localsharecontainers, containerbind],
    ).requisite

    subgid = Podman.allocate_subgid_range(
        f"{id_} subgid",
        name=id_,
        howmany="1000000",
        require=[u],
    ).requisite

    subuid = Podman.allocate_subuid_range(
        f"{id_} subuid",
        name=id_,
        howmany="1000000",
        require=[u],
    ).requisite

    return [u, localsharecontainers, containerbind, context_applied, subgid, subuid]


# Deprecate me with the state SshKeypair.present.
def SSHKeyForUser(id_, key, key_name="id_rsa", key_path=".ssh", **kwargs):
    if key_path.startswith(os.path.pathsep):
        pass
    else:
        key_path = f"~{id_}/{key_path}/{key_name}"
    return File.managed(
        f"SSH key {key_path} for user {id_}",
        name=key_path,
        user=id_,
        group=id_,
        mode="0600",
        contents=key,
        makedirs=True,
        dirmode="0700",
        **kwargs,
    ).requisite


def SSHAccessToUser(id_, authorized_keys, **kwargs):
    # FIXME redeploy me everywhere I am used.
    opts = [
        "no-agent-forwarding",
        "no-port-forwarding",
        "no-X11-forwarding",
        "no-pty",
        "restrict",
    ]
    if "options" in kwargs:
        for opt in kwargs["options"]:
            if opt not in opts:
                opts.append(opt)
        del kwargs["options"]
    return SshAuth.manage(
        f"access to {id_}",
        user=id_,
        options=opts,
        ssh_keys=authorized_keys,
        **kwargs,
    ).requisite


# FIXME this usually should add both the FQDN and the IP address key for the host keys
# so it should be a double loop, simplifying the callers.
# FIXME: also port to a module instead of a string of tasks.
def KnownHostForUser(id_, host, known_host_keys, **kwargs):
    try:
        host = host.split("@")[-1].split(":")[0]
    except Exception:
        assert 0, host
    before_n = f"Before keys for host {host} in user {id_}"
    after_n = f"After keys for host {host} in user {id_}"
    before = Test.nop(before_n)
    after = Test.nop(after_n)
    with Test(before_n, "require"):
        with Test(after_n, "watch_in"):
            for known_host_key in known_host_keys:
                key_enc = known_host_key.split()[0]
                key = known_host_key.split(" ", 2)[1]
                SshKnownHosts.present(
                    f"{key_enc} key for host {host} in user {id_}",
                    name=host,
                    user=id_,
                    enc=key_enc,
                    key=key,
                    **kwargs,
                )
    return before.requisite, after.requisite


def ReloadSystemdOnchanges(sls_name):
    # Returns the requisite directly.
    return Cmd.run(
        f"Reload systemd for changes made in {sls_name}",
        name="systemctl --system daemon-reload",
        onchanges=[Test.nop(f"Noop for systemctl --system daemon-reload for {sls_name}").requisite],
    ).requisite


def SystemdSystemDropin(service_name, dropin_name, contents, require=None, watch_in=None, onchanges_in=None):
    if not any(service_name.endswith("." + x) for x in "service socket device mount automount swap target path timer slice scope".split()):
        service_name = service_name + ".service"
    fn = f"/etc/systemd/system/{service_name}.d/{dropin_name}.conf"
    reloadsystemd = ReloadSystemdOnchanges(fn)
    kws = {}
    if watch_in:
        kws["watch_in"] = watch_in
    if require:
        kws["require"] = require
    if onchanges_in:
        kws["onchanges_in"] = [reloadsystemd] + onchanges_in
    else:
        kws["onchanges_in"] = [reloadsystemd]
    file_ = File.managed(
        fn,
        contents=contents,
        mode="0644",
        makedirs=True,
        **kws,
    ).requisite
    return (file_, reloadsystemd)
