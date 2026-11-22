import 'package:flutter_js_runtime/extensions/fetch.dart';
import 'package:flutter_js_runtime/flutter_js.dart' as legacy;
import 'package:flutter_js_runtime/flutter_js_runtime.dart' as current;
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('both entry points expose the same runtime API', () {
    expect(
      identical(legacy.getJavascriptRuntime, current.getJavascriptRuntime),
      isTrue,
    );
    final rt = current.getJavascriptRuntime(xhr: false);
    expect(rt, isA<legacy.JavascriptRuntime>());
    expect(rt.evaluate('1 + 1').stringResult, equals('2'));
    rt.dispose();
  });

  test('enableFetch loads the bundled fetch polyfill from this package', () async {
    final rt = current.getJavascriptRuntime(xhr: false);
    await rt.enableFetch();
    expect(rt.evaluate('typeof fetch').stringResult, equals('function'));
    rt.dispose();
  });
}
