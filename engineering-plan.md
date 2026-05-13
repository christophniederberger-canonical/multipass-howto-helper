# Project Lighthouse — Engineering Plan

---

## Decisions

| Topic | Decision |
|---|---|
| Framework | Flutter Desktop, latest stable 3.x |
| Platforms | Linux (primary), macOS, Windows (stretch) |
| UI | System tray icon + status window |
| WebSocket | `wss://` port 50051, mkcert TLS; debug build uses `ws://` + allows `localhost` origin |
| Protocol | JSON messages (protobuf as stretch goal) |
| VM model | One VM per browser tab/session; `session_resume` reattaches to same VM on refresh within 30 min |
| Multi-session | Supported; all active sessions shown in status window |
| JS delivery | Production: Canonical embeds in tutorial pages; Development: HTTP proxy on `:8080` |
| Command sanitization | Blocklist-based; allowlist as future hardening |
| Timeline | Hackathon, ≤1 week, solo developer |
| MVP goal | End-to-end demo: browser → Agent → VM → output streamed back |
| Multipass | Latest stable, CLI only (no `libmultipass`) |
| Tutorial target | TBD — simplest available `ubuntu.com` tutorial |

---

## Architecture

Three components:

```
[Browser: ubuntu.com/tutorials/...]
  └── [JS Tutorial Controller]  ← injected by Canonical (prod) or local proxy (dev)
        │  WebSocket  wss://localhost:50051
        ▼
[Lighthouse Agent: Flutter Desktop]
  ├── System Tray Icon  (error state if multipass missing)
  ├── Status Window  (active sessions table)
  ├── WSS Server  (mkcert TLS, port 50051)
  ├── Session Manager  (VM lifecycle, 30-min close-event timer, session_resume)
  ├── Origin Validator  (*.ubuntu.com, *.canonical.com; localhost in debug only)
  ├── Native Allow/Deny Dialog  (fires on first exec, not on connect)
  ├── Command Sanitizer  (blocklist)
  └── Multipass CLI Wrapper  (launch / exec streaming / delete --purge)

[Local Test Proxy: port 8080]  ← dev-only
  └── Fetches Canonical tutorial pages
  └── Injects <script src="/js/tutorial_controller.js">
  └── Serves over HTTP (Agent runs in ws:// debug mode to avoid mixed-content)
```

---

## WebSocket Protocol (JSON)

### Client → Agent

| Message | Fields | Notes |
|---|---|---|
| `session_start` | `origin`, `tutorial_url` | Sent on page load |
| `session_resume` | `session_id` | Sent if sessionStorage has an existing session_id; Agent reattaches or returns error |
| `exec` | `session_id`, `command` | First exec triggers Allow/Deny dialog |
| `finish` | `session_id` | Immediately purges VM |

> **Note:** `heartbeat` is not used. The WebSocket close event alone triggers the 30-minute countdown.

### Agent → Client

| Message | Fields | Notes |
|---|---|---|
| `session_ready` | `session_id`, `vm_name` | Agent generates session_id |
| `session_denied` | — | Agent closes WebSocket after sending |
| `output` | `session_id`, `stream` (stdout\|stderr), `data` | Real-time stream |
| `exec_done` | `session_id`, `exit_code` | Browser maps exit 0 → success, non-zero → failure |
| `error` | `session_id`, `code`, `message` | General errors (VM launch failure, sanitizer block, etc.) |
| `agent_error` | `code`, `message` | Agent-level errors (multipass not found, cert issue) |

---

## Session Lifecycle

