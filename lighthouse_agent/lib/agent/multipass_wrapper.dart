import 'dart:async';

class CommandOutput {
  const CommandOutput({required this.stream, required this.data});

  final String stream;
  final String data;
}

class ExecResult {
  const ExecResult({required this.exitCode});

  final int exitCode;
}

class MultipassWrapper {
  const MultipassWrapper();

  Future<String> launch({required String vmName}) async {
    throw UnimplementedError('Day 2: implement multipass launch');
  }

  Stream<CommandOutput> exec({
    required String vmName,
    required String command,
  }) {
    throw UnimplementedError('Day 2: implement multipass exec streaming');
  }

  Future<void> delete({required String vmName, bool purge = true}) async {
    throw UnimplementedError('Day 2: implement multipass delete');
  }
}
