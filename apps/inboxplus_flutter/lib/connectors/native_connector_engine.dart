import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'connector_engine.dart';

class NativeConnectorEngine implements ConnectorEngine {
  NativeConnectorEngine._(this._requestTimeout) {
    _subscription = _receive.listen(_onMessage);
  }

  final Duration _requestTimeout;
  final _receive = ReceivePort();
  final _workers = <String, Isolate>{};
  final _ready = <String, Completer<SendPort?>>{
    'requests': Completer<SendPort?>(),
    'events': Completer<SendPort?>(),
  };
  final _exited = <String, Completer<void>>{
    'requests': Completer<void>(),
    'events': Completer<void>(),
  };
  final _ports = <String, SendPort>{};
  final _events = StreamController<ConnectorEvent>.broadcast();
  final _pending = <int, Completer<Map<String, Object?>>>{};
  late final StreamSubscription<dynamic> _subscription;
  int _nextId = 0;
  bool _starting = true;
  bool _closed = false;
  bool _failed = false;
  Future<void> _requestTail = Future.value();
  Future<void>? _closing;

  static Future<NativeConnectorEngine> open() => _open(_libraryPath());

  @visibleForTesting
  static Future<NativeConnectorEngine> openForTesting({
    required String libraryPath,
    Duration startupTimeout = const Duration(seconds: 20),
    Duration requestTimeout = const Duration(minutes: 3),
  }) => _open(
    libraryPath,
    startupTimeout: startupTimeout,
    requestTimeout: requestTimeout,
  );

  static Future<NativeConnectorEngine> _open(
    String? path, {
    Duration startupTimeout = const Duration(seconds: 20),
    Duration requestTimeout = const Duration(minutes: 3),
  }) async {
    final startup = Stopwatch()..start();
    final engine = NativeConnectorEngine._(requestTimeout);
    try {
      for (final role in engine._ready.keys) {
        final worker = await Isolate.spawn(
          _run,
          (engine._receive.sendPort, path, role),
          paused: true,
          errorsAreFatal: true,
          onError: engine._receive.sendPort,
        );
        engine._workers[role] = worker;
        worker.addOnExitListener(
          engine._receive.sendPort,
          response: {'worker_exit': role},
        );
        worker.resume(worker.pauseCapability!);
      }
      final ports = await Future.wait(
        engine._ready.values.map((ready) => ready.future),
      ).timeout(startupTimeout - startup.elapsed);
      if (startup.elapsed >= startupTimeout ||
          ports.any((port) => port == null) ||
          engine._failed) {
        throw const ConnectorException('native_library_unavailable');
      }
      engine._ports.addAll(
        Map.fromIterables(engine._ready.keys, ports.cast<SendPort>()),
      );
      engine._starting = false;
      return engine;
    } catch (_) {
      engine._closed = true;
      for (final worker in engine._workers.values) {
        worker.kill(priority: Isolate.immediate);
      }
      await engine._subscription.cancel();
      engine._receive.close();
      await engine._events.close();
      throw const ConnectorException('native_library_unavailable');
    }
  }

  static String? _libraryPath() {
    if (Platform.isIOS) return null;
    if (!kReleaseMode) {
      final override = Platform.environment['INBOXPLUS_CONNECTORS_LIBRARY'];
      if (override != null && p.isAbsolute(override)) return override;
    }
    if (Platform.isAndroid) return 'libinboxplus_connectors.so';
    final executable = p.dirname(Platform.resolvedExecutable);
    if (Platform.isMacOS) {
      return p.normalize(
        p.join(executable, '../Frameworks/libinboxplus_connectors.dylib'),
      );
    }
    if (Platform.isWindows) {
      return p.join(executable, 'inboxplus_connectors.dll');
    }
    return p.join(executable, 'lib/libinboxplus_connectors.so');
  }

  @override
  Stream<ConnectorEvent> get events => _events.stream;

  @override
  Future<Map<String, Object?>> request(Map<String, Object?> command) {
    if (_closed || _closing != null || _failed) {
      return Future.error(const ConnectorException('engine_closed'));
    }
    if (command['op'] == 'cancel') return _dispatch(command, 'events');
    final result = Completer<Map<String, Object?>>();
    _requestTail = _requestTail.then((_) async {
      if (_closed || _closing != null || _failed) {
        result.completeError(const ConnectorException('engine_closed'));
        return;
      }
      final native = _dispatch(command, 'requests', timeout: false);
      unawaited(
        _withTimeout(native)
            .then(result.complete, onError: result.completeError),
      );
      try {
        await native;
      } on ConnectorException {
        // Keep the next request behind the native call even after a timeout.
      }
    });
    return result.future;
  }

  Future<Map<String, Object?>> _dispatch(
    Map<String, Object?> command,
    String role, {
    String? action,
    bool timeout = true,
  }) async {
    final port = _ports[role];
    if (port == null || _exited[role]!.isCompleted) {
      throw const ConnectorException('engine_closed');
    }
    final id = _nextId++;
    final response = Completer<Map<String, Object?>>();
    _pending[id] = response;
    port.send((id, command, action));
    return timeout ? _withTimeout(response.future) : response.future;
  }

  Future<Map<String, Object?>> _withTimeout(
    Future<Map<String, Object?>> response,
  ) async {
    try {
      return await response.timeout(_requestTimeout);
    } on TimeoutException {
      throw const ConnectorException('outcome_unknown');
    }
  }

