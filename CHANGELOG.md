# 1.0.2

Bug fixes; no API changes. Issue numbers refer to flutter_js.

**Android, Windows, Linux (QuickJS)**

- Promise callbacks run on their own, as on iOS and macOS (#112, #100). Before, `.then` callbacks, code after `await` (for example after a `setTimeout`) and `await` on the result of an async `onMessage` handler only ran while `handlePromise` was waiting or after calling `executePendingJob()`. They run right after the current Dart event, not inside `evaluate`. Calling `executePendingJob()` still works.

**iOS, macOS (JavaScriptCore)**

- Fixed memory leaks in `evaluate` calls that return an object or throw an error, and in `sendMessage` calls whose `onMessage` handler returns a value (#168).

**Documentation and cleanup**

- README: added a FAQ on calling functions with arguments (#103), loading several files or a bundled library (#115, #131, #142, #148) and resetting a runtime (#91), and a note on the Flutter 3.44–3.46 `android.builtInKotlin=true` build limitation.
- Android: removed an unused duplicate plugin class.
- iOS: removed a compiler warning.

# 1.0.1

Bug fixes only; no API changes. Issue numbers refer to flutter_js.

**fetch / XMLHttpRequest**

- Response bodies are passed as data. Bodies containing `` ` ``, `\` or `${...}` broke the request or ran as JavaScript (#135, #80).
- The real HTTP status is reported instead of always `200 OK` (#175), and response headers are available (`getResponseHeader()` returns `null` for a missing header).
- Network failures reject with a `TypeError` and non-UTF-8 bodies no longer hang the request (#137).
- `POST`/`PUT`/`PATCH` without a body no longer send `null`. Other methods (`OPTIONS`, ...) and non-string header values or bodies are sent instead of hanging. Binary bodies are not supported and fail with `onerror`.

**Runtime**

- `dispose()` cancels the runtime's timers and frees it; before, they kept running and leaked the runtime (#168, #37). It is safe to call twice, right after creation, and inside an `onMessage` handler. Work still pending is dropped.
- Fixed memory leaks in `evaluate` (#168): on Android, Windows and Linux for every call, and on iOS and macOS for calls that return a number or a string.
- `setTimeout` works with delays such as `10.5` or `"10"` (#62).
- `handlePromise` no longer overwrites a global named `idx`.

**iOS, macOS (JavaScriptCore)**

- Fixed crashes: `sendMessage` called with fewer than two arguments, and using a runtime after `dispose()` (now a `StateError`).
- With several runtimes, each one receives its own messages (`console.log`, `setTimeout`, `fetch`).
- A failing async `onMessage` handler rejects the JavaScript promise. `convertValue` handles `NaN`, `Infinity` and exponent notation.

**Android, Windows, Linux (QuickJS)**

- `evaluate` sets `isPromise` (#155) and uses `sourceUrl` in error stacks (#146). `convertValue` returns the value instead of `true` (#101).

# 1.0.0

- Added Swift Package Manager support on iOS and macOS. CocoaPods keeps working.
- Android: migrated the plugin to built-in Kotlin (Android Gradle Plugin 9). Fixes the build failure and the "plugins that apply Kotlin Gradle Plugin" warning in apps created with current Flutter versions.
- Requires Flutter 3.44 / Dart 3.12 or newer. Use 0.9.x on older Flutter versions.
- Minimum deployment targets raised to iOS 13.0 and macOS 10.15 (the minimums of Flutter 3.44).
- iOS: the plugin is now Swift-only. The Objective-C wrapper and the `SwiftFlutterJsRuntimePlugin` class were removed; the plugin class is `FlutterJsRuntimePlugin`.
- Example app updated to the current Flutter Android and Xcode project setup, with an integration test.

# 0.9.1

- Replaced deprecated `Pointer.elementAt`. Requires Dart 3.3 / Flutter 3.19+.

# 0.9.0

First release as `flutter_js_runtime`, based on flutter_js 0.8.7.

- Renamed package. Change the dependency and imports to `package:flutter_js_runtime/`; the API is the same.
- New import `package:flutter_js_runtime/flutter_js_runtime.dart` (`flutter_js.dart` still works).
- Renamed method channel and plugin class to avoid clashes with flutter_js.
- Fixed `enableFetch()` asset path.

For earlier versions, see the [flutter_js changelog](https://github.com/abner/flutter_js/blob/master/CHANGELOG.md).
