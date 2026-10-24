import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../core/theme.dart';
import '../services/diagnostics.dart';
import '../services/share_service.dart';
import '../services/training_plan_export.dart';

class TrainingPlanSharePage extends StatefulWidget {
  final TrainingPlanExportData data;
  final AppPalette palette;
  const TrainingPlanSharePage({
    super.key,
    required this.data,
    required this.palette,
  });
  @override
  State<TrainingPlanSharePage> createState() => _TrainingPlanSharePageState();
}

class _TrainingPlanSharePageState extends State<TrainingPlanSharePage> {
  late TrainingPlanExportLayout _layout;
  bool _includeNotes = false;
  TrainingExportResult? _result;
  bool _busy = false, _cancelled = false, _sharing = false, _handedOff = false;
  int _progress = 0;
  String? _error;
  final _shareKey = GlobalKey();
  final _shareCooldown = Stopwatch();

  @override
  void initState() {
    super.initState();
    _layout = TrainingPlanExportLayout(
      widget.data,
      widget.palette,
      includeNotes: _includeNotes,
    );
  }

  void _setIncludeNotes(bool value) {
    if (_busy || _sharing) return;
    if (_result != null && !_handedOff) {
      _result!.dispose().catchError((Object _) {});
    }
    _layout.dispose();
    setState(() {
      _includeNotes = value;
      _result = null;
      _handedOff = false;
      _layout = TrainingPlanExportLayout(
        widget.data,
        widget.palette,
        includeNotes: value,
      );
    });
  }

