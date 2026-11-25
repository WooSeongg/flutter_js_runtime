// fetch / XMLHttpRequest behaviour against a local server.
// Runs on the host engine (JavaScriptCore on macOS). Issue numbers refer to
// https://github.com/abner/flutter_js/issues.
import 'dart:convert';
import 'dart:io';

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
        ..headers.set('X-Why', 'gone')
        ..write('nf'),
      '/latin1': (r) => r.add([0x63, 0xff, 0x64]),
      '/plain': (r) => r.write('x'),
      '/headers': (r) => r
        ..headers.contentType =
            ContentType('application', 'json', charset: 'utf-8')
        ..headers.set('X-Custom-Header', 'Hello')
        ..headers.set('X-Url', 'http://example.com:8080/a?b=c')
        ..headers.set('X-Empty', '')
        ..write('{}'),
      '/multi': (r) => r
        ..headers.add('X-Multi', 'a')
        ..headers.add('X-Multi', 'b')
        ..headers.add('Set-Cookie', 'a=1; Path=/')
        ..headers.add('Set-Cookie', 'b=2; Path=/')
        ..write('x'),
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

  group('request', () {
    // Decoded `ok` value of pick(echo) for fetch('/echo', options), where
    // echo is what the server received.
    Future<dynamic> sent(String options, String pick) async =>
        jsonDecode(await jsOutcome(
            'fetch(${jsonEncode(server.url('/echo'))}, $options)'
            '.then(r => r.json()).then($pick)'))['ok'];

    test('POST without a body sends an empty body, not "null"', () async {
      expect(
          await sent("{method: 'POST'}", '''e => ({
            body: e.body,
            length: e.headers['content-length'],
            hasType: 'content-type' in e.headers})'''),
          {'body': '', 'length': '0', 'hasType': false});
    });

    test('PUT and PATCH without a body send an empty body', () async {
      expect(await sent("{method: 'PUT'}", 'e => e.method + ":" + e.body'),
          'PUT:');
      expect(await sent("{method: 'PATCH'}", 'e => e.method + ":" + e.body'),
          'PATCH:');
    });

    test('a string body is sent unchanged', () async {
      expect(
          await sent("{method: 'POST', body: '{\"a\": 1}'}", 'e => e.body'),
          '{"a": 1}');
    });

    test('a body that is not a string is sent as String(body)', () async {
      expect(await sent("{method: 'POST', body: 5}", 'e => e.body'), '5');
      expect(await sent("{method: 'POST', body: {a: 1}}", 'e => e.body'),
          '[object Object]');
    });

    test('a binary body fails instead of being sent as text', () async {
      expect(
          await jsOutcome('fetch(${jsonEncode(server.url('/echo'))}, '
              '{method: "POST", body: new Uint8Array([104, 105])})'),
          jsonEncode({'rejected': true}));
    });

    test('header values that are not strings are sent as strings', () async {
      expect(
          await sent("{headers: {'X-Id': 1, 'X-Flag': true}}",
              "e => ({id: e.headers['x-id'], flag: e.headers['x-flag']})"),
          {'id': '1', 'flag': 'true'});
    });

    test('methods outside GET/POST/PUT/PATCH/DELETE/HEAD are sent', () async {
      expect(await sent("{method: 'OPTIONS'}", 'e => e.method'), 'OPTIONS');
      expect(await sent("{method: 'options'}", 'e => e.method'), 'OPTIONS');
      expect(
          await sent("{method: 'PROPFIND', body: 'x'}",
              'e => e.method + ":" + e.body'),
          'PROPFIND:x');
    });

    test('finished requests are not kept in memory', () async {
      expect(
          jsonDecode(await jsOutcome(
              'fetch(${jsonEncode(server.url('/plain'))})'
              '.then(() => fetch(${jsonEncode(server.url('/plain'))}))'
              '.then(() => Object.keys(xhrRequests).length)'))['ok'],
          0);
    });
  });

  group('response headers', () {
    // Decoded `ok` value of fetch(path).then(then).
    Future<dynamic> headersOf(String path, String then) async =>
        jsonDecode(await fetchOutcome(server.url(path), then))['ok'];

    test('get() returns the value, whatever the case of the name', () async {
      expect(
          await headersOf('/headers', '''r => ({
            lower: r.headers.get('x-custom-header'),
            upper: r.headers.get('X-CUSTOM-HEADER'),
            type: r.headers.get('Content-Type')})'''),
          {
            'lower': 'Hello',
            'upper': 'Hello',
            'type': 'application/json; charset=utf-8'
          });
    });

    test('has() is true only for headers in the response', () async {
      expect(
          await headersOf('/headers', '''r => ({
            yes: r.headers.has('X-Custom-Header'),
            no: r.headers.has('x-nope'),
            getMissing: r.headers.get('x-nope') == null})'''),
          {'yes': true, 'no': false, 'getMissing': true});
    });

    test('keys() and entries() list the real names in lower case', () async {
      final headers = await headersOf('/headers',
          'r => ({keys: r.headers.keys(), entries: r.headers.entries()})');
      expect(headers['keys'], containsAll(['x-custom-header', 'content-type']));
      expect(headers['keys'], everyElement(matches(RegExp(r'^[a-z0-9-]+$'))));
      expect(
          headers['entries'], contains(equals(['x-custom-header', 'Hello'])));
      expect(headers['entries'], hasLength((headers['keys'] as List).length));
    });

    test('a value with colons and an empty value', () async {
      expect(
          await headersOf('/headers', '''r => ({
            url: r.headers.get('x-url'),
            empty: r.headers.get('x-empty'),
            hasEmpty: r.headers.has('x-empty')})'''),
          {
            'url': 'http://example.com:8080/a?b=c',
            'empty': '',
            'hasEmpty': true
          });
    });

    test('repeated headers arrive as one comma-separated value', () async {
      final headers = await headersOf('/multi', '''r => ({
        multi: r.headers.get('x-multi'),
        cookie: r.headers.get('set-cookie'),
        cookieKeys: r.headers.keys().filter(k => k === 'set-cookie').length})''');
      // The separator (',' or ', ') depends on how the server folds them.
      expect((headers['multi'] as String).split(',').map((v) => v.trim()),
          ['a', 'b']);
      expect(headers['cookie'], allOf(contains('a=1'), contains('b=2')));
      expect(headers['cookieKeys'], 1);
    });

    test('a response without custom headers has no made-up names', () async {
      final headers = await headersOf('/plain',
          "r => ({keys: r.headers.keys(), type: r.headers.get('content-type')})");
      expect(headers['keys'], isNot(anyOf(contains('['), contains(']'))));
      expect(headers['keys'], everyElement(matches(RegExp(r'^[a-z0-9-]+$'))));
      expect(headers['type'], startsWith('text/plain'));
    });

    test('headers of an error status are readable', () async {
      expect(
          await headersOf('/missing',
              "r => ({status: r.status, why: r.headers.get('x-why')})"),
          {'status': 404, 'why': 'gone'});
    });
  });
}
