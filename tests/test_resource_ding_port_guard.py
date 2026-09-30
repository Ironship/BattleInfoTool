"""ResourceDing ports must not silently discard BIT-only GUID fixes.

Run: python tests/test_resource_ding_port_guard.py
These tests exercise the real port edit without requiring a sibling checkout.
"""
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("bit_port_guid_guard", ROOT / "tools" / "port.py")
port = importlib.util.module_from_spec(spec)
spec.loader.exec_module(port)


class ResourceDingPortGuardTests(unittest.TestCase):
    def test_upstream_without_the_bit_latch_is_refused(self):
        # Today's standalone upstream has no usableGuid/per-target latch. A port
        # would replace the reviewed Core and lose the local crash fix.
        with self.assertRaisesRegex(SystemExit, "BIT-only.*latch"):
            port.rd_replay_secret_guid_fix("ResourceDing/Core.lua", "local function known(value) return value end\n")

    def test_guid_helper_without_per_target_latch_is_refused(self):
        incoming = "local function usableGuid(value)\n    if ok then return secret and nil or value end\nend\n"
        with self.assertRaisesRegex(SystemExit, "BIT-only.*latch"):
            port.rd_replay_secret_guid_fix("ResourceDing/Core.lua", incoming)

    def test_original_bug_is_fixed_when_the_required_latch_exists(self):
        incoming = (
            "local function usableGuid(value)\n"
            "    if ok then return secret and nil or value end\n"
            "end\n"
            "local byTarget = Addon.wasFullBy or {}\n"
        )
        result = port.rd_replay_secret_guid_fix("ResourceDing/Core.lua", incoming)
        self.assertNotIn("return secret and nil or value", result)
        self.assertIn("if secret then return nil end", result)
        self.assertIn("local byTarget = Addon.wasFullBy or {}", result)

    def test_unknown_guid_helper_shape_is_refused(self):
        incoming = (
            "local function usableGuid(value) return value end\n"
            "local byTarget = Addon.wasFullBy or {}\n"
        )
        with self.assertRaisesRegex(SystemExit, "changed shape"):
            port.rd_replay_secret_guid_fix("ResourceDing/Core.lua", incoming)


if __name__ == "__main__":
    unittest.main(verbosity=2)
