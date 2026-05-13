# Project Lighthouse

A cross-platform "Bridge Agent" that connects official Canonical web tutorials to a user's local [Multipass](https://multipass.run/) installation. The agent runs as a local WebSocket server that receives commands from tutorial pages, executes them inside ephemeral Multipass VMs, and streams the output back to the browser in real time.

## Current Status: Day 3 Complete ✅

| Day | Focus | Status |
|---|---|---|
| Day 1 | Scaffold, tray icon, WSS server skeleton, autostart | **Complete** |
| Day 2 | Multipass CLI wrapper (launch, exec streaming, delete) | **Complete** |
| Day 3 | Session manager, origin validation, permission dialog | **Complete** |
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
  ├── Session manager with full lifecycle (pending → authorizing → provisioning → ready → expiring → purged)
  ├── Origin validator (ubuntu.com/canonical.com domains + localhost in debug)
  ├── Permission dialog (native Allow/Deny prompt on first command)
  └── Day 4–7 stubs ready to fill in
```

## Repository Layout

| Path | Description |
|---|---|
| `project-plan.md` | Original product brief |
| `engineering-plan.md` | Detailed engineering plan with protocol spec, lifecycle, schedule |
| `prompts/` | Day-by-day implementation prompts |
| `prompts/day1.md` | Day 1 implementation prompt |
| `prompts/day2.md` | Day 2 implementation prompt |
| `prompts/day3.md` | Day 3 implementation prompt |
| `lighthouse_agent/` | Flutter Desktop application (Linux primary) |
| `lighthouse_agent/lib/models/message.dart` | WebSocket JSON message codec |
| `lighthouse_agent/lib/models/session.dart` | Session state enum + model with expiry timer |
| `lighthouse_agent/lib/agent/websocket_server.dart` | WSS server (debug ws / release wss) |
| `lighthouse_agent/lib/agent/session_manager.dart` | Session lifecycle manager with timer management |
| `lighthouse_agent/lib/agent/multipass_wrapper.dart` | Multipass CLI wrapper (launch, exec, delete) |
| `lighthouse_agent/lib/ui/permission_dialog.dart` | Native Allow/Deny permission dialog |
| `lighthouse_agent/lib/platform/autostart_linux.dart` | XDG autostart registration |
| `lighthouse_agent/lib/main.dart` | App entry point with startup sequence |
| `test_client/` | Node.js WebSocket test client |
| `test_client/test.js` | Basic connection + multipass integration tests |

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

### Recommended: Local Test Client (Node.js)

The easiest way to test the agent is with the included Node.js test client in `test_client/`:

```bash
# Install dependencies (first time only)
cd test_client
npm install

# Basic connection test
node test.js

