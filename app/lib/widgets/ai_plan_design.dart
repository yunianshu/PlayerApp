import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../core/theme_controller.dart';

/// Visual language scoped to AI planning screens; never changes global settings.
class PlanDesign {
  final AppPalette palette;
  const PlanDesign._(this.palette);

  static PlanDesign of(BuildContext context, {bool listen = true}) {
    final controller = Provider.of<ThemeController?>(context, listen: listen);
    final base = Theme.of(context);
    return PlanDesign._(
      controller?.effectivePalette ??
          (base.scaffoldBackgroundColor == AppPalette.editorial.bg
              ? AppPalette.editorial
              : base.brightness == Brightness.dark
              ? AppPalette.dark
              : AppPalette.light),
    );
  }

  static ThemeData theme(BuildContext context) {
    final p = of(context, listen: false).palette;
    final base = Theme.of(context);
    final primary = p.isEditorial ? p.textPrimary : p.accent;
    final onPrimary = p.isEditorial || p.isDark ? p.bg : p.onAccent;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
    );
    final scheme = base.colorScheme.copyWith(
      brightness: p.isDark ? Brightness.dark : Brightness.light,
      primary: primary,
      onPrimary: onPrimary,
      primaryContainer: p.accentSoft,
      onPrimaryContainer: p.textPrimary,
      primaryFixed: p.accent,
      primaryFixedDim: p.accentDeep,
      onPrimaryFixed: p.isDark ? p.bg : p.onAccent,
      onPrimaryFixedVariant: p.textPrimary,
      secondary: primary,
      onSecondary: onPrimary,
      secondaryContainer: p.surface2,
      onSecondaryContainer: p.textPrimary,
      secondaryFixed: p.accent,
      secondaryFixedDim: p.accentDeep,
      onSecondaryFixed: p.isDark ? p.bg : p.onAccent,
      onSecondaryFixedVariant: p.textPrimary,
      tertiary: primary,
      onTertiary: onPrimary,
      tertiaryContainer: p.accentSoft,
      onTertiaryContainer: p.textPrimary,
      tertiaryFixed: p.accent,
      tertiaryFixedDim: p.accentDeep,
      onTertiaryFixed: p.isDark ? p.bg : p.onAccent,
      onTertiaryFixedVariant: p.textPrimary,
      error: p.danger,
      onError: Colors.white,
      errorContainer: p.dangerSoft,
      onErrorContainer: p.danger,
      surface: p.surface,
      onSurface: p.textPrimary,
      surfaceDim: p.surface2,
      surfaceBright: p.surface,
      surfaceContainerLowest: p.bg,
      surfaceContainerLow: p.surface,
      surfaceContainer: p.surface2,
      surfaceContainerHigh: p.surface2,
      surfaceContainerHighest: p.surface2,
      onSurfaceVariant: p.textSecondary,
      outline: p.stroke,
      outlineVariant: p.divider,
      shadow: p.cardShadow,
      scrim: Colors.black54,
      inverseSurface: p.inverseSurface,
      onInverseSurface: p.onInverse,
      inversePrimary: p.onInverseAccent,
      surfaceTint: Colors.transparent,
    );
    final input = InputDecorationThemeData(
      filled: true,
      fillColor: p.surface2,
      labelStyle: appTextStyle(p, color: p.textSecondary),
      hintStyle: appTextStyle(p, color: p.textMuted),
      helperStyle: appTextStyle(p, color: p.textSecondary, fontSize: 12),
      errorStyle: appTextStyle(p, color: p.danger, fontSize: 12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: BorderSide(color: p.stroke),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: BorderSide(color: p.stroke),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: BorderSide(color: primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: BorderSide(color: p.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: BorderSide(color: p.danger, width: 2),
      ),
    );
    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: p.bg,
      canvasColor: p.surface,
      cardColor: p.surface,
      dividerColor: p.divider,
      focusColor: p.accentSoft,
      hoverColor: p.accentSoft,
      highlightColor: p.accentSoft,
      splashColor: p.accentSoft,
      disabledColor: p.textMuted,
      textTheme: base.textTheme.apply(
        bodyColor: p.textPrimary,
        displayColor: p.textPrimary,
        fontFamily: p.isEditorial ? 'Noto Sans SC' : null,
      ),
      iconTheme: IconThemeData(color: p.textSecondary),
      appBarTheme: AppBarThemeData(
        backgroundColor: p.bg,
        foregroundColor: p.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      inputDecorationTheme: input,
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: primary,
        selectionColor: p.accentSoft,
        selectionHandleColor: primary,
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        inputDecorationTheme: input,
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(p.surface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        textStyle: appTextStyle(p),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        titleTextStyle: appTextStyle(
          p,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: appTextStyle(p, height: 1.5),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: p.surface2,
        headerForegroundColor: p.textPrimary,
        todayForegroundColor: WidgetStatePropertyAll(primary),
        todayBorder: BorderSide(color: primary),
        rangeSelectionBackgroundColor: p.accentSoft,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.surface2,
        selectedColor: p.accentSoft,
        checkmarkColor: primary,
        side: BorderSide(color: p.stroke),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        labelStyle: appTextStyle(p, fontSize: 13),
        secondaryLabelStyle: appTextStyle(p, fontSize: 13),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? onPrimary
              : p.textSecondary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? primary : p.surface2,
        ),
        trackOutlineColor: WidgetStatePropertyAll(p.stroke),
      ),
      checkboxTheme: CheckboxThemeData(
        checkColor: WidgetStatePropertyAll(onPrimary),
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? primary
              : Colors.transparent,
        ),
        side: BorderSide(color: p.textMuted),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          minimumSize: const Size(48, 52),
          shape: shape,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          surfaceTintColor: Colors.transparent,
          shape: shape,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: BorderSide(color: p.stroke),
          shape: shape,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: primary, shape: shape),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primary,
        linearTrackColor: p.surface2,
        circularTrackColor: p.surface2,
      ),
    );
  }
}

