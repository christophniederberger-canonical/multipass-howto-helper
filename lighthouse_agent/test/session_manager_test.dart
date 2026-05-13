import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:lighthouse_agent/agent/session_manager.dart';
import 'package:lighthouse_agent/models/session.dart';

void main() {
  group('SessionManager', () {
    late SessionManager manager;

    setUp(() {
      manager = SessionManager();
    });

    test('create returns a session with pending state and auto-generated IDs', () {
      final session = manager.create(
        origin: 'https://example.com',
        tutorialUrl: 'https://example.com/tutorial',
      );

      expect(session.sessionId, isNotEmpty);
      expect(session.vmName, startsWith('lighthouse-'));
      expect(session.vmName!.length, 19); // 'lighthouse-' (11) + 8 chars = 19
      expect(session.state, SessionState.pending);
      expect(session.origin, 'https://example.com');
      expect(session.tutorialUrl, 'https://example.com/tutorial');
    });

    test('create adds session to internal map', () {
      final session = manager.create(
        origin: 'https://example.com',
        tutorialUrl: 'https://example.com/tutorial',
      );

      final found = manager.find(session.sessionId);
      expect(found, isNotNull);
      expect(found!.sessionId, session.sessionId);
    });

    test('find returns null for unknown session', () {
      expect(manager.find('nonexistent'), isNull);
    });

    test('remove deletes session and cancels timer', () {
      final session = manager.create(
        origin: 'https://example.com',
        tutorialUrl: 'https://example.com/tutorial',
      );

      manager.remove(session.sessionId);
      expect(manager.find(session.sessionId), isNull);
    });

    test('remove is idempotent for non-existent session', () {
      expect(() => manager.remove('nonexistent'), returnsNormally);
    });

    test('sessions returns only active sessions', () {
      final s1 = manager.create(
        origin: 'https://example.com',
        tutorialUrl: 'https://example.com/tutorial',
      );
      final s2 = manager.create(
        origin: 'https://example.com',
        tutorialUrl: 'https://example.com/tutorial',
      );

      // Mark one as purged
      s1.state = SessionState.purged;

      final active = manager.sessions.toList();
      expect(active.length, 1);
      expect(active.first.sessionId, s2.sessionId);
    });

    test('startExpiry transitions session to expiring state', () {
      final session = manager.create(
        origin: 'https://example.com',
        tutorialUrl: 'https://example.com/tutorial',
      );

      manager.startExpiry(session.sessionId, onExpire: () {});

      final updated = manager.find(session.sessionId);
      expect(updated, isNotNull);
      expect(updated!.state, SessionState.expiring);
      expect(updated.expiresAt, isNotNull);

      // Clean up
      manager.remove(session.sessionId);
    });

    test('cancelExpiry resets session to ready state', () {
      final session = manager.create(
        origin: 'https://example.com',
        tutorialUrl: 'https://example.com/tutorial',
      );

      manager.startExpiry(session.sessionId, onExpire: () {});
      manager.cancelExpiry(session.sessionId);

      final updated = manager.find(session.sessionId);
      expect(updated, isNotNull);
      expect(updated!.state, SessionState.ready);
      expect(updated.expiresAt, isNull);

      // Clean up
      manager.remove(session.sessionId);
    });

    test('cancelExpiry is safe for non-existent session', () {
      expect(() => manager.cancelExpiry('nonexistent'), returnsNormally);
    });

    test('startExpiry is safe for non-existent session', () {
      expect(() => manager.startExpiry('nonexistent', onExpire: () {}), returnsNormally);
    });

    test('full lifecycle: create → expiry → cancel → ready', () {
      final session = manager.create(
        origin: 'https://example.com',
        tutorialUrl: 'https://example.com/tutorial',
      );

      expect(session.state, SessionState.pending);

      // Simulate first exec triggering permission
      session.state = SessionState.authorizing;
      session.state = SessionState.provisioning;
      session.state = SessionState.ready;

      // Start expiry (simulating WS close)
      manager.startExpiry(session.sessionId, onExpire: () {});
      expect(session.state, SessionState.expiring);

      // Resume session
      manager.cancelExpiry(session.sessionId);
      expect(session.state, SessionState.ready);

      // Clean up
      manager.remove(session.sessionId);
      expect(manager.find(session.sessionId), isNull);
    });

    test('multiple sessions are tracked independently', () {
      final s1 = manager.create(
        origin: 'https://example.com',
        tutorialUrl: 'https://example.com/tutorial',
      );
      final s2 = manager.create(
        origin: 'https://other.com',
        tutorialUrl: 'https://other.com/tutorial',
      );

      expect(s1.sessionId, isNot(equals(s2.sessionId)));
      expect(s1.vmName, isNot(equals(s2.vmName)));

      manager.remove(s1.sessionId);
      expect(manager.find(s1.sessionId), isNull);
      expect(manager.find(s2.sessionId), isNotNull);

      // Clean up
      manager.remove(s2.sessionId);
    });

    test('expiry timer callback fires and purges session', () async {
      final completer = Completer<String>();
      final session = manager.create(
        origin: 'https://example.com',
        tutorialUrl: 'https://example.com/tutorial',
      );

      manager.startExpiry(session.sessionId, onExpire: () {
        completer.complete(session.sessionId);
      });

      // Manually trigger the timer for testing
      session.expiryTimer!.cancel();
      session.expiryTimer = Timer(const Duration(milliseconds: 50), () {
        completer.complete(session.sessionId);
      });

      final expiredSessionId = await completer.future;
      expect(expiredSessionId, session.sessionId);

      // Clean up
      manager.remove(session.sessionId);
    });
  });
}
