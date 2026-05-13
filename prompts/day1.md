# Day 1 Prompt: Lighthouse Agent — Scaffold, Tray, TLS, WSS Server Skeleton, Autostart

## Objective
Implement Day 1 of the Project Lighthouse engineering plan. Create a new Flutter Desktop project for Linux (primary target) that sets up the foundational infrastructure: system tray integration, a WebSocket server (secure in release mode, plain in debug mode), mkcert-based TLS certificate management, and XDG autostart registration on first launch.

## Context

Read these files before starting:
- `project-plan.md` — the original implementation brief
- `engineering-plan.md` — the detailed engineering plan with all gap-review decisions

**Key decisions from the engineering plan:**
- Framework: Flutter Desktop, latest stable 3.x, Linux target
- System tray icon with normal and error states
- WSS server on port 50051; debug build uses `ws://`, release uses `wss://` with mkcert TLS
- OS autostart: XDG autostart registration on first launch (Linux)
- No actual Multipass or session logic yet — that's Day 2+

## Tasks

### 1. Initialize Flutter Project

Run `flutter create lighthouse_agent --platforms=linux` in the workspace root. Ensure:
- `linux/` directory exists and compiles
- `.gitignore` is respected (no build artifacts committed)
- `pubspec.yaml` is configured for Linux desktop

### 2. Add Dependencies

Add to `pubspec.yaml`:
- `tray_manager` — system tray icon management
- `window_manager` — window state control (needed for status window later)
- `shelf` + `shelf_web_socket` — WebSocket server framework
- `path_provider` — access to app data directory
- `path` — path manipulation
- `uuid` — for session ID generation (Day 3)

After adding, run `flutter pub get`.

### 3. Create Project Directory Structure

Create directories under `lib/`:
```
lib/
  main.dart
  agent/
    websocket_server.dart
    session_manager.dart         # skeleton only — no logic yet
    origin_validator.dart         # skeleton only
    command_sanitizer.dart         # skeleton only
    multipass_wrapper.dart         # skeleton only
  ui/
    tray_icon.dart
    status_window.dart            # skeleton only
    permission_dialog.dart          # skeleton only
  models/
    session.dart                   # skeleton only
    message.dart                   # sealed classes for WS protocol
  proxy/
    tutorial_proxy.dart            # skeleton only
```

### 4. Implement `lib/models/message.dart`

Define sealed classes (or Dart 3 `sealed` + `final` classes) for all WebSocket message types per the engineering plan protocol:

```dart
// All message types
abstract class LighthouseMessage {}

// Client → Agent
class SessionStart implements LighthouseMessage { final String origin; final String tutorialUrl; }
class SessionResume implements LighthouseMessage { final String sessionId; }
class Exec implements LighthouseMessage { final String sessionId; final String command; }
class Finish implements LighthouseMessage { final String sessionId; }

// Agent → Client
class SessionReady implements LighthouseMessage { final String sessionId; final String vmName; }
class SessionDenied implements LighthouseMessage {}
class Output implements LighthouseMessage { final String sessionId; final String stream; final String data; }
class ExecDone implements LighthouseMessage { final String sessionId; final int exitCode; }
class Error implements LighthouseMessage { final String? sessionId; final String code; final String message; }
class AgentError implements LighthouseMessage { final String code; final String message; }
```

Implement `toJson()` / `fromJson()` for each. Use a `MessageCodec` class that can encode/decode any `LighthouseMessage` to/from JSON strings.

### 5. Implement `lib/models/session.dart`

Define session state enum and model:

```dart
enum SessionState { pending, authorizing, provisioning, ready, expiring, purged }

class Session {
  final String sessionId;
  final String tutorialUrl;
  final String origin;
  SessionState state;
  String? vmName;
  DateTime createdAt;
  DateTime? expiresAt;  // for the 30-min countdown
}
```

Keep this lightweight — it's just the data model for now.

### 6. Implement `lib/ui/tray_icon.dart`

Using `tray_manager`:

- `setupTrayIcon()` — initialize system tray with a default icon (use a placeholder PNG in `assets/`)
- `setTrayState(Normal)` — grey/green icon
- `setTrayState(Error)` — red icon (for when multipass is missing)
- Context menu:
  - "Show Status" → opens status window (Day 6)
  - "Quit" → confirms if active sessions exist (stub for now)

The tray icon must appear immediately on app start. The Flutter window itself should be hidden by default (system tray only app).

### 7. Implement `lib/agent/websocket_server.dart`

Using `shelf` and `shelf_web_socket`:

**Design decisions:**
- Debug mode (kDebugMode from `flutter/foundation.dart`): run `ws://` on port 50051
- Release mode: run `wss://` on port 50051 with TLS certificates

**Class `WebSocketServer`:**
```dart
class WebSocketServer {
  Future<void> start();  // binds to localhost:50051
  Future<void> stop();   // closes all connections
  Future<bool> hasValidCertificates();  // checks cert/key files exist and are not expired
  String getCertPath();   // returns <appDataDir>/lighthouse/localhost.pem
  String getKeyPath();    // returns <appDataDir>/lighthouse/localhost-key.pem
}
```

**For Day 1 (skeleton only):**
- Server starts and accepts WebSocket connections
- On connection, logs to stdout (or to a simple in-memory log)
- Parses incoming JSON messages using `MessageCodec`
- Replies with `AgentError { code: "NOT_IMPLEMENTED", message: "Day 1" }` for any message
- No origin validation, no session handling yet

