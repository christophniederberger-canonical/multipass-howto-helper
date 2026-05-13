# lighthouse_agent

Flutter Desktop application for **Project Lighthouse** — a local bridge agent that connects Canonical web tutorials to a user's Multipass installation via WebSocket.

## What It Does (End Goal)

- Runs in the system tray as a background agent
- Accepts WebSocket connections from tutorial pages on `localhost:50051`
- Spawns ephemeral Multipass VMs per tutorial session
- Executes commands inside VMs and streams output back to the browser in real time
- Auto-cleans VMs after 30 minutes of browser inactivity

## Day 2 Status ✅

### What's Working

| Component | File | Status |
|---|---|---|
| WebSocket server skeleton | `lib/agent/websocket_server.dart` | ✅ Accepts connections, parses JSON messages, replies with `NOT_IMPLEMENTED` |
| Message codec (JSON) | `lib/models/message.dart` | ✅ All protocol messages defined with `toJson`/`fromJson` |
| Session model | `lib/models/session.dart` | ✅ Enum + data model ready |
| Linux autostart registration | `lib/platform/autostart_linux.dart` | ✅ Writes `~/.config/autostart/lighthouse.desktop` on first launch |
| App startup sequence | `lib/main.dart` | ✅ Tray init → autostart check → cert check → multipass check → WSS server start |
| Release vs debug mode | `lib/agent/websocket_server.dart` | ✅ Debug: `ws://` / Release: `wss://` (cert loading skeleton) |
| **Multipass wrapper** | `lib/agent/multipass_wrapper.dart` | ✅ **Day 2: launch, exec streaming, delete --purge** |
| **Multipass detection** | `lib/main.dart` | ✅ **Day 2: checks PATH at startup, tray error state if missing** |
| **Tray tooltip** | `lib/ui/tray_icon.dart` | ✅ **Day 2: reflects multipass availability** |
| **WS test hook** | `lib/agent/websocket_server.dart` | ✅ **Day 2: `__test_multipass__` for manual E2E validation** |

### Stubs Ready for Future Days

| Component | File | Day |
|---|---|---|
| Session manager | `lib/agent/session_manager.dart` | Day 3 |
| Origin validator | `lib/agent/origin_validator.dart` | Day 3 |
| Command sanitizer | `lib/agent/command_sanitizer.dart` | Day 6 |
| Permission dialog | `lib/ui/permission_dialog.dart` | Day 3 |
| Status window | `lib/ui/status_window.dart` | Day 6 |
| Tutorial proxy | `lib/proxy/tutorial_proxy.dart` | Day 5 |

## Running Locally

### Prerequisites

- Flutter 3.x with Linux desktop support
- `flutter doctor` passes for Linux toolchain
- Linux dev libraries: `sudo apt install libgtk-3-dev libblkid-dev liblzma-dev`
- **Multipass** (for Day 2+ functionality): [Install Multipass](https://multipass.run/install)

### Debug (ws://, no TLS)

```bash
flutter run
```

The app starts a WebSocket server on `ws://127.0.0.1:50051`.

If Multipass is not in PATH, the tray will show an error state and the log will display:
```
Multipass not found in PATH. Please install Multipass.
```

### Release (wss://, requires mkcert certs)

```bash
flutter build linux --release
./build/linux/x64/release/bundle/lighthouse_agent
```

Release mode expects TLS certificates at:
- `~/.local/share/lighthouse/localhost.pem`
- `~/.local/share/lighthouse/localhost-key.pem`

These are **not** auto-generated yet (Day 1 TODO).

## Testing

### Recommended: Local Test Client (Node.js)

The easiest way to test the agent is with the included Node.js test client in `../test_client/`:

```bash
# Install dependencies (first time only)
cd ../test_client
npm install

# Basic connection test
node test.js

# Full multipass integration test (requires multipass installed)
node test.js --multipass
```

### Alternative: Browser Console Test

1. Open any regular web page (e.g., `about:blank`)
2. Open DevTools → Console
3. Paste:

```javascript
const ws = new WebSocket('ws://127.0.0.1:50051');
ws.onopen = () => {
  ws.send(JSON.stringify({
    type: 'session_start',
    origin: 'http://localhost:8080',
    tutorial_url: 'http://localhost:8080/test'
  }));
};
ws.onmessage = (e) => console.log('Received:', JSON.parse(e.data));
ws.onerror = (e) => console.error('Error:', e);
```

Expected output:
```
Received: {type: 'session_ready', session_id: '...', vm_name: 'lighthouse-...'}
```

> **Note:** If you get a connection error, make sure the agent is running (`flutter run`). Also, some snap/flatpak browsers have restricted localhost access — try Firefox (deb) or Chrome (.deb) if your browser is a snap.

### Multipass Integration Test (Day 2)

To verify the Multipass wrapper works end-to-end, send the special test command:

```javascript
const ws = new WebSocket('ws://127.0.0.1:50051');
ws.onopen = () => {
  ws.send(JSON.stringify({
    type: 'exec',
    session_id: 'test-session-123',
    command: '__test_multipass__'
  }));
};
ws.onmessage = (e) => console.log('Received:', JSON.parse(e.data));
```

This will:
1. Launch a temporary VM (`lighthouse-test-<timestamp>`)
2. Run `echo hello from multipass` inside it
3. Stream the output back as `output` messages
4. Send `exec_done` with the exit code
5. Delete the VM

**Requires Multipass to be installed and in PATH.**

## Build Notes for This Environment

The project was scaffolded inside a Multipass VM using the **snap Flutter SDK**. Several build fixes were needed:

1. **`path_provider` replaced with `path_provider_linux`** — the cross-platform package pulled in Android/iOS native toolchain dependencies (`jni_flutter`, `objective_c`, `native_toolchain_c`) that failed to link under the snap toolchain.
2. **`tray_manager` replaced with a Linux stub** — the `libayatana-appindicator` library caused glibc/GTK symbol mismatches when linking against the snap-bundled libraries.
3. **CMake toolchain override** — `linux/CMakeLists.txt` forces system `clang/clang++/ld` to avoid ABI mismatches.
4. **Deprecation warning policy** — `-Wno-error=deprecated-declarations` was added to handle upstream plugin deprecation warnings without failing the build.

If building on a **non-snap Flutter installation** (recommended for host development), these workarounds may be unnecessary.

## Project Structure

```
lib/
  main.dart                          ← Entry point, startup sequence
  agent/
    websocket_server.dart              ← WSS listener (ws debug / wss release)
    session_manager.dart               ← Stub: session state machine
    origin_validator.dart              ← Stub: origin allowlist check
    command_sanitizer.dart             ← Stub: command blocklist
    multipass_wrapper.dart             ← Stub: multipass CLI wrappers
  ui/
    tray_icon.dart                     ← Linux-safe fallback (placeholder)
    status_window.dart                 ← Stub: active sessions window
    permission_dialog.dart               ← Stub: Allow/Deny dialog
  models/
    message.dart                       ← JSON message codec (sealed classes)
    session.dart                       ← Session enum + model
  platform/
    autostart_linux.dart               ← XDG autostart registration
  proxy/
    tutorial_proxy.dart                ← Stub: local HTTP proxy on :8080
assets/
  icon_normal.png                      ← Placeholder tray icon (green)
  icon_error.png                       ← Placeholder tray icon (red)
```
