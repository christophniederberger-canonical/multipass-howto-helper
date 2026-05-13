# Day 2 Prompt: Lighthouse Agent — Multipass CLI Wrapper

## Objective
Implement Day 2 of the Project Lighthouse engineering plan. Build the `MultipassWrapper` that wraps the Multipass CLI via `Process.start()`: VM launch (`multipass launch`), real-time command execution (`multipass exec` with streaming stdout/stderr), and VM deletion (`multipass delete --purge`). Also add Multipass PATH detection at startup with tray error state feedback.

## Context

Read these files before starting:
- `project-plan.md` — the original implementation brief
- `engineering-plan.md` — the detailed engineering plan with all gap-review decisions
- `prompts/day1.md` — what was built on Day 1 (scaffold, tray, WSS skeleton, autostart)

**Key decisions from the engineering plan:**
- Multipass CLI only (no `libmultipass`)
- VM naming: `lighthouse-` + first 8 chars of UUID v4 (e.g. `lighthouse-3f7a1b2c`)
- `multipass exec` must stream stdout/stderr in real-time via Dart `Stream`
- If `multipass` is not in PATH at startup: tray icon shows error state; tooltip: "Multipass not found"
- `multipass launch` uses `--name <vm-name>`; no other flags required for MVP
- `multipass delete --purge <vm-name>` for immediate cleanup

## Current State (Day 1 Complete)

The following are already in place and must NOT be reimplemented:
- Flutter project scaffold with Linux target
- `pubspec.yaml` with all dependencies (`shelf`, `shelf_web_socket`, `tray_manager`, `window_manager`, `path_provider`, `path`, `uuid`)
- `lib/models/message.dart` — sealed classes + `MessageCodec` for all WS message types
- `lib/models/session.dart` — `SessionState` enum + `Session` model
- `lib/agent/websocket_server.dart` — WSS server skeleton (debug `ws://`, release `wss://`) on port 50051
- `lib/ui/tray_icon.dart` — `LighthouseTray` with `setupTrayIcon()`, `setTrayState(TrayState)`, `showStatus()`, `quit()`
- `lib/main.dart` — startup sequence: tray → autostart check → cert check → server start
- `lib/platform/autostart_linux.dart` — XDG autostart registration
- Skeleton stubs for `session_manager.dart`, `origin_validator.dart`, `command_sanitizer.dart`, `permission_dialog.dart`, `status_window.dart`, `tutorial_proxy.dart`

## Tasks

### 1. Implement `lib/agent/multipass_wrapper.dart`

Replace the Day 1 stubs with full implementations.

**Class `MultipassWrapper`:**

```dart
class MultipassWrapper {
  /// Detects whether `multipass` is available in PATH.
  static Future<bool> isAvailable();

  /// Launches a new VM with the given name.
  /// Returns the VM name on success.
  /// Throws if multipass is unavailable or launch fails.
  Future<String> launch({required String vmName});

  /// Executes a command inside a VM and streams stdout/stderr in real time.
  /// Yields [CommandOutput] events with `stream` equal to "stdout" or "stderr".
  /// After the process exits, yields a final [ExecResult] with the exit code.
  /// 
  /// IMPORTANT: The caller must distinguish [CommandOutput] from [ExecResult].
  /// One pattern: yield* the process stdout/stderr as CommandOutput, then
  /// await exit code and yield ExecResult at the end.
  Stream<Object> exec({required String vmName, required String command});

  /// Deletes (and purges) a VM. Does not throw if VM already gone.
  Future<void> delete({required String vmName, bool purge = true});
}
```

**Implementation details:**

- `isAvailable()`: run `which multipass` (Linux) or `where multipass` (Windows) or `command -v multipass` (macOS). For Day 2, Linux-only is sufficient — use `which multipass` via `Process.run` and check `exitCode == 0`.
- `launch()`: run `multipass launch --name <vmName>`. Use `Process.run` (not `start`) because launch is a one-shot operation. Wait for completion. If exit code != 0, throw `Exception('multipass launch failed: <stderr>')`.
- `exec()`: run `multipass exec <vmName> -- bash -c '<command>'`. Use `Process.start` to get real-time streams.
  - Capture `process.stdout` as UTF-8 lines → yield `CommandOutput(stream: 'stdout', data: line)`
  - Capture `process.stderr` as UTF-8 lines → yield `CommandOutput(stream: 'stderr', data: line)`
  - Wait for `process.exitCode` → yield `ExecResult(exitCode: exitCode)` as the final event
  - Use `StreamController` or `async*` to merge stdout and stderr into a single stream
  - Handle process start failure (e.g., VM not found) by throwing from the stream
- `delete()`: run `multipass delete --purge <vmName>` via `Process.run`. If exit code != 0 AND stderr does NOT contain "does not exist", log a warning but do not throw. This handles the "already deleted" case gracefully.

**Update the model classes if needed:**

The current `CommandOutput` and `ExecResult` are fine. Keep them as-is or refine if you discover a better pattern during implementation.

### 2. Add Multipass Availability Check to `lib/main.dart`

In the startup sequence, after tray initialization but BEFORE starting the WebSocket server:

```
1. Ensure Flutter window is hidden (system tray app)
2. Initialize tray icon (setTrayState(Normal))
3. Check first launch → autostart registration
4. Check mkcert / certificates
5. NEW: Check Multipass availability
     - Call MultipassWrapper.isAvailable()
     - If NOT available:
         - await tray.setTrayState(TrayState.error)
         - Log to stderr: "Multipass not found in PATH. Please install Multipass."
         - Continue anyway (server starts, but any VM operation will fail at runtime)
     - If available:
         - Log to stdout: "Multipass detected."
6. Start WebSocketServer
```

