# Day 5 — Local Test Proxy + End-to-End Integration

## Goal

Implement the local HTTP proxy (`tutorial_proxy.dart`) that serves tutorial pages on port 8080, injects the JS controller, and wires everything together for a full end-to-end demo. By the end of Day 5:

- The Agent starts an HTTP proxy on port 8080 that fetches real Canonical tutorial pages
- The proxy injects `<script src="/js/tutorial_controller.js">` into fetched HTML pages
- The `tutorial_controller.js` and `tutorial_controller.css` are self-served by the proxy at `/js/...`
- The Agent runs in debug `ws://` mode (not `wss://`) so the browser doesn't get mixed-content errors
- Visiting `http://localhost:8080/tutorials/<slug>` renders a tutorial with working Run buttons
- Live command output streams from the Agent back to the browser

---

## File to Implement

**`lighthouse_agent/lib/proxy/tutorial_proxy.dart`** — replace the stub with a full implementation.

The proxy is a Shelf-based HTTP server that:
1. Listens on port 8080
2. Routes static assets (`/js/*`) directly from the workspace's `js/` directory
3. Routes everything else (`/*`) to a proxy handler that:
   - Fetches the corresponding page from `https://ubuntu.com`
   - Injects a `<script src="/js/tutorial_controller.js">` tag before `</body>`
   - Serves the modified HTML to the browser

---

## Execution Strategy: Single Agent

This is a smaller day with only one non-trivial file. A single subagent handles the proxy implementation. The main agent does a final verification pass.

---

## Detailed Specification

### 1. `tutorial_proxy.dart` — Shelf HTTP Proxy

```dart
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_proxy/shelf_proxy.dart';

class TutorialProxy {
  final int port;
  late HttpServer _server;

  TutorialProxy({this.port = 8080});

  Future<void> start() async {
    final handler = _buildHandler();
    _server = await shelf_io.serve(handler, 'localhost', port);
    print('Tutorial proxy running at http://localhost:$port');
  }

  Future<void> stop() async {
    await _server.close();
  }

  Handler _buildHandler() {
    // TODO: Implement pipeline
  }
}
```

### 2. Static File Serving (`/js/*`)

Requests to `/js/tutorial_controller.js` and `/js/tutorial_controller.css` must be served from the **workspace root's** `js/` directory (NOT from `lighthouse_agent/lib/`).

Use `shelf_static` or a custom file handler:

```dart
final jsHandler = createFileHandler(
  path.join(_workspaceRoot, 'js'),
  // Serve files at /js/... from $workspaceRoot/js/...
);
```

The workspace root is `../` relative to the `lighthouse_agent/` directory (since the proxy runs from inside `lighthouse_agent/`). Compute it using:

```dart
final workspaceRoot = path.dirname(Platform.resolvedExecutable);
// For development, use the parent of lighthouse_agent/
// In dev mode (flutter run), the executable is in build/linux/x64/debug/bundle/
// So workspaceRoot needs to go up several directories.
// Better: use a known path: the parent of lighthouse_agent's parent.
// Or pass the workspace root as an environment variable or constructor argument.

final wsRoot = path.normalize(path.join(Platform.script.toFilePath(), '..', '..'));
// Platform.script resolves to lighthouse_agent/lib/proxy/tutorial_proxy.dart
// So '../..' gives us the workspace root.
```

### 3. Tutorial Page Proxy (`/*`)

For all non-static requests:
1. Extract the path (e.g., `/tutorials/intro-to-docker`)
2. Fetch `https://ubuntu.com{path}` (preserve query params)
3. Parse the HTML response
4. Inject `<script src="/js/tutorial_controller.js"></script>` just before `</body>`
5. Also inject `<link rel="stylesheet" href="/js/tutorial_controller.css">` in `<head>` if not already present
6. Return the modified HTML with `Content-Type: text/html`

