// Behaviour of the JavaScript environment a runtime sets up: timers, the
// sendMessage channel, promises and value conversion.
// Runs on the host engine (JavaScriptCore on macOS). Issue numbers refer to
// https://github.com/abner/flutter_js/issues.
import 'package:flutter_js_runtime/flutter_js.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late JavascriptRuntime runtime;

  setUp(() => runtime = getJavascriptRuntime(xhr: false));
  tearDown(() => runtime.dispose());

  group('setTimeout', () {
    test('fires for delays that are not integers (#62)', () async {
      runtime.evaluate('''globalThis.fired = [];
        setTimeout(function () { fired.push('integer'); }, 10);
        setTimeout(function () { fired.push('fraction'); }, 10.5);
        setTimeout(function () { fired.push('string'); }, "10");
        setTimeout(function () { fired.push('missing'); });
        setTimeout(function () { fired.push('NaN'); }, NaN);
        setTimeout(function () { fired.push('negative'); }, -5);
        setTimeout(function () { fired.push('text'); }, "soon");
        setTimeout(function () { fired.push('array'); }, [10]);''');
      await Future.delayed(const Duration(milliseconds: 300));
      expect(
          runtime.evaluate('fired.sort().join()').stringResult,
          'NaN,array,fraction,integer,missing,negative,string,text');
    });

    test('a fractional delay is truncated, not treated as 0', () async {
      runtime.evaluate('''globalThis.late = false;
        setTimeout(function () { late = true; }, 400.9);''');
      await Future.delayed(const Duration(milliseconds: 100));
      expect(runtime.evaluate('String(late)').stringResult, 'false');
      await Future.delayed(const Duration(milliseconds: 500));
      expect(runtime.evaluate('String(late)').stringResult, 'true');
    });
  });

  test('handlePromise does not touch a global named idx', () async {
    runtime.evaluate('var idx = "mine";');
    final promise = runtime.evaluate('Promise.resolve(7)');
    runtime.executePendingJob();
    final result = await runtime.handlePromise(promise,
        timeout: const Duration(seconds: 3));
    expect(result.stringResult, '7');
    expect(runtime.evaluate('idx').stringResult, 'mine');
  });

}
