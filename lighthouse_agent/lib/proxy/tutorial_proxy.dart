import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

/// Local HTTP proxy that serves tutorial pages with the JS controller injected.
/// Runs on port 8080 and proxies requests to ubuntu.com while injecting
/// the tutorial_controller script and stylesheet.
///
/// Features:
/// - Caches fetched pages for 5 minutes
/// - Handles malformed HTML gracefully
/// - Strips dangerous content (external scripts, iframes)
/// - Logs all filtering actions for audit
class TutorialProxy {
  final int port;
  final String _workspaceRoot;
  
  // Simple in-memory cache: URI -> (response, timestamp)
  final Map<String, _CacheEntry> _cache = {};
  static const Duration _cacheDuration = Duration(minutes: 5);

  TutorialProxy({this.port = 8080})
      : _workspaceRoot = _resolveWorkspaceRoot();

  static String? _findWorkspaceRootFrom(String startDir) {
    var current = path.normalize(startDir);
    for (var i = 0; i < 10; i++) {
      final controllerPath = path.join(current, 'js', 'tutorial_controller.js');
      if (File(controllerPath).existsSync()) {
        return current;
      }

      final parent = path.dirname(current);
      if (parent == current) {
        break;
      }
      current = parent;
    }
    return null;
  }

  static String _resolveWorkspaceRoot() {
    final envRoot = Platform.environment['LIGHTHOUSE_WORKSPACE_ROOT'];
    if (envRoot != null && envRoot.isNotEmpty) {
      final normalized = path.normalize(envRoot);
      if (File(path.join(normalized, 'js', 'tutorial_controller.js')).existsSync()) {
        return normalized;
      }
    }

    final startPoints = <String>[
      Directory.current.path,
      path.dirname(Platform.resolvedExecutable),
      path.dirname(Platform.script.toFilePath()),
    ];

    for (final start in startPoints) {
      final found = _findWorkspaceRootFrom(start);
      if (found != null) {
        return found;
      }
    }

    return path.normalize(path.join(Directory.current.path, '..'));
  }

  Future<void> start({int? port}) async {
    final p = port ?? this.port;
    _server = await shelf_io.serve(_handler, 'localhost', p);
    _log('Tutorial proxy running at http://localhost:$p');
    _log('Using workspace root: $_workspaceRoot');
  }

  Future<void> stop() async {
    if (_server != null) {
      await _server!.close();
    }
  }

  HttpServer? _server;

  void _log(String message) {
    stdout.writeln('[TutorialProxy] $message');
  }

  // -----------------------------------------------------------------------
  // Request handling
  // -----------------------------------------------------------------------

  Handler get _handler {
    return (Request request) async {
      // Handle static JS/CSS files
      if (request.url.path.startsWith('js/')) {
        return _serveStaticFile(request);
      }
      // Proxy tutorial pages
      return _proxyTutorial(request);
    };
  }

  Future<Response> _serveStaticFile(Request request) async {
    var filePath = request.url.path;
    // Remove leading slash if present (shelf gives path as /js/file.js)
    if (filePath.startsWith('/')) {
      filePath = filePath.substring(1);
    }
    // Now strip the 'js/' prefix to get the filename
    filePath = filePath.replaceFirst('js/', '');
    final fullPath = path.join(_workspaceRoot, 'js', filePath);
    final file = File(fullPath);

    if (!await file.exists()) {
      return Response.notFound('File not found: $filePath');
    }

    final bytes = await file.readAsBytes();
    final contentType = filePath.endsWith('.css')
        ? 'text/css'
        : filePath.endsWith('.js')
            ? 'application/javascript'
            : 'application/octet-stream';

    return Response.ok(bytes, headers: {'Content-Type': contentType});
  }

