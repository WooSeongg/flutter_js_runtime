# flutter_js_runtime example

A small Flutter app showing how to use `flutter_js_runtime`.

```bash
cd example
flutter run
```

On iOS and macOS the example uses Swift Package Manager. Flutter adds the
plugin as a local Swift package named after the repository directory, so keep
the checkout in a directory named `flutter_js_runtime` (for example, rename
`flutter_js_runtime-main` after unpacking a GitHub ZIP). Otherwise the build
fails with "unable to override package 'flutter_js_runtime' because its
identity ... doesn't match".

What it demonstrates:

- Evaluating a JavaScript expression with `getJavascriptRuntime()` and `evaluateAsync`
- Validating a form with the [Ajv](https://ajv.js.org/) JSON schema validator running in JavaScript
- Calling `fetch` from JavaScript and reading the response in Dart