The tray error state must be visible to the user. On Linux, since `tray_manager` may not be fully functional in all environments, at minimum the `setTrayState(TrayState.error)` call must be made (it logs to stdout in the Day 1 fallback).

### 3. Update `lib/ui/tray_icon.dart` Tooltip

Add a tooltip field to the tray icon that reflects the current state:
- Normal state: tooltip = "Lighthouse Agent"
- Error state (multipass missing): tooltip = "Multipass not found"

If `tray_manager` APIs for tooltip are not available or fail, fall back to logging.

### 4. Wire `multipass_wrapper.dart` into `websocket_server.dart` (Minimal)

The WebSocket server currently replies with `AgentError(code: 'NOT_IMPLEMENTED', ...)` for every message. For Day 2, do NOT implement full session logic — that is Day 3. Instead, add a minimal integration so that the Day 2 work can be manually tested:

In `websocket_server.dart`, when an `Exec` message is received:
- Parse the `Exec` message (already done by `MessageCodec`)
- For Day 2 testing only: if the command is exactly `"__test_multipass__"`, run:
  ```dart
  final wrapper = MultipassWrapper();
  final vmName = 'lighthouse-test-${DateTime.now().millisecondsSinceEpoch}';
  await wrapper.launch(vmName: vmName);
  await for (final event in wrapper.exec(vmName: vmName, command: 'echo hello from multipass')) {
    if (event is CommandOutput) {
      channel.sink.add(_codec.encode(Output(sessionId: exec.sessionId, stream: event.stream, data: event.data)));
    } else if (event is ExecResult) {
      channel.sink.add(_codec.encode(ExecDone(sessionId: exec.sessionId, exitCode: event.exitCode)));
    }
  }
  await wrapper.delete(vmName: vmName);
  ```
- For ALL other messages, keep the Day 1 `AgentError(code: 'NOT_IMPLEMENTED', ...)` response.

This `__test_multipass__` command is a temporary Day 2 test hook. It will be removed in Day 3 when real session management is implemented. Document it clearly with a `// TODO(day3): remove test hook` comment.

### 5. Unit Tests

Create `test/multipass_wrapper_test.dart` with tests for `MultipassWrapper`:

**Test 1: `isAvailable()`**
- If `multipass` is in PATH, `isAvailable()` returns `true`.
- If `multipass` is NOT in PATH, `isAvailable()` returns `false`.
  - You can simulate "not in PATH" by temporarily overriding `PATH` to an empty directory, or by mocking `Process.run`.

**Test 2: `exec()` streaming**
- Mock a `Process` with fake stdout/stderr streams and a fake exit code.
- Verify that `exec()` yields `CommandOutput` events for stdout and stderr lines, followed by an `ExecResult` with the correct exit code.

**Test 3: `delete()` idempotency**
- Mock a `Process.run` that returns exit code 1 with stderr containing "does not exist".
- Verify that `delete()` does NOT throw.

**Guidance on mocking:**
- Since `MultipassWrapper` uses static `Process.run` and `Process.start`, you may need to refactor slightly to make it testable. One approach: add an optional `ProcessRunner` function parameter to the constructor, defaulting to the real `Process.run`/`Process.start`. Another approach: use `package:mockito` or manual fakes.
- Keep it simple. If mocking `Process` is too complex for a hackathon timeline, write integration tests that require real `multipass` and skip them with `test('...', skip: 'requires multipass')`.

### 6. Update `pubspec.yaml` if Needed

If you add test dependencies (e.g., `mockito`, `test`), add them under `dev_dependencies`.

## Acceptance Criteria

- [ ] `MultipassWrapper.launch()` creates a VM via `multipass launch --name <vmName>`
- [ ] `MultipassWrapper.exec()` streams stdout/stderr in real time and returns the exit code
- [ ] `MultipassWrapper.delete()` purges a VM and handles "already gone" gracefully
- [ ] `MultipassWrapper.isAvailable()` correctly detects `multipass` in PATH
- [ ] `main.dart` checks multipass availability on startup and sets tray to error state if missing
- [ ] Tray tooltip reflects "Multipass not found" when in error state
- [ ] WebSocket server has a temporary `__test_multipass__` test hook that demonstrates end-to-end launch/exec/delete (to be removed in Day 3)
- [ ] Unit or integration tests exist for `MultipassWrapper`
- [ ] `flutter build linux --debug` succeeds
- [ ] `flutter test` runs without compilation errors (tests may skip if multipass is not installed)

## Deliverables

All code changes committed to the `main` branch with a descriptive commit message:
```
feat(day2): multipass CLI wrapper with launch, exec streaming, and delete

- Implement MultipassWrapper: launch, exec (real-time stdout/stderr), delete --purge
- Detect multipass in PATH at startup; set tray error state if missing
- Add tray tooltip reflecting multipass availability
- Temporary WS test hook (__test_multipass__) for manual E2E validation
- Unit tests for wrapper behavior (mocked and/or integration)
```

## Important Notes

- **Do NOT** implement session state machine or `session_start`/`session_resume` handling — that's Day 3
- **Do NOT** implement origin validation logic — that's Day 3
- **Do NOT** implement the Allow/Deny permission dialog — that's Day 3
- **Do NOT** implement the status window UI beyond what's already there — that's Day 6
- **Do NOT** implement the local HTTP proxy — that's Day 5
- The `__test_multipass__` WS hook is temporary and MUST be marked with `TODO(day3): remove`
- Keep the `exec()` stream pattern compatible with the WebSocket `output` + `exec_done` message protocol defined in `models/message.dart`
- If `multipass` is not installed on your system, the tests should skip gracefully rather than fail