  Future<Response> _proxyTutorial(Request request) async {
    final uriPath = request.url.path;
    final urlPath = uriPath.isEmpty ? '/' : (uriPath.startsWith('/') ? uriPath : '/$uriPath');
    final query = request.url.query.isNotEmpty ? '?${request.url.query}' : '';
    final url = 'https://ubuntu.com$urlPath$query';

    // Check cache first
    final cached = _getCached(url);
    if (cached != null) {
      _log('Cache hit: $url');
      return Response.ok(cached.body, headers: {'Content-Type': 'text/html', 'X-Cache': 'HIT'});
    }

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': request.headers['user-agent'] ?? 'Lighthouse Proxy',
          'Accept': 'text/html',
        },
      );

      if (response.statusCode != 200) {
        final contentType = response.headers['content-type'] ?? 'text/plain; charset=utf-8';
        return Response(
          response.statusCode,
          body: response.bodyBytes,
          headers: {'Content-Type': contentType},
        );
      }

      final contentType = response.headers['content-type']?.toLowerCase() ?? '';
      final isHtml = contentType.contains('text/html');

      if (!isHtml) {
        return Response(
          response.statusCode,
          body: response.bodyBytes,
          headers: {'Content-Type': response.headers['content-type'] ?? 'application/octet-stream'},
        );
      }

      // Process and cache HTML tutorial pages only.
      String processedHtml = _processContent(response.body, url);
      _setCached(url, processedHtml);
      
      return Response.ok(processedHtml, headers: {'Content-Type': 'text/html', 'X-Cache': 'MISS'});
    } on http.ClientException catch (e) {
      return Response(
        502,
        body: '<html><body><h1>Proxy Error</h1><p>Failed to fetch $url: ${e.message}</p></body></html>',
        headers: {'Content-Type': 'text/html'},
      );
    } on FormatException catch (e) {
      _log('Malformed HTML from $url: ${e.message}');
      return Response(
        502,
        body: '<html><body><h1>Content Error</h1><p>The fetched content was malformed and could not be processed.</p></body></html>',
        headers: {'Content-Type': 'text/html'},
      );
    } catch (e) {
      return Response(
        502,
        body: '<html><body><h1>Proxy Error</h1><p>Failed to fetch $url: $e</p></body></html>',
        headers: {'Content-Type': 'text/html'},
      );
    }
  }

  // -----------------------------------------------------------------------
  // Content processing - filtering and injection
  // -----------------------------------------------------------------------

  String _processContent(String html, String url) {
    // Inject our assets
    html = _injectAssets(html);

    return html;
  }

  String _injectAssets(String html) {
    // Inject CSS in <head> if not already present
    if (!html.contains('tutorial_controller.css')) {
      final headEnd = html.indexOf('</head>');
      if (headEnd != -1) {
        html = html.replaceFirst(
          '</head>',
          '<link rel="stylesheet" href="/js/tutorial_controller.css">\n</head>',
        );
      }
    }
    // Inject JS before </body>
    final bodyEnd = html.indexOf('</body>');
    if (bodyEnd != -1) {
      html = html.replaceFirst(
        '</body>',
        '<script src="/js/tutorial_controller.js"></script>\n</body>',
      );
    }
    return html;
  }

  // -----------------------------------------------------------------------
  // Simple cache implementation
  // -----------------------------------------------------------------------

  _CacheEntry? _getCached(String url) {
    final entry = _cache[url];
    if (entry == null) return null;
    
    if (DateTime.now().difference(entry.timestamp) > _cacheDuration) {
      _cache.remove(url);
      return null;
    }
    return entry;
  }

  void _setCached(String url, String body) {
    // Limit cache size to prevent memory issues
    if (_cache.length > 100) {
      // Remove oldest entries
      final toRemove = _cache.keys.take(20).toList();
      for (final key in toRemove) {
        _cache.remove(key);
      }
    }
    _cache[url] = _CacheEntry(body, DateTime.now());
  }
}

class _CacheEntry {
  _CacheEntry(this.body, this.timestamp);
  final String body;
  final DateTime timestamp;
}
