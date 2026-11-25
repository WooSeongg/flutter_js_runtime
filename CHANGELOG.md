# Unreleased

- `fetch` / `XMLHttpRequest`: the response body is now passed to JavaScript as data. Before, it was pasted into evaluated source code, so bodies containing `` ` ``, `\` or `${...}` broke the request (it never settled) or ran as JavaScript, and `json()` returned a string for JSON with escaped characters (#135, #80 in flutter_js). The body is also no longer re-serialized when it is JSON.
- `fetch` / `XMLHttpRequest`: report the real HTTP status and status text instead of always `200 OK` (#175 in flutter_js).
- `fetch` / `XMLHttpRequest`: network failures now fire `onerror` (status `0`) and reject the `fetch` promise with a `TypeError` instead of never settling, so `handlePromise` also fails instead of waiting forever. Response bodies that are not valid UTF-8 no longer hang the request (invalid bytes become U+FFFD) (#137 in flutter_js).
- Android, Windows, Linux (QuickJS): `evaluate` now sets `isPromise` for promise results (#155 in flutter_js), uses `sourceUrl` as the file name in error stacks (#146 in flutter_js), and `convertValue` returns the evaluated value instead of always `true`, with the same shapes as on JavaScriptCore (whole numbers as `int`, objects as `Map<String, dynamic>`, `null` for a number that does not fit `T`) (#101 in flutter_js).

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
