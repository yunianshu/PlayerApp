import 'package:flutter/material.dart';
import '../widgets/app_toast.dart';

import '../core/calendar.dart';
import '../core/i18n.dart';
import '../core/theme.dart';
import '../models/run_record.dart';
import '../services/run_storage.dart';
import '../services/tracking_policies.dart';
import '../widgets/common.dart';

/// 手动补录：跑步机、忘带手机等无轨迹场景。
/// 保存后记录 source=manual，历史/统计正常计入，详情页不展示轨迹。
class ManualEntryPage extends StatefulWidget {
  const ManualEntryPage({super.key});

  @override
  State<ManualEntryPage> createState() => _ManualEntryPageState();
}

class _ManualEntryPageState extends State<ManualEntryPage> {
  late DateTime _day = Calendar.day(DateTime.now());
  final _timeCtrl = TextEditingController(text: _initialTimeText());
  final _durationCtrl = TextEditingController();
  final _distanceCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String? _error;
  bool _saving = false;

  static String _initialTimeText() {
    final n = DateTime.now();
    return '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _timeCtrl.dispose();
    _durationCtrl.dispose();
    _distanceCtrl.dispose();
    _titleCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final now = DateTime.now();
    final error = _validate(now);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final durationS = parseDurationInput(_durationCtrl.text)!;
      final distanceKm = double.parse(_distanceCtrl.text.trim());
      final timeParts = _timeCtrl.text.trim().split(':');
      final start = DateTime(
        _day.year,
        _day.month,
        _day.day,
        int.parse(timeParts[0]),
        int.parse(timeParts[1]),
      );
      final record = RunRecord(
        sessionId:
            'manual-${start.microsecondsSinceEpoch}-${DateTime.now().microsecondsSinceEpoch % 100000}',
        start: start,
        end: start.add(Duration(seconds: durationS)),
        distanceM: distanceKm * 1000,
        durationS: durationS,
        calories: (distanceKm * 65 * 1.036).round(),
        climbM: 0,
        source: RunRecord.sourceManual,
        title: _titleCtrl.text.trim(),
        notes: _notesCtrl.text.trim(),
      );
      await RunStorage.save(record, const []);
      if (!mounted) return;
      showAppToast(context, '补录成功'.tr);
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '补录失败，请重试'.tr;
      });
    }
  }

  String? _validate(DateTime now) {
    final duration = parseDurationInput(_durationCtrl.text);
    if (duration == null) return '请输入有效时长，如 30:00 或 90'.tr;
    final distance = double.tryParse(_distanceCtrl.text.trim());
    if (distance == null ||
        !distance.isFinite ||
        distance < 0.1 ||
        distance > 200) {
      return '请输入有效距离（0.1 – 200 公里）'.tr;
    }
    final timeMatch = RegExp(r'^(\d{1,2}):([0-5]\d)$')
        .firstMatch(_timeCtrl.text.trim());
    if (timeMatch == null || int.parse(timeMatch.group(1)!) > 23) {
      return '时间格式应为 时:分'.tr;
    }
    if (DateTime(_day.year, _day.month, _day.day).isAfter(Calendar.day(now))) {
      return '日期不能晚于今天'.tr;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      body: Backdrop(
        child: SafeArea(
          top: false,
          bottom: false,
          child: ListView(
            physics: dampedPhysics,
            padding: EdgeInsets.fromLTRB(
              20,
              MediaQuery.of(context).padding.top + 8,
              20,
              32,
            ),
            children: [
              Row(
                children: [
                  CircleBtn(
                    Icons.chevron_left_rounded,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  Column(
                    children: [
                      Text(
                        '手动补录'.tr,
                        style: TextStyle(
                          fontFamily: c.isEditorial ? 'Playfair Display' : null,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: c.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  const SizedBox(width: 38),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '补录一次跑步（跑步机、忘带手机等场景）'.tr,
                style: TextStyle(fontSize: 12, color: c.textSecondary),
              ),
              const SizedBox(height: 18),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _dateRow(c),
                    const SizedBox(height: 14),
                    _field(
                      c,
                      label: '开始时间'.tr,
                      controller: _timeCtrl,
                      hint: '08:30',
                      icon: Icons.schedule_outlined,
                    ),
                    const SizedBox(height: 14),
                    _field(
                      c,
                      label: '时长（分:秒）'.tr,
                      controller: _durationCtrl,
                      hint: '45:00',
                      icon: Icons.timer_outlined,
                    ),
                    const SizedBox(height: 14),
                    _field(
                      c,
                      label: '距离（公里）'.tr,
                      controller: _distanceCtrl,
                      hint: '6.50',
                      icon: Icons.route_outlined,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _field(
                      c,
                      label: '标题（可选）'.tr,
                      controller: _titleCtrl,
                      hint: '跑步机 5km'.tr,
                      icon: Icons.title_outlined,
                    ),
                    const SizedBox(height: 14),
                    _field(
                      c,
                      label: '备注（可选）'.tr,
                      controller: _notesCtrl,
                      hint: '',
                      icon: Icons.notes_outlined,
                      maxLines: 3,
                    ),
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(fontSize: 12, color: c.danger)),
              ],
              const SizedBox(height: 18),
              PrimaryButton(
                label: _saving ? '保存中…'.tr : '保存'.tr,
                onTap: _saving ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dateRow(AppPalette c) {
    final today = Calendar.day(DateTime.now());
    final canForward = _day.isBefore(today);
    return Row(
      children: [
        IconLabel(Icons.calendar_today_outlined, '日期'.tr, size: 13),
        const Spacer(),
        _dateArrow(c, Icons.chevron_left_rounded, () {
          setState(() => _day = Calendar.addDays(_day, -1));
        }),
        const SizedBox(width: 10),
        Text(
          _dateLabel(_day),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: c.textPrimary,
          ),
        ),
        const SizedBox(width: 10),
        _dateArrow(
          c,
          Icons.chevron_right_rounded,
          canForward
              ? () => setState(() => _day = Calendar.addDays(_day, 1))
              : null,
        ),
      ],
    );
  }

  String _dateLabel(DateTime day) {
    final today = Calendar.day(DateTime.now());
    final diff = Calendar.daysBetween(today, day);
    if (diff == 0) return '今天'.tr;
    if (diff == -1) return '昨天'.tr;
    if (LocaleController.instance.isEnglish) {
      return '${enMonthAbbr[day.month - 1]} ${day.day}';
    }
    return '${day.month}月${day.day}日';
  }

  Widget _dateArrow(AppPalette c, IconData icon, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: c.surface2, shape: BoxShape.circle),
        child: Icon(
          icon,
          size: 18,
          color: onTap == null ? c.textMuted : c.textPrimary,
        ),
      ),
    );
  }

  Widget _field(
    AppPalette c, {
    required String label,
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconLabel(icon, label, size: 13),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          enabled: !_saving,
          keyboardType: keyboardType,
          maxLines: maxLines,
          style: TextStyle(fontSize: 15, color: c.textPrimary),
          decoration: InputDecoration(
            isDense: true,
            hintText: hint.isEmpty ? null : hint,
            hintStyle: TextStyle(fontSize: 13, color: c.textMuted),
            filled: true,
            fillColor: c.surface2,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }
}
