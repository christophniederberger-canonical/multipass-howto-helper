import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum PermissionDecision { allow, deny }

class PermissionDialog {
  const PermissionDialog();

  /// Shows a native-style Allow/Deny dialog.
  /// Must be called with a valid [BuildContext].
  Future<PermissionDecision> requestTutorialPermission({
    required BuildContext context,
    required String origin,
    String? sessionId,
  }) async {
    return await showDialog<PermissionDecision>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Allow Tutorial Commands?"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("A tutorial from $origin wants to run commands in a Multipass VM."),
              const SizedBox(height: 16),
              const Text(
                'How to approve:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text('1. Find the authorization file created by the tutorial'),
              const Text('2. Review the commands it will run'),
              const Text('3. Click "Allow" to authorize this session'),
              if (sessionId != null) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text(
                      'Session ID: ',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Expanded(
                      child: SelectableText(
                        sessionId,
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 18),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: sessionId));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Session ID copied to clipboard'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      tooltip: 'Copy session ID',
                    ),
                  ],
                ),
              ],
            ],
          ),
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
