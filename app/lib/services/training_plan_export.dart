import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'marathon_training_service.dart';
import 'training_run_results.dart';

/// Explicit allowlist: no feedback, GPS, provider settings or AI prompt enters
/// the export. A snapshot also prevents plan switches changing an open preview.
class TrainingPlanExportData {
  final String name, raceDate, goal;
  final DateTime createdAt;
  final List<TrainingTask> tasks;
  final Set<String> completed;
  final Map<String, TrainingRunResult> results;

  TrainingPlanExportData({
    required this.name,
    required this.raceDate,
    required this.goal,
    required this.createdAt,
    required List<TrainingTask> tasks,
    required Set<String> completed,
    Map<String, TrainingRunResult> results = const {},
  }) : tasks = List.unmodifiable(
         [...tasks]..sort((a, b) => a.date.compareTo(b.date)),
       ),
       completed = Set.unmodifiable(completed),
       results = Map.unmodifiable(results);

  TrainingRunResult resultFor(TrainingTask task) =>
      results[task.date] ??
      TrainingRunResults.forTask(
        task,
        manuallyCompleted: completed.contains(task.date),
      );

  String get range =>
      tasks.isEmpty ? '' : '${tasks.first.date} — ${tasks.last.date}';
  String get countdown {
    final race = DateTime.tryParse(raceDate);
    if (race == null) return '';
    final today = DateTime(createdAt.year, createdAt.month, createdAt.day);
    final days = DateTime.utc(
      race.year,
      race.month,
      race.day,
    ).difference(DateTime.utc(today.year, today.month, today.day)).inDays;
    return days > 0
        ? '距比赛 $days 天'
        : days == 0
        ? '今天比赛'
        : '比赛已结束';
  }
}

class TrainingExportCancelled implements Exception {}

class TrainingExportResult {
  final Directory directory;
  final File file;
  final List<File> previews;
  final bool pdf;
  TrainingExportResult(this.directory, this.file, this.previews, this.pdf);
  Future<void> dispose() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}

class _ExportLine {
  final TextPainter painter;
  final double y;
  _ExportLine(this.painter, this.y);
}

/// Fixed-width, fully expanded print layout, independent of screen orientation,
/// viewport, current date selection and lazily built calendar/list children.
class TrainingPlanExportLayout {
  static const int width = 900;
  static const int pageHeight = 1400;
  static const int maxPngHeight = 16000;
  final TrainingPlanExportData data;
  final AppPalette palette;
  final List<List<_ExportLine>> _pages = [[]];
  final List<String> content = [];
  double _y = 48;

  TrainingPlanExportLayout(
    this.data,
    this.palette, {
    bool includeNotes = true,
  }) {
    if (data.tasks.isEmpty) throw StateError('没有可分享的训练安排');
    _text('跑迹 RUNTRAIL  /  完整训练计划', size: 20, secondary: true);
    _text(data.name, size: 40, bold: true);
    _text('${data.raceDate}  ·  ${data.countdown}', size: 26);
    _text(data.goal, size: 24);
    _text(
      '${data.range}\n共 ${data.tasks.length} 天 · 完成 ${data.tasks.where((t) => data.resultFor(t).isComplete).length} 天',
      size: 22,
      secondary: true,
    );
    _text(
      '包含全部日期、训练安排、跑步成果及完成状态。生成于 ${data.createdAt.toIso8601String().substring(0, 10)}',
      size: 18,
      secondary: true,
    );
    String month = '';
    for (final task in data.tasks) {
      final nextMonth = task.date.length >= 7
          ? task.date.substring(0, 7)
          : task.date;
      if (nextMonth != month) {
        month = nextMonth;
        _space(20);
        _text('${month.replaceFirst('-', ' 年 ')} 月', size: 30, bold: true);
      }
      _space(12);
      final result = data.resultFor(task);
      _text(
        '${task.date}  ·  ${result.statusLabel}${result.manuallyCompleted ? ' · 手动标记完成' : ''}',
        size: 22,
        secondary: true,
      );
      _text(
        '${task.title}  ·  ${task.km > 0 ? '${task.km.toStringAsFixed(1)} km' : '休息 / 恢复'}',
        size: 28,
        bold: true,
      );
      _text(result.summary, size: 20, secondary: true);
      if (task.easyPace != null || task.slowPace != null) {
        String pace(int? seconds) => seconds == null
            ? '—'
            : '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
        _text(
          '参考配速 ${pace(task.easyPace)}–${pace(task.slowPace)} /km',
          size: 20,
          secondary: true,
        );
      }
      if (task.notes.isNotEmpty) {
        _text(
          includeNotes ? task.notes : '训练说明未附带（可在分享设置中开启）',
          size: 22,
          secondary: !includeNotes,
        );
      }
    }
    _space(20);
    _text(
      '完整计划 · ${data.tasks.length} 天 · 结束于 ${data.tasks.last.date}',
      size: 20,
      bold: true,
    );
    _text('计划供训练参考，请结合实际恢复情况调整。', size: 18, secondary: true);
  }

