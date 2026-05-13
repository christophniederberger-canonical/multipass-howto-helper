import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lighthouse_agent/ui/permission_dialog.dart';

void main() {
  group('PermissionDialog', () {
    testWidgets('shows dialog with correct title and content', (WidgetTester tester) async {
      const dialog = PermissionDialog();
      final decisionCompleter = Completer<PermissionDecision>();

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  final decision = await dialog.requestTutorialPermission(
                    context: context,
                    origin: 'https://example.com',
                  );
                  decisionCompleter.complete(decision);
                },
                child: const Text('Show Dialog'),
              );
            },
          ),
        ),
      );

      // Tap button to show dialog
      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      // Verify dialog content
      expect(find.text('Allow Tutorial Commands?'), findsOneWidget);
      expect(
        find.text('A tutorial from https://example.com wants to run commands in a Multipass VM.'),
        findsOneWidget,
      );
      expect(find.text('Deny'), findsOneWidget);
      expect(find.text('Allow'), findsOneWidget);
    });

    testWidgets('returns allow when Allow button is tapped', (WidgetTester tester) async {
      const dialog = PermissionDialog();
      final decisionCompleter = Completer<PermissionDecision>();

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  final decision = await dialog.requestTutorialPermission(
                    context: context,
                    origin: 'https://example.com',
                  );
                  decisionCompleter.complete(decision);
                },
                child: const Text('Show Dialog'),
              );
            },
          ),
        ),
      );

      // Tap button to show dialog
      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      // Tap Allow
      await tester.tap(find.text('Allow'));
      await tester.pumpAndSettle();

      final decision = await decisionCompleter.future;
      expect(decision, PermissionDecision.allow);
    });

    testWidgets('returns deny when Deny button is tapped', (WidgetTester tester) async {
      const dialog = PermissionDialog();
      final decisionCompleter = Completer<PermissionDecision>();

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  final decision = await dialog.requestTutorialPermission(
                    context: context,
                    origin: 'https://example.com',
                  );
                  decisionCompleter.complete(decision);
                },
                child: const Text('Show Dialog'),
              );
            },
          ),
        ),
      );

      // Tap button to show dialog
      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      // Tap Deny
      await tester.tap(find.text('Deny'));
      await tester.pumpAndSettle();

      final decision = await decisionCompleter.future;
      expect(decision, PermissionDecision.deny);
    });

    testWidgets('dialog is not barrier dismissible', (WidgetTester tester) async {
      const dialog = PermissionDialog();
      final decisionCompleter = Completer<PermissionDecision>();

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  final decision = await dialog.requestTutorialPermission(
                    context: context,
                    origin: 'https://example.com',
                  );
                  decisionCompleter.complete(decision);
                },
                child: const Text('Show Dialog'),
              );
            },
          ),
        ),
      );

      // Tap button to show dialog
      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      // Tap outside dialog (barrier)
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // Dialog should still be visible
      expect(find.text('Allow Tutorial Commands?'), findsOneWidget);

      // Decision should not have been completed yet
      expect(decisionCompleter.isCompleted, isFalse);
    });

    testWidgets('Allow button is styled as FilledButton', (WidgetTester tester) async {
      const dialog = PermissionDialog();

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  await dialog.requestTutorialPermission(
                    context: context,
                    origin: 'https://example.com',
                  );
                },
                child: const Text('Show Dialog'),
              );
            },
          ),
        ),
      );

      // Tap button to show dialog
      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      // Verify Allow is a FilledButton
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.text('Allow'), findsOneWidget);

      // Verify Deny is a TextButton
      expect(find.byType(TextButton), findsOneWidget);
      expect(find.text('Deny'), findsOneWidget);
    });

    testWidgets('displays different origins correctly', (WidgetTester tester) async {
      const dialog = PermissionDialog();

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  await dialog.requestTutorialPermission(
                    context: context,
                    origin: 'http://localhost:3000',
                  );
                },
                child: const Text('Show Dialog'),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      expect(
        find.text('A tutorial from http://localhost:3000 wants to run commands in a Multipass VM.'),
        findsOneWidget,
      );
    });
  });
}
