from __future__ import print_function

import pipes
from six import string_types


def quote(s):
    return pipes.quote(s)


def escape_regex(l):
    if isinstance(l, string_types):
        n = []
        specials = [
            '/', '.', '*', '+', '?', '|',
            '(', ')', '[', ']', '{', '}', '\\'
        ]
        for char in l:
            if char in specials:
                char = '\\' + char
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
