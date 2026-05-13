#!/usr/bin/env node
/**
 * Lighthouse Agent — Local Test Client
 *
 * Connects to the Lighthouse Agent WebSocket server and runs through
 * the basic connection test and (optionally) the Multipass integration test.
 *
 * Usage:
 *   node test.js              — basic connection test
 *   node test.js --multipass  — also run the __test_multipass__ integration test
 */

const WebSocket = require('ws');

const WS_URL = process.env.WS_URL || 'ws://127.0.0.1:50051';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function log(label, data) {
  const ts = new Date().toISOString().slice(11, 23);
  const payload = typeof data === 'string' ? data : JSON.stringify(data, null, 2);
  console.log(`\x1b[90m[${ts}]\x1b[0m \x1b[1m${label}\x1b[0m  ${payload}`);
}

function connect() {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(WS_URL);
    ws.on('open', () => resolve(ws));
    ws.on('error', (err) => reject(err));
  });
}

function sendAndWait(ws, message, timeoutMs = 5000) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('Timeout waiting for response')), timeoutMs);
    ws.once('message', (raw) => {
      clearTimeout(timer);
      resolve(JSON.parse(raw.toString()));
    });
    ws.send(JSON.stringify(message));
  });
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

async function testBasicConnection() {
  log('TEST', 'Basic WebSocket connection');
  const ws = await connect();
  log('OK', 'Connected to ' + WS_URL);

  const response = await sendAndWait(ws, {
    type: 'session_start',
    origin: 'http://localhost:8080',
    tutorial_url: 'http://localhost:8080/test',
  });

  log('RECV', response);

  if (response.type === 'agent_error' && response.code === 'NOT_IMPLEMENTED') {
    log('PASS', 'Received expected NOT_IMPLEMENTED response');
  } else if (response.type === 'session_ready') {
    log('PASS', 'Received session_ready (agent has full session management)');
    log('INFO', 'Session ID: ' + response.session_id);
    log('INFO', 'VM Name: ' + response.vm_name);
  } else if (response.type === 'session_denied') {
    log('WARN', 'Session denied — origin may not be allowed');
  } else {
    log('WARN', 'Unexpected response type: ' + response.type);
  }

  ws.close();
  log('OK', 'Connection closed');
}

async function testMultipassIntegration() {
  log('TEST', 'Multipass integration (__test_multipass__)');
  const ws = await connect();
  log('OK', 'Connected to ' + WS_URL);

  // Step 1: Start a session first
  log('SEND', { type: 'session_start', origin: 'http://localhost:8080', tutorial_url: 'http://localhost:8080/test' });
  const sessionReady = await sendAndWait(ws, {
    type: 'session_start',
    origin: 'http://localhost:8080',
    tutorial_url: 'http://localhost:8080/test',
  });

  if (sessionReady.type !== 'session_ready') {
    log('FAIL', 'Expected session_ready, got: ' + sessionReady.type);
    ws.close();
    return;
  }

  const sessionId = sessionReady.session_id;
  log('OK', 'Session ready: ' + sessionId + ' (VM: ' + sessionReady.vm_name + ')');

  // Step 2: Send the test multipass command and wait for responses
  const messages = [];
  const done = new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('Timeout waiting for exec_done (120s)')), 120000);

    ws.on('message', (raw) => {
      const msg = JSON.parse(raw.toString());
      messages.push(msg);
      log('RECV', msg);

      if (msg.type === 'exec_done' || msg.type === 'error' || msg.type === 'agent_error' || msg.type === 'lighthouse_error') {
        clearTimeout(timer);
        resolve();
      }
    });
  });

  log('SEND', { type: 'exec', session_id: sessionId, command: '__test_multipass__' });
  ws.send(JSON.stringify({
    type: 'exec',
    session_id: sessionId,
    command: '__test_multipass__',
  }));

  // Wait for all messages — do NOT close the connection until we get exec_done
  log('WAIT', 'Waiting for multipass execution to complete (may take 60-90s)...');
  await done;

  // Now close the connection
  ws.close();

  // Validate the sequence
  const types = messages.map((m) => m.type);
  log('SEQUENCE', types.join(' → '));

  const hasOutput = types.includes('output');
  const hasExecDone = types.includes('exec_done');

  if (hasOutput && hasExecDone) {
    const execDone = messages.find((m) => m.type === 'exec_done');
    if (execDone.exit_code === 0) {
      log('PASS', 'Multipass integration test passed (exit code 0)');
    } else {
      log('WARN', 'Multipass exec returned non-zero exit code: ' + execDone.exit_code);
    }
  } else if (types.includes('agent_error') || types.includes('error') || types.includes('lighthouse_error')) {
    const err = messages.find((m) => m.type === 'agent_error' || m.type === 'error' || m.type === 'lighthouse_error');
    log('FAIL', 'Multipass test failed: ' + (err.message || JSON.stringify(err)));
  } else {
    log('FAIL', 'Missing expected output/exec_done messages. Got: ' + types.join(', '));
  }

  log('OK', 'Connection closed');
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main() {
  const runMultipass = process.argv.includes('--multipass');

  console.log('\n\x1b[1m╔══════════════════════════════════════════════════════════╗\x1b[0m');
  console.log('\x1b[1m║        Lighthouse Agent — Local Test Client              ║\x1b[0m');
  console.log('\x1b[1m╚══════════════════════════════════════════════════════════╝\x1b[0m\n');
  log('INFO', 'Connecting to ' + WS_URL);

  try {
    await testBasicConnection();

    if (runMultipass) {
      console.log();
      await testMultipassIntegration();
    }

    console.log('\n\x1b[32mAll tests completed.\x1b[0m\n');
  } catch (err) {
    console.log('\n\x1b[31mTest failed:\x1b[0m ' + err.message);
    if (err.code === 'ECONNREFUSED') {
      console.log('\n\x1b[33mHint:\x1b[0m Make sure the Lighthouse Agent is running:');
      console.log('  cd lighthouse_agent && flutter run\n');
    }
    process.exit(1);
  }
}

main();