  Future<void> _generate(bool pdf) async {
    if (_busy || _sharing) return;
    setState(() {
      _busy = true;
      _cancelled = false;
      _progress = 0;
      _error = null;
    });
    try {
      final temp = await getTemporaryDirectory();
      // Only our old export folders; keep recent handoffs because some platforms
      // return from their share sheet before the recipient has read the file.
      await for (final entry in temp.list()) {
        if (entry is Directory &&
            entry.path
                .split(Platform.pathSeparator)
                .last
                .startsWith('runtrail-plan-')) {
          final stat = await entry.stat();
          if (DateTime.now().difference(stat.modified) >
              const Duration(days: 1)) {
            try {
              await entry.delete(recursive: true);
            } on FileSystemException {
              /* A receiver may still hold the file. */
            }
          }
        }
      }
      final result = await _layout.generate(
        temporaryRoot: temp,
        pdf: pdf,
        cancelled: () => _cancelled || !mounted,
        onProgress: (current, total) {
          if (mounted) setState(() => _progress = current);
        },
      );
      if (!mounted) {
        await result.dispose();
        return;
      }
      if (_result != null && !_handedOff) await _result!.dispose();
      if (!mounted) {
        await result.dispose();
        return;
      }
      setState(() {
        _result = result;
        _handedOff = false;
      });
    } on TrainingExportCancelled {
      // Cancellation is deliberate and never opens the system share sheet.
    } catch (error, stack) {
      await Diagnostics.logError('TRAINING_SHARE export failed', error, stack);
      if (mounted) setState(() => _error = '生成失败，请重试；也可选择完整 PDF。');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      } else {
        _layout.dispose();
      }
    }
  }

  Future<void> _share() async {
    if (_busy || _sharing || _result == null) return;
    // Some native share adapters return as soon as the sheet opens. Keep a
    // short monotonic debounce so the second tap cannot open another sheet.
    if (_shareCooldown.isRunning &&
        _shareCooldown.elapsed < const Duration(milliseconds: 700)) {
      return;
    }
    final box = _shareKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final origin = box.localToGlobal(Offset.zero) & box.size;
    _shareCooldown
      ..reset()
      ..start();
    setState(() {
      _sharing = true;
      _error = null;
    });
    try {
      // Native sheets can return before another app opens the file. Retain for
      // at most the next cleanup window even if the native result is uncertain.
      _handedOff = true;
      await ShareService.file(
        _result!.file.path,
        subject: '${widget.data.name} · 完整训练计划',
        mimeType: _result!.pdf ? 'application/pdf' : 'image/png',
        sharePositionOrigin: origin,
      );
    } catch (error, stack) {
      await Diagnostics.logError(
        'TRAINING_SHARE native share failed',
        error,
        stack,
      );
      if (mounted) setState(() => _error = '系统分享未完成，请重试。预览文件仍保留。');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  void dispose() {
    _cancelled = true;
    // Generation owns its own resources until its pending frame completes.
    if (!_busy) _layout.dispose();
    if (_result != null && !_handedOff) {
      _result!.dispose().catchError((Object _) {});
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final buttonStyle = FilledButton.styleFrom(
      backgroundColor: p.inverseSurface,
      foregroundColor: p.onInverse,
      disabledBackgroundColor: p.surface2,
      disabledForegroundColor: p.textSecondary,
    );
    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(title: const Text('分享完整训练计划')),
      body: SafeArea(
        child: CustomScrollView(
          key: const Key('training-export-scroll'),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${widget.data.range} · 共 ${widget.data.tasks.length} 天',
                      style: TextStyle(
                        color: p.textPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '包含全部日期、标题、距离、配速、完成状态及实际跑量。不附带体重和身体反馈原始记录、GPS、API Key 或 AI 对话。',
                      style: TextStyle(color: p.textSecondary, fontSize: 12),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text('附带完整训练说明'),
                      subtitle: const Text(
                        '包括间歇组数等文字细节。AI 说明也可能涉及身体情况，开启后请检查预览。',
                      ),
                      value: _includeNotes,
                      onChanged: _busy || _sharing ? null : _setIncludeNotes,
                    ),
                    if (!_includeNotes)
                      Text(
                        '当前不附带训练说明，部分细节可能只在说明中；需要完整文字时请开启。',
                        style: TextStyle(color: p.textSecondary, fontSize: 12),
                      ),
                    if (!_layout.supportsPng)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '这份计划较长，完整长图可能无法在手机中打开。请选择完整 PDF：包含全部 ${_layout.pageCount} 页，不截断日期。',
                          style: TextStyle(color: p.textPrimary),
                        ),
                      ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(_error!, style: TextStyle(color: p.danger)),
                      ),
                  ],
                ),
              ),
            ),
            if (_busy)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      CircularProgressIndicator(
                        value: _progress / _layout.pageCount,
                      ),
                      const SizedBox(height: 12),
                      Text('正在生成 $_progress / ${_layout.pageCount} 页'),
                      TextButton(
                        onPressed: () => setState(() => _cancelled = true),
                        child: Text(_cancelled ? '正在取消…' : '取消生成'),
                      ),
                    ],
                  ),
                ),
              )
            else if (_result == null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    '生成后可逐页检查完整内容\n不是当前屏幕截图',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: p.textSecondary),
                  ),
                ),
              )
            else
              SliverList(
                key: const Key('training-export-preview'),
                delegate: SliverChildBuilderDelegate(
                  (context, index) => Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Semantics(
                      label:
                          '完整计划第 ${index + 1} 页，共 ${_result!.previews.length} 页',
                      child: Image.file(
                        _result!.previews[index],
                        fit: BoxFit.fitWidth,
                        cacheWidth: 900,
                      ),
                    ),
                  ),
                  childCount: _result!.previews.length,
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 4,
                alignment: WrapAlignment.center,
                children: [
                  if (_layout.supportsPng)
                    OutlinedButton(
                      onPressed: _busy || _sharing
                          ? null
                          : () => _generate(false),
                      child: const Text('生成完整长图'),
                    ),
                  OutlinedButton(
                    onPressed: _busy || _sharing ? null : () => _generate(true),
                    child: const Text('生成完整 PDF'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: _shareKey,
                  style: buttonStyle,
                  onPressed: _result == null || _busy || _sharing
                      ? null
                      : _share,
                  icon: const Icon(Icons.ios_share),
                  label: Text(
                    _sharing
                        ? '正在打开系统分享…'
                        : '确认预览并分享${_result?.pdf == true ? ' PDF' : '长图'}',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
