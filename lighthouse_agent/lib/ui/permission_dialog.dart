import 'package:flutter/material.dart';

enum PermissionDecision { allow, deny }

class PermissionDialog {
  const PermissionDialog();

  /// Shows a native-style Allow/Deny dialog.
  /// Must be called with a valid [BuildContext].
  Future<PermissionDecision> requestTutorialPermission({
    required BuildContext context,
    required String origin,
  }) async {
    return await showDialog<PermissionDecision>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Allow Tutorial Commands?"),
          content: Text("A tutorial from $origin wants to run commands in a Multipass VM."),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(PermissionDecision.deny);
              },
              child: const Text("Deny"),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop(PermissionDecision.allow);
              },
              child: const Text("Allow"),
            ),
          ],
        );
      },
    ) ?? PermissionDecision.deny; // Default to deny if dialog is dismissed unexpectedly
  }
}
