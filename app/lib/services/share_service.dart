// The HarmonyOS share_plus fork still exposes the static API.
// Keep the compatibility boundary here until both toolchains support SharePlus.
// ignore_for_file: deprecated_member_use
import 'package:share_plus/share_plus.dart';

import 'dart:ui' show Rect;

class ShareService {
  ShareService._();
  static Future<void> file(
    String path, {
    String? subject,
    String? mimeType,
    Rect? sharePositionOrigin,
  }) async {
    await Share.shareXFiles(
      [XFile(path, mimeType: mimeType)],
      subject: subject,
      sharePositionOrigin: sharePositionOrigin,
    );
  }
}
