library;

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
          content: Text(message),
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

