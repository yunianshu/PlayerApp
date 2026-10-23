import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme.dart';

_AppToastHandle? _visibleToast;

/// Short feedback is centered above routes and sheets, never behind the tab bar.
/// A newer message replaces the old one instead of queuing stale notifications.
void showAppToast(
  BuildContext context,
  String message, {
  Duration duration = const Duration(seconds: 4),
  String? actionLabel,
  VoidCallback? onAction,
}) {
  assert((actionLabel == null) == (onAction == null));
  if (!context.mounted || message.trim().isEmpty) return;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _visibleToast?.dismiss();
  final handle = _AppToastHandle();
  final theme = Theme.of(context);
  final accessibleNavigation = MediaQuery.of(context).accessibleNavigation;
  handle.entry = OverlayEntry(
    builder: (_) => Theme(
      data: theme,
      child: _AppToast(
        message: message,
        duration: accessibleNavigation && onAction != null ? null : duration,
        actionLabel: actionLabel,
        onAction: onAction,
        handle: handle,
      ),
    ),
  );
  _visibleToast = handle;
  overlay.insert(handle.entry!);
}

class _AppToastHandle {
  OverlayEntry? entry;

  void dismiss() {
    final current = entry;
    entry = null;
    if (identical(_visibleToast, this)) _visibleToast = null;
    current?.remove();
    current?.dispose();
  }

  // The navigator/overlay can go away before the timeout (including in tests).
  // Its widget owns the timer, so disposal never leaves a delayed callback that
  // tries to remove an entry from an already disposed overlay.
  void didUnmount() {
    if (identical(_visibleToast, this)) _visibleToast = null;
    // Parent overlay teardown can unmount us without an explicit dismissal.
    // Release the entry after tree finalization, never setState during dispose.
    if (entry != null) scheduleMicrotask(dismiss);
  }
}

class _AppToast extends StatefulWidget {
  const _AppToast({
    required this.message,
    required this.duration,
    required this.handle,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final Duration? duration;
  final String? actionLabel;
  final VoidCallback? onAction;
  final _AppToastHandle handle;

  @override
  State<_AppToast> createState() => _AppToastState();
}

class _AppToastState extends State<_AppToast> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.duration != null) {
      _timer = Timer(widget.duration!, widget.handle.dismiss);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.handle.didUnmount();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Positioned.fill(
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            16,
            24,
            16 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Semantics(
                key: const ValueKey('app-toast-announcement'),
                liveRegion: true,
                label: widget.message,
                container: true,
                child: Material(
                  key: const ValueKey('app-toast'),
                  color: colors.inverseSurface,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  elevation: 6,
                  clipBehavior: Clip.antiAlias,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ExcludeSemantics(
                          child: Text(
                            widget.message,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: colors.onInverseSurface),
                          ),
                        ),
                        if (widget.onAction != null)
                          TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: colors.inversePrimary,
                            ),
                            onPressed: () {
                              widget.handle.dismiss();
                              widget.onAction!();
                            },
                            child: Text(widget.actionLabel!),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
