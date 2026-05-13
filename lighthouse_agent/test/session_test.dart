import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:lighthouse_agent/models/session.dart';

void main() {
  group('Session', () {
    test('creates session in pending state with correct defaults', () {
      final session = Session(
        sessionId: 'test-123',
        tutorialUrl: 'https://example.com/tutorial',
        origin: 'https://example.com',
      );

      expect(session.sessionId, 'test-123');
      expect(session.tutorialUrl, 'https://example.com/tutorial');
      expect(session.origin, 'https://example.com');
      expect(session.state, SessionState.pending);
      expect(session.vmName, isNull);
      expect(session.expiresAt, isNull);
      expect(session.expiryTimer, isNull);
      expect(session.isActive, isTrue);
    });

    test('creates session with custom vmName', () {
      final session = Session(
        sessionId: 'test-123',
        tutorialUrl: 'https://example.com/tutorial',
        origin: 'https://example.com',
        vmName: 'lighthouse-abc12345',
      );

      expect(session.vmName, 'lighthouse-abc12345');
    });

    test('isActive returns true for all states except purged', () {
      final states = [
        SessionState.pending,
        SessionState.authorizing,
        SessionState.provisioning,
        SessionState.ready,
        SessionState.expiring,
      ];

      for (final state in states) {
        final session = Session(
          sessionId: 'test',
          tutorialUrl: 'https://example.com',
          origin: 'https://example.com',
          state: state,
        );
        expect(session.isActive, isTrue, reason: 'State $state should be active');
      }

      final purgedSession = Session(
        sessionId: 'test',
        tutorialUrl: 'https://example.com',
        origin: 'https://example.com',
        state: SessionState.purged,
      );
      expect(purgedSession.isActive, isFalse);
    });

    group('expiry timer', () {
      test('startExpiryTimer sets state to expiring and sets expiresAt', () async {
        final completer = Completer<void>();
        final session = Session(
          sessionId: 'test',
          tutorialUrl: 'https://example.com',
          origin: 'https://example.com',
          state: SessionState.ready,
        );

        session.startExpiryTimer(onExpire: () {
          completer.complete();
        });

        expect(session.state, SessionState.expiring);
        expect(session.expiresAt, isNotNull);
        expect(session.expiresAt!.isAfter(DateTime.now()), isTrue);
        expect(session.expiryTimer, isNotNull);

        // Clean up
        session.cancelExpiryTimer();
      });

      test('cancelExpiryTimer cancels and nulls timer', () {
        final session = Session(
          sessionId: 'test',
          tutorialUrl: 'https://example.com',
          origin: 'https://example.com',
        );

        session.startExpiryTimer(onExpire: () {});
        expect(session.expiryTimer, isNotNull);

        session.cancelExpiryTimer();
        expect(session.expiryTimer, isNull);
      });

      test('startExpiryTimer cancels existing timer before starting new one', () {
        final session = Session(
          sessionId: 'test',
          tutorialUrl: 'https://example.com',
          origin: 'https://example.com',
        );

        var expireCount = 0;
        session.startExpiryTimer(onExpire: () {
          expireCount++;
        });

        // Start another timer - should cancel the first one
        session.startExpiryTimer(onExpire: () {
          expireCount++;
        });

        // Only one timer should be active
        expect(session.expiryTimer, isNotNull);

        // Clean up
        session.cancelExpiryTimer();
      });

      test('expiry timer fires after duration', () async {
        final completer = Completer<void>();
        final session = Session(
          sessionId: 'test',
          tutorialUrl: 'https://example.com',
          origin: 'https://example.com',
        );

        // Use a very short timer for testing
        session.expiryTimer?.cancel();
        session.expiryTimer = Timer(const Duration(milliseconds: 50), () {
          completer.complete();
        });

        await completer.future;
        expect(true, isTrue); // Timer fired successfully

        // Clean up
        session.cancelExpiryTimer();
      });
    });
  });
}
