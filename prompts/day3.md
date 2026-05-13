# Day 3 — Session Manager + Security (Permission Dialog & Lifecycle)

## Goal

Implement the full session lifecycle state machine, the native Allow/Deny permission dialog, and the 30-minute expiry timer. By the end of Day 3, the Agent must:

- Accept `session_start`, validate the origin, but **not** immediately provision a VM
- On the **first `exec`** command, show a native OS Allow/Deny dialog
- On **Allow**: launch a Multipass VM, send `session_ready`
- On **Deny**: send `session_denied`, close the WebSocket
- Handle `session_resume`: cancel the expiry timer and reattach to the existing session
- On WebSocket close: start a 30-minute timer; if it expires, purge the VM
- On `finish`: immediately purge the VM

---

## Execution Strategy: Parallel Subagents with Competition

This prompt launches **3 subagents in parallel**. Two of them compete on the hardest file (`websocket_server.dart`) — the main agent reviews both submissions and picks the winner.

```
                    ┌─────────────────────────────────────────┐
                    │           MAIN AGENT (You)               │
                    │  Orchestrates, reviews, merges, commits  │
                    └──────────┬──────────────────────────────┘
                               │
              ┌────────────────┼────────────────┐
              │                │                │
              ▼                ▼                ▼
        ┌───────────┐   ┌───────────┐   ┌───────────┐
        │ Subagent A│   │ Subagent B│   │ Subagent C│
        │ Session   │   │ WS Server │   │ Permission│
        │ Manager   │   │ (Version 1)│   │ Dialog +  │
        │ + Model   │   │           │   │ Main      │
        │           │   │           │   │ wiring    │
        └───────────┘   └─────┬─────┘   └───────────┘
                              │
                    ┌─────────┴─────────┐
                    │  Competition      │
                    │ Subagent D        │
                    │ WS Server (V2)    │
                    │                   │
                    │  Main agent picks │
                    │ the better impl   │
                    └───────────────────┘
```

### Subagent Assignments

| Subagent | Scope | Files |
|---|---|---|
| **A — Session Core** | Session model + Session Manager rewrite | `lib/models/session.dart`, `lib/agent/session_manager.dart` |
| **B — WS Server v1** | WebSocket server rework (approach 1) | `lib/agent/websocket_server.dart` |
| **C — UI + Wiring** | Permission dialog + main.dart wiring | `lib/ui/permission_dialog.dart`, `lib/main.dart` |
| **D — WS Server v2** | WebSocket server rework (approach 2, competes with B) | `lib/agent/websocket_server.dart` |

### Competition Rules

Subagents **B** and **D** both receive the same spec for `websocket_server.dart` but are told to use **different architectural approaches**:

- **B** should use a **callback-based** approach: the WS server holds a `GlobalKey<NavigatorState>` and calls `showDialog` directly from within `_handleExec`
- **D** should use a **callback/continuation-based** approach: the WS server exposes a `Future<PermissionDecision> Function()` callback that the UI layer registers; the server awaits this callback when permission is needed, decoupling the UI from the server

The main agent reviews both implementations and picks the winner (or merges the best parts of each).

### Execution Order

1. **All 4 subagents launch simultaneously** — A, B, C, D start in parallel
2. Subagent A must finish before B and D can fully validate their code (since they import `Session` and `SessionManager`)
3. Subagent C is fully independent — no dependencies on A, B, or D
4. After B and D both finish, the main agent reviews, picks a winner, and applies it
5. The main agent does a final validation pass across all files

---

## Detailed Requirements

### 1. Session Model (`lib/models/session.dart`) — Subagent A

Add to the existing `Session` class:

```dart
import 'dart:async';

// Add field:
Timer? expiryTimer;
```

Add helper methods:

