import 'dart:io';

import 'package:flutter/services.dart';
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
