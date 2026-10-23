import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/i18n.dart';
import '../core/theme.dart';
import '../services/courses.dart';
import '../widgets/common.dart';
import 'course_page.dart';

/// 课程列表页（底栏 tab）：跑前热身 / 跑后拉伸随时可练。
/// 参照 Keep 的课程列表形态：图标 + 名称 + 简介 + 时长动作数。
class CoursesPage extends StatelessWidget {
  const CoursesPage({super.key});

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleController>();
    final c = context.colors;
    final en = LocaleController.instance.isEnglish;
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
              tabScrollBottomPadding(context),
            ),
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (c.isEditorial) ...[
                    Text('COURSES', style: kickerStyle(c)),
                    const SizedBox(height: 2),
                  ],
                  Text(
                    '跑步课程'.tr,
                    style: TextStyle(
                      fontFamily: c.isEditorial ? 'Playfair Display' : null,
                      fontFamilyFallback: c.isEditorial
                          ? const ['Noto Sans SC']
                          : null,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: c.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '协助课程'.tr,
                style: TextStyle(fontSize: 12, color: c.textMuted),
              ),
              const SizedBox(height: 16),
              _courseCard(
                context,
                c,
                course: warmupCourse,
                finishedTitle: '热身完成！',
                icon: Icons.directions_run,
                intro: en
                    ? 'Dynamic moves to wake up joints and muscles before you run'
                    : '动态激活踝、髋与核心，降低岔气与拉伤风险',
              ),
              const SizedBox(height: 12),
              _courseCard(
                context,
                c,
                course: stretchCourse,
                finishedTitle: '拉伸完成！',
                icon: Icons.self_improvement,
                intro: en
                    ? 'Static stretches for the major muscle groups after you run'
                    : '静态拉伸主要肌群，配合深呼吸帮助身体恢复',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _courseCard(
    BuildContext context,
    AppPalette c, {
    required AssistCourse course,
    required String finishedTitle,
    required IconData icon,
    required String intro,
  }) {
    final en = LocaleController.instance.isEnglish;
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () =>
            Navigator.of(context).push(CoursePage.route(course, finishedTitle)),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: c.surface2,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 22, color: c.accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    course.title.tr,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    intro,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: c.textSecondary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    en
                        ? '${course.steps.length} moves · about '
                              '${course.total.inMinutes} min'
                        : '${course.steps.length}个动作 · 约'
                              '${course.total.inMinutes}分钟',
                    style: TextStyle(fontSize: 10, color: c.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.play_circle_outline, size: 26, color: c.accent),
          ],
        ),
      ),
    );
  }
}