  int get pageCount => _pages.length;
  int get pngHeight => pageCount * pageHeight;
  bool get supportsPng => pngHeight <= maxPngHeight;

  void _space(double height) => _y += height;

  void _text(
    String text, {
    required double size,
    bool bold = false,
    bool secondary = false,
  }) {
    // Bound paragraph size before layout: even a long user-entered note cannot
    // exceed a page or be ellipsized. Preserve every Unicode scalar and newline.
    for (final paragraph in text.split('\n')) {
      final runes = paragraph.runes.toList();
      if (runes.isEmpty) {
        _space(size * 1.45);
        continue;
      }
      for (var start = 0; start < runes.length; start += 220) {
        final part = String.fromCharCodes(
          runes.sublist(start, (start + 220).clamp(0, runes.length).toInt()),
        );
        final painter = TextPainter(
          text: TextSpan(
            text: part,
            style: TextStyle(
              fontFamily: 'Noto Sans SC',
              fontSize: size,
              height: 1.45,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
              color: secondary ? palette.textSecondary : palette.textPrimary,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: width - 96);
        if (_y + painter.height > pageHeight - 65) {
          _pages.add([]);
          _y = 48;
        }
        _pages.last.add(_ExportLine(painter, _y));
        content.add(part);
        _y += painter.height + 10;
      }
    }
  }

  Future<ui.Image> renderPage(int index) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(palette.bg, BlendMode.src);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 12, 1400),
      Paint()..color = palette.accent,
    );
    for (final line in _pages[index]) {
      line.painter.paint(canvas, Offset(48, line.y));
    }
    final footer = TextPainter(
      text: TextSpan(
        text: '跑迹 · 完整计划   ${index + 1} / $pageCount',
        style: TextStyle(
          fontFamily: 'Noto Sans SC',
          fontSize: 16,
          color: palette.textSecondary,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    footer.paint(canvas, const Offset(48, pageHeight - 40));
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(width, pageHeight);
    } finally {
      picture.dispose();
      footer.dispose();
    }
  }

  void dispose() {
    for (final page in _pages) {
      for (final line in page) {
        line.painter.dispose();
      }
    }
  }

  /// GPU work is bounded to 900×1400. PNG scanlines are compressed incrementally,
  /// not stitched into one huge GPU texture. For long plans explicitly use PDF.
  Future<TrainingExportResult> generate({
    required Directory temporaryRoot,
    required bool pdf,
    bool Function()? cancelled,
    void Function(int, int)? onProgress,
  }) async {
    if (!pdf && !supportsPng) throw StateError('计划较长，请选择完整 PDF，避免长图在手机中无法打开');
    void check() {
      if (cancelled?.call() ?? false) throw TrainingExportCancelled();
    }

    check();
    final directory = await temporaryRoot.createTemp('runtrail-plan-');
    final previews = <File>[];
    final pdfPages = <Uint8List>[];
    final compressed = BytesBuilder(copy: false);
    final compressor = pdf
        ? null
        : ZLibEncoder().startChunkedConversion(
            ByteConversionSink.withCallback(compressed.add),
          );
    var compressorClosed = false;
    try {
      for (var index = 0; index < pageCount; index++) {
        check();
        final image = await renderPage(index);
        try {
          check();
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          if (png == null) throw StateError('预览图生成失败');
          final preview = File('${directory.path}/page-${index + 1}.png');
          await preview.writeAsBytes(
            png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
          );
          previews.add(preview);
          final raw = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          if (raw == null) throw StateError('图片生成失败');
          final rgba = raw.buffer.asUint8List(
            raw.offsetInBytes,
            raw.lengthInBytes,
          );
          if (pdf) {
            final rgb = Uint8List(width * pageHeight * 3);
            for (int from = 0, to = 0; from < rgba.length; from += 4) {
              rgb[to++] = rgba[from];
              rgb[to++] = rgba[from + 1];
              rgb[to++] = rgba[from + 2];
            }
            pdfPages.add(Uint8List.fromList(ZLibEncoder().convert(rgb)));
          } else {
            final row = Uint8List(width * 4 + 1); // PNG filter 0.
            for (var y = 0; y < pageHeight; y++) {
              row.setRange(1, row.length, rgba, y * width * 4);
              compressor!.add(row);
            }
          }
        } finally {
          image.dispose();
        }
        onProgress?.call(index + 1, pageCount);
        await Future<void>.delayed(Duration.zero);
      }
      check();
      if (compressor != null) {
        compressor.close();
        compressorClosed = true;
      }
      final bytes = pdf
          ? _pdf(pdfPages)
          : _png(width, pngHeight, compressed.takeBytes());
      final file = File(
        '${directory.path}/training-plan.${pdf ? 'pdf' : 'png'}',
      );
      await file.writeAsBytes(bytes, flush: true);
      check();
      return TrainingExportResult(directory, file, previews, pdf);
    } catch (_) {
      if (await directory.exists()) await directory.delete(recursive: true);
      rethrow;
    } finally {
      if (compressor != null && !compressorClosed) compressor.close();
    }
  }
}

Uint8List _png(int width, int height, Uint8List compressed) {
  final result = BytesBuilder(copy: false)
    ..add([137, 80, 78, 71, 13, 10, 26, 10]);
  void chunk(String type, List<int> data) {
    final body = Uint8List.fromList([...ascii.encode(type), ...data]);
    var crc = 0xffffffff;
    for (final byte in body) {
      crc ^= byte;
      for (var bit = 0; bit < 8; bit++) {
        crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
      }
    }
    final length = ByteData(4)..setUint32(0, data.length);
    final checksum = ByteData(4)..setUint32(0, (crc ^ 0xffffffff) & 0xffffffff);
    result.add(length.buffer.asUint8List());
    result.add(body);
    result.add(checksum.buffer.asUint8List());
  }

  final header = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8)
    ..setUint8(9, 6);
  chunk('IHDR', header.buffer.asUint8List());
  chunk('IDAT', compressed);
  chunk('IEND', []);
  return result.takeBytes();
}