class PlanSection extends StatelessWidget {
  final String eyebrow, title;
  final String? subtitle;
  final Widget child;
  const PlanSection({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.child,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final p = PlanDesign.of(context).palette;
    return AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: p.stroke),
        boxShadow: p.isLight
            ? [
                BoxShadow(
                  color: p.cardShadow,
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            eyebrow.toUpperCase(),
            style: kickerStyle(
              p,
              color: p.isEditorial ? p.textSecondary : p.accent,
              size: 10,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: appTextStyle(
              p,
              fontSize: 21,
              fontWeight: FontWeight.w800,
              height: 1.3,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle!,
              style: appTextStyle(p, color: p.textSecondary, height: 1.55),
            ),
          ],
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }
}

class PlanHero extends StatelessWidget {
  final String eyebrow, title, subtitle;
  final List<Widget> children;
  const PlanHero({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    this.children = const [],
  });

  @override
  Widget build(BuildContext context) {
    final p = PlanDesign.of(context).palette;
    final foreground = p.isEditorial ? p.onInverse : p.textPrimary;
    final accent = p.accent;
    return AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: p.isEditorial ? p.inverseSurface : p.surface,
        gradient: p.isLight
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [p.surface, Color.alphaBlend(p.accentSoft, p.surface)],
              )
            : null,
        border: Border.all(
          color: p.isEditorial ? p.inverseSurface : p.accentStroke,
        ),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 4,
                  height: 30,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    eyebrow.toUpperCase(),
                    style: kickerStyle(
                      p,
                      color: p.isEditorial ? p.accent : p.textSecondary,
                      size: 11,
                    ),
                  ),
                ),
                Icon(Icons.auto_awesome_outlined, color: accent, size: 24),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: appTextStyle(
                p,
                fontSize: 30,
                fontWeight: FontWeight.w800,
                height: 1.2,
                letterSpacing: -.8,
                color: foreground,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              subtitle,
              style: appTextStyle(
                p,
                color: p.isEditorial ? p.onInverse : p.textSecondary,
                height: 1.65,
              ),
            ),
            if (children.isNotEmpty) ...[
              const SizedBox(height: 22),
              Wrap(spacing: 10, runSpacing: 10, children: children),
            ],
          ],
        ),
      ),
    );
  }
}

class PlanMetric extends StatelessWidget {
  final String label, value;
  final IconData? icon;
  const PlanMetric({
    super.key,
    required this.label,
    required this.value,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final p = PlanDesign.of(context).palette;
    return AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      constraints: const BoxConstraints(maxWidth: 240),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: p.surface2,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: p.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 18,
              color: p.isEditorial ? p.textPrimary : p.accent,
            ),
            const SizedBox(height: 8),
          ],
          Text(
            value,
            style: appTextStyle(
              p,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: appTextStyle(
              p,
              color: p.textSecondary,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class PlanNotice extends StatelessWidget {
  final List<String> messages;
  const PlanNotice({super.key, required this.messages});

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) return const SizedBox.shrink();
    final p = PlanDesign.of(context).palette;
    return AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.surface2,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: p.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < messages.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: p.textSecondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    messages[i],
                    style: appTextStyle(
                      p,
                      color: p.textSecondary,
                      fontSize: 13,
                      height: 1.55,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
