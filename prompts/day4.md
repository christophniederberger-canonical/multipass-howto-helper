# Day 4 — JS Tutorial Controller

## Goal

Implement the browser-side WebSocket client (`tutorial_controller.js`) that connects to the Lighthouse Agent, injects interactive "▶ Run" buttons into Canonical tutorial pages, streams live command output, and manages the full session lifecycle from the browser side. By the end of Day 4:

- The script detects whether the Agent is running and shows an install banner if not
- `<pre><code>` blocks on the page get a "▶ Run" button injected next to them
- Clicking Run connects (or reuses an existing session), executes the command, and shows live output
- Each block transitions through clear visual states: idle → running → success / failure / blocked
- Raw stdout/stderr is shown per block in a collapsible section
- `sessionStorage` persists the `session_id` so a page refresh reattaches to the same VM
- A "Finish Tutorial" button appears at the bottom of the page and inside a console panel
- `session_denied` puts all Run buttons into a non-interactive "Permission denied" state

---

## Execution Strategy: Parallel Subagents with Competition

This prompt launches **3 subagents in parallel**. Subagents A and B compete on the full `tutorial_controller.js`; the main agent reviews both and picks the better implementation (or cherry-picks the best parts). Subagent C produces CSS independently.

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
        │ Controller│   │ Controller│   │ Stylesheet│
        │ (class-   │   │ (function-│   │ tutorial_ │
        │  based OOP│   │  al/module│   │ controller│
        │  approach)│   │  approach)│   │ .css      │
        └───────────┘   └───────────┘   └───────────┘
              │                │
              └────── compete ─┘
               Main agent picks winner
```

### Subagent Assignments

| Subagent | Scope | Output |
|---|---|---|
| **A — OOP Controller** | Full `tutorial_controller.js` using a class-based approach | `js/tutorial_controller.js` |
| **B — Functional Controller** | Full `tutorial_controller.js` using a module/functional approach | `js/tutorial_controller.js` |
| **C — Stylesheet** | `js/tutorial_controller.css` with all visual states | `js/tutorial_controller.css` |

### Competition Rules

Both A and B implement the **same spec** (below) but with different code architectures:

- **A** uses a `TutorialController` class with methods and instance state
- **B** uses a module pattern with closures and standalone functions; no `class` keyword

The main agent reviews both and picks the winner based on: readability, correctness, and robustness of the session lifecycle handling.

### Execution Order

1. All 3 subagents launch simultaneously
2. After A and B finish, the main agent reviews both implementations and picks a winner
3. The main agent writes the chosen implementation to `js/tutorial_controller.js`
4. Subagent C's CSS is applied directly (no competition)
5. The main agent does a final validation pass: load the page in `test_client/` and confirm the script initialises without errors

---

## File Layout

Create a new top-level `js/` directory in the workspace root (NOT inside `lighthouse_agent/`):

```
js/
  tutorial_controller.js    ← browser WebSocket client (produced by A or B)
  tutorial_controller.css   ← visual states stylesheet (produced by C)
```

The `lighthouse_agent/proxy/tutorial_proxy.dart` serves these at `/js/tutorial_controller.js` and `/js/tutorial_controller.css` (Day 5 work — do NOT modify `tutorial_proxy.dart` today).

---

## Detailed Specification

### 1. Entry Point & Auto-Initialisation

The script must self-execute on DOM ready. It must NOT require a manual call from the page host.

```js
// Pattern A (class-based):
document.addEventListener('DOMContentLoaded', () => {
  const controller = new TutorialController();
  controller.init();
});

// Pattern B (functional):
document.addEventListener('DOMContentLoaded', init);
```

### 2. WebSocket Connection & Agent Detection

On init:

1. Determine the WS URL:
   - If the page is served over HTTPS → connect to `wss://localhost:50051`
   - If served over HTTP → connect to `ws://localhost:50051`
2. Open a WebSocket connection with a **3-second timeout**:
   - If the connection is established → proceed to session setup
   - If the connection fails or the timeout fires before `onopen` → **show install banner**, stop (do NOT inject Run buttons)

```js
const WS_PORT = 50051;
const wsUrl = location.protocol === 'https:' ? `wss://localhost:${WS_PORT}` : `ws://localhost:${WS_PORT}`;
```

**Install banner HTML (injected at the top of `<body>`):**

```html
<div id="lh-install-banner" style="/* see CSS spec */">
  <strong>Lighthouse Agent not detected.</strong>
  To run commands interactively, <a href="https://github.com/canonical/lighthouse-agent/releases">download and install Lighthouse Agent</a>.
  <button id="lh-banner-dismiss">✕</button>
