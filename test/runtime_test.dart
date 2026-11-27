// Behaviour of the JavaScript environment a runtime sets up: timers, the
// sendMessage channel, promises and value conversion.
// Runs on the host engine (JavaScriptCore on macOS). Issue numbers refer to
// https://github.com/abner/flutter_js/issues.
import 'dart:io';

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

  group('sendMessage from JavaScript', () {
    // Wraps the call so the outcome is a string on every engine.
    String call(String js) => runtime.evaluate('''(function () {
      try { return 'returned:' + String($js); }
      catch (e) { return 'threw'; } })()''').stringResult;

    test('with fewer than two arguments throws instead of crashing', () {
      runtime.onMessage('channel', (args) => 'reply');
      expect(call("sendMessage('channel', '1')"), 'returned:reply');
      expect(call("sendMessage('channel')"), 'threw');
      expect(call('sendMessage()'), 'threw');
      // The runtime is still usable.
      expect(call("sendMessage('channel', '2')"), 'returned:reply');
    });

    test('an async handler that fails rejects the promise', () async {
      runtime.onMessage(
          'fail', (args) => Future<String>.error('bad "quote"\nsecond line'));
      runtime.evaluate('''globalThis.outcome = 'pending';
        Promise.resolve(sendMessage('fail', '1')).then(
          function () { outcome = 'resolved'; },
          function () { outcome = 'rejected'; });''');
      for (var i = 0; i < 50; i++) {
        await Future.delayed(const Duration(milliseconds: 20));
        runtime.executePendingJob();
        if (runtime.evaluate('outcome').stringResult != 'pending') break;
      }
      expect(runtime.evaluate('outcome').stringResult, 'rejected');
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

  test('evaluate does not leak memory on every call', () async {
    const script = 'Math.max(1, 2) + JSON.stringify({a: 1}).length';
    // Evaluates in batches, returning to the event loop in between as an
    // app does.
    Future<void> evaluateBatches(int batches) async {
      for (var batch = 0; batch < batches; batch++) {
        for (var i = 0; i < 5000; i++) {
          runtime.evaluate(script);
        }
        await Future<void>.delayed(Duration.zero);
      }
    }

    // Let the engine's own caches and heap settle first.
    await evaluateBatches(4);
    final before = ProcessInfo.currentRss;
    await evaluateBatches(120); // 600,000 evaluates
    final grownMb = (ProcessInfo.currentRss - before) / (1024 * 1024);
    // The old leaks grew about 190 MB (JavaScriptCore) and 24 MB (QuickJS)
    // here; without them growth stays within a few MB.
    expect(grownMb, lessThan(12));
  });

  // Object results are checked for then/catch and errors read message/stack;
  // each property read leaked its name (JavaScriptCore).
  // Measured over 200,000 evaluates: an object grew 40 MB before the fix and
  // under 1 MB after; an error 121 MB before and about 23 MB after (the rest
  // is JavaScriptCore collecting Error objects late, not a steady leak).
  for (final entry in {
    'an object': ('({a: 1})', 12),
    'an error': ('throw new Error("boom")', 60),
  }.entries) {
    final (script, limitMb) = entry.value;
    test('evaluate returning ${entry.key} does not leak memory', () async {
      Future<void> evaluateBatches(int batches) async {
        for (var batch = 0; batch < batches; batch++) {
          for (var i = 0; i < 5000; i++) {
            runtime.evaluate(script);
          }
          await Future<void>.delayed(Duration.zero);
        }
      }

      await evaluateBatches(4);
      final before = ProcessInfo.currentRss;
      await evaluateBatches(40); // 200,000 evaluates
      final grownMb = (ProcessInfo.currentRss - before) / (1024 * 1024);
      expect(grownMb, lessThan(limitMb));
    });
  }

  group('convertValue', () {
    T? convert<T>(String js) => runtime.convertValue<T>(runtime.evaluate(js));

    test('whole numbers are int, others double', () {
      expect(convert<num>('5'), 5);
      expect(convert<num>('5'), isA<int>());
      expect(convert<num>('2 ** 40'), 1099511627776);
      expect(convert<num>('1.5'), 1.5);
      expect(convert<num>('1e-7'), 1e-7);
    });

    test('NaN, Infinity and numbers beyond int64 are double', () {
      expect(convert<num>('0 / 0'), isNaN);
      expect(convert<num>('1 / 0'), double.infinity);
      expect(convert<num>('-1 / 0'), double.negativeInfinity);
      expect(convert<num>('1e21'), 1e21);
      expect(convert<num>('1e21'), isA<double>());
      expect(convert<num>('-(2 ** 63)'), isA<double>());
    });

    test('whole numbers up to the int64 limit are int', () {
      expect(convert<num>('9.21e18'), 9210000000000000000);
      expect(convert<num>('9.21e18'), isA<int>());
      expect(convert<num>('-9.21e18'), isA<int>());
    });

    test('a number that does not fit the requested type gives null', () {
      expect(convert<int>('1.5'), isNull);
      expect(convert<int>('0 / 0'), isNull);
    });
  });
}
