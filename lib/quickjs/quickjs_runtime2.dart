/* START PARTS IMPORT QJS ENGINE */
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_js_runtime/flutter_js.dart';

import 'ffi.dart';

export 'ffi.dart' show JSEvalFlag, JSRef;

part './isolate.dart';
part './object.dart';
part './wrapper.dart';

/// Handler function to manage js module.
typedef _JsModuleHandler = String Function(String name);

/// Handler to manage unhandled promise rejection.
typedef _JsHostPromiseRejectionHandler = void Function(dynamic reason);

/// Quickjs engine for flutter.
class QuickJsRuntime2 extends JavascriptRuntime {
  Pointer<JSRuntime>? _rt;
  Pointer<JSContext>? _ctx;

  /// Max stack size for quickjs.
  int stackSize;

  /// Max stack size for quickjs.
  final int? timeout;

  /// Max memory for quickjs.
  final int? memoryLimit;

  /// Message Port for event loop. Close it to stop dispatching event loop.
  ReceivePort port = _TickPort();

  /// Handler function to manage js module.
  final _JsModuleHandler? moduleHandler;

  /// Handler function to manage js module.
  final _JsHostPromiseRejectionHandler? hostPromiseRejectionHandler;

  QuickJsRuntime2({
    this.moduleHandler,
    this.stackSize = 1024 * 1024,
    this.timeout,
    this.memoryLimit,
    this.hostPromiseRejectionHandler,
  }) {
    this.init();
  }

  _ensureEngine() {
    if (_rt != null) return;
    final rt = jsNewRuntime((ctx, type, ptr) {
      try {
        switch (type) {
          case JSChannelType.METHON:
            final pdata = ptr.cast<Pointer<JSValue>>();
            final argc = pdata[1].cast<Int32>().value;
            final pargs = [];
            for (var i = 0; i < argc; ++i) {
              pargs.add(_jsToDart(
                ctx,
                Pointer.fromAddress(
                  pdata[2].address + sizeOfJSValue * i,
                ),
              ));
            }
            final JSInvokable func = _jsToDart(
              ctx,
              pdata[3],
            );
            return _dartToJs(
                ctx,
                func.invoke(
                  pargs,
                  _jsToDart(ctx, pdata[0]),
                ));
          case JSChannelType.MODULE:
            if (moduleHandler == null) throw JSError('No ModuleHandler');
            final ret = moduleHandler!(
              ptr.cast<Utf8>().toDartString(),
            ).toNativeUtf8();
            Future.microtask(() {
              malloc.free(ret);
            });
            return ret.cast();
          case JSChannelType.PROMISE_TRACK:
            final err = _parseJSException(ctx, ptr);
            if (hostPromiseRejectionHandler != null) {
              hostPromiseRejectionHandler!(err);
            } else {
              print('unhandled promise rejection: $err');
            }
            return nullptr;
          case JSChannelType.FREE_OBJECT:
            final rt = ctx.cast<JSRuntime>();
            _DartObject.fromAddress(rt, ptr.address)?.free();
            return nullptr;
        }
        throw JSError('call channel with wrong type');
      } catch (e) {
        if (type == JSChannelType.FREE_OBJECT) {
          print('DartObject release error: $e');
          return nullptr;
        }
        if (type == JSChannelType.MODULE) {
          print('host Promise Rejection Handler error: $e');
          return nullptr;
        }
        final throwObj = _dartToJs(ctx, e);
        final err = jsThrow(ctx, throwObj);
        jsFreeValue(ctx, throwObj);
        if (type == JSChannelType.MODULE) {
          jsFreeValue(ctx, err);
          return nullptr;
        }
        return err;
      }
    }, timeout ?? 0, port);
    final stackSize = this.stackSize;
    if (stackSize > 0) jsSetMaxStackSize(rt, stackSize);
    final memoryLimit = this.memoryLimit ?? 0;
    if (memoryLimit > 0) jsSetMemoryLimit(rt, memoryLimit);
    _rt = rt;
    _ctx = jsNewContext(rt);
  }

  /// Free Runtime and Context which can be recreate when evaluate again.
  close() {
    final rt = _rt;
    final ctx = _ctx;
    _rt = null;
    _ctx = null;
    if (ctx != null) jsFreeContext(ctx);
    if (rt == null) return;
    _executePendingJob();
    try {
      for (final obj in localContext.values) {
        JSRef.freeRecursive(obj);
      }
      jsFreeRuntime(rt);
    } on String catch (e) {
      throw JSError(e);
    }
  }

  void _executePendingJob() {
    final rt = _rt;
    final ctx = _ctx;
    if (rt == null || ctx == null) return;
    while (true) {
      int err = jsExecutePendingJob(rt);
      if (err <= 0) {
        if (err < 0) print(_parseJSException(ctx));
        break;
      }
    }
  }

  /// Dispatch JavaScript Event loop.
  Future<void> dispatch() async {
    //await for (final _ in port) {
    _executePendingJob();
    //}
  }

