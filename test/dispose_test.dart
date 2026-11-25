// What happens around JavascriptRuntime.dispose(), and with several runtimes
// alive at once. Runs on the host engine (JavaScriptCore on macOS). Issue
// numbers refer to https://github.com/abner/flutter_js/issues.
import 'dart:async';
import 'dart:io';

import 'package:flutter_js_runtime/extensions/xhr.dart';
import 'package:flutter_js_runtime/flutter_js.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fetch_harness.dart';

/// Runs [body] and returns the errors nothing caught while it ran.
Future<List<Object>> uncaughtErrorsOf(Future<void> Function() body) async {
  final errors = <Object>[];
  final done = Completer<void>();
  runZonedGuarded(() async {
    try {
      await body();
    } catch (error) {
      // A failed expectation in the body: report it, do not time out.
      errors.add(error);
    } finally {
      done.complete();
    }
  }, (error, stack) => errors.add(error));
  await done.future;
  return errors;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('dispose() can be called twice', () {
    final runtime = getJavascriptRuntime(xhr: false);
    runtime.dispose();
    runtime.dispose();
  });

  test('dispose() removes the runtime from the channel registry', () {
    final runtime = getJavascriptRuntime(xhr: false);
    final id = runtime.getEngineInstanceId();
    expect(JavascriptRuntime.channelFunctionsRegistered, contains(id));
    runtime.dispose();
    expect(JavascriptRuntime.channelFunctionsRegistered, isNot(contains(id)));
  });

  test('dispose() cancels the timers the runtime started (#37, #168)',
      () async {
    final timers = <Timer>[];
    late JavascriptRuntime runtime;
    // Records every timer created while the runtime is set up and used.
    await runZoned(() async {
      runtime = getJavascriptRuntime(xhr: false);
      runtime.enableXhr(); // polls every 40 ms
      runtime.evaluate('setTimeout(function () {}, 3600000);');
      final pending = runtime.evaluate('new Promise(function () {})');
      unawaited(runtime
          .handlePromise(pending)
          .then<void>((_) {}, onError: (_) {})); // polls every 20 ms
      await Future<void>.delayed(const Duration(milliseconds: 60));
    },
        zoneSpecification: ZoneSpecification(
          createTimer: (self, parent, zone, duration, callback) {
            final timer = parent.createTimer(zone, duration, callback);
            timers.add(timer);
            return timer;
          },
          createPeriodicTimer: (self, parent, zone, period, callback) {
            final timer = parent.createPeriodicTimer(zone, period, callback);
            timers.add(timer);
            return timer;
          },
        ));
    expect(timers.where((timer) => timer.isActive), isNotEmpty);
    runtime.dispose();
    // The QuickJS promise poll is a chain of one-shot timers that stops at
    // its next turn.
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(timers.where((timer) => timer.isActive), isEmpty);
  });

  test('dispose() right after getJavascriptRuntime() is safe', () async {
    final errors = await uncaughtErrorsOf(() async {
      // xhr: true loads the fetch polyfill in the background.
      final runtime = getJavascriptRuntime();
      expect(runtime.evaluate('1 + 1').stringResult, '2');
      runtime.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    expect(errors, isEmpty);
  });

  test('work still pending at dispose() is dropped without errors', () async {
    final errors = await uncaughtErrorsOf(() async {
      final runtime = getJavascriptRuntime(xhr: false);
      final reply = Completer<String>();
      runtime.onMessage('slow', (args) => reply.future);
      runtime.evaluate('''
        setTimeout(function () { globalThis.fired = true; }, 50);
        Promise.resolve(sendMessage('slow', '1')).then(function () {});''');
      final pending = runtime.evaluate(
          'new Promise(function (resolve) { setTimeout(resolve, 30); })');
      unawaited(runtime
          .handlePromise(pending)
          .then<void>((_) {}, onError: (_) {}));
      runtime.dispose();
      reply.complete('late');
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    expect(errors, isEmpty);
  });

  test('a response that arrives after dispose() is dropped', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      request.response.write('ok');
      await request.response.close();
    });
    useRealHttpClientForXhr();
    final errors = await uncaughtErrorsOf(() async {
      final runtime = getJavascriptRuntime(xhr: false);
      runtime.enableXhr();
      runtime.evaluate('''var xhr = new XMLHttpRequest();
        xhr.open('GET', 'http://127.0.0.1:${server.port}/');
        xhr.send();''');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      runtime.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await server.close(force: true);
    expect(errors, isEmpty);
  });

  group('dispose() inside a channel handler', () {
    test('lets the running script finish', () async {
      final errors = await uncaughtErrorsOf(() async {
        final runtime = getJavascriptRuntime(xhr: false);
        var callsAfterDispose = 0;
        runtime.onMessage('after', (args) => callsAfterDispose++);
        runtime.onMessage('bye', (args) {
          runtime.dispose();
          return 1;
        });
        final result = runtime.evaluate('''sendMessage('bye', '1');
          try { sendMessage('after', '1'); } catch (e) {}
          'finished' ''');
        expect(result.stringResult, 'finished');
        expect(callsAfterDispose, 0);
        runtime.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      expect(errors, isEmpty);
    });

    test('by a handler that returns a Future', () async {
      final errors = await uncaughtErrorsOf(() async {
        final runtime = getJavascriptRuntime(xhr: false);
        runtime.onMessage('bye', (args) async => runtime.dispose());
        final result = runtime.evaluate("sendMessage('bye', '1'); 'finished'");
        expect(result.stringResult, 'finished');
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      expect(errors, isEmpty);
    });

    test('from a setTimeout callback', () async {
      final errors = await uncaughtErrorsOf(() async {
        final runtime = getJavascriptRuntime(xhr: false);
        var disposed = false;
        runtime.onMessage('bye', (args) {
          runtime.dispose();
          disposed = true;
          return 1;
        });
        runtime.evaluate('''setTimeout(function () {
          sendMessage('bye', '1');
          setTimeout(function () {}, 10);
        }, 10);''');
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(disposed, isTrue);
      });
      expect(errors, isEmpty);
    });

    test('many times over', () async {
      for (var i = 0; i < 200; i++) {
        final runtime = getJavascriptRuntime(xhr: false);
        runtime.onMessage('bye', (args) {
          runtime.dispose();
          return 1;
        });
        runtime.evaluate("sendMessage('bye', '1');");
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
  });

  test('many pending timeouts stay cheap to add', () {
    final runtime = getJavascriptRuntime(xhr: false);
    final watch = Stopwatch()..start();
    runtime.evaluate('''for (var i = 0; i < 20000; i++) {
      setTimeout(function () {}, 3600000);
    }''');
    // About 0.15 s; a sweep of all pending timers per call took several.
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    runtime.dispose();
  });

  group('several runtimes', () {
    test('each one gets the messages of its own JavaScript', () {
      final first = getJavascriptRuntime(xhr: false);
      final second = getJavascriptRuntime(xhr: false);
      final received = <String>[];
      first.onMessage('ping', (args) {
        received.add('first:$args');
        return 'from first';
      });
      second.onMessage('ping', (args) {
        received.add('second:$args');
        return 'from second';
      });
      expect(first.evaluate("sendMessage('ping', '1')").stringResult,
          'from first');
      expect(second.evaluate("sendMessage('ping', '2')").stringResult,
          'from second');
      expect(received, ['first:1', 'second:2']);
      first.dispose();
      second.dispose();
    });

    test('one keeps working after a later one is disposed', () async {
      final first = getJavascriptRuntime(xhr: false);
      var ticks = 0;
      first.onMessage('tick', (args) => ticks++);
      getJavascriptRuntime(xhr: false).dispose();

      first.evaluate('''console.log('still alive');
        setTimeout(function () { sendMessage('tick', '1'); }, 5);''');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(ticks, 1);

      final pending = first.evaluate('Promise.resolve(7)');
      first.executePendingJob();
      final result = await first.handlePromise(pending,
          timeout: const Duration(seconds: 3));
      expect(result.stringResult, '7');
      first.dispose();
    });

    test('an entry of another runtime with the same id is left alone', () {
      final runtime = getJavascriptRuntime(xhr: false);
      runtime.onMessage('ping', (args) => 'mine');
      final id = runtime.getEngineInstanceId();
      // Engine ids are hash codes: simulate another runtime taking this one.
      final other = <String, dynamic Function(dynamic)>{};
      JavascriptRuntime.channelFunctionsRegistered[id] = other;
      expect(runtime.evaluate("sendMessage('ping', '1')").stringResult, 'mine');
      runtime.dispose();
      expect(JavascriptRuntime.channelFunctionsRegistered[id], same(other));
      JavascriptRuntime.channelFunctionsRegistered.remove(id);
    });
  });

  group('JavaScriptCore: using a disposed runtime', () {
    test('throws a StateError instead of crashing', () {
      final runtime = getJavascriptRuntime(xhr: false);
      final value = runtime.evaluate('({a: 1})');
      runtime.dispose();
      expect(() => runtime.evaluate('1'), throwsStateError);
      expect(() => runtime.evaluateAsync('1'), throwsStateError);
      // Registering a handler touches no native state; as before, it is
      // simply never called.
      runtime.onMessage('channel', (args) {});
      expect(() => runtime.convertValue<dynamic>(value), throwsStateError);
      expect(() => runtime.jsonStringify(value), throwsStateError);
      expect(() => runtime.enableXhr(), throwsStateError);
      expect(runtime.executePendingJob(), 0);
    });
  }, skip: Platform.isMacOS || Platform.isIOS ? false : 'JavaScriptCore only');
}