```
1.  Browser opens WebSocket to wss://localhost:50051
     ├── If Agent not running → connection refused → JS shows "Download Lighthouse Agent" banner
     └── Connected → send session_start (or session_resume if sessionStorage has session_id)

2.  session_resume path:
     ├── Agent finds live session → sends session_ready (same session_id, same VM)
     └── Session expired/unknown → sends error; browser falls back to session_start

3.  session_start path:
     ├── Agent validates origin (allowlist: *.ubuntu.com, *.canonical.com; localhost in debug build)
     ├── Origin rejected → send session_denied, close WebSocket
     └── Origin accepted → Agent is ready, waiting for first exec

4.  First exec command received:
     ├── Agent shows native OS Allow/Deny dialog:
     │     "Allow 'Ubuntu Tutorials' to run commands in a Multipass VM?"
     ├── Deny → send session_denied, close WebSocket; JS shows "Permission denied" on all Run buttons
     └── Allow → multipass launch --name lighthouse-<8-char-uuid>
                  send session_ready { session_id, vm_name }

5.  Subsequent exec commands:
     └── Agent runs: multipass exec <vm> -- <command>
          ├── Command sanitizer check: blocked → send error, command NOT executed
          └── Allowed → stream output messages in real-time; send exec_done on completion

6.  WebSocket closes (tab closed / navigation / crash):
     └── Agent starts 30-minute timer
          ├── Browser reconnects + session_resume within 30 min → timer cancelled, session restored
          └── Timer expires → multipass delete --purge <vm>

7.  finish message received:
     └── Immediate: multipass delete --purge <vm>; session removed
```

---

## Flutter Project Structure

```
lib/
  main.dart                        ← app entry, tray init, WSS server start, autostart registration
  agent/
    websocket_server.dart          ← WSS listener, message dispatch, debug/release mode flag
    session_manager.dart           ← session state machine, VM map, close-event timers
    origin_validator.dart          ← allowlist check (debug vs. release behaviour)
    command_sanitizer.dart         ← blocklist patterns
    multipass_wrapper.dart         ← Process.start() wrappers: launch, exec (streaming), delete
  ui/
    tray_icon.dart                 ← system tray (tray_manager); normal / error states
    status_window.dart             ← DataTable: session_id, VM name, tutorial URL, status, elapsed
    permission_dialog.dart         ← native Allow/Deny dialog
  models/
    session.dart                   ← session state enum + model
    message.dart                   ← sealed classes for all WS message types
  proxy/
    tutorial_proxy.dart            ← shelf HTTP proxy on :8080; injects JS; debug only
js/
  tutorial_controller.js           ← browser WS client, Run buttons, console UI, install banner
```

---

## VM Naming

Format: `lighthouse-` + first 8 characters of a UUID v4 (e.g. `lighthouse-3f7a1b2c`).

- Fits within Multipass's 63-character name limit.
- No underscores (Multipass rejects them).
- Unique enough for concurrent sessions on a single machine.

---

## mkcert TLS Setup (First Launch)

1. On first run, check for `~/.local/share/lighthouse/localhost.pem`.
2. If missing: check `mkcert` in PATH; if absent, show setup screen with installation instructions (or offer to download bundled binary).
3. Run `mkcert -install` — user sees one-time elevated prompt to trust the local CA.
4. Run `mkcert -cert-file <appdata>/localhost.pem -key-file <appdata>/localhost-key.pem localhost 127.0.0.1 ::1`.
5. WSS server loads cert from app data directory on every start.
6. Cert is regenerated if expired or file missing.

**Debug build:** `ws://` mode active; skip TLS setup. Agent also accepts `localhost` as a valid origin.

---

## OS Autostart Registration (First Launch)

| Platform | Mechanism |
|---|---|
| Linux | Write `~/.config/autostart/lighthouse.desktop` (XDG autostart spec) |
| macOS | Write `~/Library/LaunchAgents/com.canonical.lighthouse.plist` |
| Windows | Add registry key `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` (post-hackathon) |

Registration happens once on first launch. The status window includes a toggle to disable autostart.

---

## Command Sanitization Blocklist

