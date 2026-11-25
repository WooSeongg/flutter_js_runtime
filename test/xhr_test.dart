// XMLHttpRequest polyfill: response headers.
// Runs on the host engine (JavaScriptCore on macOS).
import 'dart:convert';

import 'package:flutter_js_runtime/extensions/xhr.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fetch_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestHttpServer server;

  setUpAll(() async {
    useRealHttpClientForXhr();
    server = await TestHttpServer.start({
      '/headers': (r) => r
        ..headers.set('X-Custom-Header', 'Hello')
        ..headers.set('X-Url', 'http://example.com:8080/a?b=c')
        ..headers.set('X-Empty', '')
        ..write('{}'),
    });
  });

  tearDownAll(() => server.close());

  group('response info sent to JavaScript', () {
    test('toJson gives responseHeaders as a list of [name, value]', () {
      final info = XhtmlHttpResponseInfo(statusCode: 200, statusText: 'OK')
        ..addResponseHeaders('a', 'b');
      expect(jsonDecode(jsonEncode(info))['responseHeaders'], [
        ['a', 'b']
      ]);
    });

    test('toJson gives an empty list when there are no headers', () {
      final info = XhtmlHttpResponseInfo(statusCode: 0, statusText: '');
      expect(jsonDecode(jsonEncode(info))['responseHeaders'], <dynamic>[]);
    });
  });

  group('headers of a real response', () {
    // Decoded `ok` value of read(xhr, event) after a request to [path].
    Future<dynamic> request(String path, String read,
            {String method = 'GET'}) async =>
        jsonDecode(await xhrOutcome(server.url(path), read, method: method))[
            'ok'];

    test('getAllResponseHeaders() gives sorted "name: value" CRLF lines',
        () async {
      final all =
          await request('/headers', 'x => x.getAllResponseHeaders()') as String;
      expect(all, endsWith('\r\n'));
      // The server adds its own default headers, so only the shape and the
      // headers set by the route are checked.
      final lines = all.split('\r\n')..removeLast();
      expect(lines, everyElement(matches(RegExp(r'^[^\s:A-Z]+: .*$'))));
      expect(
          lines,
          containsAll([
            'x-custom-header: Hello',
            'x-url: http://example.com:8080/a?b=c',
            'x-empty: ',
          ]));
      final names = [for (final line in lines) line.split(':').first];
      expect(
          names,
          [...names]
            ..sort((a, b) => a.toUpperCase().compareTo(b.toUpperCase())));
    });

    test('getResponseHeader() ignores case, null when missing', () async {
      expect(
          await request('/headers', '''(x, event) => ({
            event,
            lower: x.getResponseHeader('x-custom-header'),
            mixed: x.getResponseHeader('X-Custom-HEADER'),
            missing: x.getResponseHeader('x-nope'),
            empty: x.getResponseHeader('x-empty')})'''),
          {
            'event': 'load',
            'lower': 'Hello',
            'mixed': 'Hello',
            'missing': null,
            'empty': ''
          });
    });

    test('a HEAD response has headers and an empty body', () async {
      expect(
          await request(
              '/headers',
              '''(x, event) => ({
            event,
            header: x.getResponseHeader('x-custom-header'),
            text: x.responseText})''',
              method: 'HEAD'),
          {'event': 'load', 'header': 'Hello', 'text': ''});
    });

    test('a network failure has no headers', () async {
      final port = await closedPort();
      final outcome = await xhrOutcome('http://127.0.0.1:$port/', '''(x, event) => ({
        event,
        status: x.status,
        all: x.getAllResponseHeaders(),
        type: x.getResponseHeader('content-type')})''');
      expect(jsonDecode(outcome)['ok'],
          {'event': 'error', 'status': 0, 'all': '', 'type': null});
    });
  });

  group('header lists the HTTP client does not produce', () {
    // Result of read(xhr) for a 200 response carrying [headers].
    dynamic respondWith(Object? headers, String read) =>
        jsonDecode(xhrWithCannedResponse({
          'statusCode': 200,
          'statusText': 'OK',
          if (headers != null) 'responseHeaders': headers,
        }, read));

    test('before a response there are no headers', () {
      expect(
          respondWith([], '''() => {
            const fresh = new XMLHttpRequest();
            return {all: fresh.getAllResponseHeaders(),
                    one: fresh.getResponseHeader('a')}; }'''),
          {'all': '', 'one': null});
    });

    test('mixed-case and repeated names are combined', () {
      expect(
          respondWith([
            ['X-A', '1'],
            ['x-a', '2'],
            ['B', '']
          ], '''x => ({
            a: x.getResponseHeader('X-a'),
            b: x.getResponseHeader('b'),
            missing: x.getResponseHeader('c'),
            all: x.getAllResponseHeaders()})'''),
          {'a': '1, 2', 'b': '', 'missing': null, 'all': 'b: \r\nx-a: 1, 2\r\n'});
    });

    test('names are sorted by their upper-cased form', () {
      expect(
          respondWith([
            ['x_a', 'u'],
            ['xab', 'z'],
            ['Zed', '1'],
            ['Date', 'Wed, 25 Nov 2026 00:00:00 GMT']
          ], 'x => x.getAllResponseHeaders()'),
          'date: Wed, 25 Nov 2026 00:00:00 GMT\r\n'
          'xab: z\r\n'
          'x_a: u\r\n'
          'zed: 1\r\n');
    });

    test('names with the same upper-cased form stay one line each', () {
      expect(
          respondWith([
            ['ss', '1'],
            ['\u00df', '2'],
            ['SS', '3']
          ], 'x => x.getAllResponseHeaders()'),
          'ss: 1, 3\r\n\u00df: 2\r\n');
    });

    test('a payload that is not a list of pairs gives no headers', () {
      const read = '''x => ({all: x.getAllResponseHeaders(),
                             one: x.getResponseHeader('[')})''';
      const none = {'all': '', 'one': null};
      expect(respondWith('[]', read), none);
      expect(respondWith(null, read), none);
      expect(respondWith(['a', 5, []], read), none);
    });

    test('open() on a finished request clears its headers', () {
      expect(
          respondWith([
            ['a', '1']
          ], '''x => {
            const before = x.getResponseHeader('a');
            x.open('GET', 'http://unused.invalid/');
            return {before, after: x.getResponseHeader('a'),
                    all: x.getAllResponseHeaders()}; }'''),
          {'before': '1', 'after': null, 'all': ''});
    });
  });
}
