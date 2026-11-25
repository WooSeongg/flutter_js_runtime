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