| Type | Blocked patterns |
|---|---|
| Commands | `mount`, `umount`, `mkfs`, `fdisk`, `modprobe`, `insmod` |
| Path patterns | `/proc/`, `/sys/`, `/dev/`, `../../`, `--host` |
| Multipass flags | `mount`, `transfer` (if somehow invoked inside exec) |

When a command is blocked: Agent sends `error { code: "COMMAND_BLOCKED", message: "..." }` and does **not** execute the command. The browser shows the error inline below the code block.

---

## Browser UI Specification (JS Tutorial Controller)

### On page load
- Attempt WebSocket connection to `wss://localhost:50051` (or `ws://` in dev).
- **Connection refused:** inject "Download Lighthouse Agent" install banner at top of page. Do not inject Run buttons.
- **Connected:** scan DOM for `<pre><code>` blocks; inject "▶ Run" button per block.

### Per-command block states
| State | UI |
|---|---|
| Idle | "▶ Run" button visible |
| Running | Spinner; "▶ Run" button disabled |
| Success (exit 0) | Green ✓ indicator inline |
| Failure (non-zero exit) | Red ✗ indicator inline |
| Blocked | Orange ⚠ indicator + error message |

- Each block has a collapsible "View output" section below it showing raw stdout/stderr.
- Output is appended in real-time as `output` messages arrive.

### Console panel (sidebar/overlay)
- Togglable panel showing all output for the current session.
- Contains a "Finish Tutorial" button (sends `finish` message → confirms VM will be destroyed).

### Page bottom
- "Finish Tutorial" button injected after the last content block.

### Permission denied state
- All Run buttons replaced with "⚠ Permission denied" label (non-interactive).

### Session persistence
- On `session_ready`: store `session_id` in `sessionStorage`.
- On page load: if `sessionStorage` has `session_id`, send `session_resume` before `session_start`.
- On `session_denied` or `error` on resume: clear `sessionStorage`, fall back to fresh `session_start`.

---

## Multipass Error Handling

| Scenario | Agent behaviour | Browser behaviour |
|---|---|---|
| `multipass` not in PATH at startup | Tray icon shows error state; tooltip: "Multipass not found" | `agent_error` sent on first connection; JS shows error banner |
| VM launch failure | Send `error` message | Show error inline; Run buttons remain available to retry |
| `multipass exec` non-zero exit | Stream output, send `exec_done { exit_code }` | Show failure indicator; output still visible |
| VM already deleted externally | Session lookup fails; send `error` | JS clears `sessionStorage`, starts fresh session |

---

## Hackathon 7-Day Schedule

### Day 1 — Scaffold + Autostart + TLS
- Flutter project, Linux desktop target
- `tray_manager` system tray (normal + error icon states)
- mkcert detection + cert generation logic
- WSS server skeleton (debug: `ws://`, release: `wss://`)
- XDG autostart registration on first launch

### Day 2 — Multipass CLI Wrapper
- `Process.start()` wrappers: `launch`, `exec` (real-time stdout/stderr stream), `delete --purge`
- `multipass` PATH detection; tray error state if missing
- Unit tests with mock subprocess (or real multipass)

### Day 3 — Session Manager + Security
- Session state machine: `pending → authorizing → provisioning → ready → expiring → purged`
- Origin validator (debug vs. release allowlists)
- Allow/Deny dialog (fires on first `exec`, not `session_start`)
- `session_resume` handling: reattach or return error
- WebSocket close-event → 30-minute `Timer` (no heartbeat)
- `session_denied` → close WebSocket

### Day 4 — JS Tutorial Controller
- WebSocket client (`wss://` / `ws://` based on page protocol)
- Agent-not-running detection → install banner (no Run buttons)
- DOM scan + "▶ Run" button injection per `<pre><code>` block
- Per-block status states (idle / running / success / failure / blocked)
- Collapsible raw output section per block
- `sessionStorage` session persistence + `session_resume` on page load
- "Finish Tutorial" button (page bottom + console panel)
- "Permission denied" state on `session_denied`

