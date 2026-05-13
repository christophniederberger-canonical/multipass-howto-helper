import '../models/session.dart';

class SessionManager {
  final Map<String, Session> _sessions = <String, Session>{};

  Iterable<Session> get sessions => _sessions.values;

  Session? find(String sessionId) => _sessions[sessionId];

  void add(Session session) {
    _sessions[session.sessionId] = session;
  }

  void remove(String sessionId) {
    _sessions.remove(sessionId);
  }
}
