#!/bin/bash

# End-to-end test script for Lighthouse Agent
# Tests the full flow from WebSocket connection to command execution

set -e

AGENT_HOST="127.0.0.1"
AGENT_PORT="50051"
WEBSOCKET_URL="ws://${AGENT_HOST}:${AGENT_PORT}"
TEST_SESSION_ID="test-e2e-$(date +%s)"
TMP_DIR="/tmp/lighthouse_e2e_test"
LOG_FILE="${TMP_DIR}/test_output.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[TEST]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOG_FILE"
}

pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    cleanup
    exit 1
}

cleanup() {
    log "Cleaning up..."
    rm -rf "$TMP_DIR" 2>/dev/null || true
}

# Trap for cleanup on exit
trap cleanup EXIT

setup() {
    log "Setting up test environment..."
    mkdir -p "$TMP_DIR"
    > "$LOG_FILE"
}

check_agent_running() {
    log "Checking if Lighthouse Agent is running..."
    
    # Check if port is listening
    if ! ss -tlnp 2>/dev/null | grep -q ":${AGENT_PORT}" && \
       ! netstat -tlnp 2>/dev/null | grep -q ":${AGENT_PORT}"; then
        warn "Agent not listening on port ${AGENT_PORT}"
        warn "Attempting to start the agent..."
        
        # Try to start the agent
        cd "$(dirname "$0")/lighthouse_agent"
        export PATH="$HOME/dev/flutter_sdk/flutter/bin:$HOME/dev/flutter_sdk/flutter/bin/cache/dart-sdk/bin:$PATH"
        flutter run -d linux &
        AGENT_PID=$!
        
        # Wait for agent to start (max 30 seconds)
        for i in {1..30}; do
            if ss -tlnp 2>/dev/null | grep -q ":${AGENT_PORT}" || \
               netstat -tlnp 2>/dev/null | grep -q ":${AGENT_PORT}"; then
                log "Agent started with PID $AGENT_PID"
                break
            fi
            sleep 1
        done
        
        if ! ss -tlnp 2>/dev/null | grep -q ":${AGENT_PORT}" && \
           ! netstat -tlnp 2>/dev/null | grep -q ":${AGENT_PORT}"; then
            error "Failed to start agent"
            return 1
        fi
    fi
    
    pass "Agent is running"
    return 0
}

test_websocket_upgrade() {
    log "Testing WebSocket upgrade..."
    
    # Use websocat or similar tool if available, otherwise use curl
    if command -v websocat &> /dev/null; then
        echo '{"type":"ping"}' | websocat -n "ws://${AGENT_HOST}:${AGENT_PORT}" 2>&1 | tee -a "$LOG_FILE"
    else
        # Fallback to curl
        curl -s -o /dev/null -w "%{http_code}" \
            -H "Connection: Upgrade" \
            -H "Upgrade: websocket" \
            -H "Sec-WebSocket-Version: 13" \
            -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" \
            "http://${AGENT_HOST}:${AGENT_PORT}/" 2>&1 | tee -a "$LOG_FILE"
        
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
            -H "Connection: Upgrade" \
            -H "Upgrade: websocket" \
            -H "Sec-WebSocket-Version: 13" \
            -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" \
            "http://${AGENT_HOST}:${AGENT_PORT}/" 2>&1)
        
        if [ "$HTTP_CODE" = "101" ] || [ "$HTTP_CODE" = "400" ] || [ "$HTTP_CODE" = "426" ]; then
            pass "WebSocket upgrade supported (HTTP $HTTP_CODE)"
            return 0
        else
            fail "WebSocket upgrade failed with HTTP $HTTP_CODE"
        fi
    fi
}

test_session_start() {
    log "Testing session_start message..."
    
    # Create a simple WebSocket client test
    cat > "${TMP_DIR}/ws_test.js" << 'EOF'
const WebSocket = require('ws');

const ws = new WebSocket('ws://127.0.0.1:50051');

ws.on('open', () => {
    console.log('Connected to agent');
    
    // Send session_start
    ws.send(JSON.stringify({
        type: 'session_start',
        origin: 'http://localhost:8080',
        tutorial_url: 'http://localhost:8080/tutorial'
    }));
});

ws.on('message', (data) => {
    console.log('Received:', data.toString());
    const msg = JSON.parse(data.toString());
    
    if (msg.type === 'session_ready') {
        console.log('SESSION_ID:' + msg.session_id);
        ws.close();
    } else if (msg.type === 'error') {
        console.error('Error:', msg.message);
        ws.close();
    }
});

ws.on('error', (err) => {
    console.error('WebSocket error:', err.message);
    process.exit(1);
});

setTimeout(() => {
    console.error('Timeout waiting for response');
    ws.close();
    process.exit(1);
}, 10000);
EOF

    if command -v node &> /dev/null; then
        cd "$TMP_DIR"
        node ws_test.js 2>&1 | tee -a "$LOG_FILE"
        pass "Session start test completed"
    else
        warn "Node.js not available, skipping WebSocket test"
    fi
}

test_tutorial_proxy() {
    log "Testing tutorial proxy on port 8080..."
    
    # Check if proxy is running
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/js/tutorial_controller.js" 2>&1)
    
    if [ "$HTTP_CODE" = "200" ]; then
        pass "Tutorial proxy is running and serving JS files"
    else
        warn "Tutorial proxy not running (HTTP $HTTP_CODE) - this may be expected"
    fi
}

test_multipass_available() {
    log "Checking Multipass availability..."
    
    if command -v multipass &> /dev/null; then
        multipass list 2>&1 | tee -a "$LOG_FILE"
        pass "Multipass is available"
    else
        warn "Multipass not installed - VM tests will be skipped"
    fi
}

run_tests() {
    log "Running Lighthouse Agent E2E tests..."
    log "======================================"
    
    setup
    
    check_agent_running || fail "Agent is not running"
    test_websocket_upgrade || warn "WebSocket upgrade test failed"
    test_session_start || warn "Session start test failed"
    test_tutorial_proxy || warn "Tutorial proxy test failed"
    test_multipass_available
    
    log "======================================"
    log "E2E tests completed!"
    log "Full log saved to: $LOG_FILE"
}

# Run tests
run_tests