- `void cancelExpiryTimer()` — cancels and nulls out `expiryTimer`
- `void startExpiryTimer({required VoidCallback onExpire})` — creates a 30-minute `Timer` that calls `onExpire`, sets `state = SessionState.expiring` and `expiresAt`
- `bool get isActive` — returns `true` unless state is `purged`

### 2. Session Manager (`lib/agent/session_manager.dart`) — Subagent A

Rewrite the stub. The `SessionManager` must:

- Maintain `Map<String, Session> _sessions`
- `Session? find(String sessionId)` — lookup
- `Session create({required String origin, required String tutorialUrl})` — creates a new `Session` in `pending` state with a UUID-based `sessionId` and `vmName = 'lighthouse-<first-8-chars-of-uuid>'`. Adds to map, returns it.
- `void remove(String sessionId)` — cancels any expiry timer, removes from map
- `void startExpiry(String sessionId, {required VoidCallback onExpire})` — transitions session to `expiring`, sets `expiresAt` to now + 30 min, starts timer
- `void cancelExpiry(String sessionId)` — cancels timer, clears `expiresAt`, sets state back to `ready`
- `Iterable<Session> get sessions` — all active (non-purged) sessions

### 3. Permission Dialog (`lib/ui/permission_dialog.dart`) — Subagent C

Replace the stub. Implement a real dialog:

```dart
import 'package:flutter/material.dart';

enum PermissionDecision { allow, deny }

class PermissionDialog {
  const PermissionDialog();

  /// Shows a native-style Allow/Deny dialog.
  /// Must be called with a valid [BuildContext].
  Future<PermissionDecision> requestTutorialPermission({
    required BuildContext context,
    required String origin,
  }) async {
    // Use showDialog<PermissionDecision> with an AlertDialog
    // Title: "Allow Tutorial Commands?"
    // Content: "A tutorial from {origin} wants to run commands in a Multipass VM."
    // Actions: "Deny" (returns deny) and "Allow" (returns allow)
    // Barrier dismissible: false (user must choose)
  }
}
```

Key details:
- The dialog must be modal (barrierDismissible: false)
- "Allow" is the default/primary action (styled as a filled button)
- "Deny" is a text button
- The `origin` parameter is displayed in the dialog body so the user knows which site is requesting access

### 4. WebSocket Server (`lib/agent/websocket_server.dart`) — Subagents B & D (Competing)

This is the biggest change. The server must now accept `MultipassWrapper` and a permission mechanism as constructor parameters.

#### Constructor changes (both B and D)

```dart
WebSocketServer({
  this.port = 50051,
  SessionManager? sessionManager,
  OriginValidator? originValidator,
  CommandSanitizer? commandSanitizer,
  MultipassWrapper? multipass,
  // B and D will differ on how permission is handled:
  // B: PermissionDialog? permissionDialog,
  // D: Future<PermissionDecision> Function(String origin)? onPermissionRequested,
})
```

#### `_handleSessionStart` changes (both B and D)

**Current behavior:** validates origin, creates session, immediately sends `session_ready`.

**New behavior:**
1. Validate origin (same as now)
2. Create session via `_sessions.create(origin, tutorialUrl)` — state is `pending`
3. Associate channel with sessionId
4. **Do NOT send `session_ready` yet** — the session is pending, waiting for first `exec`
5. Log: "Session pending: $sessionId (awaiting first exec)"

#### `_handleExec` changes (both B and D)

**Current behavior:** checks sanitizer, returns `NOT_IMPLEMENTED`.

**New behavior:**
1. Look up session; return `SESSION_UNKNOWN` error if not found
2. Run sanitizer check; return `COMMAND_BLOCKED` if unsafe
3. **If session state is `pending`:**
   a. Set state to `authorizing`
   b. **Request permission** (B and D differ here — see below)
   c. If **Deny**: set state to `purged`, remove session, send `session_denied`, close WebSocket
   d. If **Allow**: set state to `provisioning`