# Full multipass integration test (requires multipass installed)
node test.js --multipass
```

**Expected output for basic test:**
```
[12:54:39.030] PASS  Received session_ready (agent has full session management)
[12:54:39.030] INFO  Session ID: 1158b6e7-4396-4445-8989-b5abe8f9ddd8
[12:54:39.030] INFO  VM Name: lighthouse-1158b6e7
```

**Expected output for multipass test:**
```
[12:54:53.626] OK  Session ready: 3114cf36-... (VM: lighthouse-3114cf36)
[12:56:45.244] RECV  { type: "output", stream: "stderr", data: "..." }
[12:56:45.246] RECV  { type: "exec_done", exit_code: 0 }
[12:56:45.246] PASS  Multipass integration test passed (exit code 0)
```

This will:
1. Launch a temporary VM (`lighthouse-test-<timestamp>`)
2. Run `echo hello from multipass` inside it
3. Stream the output back as `output` messages
4. Send `exec_done` with the exit code
5. Delete the VM

**Requires Multipass to be installed and in PATH.**
## Development Environment Notes

- **Framework:** Flutter Desktop 3.41.9 (stable), Dart 3.11.5
- **Primary platform:** Linux
- **macOS/Windows:** Stretch goals, not yet configured
- The project was scaffolded and validated inside a Multipass VM running Ubuntu with a snap-based Flutter SDK. Build fixes were applied to handle the snap toolchain's linker/ABI constraints.

## Development Environment Setup

### Prerequisites

Before starting development, ensure you have:

1. **Multipass** installed: https://multipass.run/install
2. **Git** for cloning the repository
3. **Flutter** (recommended: non-snap version for better compatibility)

### Option 1: Host Development (Recommended)

For the best development experience, work directly on your host machine:

1. **Install Flutter** (not via snap): https://docs.flutter.dev/get-started/install/linux
2. **Install Linux desktop dependencies**:
   ```bash
   # Download Flutter SDK
   cd ~
   wget -O flutter.tar.xz https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.24.0-stable.tar.xz
   tar xf flutter.tar.xz
   export PATH="$PATH:`pwd`/flutter/bin"
   
   # Add to your shell profile (~/.bashrc, ~/.zshrc, etc.)
   echo 'export PATH="$PATH:~/flutter/bin"' >> ~/.bashrc
   source ~/.bashrc
   ```
3. **Install Multipass**: https://multipass.run/install
4. **Clone the repository** and navigate to the project:
   ```bash
   flutter config --enable-linux-desktop
   ```

3. **Install Linux desktop dependencies**:
   ```bash
   sudo apt update
   sudo apt install libgtk-3-dev libblkid-dev liblzma-dev libgconf-2-4 libnss3-dev libasound2-dev clang cmake ninja-build pkg-config libgtk-3-dev libblkid-dev liblzma-dev
   ```

4. **Clone and set up the repository**:
   ```bash
   git clone <repository-url>
   cd multipass-howto-helper/lighthouse_agent
   flutter pub get
   flutter run
   ```

### Option 2: Multipass VM Development

If you prefer an isolated environment or need to test on a clean Ubuntu install:

1. **Launch a Multipass VM with sufficient resources**:
   ```bash
   multipass launch --name lighthouse-dev --disk 20G --mem 4G --cpus 2
   multipass shell lighthouse-dev
   ```

2. **Inside the VM, install dependencies**:
   ```bash
   # Update system
   sudo apt update
   
   # Install Git
   sudo apt install git
   
   # Install Flutter via snap
   sudo snap install flutter --classic
   flutter config --enable-linux-desktop
   
   # Install desktop dependencies
   sudo apt install libgtk-3-dev libblkid-dev liblzma-dev libgconf-2-4 libnss3-dev libasound2-dev clang cmake ninja-build pkg-config
   ```

3. **Install Multipass inside the VM** (for nested VM testing):
   ```bash
   sudo snap install multipass --classic
   ```

4. **Clone and set up the repository**:
   ```bash
   git clone <repository-url>
   cd multipass-howto-helper/lighthouse_agent
   flutter pub get
   ```

5. **Important: Build artifacts are NOT portable between environments**
   - Always run `flutter clean` when switching between host and VM development
   - Build artifacts contain absolute paths and are linked against the system's glibc/GTK libraries
   - The snap Flutter toolchain has additional linker constraints that may require workarounds

6. **For browser testing**, consider running the agent on the **host** (not the VM) to avoid port forwarding complications:
   ```bash
   # On host system
   cd multipass-howto-helper/lighthouse_agent
   flutter run
   ```

### Verifying Your Setup

Once you've set up your environment, verify everything works:

1. **Check Flutter doctor**:
   ```bash
   flutter doctor -v
   ```
   Make sure all Linux desktop checks pass.

2. **Test Multipass availability**:
   ```bash
   multipass version
   which multipass
   ```

3. **Run the agent**:
   ```bash
   cd lighthouse_agent
   flutter run
   ```
   You should see the agent start with a system tray icon and log that Multipass is detected.

4. **Run tests**:
   ```bash
   flutter test
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

