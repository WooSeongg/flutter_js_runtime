# flutter_js_runtime example

A small Flutter app showing how to use `flutter_js_runtime`.

```bash
cd example
flutter run
```

What it demonstrates:

- Evaluating a JavaScript expression with `getJavascriptRuntime()` and `evaluateAsync`
- Validating a form with the [Ajv](https://ajv.js.org/) JSON schema validator running in JavaScript
- Calling `fetch` from JavaScript and reading the response in Dart
