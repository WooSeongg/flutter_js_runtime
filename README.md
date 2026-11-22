# flutter_js_runtime

Run JavaScript inside Flutter apps through `dart:ffi`. Use it for validation
rules, rule engines, or any logic you want to share between your web and
Flutter code.

| Platform | Engine |
|---|---|
| Android | QuickJS |
| Windows | QuickJS |
| Linux | QuickJS |
| iOS | JavaScriptCore |
| macOS | JavaScriptCore |

## About this project

flutter_js_runtime is a continuation of [flutter_js](https://github.com/abner/flutter_js)
by Ábner Oliveira. It was started because the original package is no longer
actively maintained. The public API is the same, so existing flutter_js code
keeps working after the [migration steps](#migrating-from-flutter_js) below.

## Installation

```yaml
dependencies:
  flutter_js_runtime: ^0.9.0
```

## Usage

### Evaluate code

```dart
import 'package:flutter_js_runtime/flutter_js_runtime.dart';

// xhr: false skips the fetch/XMLHttpRequest polyfills (see below).
final runtime = getJavascriptRuntime(xhr: false);

final result = runtime.evaluate('Math.pow(5, 3)');
print(result.stringResult); // 125
```

`getJavascriptRuntime()` picks the engine for the current platform. The
snippets below reuse this `runtime`; call `runtime.dispose()` once you no
longer need it (see [Cleanup](#cleanup)).

### Promises and async code

```dart
final pending = await runtime.evaluateAsync('''
  new Promise((resolve) => setTimeout(() => resolve('done'), 100));
''');
runtime.executePendingJob();
final resolved = await runtime.handlePromise(pending);
print(resolved.stringResult); // "done" (JSON-encoded)
```

### Messages from JavaScript to Dart

```dart
runtime.onMessage('greeting', (dynamic args) {
  print('JavaScript says: $args');
});

runtime.evaluate("sendMessage('greeting', JSON.stringify({name: 'Flutter'}));");
```

### fetch and XMLHttpRequest

`getJavascriptRuntime()` enables `fetch` and `XMLHttpRequest` by default
(`xhr: true`), loading the polyfill in the background. Do not `dispose()` such
a runtime immediately after creating it; if you need `fetch` right away,
create the runtime with `xhr: false` and await `enableFetch()`:

```dart
import 'package:flutter_js_runtime/extensions/fetch.dart';

final runtime = getJavascriptRuntime(xhr: false);
await runtime.enableFetch();
```

### Cleanup

```dart
runtime.dispose();
```

Do not use a runtime after disposing it.

## Migrating from flutter_js

1. Replace the dependency in `pubspec.yaml`:

   ```yaml
   dependencies:
     flutter_js_runtime: ^0.9.0   # was: flutter_js
   ```

2. Replace the imports:

   ```dart
   // before
   import 'package:flutter_js/flutter_js.dart';
   // after
   import 'package:flutter_js_runtime/flutter_js.dart';
   // or
   import 'package:flutter_js_runtime/flutter_js_runtime.dart';
   ```

Class and function names are unchanged.

## Platform notes

- **`JsEvalResult.rawResult` depends on the engine.** QuickJS returns a Dart
  value, while JavaScriptCore returns a native `JSValueRef` pointer. Use
  `stringResult`, or `runtime.convertValue<T>(result)`, when the code has to
  run on every platform.
- **iOS uses JavaScriptCore** so apps follow App Store Review Guideline 4.7,
  which requires third-party code to run through WebKit or JavaScriptCore.

## License

MIT. See [LICENSE](LICENSE). Third-party notices are listed in
[NOTICE.md](NOTICE.md).
