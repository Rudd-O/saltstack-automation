#!objects

import yaml


defaults = {
    "mta": {
        "hostname": grains("localhost"),
        "origin": "$myhostname",
        "mynetworks": ["127.0.0.0/8", "[::1]/128"],
        "greylisting": True,
        "message_size_limit": 50 * 1024 * 1024,
        "mailbox_size_limit": 10 * 1024 * 1024 * 1024,
        "recipient_delimiter": "+.",
        "smtp_tls_security_level": "may",
        "smtpd_tls_security_level": "may",
        "dkim": {
            "MinimumKeyBits": 2048,
        },
        "spf": {
            "HELO_reject": "Fail",
            "Mail_From_reject": "Fail",
            "PermError_reject": "False",
            "TempError_Defer": "False",
            "skip_addresses": "127.0.0.0/8,::ffff:127.0.0.0/104,::1".split(","),
        },
    },
    "mda": {
        "enable": None,  # Means MDA will only be enabled if recipients are listed.
        "mailbox_type": "maildir",
    },
}
p = pillar("email", {})
config = __salt__["slsutil.merge"](defaults, p)

assert config["mda"]["mailbox_type"] in ["maildir", "mbox"], "mailbox_type can be only one of maildir or mbox"
n, o = "smtpd_tls_security_level", ["none", "may", "encrypt", "dane", "dane-only", "fingerprint", "verify", "secure"]
assert config["mta"][n] in o, f"{n} can be only one of {o}"
n, o = "smtp_tls_security_level", ["none", "may", "encrypt"]
assert config["mta"][n] in o, f"{n} can be only one of {o}"

if "mailbox_command" not in config["mta"]:
    config["mta"]["mailbox_command"] = "/bin/true"
    if config["mda"]["enable"]:
        config["mta"]["mailbox_command"] = "/usr/libexec/dovecot/deliver"
    if config["mda"].get("recipients") and config["mda"]["enable"] is not False:
        config["mta"]["mailbox_command"] = "/usr/libexec/dovecot/deliver"

if config["mda"].get("recipients"):
    if "catchall_username" not in config["mda"]:
        config["mda"]["catchall_username"] = config["mda"]["recipients"][0]["user"]

if "destination_domains" not in config["mta"]:
    config["mta"]["destination_domains"] = ["$mydomain"]

for m in "HELO_reject Mail_From_reject PermError_reject TempError_Defer".split():
    if isinstance(config["mta"]["spf"][m], bool):
        config["mta"]["spf"][m] = str(config["mta"]["spf"][m])

Test.nop("Effective mail configuration for this host:\n\n" + yaml.safe_dump(config))
