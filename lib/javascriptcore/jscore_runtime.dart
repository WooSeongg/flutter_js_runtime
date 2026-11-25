import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_js_runtime/javascript_runtime.dart';
import 'package:flutter_js_runtime/javascriptcore/binding/js_object_ref.dart'
    as jsObject;
import 'package:flutter_js_runtime/javascriptcore/flutter_jscore.dart';
import 'package:flutter_js_runtime/javascriptcore/jscore_bindings.dart';
import 'package:flutter_js_runtime/js_eval_result.dart';
import 'package:flutter_js_runtime/src/runtime_lifecycle.dart';

class JavascriptCoreRuntime extends JavascriptRuntime {
  late Pointer _contextGroup;
  late Pointer _globalContext;
  late JSContext context;
  late Pointer _globalObject;

  int executePendingJob() {
    if (isRuntimeDisposed(this)) return 0;
    evaluate('(function(){})();');
    return 0;
  }

  String? onMessageFunctionName;
  String? sendMessageFunctionName;

  JavascriptCoreRuntime() {
    _contextGroup = jSContextGroupCreate();
    _globalContext = jSGlobalContextCreateInGroup(_contextGroup, nullptr);
    _globalObject = jSContextGetGlobalObject(_globalContext);

    context = _RuntimeJSContext(this, _globalContext);

    // The native callback is one static function for every runtime; this is
    // how it finds the runtime a call belongs to.
    _instances[_globalContext.address] = this;

    Pointer<Utf8> funcNameCString = 'sendMessage'.toNativeUtf8();
    final funcNameJsString = jSStringCreateWithUTF8CString(funcNameCString);
    var functionObject = jSObjectMakeFunctionWithCallback(
        _globalContext,
        funcNameJsString,
        Pointer.fromFunction(sendMessageBridgeFunction));
    jSObjectSetProperty(
        _globalContext,
        _globalObject,
        funcNameJsString,
        functionObject,
        jsObject.JSPropertyAttributes.kJSPropertyAttributeNone,
        nullptr);
    jSStringRelease(funcNameJsString);
    calloc.free(funcNameCString);

    init();
  }

  @override
  void initChannelFunctions() {
    JavascriptRuntime.channelFunctionsRegistered[getEngineInstanceId()] =
        runtimeChannels(this);
  }

  @override
  JsEvalResult evaluate(String js, {String? sourceUrl}) {
    checkRuntimeNotDisposed(this);
    Pointer<Utf8> scriptCString = js.toNativeUtf8();
    Pointer<Utf8>? sourceUrlCString = sourceUrl?.toNativeUtf8();

    JSValuePointer exception = JSValuePointer();
    // The JSStrings are copies owned by this call: release them once the
    // script has run, or every evaluate leaks a copy of its source.
    final scriptJsString = jSStringCreateWithUTF8CString(scriptCString);
    final Pointer sourceUrlJsString = sourceUrlCString != null
        ? jSStringCreateWithUTF8CString(sourceUrlCString)
        : nullptr;
    var jsValueRef = jSEvaluateScript(
        _globalContext,
        scriptJsString,
        nullptr,
        sourceUrlJsString,
        1,
        exception.pointer);
    jSStringRelease(scriptJsString);
    if (sourceUrlJsString != nullptr) jSStringRelease(sourceUrlJsString);
    calloc.free(scriptCString);
    if (sourceUrlCString != null) {
        calloc.free(sourceUrlCString as Pointer<NativeType>);
    }

    String result;

    JSValue exceptionValue = exception.getValue(context);
    malloc.free(exception.pointer);
    bool isPromise = false;
    if (exceptionValue.isObject) {
      result =
          'ERROR: ${exceptionValue.toObject().getProperty("message").string} \n  at ${exceptionValue.toObject().getProperty("stack").string}';
    } else {
      result = _getJsValue(jsValueRef);
      JSValue resultValue = JSValue(context, jsValueRef);

      isPromise = resultValue.isObject &&
          resultValue.toObject().getProperty('then').isObject &&
          resultValue.toObject().getProperty('catch').isObject;
    }

    return JsEvalResult(
      result,
      exceptionValue.isObject ? exceptionValue.toObject().pointer : jsValueRef,
      isError: result.startsWith('ERROR:'),
      isPromise: isPromise,
    );
  }

  @override
  void dispose() {
    if (!markRuntimeDisposed(this)) return;
    _instances.remove(_globalContext.address);
    // When a channel handler disposes the runtime, JavaScript of this
    // context is still running: release it once the stack has unwound.
    if (_callbackDepth > 0) {
      scheduleMicrotask(_release);
    } else {
      _release();
    }
  }