  @override
  void setInspectable(bool inspectable) {
    // Nothing to do.
  }

  /// Evaluate js script.
  JsEvalResult evaluate(
    String command, {
    String? name,
    int? evalFlags,
    String? sourceUrl,
  }) {
    _ensureEngine();
    final ctx = _ctx!;
    final jsval = jsEval(
      ctx,
      command,
      name ?? sourceUrl ?? '<eval>',
      evalFlags ?? JSEvalFlag.GLOBAL,
    );

    if (jsIsException(jsval) != 0) {
      jsFreeValue(ctx, jsval);
      JSError exception = _parseJSException(ctx);
      return JsEvalResult(exception.toString(), exception, isError: true);
    }
    final result = _jsToDart(ctx, jsval);
    jsFreeValue(ctx, jsval);
    return JsEvalResult(result?.toString() ?? "null", result,
        isPromise: result is Future);
  }

  @override
  JsEvalResult callFunction(Pointer<NativeType> fn, Pointer<NativeType> obj) {
    throw UnimplementedError();
  }

  @override
  T? convertValue<T>(JsEvalResult jsValue) {
    // rawResult is already a Dart value. Shape it like
    // JavascriptCoreRuntime.convertValue: whole numbers as int, objects and
    // arrays JSON-decoded (Map<String, dynamic> / List<dynamic>), and null
    // when a number does not fit T.
    Object? value = jsValue.rawResult;
    // (Outside the int64 range toInt() would clamp, so those stay double.)
    if (value is double &&
        value > -9223372036854775808.0 &&
        value < 9223372036854775808.0 &&
        value == value.truncateToDouble()) {
      value = value.toInt();
    } else if (value is Map || value is List) {
      try {
        value = jsonDecode(jsonEncode(value, toEncodable: (_) => null));
      } on Error catch (_) {
        // Not JSON-encodable (e.g. NaN inside); keep the raw value.
      }
    }
    if (value is num) {
      try {
        return value as T;
      } on TypeError {
        return null;
      }
    }
    return value as T?;
  }

  @override
  void dispose() {
    try {
      port.close(); // stop dispatch loop
      close(); // close engine
    } on JSError catch (e) {
      print(e); // catch reference leak exception
    }
  }

  @override
  Future<JsEvalResult> evaluateAsync(String code, {String? sourceUrl}) {
    return Future.value(evaluate(code, sourceUrl: sourceUrl));
  }

  @override
  int executePendingJob() {
    this.dispatch();
    return 0;
  }

  @override
  String getEngineInstanceId() {
    return this.hashCode.toString();
  }

  @override
  void initChannelFunctions() {
    JavascriptRuntime.channelFunctionsRegistered[getEngineInstanceId()] = {};
    final setToGlobalObject =
        evaluate("(key, val) => { this[key] = val; }").rawResult;
    localContext['setToGlobalObject'] = setToGlobalObject;
    (setToGlobalObject as JSInvokable).invoke([
      'sendMessage',
      (String channelName, String message) {
        final channelFunctions = JavascriptRuntime
            .channelFunctionsRegistered[getEngineInstanceId()]!;

        if (channelFunctions.containsKey(channelName)) {
          return channelFunctions[channelName]!.call(jsonDecode(message));
        } else {
          print('No channel $channelName registered');
        }
        if (JavascriptRuntime.debugEnabled) {
          print('CHANNEL: $channelName - Message: $message');
        }
      }
    ]);
  }

  @override
  String jsonStringify(JsEvalResult jsValue) {
    throw UnimplementedError();
  }

  @override
  bool setupBridge(String channelName, void Function(dynamic args) fn) {
    final channelFunctionCallbacks =
        JavascriptRuntime.channelFunctionsRegistered[getEngineInstanceId()]!;

    if (channelFunctionCallbacks.keys.contains(channelName)) return false;

    channelFunctionCallbacks[channelName] = fn;

    return true;
  }
}

/// The [QuickJsRuntime2.port]. Every evaluate and function call posts a tick
/// to it. A plain [ReceivePort] buffers messages until somebody listens, and
/// nothing in this package does, so the ticks piled up forever. This port
/// delivers ticks while it has a listener and drops them otherwise.
class _TickPort extends Stream<dynamic> implements ReceivePort {
  final RawReceivePort _port = RawReceivePort();
  final StreamController<dynamic> _ticks = StreamController<dynamic>();

  _TickPort() {
    _port.handler = (dynamic message) {
      if (_ticks.hasListener) _ticks.add(message);
    };
  }

  @override
  SendPort get sendPort => _port.sendPort;

  @override
  StreamSubscription<dynamic> listen(
    void Function(dynamic message)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      _ticks.stream.listen(onData,
          onError: onError, onDone: onDone, cancelOnError: cancelOnError);

  @override
  void close() {
    _port.close();
    _ticks.close();
  }
}
