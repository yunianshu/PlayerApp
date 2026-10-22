import 'package:flutter/material.dart';

import '../widgets/exercise_video.dart';
import '../widgets/muscle_diagram.dart';

/// 跑步协助课程的单一动作步骤。
class CourseStep {
  const CourseStep({
    required this.name,
    required this.tip,
    required this.seconds,
    required this.icon,
    required this.anim,
    this.primaryMuscles = const {},
    this.secondaryMuscles = const {},
    this.twoSided = false,
  });

  /// 动作名称（中文即 i18n key，英文经 _en 字典翻译）。
  final String name;

  /// 动作要点提示。
  final String tip;

  /// 该步骤时长（秒）。
  final int seconds;

  /// 步骤图标。
  final IconData icon;

  /// 步骤的真人演示视频（Keep 同款"每步有画面"体验）。
  final ExerciseAnim anim;

  /// 主发力肌群（肌群图示深红高亮）。
  final Set<MuscleGroup> primaryMuscles;

  /// 辅助发力肌群（浅红高亮）。
  final Set<MuscleGroup> secondaryMuscles;

  /// 单侧动作（中途需要"换边"提示；交替类动作如开合跳不算）。
  final bool twoSided;
}

/// 课程过程中的整点播报决策（纯函数，便于测试）。
/// [remaining] 为当前步骤剩余秒数；返回 null 表示这一秒不播报。
/// 对齐 Keep 的全程语音引导：换边/时间过半 + 剩余 10 秒/5 秒倒计时。
String? courseAnnouncement({
  required int remaining,
  required int seconds,
  required bool twoSided,
}) {
  final half = seconds ~/ 2;
  if (remaining == half && remaining > 5) {
    return twoSided ? '换边' : (seconds >= 45 ? '时间过半' : null);
  }
  if (remaining == 10 && seconds > 12 && half != 10) return '还剩10秒';
  if (remaining == 5 && seconds > 8 && half != 5) return '还剩5秒';
  return null;
}

/// 一节协助课程（跑前热身 / 跑后拉伸）：按顺序自动推进的动作序列。
class AssistCourse {
  const AssistCourse({required this.title, required this.steps});

  final String title;
  final List<CourseStep> steps;

  Duration get total =>
      Duration(seconds: steps.fold(0, (sum, s) => sum + s.seconds));
}

/// 跑前热身：唤醒心率与关节，约 3 分半。
/// 参照主流跑步 App（Keep 等）的动态热身编排：自下而上激活踝、髋、核心。
const warmupCourse = AssistCourse(
  title: '跑前热身',
  steps: [
    CourseStep(
      name: '原地慢跑',
      tip: '轻盈落地，逐渐把心率带起来',
      seconds: 30,
      icon: Icons.directions_run,
      anim: ExerciseAnim.jogInPlace,
      primaryMuscles: {MuscleGroup.quads, MuscleGroup.calves},
      secondaryMuscles: {MuscleGroup.core},
    ),
    CourseStep(
      name: '踝关节环绕',
      tip: '脚尖点地画最大的圆，双脚交替',
      seconds: 30,
      icon: Icons.rotate_right,
      anim: ExerciseAnim.ankleCircle,
      primaryMuscles: {MuscleGroup.calves},
      secondaryMuscles: {},
    ),
    CourseStep(
      name: '开合跳',
      tip: '落地屈膝缓冲，保持稳定节奏',
      seconds: 30,
      icon: Icons.fitness_center,
      anim: ExerciseAnim.jumpingJack,
      primaryMuscles: {MuscleGroup.shoulders, MuscleGroup.calves},
      secondaryMuscles: {MuscleGroup.quads},
    ),
    CourseStep(
      name: '弓步转体',
      tip: '前膝对准脚尖，转体看向后方',
      seconds: 40,
      icon: Icons.accessibility_new,
      anim: ExerciseAnim.lungeTwist,
      primaryMuscles: {MuscleGroup.quads, MuscleGroup.glutes},
      secondaryMuscles: {MuscleGroup.core, MuscleGroup.back},
    ),
    CourseStep(
      name: '高抬腿',
      tip: '大腿抬至水平，核心收紧不后仰',
      seconds: 30,
      icon: Icons.flash_on,
      anim: ExerciseAnim.highKnees,
      primaryMuscles: {MuscleGroup.quads, MuscleGroup.hipFlexors},
      secondaryMuscles: {MuscleGroup.core},
    ),
    CourseStep(
      name: '腿后侧动态拉伸',
      tip: '直腿体前屈，感受大腿后侧发力',
      seconds: 40,
      icon: Icons.straighten,
      anim: ExerciseAnim.hamstringSwing,
      primaryMuscles: {MuscleGroup.hamstrings},
      secondaryMuscles: {MuscleGroup.calves, MuscleGroup.glutes},
    ),
  ],
);