  /// How many native sendMessage callbacks of this runtime are running.
  int _callbackDepth = 0;
  bool _released = false;

  void _release() {
    if (_released) return;
    _released = true;
    jSGlobalContextRelease(_globalContext);
    jSContextGroupRelease(_contextGroup);
  }

  @override
  String getEngineInstanceId() => hashCode.abs().toString();

  /// Works only for iOS & MacOS.
  @override
  void setInspectable(bool inspectable) {
    checkRuntimeNotDisposed(this);
    if (Platform.isIOS || Platform.isMacOS) {
      try {
        context.setInspectable(inspectable);
      } on Error {
        print('Could not set inspectable to $inspectable');
      }
    }
  }

  @override
  bool setupBridge(String channelName, Function(dynamic args) fn) {
    final channelFunctionCallbacks = runtimeChannels(this);

    if (channelFunctionCallbacks.keys.contains(channelName)) return false;

    channelFunctionCallbacks[channelName] = fn;

    return true;
  }

  static Pointer sendMessageBridgeFunction(
      Pointer ctx,
      Pointer function,
      Pointer thisObject,
      int argumentCount,
      Pointer<Pointer> arguments,
      Pointer<Pointer> exception) {
    final runtime = _instances[ctx.address] ??
        _instances[jSContextGetGlobalContext(ctx).address];
    // A call from a disposed (or unknown) runtime is dropped.
    if (runtime == null || isRuntimeDisposed(runtime)) return nullptr;
    runtime._callbackDepth++;
    try {
      return runtime._sendMessage(
          ctx, function, thisObject, argumentCount, arguments, exception);
    } finally {
      runtime._callbackDepth--;
    }
  }

  String _getJsValue(Pointer jsValueRef) {
    if (jSValueIsNull(_globalContext, jsValueRef) == 1) {
      return 'null';
    } else if (jSValueIsUndefined(_globalContext, jsValueRef) == 1) {
      return 'undefined';
    }
    var resultJsString =
        jSValueToStringCopy(_globalContext, jsValueRef, nullptr);
    var resultCString = jSStringGetCharactersPtr(resultJsString);
    int resultCStringLength = jSStringGetLength(resultJsString);
    if (resultCString == nullptr) {
      return 'null';
    }
    String result = String.fromCharCodes(Uint16List.view(
        resultCString.cast<Uint16>().asTypedList(resultCStringLength).buffer,
        0,
        resultCStringLength));
    jSStringRelease(resultJsString);
    return result;
  }

  /// Live runtimes by the address of their global context.
  static final Map<int, JavascriptCoreRuntime> _instances = {};

  Pointer _sendMessage(
      Pointer ctx,
      Pointer function,
      Pointer thisObject,
      int argumentCount,
      Pointer<Pointer> arguments,
      Pointer<Pointer> exception) {
    if (argumentCount < 2) {
      // Reading a missing argument would run past the end of the array
      // JavaScriptCore passes and crash the process.
      _throwJsError(ctx, exception,
          'sendMessage requires 2 arguments: (channelName, message)');
      return nullptr;
    }
    final channelFunctions = runtimeChannels(this);

    String channelName = _getJsValue(arguments[0]);
    String message = _getJsValue(arguments[1]);

    if (channelFunctions.containsKey(channelName)) {
      final result = channelFunctions[channelName]!.call(jsonDecode(message));
      // The handler may have disposed this runtime.
      if (isRuntimeDisposed(this)) return nullptr;
      try {
        if (result is Future) {
          return _constructPromiseFor(result);
        }
        final encoded = json.encode(result);
        return JSValue.makeFromJSONString(context, encoded).pointer;
      } catch (err) {
        print(
            'Could not encode return value of message on channel $channelName to json... returning null');
      }
    } else {
      print('No channel $channelName registered');
    }

    return nullptr;
  }

  /// Makes the JavaScript call that is running the native callback throw an
  /// Error with [message].
  void _throwJsError(Pointer ctx, Pointer<Pointer> exception, String message) {
    if (exception == nullptr) return;
    final messageCString = message.toNativeUtf8();
    final messageJsString = jSStringCreateWithUTF8CString(messageCString);
    final arguments = JSValuePointer(jSValueMakeString(ctx, messageJsString));
    exception.value =
        jsObject.jSObjectMakeError(ctx, 1, arguments.pointer, nullptr);
    malloc.free(arguments.pointer);
    jSStringRelease(messageJsString);
    calloc.free(messageCString);
  }

