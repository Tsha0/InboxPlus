import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inboxplus_flutter/connectors/connector_engine.dart';
import 'package:inboxplus_flutter/connectors/native_connector_engine.dart';
import 'package:path/path.dart' as p;

void main() {
  if (!Platform.isMacOS && !Platform.isLinux) {
    test('threaded native fixture', () {}, skip: 'Requires a POSIX C compiler');
    return;
  }
  late Directory directory;
  late String library;

  Future<String> compile({bool slow = false}) async {
    final output = p.join(
      directory.path,
      '${slow ? 'slow' : 'fixture'}.${Platform.isMacOS ? 'dylib' : 'so'}',
    );
    final result = await Process.run('cc', [
      Platform.isMacOS ? '-dynamiclib' : '-shared',
      '-fPIC',
      '-std=c11',
      if (slow) '-DSLOW_START',
      'test/connectors/fixture_connector.c',
      '-o',
      output,
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    return output;
  }

  Matcher errorCode(String code) =>
      isA<ConnectorException>().having((error) => error.code, 'code', code);

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('inboxplus-ffi-test-');
    library = await compile();
  });

  tearDownAll(() async {
    await directory.delete(recursive: true);
  });

  test('polls QR events while a native request is blocked', () async {
    final engine = await NativeConnectorEngine.openForTesting(
      libraryPath: library,
    );
    addTearDown(engine.close);
    await engine.request({'op': 'reset'});
    final event = engine.events.first;
    var finished = false;
    final blocked = engine
        .request({'op': 'block'})
        .whenComplete(() => finished = true);

    expect(
      (await event.timeout(const Duration(seconds: 5)))['code'],
      'fixture-qr',
    );
    expect(finished, isFalse);
    await blocked;
  });

  test(
    'cancels a blocked request through the independent control worker',
    () async {
      final engine = await NativeConnectorEngine.openForTesting(
        libraryPath: library,
      );
      addTearDown(engine.close);
      await engine.request({'op': 'reset'});
      final event = engine.events.first;
      final blocked = engine.request({'op': 'block'});
      final failure = expectLater(
        blocked,
        throwsA(errorCode('operation_failed')),
      );
      await event.timeout(const Duration(seconds: 5));

      await engine.request({'op': 'cancel', 'account_id': 'fixture'});
      await failure;
    },
  );

  test('keeps timed-out requests ahead of later work until the native call returns', () async {
    final engine = await NativeConnectorEngine.openForTesting(
      libraryPath: library,
      requestTimeout: const Duration(milliseconds: 50),
    );
    addTearDown(engine.close);
    await engine.request({'op': 'reset'});
    await expectLater(
      engine.request({'op': 'block'}),
      throwsA(errorCode('outcome_unknown')),
    );

    final next = engine.request({'op': 'state'});
    await engine.request({'op': 'cancel'});
    expect((await next)['increments'], 0);
  });

  test(
    'closing cancels active work and does not execute queued requests',
    () async {
      final engine = await NativeConnectorEngine.openForTesting(
        libraryPath: library,
      );
      await engine.request({'op': 'reset'});
      final event = engine.events.first;
      final active = expectLater(
        engine.request({'op': 'block'}),
        throwsA(errorCode('operation_failed')),
      );
      final queued = expectLater(
        engine.request({'op': 'increment'}),
        throwsA(errorCode('engine_closed')),
      );
      await event.timeout(const Duration(seconds: 5));

      final close = engine.close();
      expect(identical(close, engine.close()), isTrue);
      await close;
      await active;
      await queued;
      await expectLater(
        engine.request({'op': 'state'}),
        throwsA(errorCode('engine_closed')),
      );

      final reopened = await NativeConnectorEngine.openForTesting(
        libraryPath: library,
      );
      addTearDown(reopened.close);
      expect((await reopened.request({'op': 'state'}))['increments'], 0);
    },
  );

  test(
    'keeps native error details private and handles malformed responses',
    () async {
      final engine = await NativeConnectorEngine.openForTesting(
        libraryPath: library,
      );
      addTearDown(engine.close);
      await expectLater(
        engine.request({'op': 'failure'}),
        throwsA(errorCode('operation_failed')),
      );
      await expectLater(
        engine.request({'op': 'malformed'}),
        throwsA(errorCode('native_protocol_error')),
      );
      expect((await engine.request({'op': 'capabilities'}))['abi_version'], 1);
    },
  );

  test('fails safely when a library cannot be loaded', () async {
    await expectLater(
      NativeConnectorEngine.openForTesting(
        libraryPath: p.join(directory.path, 'missing.dylib'),
      ),
      throwsA(errorCode('native_library_unavailable')),
    );
  });

  test('cleans up startup when loading takes too long', () async {
    final slow = await compile(slow: true);
    await expectLater(
      NativeConnectorEngine.openForTesting(
        libraryPath: slow,
        startupTimeout: const Duration(milliseconds: 20),
      ),
      throwsA(errorCode('native_library_unavailable')),
    );
  });

  test('startup deadline includes worker creation', () async {
    await expectLater(
      NativeConnectorEngine.openForTesting(
        libraryPath: library,
        startupTimeout: Duration.zero,
      ),
      throwsA(errorCode('native_library_unavailable')),
    );
  });

  test('native fixture waits through an interrupted sleep', () async {
    final executable = p.join(directory.path, 'interrupted-sleep');
    final compiled = await Process.run('cc', [
      '-std=c11',
      '-DTEST_INTERRUPTED_SLEEP',
      'test/connectors/fixture_connector.c',
      '-o',
      executable,
    ]);
    expect(compiled.exitCode, 0, reason: '${compiled.stderr}');
    final result = await Process.run(
      executable,
      [],
    ).timeout(const Duration(seconds: 10));
    expect(result.exitCode, 0, reason: '${result.stderr}');
  });
}
