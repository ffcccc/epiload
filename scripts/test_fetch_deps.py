import hashlib
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import zipfile

import yaml


FETCHER = Path(__file__).with_name("fetch_deps.py")


class FetchDependenciesTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="epiload deps ")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.manifest = self.root / "deps.yaml"
        self.destination = self.root / "external dependencies"

    def fetch(self, platform="windows-x86_64", force=False):
        command = [
            sys.executable, str(FETCHER),
            "--manifest", str(self.manifest),
            "--root", str(self.destination),
            "--platform", platform,
        ]
        if force:
            command.append("--force")
        return subprocess.run(command, capture_output=True, text=True)

    def write_manifest(self):
        archive = self.root / "package.zip"
        with zipfile.ZipFile(archive, "w") as package:
            package.writestr("include/example.h", "original")
        artifact = {
            "url": archive.as_uri(),
            "sha256": hashlib.sha256(archive.read_bytes()).hexdigest(),
        }
        self.manifest.write_text(yaml.safe_dump({
            "dependencies": {"example": {
                "version": "1.0",
                "platforms": {
                    "windows-x86_64": artifact,
                    "linux-x86_64": artifact,
                },
            }},
        }))

    def test_empty_dependencies(self):
        for content in ("dependencies:\n", "dependencies: {}\n"):
            with self.subTest(content=content):
                self.manifest.write_text(content)
                result = self.fetch()
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_install_cache_and_force_on_each_platform(self):
        self.write_manifest()
        for platform in ("windows-x86_64", "linux-x86_64"):
            with self.subTest(platform=platform):
                self.destination = self.root / platform
                result = self.fetch(platform)
                self.assertEqual(result.returncode, 0, result.stderr)
                installed = self.destination / "example/1.0/include/example.h"
                self.assertEqual(installed.read_text(), "original")
                installed.write_text("local edit")
                result = self.fetch(platform)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("[OK]", result.stdout)
                self.assertEqual(installed.read_text(), "local edit")
                result = self.fetch(platform, force=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(installed.read_text(), "original")

    def test_checksum_mismatch_does_not_install(self):
        self.write_manifest()
        manifest = yaml.safe_load(self.manifest.read_text())
        manifest["dependencies"]["example"]["platforms"]["windows-x86_64"]["sha256"] = "0" * 64
        self.manifest.write_text(yaml.safe_dump(manifest))
        result = self.fetch()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("SHA256 mismatch", result.stderr)
        self.assertFalse((self.destination / "example/1.0/.ready").exists())

    def test_platform_switch_reinstalls(self):
        self.write_manifest()
        result = self.fetch("windows-x86_64")
        self.assertEqual(result.returncode, 0, result.stderr)
        installed = self.destination / "example/1.0/include/example.h"
        installed.write_text("wrong platform")
        result = self.fetch("linux-x86_64")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(installed.read_text(), "original")
        marker = self.destination / "example/1.0/.ready"
        self.assertIn("linux-x86_64", marker.read_text())


if __name__ == "__main__":
    unittest.main()