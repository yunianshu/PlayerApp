import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Circular completion control with a full-size keyboard/touch target.
/// Selection is owned by the persisted training state, not by this animation.
class TrainingCompletionToggle extends StatelessWidget {
  const TrainingCompletionToggle({
    super.key,
    required this.value,
    required this.label,
    required this.palette,
    required this.onPressed,
    this.busy = false,
    this.focusNode,
    this.autofocus = false,
  });

  final bool value;
  final String label;
  final AppPalette palette;
  final VoidCallback? onPressed;
  final bool busy;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    final duration = MediaQuery.of(context).disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 220);
    final accent = enabled || busy
        ? palette.accent
        : scaleAlpha(palette.accent, .35);
    final ring = enabled || busy
        ? palette.textSecondary
        : scaleAlpha(palette.textSecondary, .35);
    final check = palette.isDark ? palette.bg : palette.onAccent;

    return MergeSemantics(
      child: Semantics(
        label: busy ? '$label，正在保存' : label,
        checked: value,
        enabled: enabled,
        child: IconButton(
          focusNode: focusNode,
          autofocus: autofocus,
          onPressed: enabled ? onPressed : null,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 48, height: 48),
          style: IconButton.styleFrom(
            minimumSize: const Size(48, 48),
            maximumSize: const Size(48, 48),
            shape: const CircleBorder(),
            backgroundColor: Colors.transparent,
            focusColor: palette.accentSoft,
            hoverColor: palette.accentSoft,
            highlightColor: palette.accentSoft,
          ),
          icon: AnimatedScale(
            duration: duration,
            curve: Curves.easeOutCubic,
            scale: value ? 1 : .9,
            child: AnimatedContainer(
              key: const ValueKey('training-completion-circle'),
              duration: duration,
              curve: Curves.easeOutCubic,
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: value ? accent : Colors.transparent,
                border: Border.all(color: value ? accent : ring, width: 1.7),
              ),
              alignment: Alignment.center,
              child: AnimatedSwitcher(
                duration: duration,
                reverseDuration: duration,
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: .65, end: 1).animate(animation),
                    child: child,
                  ),
                ),
                child: busy
                    ? Icon(
                        Icons.more_horiz_rounded,
                        key: const ValueKey('saving'),
                        size: 17,
                        color: value ? check : ring,
                      )
                    : value
                    ? Icon(
                        Icons.check_rounded,
                        key: const ValueKey('checked'),
                        size: 18,
                        color: check,
                      )
                    : const SizedBox(
                        key: ValueKey('unchecked'),
                        width: 18,
                        height: 18,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
