import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Asks before an action: a compact alert with the app icon and stacked buttons on desktop, as
/// macOS presents one, and a standard dialog on phones.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final desktop = switch (defaultTargetPlatform) {
    TargetPlatform.macOS ||
    TargetPlatform.windows ||
    TargetPlatform.linux => true,
    _ => false,
  };
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      final confirmColor = destructive ? scheme.error : null;
      if (!desktop) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: confirmColor),
              onPressed: () => Navigator.pop(context, true),
              child: Text(confirmLabel),
            ),
          ],
        );
      }
      Widget button(String label, bool value, {bool primary = false}) =>
          SizedBox(
            width: double.infinity,
            height: 28,
            child: TextButton(
              autofocus: primary,
              style: TextButton.styleFrom(
                backgroundColor: primary && !destructive
                    ? scheme.primary
                    : scheme.surfaceContainer,
                foregroundColor: primary
                    ? (destructive ? scheme.error : scheme.onPrimary)
                    : scheme.onSurface,
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(7),
                ),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              onPressed: () => Navigator.pop(context, value),
              child: Text(label),
            ),
          );
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: SizedBox(
          width: 260,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ExcludeSemantics(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.asset(
                      'assets/inboxplus-logo.png',
                      width: 64,
                      height: 64,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11, height: 1.35),
                ),
                const SizedBox(height: 16),
                button(confirmLabel, true, primary: true),
                const SizedBox(height: 8),
                button('Cancel', false),
              ],
            ),
          ),
        ),
      );
    },
  );
  return confirmed == true;
}

Future<bool> confirmAccountRemoval(
  BuildContext context,
  String network,
) => confirmAction(
  context,
  title: 'Remove $network?',
  message:
      'Inbox+ attempts to sign out of $network and deletes its saved login, conversations and downloaded files from this device. If sign-out cannot be confirmed, remove this device in $network too. Your messages stay on $network itself. This cannot be undone. To keep the history in Inbox+, disconnect instead.',
  confirmLabel: 'Sign out and remove',
  destructive: true,
);

Future<bool> confirmClearMediaCache(BuildContext context) => confirmAction(
  context,
  title: 'Clear downloaded media?',
  message: 'Photos, videos and files download again when you open them. Messages, drafts and attachments you have not sent are kept.',
  confirmLabel: 'Clear Cache',
  destructive: true,
);
