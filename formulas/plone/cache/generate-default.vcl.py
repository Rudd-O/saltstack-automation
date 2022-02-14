#!/usr/bin/python3

import json
import os
import subprocess


os.chdir("/etc/varnish")

pairs = []
for file in subprocess.check_output(["find", ".", "-name", "*.vcl"], text=True).splitlines():
    if not file or file =="./default.vcl":
        continue
    pairs.append((os.path.basename(file), file[2:]))

pairs.sort()

text = "\n".join("include \"%s\";" % file for _, file in pairs)
text = "vcl 4.1;\n\n" + text

try:
    with open("default.vcl", "r") as existing_f:
        existing = existing_f.read()
except FileNotFoundError:
    existing = None


if text != existing:
    with open("default.vcl", "w") as existing_f:
        existing_f.write(text)

    out = json.dumps(
        {
            "changed": True,
            "comment": "New default.vcl written.",
        }
    )
    print(out)