  void _onMessage(dynamic message) {
    if (message is! Map) {
      _workerFailed();
      return;
    }
    final exited = _exited[message['worker_exit']];
    if (exited != null) {
      if (!exited.isCompleted) exited.complete();
      if (_closing == null) _workerFailed();
      return;
    }
    final ready = _ready[message['worker_ready']];
    if (ready != null) {
      if (!ready.isCompleted) {
        ready.complete(
          message['port'] is SendPort ? message['port'] as SendPort : null,
        );
      }
      return;
    }
    if (message['event'] is Map) {
      _events.add(Map<String, Object?>.from(message['event'] as Map));
      return;
    }
    final completion = _pending.remove(message['id']);
    if (completion == null) return;
    final response = message['response'];
    if (response is Map && response['ok'] == true) {
      final data = response['data'];
      completion.complete(
        data is Map ? Map<String, Object?>.from(data) : {'value': data},
      );
    } else {
      final error = response is Map ? response['error'] : null;
      final code = error is Map ? error['code'] : null;
      completion.completeError(
        ConnectorException(
          _errorCodes.contains(code) ? code as String : 'operation_failed',
        ),
      );
    }
  }

  void _workerFailed() {
    if (_closed || _failed) return;
    _failed = true;
    for (final ready in _ready.values) {
      if (!ready.isCompleted) ready.complete(null);
    }
    for (final completion in _pending.values) {
      completion.completeError(const ConnectorException('outcome_unknown'));
    }
    _pending.clear();
    _events.add({'type': 'error', 'code': 'native_engine_stopped'});
    if (!_starting && _closing == null) {
      unawaited(close().catchError((Object _) {}));
    }
  }

  @override
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    if (_closed) return;
    try {
      final role = _exited['events']!.isCompleted ? 'requests' : 'events';
      await _dispatch({'op': 'shutdown'}, role);
    } finally {
      // Drain before stopping: a timed-out native send may still be executing.
      await _requestTail;
      for (final role in _ports.keys) {
        if (!_exited[role]!.isCompleted) {
          try {
            await _dispatch({}, role, action: 'stop');
          } on ConnectorException {
            // The queued stop still runs after the native call returns.
          }
        }
      }
      _closed = true;
      for (final completion in _pending.values) {
        completion.completeError(const ConnectorException('outcome_unknown'));
      }
      _pending.clear();
      await _subscription.cancel();
      _receive.close();
      await _events.close();
    }
  }
}

const _errorCodes = {
  'invalid_request',
  'storage_failed',
  'initialization_failed',
  'account_not_initialized',
  'account_closed',
  'internal_error',
  'operation_failed',
  'request_cancelled',
  'native_protocol_error',
};

void _run((SendPort, String?, String) arguments) {
  final (results, path, role) = arguments;
  final _Bindings bindings;
  try {
    bindings = _Bindings(
      path == null ? DynamicLibrary.process() : DynamicLibrary.open(path),
    );
  } catch (_) {
    results.send({'worker_ready': role});
    return;
  }
  final commands = ReceivePort();
  results.send({'worker_ready': role, 'port': commands.sendPort});
  // Poll on a separate thread so QR codes and receipts arrive during requests.
  final timer = role == 'events'
      ? Timer.periodic(const Duration(milliseconds: 100), (_) {
          try {
            for (var count = 0; count < 100; count++) {
              final event = bindings.poll();
              if (event == null) break;
              results.send({'event': event});
            }
          } catch (_) {
            results.send({
              'event': {'type': 'error', 'code': 'native_protocol_error'},
            });
          }
        })
      : null;
  commands.listen((dynamic command) {
    if (command is! (int, Map<String, Object?>, String?)) return;
    try {
      if (command.$3 == 'stop') {
        timer?.cancel();
        commands.close();
        results.send({
          'id': command.$1,
          'response': {'ok': true},
        });
        return;
      }
      results.send({
        'id': command.$1,
        'response': bindings.request(command.$2),
      });
    } catch (_) {
      results.send({
        'id': command.$1,
        'response': {
          'ok': false,
          'error': {'code': 'native_protocol_error'},
        },
      });
    }
  });
}

class _Bindings {
  _Bindings(DynamicLibrary library)
    : _request = library
          .lookupFunction<
            Pointer<Utf8> Function(Pointer<Utf8>),
            Pointer<Utf8> Function(Pointer<Utf8>)
          >('inboxplus_request'),
      _poll = library
          .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
            'inboxplus_poll_event',
          ),
      _free = library
          .lookupFunction<
            Void Function(Pointer<Utf8>),
            void Function(Pointer<Utf8>)
          >('inboxplus_free');

  final Pointer<Utf8> Function(Pointer<Utf8>) _request;
  final Pointer<Utf8> Function() _poll;
  final void Function(Pointer<Utf8>) _free;

  Map<String, Object?> request(Map<String, Object?> command) {
    final input = jsonEncode(command).toNativeUtf8();
    try {
      final response = _decode(_request(input));
      if (response == null) {
        throw const FormatException('Missing connector response');
      }
      return response;
    } finally {
      malloc.free(input);
    }
  }

  Map<String, Object?>? poll() => _decode(_poll());

  Map<String, Object?>? _decode(Pointer<Utf8> pointer) {
    if (pointer == nullptr) return null;
    try {
      return Map<String, Object?>.from(
        jsonDecode(pointer.toDartString()) as Map,
      );
    } finally {
      _free(pointer);
    }
  }
}
