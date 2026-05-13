# Day 6 — Integration, Hardening & Polish

## Goal

With all components implemented (Flutter agent, WebSocket server, Multipass wrapper, JS controller), Day 6 focuses on integration testing, bug fixes, and polishing the user experience end-to-end. By end of Day 6:

- All components work together seamlessly
- Error cases are handled gracefully with clear feedback
- The system is production-ready with proper logging and diagnostics

---

## Tasks

### 1. WebSocket Server — Connection Resilience

The WebSocket server should handle edge cases gracefully:

- **Reconnection logic**: If a client disconnects, clean up the session properly. If Multipass VM is running and client reconnects within 60 seconds, offer to resume the session instead of starting fresh.
- **Heartbeat mechanism**: Send periodic pings to keep connections alive. If a client misses 3 pings, close the connection and clean up.
- **Session timeout**: If a session is idle for more than 5 minutes without client activity, automatically close the WebSocket connection but keep the Multipass VM running in background (in case client reconnects).

### 2. Permission Dialog — UX Improvements

Review `lib/ui/permission_dialog.dart`:

- Add a clear "How to approve" section explaining where to find the authorization file
- Show the session ID being authorized so users can verify they're approving the right session
- Add a "Copy session ID" button for easy clipboard access
- If the file doesn't exist yet, show a "Waiting for request..." state with a spinner

### 3. Status Window — Real-time Updates

Review `lib/ui/status_window.dart`:

- Display actual Multipass VM status (Starting, Running, Stopped, Deleting)
- Show memory and disk usage if available from `multipass info`
- Add a "Open Tutorial" button that launches the browser to the tutorial URL
- Show connection count (how many WebSocket clients are connected)
- Add system tray icon state (green = running, yellow = starting, red = error)

### 4. Session Manager — Error Handling

Review `lib/agent/session_manager.dart`:

- When launching Multipass fails, provide actionable error messages (e.g., "Multipass daemon not running. Run: sudo systemctl start multipass")
- Handle cases where `multipass list` returns no VMs
- Properly clean up if the VM delete fails mid-operation
- Add retry logic (3 attempts with exponential backoff) when starting the VM

### 5. Tutorial Proxy — Content Filtering

Review `lib/proxy/tutorial_proxy.dart`:

- Add caching for fetched tutorial pages (cache for 5 minutes)
- Handle malformed HTML gracefully
- Strip or neutralize potentially dangerous content (scripts, iframes from external sources)
- Log when content is filtered so admins can audit

### 6. End-to-End Test

Create a test script that verifies the full flow:

```
1. Start the Flutter agent (or detect it's running)
2. Open http://localhost:50051 in a browser
3. Verify the agent responds with WebSocket upgrade support
4. Simulate a tutorial page load with embedded JS
5. Verify "Run" buttons appear
6. Click "Run" and verify command execution works
7. Verify output streams back to the browser
8. Verify session persists across page reload
```

### 7. Logging & Diagnostics

Add structured logging throughout:

- All WebSocket events (connect, disconnect, message received, message sent)
- All Multipass commands executed (with sanitized arguments)
- All errors with stack traces
- Log levels: DEBUG, INFO, WARNING, ERROR

Logs should go to:
- `~/.cache/lighthouse_agent/logs/` on Linux
- Rotate logs daily, keep 7 days of history

---

## Verification

Run these commands to verify progress:

```bash
# Start the agent
cd lighthouse_agent && flutter run -d linux &

# Check logs
tail -f ~/.cache/lighthouse_agent/logs/*.log

# Run all tests
flutter test

# Verify WebSocket endpoint
curl -H "Connection: Upgrade" -H "Upgrade: websocket" \
     -H "Sec-WebSocket-Version: 13" \
     -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" \
     http://127.0.0.1:50051/
```

---

## Success Criteria

- [ ] WebSocket connections are resilient to network glitches
- [ ] Permission dialog clearly guides users through authorization
- [ ] Status window shows real-time system state
- [ ] Error messages are actionable, not cryptic
- [ ] Tutorial proxy handles malformed content gracefully
- [ ] End-to-end flow works without manual intervention
- [ ] Logs provide sufficient detail for debugging production issues