4. **If session state is `provisioning`:**
   a. Call `_multipass.launch(vmName: session.vmName!)`
   b. On success: set state to `ready`, send `session_ready { session_id, vm_name }`
   c. On failure: send `error { code: "VM_LAUNCH_FAILED", message: "..." }`, set state back to `pending` so user can retry
5. **If session state is `ready`:**
   a. Call `_multipass.exec(vmName: session.vmName!, command: command)`
   b. Stream each `CommandOutput` as an `output` message to the client
   c. On completion, send `exec_done { session_id, exit_code }`
   d. On error during exec, send `error` message

**Approach B (callback-based):**
```dart
// The server holds a PermissionDialog and calls showDialog directly
final decision = await _permissionDialog.requestTutorialPermission(
  context: _navigatorKey.currentContext!,
  origin: session.origin,
);
```

**Approach D (continuation-based):**
```dart
// The server holds a callback, not a dialog. The UI layer registers it.
final decision = await _onPermissionRequested!(session.origin);
```

#### `_handleSessionResume` changes (both B and D)

**Current behavior:** looks up session, checks expiry, sends `session_ready`.

**New behavior (add to existing):**
1. Same lookup and expiry check as now
2. **Also call `_sessions.cancelExpiry(sessionId)`** to cancel any active 30-min timer
3. Associate channel with sessionId
4. Send `session_ready` (keep existing behavior)

#### `_handleFinish` changes (both B and D)

**Current behavior:** sets state to purged, removes session, sends `NOT_IMPLEMENTED`.

**New behavior:**
1. Look up session; return error if not found
2. Call `_multipass.delete(vmName: session.vmName!, purge: true)` — **fire-and-forget**
3. Call `_sessions.remove(sessionId)` (which cancels any timer)
4. Send `exec_done { session_id, exit_code: 0 }` as acknowledgment
5. Close the WebSocket channel

#### `_onConnectionClosed` changes (both B and D)

**Current behavior:** sets state to `expiring`, sets `expiresAt`, logs.

**New behavior (enhance existing):**
1. Same as current
2. **Call `_sessions.startExpiry(sessionId, onExpire: () { ... })`**
3. The `onExpire` callback must:
   - Call `_multipass.delete(vmName: session.vmName!, purge: true)` (fire-and-forget)
   - Call `_sessions.remove(sessionId)`
   - Log: "Session $sessionId expired, VM purged"

### 5. Main (`lib/main.dart`) — Subagent C

Wire the new dependencies:

```dart
// Create instances
final multipass = MultipassWrapper();
final permissionDialog = const PermissionDialog();

_server = WebSocketServer(
  multipass: multipass,
  permissionDialog: permissionDialog,  // if using approach B
  // OR
  onPermissionRequested: (origin) => permissionDialog.requestTutorialPermission(
    context: navigatorKey.currentContext!,
    origin: origin,
  ),  // if using approach D
);
```

Also, set up the navigator key on `MaterialApp`:

```dart
MaterialApp(
  navigatorKey: navigatorKey,
  // ...
)
```

---

## State Machine Diagram

```
                    session_start
                         │
                         ▼
                      pending ─────────────────────────────────────┐
                         │                                          │
                    first exec                                      │
                         │                                          │
                         ▼                                          │
                    authorizing                                     │
                      │       │                                     │
                  Allow│       │Deny                                 │
                      ▼       ▼                                     │
                  provisioning   purged (session_denied, WS closed) │
                      │                                              │
                 launch OK                                           │
                      ▼                                              │
                     ready ─── exec ─── output ─── exec_done ──┐    │
                      │                                         │    │
                      │ ◄───────────────────────────────────────┘    │
                      │                                              │
             WS close │                                              │
                      ▼                                              │
                   expiring ─── 30 min ─── purged (VM deleted)      │
                      │                                              │
              resume  │                                              │
                      ▼                                              │
                     ready ◄────────────────────────────────────────┘
                      │
            finish    │
                      ▼
                   purged (VM deleted, WS closed)
```

