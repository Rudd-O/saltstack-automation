#!pyobjects


class Perms(object):

    dir = {"mode": "0755"}
    file = {"mode": "0644"}
    owner_dir = {"mode": "0700"}
    owner_file = {"mode": "0600"}

    def __init__(self, user, group=None):
        if not group:
            group = user
        self.dir = self.dir.copy() ; self.dir.update({"user": user, "group": group})
        self.file = self.file.copy() ; self.file.update({"user": user, "group": group})
        self.owner_dir = self.owner_dir.copy() ; self.owner_dir.update({"user": user, "group": group})
        self.owner_file = self.owner_file.copy() ; self.owner_file.update({"user": user, "group": group})