```dart
Future<Response> _proxyTutorial(Request request) async {
  final url = 'https://ubuntu.com${request.url.path}';
  // Forward headers (host, user-agent, etc.)
  // Use http or http_proxy package to fetch

  final response = await _httpClient.get(
    Uri.parse(url),
    headers: {
      'User-Agent': request.headers['user-agent'] ?? 'Lighthouse Proxy',
    },
  );

  // Inject script and CSS
  final modifiedHtml = _injectAssets(response.body);
  return Response.ok(modifiedHtml, headers: {'Content-Type': 'text/html'});
}

String _injectAssets(String html) {
  // Inject CSS in <head> if not already there
  if (!html.contains('tutorial_controller.css')) {
    html = html.replaceFirst(
      '</head>',
      '<link rel="stylesheet" href="/js/tutorial_controller.css">\n</head>',
    );
  }
  // Inject JS before </body>
  html = html.replaceFirst(
    '</body>',
    '<script src="/js/tutorial_controller.js"></script>\n</body>',
  );
  return html;
}
```

### 4. Workspace Root Resolution

The proxy needs to find the workspace `js/` directory. Since `tutorial_proxy.dart` lives in `lighthouse_agent/lib/proxy/`, the workspace root is two directories up:

```dart
import 'package:path/path.dart' as path;

final workspaceRoot = path.normalize(
  path.join(path.dirname(Platform.script.toFilePath()), '..', '..'),
);
// Resolves to: /path/to/lighthouse_agent/../../../ = /path/to/
// Verify: ls $workspaceRoot/js/tutorial_controller.js should exist
```

### 5. Error Handling

- If fetching from `ubuntu.com` fails (network error, 404): return a friendly error page with the error message
- If the `js/` directory doesn't exist: log a warning, serve a 404 for static assets
- Invalid URLs: return 404

### 6. Main Wiring (`lib/main.dart`)

Update the startup sequence to also start the proxy:

```dart
// After WebSocket server starts:
// Start tutorial proxy on port 8080
final proxy = TutorialProxy(port: 8080);
await proxy.start();
```

The proxy should start **after** the WebSocket server. Pass the `debug` flag to `WebSocketServer` so it uses `ws://` instead of `wss://`.

---

## Static Asset Handler Detail

The static handler must correctly map `/js/tutorial_controller.js` → `$workspaceRoot/js/tutorial_controller.js`.

Example using a custom middleware:

```dart
Handler _buildHandler() {
  final staticHandler = (Request request) async {
    // request.url.path starts with 'js/'
    // Strip the leading '/js/' to get filename
    final filePath = request.url.path.replaceFirst('js/', '');
    final fullPath = path.join(workspaceRoot, 'js', filePath);
    
    final file = File(fullPath);
    if (await file.exists()) {
      final bytes = await file.readAsBytes();
      final contentType = filePath.endsWith('.js')
          ? 'application/javascript'
          : 'text/css';
      return Response.ok(bytes, headers: {'Content-Type': contentType});
    }
    return Response.notFound('Not found');
  };

  // Wrap in Cascade to try static first, then proxy
  // ...
}
```

---

## Startup Sequence (Updated)

```
1. Ensure Flutter window is hidden
2. Initialize tray icon
3. Check first launch → autostart registration
4. Check mkcert / certificates (skip in debug mode)
5. Check Multipass availability
6. Start WebSocketServer (debug=True → ws:// on port 50051)
7. Start TutorialProxy (port 8080)
```

---

## Testing

After implementing, verify:

1. **Static assets:** `curl http://localhost:8080/js/tutorial_controller.js` returns the JS file
2. **CSS:** `curl http://localhost:8080/js/tutorial_controller.css` returns the CSS file
3. **Proxy fetch:** `curl http://localhost:8080/` fetches ubuntu.com homepage (or a friendly redirect page)
4. **E2E:** Open `http://localhost:8080/tutorials/intro-to-docker` (or similar) in the test browser — Run buttons appear, clicking one triggers the permission dialog, command runs, output streams back

---

## Acceptance Criteria

1. `curl http://localhost:8080/js/tutorial_controller.js` returns 200 with JS content
2. `curl http://localhost:8080/js/tutorial_controller.css` returns 200 with CSS content
3. `curl http://localhost:8080/` returns HTML (tutorial page from ubuntu.com) with script and stylesheet injected
4. The `js/` directory is found relative to workspace root (not relative to the built binary)
5. The proxy starts after the WebSocket server without errors
6. In debug mode, the WebSocket server binds to `ws://` (not `wss://`)

---

## Cleanup

After the proxy is confirmed working, clean up any placeholder/stub comments in `tutorial_proxy.dart`.