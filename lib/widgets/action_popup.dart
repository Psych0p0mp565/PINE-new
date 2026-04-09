library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Small helper for consistent user-visible responses:
/// - blocking progress dialogs for in-flight actions
/// - success/error dialogs for action outcomes
class ActionPopup {
  static Future<void> showSuccess(
    BuildContext context, {
    required String message,
    String title = 'Success',
  }) {
    return _showMessageDialog(
      context,
      title: title,
      message: message,
      icon: Icons.check_circle,
      iconColor: AppTheme.primaryGreen,
    );
  }

  /// Single success dialog that stays open for [readSeconds] (countdown shown), then closes.
  /// Merge save + optional GPS note into [message] before calling.
  static Future<void> showSuccessAutoDismiss(
    BuildContext context, {
    required String message,
    String title = 'Success',
    int readSeconds = 3,
    String Function(int remaining)? countdownLabel,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return _AutoDismissSuccessDialog(
          title: title,
          message: message,
          readSeconds: readSeconds,
          countdownLabel:
              countdownLabel ?? (int r) => 'Continuing in $r…',
          onFinish: () {
            if (dialogContext.mounted) {
              Navigator.of(dialogContext).pop();
            }
          },
        );
      },
    );
  }

  static Future<void> showError(
    BuildContext context, {
    required String message,
    String title = 'Error',
  }) {
    return _showMessageDialog(
      context,
      title: title,
      message: message,
      icon: Icons.error_outline,
      iconColor: AppTheme.errorRed,
    );
  }

  /// Neutral notice (e.g. no detections, nothing to export).
  static Future<void> showInfo(
    BuildContext context, {
    required String message,
    String title = 'Notice',
  }) {
    return _showMessageDialog(
      context,
      title: title,
      message: message,
      icon: Icons.info_outline,
      iconColor: AppTheme.accentOrange,
    );
  }

  static Future<void> _showMessageDialog(
    BuildContext context, {
    required String title,
    required String message,
    required IconData icon,
    required Color iconColor,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(icon, color: iconColor),
              const SizedBox(width: 10),
              Expanded(child: Text(title)),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400, maxHeight: 320),
            child: SingleChildScrollView(
              child: Text(message),
            ),
          ),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryGreen,
                foregroundColor: Colors.white,
              ),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }
}

class _AutoDismissSuccessDialog extends StatefulWidget {
  const _AutoDismissSuccessDialog({
    required this.title,
    required this.message,
    required this.readSeconds,
    required this.countdownLabel,
    required this.onFinish,
  });

  final String title;
  final String message;
  final int readSeconds;
  final String Function(int remaining) countdownLabel;
  final VoidCallback onFinish;

  @override
  State<_AutoDismissSuccessDialog> createState() =>
      _AutoDismissSuccessDialogState();
}

class _AutoDismissSuccessDialogState extends State<_AutoDismissSuccessDialog> {
  int _elapsed = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.readSeconds <= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onFinish();
      });
      return;
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_elapsed + 1 >= widget.readSeconds) {
        _timer?.cancel();
        widget.onFinish();
        return;
      }
      setState(() => _elapsed++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final int remaining = widget.readSeconds - _elapsed;
    final double progress = widget.readSeconds <= 0
        ? 1.0
        : _elapsed / widget.readSeconds;

    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Row(
          children: <Widget>[
            const Icon(Icons.check_circle, color: AppTheme.primaryGreen),
            const SizedBox(width: 10),
            Expanded(child: Text(widget.title)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400, maxHeight: 280),
              child: SingleChildScrollView(
                child: Text(widget.message),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              remaining <= 0 ? '' : widget.countdownLabel(remaining),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: Colors.grey.shade200,
                color: AppTheme.primaryGreen,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ActionPopupController {
  bool _shown = false;
  BuildContext? _dialogContext;

  void showBlockingProgress(
    BuildContext context, {
    required String message,
  }) {
    if (_shown) return;
    _shown = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        _dialogContext = ctx;
        return PopScope(
          canPop: false,
          child: AlertDialog(
            content: Row(
              children: [
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    message,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void close() {
    if (!_shown) return;
    final ctx = _dialogContext;
    _dialogContext = null;
    _shown = false;
    if (ctx != null && ctx.mounted) {
      Navigator.of(ctx, rootNavigator: true).pop();
    }
  }
}