---

## Acceptance Criteria

1. **Origin rejected:** Connect with an invalid origin → receive `session_denied` → WebSocket closes
2. **Origin accepted, no VM yet:** Connect with valid origin → WebSocket stays open, no `session_ready` sent
3. **First exec triggers dialog:** Send `exec` → permission dialog appears (Allow/Deny)
4. **Deny:** Click Deny → receive `session_denied` → WebSocket closes
5. **Allow:** Click Allow → VM launches → receive `session_ready { session_id, vm_name }`
6. **Subsequent execs:** After `session_ready`, send `exec` → command runs → receive `output` messages → receive `exec_done`
7. **Session resume:** Close WebSocket, reconnect with `session_resume` → receive `session_ready` with same session_id
8. **30-min expiry:** Close WebSocket, wait (or use a short timer for testing) → VM is purged, session removed
9. **Finish:** Send `finish` → VM purged, WebSocket closes
10. **Command blocked:** Send a blocked command → receive `error { code: "COMMAND_BLOCKED" }`

---

## Testing Strategy

Since Day 2 (`MultipassWrapper`) is not yet implemented, create a **fake/mock** `MultipassWrapper` for Day 3 testing:

```dart
class FakeMultipassWrapper extends MultipassWrapper {
  @override
  Future<String> launch({required String vmName}) async {
    await Future.delayed(const Duration(milliseconds: 500));
    return 'launched-$vmName';
  }

  @override
  Stream<CommandOutput> exec({required String vmName, required String command}) async* {
    yield const CommandOutput(stream: 'stdout', data: 'Hello from $vmName!\n');
    yield const CommandOutput(stream: 'stdout', data: 'Running: $command\n');
    await Future.delayed(const Duration(milliseconds: 300));
    yield const CommandOutput(stream: 'stderr', data: '');
  }

  @override
  Future<void> delete({required String vmName, bool purge = true}) async {
    // no-op for testing
  }
}
```

Use this fake in `main.dart` during development, and swap to the real `MultipassWrapper` once Day 2 is complete.

### Manual WebSocket Test Script

```javascript
// Test 1: Invalid origin → should get session_denied
const ws1 = new WebSocket('ws://127.0.0.1:50051');
ws1.onopen = () => ws1.send(JSON.stringify({
  type: 'session_start',
  origin: 'https://evil.com',
  tutorial_url: 'https://evil.com/test'
}));
ws1.onmessage = (e) => console.log('Test 1:', JSON.parse(e.data));
ws1.onclose = () => console.log('Test 1: connection closed');

// Test 2: Valid origin → stays open, no session_ready yet
const ws2 = new WebSocket('ws://127.0.0.1:50051');
ws2.onmessage = (e) => console.log('Test 2:', JSON.parse(e.data));
ws2.onopen = () => ws2.send(JSON.stringify({
  type: 'session_start',
  origin: 'http://localhost:8080',
  tutorial_url: 'http://localhost:8080/test'
}));

// Test 3: First exec → triggers dialog (check Agent UI)
// After dialog Allow:
ws2.send(JSON.stringify({
  type: 'exec',
  session_id: '<session_id_from_test_2>',
  command: 'echo hello'
}));
// Expect: session_ready, then output, then exec_done
```

---

## Files NOT to Modify

- `lib/agent/origin_validator.dart` — already complete from Day 1
- `lib/agent/command_sanitizer.dart` — Day 6 work; leave the stub as-is
- `lib/agent/multipass_wrapper.dart` — Day 2 work; leave the stub as-is (but wire it in)
- `lib/models/message.dart` — already complete
- `lib/platform/autostart_linux.dart` — already complete
- `lib/ui/tray_icon.dart` — already complete
- `lib/ui/status_window.dart` — Day 6 work; leave as-is
- `lib/proxy/tutorial_proxy.dart` — Day 5 work; leave as-is