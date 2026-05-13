# Implementation Brief: Project "Lighthouse"

**Role:** Senior Systems Architect / Product Manager

**Objective:** Build a cross-platform "Bridge Agent" that connects official Canonical web tutorials to a user's local Multipass installation without modifying the Multipass source code.

---

## 1. System Architecture

| Component | Description |
|---|---|
| **The Web Client** | A JavaScript "Tutorial Controller" injected into `*.ubuntu.com` or `*.canonical.com`. Communicates via WebSockets to localhost. |
| **The Lighthouse Agent** | A standalone, cross-platform GUI application (Windows, macOS, Linux). Acts as a secure proxy between the browser and the Multipass CLI. |
| **The Execution Engine** | Existing Multipass CLI (`multipass launch`, `multipass exec`, `multipass delete`). |

---

## 2. Core Functional Requirements

### A. Lifecycle Management

- **Automatic Provisioning:** When a tutorial starts, the Agent must trigger `multipass launch` to create a fresh, uniquely named VM instance.
- **State Persistence:** If a user closes the browser tab, the Agent must keep the VM alive for 30 minutes before auto-purging (`delete --purge`). This allows for accidental tab closures or browser restarts.
- **Cleanup:** The Agent provides a "Finish Tutorial" hook that immediately destroys the VM.

### B. Command Execution & UI

- **Secure Execution:** The Agent receives shell commands from the browser and executes them via `multipass exec <vm-name> -- <command>`.
- **Live Console Stream:** The Agent must capture stdout and stderr in real-time and stream it back to the browser via WebSockets.
- **Browser UI:** The web component should display a "Console" window that can be toggled (hidden/shown). Non-technical users should see a clean "Success" indicator by default, with the option to inspect the "technical details" (console output).

### C. Security Protocol (The "Guardrail")

- **Origin Validation:** The Agent must reject any request not originating from `*.ubuntu.com` or `*.canonical.com`.
- **Session Authorization:** Upon the first command of a tutorial session, the Agent must prompt the user with a native OS dialog: *"Allow 'Ubuntu Tutorials' to run commands in a Multipass VM? [Allow / Deny]"*.
- **Command Sanitization:** Filter and block commands that attempt to escape the VM (e.g., restricted use of `mount` or host-level path manipulation).

---

## 3. Technical Constraints

- **Platform:** Must be written in a cross-platform framework. Go (with a lightweight TUI/GUI) or Flutter (Desktop) is preferred to ensure a single codebase for Linux, Windows, and macOS.
- **Communication:** Use WebSockets (port `50051`) for the browser-to-agent link to support real-time data streaming.
- **Interface:** Use the Multipass CLI as the primary interface. Do not attempt to link against `libmultipass` C++ libraries directly to avoid versioning conflicts.

---

## 4. Development Phases (Suggested)

| Phase | Description |
|---|---|
| Phase 1 | Create the Local WebSocket server and CLI wrapper logic. |
| Phase 2 | Implement Origin Whitelisting and the "Allow/Deny" User Prompt. |
| Phase 3 | Build the JavaScript snippet for the browser to "handshake" with the Agent. |
| Phase 4 | Implement the 30-minute "Heartbeat/Timeout" logic for VM cleanup. |
