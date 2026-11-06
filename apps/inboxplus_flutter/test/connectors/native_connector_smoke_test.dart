import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:inboxplus_flutter/app_controller.dart';
import 'package:inboxplus_flutter/platform/app_environment.dart';
import 'package:inboxplus_storage/inboxplus_storage.dart';
import 'package:inboxplus_flutter/connectors/connector_engine.dart';
import 'package:inboxplus_flutter/connectors/native_connector_engine.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final library = Platform.environment['INBOXPLUS_CONNECTORS_LIBRARY'];
  test(
    'app startup loads the real embedded capabilities into an empty encrypted inbox',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'inboxplus-app-smoke-',
      );
      final directory = Directory(await temporary.resolveSymbolicLinks());
      final store = await LocalStore.open(
        file: File(p.join(directory.path, 'inbox.sqlite')),
        key: Uint8List.fromList(List.filled(32, 31)),
      );
      final engine = await NativeConnectorEngine.openForTesting(
        libraryPath: library!,
      );
      final app = AppController(
        store: store,
        environment: AppEnvironment(directory: directory, secrets: _Secrets()),
        engine: engine,
        nativeCall: (method, arguments) async => method == 'capabilities'
            ? {
                'web_login_platforms': ['instagram', 'messenger'],
                'imessage': true,
              }
            : null,
      );
      try {
        await app.initialize();
        expect(app.error, isNull);
        expect(app.isLoading, isFalse);
        expect(app.accounts, isEmpty);
        expect(app.conversations, isEmpty);
        expect(
          app.networks.where((network) => network.available),
          hasLength(5),
        );
        expect(app.storageSummary.messageCount, 0);
        expect(
          app.networks
              .where((network) => network.available && network.id != 'imessage')
              .every((network) => network.canReply && network.canReact),
          isTrue,
        );
        expect(
          app.networks
              .where((network) => !network.available)
              .every(
                (network) =>
                    !network.canReply &&
                    !network.canReact &&
                    !network.canAttach &&
                    !network.canStartConversation,
              ),
          isTrue,
        );
      } finally {
        await app.close();
        await directory.delete(recursive: true);
      }
    },
    skip: library == null
        ? 'Set INBOXPLUS_CONNECTORS_LIBRARY to a built connector library.'
        : false,
  );
  test(
    'embedded connectors initialize an isolated session without network access',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'inboxplus-native-smoke-',
      );
      final resolved = await directory.resolveSymbolicLinks();
      final engine = await NativeConnectorEngine.openForTesting(
        libraryPath: library!,
      );
      try {
        final capabilities = await engine.request({'op': 'capabilities'});
        expect(capabilities['abi_version'], 1);
        expect(
          capabilities['platforms'],
          containsAll(['whatsapp', 'telegram', 'instagram', 'messenger']),
        );
        final initialized = await engine.request({
          'op': 'initialize',
          'account_id': 'offline-smoke',
          'platform': 'whatsapp',
          'directory': p.join(resolved, 'account'),
          'key': base64Encode(List.filled(32, 7)),
        });
        expect(initialized['initialized'], isTrue);
        await expectLater(
          engine.request({
            'op': 'send_text',
            'account_id': 'unknown-account',
            'body': 'fixture',
          }),
          throwsA(
            isA<ConnectorException>().having(
              (error) => error.code,
              'code',
              'account_not_initialized',
            ),
          ),
        );
        expect(
          (await engine.request({
            'op': 'close',
            'account_id': 'offline-smoke',
          }))['closed'],
          isTrue,
        );
      } finally {
        await engine.close();
        await directory.delete(recursive: true);
      }
    },
    skip: library == null
        ? 'Set INBOXPLUS_CONNECTORS_LIBRARY to a source-built library'
        : false,
  );
}

class _Secrets implements SecretStore {
  final _values = <String, String>{};
  @override
  Future<String?> read(String key) async => _values[key];
  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}
