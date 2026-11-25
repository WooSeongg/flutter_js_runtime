// Keeps the code samples in README.md honest: each test mirrors one snippet.
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
