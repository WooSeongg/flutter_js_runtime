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

  testWidgets('dispose() twice and right after creation is safe',
      (tester) async {
    await tester.runAsync(() async {
      final runtime = getJavascriptRuntime(); // loads fetch in the background
      runtime.dispose();
      runtime.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
  });

  testWidgets('dispose() inside an onMessage handler lets the script finish',
      (tester) async {
    await tester.runAsync(() async {
      final runtime = getJavascriptRuntime(xhr: false);
      runtime.onMessage('bye', (args) {
        runtime.dispose();
        return 1;
      });
      final result = runtime.evaluate("sendMessage('bye', '1'); 'finished'");
      expect(result.stringResult, 'finished');
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
  });

  testWidgets('a timeout pending at dispose() never calls back',
      (tester) async {
    await tester.runAsync(() async {
      final runtime = getJavascriptRuntime(xhr: false);
      var calls = 0;
      runtime.onMessage('tick', (args) => calls++);
      runtime.evaluate(
          "setTimeout(function () { sendMessage('tick', '1'); }, 50);");
      runtime.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(calls, 0);
    });
  });

  testWidgets('.then runs after the script, without executePendingJob (#100)',
      (tester) async {
    await tester.runAsync(() async {
      final runtime = getJavascriptRuntime(xhr: false);
      final order = <String>[];
      runtime.onMessage('order', (args) => order.add('$args'));
      runtime.evaluate("Promise.resolve().then(() => sendMessage('order', '2'));"
          "sendMessage('order', '1');");
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(order, ['1', '2']);
      runtime.dispose();
    });
  });

  testWidgets('await continues after setTimeout, without handlePromise (#112)',
      (tester) async {
    await tester.runAsync(() async {
      for (final xhr in [false, true]) {
        final runtime = getJavascriptRuntime(xhr: xhr);
        final steps = <String>[];
        runtime.onMessage('step', (args) => steps.add('$args'));
        runtime.evaluate('''
          (async () => {
            await new Promise((resolve) => setTimeout(resolve, 50));
            sendMessage('step', JSON.stringify('timeout'));
            await Promise.resolve();
            sendMessage('step', JSON.stringify('microtask'));
          })();
        ''');
        await Future<void>.delayed(const Duration(milliseconds: 500));
        expect(steps, ['timeout', 'microtask'], reason: 'xhr: $xhr');
        runtime.dispose();
      }
    });
  });

  testWidgets('a Future returned by onMessage resolves the awaiting script',
      (tester) async {
    await tester.runAsync(() async {
      final runtime = getJavascriptRuntime(xhr: false);
      final got = <String>[];
      runtime.onMessage('later', (args) async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return 41;
      });
      runtime.onMessage('got', (args) => got.add('$args'));
      runtime.evaluate('''
        (async () => {
          const value = await sendMessage('later', '1');
          sendMessage('got', JSON.stringify(value + 1));
        })();
      ''');
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(got, ['42']);
      runtime.dispose();
    });
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
