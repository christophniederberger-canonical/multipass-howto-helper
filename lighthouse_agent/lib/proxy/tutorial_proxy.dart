import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

/// Local HTTP proxy that serves tutorial pages with the JS controller injected.
/// Runs on port 8080 and proxies requests to ubuntu.com while injecting
/// the tutorial_controller script and stylesheet.
class TutorialProxy {
  final int port;
  late HttpServer _server;
  final String _workspaceRoot;

  TutorialProxy({this.port = 8080})
      : _workspaceRoot = path.normalize(
          path.join(path.dirname(Platform.script.toFilePath()), '..', '..'),
        );

  Future<void> start({int? port}) async {
    final p = port ?? this.port;
    _server = await shelf_io.serve(_handler, 'localhost', p);
    print('Tutorial proxy running at http://localhost:$p');
  }

  Future<void> stop() async {
    await _server.close();
  }

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
    final filePath = request.url.path.replaceFirst('js/', '');
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
    final query = request.url.query.isNotEmpty ? '?${request.url.query}' : '';
    final url = 'https://ubuntu.com${request.url.path}$query';

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': request.headers['user-agent'] ?? 'Lighthouse Proxy',
          'Accept': 'text/html',
        },
      );

      if (response.statusCode != 200) {
        return Response(
          response.statusCode,
          body: '<html><body><h1>Failed to fetch tutorial</h1><p>URL: $url<br>Status: ${response.statusCode}</p></body></html>',
          headers: {'Content-Type': 'text/html'},
        );
      }

      final modifiedHtml = _injectAssets(response.body);
      return Response.ok(modifiedHtml, headers: {'Content-Type': 'text/html'});
    } on http.ClientException catch (e) {
      return Response(
        502,
        body: '<html><body><h1>Proxy Error</h1><p>Failed to fetch $url: ${e.message}</p></body></html>',
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

  String _injectAssets(String html) {
    // Inject CSS in <head> if not already present
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
}
