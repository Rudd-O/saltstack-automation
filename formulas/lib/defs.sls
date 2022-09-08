#!objects

import os
import yaml


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
        if isinstance(v, dict) and not isinstance(v, Dotdict):
            self[k] = v
        elif isinstance(v, list):
            redo = False
            for n, elm in enumerate(v):
                if isinstance(elm, dict) and not isinstance(elm, Dotdict):
                    redo = True
            if redo:
                self[k] = v
        v = dict.__getitem__(self, k)
        return v

    def __deepcopy__(self):
        return Dotdict(self.items())

    def __setitem__(self, k, v):
        if isinstance(v, dict) and not isinstance(v, Dotdict):
            v = Dotdict(v)
        if isinstance(v, list):
            new_ = []
            done = False
            for elm in v:
                if isinstance(elm, dict) and not isinstance(v, Dotdict):
                    elm = Dotdict(elm)
                    done = True
                new_.append(elm)
            if done:
                v = new_
        dict.__setitem__(self, k, v)

    def __getattribute__(self, attrname):
        if attrname == "__getitem__":
            return lambda k: Dotdict.__getitem__(self, k)
        elif attrname == "__deepcopy__":
            return lambda k: Dotdict.__deepcopy__(self)
        elif attrname in dict.__dict__:
            return dict.__getattribute__(self, attrname)
        try:
            return self.__getitem__(attrname)
        except KeyError as e:
            raise AttributeError(str(e))

    __setattr__ = dict.__setitem__
    __delattr__ = dict.__delitem__


def as_plain_dict(d):
    if isinstance(d, Dotdict):
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
    config = __salt__["slsutil.merge"](defaults, user, merge_lists=merge_lists)
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
            createhome=True,
            shell=shell if shell else "/usr/sbin/nologin",
            home=f"/var/lib/{id_}",
            **kwargs,
        ).requisite
    return u


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
    return SshAuth.present(
        f"access to {id_}",
        user=id_,
        options=["no-agent-forwarding", "no-port-forwarding"],
        names=authorized_keys,
        **kwargs,
    ).requisite


def KnownHostForUser(id_, host, known_host_keys, **kwargs):
    host = host.split("@")[-1].split(":")[0]
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
                    **kwargs,
                )
    return before.requisite, after.requisite

