from __future__ import print_function


import collections

try:
    from shlex import quote as mquote
except ImportError:
    from pipes import quote as mquote
from six import string_types


def quote(s):
    if isinstance(s, dict) or isinstance(s, collections.OrderedDict):
        lst = [(x, mquote(y)) for x, y in s.items()]
        return s.__class__(lst)
    if isinstance(s, list) or isinstance(s, tuple):
        lst = [mquote(y) for y in s]
        return lst
    return mquote(s)


def list_to_dict(s):
    return dict([(x, x) for x in s])


def escape_regex(l):
    if isinstance(l, string_types):
        n = []
        specials = ["/", ".", "*", "+", "?", "|", "(", ")", "[", "]", "{", "}", "\\"]
        for char in l:
            if char in specials:
                char = "\\" + char
            n.append(char)
        return "".join(n)
    return "|".join(escape_regex(x) for x in l)


def escape_regex_anchored(l):
    if isinstance(l, string_types):
        return "^" + escape_regex(l) + "$"
    return "^(" + escape_regex(l) + ")$"


def escape_regex_unanchored(l):
    if isinstance(l, string_types):
        return ".*" + escape_regex(l) + ".*"
    return ".*(" + escape_regex(l) + ").*"


def without(first, second):
    return [f for f in first if f not in second]


if __name__ == "__main__":
    print(escape_regex("dom0"))
    print(escape_regex_anchored("dom0"))
    print(escape_regex_anchored(["dom0", "dom0.castle"]))