**Debug vs. release binding:**
- Debug: `shelf_io.serve()` directly on `ws://`
- Release: use `io.HttpServer` with TLS `SecurityContext` loaded from cert files, then wrap with `shelf`

### 8. Implement `lib/main.dart`

App entry point with this startup sequence:

```
1. Ensure Flutter window is hidden (system tray app)
2. Initialize tray icon (setTrayState(Normal))
3. Check first launch:
     - If <appDataDir>/lighthouse/ has no config file → run autostart registration (see Task 9)
4. Check mkcert / certificates:
     - If release mode AND no valid certificates → show setup UI (Day 1: log to stdout, TODO placeholder)
5. Start WebSocketServer
6. Enter event loop (system tray driven)
```

The app should not show a Flutter window on startup. It lives in the system tray.

### 9. Implement Autostart Registration (Linux)

Create a function `registerAutostart()` in `main.dart` or a new file `lib/platform/autostart_linux.dart`:

```dart
Future<void> registerAutostartLinux() async {
  final home = Platform.environment['HOME'];
  final autostartDir = Directory('$home/.config/autostart');
  await autostartDir.create(recursive: true);
  
  final desktopFile = File('${autostartDir.path}/lighthouse.desktop');
  await desktopFile.writeAsString('''
[Desktop Entry]
Name=Lighthouse Agent
Exec=<path_to_executable>
Type=Application
Terminal=false
Hidden=false
X-GNOME-Autostart-enabled=true
''');
}
```

- The executable path should be determined at runtime (use `Platform.resolvedExecutable`)
- Create a flag file `<appDataDir>/lighthouse/.autostart_registered` to ensure this only happens once
- This is a best-effort operation; if it fails, log and continue

### 10. Create Assets

- `assets/icon_normal.png` — placeholder 32x32 tray icon (can be a simple colored square for now)
- `assets/icon_error.png` — placeholder 32x32 red tray icon
- Add to `pubspec.yaml` under `assets:`

### 11. Update `pubspec.yaml`

Ensure all dependencies are declared and the project is configured:
- Minimum Dart SDK >= 3.0 (for `sealed` classes)
- `flutter:` section with `assets:`
- All dependencies from Task 2

### 12. Ensure It Builds

Run `flutter build linux --release` and `flutter build linux --debug` to verify compilation. The debug build should produce a runnable binary that:
- Shows a system tray icon
- Accepts WebSocket connections on `ws://localhost:50051`
- Prints connection logs

The release build should attempt to load TLS certificates (will fail on Day 1 since certs aren't generated yet — that's expected).

## Skeleton Files (stub implementations)

These files must exist as compilable stubs (empty classes, no-op methods) so Day 2+ agents can fill them in:

- `lib/agent/session_manager.dart` — `class SessionManager { ... }` with method signatures matching the lifecycle
- `lib/agent/origin_validator.dart` — `class OriginValidator { bool isAllowed(String origin); }`
- `lib/agent/command_sanitizer.dart` — `class CommandSanitizer { String? blockIfUnsafe(String command); }`
- `lib/agent/multipass_wrapper.dart` — `class MultipassWrapper { ... }` with `launch()`, `exec()`, `delete()` method signatures
- `lib/ui/status_window.dart` — `class StatusWindow { ... }` minimal Flutter widget skeleton
- `lib/ui/permission_dialog.dart` — `class PermissionDialog { ... }` minimal stub
- `lib/proxy/tutorial_proxy.dart` — `class TutorialProxy { ... }` minimal stub

## Acceptance Criteria

- [ ] `flutter create` produces valid Linux project in the workspace
- [ ] `pubspec.yaml` has all required dependencies
- [ ] `lib/models/message.dart` compiles with all message types + JSON codec
- [ ] `lib/models/session.dart` compiles with enum + model
- [ ] `lib/ui/tray_icon.dart` shows a system tray icon on Linux with "Show Status" and "Quit" context menu items
- [ ] `lib/agent/websocket_server.dart` starts a WS server on port 50051 (debug: ws://, release: wss:// attempt)
- [ ] Any WS client connecting to the server receives parsed messages (echoed back as `AgentError` for Day 1)
- [ ] `lib/main.dart` startup sequence implemented: tray → autostart check → cert check → server start
- [ ] XDG autostart `.desktop` file is written on first launch (and only first launch)
- [ ] All skeleton files for Day 2–7 exist and compile
- [ ] `flutter build linux --release` and `--debug` both succeed without errors
- [ ] `.gitignore` is respected; no build artifacts staged

## Deliverables

All code changes committed to the `main` branch with a descriptive commit message. The commit should be:
```
feat(day1): scaffold Flutter project, tray icon, WSS skeleton, autostart

- Initialize Flutter Desktop for Linux
- System tray with tray_manager (normal/error states)
- WebSocket server skeleton (ws:// debug, wss:// release) on port 50051
- Message + session models with JSON codec
- XDG autostart registration on first launch
- Stubs for all Day 2–7 modules
```

## Important Notes

- **Do NOT** implement actual Multipass calling (that's Day 2)
- **Do NOT** implement origin validation logic (that's Day 3)
- **Do NOT** implement session state machine (that's Day 3)
- **Do NOT** implement the status window UI beyond a skeleton (that's Day 6)
- **Do NOT** implement the local HTTP proxy (that's Day 5)
- The WSS server must be a standalone class that can be started/stopped programmatically
- The app must be primarily a system tray application (no visible window on startup)
- Use Dart 3 features (`sealed`, `final` classes, pattern matching) where appropriate
- Keep code clean, commented, and ready for other agents to extend
