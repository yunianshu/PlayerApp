"""The optional API26 overlay must not alter the standard build or claim SDK support."""
import importlib.util
import json
from pathlib import Path
import shutil
import tempfile
import unittest

ROOT = Path(__file__).parents[2]
SPEC = importlib.util.spec_from_file_location('ohos_build', ROOT / 'tool/ohos_build.py')
builder = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(builder)


class LauncherIconTrialTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.config = {'deveco_home': str(self.root / 'deveco')}

    def sdk(self, *, schema=True):
        api = self.root / 'deveco/sdk/default/openharmony/ets/api/@ohos.bundle.bundleManager.d.ts'
        builder.write_text(api, 'function setAlternateIcon(name: string): Promise<void>;\n'
                           'function getAlternateIcons(): Promise<Array<AlternateIconInfo>>;')
        if schema:
            builder.write_text(self.root / 'deveco/sdk/default/ets/schema/app.schema.json',
                               '{"properties":{"alternateIcons":{"type":"array"}}}')

    def test_missing_sdk_fails_before_workspace_changes(self):
        with self.assertRaisesRegex(RuntimeError, 'API 26.0.0'):
            builder.build(self.root / 'app', 'debug', self.config, launcher_icons=True)
        self.assertFalse((self.root / 'app/build').exists())

    def test_inactive_new_sdk_does_not_enable_old_active_sdk(self):
        self.sdk()
        sdk = self.root / 'deveco/sdk'
        (sdk / 'default').rename(sdk / 'inactive26')
        with self.assertRaisesRegex(RuntimeError, 'API 26.0.0'):
            builder.verify_launcher_icon_sdk(self.config)

    def test_new_declarations_with_old_packager_rejected(self):
        self.sdk(schema=False)
        with self.assertRaisesRegex(RuntimeError, 'schema'):
            builder.verify_launcher_icon_sdk(self.config)

    def test_matching_declarations_and_schema_accepted(self):
        self.sdk()
        builder.verify_launcher_icon_sdk(self.config)

    def test_overlay_changes_only_disposable_workspace_and_keeps_sdk_targets(self):
        stage = self.root / 'stage'
        shutil.copytree(ROOT / 'tool/launcher_icons_api26', stage / 'tool/launcher_icons_api26')
        builder.write_text(stage / 'ohos/AppScope/app.json5', '{"app":{"bundleName":"com.test.app"}}')
        profile = '{"targetSdkVersion":"6.0.2(22)","compatibleSdkVersion":"5.0.0(12)"}'
        builder.write_text(stage / 'ohos/build-profile.json5', profile)
        original = (ROOT / 'ohos/AppScope/app.json5').read_bytes()
        builder.prepare_launcher_icons(stage)
        self.assertEqual((stage / 'ohos/build-profile.json5').read_text(), profile)
        self.assertEqual((ROOT / 'ohos/AppScope/app.json5').read_bytes(), original)
        icons = json.loads((stage / 'ohos/AppScope/app.json5').read_text())['app']['alternateIcons']
        self.assertEqual([i['name'] for i in icons], ['runtrail_light','runtrail_dark','runtrail_editorial'])
        for name in ('light','dark','editorial'):
            self.assertTrue((stage / f'ohos/AppScope/resources/base/media/launcher_{name}.svg').exists())
        bridge = (stage / 'ohos/entry/src/main/ets/appearance/LauncherIconSupport.ets').read_text()
        self.assertIn('bundleManager.setAlternateIcon', bridge)
        self.assertIn('deviceInfo.sdkApiVersion < 26', bridge)
        self.assertIn('getAlternateIcons', bridge)
        self.assertNotIn('alternateIcons', json.loads(original)['app'])

    def test_overlay_refuses_overwriting_existing_alternates(self):
        stage = self.root / 'stage'
        shutil.copytree(ROOT / 'tool/launcher_icons_api26', stage / 'tool/launcher_icons_api26')
        builder.write_text(stage / 'ohos/AppScope/app.json5',
                           '{"app":{"alternateIcons":[{"name":"owned"}]}}')
        with self.assertRaisesRegex(RuntimeError, 'Existing alternateIcons'):
            builder.prepare_launcher_icons(stage)


if __name__ == '__main__':
    unittest.main()
