// Shared helpers for tests that run `fetch` / `XMLHttpRequest` against a
// local HTTP server. Not a test file itself (no `_test.dart` suffix).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_js_runtime/extensions/fetch.dart';
import 'package:flutter_js_runtime/extensions/xhr.dart';
import 'package:flutter_js_runtime/flutter_js.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// Writes the response for one request path.
typedef RouteHandler = void Function(HttpResponse response);

/// TestWidgetsFlutterBinding replaces HttpClient with a fake that always
/// answers 400. Gives the XHR extension's shared client a real one so tests
/// can reach the loopback server. Each test file runs in its own isolate, so
/// this does not leak into other test files.
void useRealHttpClientForXhr() {
  xhrSetHttpClient(HttpOverrides.runWithHttpOverrides(
      () => http.Client(), _RealHttpOverrides()));
}

class _RealHttpOverrides extends HttpOverrides {}

/// Local HTTP server on 127.0.0.1 that answers each path from [routes].
/// Unknown paths get 404.
class TestHttpServer {
  TestHttpServer._(this._server);

  final HttpServer _server;

  static Future<TestHttpServer> start(Map<String, RouteHandler> routes) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final handler = routes[request.uri.path];
      if (handler == null) {
        request.response.statusCode = HttpStatus.notFound;
      } else {
        handler(request.response);
      }
      await request.response.close();
    });
    return TestHttpServer._(server);
  }

  /// Absolute URL of [path] on this server.
  String url(String path) => 'http://127.0.0.1:${_server.port}$path';

  Future<void> close() => _server.close(force: true);
}

/// A loopback port with nothing listening on it (connections are refused).
Future<int> closedPort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

/// Runs `fetch(url).then(then)` on a fresh runtime and returns the settled
/// outcome as JSON: `{"ok": <value>}` when it resolves, or
/// `{"rejected": <reason instanceof TypeError>}` when it rejects.
///
/// Also fails the test if the response body ran as JavaScript (it sets
/// `globalThis.injected` when it does).
Future<String> fetchOutcome(String url, String then) async {
  final runtime = getJavascriptRuntime(xhr: false);
  await runtime.enableFetch();
  runtime.evaluate('''globalThis.out = undefined;
    fetch(${jsonEncode(url)}).then($then).then(
      v => { globalThis.out = JSON.stringify({ok: v}); },
      e => { globalThis.out = JSON.stringify({rejected: e instanceof TypeError}); });''');
  var out = 'undefined';
  for (var i = 0; i < 150 && out == 'undefined'; i++) {
    await Future.delayed(const Duration(milliseconds: 20));
    runtime.executePendingJob();
    out = runtime.evaluate('String(globalThis.out)').stringResult;
  }
  final injected = runtime.evaluate('String(globalThis.injected)').stringResult;
  runtime.dispose();
  expect(injected, 'undefined', reason: 'response body ran as JavaScript');
  return out;
}
