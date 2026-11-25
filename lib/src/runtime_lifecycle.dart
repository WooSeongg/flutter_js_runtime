// Internal to this package: not part of the public API.
//
// Tracks, for each JavascriptRuntime, whether it was disposed, the timers it
// owns and its channel handlers. Kept outside the JavascriptRuntime class so
// the class gains no public members.
import 'dart:async';

import '../javascript_runtime.dart';

class _RuntimeState {
  bool disposed = false;
  final Map<Object, Timer> timers = {};
  final Map<String, dynamic Function(dynamic arg)> channels = {};
}

final Expando<_RuntimeState> _states = Expando('JavascriptRuntime state');

_RuntimeState _stateOf(JavascriptRuntime runtime) =>
    _states[runtime] ??= _RuntimeState();

/// Whether [markRuntimeDisposed] was called for [runtime].
bool isRuntimeDisposed(JavascriptRuntime runtime) =>
    _states[runtime]?.disposed ?? false;

/// The channel handlers of [runtime]. A runtime looks its handlers up here,
/// not through `JavascriptRuntime.channelFunctionsRegistered`, whose keys
/// (engine instance ids) are hash codes and can collide.
Map<String, dynamic Function(dynamic arg)> runtimeChannels(
        JavascriptRuntime runtime) =>
    _stateOf(runtime).channels;

/// Makes [runtime] own [timer]: [markRuntimeDisposed] cancels it. With a
/// [key], [releaseRuntimeTimer] forgets it again.
Timer ownRuntimeTimer(JavascriptRuntime runtime, Timer timer, {Object? key}) {
  final state = _stateOf(runtime);
  if (state.disposed) {
    timer.cancel();
    return timer;
  }
  if (key == null) {
    // Keyless timers (the polls) are few and never released one by one, so
    // finished ones are swept here. Keyed timers are released when they
    // fire; sweeping on each of them would make setTimeout quadratic.
    state.timers.removeWhere((_, owned) => !owned.isActive);
  }
  state.timers[key ?? timer] = timer;
  return timer;
}

/// Forgets the timer registered under [key], without cancelling it.
void releaseRuntimeTimer(JavascriptRuntime runtime, Object key) {
  _states[runtime]?.timers.remove(key);
}

/// Marks [runtime] as disposed: cancels its timers and removes its entry
/// from `JavascriptRuntime.channelFunctionsRegistered`. Returns false when
/// it was already marked.
bool markRuntimeDisposed(JavascriptRuntime runtime) {
  final state = _stateOf(runtime);
  if (state.disposed) return false;
  state.disposed = true;
  for (final timer in state.timers.values.toList()) {
    timer.cancel();
  }
  state.timers.clear();
  final id = runtime.getEngineInstanceId();
  final registry = JavascriptRuntime.channelFunctionsRegistered;
  // Only this runtime's own entry: another runtime may share the id.
  if (identical(registry[id], state.channels)) registry.remove(id);
  return true;
}

/// Throws when [runtime] was disposed.
void checkRuntimeNotDisposed(JavascriptRuntime runtime) {
  if (isRuntimeDisposed(runtime)) {
    throw StateError('JavascriptRuntime used after dispose()');
  }
}
