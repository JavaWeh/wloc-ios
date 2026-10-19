"""Test packaging format with temporary fixtures; produces no distributable app."""
from pathlib import Path
import plistlib
import tempfile
import unittest
import zipfile
from package_ipa import package


class PackagingTests(unittest.TestCase):
    def test_missing_build_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            with self.assertRaisesRegex(SystemExit, "No device build"):
                package(Path(temp) / "Absent.app", Path(temp) / "test.ipa")

    def test_simulator_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            app = self.fixture(Path(temp), "iphonesimulator")
            with self.assertRaisesRegex(SystemExit, "simulator"):
                package(app, Path(temp) / "test.ipa")

    def test_payload_structure_and_executable_mode(self):
        with tempfile.TemporaryDirectory() as temp:
            app = self.fixture(Path(temp), "iphoneos")
            output = Path(temp) / "fixture.ipa"
            package(app, output)
            with zipfile.ZipFile(output) as archive:
                self.assertEqual(set(archive.namelist()), {"Payload/Fixture.app/Fixture", "Payload/Fixture.app/Info.plist"})
                mode = archive.getinfo("Payload/Fixture.app/Fixture").external_attr >> 16
                self.assertTrue(mode & 0o111)
                self.assertEqual(archive.read("Payload/Fixture.app/Fixture"), b"packaging-test-fixture")

    def fixture(self, root, platform):
        app = root / "Fixture.app"
        app.mkdir()
        (app / "Fixture").write_bytes(b"packaging-test-fixture")
        (app / "Info.plist").write_bytes(plistlib.dumps({"CFBundleExecutable": "Fixture", "DTPlatformName": platform}))
        return app


if __name__ == "__main__":
    unittest.main()
