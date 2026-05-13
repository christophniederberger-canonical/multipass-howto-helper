import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lighthouse_agent/main.dart';
import 'package:lighthouse_agent/models/message.dart';

void main() {
  testWidgets('Lighthouse status window smoke test', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const LighthouseApp());
    // Pump a few frames to let async operations complete
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Lighthouse Agent'), findsOneWidget);
    // Status window shows the app bar title and either VMs or loading state
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  group('MessageCodec', () {
    const codec = MessageCodec();

    test('encodes and decodes session_start', () {
      const msg = SessionStart(
        origin: 'https://ubuntu.com',
        tutorialUrl: 'https://ubuntu.com/tutorials/test',
      );
      final encoded = codec.encode(msg);
      final decoded = codec.decode(encoded);
      expect(decoded, isA<SessionStart>());
      final start = decoded as SessionStart;
      expect(start.origin, 'https://ubuntu.com');
      expect(start.tutorialUrl, 'https://ubuntu.com/tutorials/test');
    });

    test('encodes and decodes exec', () {
      const msg = Exec(sessionId: 'abc-123', command: 'echo hello');
      final encoded = codec.encode(msg);
      final decoded = codec.decode(encoded);
      expect(decoded, isA<Exec>());
      final exec = decoded as Exec;
      expect(exec.sessionId, 'abc-123');
      expect(exec.command, 'echo hello');
    });

    test('encodes and decodes session_ready', () {
      const msg = SessionReady(sessionId: 'abc-123', vmName: 'lighthouse-abc');
      final encoded = codec.encode(msg);
      final decoded = codec.decode(encoded);
      expect(decoded, isA<SessionReady>());
      final ready = decoded as SessionReady;
      expect(ready.sessionId, 'abc-123');
      expect(ready.vmName, 'lighthouse-abc');
    });

    test('encodes and decodes agent_error', () {
      const msg = AgentError(code: 'TEST', message: 'test error');
      final encoded = codec.encode(msg);
      final decoded = codec.decode(encoded);
      expect(decoded, isA<AgentError>());
      final err = decoded as AgentError;
      expect(err.code, 'TEST');
      expect(err.message, 'test error');
    });

    test('throws on unknown type', () {
      expect(
        () => codec.decode('{"type": "bogus"}'),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws on missing type', () {
      expect(
        () => codec.decode('{"foo": "bar"}'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
