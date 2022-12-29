# Qubes OS `bombshell-client` adapters for SaltStack

If you are using vanilla SaltStack rather than the Qubes OS host-centric one, these adapters allow you to connect to and manage VMs using `salt-ssh`.

To use them:

1. Ensure `bombshell-client` is available in your `$PATH`.  [That program is available here](https://github.com/Rudd-O/ansible-qubes/tree/master/bin).
2. Add the folder containing this file to your `$PATH` environment variable, *first*.  The `ssh` and `scp` programs are shims which should be invoked via `salt-ssh`.
3. Export variable `SALT_SSH_ROSTER` to point to your Salt roster file.
4. In your roster file, to describe a Qubes OS VM you want to manage (in the same Qubes OS system where you are running `salt-ssh`), do it as follows:

```
# Host entry for a machine in your dom0.
my-vm:                   # MANDATORY: name of machine in roster entry.
  connection_type: qubes # MANDATORY: this signals the adapter to connect via `bombshell-client`.
  vm_name: my-vm         # MANDATORY: this indicates to the shim what VM name to use.
  # everything below here is optional
  dom0: dom0
  vm_class: AppVM
  vm_provides-network: true
  vm_netvm: null
  vm_label: green
  vm_template: fedora-user-tpl
  vm_autostart: yes
  vm_qrexec_timeout: 600
  vm_shutdown_timeout: 600
  vm_virt_mode: hvm
  vm_memory: 500
  vm_maxmem: 0  # Disable memory balancing.
  vm_pcidevs:
  - '00:1f.6'
  nodegroups:
  - homenetwork:zips
  - homenetwork:lanc
  - homenetwork:firewall
  - prometheus:prometheus-qubes-proxy
```

You can also access remote instances (in another dom0) much like Ansible Qubes permits you to do, provided that:

* a VM (the "management VM") in the remote system is accessible via SSH (as `user`),
* that VM has `bombshell-client` installed, and
* dom0 Qubes-RPC policies have been configured to allow that VM to execute the `qubes.VMSHell` RPC in other VMs of the system.

For example, if your remote management VM has IP 1.2.3.4 and is properly configured to let you SSH as `user` to it, here is what you would put in your roster to access *another* VM on the system (in the example, named `nginxproxy`):

```
nginxproxy.remotequbes:   # MANDATORY: name of machine in roster entry.
  connection_type: qubes  # MANDATORY: signals the shim to become active.
  vm_name: nginxproxy     # MANDATORY: this is the remote VM name.
  proxy: 1.2.3.4          # MANDATORY: signals the shim to first SSH to 1.2.3.4 before running `bombshell-client`
  # everything below here is optional
  dom0: dom0.remotequbes
```