/// 跑后拉伸：静态拉伸主要肌群，共 5 分钟（45 秒 × 6 + 深呼吸 30 秒）。
/// 每个动作默认双侧轮流；配合深呼吸让心率缓缓回落。
const stretchCourse = AssistCourse(
  title: '跑后拉伸',
  steps: [
    CourseStep(
      name: '大腿前侧拉伸',
      tip: '手扶脚背向臀部收，两侧各约 20 秒',
      seconds: 45,
      icon: Icons.accessibility_new,
      anim: ExerciseAnim.quadStretch,
      primaryMuscles: {MuscleGroup.quads},
      secondaryMuscles: {MuscleGroup.hipFlexors},
      twoSided: true,
    ),
    CourseStep(
      name: '大腿后侧拉伸',
      tip: '直腿勾脚尖，背部平直向前压',
      seconds: 45,
      icon: Icons.straighten,
      anim: ExerciseAnim.hamstringStretch,
      primaryMuscles: {MuscleGroup.hamstrings},
      secondaryMuscles: {MuscleGroup.calves, MuscleGroup.back},
      twoSided: true,
    ),
    CourseStep(
      name: '小腿拉伸',
      tip: '后腿伸直脚跟踩地，前腿弓步下压',
      seconds: 45,
      icon: Icons.south,
      anim: ExerciseAnim.calfStretch,
      primaryMuscles: {MuscleGroup.calves},
      secondaryMuscles: {MuscleGroup.hamstrings},
      twoSided: true,
    ),
    CourseStep(
      name: '臀部拉伸',
      tip: '脚踝搭在对侧膝上，臀部向后坐',
      seconds: 45,
      icon: Icons.airline_seat_recline_normal,
      anim: ExerciseAnim.gluteStretch,
      primaryMuscles: {MuscleGroup.glutes},
      secondaryMuscles: {MuscleGroup.back},
      twoSided: true,
    ),
    CourseStep(
      name: '髋屈肌拉伸',
      tip: '弓步下压，骨盆微微后倾',
      seconds: 45,
      icon: Icons.swap_horiz,
      anim: ExerciseAnim.hipFlexorStretch,
      primaryMuscles: {MuscleGroup.hipFlexors, MuscleGroup.quads},
      secondaryMuscles: {MuscleGroup.glutes},
      twoSided: true,
    ),
    CourseStep(
      name: '大腿外侧拉伸',
      tip: '前腿交叉，俯身向侧下方压',
      seconds: 45,
      icon: Icons.self_improvement,
      anim: ExerciseAnim.itBandStretch,
      primaryMuscles: {MuscleGroup.quads},
      secondaryMuscles: {MuscleGroup.glutes, MuscleGroup.back},
      twoSided: true,
    ),
    CourseStep(
      name: '深呼吸放松',
      tip: '鼻吸口呼，让心率缓缓回落',
      seconds: 30,
      icon: Icons.air,
      anim: ExerciseAnim.breathing,
      primaryMuscles: {MuscleGroup.core},
      secondaryMuscles: {},
    ),
  ],
);
