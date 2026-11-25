import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_js_runtime/extensions/fetch.dart';
import 'package:flutter_js_runtime/flutter_js_runtime.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('evaluate runs JavaScript through the platform engine',
      (tester) async {
    final runtime = getJavascriptRuntime();
    expect(
      runtime.evaluate('[1, 2, 3].map(x => x * 2).join(",")').stringResult,
      '2,4,6',
    );
    expect(
      runtime.runtimeType.toString(),
      Platform.isAndroid ? 'QuickJsRuntime2' : 'JavascriptCoreRuntime',
    );
  });

  testWidgets('evaluateAsync resolves a promise', (tester) async {
    final runtime = getJavascriptRuntime();
    final pending = await runtime.evaluateAsync('Promise.resolve(40 + 2)');
    runtime.executePendingJob();
    final resolved = await runtime.handlePromise(pending);
    expect(resolved.stringResult, '42');
  });

  testWidgets('evaluate marks a promise result with isPromise (#155)',
      (tester) async {
    final runtime = getJavascriptRuntime();
    expect(runtime.evaluate('Promise.resolve(1)').isPromise, isTrue);
    expect(runtime.evaluate('1').isPromise, isFalse);
  });

  testWidgets('convertValue returns the evaluated value (#101)', (tester) async {
    final runtime = getJavascriptRuntime();
    expect(runtime.convertValue<int>(runtime.evaluate('5')), 5);
    expect(runtime.convertValue<String>(runtime.evaluate('"a"')), 'a');
    expect(runtime.convertValue<int>(runtime.evaluate('2 ** 40')), 1099511627776);
    expect(runtime.convertValue<double>(runtime.evaluate('1.5')), 1.5);
    expect(runtime.convertValue<int>(runtime.evaluate('1.5')), isNull);
    expect(
      runtime.convertValue<Map<String, dynamic>>(
          runtime.evaluate('({a: 1, b: [true, "x"]})')),
      {
        'a': 1,
        'b': [true, 'x']
      },
    );
  });

  testWidgets('fetch network failure rejects the Dart future', (tester) async {
    await tester.runAsync(() async {
      final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = closed.port;
      await closed.close();
      final runtime = getJavascriptRuntime(xhr: false);
      await runtime.enableFetch();
      final pending = runtime.evaluate("fetch('http://127.0.0.1:$port/')");
      await expectLater(
        runtime.handlePromise(pending, timeout: const Duration(seconds: 5)),
        throwsA(isNot(isA<TimeoutException>())),
      );
    });
  });

  testWidgets('sourceUrl appears in the error stack (#146)', (tester) async {
    final runtime = getJavascriptRuntime();
    final stack = runtime.evaluate(
      '(function () { try { throw new Error("x"); } catch (e) { return String(e.stack); } })()',
      sourceUrl: 'my_script.js',
    );
    expect(stack.stringResult, contains('my_script.js'));
  });

  testWidgets('QuickJS: a listener on the runtime port still gets ticks',
      (tester) async {
    final runtime = getJavascriptRuntime();
    if (runtime is! QuickJsRuntime2) return;
    await tester.runAsync(() async {
      final ticks = <dynamic>[];
      final subscription = runtime.port.listen(ticks.add);
      runtime.evaluate('1 + 1');
      await Future.delayed(const Duration(milliseconds: 50));
      expect(ticks, isNotEmpty);
      await subscription.cancel();
    });
  }, skip: !Platform.isAndroid);

  testWidgets('native plugin class answers on its method channel',
      (tester) async {
    const channel = MethodChannel('io.github.wooseongg.flutter_js_runtime');
    if (Platform.isIOS) {
      expect(await channel.invokeMethod('initEngine', 7), 7);
    } else if (Platform.isAndroid) {
      expect(await channel.invokeMethod('getPlatformVersion'),
          startsWith('Android'));
    } else if (Platform.isMacOS) {
      expect(
        await const MethodChannel('flutter_js_runtime')
            .invokeMethod('getPlatformVersion'),
        startsWith('macOS'),
      );
    }
  });
}
