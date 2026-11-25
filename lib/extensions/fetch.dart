import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_js_runtime/javascript_runtime.dart';
import 'package:flutter_js_runtime/src/runtime_lifecycle.dart';
import './xhr.dart';

var _fetchDebug = false;

setFetchDebug(bool value) => _fetchDebug = value;

extension JavascriptRuntimeFetchExtension on JavascriptRuntime {
  Future<JavascriptRuntime> enableFetch() async {
    debug('Before enable xhr');
    enableXhr();
    debug('After enable xhr');
    final fetchPolyfill =
        await rootBundle.loadString('packages/flutter_js_runtime/assets/js/fetch.js');
    debug('Loaded fetchPolyfill');
    // The runtime may have been disposed while the asset was loading.
    if (isRuntimeDisposed(this)) return this;
    final evalFetchResult = evaluate(fetchPolyfill);
    debug('Eval Fetch Result: $evalFetchResult');
    return this;
  }
}

void debug(String message) {
  if (_fetchDebug) {
    print('JavascriptRuntimeFetchExtension: $message');
  }
}
