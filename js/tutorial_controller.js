/**
 * Tutorial Controller - WebSocket client for Lighthouse Agent
 */
class TutorialController {
  constructor() {
    this.ws = null;
    this.sessionId = null;
    this.vmName = null;
    this.commandQueue = []; // FIFO queue for tracking command execution
    this.timeoutId = null;
    this.connectionEstablished = false;
    this.isResuming = false; // Track if we're attempting to resume a session
  }

  init() {
    // Wait for DOM to be ready
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', () => this._initialize());
    } else {
      this._initialize();
    }
  }

  _initialize() {
    // Determine WebSocket URL based on page protocol
    const WS_PORT = 50051;
    const wsUrl = location.protocol === 'https:' 
      ? `wss://localhost:${WS_PORT}` 
      : `ws://localhost:${WS_PORT}`;

    // Create WebSocket connection with timeout
    this.ws = new WebSocket(wsUrl);

    // Set up timeout for connection establishment
    this.timeoutId = setTimeout(() => {
      if (!this.connectionEstablished) {
        this.ws.close();
        this._showInstallBanner();
      }
    }, 3000); // 3 second timeout

    this.ws.onopen = () => {
      this.connectionEstablished = true;
      clearTimeout(this.timeoutId);
      
      // Check for existing session in sessionStorage
      this.sessionId = sessionStorage.getItem('lh_session_id');
      
      if (this.sessionId) {
        // Try to resume existing session
        this.isResuming = true;
        this._sendMessage({
          type: 'session_resume',
          session_id: this.sessionId
        });
      } else {
        // Start a new session
        this._sendMessage({
          type: 'session_start',
          origin: location.origin,
          tutorial_url: location.href
        });
      }
    };

    this.ws.onmessage = (event) => {
      const message = JSON.parse(event.data);
      this._handleMessage(message);
    };

    this.ws.onerror = (error) => {
      console.error('WebSocket error:', error);
    };

    this.ws.onclose = () => {
      if (this.connectionEstablished) {
        // Unexpected closure - show notification
        this._showNotification('Connection to Lighthouse Agent lost. Refresh to reconnect.', 'warning');
        this._disableAllRunButtons();
        
        // Update finish button text if it exists
        const finishBtn = document.getElementById('lh-finish-btn');
        if (finishBtn) {
          finishBtn.textContent = 'Session ended.';
        }
      }
    };
  }

  _sendMessage(message) {
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(message));
    }
  }

  _handleMessage(message) {
    switch (message.type) {
      case 'session_ready':
        this.sessionId = message.session_id;
        this.vmName = message.vm_name;
        this.isResuming = false; // Reset resuming flag on success
        sessionStorage.setItem('lh_session_id', this.sessionId);
        
        // Enable all run buttons
        this._enableAllRunButtons();
        
        // Update console panel with VM name (if panel already exists)
        const vmNameEl = document.getElementById('lh-vm-name');
        if (vmNameEl) {
          vmNameEl.textContent = this.vmName;
        }
        break;

      case 'session_denied':
        this._setPermissionDenied();
        this.ws.close();
        break;

      case 'error':
        // Check if this is an error during session_resume (resume failed)
        if (this.isResuming && message.session_id && message.code) {
          // Resume failed - clear session and start fresh
          sessionStorage.removeItem('lh_session_id');
          this.sessionId = null;
          this.isResuming = false;
          
          // Fall back to session_start
          this._sendMessage({
            type: 'session_start',
            origin: location.origin,
            tutorial_url: location.href
          });
        } else if (message.session_id && message.code === 'COMMAND_BLOCKED') {
          // Find the block associated with this session and mark as blocked
          const block = this._getBlockBySessionId(message.session_id);
          if (block) {
            this._setBlockState(block, 'blocked');
          }
        } else if (message.session_id && message.code) {
          // Find the block associated with this session and mark as error
          const block = this._getBlockBySessionId(message.session_id);
          if (block) {
            this._setBlockState(block, 'failure');
          }
        } else if (!message.session_id && message.code) {
          // Agent-level error
          this._showAgentError(message.message);
        }
        break;

      case 'output':
        // Find the block associated with this session and append output
        const block = this._getBlockBySessionId(message.session_id);
        if (block) {
          this._appendToOutput(block, message.data);
        }
        
        // Also append to console log
        this._appendToConsoleOutput(message.data);
        break;

      case 'exec_done':
        // Complete the oldest command in the queue
        if (this.commandQueue.length > 0) {
          const block = this.commandQueue.shift();
          this._setBlockState(block, message.exit_code === 0 ? 'success' : 'failure');
        }
        break;

      case 'agent_error':
        this._showAgentError(message.message);
        break;
    }
  }

  _getBlockBySessionId(sessionId) {
    // Find the block that is currently running a command for this session
    // We'll use the queue to track which blocks are running
    if (this.commandQueue.length > 0) {
      return this.commandQueue[0]; // Return the oldest running command
    }
    return null;
  }

  _showInstallBanner() {
    // Remove any existing banner
    const existingBanner = document.getElementById('lh-install-banner');
    if (existingBanner) {
      existingBanner.remove();
    }

    // Create and inject the install banner
    const banner = document.createElement('div');
    banner.id = 'lh-install-banner';
    banner.innerHTML = `
      <strong>Lighthouse Agent not detected.</strong>
      To run commands interactively, <a href="https://github.com/canonical/lighthouse-agent/releases">download and install Lighthouse Agent</a>.
      <button id="lh-banner-dismiss">✕</button>
    `;

    document.body.insertBefore(banner, document.body.firstChild);

    // Add event listener to dismiss button
    document.getElementById('lh-banner-dismiss').addEventListener('click', () => {
      banner.remove();
    });
  }

  _injectRunButtons() {
    // Find all <pre><code> blocks on the page
    const codeBlocks = document.querySelectorAll('pre code');
    
    codeBlocks.forEach((codeBlock, index) => {
      // Skip if already processed
      if (codeBlock.closest('.lh-block-wrapper')) {
        return;
      }

      // Parse command lines from this block.
      const rawLines = codeBlock.textContent
        .split('\n')
        .map(line => line.trim())
        .filter(line => line.length > 0);
      if (rawLines.length === 0) {
        return; // Skip empty blocks
      }

      // Create wrapper div
      const wrapper = document.createElement('div');
      wrapper.className = 'lh-block-wrapper lh-state-idle';
      wrapper.dataset.commandIndex = index;

      // Wrap the existing pre element
      const preElement = codeBlock.parentElement;
      preElement.parentNode.insertBefore(wrapper, preElement);
      wrapper.appendChild(preElement);

      // Create run controls (one button per command line for multi-line blocks).
      const runControls = document.createElement('div');
      runControls.className = 'lh-run-controls';

      if (rawLines.length === 1) {
        const runButton = document.createElement('button');
        runButton.className = 'lh-run-btn';
        runButton.textContent = '▶ Run';
        runButton.disabled = !this.sessionId;
        runButton.title = rawLines[0];
        runButton.addEventListener('click', () => {
          this._handleRunButtonClick(wrapper, rawLines[0]);
        });
        runControls.appendChild(runButton);
      } else {
        rawLines.forEach((line, lineIndex) => {
          const runButton = document.createElement('button');
          runButton.className = 'lh-run-btn lh-run-btn-small';
          runButton.textContent = `▶ L${lineIndex + 1}`;
          runButton.disabled = !this.sessionId;
          runButton.title = line;
          runButton.addEventListener('click', () => {
            this._handleRunButtonClick(wrapper, line);
          });
          runControls.appendChild(runButton);
        });
      }

      // Create output section (initially hidden)
      const outputSection = document.createElement('div');
      outputSection.className = 'lh-output-section lh-hidden';
      outputSection.innerHTML = '<div class="lh-output-command"></div><pre class="lh-output-pre"></pre>';

      // Create status indicator
      const statusIndicator = document.createElement('span');
      statusIndicator.className = 'lh-status-indicator';

      // Append elements to wrapper
      wrapper.appendChild(runControls);
      wrapper.appendChild(outputSection);
      wrapper.appendChild(statusIndicator);
    });
  }

  _handleRunButtonClick(block, command) {
    if (!this.sessionId) {
      return; // No active session
    }

    // Set block state to running
    this._setBlockState(block, 'running');
    
    const outputCommand = block.querySelector('.lh-output-command');
    if (outputCommand) {
      if (outputCommand.textContent && outputCommand.textContent.trim().length > 0) {
        outputCommand.textContent += `\n$ ${command}`;
      } else {
        outputCommand.textContent = `$ ${command}`;
      }
    }

    const outputSection = block.querySelector('.lh-output-section');
    if (outputSection) {
      outputSection.classList.remove('lh-hidden');
    }

    this._appendToConsoleCommand(command);

    // Send exec command
    this._sendMessage({
      type: 'exec',
      session_id: this.sessionId,
      command: command
    });

    // Add block to command queue
    this.commandQueue.push(block);
  }

  _setBlockState(block, state) {
    // Remove all state classes
    block.classList.remove(
      'lh-state-idle',
      'lh-state-running',
      'lh-state-success',
      'lh-state-failure',
      'lh-state-blocked',
      'lh-state-denied'
    );

    // Add the new state class
    block.classList.add(`lh-state-${state}`);

    // Update button based on state
    const runButtons = block.querySelectorAll('.lh-run-btn');
    const statusIndicator = block.querySelector('.lh-status-indicator');

    if (state === 'running') {
      runButtons.forEach(button => {
        button.disabled = true;
      });
      if (statusIndicator) {
        statusIndicator.textContent = '';
      }
    } else if (state === 'success') {
      runButtons.forEach(button => {
        button.disabled = false;
      });
      if (statusIndicator) {
        statusIndicator.textContent = '✓ Success';
      }
    } else if (state === 'failure') {
      runButtons.forEach(button => {
        button.disabled = false;
      });
      if (statusIndicator) {
        statusIndicator.textContent = '✗ Failed';
      }
    } else if (state === 'blocked') {
      runButtons.forEach(button => {
        button.disabled = false;
      });
      if (statusIndicator) {
        statusIndicator.textContent = '⚠ Blocked';
      }
    } else if (state === 'denied') {
      if (runButtons.length > 0) {
        runButtons.forEach(button => {
          button.remove();
        });
        const controls = block.querySelector('.lh-run-controls');
        if (controls) {
          controls.remove();
        }
        if (!block.querySelector('.lh-denied-label')) {
          // Replace buttons with denied label
          const deniedLabel = document.createElement('span');
          deniedLabel.className = 'lh-denied-label';
          deniedLabel.textContent = '⚠ Permission denied';
          block.appendChild(deniedLabel);
        }
      }
    } else if (state === 'idle') {
      runButtons.forEach(button => {
        button.disabled = !this.sessionId;
      });
      if (statusIndicator) {
        statusIndicator.textContent = '';
      }
    }
  }

  _appendToOutput(block, data) {
    const outputPre = block.querySelector('.lh-output-pre');
    if (outputPre) {
      outputPre.textContent += data;
      
      // Make output section visible
      const outputSection = block.querySelector('.lh-output-section');
      if (outputSection) {
        outputSection.classList.remove('lh-hidden');
        
        // Add toggle button after first output (if not already added)
        if (!outputSection.querySelector('.lh-output-toggle')) {
          const toggleBtn = document.createElement('button');
          toggleBtn.className = 'lh-output-toggle';
          toggleBtn.textContent = '▼ Hide output';
          toggleBtn.addEventListener('click', () => {
            if (outputPre.style.display === 'none') {
              outputPre.style.display = 'block';
              toggleBtn.textContent = '▼ Hide output';
            } else {
              outputPre.style.display = 'none';
              toggleBtn.textContent = '▶ Show output';
            }
          });
          outputSection.appendChild(toggleBtn);
        }
      }
    }
  }

  _appendToConsoleCommand(command) {
    const consoleLog = document.getElementById('lh-console-log');
    if (!consoleLog) {
      return;
    }

    const commandLine = document.createElement('span');
    commandLine.className = 'lh-console-command';
    commandLine.textContent = `$ ${command}\n`;
    consoleLog.appendChild(commandLine);
    consoleLog.scrollTop = consoleLog.scrollHeight;
  }

  _appendToConsoleOutput(data) {
    const consoleLog = document.getElementById('lh-console-log');
    if (!consoleLog) {
      return;
    }

    const outputLine = document.createElement('span');
    outputLine.className = 'lh-console-output';
    outputLine.textContent = data;
    consoleLog.appendChild(outputLine);
    consoleLog.scrollTop = consoleLog.scrollHeight;
  }

  _enableAllRunButtons() {
    const runButtons = document.querySelectorAll('.lh-run-btn');
    runButtons.forEach(button => {
      button.disabled = false;
    });
  }

  _disableAllRunButtons() {
    const runButtons = document.querySelectorAll('.lh-run-btn');
    runButtons.forEach(button => {
      button.disabled = true;
    });
  }

  _setPermissionDenied() {
    // Clear session storage
    sessionStorage.removeItem('lh_session_id');
    this.sessionId = null;

    // Update all blocks to denied state
    const blocks = document.querySelectorAll('.lh-block-wrapper');
    blocks.forEach(block => {
      this._setBlockState(block, 'denied');
    });

    // Remove finish bar if present
    const finishBar = document.getElementById('lh-finish-bar');
    if (finishBar) {
      finishBar.remove();
    }
  }

  _showAgentError(message) {
    // Show an agent-level error banner
    this._showNotification(`Agent Error: ${message}`, 'error');
    this._disableAllRunButtons();
  }

  _showNotification(message, type) {
    // Create a notification element
    const notification = document.createElement('div');
    notification.className = `lh-notification lh-notification-${type}`;
    notification.textContent = message;

    // Add to body
    document.body.appendChild(notification);

    // Remove after 5 seconds
    setTimeout(() => {
      notification.remove();
    }, 5000);
  }

  _injectFinishButton() {
    // Check if finish bar already exists
    if (document.getElementById('lh-finish-bar')) {
      return;
    }

    // Create finish bar
    const finishBar = document.createElement('div');
    finishBar.id = 'lh-finish-bar';
    finishBar.innerHTML = `
      <button id="lh-finish-btn">⏹ Finish Tutorial</button>
      <span id="lh-finish-hint">This will destroy the Multipass VM and end the session.</span>
    `;

    // Add to end of body
    document.body.appendChild(finishBar);

    // Add event listener
    document.getElementById('lh-finish-btn').addEventListener('click', () => {
      if (!this.sessionId) {
        return; // No active session
      }

      // Send finish command
      this._sendMessage({
        type: 'finish',
        session_id: this.sessionId
      });

      // Update button text
      const finishBtn = document.getElementById('lh-finish-btn');
      if (finishBtn) {
        finishBtn.textContent = 'Finishing…';
        finishBtn.disabled = true;
      }
    });
  }

  _injectConsolePanel() {
    // Check if console panel already exists
    if (document.getElementById('lh-console-panel')) {
      return;
    }

    // Create console panel
    const consolePanel = document.createElement('div');
    consolePanel.id = 'lh-console-panel';
    consolePanel.className = 'lh-console-hidden';
    consolePanel.innerHTML = `
      <div id="lh-console-header">
        <span>Lighthouse Console</span>
        <span id="lh-vm-name">${this.vmName || ''}</span>
        <button id="lh-console-finish">⏹ Finish Tutorial</button>
        <button id="lh-console-close">✕</button>
      </div>
      <pre id="lh-console-log"></pre>
    `;

    // Add to body
    document.body.appendChild(consolePanel);

    // Create console toggle button
    const consoleToggle = document.createElement('button');
    consoleToggle.id = 'lh-console-toggle';
    consoleToggle.textContent = '⌨ Console';
    document.body.appendChild(consoleToggle);

    // Add event listeners
    document.getElementById('lh-console-close').addEventListener('click', () => {
      consolePanel.classList.add('lh-console-hidden');
    });

    document.getElementById('lh-console-finish').addEventListener('click', () => {
      if (!this.sessionId) {
        return; // No active session
      }

      // Send finish command
      this._sendMessage({
        type: 'finish',
        session_id: this.sessionId
      });

      // Update button text
      const finishBtn = document.getElementById('lh-console-finish');
      if (finishBtn) {
        finishBtn.textContent = 'Finishing…';
        finishBtn.disabled = true;
      }
    });

    consoleToggle.addEventListener('click', () => {
      consolePanel.classList.toggle('lh-console-hidden');
    });
  }
}

// Initialize the controller when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
  const controller = new TutorialController();
  controller.init();
  
  // After WebSocket connection is established and session is ready,
  // inject the UI elements
  // We'll add a slight delay to ensure the WebSocket is connected
  setTimeout(() => {
    if (controller.connectionEstablished) {
      controller._injectRunButtons();
      controller._injectFinishButton();
      controller._injectConsolePanel();
    }
  }, 100);
});