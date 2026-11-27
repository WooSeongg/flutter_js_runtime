// Keeps the code samples in README.md honest: each test mirrors one snippet.
import 'dart:convert';

import 'package:flutter_js_runtime/extensions/fetch.dart';
import 'package:flutter_js_runtime/flutter_js_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('README: evaluate code', () {
    final runtime = getJavascriptRuntime(xhr: false);
    final result = runtime.evaluate('Math.pow(5, 3)');
    expect(result.stringResult, equals('125'));
    runtime.dispose();
  });

  test('README: promises and async code', () async {
    final runtime = getJavascriptRuntime(xhr: false);
    final pending = await runtime.evaluateAsync('''
      new Promise((resolve) => setTimeout(() => resolve('done'), 100));
    ''');
    runtime.executePendingJob();
    final resolved = await runtime.handlePromise(pending);
    expect(resolved.stringResult, equals('"done"')); // JSON-encoded
    runtime.dispose();
  });

  test('README: messages from JavaScript to Dart', () {
    final runtime = getJavascriptRuntime(xhr: false);
    dynamic received;
    runtime.onMessage('greeting', (dynamic args) => received = args);
    runtime.evaluate(
        "sendMessage('greeting', JSON.stringify({name: 'Flutter'}));");
    expect(received.toString(), contains('Flutter'));
    runtime.dispose();
  });

  test('README: enableFetch on a runtime created with xhr: false', () async {
    final runtime = getJavascriptRuntime(xhr: false);
    await runtime.enableFetch();
    expect(runtime.evaluate('typeof fetch').stringResult, equals('function'));
    runtime.dispose();
  });

  test('README: Usage snippets run in order on one runtime, then Cleanup',
      () async {
    final runtime = getJavascriptRuntime(xhr: false);
    expect(runtime.evaluate('Math.pow(5, 3)').stringResult, equals('125'));

    final pending = await runtime.evaluateAsync('''
      new Promise((resolve) => setTimeout(() => resolve('done'), 100));
    ''');
    runtime.executePendingJob();
    expect((await runtime.handlePromise(pending)).stringResult,
        equals('"done"'));

    dynamic received;
    runtime.onMessage('greeting', (dynamic args) => received = args);
    runtime.evaluate(
        "sendMessage('greeting', JSON.stringify({name: 'Flutter'}));");
    expect(received.toString(), contains('Flutter'));

    runtime.dispose();
  });

  test('README FAQ: call a JavaScript function with arguments', () {
    final runtime = getJavascriptRuntime(xhr: false);
    runtime.evaluate('function greet(name) { return "Hello, " + name; }');
    final result = runtime.evaluate('greet(${jsonEncode('Flutter')})');
    expect(result.stringResult, equals('Hello, Flutter'));
    // jsonEncode keeps quotes and backslashes in the argument intact.
    expect(runtime.evaluate('greet(${jsonEncode('a"b\\c')})').stringResult,
        equals('Hello, a"b\\c'));
    runtime.dispose();
  });

  test('README FAQ: files evaluated in order share the global scope', () {
    final runtime = getJavascriptRuntime(xhr: false);
    runtime.evaluate('class ClassOne { hello() { return "one"; } }');
    runtime.evaluate('const two = new ClassOne();');
    expect(runtime.evaluate('two.hello()').stringResult, equals('one'));
    runtime.dispose();
  });

  test('README FAQ: a new runtime starts empty', () {
    var runtime = getJavascriptRuntime(xhr: false);
    runtime.evaluate('var leftover = 1;');
    runtime.dispose();
    runtime = getJavascriptRuntime(xhr: false);
    expect(runtime.evaluate('typeof leftover').stringResult,
        equals('undefined'));
    runtime.dispose();
  });

  // getJavascriptRuntime() with the default xhr: true starts enableFetch()
  // without awaiting it; the polyfill must not be evaluated on a runtime
  // that was disposed in the meantime.
  test('dispose right after getJavascriptRuntime() with xhr: true', () async {
    final runtime = getJavascriptRuntime();
    expect(runtime.evaluate('1 + 1').stringResult, equals('2'));
    runtime.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });
}
