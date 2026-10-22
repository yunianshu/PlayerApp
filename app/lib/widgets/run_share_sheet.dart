import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';

import '../core/i18n.dart';
import '../core/theme.dart';
import '../models/run_record.dart';
import '../services/diagnostics.dart';
import '../services/share_service.dart';
import 'common.dart';
import 'run_poster.dart';

Future<void> showRunShareSheet(
  BuildContext context, {
  required RunRecord record,
  required List<RunPoint> points,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: context.readColors.surface,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
  ),
  builder: (_) => _RunShareSheet(record: record, points: points),
);

class _RunShareSheet extends StatefulWidget {
  final RunRecord record;
  final List<RunPoint> points;

  const _RunShareSheet({required this.record, required this.points});

  @override
  State<_RunShareSheet> createState() => _RunShareSheetState();
}

class _RunShareSheetState extends State<_RunShareSheet> {
  final _posterKey = GlobalKey();
  final _shareButtonKey = GlobalKey();
  bool _sharing = false;
  String? _error;

  Future<void> _shareImage() async {
    if (_sharing) return;
    setState(() {
      _sharing = true;
      _error = null;
    });
    try {
      // Capture the visible, painted preview, including on small screens.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final boundary =
          _posterKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      final button =
          _shareButtonKey.currentContext?.findRenderObject() as RenderBox?;
      if (boundary == null || button == null) {
        throw StateError('Share preview is not ready');
      }
      final origin = button.localToGlobal(Offset.zero) & button.size;
      final image = await boundary.toImage(pixelRatio: 3);
      late final File file;
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) throw StateError('Could not encode share image');
        final dir = await getTemporaryDirectory();
        file = File(
          '${dir.path}/runtrail_poster_${widget.record.start.millisecondsSinceEpoch}.png',
        );
        await file.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true,
        );
      } finally {
        image.dispose();
      }
      if (!mounted) return;
      await ShareService.file(
        file.path,
        subject: '跑迹 RunTrail',
        mimeType: 'image/png',
        sharePositionOrigin: origin,
      );
    } catch (error, stack) {
      await Diagnostics.logError('SHARE image failed', error, stack);
      if (mounted) setState(() => _error = '分享失败，请重试'.tr);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return FractionallySizedBox(
      heightFactor: .9,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '分享成绩海报'.tr,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭'.tr,
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close, color: c.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Center(
                  child: FittedBox(
                    child: RepaintBoundary(
                      key: _posterKey,
                      child: MediaQuery(
                        data: MediaQuery.of(context)
                            .copyWith(textScaler: TextScaler.noScaling),
                        child: RunPoster(
                          record: widget.record,
                          points: widget.points,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: c.danger)),
              ],
              const SizedBox(height: 16),
              PrimaryButton(
                key: _shareButtonKey,
                label: _sharing ? '正在生成图片…'.tr : '分享图片'.tr,
                icon: Icons.ios_share,
                onTap: _sharing ? null : _shareImage,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
