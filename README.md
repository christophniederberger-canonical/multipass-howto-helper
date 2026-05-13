# Project Lighthouse

A cross-platform "Bridge Agent" that connects official Canonical web tutorials to a user's local [Multipass](https://multipass.run/) installation. The agent runs as a local WebSocket server that receives commands from tutorial pages, executes them inside ephemeral Multipass VMs, and streams the output back to the browser in real time.

---

## Setup

### Prerequisites

- [Multipass](https://multipass.run/install) installed and in PATH
- [Flutter](https://docs.flutter.dev/get-started/install/linux) (non-snap recommended)
- Linux desktop dependencies:

```bash
sudo apt update
sudo apt install libgtk-3-dev libblkid-dev liblzma-dev libgconf-2-4 libnss3-dev libasound2-dev clang cmake ninja-build pkg-config
flutter config --enable-linux-desktop
```

### Install Flutter (non-snap)

```bash
cd ~
wget -O flutter.tar.xz https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.24.0-stable.tar.xz
tar xf flutter.tar.xz
export PATH="$PATH:~/flutter/bin"

# Persist
echo 'export PATH="$PATH:~/flutter/bin"' >> ~/.bashrc
source ~/.bashrc
```

### Verify Setup

```bash
flutter doctor -v        # all Linux desktop checks should pass
multipass version        # confirms Multipass is installed
```

---

## Architecture

```
[Browser: ubuntu.com/tutorials/...]
  └── JS Tutorial Controller  ← injected by Canonical (prod) or local proxy (dev)
        │  WebSocket  ws://localhost:50051
        ▼
[Lighthouse Agent: Flutter Desktop]
  ├── System tray icon
  ├── WebSocket server (port 50051)
  │     └── Debug: ws://  |  Release: wss:// with mkcert TLS
  ├── Message + session models (JSON protocol)
  ├── Multipass CLI wrapper (launch, exec streaming, delete --purge)
  ├── Session manager (pending → authorizing → provisioning → ready → expiring → purged)
  ├── Origin validator (ubuntu.com/canonical.com + localhost in debug)
  ├── Permission dialog (native Allow/Deny prompt)
  ├── Command sanitizer (blocklist of dangerous commands)
  └── Day 5–7 stubs ready to fill in

[Local JS Files: js/]
  ├── tutorial_controller.js  ← browser WebSocket client with UI injection
  └── tutorial_controller.css ← visual states for run buttons and output panels
```

---

## Quick Start

### 1. Run the Lighthouse Agent

```bash
cd lighthouse_agent
flutter clean
flutter pub get
flutter run
```

The agent starts a WebSocket server on `ws://localhost:50051` and shows a system tray icon.

### 2. Test the Agent (Node.js client)

```bash
cd test_client
npm install              # first time only
node test.js             # basic connection test
node test.js --multipass # full Multipass integration test
```

**Expected output:**
```
[12:54:39.030] PASS  Received session_ready
[12:54:39.030] INFO  Session ID: 1158b6e7-4396-4445-8989-b5abe8f9ddd8
[12:54:39.030] INFO  VM Name: lighthouse-1158b6e7
```

### 3. Test the Browser Controller (Day 4)

Since Day 5 (local proxy) is not yet implemented, serve the JS files with a simple HTTP server:

```bash
# In a new terminal, serve the test client directory
cd test_client
npx serve .
# or: python3 -m http.server 8080
```

Open `http://localhost:8080/index.html` in your browser:

1. The page simulates a tutorial with `<pre><code>` blocks
2. `tutorial_controller.js` auto-initializes on page load
3. "▶ Run" buttons are injected next to each code block
4. Clicking Run connects to the agent and executes via Multipass
5. Live output streams back and displays below each block

#### Load JS on Any Page

To test the controller on any webpage, open the browser console and run:

```javascript
const link = document.createElement('link');
link.rel = 'stylesheet';
link.href = 'http://localhost:8080/js/tutorial_controller.css';
document.head.appendChild(link);

const script = document.createElement('script');
script.src = 'http://localhost:8080/js/tutorial_controller.js';
document.body.appendChild(script);
```

---

## Running Tests

```bash
cd lighthouse_agent
flutter test
```

All tests pass. `multipass_wrapper_test.dart` uses mocked processes and does not require Multipass.

---

## Current Status

| Day | Focus | Status |
|---|---|---|
| Day 1 | Scaffold, tray icon, WSS server skeleton, autostart | **Complete** |
| Day 2 | Multipass CLI wrapper (launch, exec streaming, delete) | **Complete** |
| Day 3 | Session manager, origin validation, permission dialog | **Complete** |
| Day 4 | JS tutorial controller (browser side) | **Complete** |
| Day 5 | Local test proxy + end-to-end integration | Not started |
| Day 6 | Status window, command sanitizer | Not started |
| Day 7 | Buffer, polish, demo prep | Not started |

---

## Development Notes

- **Framework:** Flutter Desktop 3.41.9 (stable), Dart 3.11.5
- **Primary platform:** Linux — macOS/Windows are stretch goals
- Build artifacts contain absolute paths — always run `flutter clean` when switching environments
- System tray is a placeholder stub on Linux (real `tray_manager` plugin removed due to snap toolchain linker incompatibility)
- TLS certificates not auto-generated yet (release build logs a TODO)

## Branching Strategy

Each day's work is on a dedicated branch: `main`, `day1`, `day2`, `day3`, `day4`.

```bash
git checkout day4
```
