// fetch / XMLHttpRequest behaviour against a local server.
// Runs on the host engine (JavaScriptCore on macOS). Issue numbers refer to
// https://github.com/abner/flutter_js/issues.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'helpers/fetch_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestHttpServer server;

  setUpAll(() async {
    useRealHttpClientForXhr();
    server = await TestHttpServer.start({
      '/source': (r) => r.write(r"a`b \\ ${globalThis.injected = true}"),
      '/template': (r) => r.write(r"${globalThis.injected = true}"),
      '/raw-json': (r) => r.write('{ "b": 1, "a": 2 }'),
      '/json': (r) => r.write(r'{"s":"line1\nline2"}'),
      '/missing': (r) => r
        ..statusCode = 404
        ..write('nf'),
      '/latin1': (r) => r.add([0x63, 0xff, 0x64]),
    });
  });

  tearDownAll(() => server.close());

  group('response body is passed as data (#135, #80)', () {
    test('backticks and backslashes', () async {
      expect(await fetchOutcome(server.url('/source'), 'r => r.text()'),
          jsonEncode({'ok': r"a`b \\ ${globalThis.injected = true}"}));
    });

    test(r'a ${...} body is not evaluated', () async {
      expect(await fetchOutcome(server.url('/template'), 'r => r.text()'),
          jsonEncode({'ok': r"${globalThis.injected = true}"}));
    });

    test('JSON body text is passed through unchanged', () async {
      expect(await fetchOutcome(server.url('/raw-json'), 'r => r.text()'),
          jsonEncode({'ok': '{ "b": 1, "a": 2 }'}));
    });

    test('json() parses escaped characters', () async {
      expect(
          await fetchOutcome(
              server.url('/json'), 'r => r.json().then(j => j.s)'),
          jsonEncode({'ok': 'line1\nline2'}));
    });
  });

  test('reports the real HTTP status (#175)', () async {
    expect(
        await fetchOutcome(server.url('/missing'),
            'r => ({status: r.status, statusText: r.statusText, ok: r.ok})'),
        jsonEncode({
          'ok': {'status': 404, 'statusText': 'Not Found', 'ok': false}
        }));
  });

  test('malformed UTF-8 is replaced instead of hanging (#137)', () async {
    expect(await fetchOutcome(server.url('/latin1'), 'r => r.text()'),
        jsonEncode({'ok': 'c�d'}));
  });

  test('network failure rejects with a TypeError instead of hanging',
      () async {
    final port = await closedPort();
    expect(await fetchOutcome('http://127.0.0.1:$port/', 'r => r.status'),
        jsonEncode({'rejected': true}));
  });
}
