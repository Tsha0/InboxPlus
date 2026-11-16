import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inboxplus/platform/app_environment.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  late Map<String, String> fileKeychain;
  late Map<String, String> dataProtectionKeychain;
  late Set<String> deniedFileItems;
  late List<MethodCall> calls;

  setUp(() {
    fileKeychain = {};
    dataProtectionKeychain = {};
    deniedFileItems = {};
    calls = [];
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          final arguments = call.arguments as Map;
          final options = arguments['options'] as Map;
          final key = arguments['key'] as String;
          final dataProtection =
              options['usesDataProtectionKeychain'] == 'true';
          final keychain = dataProtection
              ? dataProtectionKeychain
              : fileKeychain;
          if (!dataProtection && deniedFileItems.contains(key)) {
            throw PlatformException(code: 'Unexpected security result code');
          }
          switch (call.method) {
            case 'read':
              return keychain[key];
            case 'write':
              keychain[key] = arguments['value'] as String;
            case 'delete':
              keychain.remove(key);
          }
          return null;
        });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppEnvironment.native, null);
  });

  test('unentitled macOS builds use the app-owned file keychain without sharing provisioning', () async {
    const secrets = PlatformSecretStore();
    await secrets.write('fixture-key', 'fixture-value');
    expect(await secrets.read('fixture-key'), 'fixture-value');
    await secrets.delete('fixture-key');
    await secrets.write('kept-key', 'kept-value');

    expect(fileKeychain, {'kept-key': 'kept-value'});
    expect(dataProtectionKeychain, isEmpty);
    for (final call in calls) {
      expect((call.arguments as Map)['options']['groupId'], isNull);
    }
  });

  test('entitled builds move a file keychain secret on first read', () async {
    fileKeychain['database'] = 'saved-key';
    const secrets = PlatformSecretStore.dataProtection();

    expect(await secrets.read('database'), 'saved-key');
    expect(fileKeychain, isEmpty);
    expect(dataProtectionKeychain, {'database': 'saved-key'});
    expect(await secrets.read('database'), 'saved-key');
    for (final call in calls) {
      expect((call.arguments as Map)['options']['groupId'], isNull);
    }
  });

  test('a denied file keychain read fails and keeps the secret for the next launch', () async {
    fileKeychain['database'] = 'saved-key';
    deniedFileItems.add('database');
    const secrets = PlatformSecretStore.dataProtection();

    await expectLater(
      secrets.read('database'),
      throwsA(isA<PlatformException>()),
    );
    expect(fileKeychain, {'database': 'saved-key'});
    expect(dataProtectionKeychain, isEmpty);

    deniedFileItems.clear();
    expect(await secrets.read('database'), 'saved-key');
  });

  test('entitled builds report a missing secret as absent', () async {
    const secrets = PlatformSecretStore.dataProtection();
    expect(await secrets.read('database'), isNull);
  });

  test('entitled builds write to the data protection keychain only', () async {
    const secrets = PlatformSecretStore.dataProtection();
    await secrets.write('preferences', '{}');

    expect(dataProtectionKeychain, {'preferences': '{}'});
    expect(fileKeychain, isEmpty);
  });

  test('entitled builds delete a secret from both keychains', () async {
    fileKeychain['account'] = 'old';
    dataProtectionKeychain['account'] = 'new';
    const secrets = PlatformSecretStore.dataProtection();
    await secrets.delete('account');

    expect(fileKeychain, isEmpty);
    expect(dataProtectionKeychain, isEmpty);
    expect(await secrets.read('account'), isNull);
  });

  for (final entitled in [true, false]) {
    test(
      'opening a macOS profile ${entitled ? 'uses' : 'skips'} the data protection keychain when the signature ${entitled ? 'has' : 'lacks'} a keychain access group',
      () async {
        final temporary = await Directory.systemTemp.createTemp(
          'inboxplus-secret-store-test-',
        );
        addTearDown(() => temporary.delete(recursive: true));
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              AppEnvironment.native,
              (call) async => switch (call.method) {
                'hasKeychainAccessGroups' => entitled,
                'protectPath' => true,
                _ => null,
              },
            );
        final environment = await AppEnvironment.open(
          supportDirectory: temporary,
          environment: const {},
          isMacOS: true,
          isIOS: false,
        );

        await environment.secrets.write('preferences', '{}');

        expect((entitled ? dataProtectionKeychain : fileKeychain), {
          'preferences': '{}',
        });
        expect((entitled ? fileKeychain : dataProtectionKeychain), isEmpty);
      },
    );
  }
}
