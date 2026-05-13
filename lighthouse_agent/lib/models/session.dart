enum SessionState {
  pending,
  authorizing,
  provisioning,
  ready,
  expiring,
  purged,
}

class Session {
  Session({
    required this.sessionId,
    required this.tutorialUrl,
    required this.origin,
    this.state = SessionState.pending,
    this.vmName,
    DateTime? createdAt,
    this.expiresAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String sessionId;
  final String tutorialUrl;
  final String origin;
  SessionState state;
  String? vmName;
  DateTime createdAt;
  DateTime? expiresAt;
}
