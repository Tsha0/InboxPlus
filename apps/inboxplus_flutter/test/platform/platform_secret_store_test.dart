import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inboxplus_flutter/platform/app_environment.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('macOS private keys use the app-owned Keychain without sharing provisioning', () async {
    const channel = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    final calls = <MethodCall>[];
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return call.method == 'read' ? 'fixture-value' : null;
        });
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    const secrets = PlatformSecretStore();
    await secrets.write('fixture-key', 'fixture-value');
    expect(await secrets.read('fixture-key'), 'fixture-value');
    await secrets.delete('fixture-key');

    expect(calls.map((call) => call.method), ['write', 'read', 'delete']);
    for (final call in calls) {
      expect(
        (call.arguments as Map)['options']['usesDataProtectionKeychain'],
        'false',
      );
      expect((call.arguments as Map)['options']['groupId'], isNull);
    }
  });
}
