"""Source-policy guardrails, not a substitute for native compilation/device tests."""

import unittest
from pathlib import Path


APP = Path(__file__).resolve().parents[2]
OHOS = APP / "ohos/entry/src/main/ets/security/AiCredentialsStore.ets"
ANDROID = APP / "android/app/src/main/kotlin/com/runtrail/runtrail/AiCredentialsStore.kt"
IOS = APP / "ios/Runner/AppDelegate.swift"


class AiCredentialsNativePolicyTest(unittest.TestCase):
    def test_channel_contract_and_redacted_failures(self):
        for path in (OHOS, ANDROID, IOS):
            with self.subTest(platform=path.suffix):
                source = path.read_text()
                if path == IOS:
                    source = source.split("private final class AiCredentialsStore", 1)[1]
                self.assertIn("runtrail/ai_credentials", source)
                for method in ("read", "write", "delete"):
                    self.assertRegex(source, rf"['\"]{method}['\"]")
                self.assertIn("secure_storage_unavailable", source)
                self.assertIn("1024", source)
                self.assertNotRegex(source, r"console\.|Log\.|print\(|NSLog\(|error\.message")
                self.assertNotRegex(source, r"getSharedPreferences\(|UserDefaults\.")

    def test_harmony_unlocked_non_sync_storage(self):
        source = OHOS.read_text()
        self.assertIn("asset.Tag.SECRET, bytes", source)
        self.assertIn("asset.Accessibility.DEVICE_UNLOCKED", source)
        self.assertIn("asset.SyncType.NEVER", source)
        self.assertIn("asset.ConflictResolution.OVERWRITE", source)
        self.assertNotIn("set(asset.Tag.IS_PERSISTENT", source)
        self.assertIn("ASSET_NOT_FOUND", source)
        self.assertIn("store.pending.then", source)

    def test_android_authenticated_encryption_and_backup_exclusion(self):
        source = ANDROID.read_text()
        for token in ("AndroidKeyStore", "AES/GCM/NoPadding", "noBackupFilesDir",
                      "AtomicFile", "setRandomizedEncryptionRequired(true)",
                      "cipher.updateAAD", "makeBackgroundTaskQueue()", "check(read() == value)"):
            self.assertIn(token, source)
        self.assertIn("key(false)", source)
        self.assertIn("keyStore().deleteEntry(KEY_ALIAS)", source)

    def test_ios_device_only_keychain(self):
        source = IOS.read_text().split("private final class AiCredentialsStore", 1)[1]
        for token in ("SecItemCopyMatching", "SecItemUpdate", "SecItemAdd", "SecItemDelete",
                      "kSecAttrAccessibleWhenUnlockedThisDeviceOnly",
                      "kSecAttrSynchronizable as String: false", "errSecItemNotFound"):
            self.assertIn(token, source)

    def test_all_bridges_are_registered(self):
        registrations = (
            ("ohos/entry/src/main/ets/entryability/EntryAbility.ets", "AiCredentialsStore.register(flutterEngine)"),
            ("android/app/src/main/kotlin/com/runtrail/runtrail/MainActivity.kt", "AiCredentialsStore.register("),
            ("ios/Runner/AppDelegate.swift", "AiCredentialsStore.register(messenger)"),
        )
        for path, registration in registrations:
            with self.subTest(path=path):
                self.assertIn(registration, (APP / path).read_text())


if __name__ == "__main__":
    unittest.main()
