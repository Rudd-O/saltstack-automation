#!objects

from salt://email/config.sls import config


context = config["mda"]
slsp = sls.replace(".", "/")


done = [Test.nop("sieve tooling deployed").requisite]

Pkg.installed(
    "dovecot-pigeonhole",
    pkgs=["bogofilter", "dovecot-pigeonhole"],
)

with File.directory(
    "/usr/local/libexec/sieve",
    mode="0755",
    require=[Pkg("dovecot-pigeonhole")],
):
    autoregister_incoming_mail = context["spam"]["train_spam_filter_with_incoming_mail"]
    File.managed(
        f"/usr/local/libexec/sieve/spamclassifier",
        source=f"salt://{slsp}/usr/local/libexec/sieve/spamclassifier",
        mode="0755",
        template="jinja",
        context={
            "autoregister_incoming_mail": autoregister_incoming_mail,
        },
        require_in=done,
    )

    for item in ["spam", "ham"]:
        File.managed(
            f"/usr/local/libexec/sieve/learn-{item}",
            source=f"salt://{slsp}/usr/local/libexec/sieve/learn",
            mode="0755",
            template="jinja",
            context={
                "item": item,
            },
            require_in=done,
        )

File.directory(
    "/var/lib/sieve dir",
    name="/var/lib/sieve",
    mode="0755",
    selinux=dict(setype="dovecot_etc_t", seuser="system_u"),
    require=[Pkg("dovecot-pigeonhole")],
)

subdirs = [m for m in "/before.d /after.d /global /imapsieve".split()] 
for m in subdirs:
    File.directory(
        f"/var/lib/sieve{m} subdir",
        name=f"/var/lib/sieve{m}",
        mode="0755",
        selinux=dict(setype="dovecot_etc_t", seuser="system_u"),
        require=[File("/var/lib/sieve dir")],
    )

Test.nop(
    "sieve content folders created",
    require=[File(f"/var/lib/sieve{m} subdir") for m in subdirs],
)

File.recurse(
    "deploy /var/lib/sieve content",
    name="/var/lib/sieve",
    source=f"salt://{slsp}/var/lib/sieve",
    template="jinja",
    context={"spam": context["spam"]},
    file_mode="0644",
    selinux=dict(setype="dovecot_etc_t", seuser="system_u"),
    require=[Test("sieve content folders created")],
)

Cmd.run(
    "symlink sieve plugins",
    name="""
set -ex
changed=no
cd /usr/lib64/dovecot/sieve
for plugin in *.so ; do
  test -f "../$plugin" && continue || true
  ln -s "sieve/$plugin" ../"$plugin"
  changed=yes
done
echo
echo changed=$changed
""",
    stateful=True,
    require=[Pkg("dovecot-pigeonhole")],
)

Cmd.run(
    "compile dovecot global scripts",
    name="""
set -e

changed=no
for item in before.d after.d global imapsieve ; do
  cd /var/lib/sieve/$item
  for script in *.sieve ; do
    if ! test -f "$script" ; then continue ; fi
    compiled=$(echo "$script" | sed 's/.sieve$/.svbin/')
    agescript=`stat -c "%Y" "$script"`
    agecompiled=`stat -c "%Y" "$compiled" || echo 0`
    if [ "$agescript" -gt "$agecompiled" ] ; then
        sievec -x '+vnd.dovecot.pipe +vnd.dovecot.execute +vnd.dovecot.filter' "$script"
        chcon -u system_u -t dovecot_etc_t "$compiled"
        changed=yes
    fi
  done
  for compiled in *.svbin ; do
    if ! test -f "$compiled" ; then continue ; fi
    if ! test -f $(echo "$compiled" | sed 's/.svbin$/.sieve/') ; then
      rm -f "$compiled"
      changed=yes
    fi
  done
done

echo
echo changed=$changed
""",
    stateful=True,
    require=[File("deploy /var/lib/sieve content"), Cmd("symlink sieve plugins")],
    require_in=done,
)
