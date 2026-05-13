import 'package:uuid/uuid.dart';
import '../models/session.dart';

class SessionManager {
  final Map<String, Session> _sessions = <String, Session>{};

  Iterable<Session> get sessions => _sessions.values.where((session) => session.isActive);

  Session? find(String sessionId) => _sessions[sessionId];

  Session create({required String origin, required String tutorialUrl}) {
    final sessionId = const Uuid().v4();
    final vmName = 'lighthouse-${sessionId.substring(0, 8)}';

    final session = Session(
      sessionId: sessionId,
      tutorialUrl: tutorialUrl,
      origin: origin,
      state: SessionState.pending,
      vmName: vmName,
    );

    _sessions[session.sessionId] = session;
    return session;
  }

  void remove(String sessionId) {
    final session = _sessions[sessionId];
    session?.cancelExpiryTimer();
    _sessions.remove(sessionId);
  }

  void startExpiry(String sessionId, {required void Function() onExpire}) {
    final session = _sessions[sessionId];
    if (session != null) {
      session.startExpiryTimer(onExpire: onExpire);
    }
  }

  void cancelExpiry(String sessionId) {
    final session = _sessions[sessionId];
    if (session != null) {
      session.cancelExpiryTimer();
      session.state = SessionState.ready;
      session.expiresAt = null;
    }
  }
}
