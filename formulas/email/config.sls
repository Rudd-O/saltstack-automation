#!objects

import yaml

# FIXME:
# also make the checker check for DKIM records, SPF records, A records and all that good stuff
# that is a bitch to check otherwise.
# checker should run without pulling any code from other SLSes except config.
# then remove analogous text from test.yml in mailserver role in Ansible.

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
        "spam": {
            "file_spam_after_user_scripts": False,
            "train_spam_filter_with_incoming_mail": False,
        },
    },
}
p = pillar("email", {})
config = __salt__["slsutil.merge"](defaults, p)

assert config["mda"]["mailbox_type"] in [
    "maildir",
    "mbox",
], "mailbox_type can be only one of maildir or mbox"
n, o = "smtpd_tls_security_level", [
    "none",
    "may",
    "encrypt",
    "dane",
    "dane-only",
    "fingerprint",
    "verify",
    "secure",
]
assert config["mta"][n] in o, f"{n} can be only one of {o}"
n, o = "smtp_tls_security_level", ["none", "may", "encrypt"]
assert config["mta"][n] in o, f"{n} can be only one of {o}"

if "hostname" not in config["mda"]:
    config["mda"]["hostname"] = config["mta"]["hostname"]

if "mailbox_command" not in config["mta"]:
    config["mta"]["mailbox_command"] = "/bin/true"
    enable = False
    if config["mda"]["enable"]:
        enable = True
        config["mta"]["mailbox_command"] = "/usr/libexec/dovecot/deliver"
    if config["mda"].get("recipients") and config["mda"]["enable"] is not False:
        enable = True
        config["mta"]["mailbox_command"] = "/usr/libexec/dovecot/deliver"
    config["mda"]["enable"] = enable

if "destination_domains" not in config["mta"]:
    autodisco_domains = []
    for recipient in config["mda"].get("recipients", []):
        for address in recipient.get("addresses", []):
            splitted = address.split("@")
            if len(splitted) > 1:
                domain = splitted[-1].lower()
                if domain not in autodisco_domains:
                    autodisco_domains.append(domain)
    for alias in config["mda"].get("forwardings", []):
        splitted = alias["name"].split("@")
        if len(splitted) > 1:
            domain = splitted[-1].lower()
            if domain not in autodisco_domains:
                autodisco_domains.append(domain)
    if not autodisco_domains:
        autodisco_domains = ["$mydomain"]
    config["mta"]["destination_domains"] = autodisco_domains

for m in "HELO_reject Mail_From_reject PermError_reject TempError_Defer".split():
    if isinstance(config["mta"]["spf"][m], bool):
        config["mta"]["spf"][m] = str(config["mta"]["spf"][m])

Test.nop(
    "Effective mail configuration for this host:\n\n"
    + yaml.safe_dump(config, default_flow_style=False)
)
