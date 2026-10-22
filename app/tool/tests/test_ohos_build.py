"""Failure isolation and deterministic preparation for the HarmonyOS build."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("ohos_build", Path(__file__).parents[1] / "ohos_build.py")
builder = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(builder)


class BuildIsolationTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="runtrail-build-test-")
        self.addCleanup(self.temporary.cleanup)
        self.app = Path(self.temporary.name) / "app"
        self.app.mkdir()
        for folder in ("lib", "assets", "ohos", "tool", "test"):
            (self.app / folder).mkdir()
        builder.write_text(self.app / "pubspec.yaml", "main manifest\n")
        builder.write_text(self.app / "pubspec.lock", "main lock\n")
        builder.write_text(self.app / "pubspec_ohos.lock", "harmony lock\n")
        builder.write_text(self.app / "pubspec_ohos.yaml", "name: example\ndependencies:\n  geolocator:\n"
                           "    git:\n      url: https://example.invalid/plugin.git\n"
                           "      ref: abc123\n      path: geolocator\n")
        builder.write_text(self.app / "analysis_options.yaml", "analyzer:\n  exclude:\n    - vendor/**\n")
        builder.write_text(self.app / "ohos/build-profile.json5", '{"signingConfigs": []}')
        builder.write_text(self.app / "ohos/build-profile.local.json5", '{"signingConfigs": ["local"]}')
        self.config = {"flutter_sdk": str(self.app / "sdk"),
                       "deveco_home": str(self.app / "deveco"),
                       "pub_cache": str(self.app / "cache")}

    def test_failed_pub_get_keeps_all_main_files_and_releases_build_lock(self):
        names = ("pubspec.yaml", "pubspec.lock", "pubspec_ohos.lock", "ohos/build-profile.json5")
        before = {name: (self.app / name).read_bytes() for name in names}
        with patch.object(builder, "run", side_effect=subprocess.CalledProcessError(1, "flutter")):
            with self.assertRaises(subprocess.CalledProcessError):
                builder.build(self.app, "release", self.config)
        self.assertEqual(before, {name: (self.app / name).read_bytes() for name in names})
        self.assertFalse((self.app / "build/.ohos-build-lock").exists())
        self.assertFalse(list(self.app.glob("*.bak")))

    def test_stage_uses_private_signing_and_pinned_overrides(self):
        stage = builder.stage_project(self.app, self.config)
        self.assertEqual((stage / "pubspec.lock").read_text(), "harmony lock\n")
        self.assertIn('"local"', (stage / "ohos/build-profile.json5").read_text())
        self.assertEqual(json.loads((self.app / "ohos/build-profile.json5").read_text())["signingConfigs"], [])
        self.assertIn("ref: abc123", (stage / "pubspec_overrides.yaml").read_text())
        builder.write_overrides(stage, local_geolocator=True)
        self.assertIn("path: vendor/geolocator", (stage / "pubspec_overrides.yaml").read_text())

    def test_refuses_to_remove_sources_or_build_root(self):
        for target in (self.app, self.app / "lib", self.app / "build", self.app.parent):
            with self.assertRaises(RuntimeError):
                builder.remove_generated(target, self.app)
        self.assertTrue((self.app / "pubspec.yaml").exists())

    @unittest.skipUnless(os.name == "nt", "Windows MAX_PATH regression")
    def test_repeated_build_can_remove_long_arkts_cache_paths(self):
        stage = self.app / "build/ohos-workspace"
        cache = stage / ("cache-" + "x" * 100) / ("entry-" + "y" * 100) / "snapshot.msgpack"
        extended = Path("\\\\?\\" + str(cache.resolve()))
        builder.write_text(extended, "generated")
        self.assertTrue(extended.exists())
        builder.remove_generated(stage, self.app)
        self.assertFalse(stage.exists())

    def test_compatibility_patches_only_private_copies(self):
        stage = builder.stage_project(self.app, self.config)
        cached = self.app / "cache/geolocator"
        source = "export 'package:geolocator_platform_interface/geolocator_platform_interface.dart';\n" \
                 "export 'package:geolocator_web/geolocator_web.dart';\n// GeolocatorPlatform\n"
        builder.write_text(cached / "lib/geolocator.dart", source)
        manifest = self.app / "sdk/packages/flutter_tools/hvigor/package.json"
        builder.write_text(manifest, json.dumps({"devDependencies": {"@ohos/hvigor": "5.2.2"}}))
        with patch.object(builder, "package_path", return_value=cached):
            builder.prepare_compatibility(stage, self.config)
        self.assertEqual((cached / "lib/geolocator.dart").read_text(), source)
        self.assertIn("5.2.2", manifest.read_text())
        self.assertNotIn("geolocator_web", (stage / "vendor/geolocator/lib/geolocator.dart").read_text())
        self.assertNotIn("@ohos/hvigor", (stage / "vendor/flutter-hvigor-plugin/package.json").read_text())


if __name__ == "__main__":
    unittest.main()