/// Small raster PDF writer: each page embeds the same verified preview pixels.
/// No font substitution or missing Chinese glyphs in the receiving PDF viewer.
Uint8List _pdf(List<Uint8List> pages) {
  final out = BytesBuilder(copy: false);
  final offsets = <int>[0];
  void text(String value) => out.add(ascii.encode(value));
  void object(int id, String body, [Uint8List? stream]) {
    offsets.add(out.length);
    text('$id 0 obj\n$body');
    if (stream != null) {
      text('\nstream\n');
      out.add(stream);
      text('\nendstream');
    }
    text('\nendobj\n');
  }

  text('%PDF-1.4\n');
  object(1, '<< /Type /Catalog /Pages 2 0 R >>');
  object(
    2,
    '<< /Type /Pages /Count ${pages.length} /Kids [${List.generate(pages.length, (i) => '${3 + i * 3} 0 R').join(' ')}] >>',
  );
  for (var i = 0; i < pages.length; i++) {
    final id = 3 + i * 3;
    object(
      id,
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 450 700] /Resources << /XObject << /Im0 ${id + 1} 0 R >> >> /Contents ${id + 2} 0 R >>',
    );
    object(
      id + 1,
      '<< /Type /XObject /Subtype /Image /Width 900 /Height 1400 /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /FlateDecode /Length ${pages[i].length} >>',
      pages[i],
    );
    final commands = Uint8List.fromList(
      ascii.encode('q 450 0 0 700 0 0 cm /Im0 Do Q'),
    );
    object(id + 2, '<< /Length ${commands.length} >>', commands);
  }
  final xref = out.length;
  text('xref\n0 ${offsets.length}\n0000000000 65535 f \n');
  for (final offset in offsets.skip(1)) {
    text('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  text(
    'trailer\n<< /Size ${offsets.length} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n',
  );
  return out.takeBytes();
}
