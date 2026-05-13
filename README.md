# Project Lighthouse

A cross-platform "Bridge Agent" that connects official Canonical web tutorials to a user's local [Multipass](https://multipass.run/) installation. The agent runs as a local WebSocket server that receives commands from tutorial pages, executes them inside ephemeral Multipass VMs, and streams the output back to the browser in real time.

## Current Status: Day 2 Complete ✅

| Day | Focus | Status |
|---|---|---|
| Day 1 | Scaffold, tray icon, WSS server skeleton, autostart | **Complete** |
| Day 2 | Multipass CLI wrapper (launch, exec streaming, delete) | **Complete** |
| Day 3 | Session manager, origin validation, permission dialog | Not started |
| Day 4 | JS tutorial controller (browser side) | Not started |
| Day 5 | Local test proxy + end-to-end integration | Not started |
| Day 6 | Status window, command sanitizer | Not started |
| Day 7 | Buffer, polish, demo prep | Not started |

## Architecture

```
[Browser: ubuntu.com/tutorials/...]
  └── JS Tutorial Controller  ← injected by Canonical (prod) or local proxy (dev)
        │  WebSocket  wss://localhost:50051
        ▼
[Lighthouse Agent: Flutter Desktop]
  ├── System tray icon (Linux placeholder for now)
  ├── WebSocket server (port 50051)
  │     └── Debug: ws://  |  Release: wss:// with mkcert TLS
  ├── Message + session models (JSON protocol)
  ├── Multipass CLI wrapper (launch, exec streaming, delete --purge)
  └── Day 3–7 stubs ready to fill in
```

## Repository Layout

| Path | Description |
|---|---|
| `project-plan.md` | Original product brief |
| `engineering-plan.md` | Detailed engineering plan with protocol spec, lifecycle, schedule |
| `prompts/day1.md` | Day 1 implementation prompt |
| `prompts/day2.md` | Day 2 implementation prompt |
| `lighthouse_agent/` | Flutter Desktop application (Linux primary) |
| `lighthouse_agent/lib/models/message.dart` | WebSocket JSON message codec |
| `lighthouse_agent/lib/models/session.dart` | Session state enum + model |
| `lighthouse_agent/lib/agent/websocket_server.dart` | WSS server (debug ws / release wss) |
| `lighthouse_agent/lib/agent/multipass_wrapper.dart` | Multipass CLI wrapper (launch, exec, delete) |
| `lighthouse_agent/lib/platform/autostart_linux.dart` | XDG autostart registration |
| `lighthouse_agent/lib/main.dart` | App entry point with startup sequence |

## Quick Start (Host)

```bash
# 1. Navigate into the Flutter app
cd lighthouse_agent

# 2. Clean any VM-specific build artifacts
flutter clean
flutter pub get

# 3. Run in debug mode (ws:// on localhost:50051)
flutter run

# 4. Or build the binary
flutter build linux --debug
./build/linux/x64/debug/bundle/lighthouse_agent
```

## Testing the WebSocket Server

### Basic Connection Test

Open any regular website (e.g., `about:blank`) in your browser, open DevTools → Console, and paste:

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

Expected response:
```
Received: {type: 'agent_error', code: 'NOT_IMPLEMENTED', message: 'Day 2 WebSocket skeleton received the message'}
```

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

## Testing from a Multipass VM (Parallel Development)

If you are editing code inside a Multipass VM while testing on the host:

1. **Always `flutter clean` when switching** between VM and host before building
2. The source files are shared, but build artifacts contain absolute paths
3. Run the agent on the **host** for easiest browser testing (no port forwarding needed)

## Known Limitations (Day 2)

- System tray is a placeholder stub on Linux (real `tray_manager` plugin removed due to `libayatana-appindicator` linker incompatibility with the snap Flutter toolchain in the VM)
- TLS certificates are not auto-generated yet (release build will log a TODO)
- No session state machine, origin validation, or permission dialog yet (Day 3)
- No browser-side JS tutorial controller yet (Day 4)
- No local HTTP proxy for development yet (Day 5)

## Development Environment Notes

- **Framework:** Flutter Desktop 3.41.9 (stable), Dart 3.11.5
- **Primary platform:** Linux
- **macOS/Windows:** Stretch goals, not yet configured
- The project was scaffolded and validated inside a Multipass VM running Ubuntu with a snap-based Flutter SDK. Build fixes were applied to handle the snap toolchain's linker/ABI constraints.

## Development Environment Setup

### Option 1: Host Development (Recommended)

For the best development experience, work directly on your host machine:

1. **Install Flutter** (not via snap): https://docs.flutter.dev/get-started/install/linux
2. **Install Linux desktop dependencies**:
   ```bash
   sudo apt install libgtk-3-dev libblkid-dev liblzma-dev
   ```
3. **Install Multipass**: https://multipass.run/install
4. **Clone the repository** and navigate to the project:
   ```bash
   cd lighthouse_agent
   flutter pub get
   flutter run
   ```

### Option 2: Multipass VM Development

If you prefer an isolated environment or need to test on a clean Ubuntu install:

1. **Launch a Multipass VM with Flutter**:
   ```bash
   multipass launch --name flutter-dev --disk 20G --mem 4G
   multipass shell flutter-dev
   ```

2. **Inside the VM, install the snap Flutter SDK**:
   ```bash
   sudo snap install flutter --classic
   flutter config --enable-linux-desktop
   ```

3. **Install dependencies**:
   ```bash
   sudo apt update
   sudo apt install libgtk-3-dev libblkid-dev liblzma-dev
   ```

4. **Important: Build artifacts are NOT portable**
   - Always run `flutter clean` when switching between host and VM
   - Build artifacts contain absolute paths and linked against the system's glibc/GTK libraries
   - The snap Flutter toolchain has additional linker constraints that required workarounds (see `lighthouse_agent/README.md` → Build Notes)

5. **For browser testing**, run the agent on the **host** (not the VM) to avoid port forwarding:
   ```bash
   # On host
   cd lighthouse_agent
   flutter run
   ```

### Running Tests

```bash
cd lighthouse_agent
flutter test
```

All tests should pass. The `multipass_wrapper_test.dart` uses mocked processes and does not require Multipass to be installed.

### Building for Release

```bash
cd lighthouse_agent
flutter build linux --release
```

The release binary will be at `build/linux/x64/release/bundle/lighthouse_agent`.

### Branching Strategy

Each day's work is implemented on a dedicated branch:
- `main` — stable baseline
- `day1` — scaffold, tray, WSS skeleton, autostart
- `day2` — multipass CLI wrapper
- `day3` — session manager, origin validation, permission dialog (upcoming)

To switch to a day's branch:
```bash
git checkout day2
```

