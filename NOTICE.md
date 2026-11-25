# Notices

flutter_js_runtime is a fork of [flutter_js](https://github.com/abner/flutter_js)
by Ábner Oliveira (forked from version 0.8.7), licensed under the MIT License.

The full text of every license listed below is in [LICENSE](LICENSE).

## Third-party components

| Component | Copyright | License | Used in |
|---|---|---|---|
| [flutter_js](https://github.com/abner/flutter_js) | (c) 2019 Ábner Oliveira | MIT | Entire code base (original project) |
| [QuickJS](https://bellard.org/quickjs/) | (c) 2017-2021 Fabrice Bellard, Charlie Gordon | MIT | JavaScript engine on Android, Linux and Windows |
| [flutter_qjs](https://github.com/ekibun/flutter_qjs) | (c) 2019 https://github.com/czy0729 | MIT | Dart FFI bridge to QuickJS (`lib/quickjs/`) |
| [flutter_jscore](https://github.com/xuelongqy/flutter_jscore) | (c) 2020 xuelongqy | MIT | Dart FFI bindings to JavaScriptCore (`lib/javascriptcore/`) |
| [android-js-runtimes](https://github.com/fast-development/android-js-runtimes) | (c) 2020 fast-development | MIT | Android QuickJS runtime (`fastdev-jsruntimes-quickjs`) |
| [unfetch](https://github.com/developit/unfetch) | (c) 2017 Jason Miller | MIT | `fetch` polyfill (`assets/js/fetch.js`) |

## Notes

- **JavaScriptCore** (iOS, macOS) is the system framework that the operating
  system provides. It is linked at runtime and is not redistributed with this
  package.
- **Desktop QuickJS binaries** (`linux/shared/libquickjs_c_bridge_plugin.so`,
  `windows/shared/quickjs_c_bridge.dll`) were built by Ábner Oliveira from
  [quickjs-c-bridge](https://github.com/abner/quickjs-c-bridge) and shipped as
  part of flutter_js under the MIT License. They contain QuickJS (see above).
  The quickjs-c-bridge repository itself has no license file, so its source
  code is not copied into this project.
- **Modified sources.** The code taken from flutter_qjs, flutter_jscore and
  unfetch was changed in flutter_js and again in this project (bug fixes; see
  [CHANGELOG.md](CHANGELOG.md)). In `assets/js/fetch.js`, flutter_js made
  `json()` return the text when it is not valid JSON and accept request
  headers given as an iterable; this project makes a network failure reject
  with a `TypeError`.
