"""Android launcher manifest/resource guardrails, not an emulator/device test."""
import unittest
from pathlib import Path
import xml.etree.ElementTree as ET

APP = Path(__file__).resolve().parents[2]
MAIN = APP / 'android/app/src/main'
A = '{http://schemas.android.com/apk/res/android}'


class LauncherIconsAndroidTest(unittest.TestCase):
    def test_main_target_is_permanent_and_not_a_second_launcher(self):
        app = ET.parse(MAIN / 'AndroidManifest.xml').getroot().find('application')
        main = next(a for a in app.findall('activity') if a.get(A + 'name') == '.MainActivity')
        self.assertNotEqual(main.get(A + 'enabled'), 'false')
        self.assertFalse(main.findall('intent-filter'))
        aliases = app.findall('activity-alias')
        self.assertEqual(len(aliases), 3)
        default = next(a for a in app.findall('activity') if a.get(A+'name') == '.LauncherDefault')
        self.assertEqual(default.get(A+'enabled'), 'true')
        self.assertEqual(default.find('intent-filter/category').get(A+'name'), 'android.intent.category.LAUNCHER')
        self.assertEqual(sum(a.get(A + 'enabled') == 'true' for a in aliases), 0)
        self.assertEqual({a.get(A+'name') for a in aliases}, {
            '.LauncherLight', '.LauncherDark', '.LauncherEditorial'})
        for alias in aliases:
            self.assertEqual(alias.get(A + 'targetActivity'), '.MainActivity')
            self.assertEqual(alias.get(A + 'exported'), 'true')
            self.assertEqual(alias.find('intent-filter/category').get(A + 'name'),
                             'android.intent.category.LAUNCHER')

    def test_all_three_styles_have_legacy_and_adaptive_resources(self):
        for style, bg, ink in [('light', '#EDEFF8', '#5E5CE6'),
                               ('dark', '#101014', '#FF6B4A'),
                               ('editorial', '#14150F', '#B8E62E')]:
            legacy = MAIN / f'res/mipmap-anydpi/ic_launcher_{style}.xml'
            adaptive = MAIN / f'res/mipmap-anydpi-v26/ic_launcher_{style}.xml'
            foreground = MAIN / f'res/drawable/launcher_{style}_foreground.xml'
            self.assertEqual(ET.parse(legacy).getroot().tag, 'vector')
            self.assertEqual(ET.parse(adaptive).getroot().tag, 'adaptive-icon')
            ET.parse(foreground)
            self.assertIn(bg, legacy.read_text())
            self.assertIn(ink, foreground.read_text())
            # Shared route shape from the existing code-native startup logo.
            self.assertIn('M74,127 C136,116 117,105 94,94', foreground.read_text())

    def test_pending_notifications_do_not_reference_switchable_aliases(self):
        source = (MAIN / 'kotlin/com/runtrail/runtrail/TrainingAlarms.kt').read_text()
        self.assertNotIn('getLaunchIntentForPackage', source)
        self.assertIn('Intent(context, MainActivity::class.java)', source)

    def test_bridge_never_disables_the_real_activity(self):
        native = (MAIN / 'kotlin/com/runtrail/runtrail/LauncherIconManager.kt').read_text()
        self.assertIn('runtrail/launcher_icon', native)
        self.assertIn('"getSupport"', native)
        self.assertIn('"setIcon"', native)
        self.assertIn('PackageManager.DONT_KILL_APP', native)
        self.assertIn('setComponentEnabledSettings', native)
        self.assertIn('if (Build.VERSION.SDK_INT >= 33)', native)
        self.assertNotIn('component("MainActivity")', native)
        # Old Android enables target before retiring previous aliases.
        old_api = native.split('} else {', 1)[1].split('check(', 1)[0]
        self.assertLess(old_api.index('setComponentEnabledSetting(target'),
                        old_api.index('filter { it != target }'))
        self.assertIn('oldEnabled.forEach', native)
        self.assertIn('if (oldEnabled.any { enabled(it) })', native)
        activity = (MAIN / 'kotlin/com/runtrail/runtrail/MainActivity.kt').read_text()
        self.assertIn('LauncherIconManager.register(', activity)


if __name__ == '__main__':
    unittest.main()
