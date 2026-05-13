# Project Lighthouse

A cross-platform "Bridge Agent" that connects official Canonical web tutorials to a user's local [Multipass](https://multipass.run/) installation. The agent runs as a local WebSocket server that receives commands from tutorial pages, executes them inside ephemeral Multipass VMs, and streams the output back to the browser in real time.

## Current Status: Day 1 Complete ✅

| Day | Focus | Status |
|---|---|---|
| Day 1 | Scaffold, tray icon, WSS server skeleton, autostart | **Complete** |
| Day 2 | Multipass CLI wrapper | Not started |
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
  └── Day 2–7 stubs ready to fill in
```

## Repository Layout

| Path | Description |
|---|---|
| `project-plan.md` | Original product brief |
| `engineering-plan.md` | Detailed engineering plan with protocol spec, lifecycle, schedule |
| `prompts/day1.md` | Day 1 implementation prompt |
| `lighthouse_agent/` | Flutter Desktop application (Linux primary) |
| `lighthouse_agent/lib/models/message.dart` | WebSocket JSON message codec |
| `lighthouse_agent/lib/models/session.dart` | Session state enum + model |
| `lighthouse_agent/lib/agent/websocket_server.dart` | WSS server (debug ws / release wss) |
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
Received: {type: 'agent_error', code: 'NOT_IMPLEMENTED', message: 'Day 1 WebSocket skeleton received the message'}
```

## Testing from a Multipass VM (Parallel Development)

If you are editing code inside a Multipass VM while testing on the host:

1. **Always `flutter clean` when switching** between VM and host before building
2. The source files are shared, but build artifacts contain absolute paths
3. Run the agent on the **host** for easiest browser testing (no port forwarding needed)

## Known Limitations (Day 1)

- System tray is a placeholder stub on Linux (real `tray_manager` plugin removed due to `libayatana-appindicator` linker incompatibility with the snap Flutter toolchain in the VM)
- TLS certificates are not auto-generated yet (release build will log a TODO)
- No actual Multipass integration, origin validation, or session management yet

## Development Environment Notes

- **Framework:** Flutter Desktop 3.41.9 (stable), Dart 3.11.5
- **Primary platform:** Linux
- **macOS/Windows:** Stretch goals, not yet configured
- The project was scaffolded and validated inside a Multipass VM running Ubuntu with a snap-based Flutter SDK. Build fixes were applied to handle the snap toolchain's linker/ABI constraints.