</div>
```

The dismiss button removes the banner from the DOM.

### 3. Session Lifecycle (Client Side)

On successful WebSocket connection:

1. Check `sessionStorage.getItem('lh_session_id')`:
   - **Present** → send `session_resume { session_id }` first
   - **Absent** → send `session_start { origin: location.origin, tutorial_url: location.href }`

2. Handle incoming messages:

| Message type | Action |
|---|---|
| `session_ready` | Store `session_id` in `sessionStorage`; record `vm_name`; enable all Run buttons |
| `session_denied` | Clear `sessionStorage`; call `_setPermissionDenied()` on all blocks; close WS |
| `error` on `session_resume` | Clear `sessionStorage`; send `session_start` as fallback |
| `output` | Append `data` to the correct block's output section |
| `exec_done` | Mark block as success (exit 0) or failure (non-zero exit) |
| `error` with `COMMAND_BLOCKED` | Mark block as blocked |
| `error` (other) | Mark block as errored; show message |
| `agent_error` | Show an agent-level error banner; disable all Run buttons |

### 4. DOM Scan & Run Button Injection

After a successful WebSocket connection (regardless of `session_ready` — inject buttons immediately, just leave them disabled until `session_ready`):

1. Find all `<pre><code>` blocks on the page.
2. For each block:
   - Extract the text content as the command string (trimmed)
   - Skip empty blocks
   - Inject a `<div class="lh-block-wrapper">` that wraps the existing `<pre>` and appends:
     - A `<button class="lh-run-btn">▶ Run</button>` 
     - A `<div class="lh-output-section lh-hidden">` containing a `<pre class="lh-output-pre"></pre>`
     - A `<span class="lh-status-indicator"></span>`
3. The Run button starts **disabled** if `session_ready` has not yet been received.
4. On `session_ready`, enable all Run buttons.

### 5. Per-Block State Machine

Each block has these visual states, controlled by CSS classes on the `lh-block-wrapper`:

| State | CSS class | Run button | Status indicator |
|---|---|---|---|
| Idle | `lh-state-idle` | Enabled, "▶ Run" | Hidden |
| Running | `lh-state-running` | Disabled, spinner | Hidden |
| Success | `lh-state-success` | Enabled, "▶ Run" | Green ✓ |
| Failure | `lh-state-failure` | Enabled, "▶ Run" | Red ✗ |
| Blocked | `lh-state-blocked` | Enabled, "▶ Run" | Orange ⚠ + message |
| Denied | `lh-state-denied` | Replaced with "⚠ Permission denied" (non-interactive) | Hidden |

Transitions:
- `idle` → `running`: on Run button click
- `running` → `success`: on `exec_done` with `exit_code === 0`
- `running` → `failure`: on `exec_done` with `exit_code !== 0`
- `running` → `blocked`: on `error { code: "COMMAND_BLOCKED" }` for this block's command
- Any → `denied`: on `session_denied` message

### 6. Output Display (Per Block)

Each block has a collapsible output section below the `<pre>`:

- Initially hidden (`lh-hidden` class)
- Shown automatically as soon as the first `output` message arrives for this block
- Output is appended in real-time: each `output.data` string is appended to `lh-output-pre` (preserve newlines)
- A "▼ Hide output" / "▶ Show output" toggle button appears after the first output
- Stdout and stderr are displayed together in order of arrival (no separate panes for MVP)

**Block-to-command matching:** When the Run button is clicked, store the command string and the block reference keyed by `session_id + ':' + command` or a per-click UUID. Use a simple FIFO queue per session: first `exec_done` goes to the oldest in-flight block for that session.

> **Implementation note:** Since multiple blocks can be running concurrently, the safest approach is to tag each `exec` send with a per-click UUID stored on the block, and match incoming `exec_done` / `output` messages by associating them with the correct block. However, the protocol does not include a per-exec correlation ID (that is a Day 7 improvement). For MVP, assume commands are queued and responses arrive in order — use a FIFO queue per session.

### 7. Run Button Click Handler

When a Run button is clicked:

1. If no active session (`session_id` not set): do nothing (button should be disabled)
2. Set block state to `running`; clear previous output
3. Send `exec { session_id, command }` over WebSocket
4. Add the block to the FIFO queue for this session

### 8. Finish Tutorial Button

Inject a `<div id="lh-finish-bar">` at the bottom of the page content area (before `</body>`):

```html
<div id="lh-finish-bar">
  <button id="lh-finish-btn">⏹ Finish Tutorial</button>
  <span id="lh-finish-hint">This will destroy the Multipass VM and end the session.</span>
