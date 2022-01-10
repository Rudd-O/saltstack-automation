import os
import sys
import unittest

sys.path.append(os.path.dirname(__file__))
import firewall


class TestFirewall(unittest.TestCase):

    maxDiff = None

    homenetwork = {
        "zips": {},
        "networks": {
            "intranet": "1.2.3.0/24",
            "internet": "0.0.0.0/0",
            "urbit": "1.2.3.5",
        },
    }
    nodegroups = {}

    def test_simple(self):
        inp = {"from": "internet", "to": "intranet", "action": "accept"}
        exp = [
            "FORWARD -s 0.0.0.0/0 -d 1.2.3.0/24 -j ACCEPT -m comment --comment simple"
        ]
        out = firewall.rule_to_iptables(
            "simple", inp, self.homenetwork, self.nodegroups, "FORWARD"
        )
        self.assertListEqual(exp, out)

    def test_simple_children(self):
        inp = {"from": "internet", "rules": [{"to": "intranet", "action": "accept"}]}
        exp = [
            "FORWARD -s 0.0.0.0/0 -d 1.2.3.0/24 -j ACCEPT -m comment --comment simple"
        ]
        out = firewall.rule_to_iptables(
            "simple", inp, self.homenetwork, self.nodegroups, "FORWARD"
        )
        self.assertListEqual(exp, out)

    def test_two_children(self):
        inp = {
            "from": "internet",
            "rules": [{"to": "intranet", "action": "accept"}, {"action": "reject"}],
        }
        exp = [
            "FORWARD -s 0.0.0.0/0 -d 1.2.3.0/24 -j ACCEPT -m comment --comment simple",
            "FORWARD -s 0.0.0.0/0 -j REJECT -m comment --comment simple",
        ]
        out = firewall.rule_to_iptables(
            "simple", inp, self.homenetwork, self.nodegroups, "FORWARD"
        )
        self.assertListEqual(exp, out)

    def test_urbit_sample(self):
        inp = {
            "proto": "udp",
            "to_ports": 34123,
            "rules": [
                {
                    "chain": "PREROUTING",
                    "rules": [
                        {"from": "urbit", "action": "accept"},
                        {
                            "from": "internet",
                            "action": "dnat",
                            "dnat-to": "urbit",
                        },
                    ],
                },
                {
                    "chain": "POSTROUTING",
                    "rules": [
                        {"to": "urbit", "action": "accept"},
                    ],
                },
            ],
        }
        exp = [
            "PREROUTING -p udp -s 1.2.3.5 -j ACCEPT --dport 34123 -m comment --comment simple",
            "PREROUTING -p udp -s 0.0.0.0/0 -j DNAT --to-destination 1.2.3.5 --dport 34123 -m comment --comment simple",
            "POSTROUTING -p udp -d 1.2.3.5 -j ACCEPT --dport 34123 -m comment --comment simple",
        ]
        out = firewall.rule_to_iptables(
            "simple", inp, self.homenetwork, self.nodegroups, "FORWARD"
        )
        self.assertEqual(exp[0], out[0])
        self.assertEqual(exp[1], out[1])
        self.assertEqual(exp[2], out[2])
        self.assertListEqual(exp, out)

    def test_action(self):
        inp = {
            "action": "accept",
            "rules": [
                {
                    "from": "1.2.3.4",
                },
                {
                    "from": "1.2.3.5",
                },
            ],
        }
        exp = [
            "HOMENET-FORWARD -s 1.2.3.4 -j ACCEPT -m comment --comment simple",
            "HOMENET-FORWARD -s 1.2.3.5 -j ACCEPT -m comment --comment simple",
        ]
        out = firewall.rule_to_iptables(
            "simple", inp, self.homenetwork, self.nodegroups, "HOMENET-FORWARD"
        )
        self.assertEqual(exp[0], out[0])
        self.assertEqual(exp[1], out[1])
        self.assertListEqual(exp, out)

    def test_no_action(self):
        inp = {
            "rules": [
                {
                    "from": "1.2.3.4",
                },
                {
                    "from": "1.2.3.5",
                },
            ],
        }
        self.assertRaises(
            AssertionError,
            firewall.rule_to_iptables,
            "simple",
            inp,
            self.homenetwork,
            self.nodegroups,
            "HOMENET-FORWARD",
        )

    def test_action_with_parent_action(self):
        inp = {
            "action": "accept",
            "rules": [
                {
                    "from": "1.2.3.4",
                },
                {"from": "1.2.3.5", "action": "reject"},
            ],
        }
        exp = [
            "HOMENET-FORWARD -s 1.2.3.4 -j ACCEPT -m comment --comment simple",
            "HOMENET-FORWARD -s 1.2.3.5 -j REJECT -m comment --comment simple",
        ]
        out = firewall.rule_to_iptables(
            "simple", inp, self.homenetwork, self.nodegroups, "HOMENET-FORWARD"
        )
        self.assertEqual(exp[0], out[0])
        self.assertEqual(exp[1], out[1])
        self.assertListEqual(exp, out)


class TestSubrule(unittest.TestCase):
    def test_inheritance(self):
        inp = {
            "action": "accept",
            "rules": [
                {"from": "1.2.3.4"},
                {"from": "1.2.3.5", "action": "reject"},
            ],
        }
        exp = {
            "rules": [
                {"from": "1.2.3.4", "action": "accept"},
                {"from": "1.2.3.5", "action": "reject"},
            ]
        }
        firewall._inherit_tree(inp)
        self.assertEqual(inp, exp)
