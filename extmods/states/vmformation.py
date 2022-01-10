from __future__ import print_function

import collections
import copy
import json
import pprint
import subprocess
import yaml

try:
    from pipes import quote
except ImportError:
    from shlex import quote


class CustomDumper(yaml.SafeDumper):
    #Super neat hack to preserve the mapping key order. See https://stackoverflow.com/a/52621703/1497385
    def represent_dict_preserve_order(self, data):
        return self.represent_dict(sorted([x for x in data.items()], key=lambda z: str(z)))
    def represent_list_preserve_order(self, data):
        return self.represent_list(sorted([x for x in data], key=lambda z: str(z)))


CustomDumper.add_representer(dict, CustomDumper.represent_dict_preserve_order)
CustomDumper.add_representer(collections.OrderedDict, CustomDumper.represent_dict_preserve_order)
CustomDumper.add_representer(list, CustomDumper.represent_list_preserve_order)


def generated(name, vm_manifest, only=None):
    sls = collections.OrderedDict()
    for vm, data in sorted(vm_manifest.items()):
        if data['dom0'] != __grains__['id']:
            continue
        del data['dom0']
        key = 'qvm.present' if data.get("vm_managed_by_formation", True) else 'qvm.exists'
        vmid = "VM " + vm
        sls[vmid] = collections.OrderedDict({key: []}.items())
        vmdata = sls[vmid][key]
        require = []
        vmdata.append({"require": require})
        vm_class = None
        for k, v in data.items():
            if k.startswith("vm_"):
                k = k[3:]
            if k in ("managed_by_formation", "storage", "features", "services"):
                continue
            if k == "template":
                vmdata.append({k: vm_manifest[v]['vm_name']})
                require.append({"qvm": "VM " + v})
            elif k == "netvm" and v is not None:
                vmdata.append({k: vm_manifest[v]['vm_name']})
                require.append({"qvm": "VM " + v})
                if vm_manifest[v].get("vm_managed_by_formation", True):
                    require.append({"qvm": "VM " + v + " prefs"})
            else:
                if k in ["provides_network"]:
                    k.replace("_", "-")
                vmdata.append({k: v})
            if k == "class":
                vm_class = v
        if key == "qvm.present":
            prefsid = vmid + " prefs"
            sls[prefsid] = collections.OrderedDict()
            sls[prefsid]['qvm.prefs'] = copy.deepcopy(sls[vmid][key])

            # Now we delete `template` chunk from qvm-prefs in StandaloneVMs.
            # It is not valid as a Qubes SLS preference.
            if vm_class == "StandaloneVM":
                template_index = -1
                for n, chunk in enumerate(sls[prefsid]['qvm.prefs']):
                    for key, value in chunk.items():
                        if key == "template":
                            template_index = n
                            break
                if template_index != -1:
                     sls[prefsid]['qvm.prefs'].pop(template_index)
                
            requireparm = [x for x in sls[prefsid]['qvm.prefs'] if 'require' in x][0]
            requireparm['require'] = [{"qvm": vmid}]
            if "vm_storage" in data:
                for volume, size in data["vm_storage"].items():
                    storageid = vm + " volume " + volume
                    sls[storageid] = collections.OrderedDict()
                    sls[storageid]['qvol.set_size'] = [
                        {
                            "name": data['vm_name'],
                        },
                        {
                            "volume": volume,
                        },
                        {
                            "size": size,
                        },
                        {
                            "require": [
                                {"qvm": prefsid}
                            ]
                        }
                    ]
            if "vm_features" in data:
                featuresid = vmid + " features"
                sls[featuresid] = collections.OrderedDict()
                sls[featuresid]['qvm.features'] = [
                    {
                        "name": data['vm_name'],
                    },
                    {
                        "set": [{k: v} for k, v in data['vm_features'].items()]
                    },
                    {
                        "require": [
                            {"qvm": prefsid}
                        ]
                    }
                ]
            if "vm_services" in data and data['vm_services']:
                servicessid = vmid + " services"
                sls[servicessid] = collections.OrderedDict()
                sls[servicessid]['qvm.service'] = [
                    {
                        "name": data['vm_name'],
                    },
                    {
                        "require": [
                            {"qvm": prefsid}
                        ]
                    }
                ]
                to_enable = [k for k, v in data['vm_services'].items() if v]
                to_disable = [k for k, v in data['vm_services'].items() if not v]
                if to_enable:
                    sls[servicessid]['qvm.service'].append({'enable': to_enable})
                if to_disable:
                    sls[servicessid]['qvm.service'].append({'disable': to_disable})
    if only:
        keep = []
    else:
        keep = None
    while only:
        if not only[0].startswith("VM "):
            only[0] = "VM " + only[0]
        stateid = only[0]
        keep.append(stateid)
        if stateid + " prefs" in sls:
            keep.append(stateid + " prefs")
        if stateid + " volumes" in sls:
            keep.append(stateid + " volumes")
        if stateid + " features" in sls:
            keep.append(stateid + " features")
        if stateid + " services" in sls:
            keep.append(stateid + " services")
        reqlist = [
            reqlist
            for j, k in sls[stateid].items()
            for l in k
            for parm, reqlist in l.items()
            if parm == "require"
        ]
        required_vms = [
            reqid
            for requirements in reqlist
            for req in requirements
            for mod, reqid in req.items()
            if mod == "qvm"
        ]
        only = only[1:]
        only.extend(required_vms)
    if keep is not None:
        for slsid in list(sls.keys()):
            if slsid not in keep:
                del sls[slsid]
    contents = yaml.dump(sls, Dumper=CustomDumper)
    ret = __salt__['state.single'](
        fun='file.managed',
        name=name,
        contents=contents,
    )
    return list(ret.values())[0]


def applied(name):
    ret = {
        "name": name,
        "comment": "",
        "changes": {},
        "result": True,
    }
    changes = ret["changes"]
    cmd = ["salt-call", "--out=json", "state.sls", name]
    if __opts__['test']:
        cmd.append("test=True")
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
    out, err = p.communicate()
    code = p.wait()
    if code == 0:
        data = json.loads(out)['local']
        for statekey, statereturn in data.items():
            for k in ['duration', "__run_num__", "__sls__", "start_time"]:
                del statereturn[k]
            try:
                if statereturn.get('retcode', 0) != 0 or statereturn['result'] not in [True, None]:
                    ret['result'] = False
                if "retcode" in statereturn and statereturn['retcode'] == 0:
                    del statereturn['retcode']
                for f in ["error_message", "prefix", "stderr", "stdout", "result", "data", "message"]:
                    if f in statereturn and statereturn[f] in ('', None):
                        del statereturn[f]
            except KeyError as e:
                assert 0, pprint.pformat((statekey, e, statereturn))
            if statereturn['changes']:
                changes[statekey] = statereturn['changes']
            elif statereturn.get('pchanges'):
                changes[statekey] = statereturn['pchanges']
        ret['comment'] = yaml.safe_dump(data)
    else:
        ret['comment'] = "%s returned status code %s\n%s" % (cmd, code, err)
        ret['result'] = False
    return ret


#need to port some of those props (of vms that exist) from props of ansible
#properties
