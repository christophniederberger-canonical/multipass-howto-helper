import 'dart:convert';

sealed class LighthouseMessage {
  const LighthouseMessage();

  String get type;

  Map<String, Object?> toJson();
}

final class SessionStart extends LighthouseMessage {
  const SessionStart({required this.origin, required this.tutorialUrl});

  final String origin;
  final String tutorialUrl;

  @override
  String get type => 'session_start';

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'origin': origin,
    'tutorial_url': tutorialUrl,
  };
}

final class SessionResume extends LighthouseMessage {
  const SessionResume({required this.sessionId});

  final String sessionId;

  @override
  String get type => 'session_resume';

  @override
  Map<String, Object?> toJson() => {'type': type, 'session_id': sessionId};
}

final class Exec extends LighthouseMessage {
  const Exec({required this.sessionId, required this.command});

  final String sessionId;
  final String command;

  @override
  String get type => 'exec';

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'session_id': sessionId,
    'command': command,
  };
}

final class Finish extends LighthouseMessage {
  const Finish({required this.sessionId});

  final String sessionId;

  @override
  String get type => 'finish';

  @override
  Map<String, Object?> toJson() => {'type': type, 'session_id': sessionId};
}

final class SessionReady extends LighthouseMessage {
  const SessionReady({required this.sessionId, required this.vmName});

  final String sessionId;
  final String vmName;

  @override
  String get type => 'session_ready';

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'session_id': sessionId,
    'vm_name': vmName,
  };
}

final class SessionDenied extends LighthouseMessage {
  const SessionDenied();

  @override
  String get type => 'session_denied';

  @override
  Map<String, Object?> toJson() => {'type': type};
}

enum OutputStream { stdout, stderr }

final class Output extends LighthouseMessage {
  const Output({
    required this.sessionId,
    required this.stream,
    required this.data,
  });

  final String sessionId;
  final OutputStream stream;
  final String data;

  @override
  String get type => 'output';

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'session_id': sessionId,
    'stream': stream.name,
    'data': data,
  };
}

final class ExecDone extends LighthouseMessage {
  const ExecDone({required this.sessionId, required this.exitCode});

  final String sessionId;
  final int exitCode;

  @override
  String get type => 'exec_done';

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'session_id': sessionId,
    'exit_code': exitCode,
  };
}

final class LighthouseError extends LighthouseMessage {
  const LighthouseError({
    this.sessionId,
    required this.code,
    required this.message,
  });

  final String? sessionId;
  final String code;
  final String message;

  @override
  String get type => 'error';

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    if (sessionId != null) 'session_id': sessionId,
    'code': code,
    'message': message,
  };
}

final class AgentError extends LighthouseMessage {
  const AgentError({required this.code, required this.message});

  final String code;
  final String message;

  @override
  String get type => 'agent_error';

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'code': code,
    'message': message,
  };
}

final class MessageCodec {
  const MessageCodec();

  String encode(LighthouseMessage message) => jsonEncode(message.toJson());

  LighthouseMessage decode(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Message must be a JSON object');
    }
    return fromJson(decoded);
  }

  LighthouseMessage fromJson(Map<String, Object?> json) {
    final type = json['type'];
    if (type is! String) {
      throw const FormatException('Message type is required');
    }

    return switch (type) {
      'session_start' => SessionStart(
        origin: _string(json, 'origin'),
        tutorialUrl: _string(json, 'tutorial_url'),
      ),
      'session_resume' => SessionResume(sessionId: _string(json, 'session_id')),
      'exec' => Exec(
        sessionId: _string(json, 'session_id'),
        command: _string(json, 'command'),
      ),
      'finish' => Finish(sessionId: _string(json, 'session_id')),
      'session_ready' => SessionReady(
        sessionId: _string(json, 'session_id'),
        vmName: _string(json, 'vm_name'),
      ),
      'session_denied' => const SessionDenied(),
      'output' => Output(
        sessionId: _string(json, 'session_id'),
        stream: _parseOutputStream(_string(json, 'stream')),
        data: _string(json, 'data'),
      ),
      'exec_done' => ExecDone(
        sessionId: _string(json, 'session_id'),
        exitCode: _int(json, 'exit_code'),
      ),
      'error' => LighthouseError(
        sessionId: json['session_id'] as String?,
        code: _string(json, 'code'),
        message: _string(json, 'message'),
      ),
      'agent_error' => AgentError(
        code: _string(json, 'code'),
        message: _string(json, 'message'),
      ),
      _ => throw FormatException('Unknown message type: $type'),
    };
  }

  static String _string(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is String) {
      return value;
    }
    throw FormatException('Expected string field: $key');
  }

  static int _int(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is int) {
      return value;
    }
    throw FormatException('Expected int field: $key');
  }

  static OutputStream _parseOutputStream(String value) {
    return switch (value) {
      'stdout' => OutputStream.stdout,
      'stderr' => OutputStream.stderr,
      _ => throw FormatException('Unknown output stream: $value'),
    };
  }
}
