// Shared helpers for tests that run `fetch` / `XMLHttpRequest`, mostly
// against a local HTTP server. Not a test file itself (no `_test.dart`
// suffix).
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
/// `/echo` answers with a JSON description of the request it received:
/// `{"method", "body", "headers": {lower-cased name: value}}`.
/// Other unknown paths get 404.
class TestHttpServer {
  TestHttpServer._(this._server);

  final HttpServer _server;

  static Future<TestHttpServer> start(Map<String, RouteHandler> routes) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final handler = routes[request.uri.path];
      if (handler == null && request.uri.path == '/echo') {
        final headers = <String, String>{};
        request.headers.forEach((name, values) {
          headers[name] = values.join(', ');
        });
        final body = await utf8.decoder.bind(request).join();
        request.response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({
            'method': request.method,
            'body': body,
            'headers': headers,
          }));
      } else if (handler == null) {
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

/// Evaluates [promiseExpr] (a JavaScript expression, usually a promise) on a
/// fresh runtime and returns the settled outcome as JSON: `{"ok": <value>}`
/// when it resolves, or `{"rejected": <reason instanceof TypeError>}` when it
/// rejects. Fails the test when it does not settle within 3 seconds.
///
/// Also fails the test if a response body ran as JavaScript (it sets
/// `globalThis.injected` when it does).
Future<String> jsOutcome(String promiseExpr) async {
  final runtime = getJavascriptRuntime(xhr: false);
  await runtime.enableFetch();
  final started = runtime.evaluate('''globalThis.out = undefined;
    Promise.resolve().then(() => ($promiseExpr)).then(
      v => { globalThis.out = JSON.stringify({ok: v}); },
      e => { globalThis.out = JSON.stringify({rejected: e instanceof TypeError}); });''');
  expect(started.isError, isFalse, reason: started.stringResult);
  var out = 'undefined';
  for (var i = 0; i < 150 && out == 'undefined'; i++) {
    await Future.delayed(const Duration(milliseconds: 20));
    runtime.executePendingJob();
    out = runtime.evaluate('String(globalThis.out)').stringResult;
  }
  final injected = runtime.evaluate('String(globalThis.injected)').stringResult;
  runtime.dispose();
  expect(injected, 'undefined', reason: 'response body ran as JavaScript');
  if (out == 'undefined') fail('JavaScript did not settle within 3 seconds');
  return out;
}

/// Runs `fetch(url).then(then)` and returns its [jsOutcome].
Future<String> fetchOutcome(String url, String then) =>
    jsOutcome('fetch(${jsonEncode(url)}).then($then)');

/// Sends one XMLHttpRequest and returns the [jsOutcome] of `read(xhr, event)`,
/// called on `loadend`. `event` is `'load'`, `'error'` or `'none'`.
Future<String> xhrOutcome(String url, String read, {String method = 'GET'}) =>
    jsOutcome('''new Promise((resolve, reject) => {
      const xhr = new XMLHttpRequest();
      let event = 'none';
      xhr.onload = () => { event = 'load'; };
      xhr.onerror = () => { event = 'error'; };
      xhr.onloadend = () => {
        try { resolve(($read)(xhr, event)); } catch (e) { reject(e); }
      };
      xhr.open(${jsonEncode(method)}, ${jsonEncode(url)});
      xhr.send();
    })''');

/// Feeds [responseInfo] (what the Dart side would send for a finished
/// request) straight into a new XMLHttpRequest, without any network, and
/// returns `JSON.stringify(read(xhr))`.
///
/// This reaches into the polyfill's private `_send_native_callback`; it is
/// the only way to test header lists the real HTTP client never produces
/// (mixed-case names, repeated names, malformed payloads).
String xhrWithCannedResponse(Object? responseInfo, String read) {
  final runtime = getJavascriptRuntime(xhr: false);
  runtime.enableXhr();
  final result = runtime.evaluate('''(() => {
    const xhr = new XMLHttpRequest();
    xhr.open('GET', 'http://unused.invalid/');
    xhr.readyState = XMLHttpRequest.LOADING;
    xhr._send_native_callback(${jsonEncode(responseInfo)}, 'body', null);
    return JSON.stringify(($read)(xhr));
  })()''');
  runtime.dispose();
  expect(result.isError, isFalse, reason: result.stringResult);
  return result.stringResult;
}
