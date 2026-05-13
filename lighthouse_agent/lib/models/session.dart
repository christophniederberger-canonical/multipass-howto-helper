import 'dart:async';

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

  final DateTime createdAt;

  DateTime? expiresAt;
  
  Timer? expiryTimer;

  void cancelExpiryTimer() {
    expiryTimer?.cancel();
    expiryTimer = null;
  }

  void startExpiryTimer({required void Function() onExpire}) {
    cancelExpiryTimer(); // Cancel any existing timer
    state = SessionState.expiring;
    expiresAt = DateTime.now().add(const Duration(minutes: 30));
    expiryTimer = Timer(const Duration(minutes: 30), onExpire);
  }

  bool get isActive => state != SessionState.purged;
}