### Day 5 — Local Test Proxy + End-to-End Integration
- `shelf` HTTP proxy on `:8080`
- Fetch `https://ubuntu.com/tutorials/<slug>`, inject `<script src="/js/tutorial_controller.js">`
- Self-serve `tutorial_controller.js` at `/js/controller.js`
- Agent in debug `ws://` mode to avoid mixed-content issues
- Full E2E test: proxy → browser → Agent → multipass → output back to browser

### Day 6 — Status Window + Command Sanitizer + Console Panel
- Flutter `status_window.dart`: DataTable (session_id, VM name, tutorial URL, status, elapsed)
- Tray menu: "Show Status" + "Quit" (with active-session warning)
- Command sanitizer with full blocklist; `COMMAND_BLOCKED` error message to browser
- Console panel UI polish (toggle, session log, Finish Tutorial button)

### Day 7 — Buffer / Bugfix / Demo Prep
- Error handling edge cases (VM deleted externally, mkcert not installed, multipass absent)
- Demo script against simplest `ubuntu.com` tutorial
- README: setup steps (Flutter, mkcert, multipass, dev proxy)
- Smoke test all user stories

---

## User Stories

| # | Story | Day |
|---|---|---|
| 1 | Install Agent → starts in system tray; registered to autostart at login | 1 |
| 2 | Agent not running → tutorial page shows "Download Lighthouse Agent" banner | 4 |
| 3 | Dev opens `localhost:8080/tutorials/<slug>` → tutorial rendered with Run buttons | 5 |
| 4 | First Run click → native Allow/Deny dialog shown | 3 |
| 5 | Allow → VM launches; Run button shows spinner | 2+3 |
| 6 | Command executes; live stdout/stderr streamed to browser output section | 2+4 |
| 7 | Exit 0 → green ✓; non-zero → red ✗ shown inline | 4 |
| 8 | "View output" expands raw stdout/stderr per block | 4 |
| 9 | Close tab → VM persists 30 min, then auto-purged | 3 |
| 10 | Refresh tab within 30 min → same VM reattached (session_resume) | 3+4 |
| 11 | "Finish Tutorial" (page bottom or console) → VM immediately destroyed | 3+4 |
| 12 | Multiple sessions visible in Agent status window | 6 |
| 13 | Dangerous command blocked → orange ⚠ shown inline; VM unaffected | 6 |
| 14 | multipass not installed → tray error icon + browser error banner | 2 |
| 15 | Deny → "Permission denied" on all Run buttons; WebSocket closed | 3+4 |

---

## Verification Checklist

| Test | Type |
|---|---|
| `multipass_wrapper_test.dart` — mock Process, assert correct CLI args, stream output | Unit |
| `origin_validator_test.dart` — canonical / non-canonical / localhost origins | Unit |
| `command_sanitizer_test.dart` — all blocklisted commands return `COMMAND_BLOCKED` | Unit |
| `session_manager_test.dart` — state transitions, 30-min timer, session_resume with FakeAsync | Unit |
| Start Agent, open proxy page, click Run, verify output in browser | Integration |
| Close tab, mock timer expiry, verify `multipass list` shows no Lighthouse VM | Integration |
| Send `session_start` from non-canonical origin → verify `session_denied` + WebSocket closed | Security |
| Send `mount /host:/mnt` as exec command → verify `COMMAND_BLOCKED` error, VM untouched | Security |
| Release build: send `session_start` from `localhost` → verify rejected | Security |
| Refresh tab within 30 min → verify same VM still running and session reattached | E2E |

---

## Deliberate Scope Exclusions (MVP)

- No protobuf — JSON only for hackathon
- No Windows/macOS packaging — Linux binary only for demo
- No Snap packaging — post-hackathon
- No allowlist command sanitization — blocklist only
- No xterm.js / interactive terminal emulator — read-only output panel
- No multi-user / remote Agent support