</div>
```

On click:
1. If no active session: ignore
2. Send `finish { session_id }` over WebSocket
3. Disable the button, update text to "Finishing…"
4. On WebSocket close: clear `sessionStorage`; update text to "Session ended."

Also inject a smaller "Finish Tutorial" link/button inside the console panel (see §9).

### 9. Console Panel

Inject a toggleable sidebar/overlay panel with id `lh-console-panel`:

```html
<div id="lh-console-panel" class="lh-console-hidden">
  <div id="lh-console-header">
    <span>Lighthouse Console</span>
    <span id="lh-vm-name"></span>
    <button id="lh-console-finish">⏹ Finish Tutorial</button>
    <button id="lh-console-close">✕</button>
  </div>
  <pre id="lh-console-log"></pre>
</div>
<button id="lh-console-toggle">⌨ Console</button>
```

- The toggle button is fixed to the bottom-right corner of the viewport
- The panel slides in from the right (or bottom — CSS choice)
- All `output` messages from any block are also appended to `#lh-console-log`
- `#lh-vm-name` shows the `vm_name` from `session_ready`
- `#lh-console-finish` sends `finish` (same as §8)
- `#lh-console-close` hides the panel

### 10. Permission Denied State

On receiving `session_denied`:

1. Iterate all `lh-block-wrapper` elements
2. Add `lh-state-denied` class to each
3. Replace each Run button with a `<span class="lh-denied-label">⚠ Permission denied</span>`
4. Remove the Finish Tutorial button / bar from the DOM
5. Close the WebSocket
6. Clear `sessionStorage`

### 11. WebSocket Reconnection (Minimal)

If the WebSocket closes unexpectedly (not due to `session_denied` or `finish`):

- Disable all Run buttons
- Show a non-blocking notification: "Connection to Lighthouse Agent lost. Refresh to reconnect."
- Do NOT attempt automatic reconnection (out of scope for MVP)

---

## CSS Specification (Subagent C)

File: `js/tutorial_controller.css`

Produce clean, minimal CSS (no external dependencies, no preprocessors). Scope all selectors under `[data-lh]` attribute or use the `lh-` prefix to avoid conflicts with the tutorial page styles.

### Install Banner (`#lh-install-banner`)

- Yellow/amber background (`#fef3c7`), dark text (`#78350f`)
- Full-width sticky banner at top of page (`position: sticky; top: 0; z-index: 9999`)
- Padding: `0.75rem 1.5rem`
- Dismiss button floats right; styled as a borderless icon button

### Run Button (`.lh-run-btn`)

- Small button, `font-size: 0.8rem`, green background (`#16a34a`), white text
- Rounded corners (`border-radius: 4px`), padding `0.25rem 0.6rem`
- Disabled state: greyed out (`#9ca3af`), `cursor: not-allowed`
- Hover: slightly darker green

### Status Indicators

- `.lh-state-success .lh-status-indicator`: `color: #16a34a; content: "✓ Success"`
- `.lh-state-failure .lh-status-indicator`: `color: #dc2626; content: "✗ Failed"`
- `.lh-state-blocked .lh-status-indicator`: `color: #d97706; content: "⚠ Blocked"`
- `.lh-state-running .lh-run-btn::after`: CSS spinner animation

### Output Section (`.lh-output-section`)

- Dark background (`#1e1e1e`), monospace font, `font-size: 0.8rem`
- White text, max-height `300px`, overflow-y auto
- Smooth reveal: `transition: max-height 0.2s ease`
- `.lh-hidden`: `max-height: 0; overflow: hidden`

### Console Panel (`#lh-console-panel`)

- Fixed right side of viewport: `position: fixed; right: 0; top: 0; width: 400px; height: 100vh`
- Dark theme matching output section
- Slide-in transition: `transform: translateX(100%)` ↔ `transform: translateX(0)`
- `.lh-console-hidden`: `transform: translateX(100%)`

### Console Toggle Button (`#lh-console-toggle`)

- Fixed bottom-right: `position: fixed; bottom: 1.5rem; right: 1.5rem; z-index: 1000`
- Dark button with a subtle shadow

### Finish Bar (`#lh-finish-bar`)

- Centered, margin `2rem auto`, padding `1rem`
- Red-ish finish button (`#dc2626`)

### Denied Label (`.lh-denied-label`)