  Pointer<NativeType> _constructPromiseFor(Future future) {
    final id = future.hashCode;
    Pointer<Utf8> scriptCString = ('var __JSC_promise_result$id = {};' +
            'new Promise(function(resolve, reject) { __JSC_promise_result$id.resolve = resolve;' +
            ' __JSC_promise_result$id.reject = reject;});')
        .toNativeUtf8();

    final scriptJsString = jSStringCreateWithUTF8CString(scriptCString);
    var jsValueRef = jSEvaluateScript(
        _globalContext, scriptJsString, nullptr, nullptr, 1, nullptr);
    jSStringRelease(scriptJsString);
    calloc.free(scriptCString);

    future.then((value) {
      if (isRuntimeDisposed(this)) return;
      final encoded = json.encode(value);
      evaluate(
          '__JSC_promise_result$id.resolve($encoded); __JSC_promise_result$id = null;');
    }).catchError((error) {
      if (isRuntimeDisposed(this)) return;
      evaluate(
          '__JSC_promise_result$id.reject(${json.encode(error.toString())}); __JSC_promise_result$id = null;');
    });
    return jsValueRef;
  }

  @override
  JsEvalResult callFunction(Pointer<NativeType>? fn, Pointer<NativeType>? obj) {
    checkRuntimeNotDisposed(this);
    JSValue fnValue = JSValue(context, fn ?? nullptr);
    JSObject functionObj = fnValue.toObject();
    JSValuePointer exception = JSValuePointer();
    final arguments = JSValuePointer(obj);
    JSValue result = functionObj.callAsFunction(
      functionObj,
      arguments,
      exception: exception,
    );
    JSValue exceptionValue = exception.getValue(context);
    // Both are single-slot native buffers only needed for the call.
    malloc.free(arguments.pointer);
    malloc.free(exception.pointer);
    bool isPromise = false;

    if (exceptionValue.isObject) {
      throw Exception(
          'ERROR: ${exceptionValue.toObject().getProperty("message").string}');
    } else {
      isPromise = result.isObject &&
          result.toObject().getProperty('then').isObject &&
          result.toObject().getProperty('catch').isObject;
    }

    return JsEvalResult(
      _getJsValue(result.pointer),
      exceptionValue.isObject
          ? exceptionValue.toObject().pointer
          : result.pointer,
      isPromise: isPromise,
    );
  }

  @override
  T? convertValue<T>(JsEvalResult jsValue) {
    checkRuntimeNotDisposed(this);
    if (jSValueIsNull(_globalContext, jsValue.rawResult) == 1) {
      return null;
    } else if (jSValueIsString(_globalContext, jsValue.rawResult) == 1) {
      return _getJsValue(jsValue.rawResult) as T;
    } else if (jSValueIsBoolean(_globalContext, jsValue.rawResult) == 1) {
      return (_getJsValue(jsValue.rawResult) == "true") as T;
    } else if (jSValueIsNumber(_globalContext, jsValue.rawResult) == 1) {
      String valueString = _getJsValue(jsValue.rawResult);
      // Whole numbers become int; everything else (fractions, exponent
      // notation, NaN, Infinity) becomes double.
      final Object? number =
          int.tryParse(valueString) ?? double.tryParse(valueString);
      if (number == null) return null;
      try {
        return number as T;
      } on TypeError {
        print('Failed to cast $valueString... returning null');
        return null;
      }
    } else if (jSValueIsObject(_globalContext, jsValue.rawResult) == 1 ||
        jSValueIsArray(_globalContext, jsValue.rawResult) == 1) {
      JSValue objValue = JSValue(context, jsValue.rawResult);
      String serialized = objValue.createJSONString().string!;
      return jsonDecode(serialized);
    } else {
      return null;
    }
  }

  @override
  String jsonStringify(JsEvalResult jsValue) {
    checkRuntimeNotDisposed(this);
    JSValue objValue = JSValue(context, jsValue.rawResult);
    return objValue.createJSONString().string!;
  }

  @override
  Future<JsEvalResult> evaluateAsync(String code, {String? sourceUrl}) {
    return Future.value(evaluate(code, sourceUrl: sourceUrl));
  }
}

/// The [JavascriptCoreRuntime.context]: refuses to hand out the context
/// pointer once the runtime has released it.
class _RuntimeJSContext extends JSContext {
  final JavascriptCoreRuntime _runtime;

  _RuntimeJSContext(this._runtime, Pointer pointer) : super(pointer);

  @override
  Pointer get pointer {
    if (_runtime._released) {
      throw StateError('JavascriptRuntime used after dispose()');
    }
    return super.pointer;
  }

  @override
  void setInspectable(bool inspectable) {
    pointer; // throws once released
    super.setInspectable(inspectable);
  }
}
