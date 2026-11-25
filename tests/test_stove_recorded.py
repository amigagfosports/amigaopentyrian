"""scripts/build_sdl3_port.py verify_stove records the compiler and refuses no stove (BL-144)."""
import importlib.util
import json
import unittest
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("sdl3_port", ROOT / "scripts/build_sdl3_port.py")
PORT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PORT)


class StoveRecorded(unittest.TestCase):
    def stove(self, root, said, provenance=None):
        gxx = root / "prefix/bin/m68k-amigaos-g++"
        gxx.parent.mkdir(parents=True)
        gxx.write_text(f"#!/bin/sh\necho 'm68k-amigaos-g++ ({said}) 16.2.0b'\n")
        gxx.chmod(0o755)
        if provenance is not None:
            (root / "provenance.json").write_text(json.dumps(provenance))
        return root

    def test_stoves_the_old_check_refused_now_build(self):
        with tempfile.TemporaryDirectory() as tmp:
            for name, said, prov in (("open9", "GFOpenAmigaGCC 16.2.0-open9", None),
                                     ("open1", "OpenAmigaGCC 16.2.0-open1", {"release": "16.2.0-open1"}),
                                     ("changed", "OpenAmigaGCC 16.2.0-open3",
                                      {"release": "16.2.0-open3", "archive_sha256": PORT.OPEN3,
                                       "compiler_runtime_sha256": {"bin/m68k-amigaos-g++": "0" * 64}})):
                r = PORT.verify_stove(self.stove(Path(tmp) / name, said, prov), "16.2.0-open3")
                self.assertIn(said, r["compiler"])
                self.assertEqual(r["release"], said.split()[-1])

    def test_archive_is_recorded_when_named(self):
        with tempfile.TemporaryDirectory() as tmp:
            r = PORT.verify_stove(self.stove(Path(tmp), "OpenAmigaGCC 16.2.0-open3",
                                             {"release": "16.2.0-open3", "archive_sha256": PORT.OPEN3}))
            self.assertEqual(r["archive_sha256"], PORT.OPEN3)

    def test_no_compiler_is_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaisesRegex(ValueError, "no compiler"):
                PORT.verify_stove(Path(tmp))


if __name__ == "__main__":
    unittest.main()