- Orange text, `font-size: 0.8rem`, `cursor: not-allowed`

---

## Message Format Reference (from engineering plan)

All messages are JSON. The `type` field identifies the message.

### Client → Agent

```json
{ "type": "session_start", "origin": "https://ubuntu.com", "tutorial_url": "https://ubuntu.com/tutorials/..." }
{ "type": "session_resume", "session_id": "abc123" }
{ "type": "exec", "session_id": "abc123", "command": "echo hello" }
{ "type": "finish", "session_id": "abc123" }
```

### Agent → Client

```json
{ "type": "session_ready", "session_id": "abc123", "vm_name": "lighthouse-3f7a1b2c" }
{ "type": "session_denied" }
{ "type": "output", "session_id": "abc123", "stream": "stdout", "data": "hello\n" }
{ "type": "exec_done", "session_id": "abc123", "exit_code": 0 }
{ "type": "error", "session_id": "abc123", "code": "COMMAND_BLOCKED", "message": "..." }
{ "type": "agent_error", "code": "MULTIPASS_MISSING", "message": "..." }
```

---

## Current State (Days 1–3 Complete)

The following are **already implemented** and must NOT be reimplemented:

- Flutter app (`lighthouse_agent/`) with system tray, WSS server on port 50051
- Session Manager: `pending → authorizing → provisioning → ready → expiring → purged` state machine
- `session_start`, `session_resume`, `exec`, `finish` handling in `websocket_server.dart`
- Origin validator (allowlist: `*.ubuntu.com`, `*.canonical.com`, `localhost` in debug)
- Allow/Deny permission dialog (fires on first `exec`)
- 30-minute expiry timer on WebSocket close
- `MultipassWrapper`: `launch`, `exec` (streaming), `delete --purge`

**The `js/` directory does not yet exist.** Create it at the workspace root (sibling of `lighthouse_agent/` and `test_client/`).

---

## Files to Create

| File | Responsible |
|---|---|
| `js/tutorial_controller.js` | Subagent A or B (winner chosen by main agent) |
| `js/tutorial_controller.css` | Subagent C |

## Files NOT to Modify

- Anything under `lighthouse_agent/` — Day 5 will wire the proxy
- `test_client/test.js` — leave existing manual test client as-is
- Any `prompts/`, `README.md`, or plan files

---

## Acceptance Criteria

1. **Agent not running:** Open any page with the script injected → install banner appears; no Run buttons injected
2. **Agent running, first load:** Connect → `session_start` sent; Run buttons visible but disabled
3. **`session_ready` received:** All Run buttons become enabled; VM name shown in console panel header
4. **Run button click:** Block transitions to `running`; `exec` sent over WebSocket
5. **`output` messages:** Text appended in real-time to block output section and console log; output section auto-reveals
6. **`exec_done` exit 0:** Block shows green ✓ success; Run button re-enabled
7. **`exec_done` non-zero:** Block shows red ✗ failure; Run button re-enabled
8. **`COMMAND_BLOCKED` error:** Block shows orange ⚠ blocked; Run button re-enabled
9. **`session_denied`:** All blocks show "⚠ Permission denied"; Finish bar removed; WS closed
10. **Page refresh:** `sessionStorage` has `session_id` → `session_resume` sent first
11. **`error` on `session_resume`:** Fall back to `session_start`; clear `sessionStorage`
12. **Finish Tutorial:** Button click sends `finish`; WS closes; `sessionStorage` cleared
13. **Console toggle:** Button shows/hides the console panel
14. **Unexpected WS close:** All Run buttons disabled; "Connection lost" message shown

---

## Manual Test Sequence

Use the `test_client/` directory's existing `test.js` as a reference for the Agent-side messages. To test the JS controller manually:

1. Start the Lighthouse Agent in debug mode (`flutter run -d linux`)
2. Create a minimal HTML file at `test_client/index.html`:
```html
<!DOCTYPE html>
<html>
<head>
  <title>Test Tutorial</title>
  <link rel="stylesheet" href="/js/tutorial_controller.css">
</head>
<body>
  <h1>Test Tutorial</h1>
  <p>Step 1: List your home directory.</p>
  <pre><code>ls -la ~</code></pre>
  <p>Step 2: Check OS version.</p>
  <pre><code>cat /etc/os-release</code></pre>
  <script src="/js/tutorial_controller.js"></script>
</body>
</html>
```
3. Serve `test_client/` with any static server (e.g. `npx serve test_client -p 8080`)
4. Open `http://localhost:8080` in Chrome
5. Walk through the acceptance criteria above
