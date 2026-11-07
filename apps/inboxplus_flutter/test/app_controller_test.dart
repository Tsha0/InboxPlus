import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:inboxplus_flutter/app_controller.dart';
import 'package:inboxplus_flutter/connectors/connector_engine.dart';
import 'package:inboxplus_flutter/platform/app_environment.dart';
import 'package:inboxplus_flutter/ui/inbox_ui_controller.dart';
import 'package:inboxplus_storage/inboxplus_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late File database;
  late Uint8List key;
  late LocalStore store;
  late _MemorySecrets secrets;
  late _NativeFixture native;
  AppController? controller;
  var storeClosed = false;
  const firstRoute = ConversationRoute('first', 'same-chat');
  const secondRoute = ConversationRoute('second', 'same-chat');
  final instant = DateTime.utc(2026, 11, 5, 10);

  Future<void> seed(
    ConversationRoute route, {
    String platform = 'whatsapp',
  }) async {
    await store.saveAccount(
      AccountRecord(
        id: route.accountId,
        platform: platform,
        displayName: 'Fixture account',
      ),
    );
    await store.saveConversation(
      ConversationRecord(
        route: route,
        title: 'Fixture conversation',
        latestActivity: instant,
      ),
    );
  }

  Future<AppController> start({
    _FakeEngine? engine,
    String profileName = 'default',
    DateTime Function()? now,
  }) async {
    final value = AppController(
      store: store,
      environment: AppEnvironment(
        directory: directory,
        secrets: secrets,
        profileName: profileName,
      ),
      engine: engine,
      nativeCall: native.call,
      now: now ?? () => instant,
    );
    controller = value;
    await value.initialize();
    return value;
  }

  Future<void> closeController() async {
    await controller?.close();
    controller = null;
    storeClosed = true;
  }

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final temporary = await Directory.systemTemp.createTemp(
      'inboxplus-controller-',
    );
    directory = Directory(await temporary.resolveSymbolicLinks());
    database = File.fromUri(directory.uri.resolve('inbox.sqlite'));
    key = Uint8List.fromList(List.generate(32, (index) => index + 1));
    store = await LocalStore.open(file: database, key: key);
    storeClosed = false;
    secrets = _MemorySecrets();
    native = _NativeFixture();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          AppEnvironment.native,
          (call) async => call.method == 'protectPath' ? true : null,
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AppEnvironment.native, null),
    );
  });

  tearDown(() async {
    if (controller != null) {
      await closeController();
    } else if (!storeClosed) {
      await store.close();
    }
    await directory.delete(recursive: true);
  });

  test('WhatsApp mobile linking validates and normalizes phone inputs without losing the form', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final engine = _FakeEngine(connectState: 'started');
    final app = await start(engine: engine);
    await app.beginLogin('whatsapp');
    final id = engine.platforms.keys.single;
    engine.emit({'type': 'qr', 'account_id': id, 'code': 'fixture-qr'});
    await _eventually(() => app.login?.step == LoginStep.fields);
    expect(app.login?.fields.map((field) => field.id), [
      'country_code',
      'phone',
    ]);
    await app.submitLogin({'country_code': '65', 'phone': 'unsafe-number'});
    expect(app.login?.step, LoginStep.fields);
    expect(app.login?.error, contains('valid phone number'));
    expect(engine.commands.where((c) => c['op'] == 'pair_phone'), isEmpty);
    engine.emit({'type': 'qr', 'account_id': id, 'code': 'refreshed-qr'});
    await Future<void>.delayed(Duration.zero);
    expect(app.login?.error, contains('valid phone number'));
    await app.submitLogin({'country_code': '65', 'phone': '8123 4567'});
    expect(
      engine.commands.singleWhere((c) => c['op'] == 'pair_phone')['phone'],
      '6581234567',
    );
    expect(app.login?.step, LoginStep.pairingCode);
    engine.emit({'type': 'qr', 'account_id': id, 'code': 'late-qr'});
    await Future<void>.delayed(Duration.zero);
    expect(app.login?.pairingCode, 'ABCD-EFGH');
    expect(
      native.calls
          .where((c) => c['method'] == 'setLoginActive')
          .first['arguments'],
      {'active': true},
    );
    engine.emit({'type': 'connection', 'account_id': id, 'state': 'connected'});
    await _eventually(() => app.login?.step == LoginStep.complete);
    expect(
      native.calls
          .where((c) => c['method'] == 'setLoginActive')
          .last['arguments'],
      {'active': false},
    );
    engine.emit({'type': 'qr', 'account_id': id, 'code': 'after-success'});
    await Future<void>.delayed(Duration.zero);
    expect(app.login?.step, LoginStep.complete);
  });

  test('WhatsApp phone pairing keeps significant zeroes and rejects duplicate requests', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final response = Completer<Map<String, Object?>>();
    final engine = _FakeEngine(
      connectState: 'started',
      onPairPhone: (_) => response.future,
    );
    final app = await start(engine: engine);
    await app.beginLogin('whatsapp');
    engine.emit({
      'type': 'qr',
      'account_id': engine.platforms.keys.single,
      'code': 'fixture',
    });
    await _eventually(() => app.login?.step == LoginStep.fields);
    final pending = app.submitLogin({
      'country_code': '39',
      'phone': '02 1234 5678',
    });
    await _eventually(() => app.login?.busy == true);
    engine.emit({
      'type': 'connection',
      'account_id': engine.platforms.keys.single,
      'state': 'connecting',
    });
    await Future<void>.delayed(Duration.zero);
    expect(app.login?.busy, isTrue);
    await app.submitLogin({'country_code': '39', 'phone': '02 1234 5678'});
    expect(engine.commands.where((c) => c['op'] == 'pair_phone').length, 1);
    expect(
      engine.commands.singleWhere((c) => c['op'] == 'pair_phone')['phone'],
      '390212345678',
    );
    response.complete({'code': 'ABCD-EFGH'});
    await pending;
  });

  test(
    'WhatsApp confirmation wins over a late phone-pairing failure',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final response = Completer<Map<String, Object?>>();
      final engine = _FakeEngine(
        connectState: 'started',
        onPairPhone: (_) => response.future,
      );
      final app = await start(engine: engine);
      await app.beginLogin('whatsapp');
      final id = engine.platforms.keys.single;
      engine.emit({'type': 'qr', 'account_id': id, 'code': 'fixture'});
      await _eventually(() => app.login?.step == LoginStep.fields);
      final pending = app.submitLogin({
        'country_code': '65',
        'phone': '81234567',
      });
      await _eventually(() => app.login?.busy == true);
      engine.emit({
        'type': 'connection',
        'account_id': id,
        'state': 'connected',
      });
      await _eventually(() => app.login?.step == LoginStep.complete);
      response.completeError(
        const ConnectorException('whatsapp_phone_pairing_failed'),
      );
      await pending;
      expect(app.login?.step, LoginStep.complete);
      expect(app.login?.error, isNull);
    },
  );

  test('WhatsApp QR mode accepts formatted full numbers and pairing failures can be corrected', () async {
    var rejected = true;
    final engine = _FakeEngine(
      connectState: 'started',
      onPairPhone: (_) async {
        if (rejected) {
          throw const ConnectorException('whatsapp_phone_pairing_failed');
        }
        return {'code': 'ABCD-EFGH'};
      },
    );
    final app = await start(engine: engine);
    await app.beginLogin('whatsapp', useQr: true);
    engine.emit({
      'type': 'qr',
      'account_id': engine.platforms.keys.single,
      'code': 'fixture',
    });
    await _eventually(() => app.login?.step == LoginStep.qr);
    await app.submitLogin({'phone': '+65 8123 4567'});
    expect(app.login?.step, LoginStep.qr);
    expect(app.login?.error, contains('Check your number'));
    rejected = false;
    await app.submitLogin({'phone': '+65 (8123)-4567'});
    expect(app.login?.step, LoginStep.pairingCode);
    expect(
      engine.commands
          .where((c) => c['op'] == 'pair_phone')
          .every((c) => c['phone'] == '6581234567'),
      isTrue,
    );
  });

  test('WhatsApp code expiry on resume clears the code and retry starts a new connection', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    var clock = instant;
    final engine = _FakeEngine(
      connectState: 'started',
      onPairPhone: (_) async => {
        'code': 'ABCD-EFGH',
        'expires_at': instant
            .add(const Duration(seconds: 160))
            .millisecondsSinceEpoch,
      },
    );
    final app = await start(engine: engine, now: () => clock);
    await app.beginLogin('whatsapp');
    engine.emit({
      'type': 'qr',
      'account_id': engine.platforms.keys.single,
      'code': 'fixture',
    });
    await _eventually(() => app.login?.step == LoginStep.fields);
    await app.submitLogin({'country_code': '65', 'phone': '81234567'});
    await app.resumeLogin();
    expect(app.login?.step, LoginStep.pairingCode);
    clock = instant.add(const Duration(minutes: 3));
    await app.resumeLogin();
    expect(app.login?.step, LoginStep.failed);
    expect(app.login?.pairingCode, isNull);
    expect(app.login?.error, contains('fresh code'));
    await app.beginLogin('whatsapp');
    expect(engine.commands.where((c) => c['op'] == 'connect').length, 2);
    expect(app.login?.step, LoginStep.preparing);
  });

  test('WeChat QR export uses native in-memory images and background expiry remains recoverable', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final engine = _FakeEngine(
      connectState: 'started',
      additionalPlatforms: ['wechat'],
    );
    final app = await start(engine: engine);
    await app.beginLogin('wechat');
    final id = engine.platforms.keys.single;
    engine.emit({'type': 'qr', 'account_id': id, 'image': 'fixture-image'});
    await _eventually(() => app.login?.step == LoginStep.qr);
    final bytes = Uint8List.fromList([1, 2, 3]);
    await app.exportLoginQr(bytes);
    await app.exportLoginQr(bytes, share: true);
    expect(
      native.calls
          .where((c) => c['method'] == 'saveLoginQr')
          .single['arguments'],
      {'image': bytes},
    );
    expect(
      native.calls
          .where((c) => c['method'] == 'shareLoginQr')
          .single['arguments'],
      {'image': bytes},
    );
    expect(app.login?.step, LoginStep.qr);
    native.photosDenied = true;
    await app.exportLoginQr(bytes);
    expect(app.login?.step, LoginStep.qr);
    expect(app.error, contains('Allow Inbox+ to add photos'));
    native.photosDenied = false;
    await app.exportLoginQr(bytes, share: true);
    expect(app.error, isNull);
    native.loginBackgroundExpired = true;
    await app.resumeLogin();
    expect(app.login?.step, LoginStep.failed);
    expect(app.login?.qrImage, isNull);
    await app.cancelLogin();
    expect(app.login, isNull);
  });

  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
    TargetPlatform.android,
    TargetPlatform.iOS,
  ]) {
    test('iMessage integration is macOS-only on $platform', () async {
      debugDefaultTargetPlatformOverride = platform;
      native.imessageAvailable = true;
      final app = await start(engine: _FakeEngine());
      final imessage = app.networks.where(
        (network) => network.id == 'imessage',
      );
      if (platform == TargetPlatform.macOS) {
        expect(imessage.single.available, isTrue);
        expect(imessage.single.canStartConversation, isTrue);
      } else {
        if (platform == TargetPlatform.iOS) {
          expect(imessage.single.available, isFalse);
          expect(imessage.single.comingSoon, isTrue);
          expect(imessage.single.canStartConversation, isFalse);
          expect(
            imessage.single.reason,
            'Coming soon · Experimental iOS integration',
          );
        } else {
          expect(imessage, isEmpty);
        }
        await app.beginLogin('imessage');
        expect(app.error, isNotNull);
        expect(app.login, isNull);
        expect(await store.loadAccounts(), isEmpty);
        expect(
          native.calls.where(
            (call) => (call['method'] as String).startsWith('imessage'),
          ),
          isEmpty,
        );
      }
    });
  }

  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
    TargetPlatform.android,
    TargetPlatform.iOS,
  ]) {
    test(
      'new device-local networks are available on $platform without web sign-in',
      () async {
        debugDefaultTargetPlatformOverride = platform;
        final app = await start(
          engine: _FakeEngine(
            additionalPlatforms: ['wechat', 'discord', 'linkedIn'],
          ),
        );
        for (final id in ['wechat', 'discord', 'linkedIn']) {
          final network = app.networks.singleWhere(
            (network) => network.id == id,
          );
          expect(network.available, isTrue);
          expect(network.canReact, isFalse);
          expect(network.canAttach, id == 'discord');
          expect(network.canReply, id == 'discord');
        }
        expect(
          app.networks.any((network) => network.id == 'imessage'),
          platform == TargetPlatform.iOS,
        );
        await app.beginLogin('linkedIn');
        expect(app.login?.fields.map((field) => field.id), [
          'username',
          'password',
        ]);
        expect(
          native.calls.where((call) => call['method'] == 'webLogin'),
          isEmpty,
        );
      },
    );
  }

  for (final network in ['discord', 'linkedIn']) {
    test(
      '$network setup accepts credentials and verification without persisting passwords',
      () async {
        final engine = _FakeEngine(
          additionalPlatforms: [network],
          connectState: 'code',
        );
        final app = await start(engine: engine);
        await app.beginLogin(network);
        await app.submitLogin({
          'username': 'fixture@example.test',
          'password': 'fixture-password',
        });
        expect(app.login?.fields.single.id, 'code');
        expect(app.login?.instructions.contains('Telegram'), isFalse);
        await app.submitLogin({'code': '123456'});
        expect(app.login?.step, LoginStep.complete);
        expect(app.accounts.single.isConnected, isTrue);
        expect(
          engine.commands.singleWhere(
            (command) => command['op'] == 'login',
          )['username'],
          'fixture@example.test',
        );
        expect(jsonEncode(secrets.values), isNot(contains('fixture-password')));
        expect(app.diagnosticsJson(), isNot(contains('fixture-password')));
      },
    );
  }

  test('Discord token sign-in omits email and password', () async {
    final engine = _FakeEngine(additionalPlatforms: ['discord']);
    final app = await start(engine: engine);
    await app.beginLogin('discord');
    await app.submitLogin({
      'username': '',
      'password': '',
      'token': 'fixture-token',
    });
    final command = engine.commands.singleWhere(
      (command) => command['op'] == 'login',
    );
    expect(command['token'], 'fixture-token');
    expect(command.containsKey('password'), isFalse);
    expect(command.containsKey('username'), isFalse);
    expect(app.login?.step, LoginStep.complete);
  });

  test(
    'WeChat QR image retains its network and skips unavailable history',
    () async {
      final started = Completer<void>();
      final complete = Completer<Map<String, Object?>>();
      final engine = _FakeEngine(
        additionalPlatforms: ['wechat'],
        onConnect: (_) {
          started.complete();
          return complete.future;
        },
      );
      final app = await start(engine: engine);
      final connecting = app.beginLogin('wechat');
      await started.future;
      final id = engine.platforms.keys.single;
      engine.emit({'type': 'qr', 'account_id': id, 'image': 'fixture-image'});
      await _eventually(() => app.login?.step == LoginStep.qr);
      expect(app.login?.networkId, 'wechat');
      expect(app.login?.qrImage, 'fixture-image');
      expect(app.login?.qrData, isNull);
      complete.complete({'state': 'connected'});
      await connecting;
      final route = ConversationRoute(id, '@friend');
      engine.emit({
        'type': 'chat',
        'account_id': id,
        'id': '@friend',
        'title': 'Friend',
      });
      await _eventually(() => app.conversations.isNotEmpty);
      app.selectConversation(route);
      await _eventually(() => !app.isBusy);
      expect(
        engine.commands.where((command) => command['op'] == 'history'),
        isEmpty,
      );
      expect(app.error, isNull);
    },
  );

  test(
    'LinkedIn approval continues without resubmitting the password',
    () async {
      final engine = _FakeEngine(
        additionalPlatforms: ['linkedIn'],
        connectState: 'approval',
      );
      final app = await start(engine: engine);
      await app.beginLogin('linkedIn');
      await app.submitLogin({
        'username': 'fixture@example.test',
        'password': 'fixture-password',
      });
      expect(app.login?.fields, isEmpty);
      expect(app.login?.title, 'Approve LinkedIn sign-in');
      await app.submitLogin({});
      expect(
        engine.commands
            .lastWhere((command) => command['op'] == 'login_wait')
            .keys,
        containsAll(['op', 'account_id']),
      );
      expect(app.login?.step, LoginStep.complete);
    },
  );

  test('accepted cross-network suggestion persists once without connecting accounts', () async {
    await seed(firstRoute);
    await seed(secondRoute, platform: 'telegram');
    for (final route in [firstRoute, secondRoute]) {
      await store.saveConversation(
        ConversationRecord(
          route: route,
          title: 'José Chen',
          identityId: 'shared',
          latestActivity: instant,
        ),
      );
    }
    final app = await start();
    final suggestion = app.contactSuggestions.single;
    expect(app.contacts, isEmpty);
    final results = await Future.wait([
      app.acceptContactSuggestion(suggestion),
      app.acceptContactSuggestion(suggestion),
    ]);
    expect(results.whereType<String>(), hasLength(1));
    expect(app.error, isNull);
    expect(
      app.contacts.single.identities.map((identity) => identity.accountId),
      ['first', 'second'],
    );
    expect(app.contactSuggestions, isEmpty);
    expect(await app.acceptContactSuggestion(suggestion), isNull);
    expect(app.contacts, hasLength(1));
    await closeController();
    store = await LocalStore.open(file: database, key: key);
    storeClosed = false;
    final reopened = await start();
    expect(reopened.contacts.single.displayName, 'José Chen');
    expect(reopened.contacts.single.identities, hasLength(2));
    expect(reopened.conversations, hasLength(2));
    expect(reopened.contactSuggestions, isEmpty);
  });

  test(
    'stale contact suggestion cannot replace an existing person link',
    () async {
      await seed(firstRoute);
      await seed(secondRoute, platform: 'telegram');
      for (final route in [firstRoute, secondRoute]) {
        await store.saveConversation(
          ConversationRecord(
            route: route,
            title: 'Alex Chen',
            identityId: 'shared',
            latestActivity: instant,
          ),
        );
      }
      final app = await start();
      final suggestion = app.contactSuggestions.single;
      await app.linkIdentity(
        const IdentityLink('first', 'shared'),
        ContactRecord(id: 'existing', displayName: 'Existing'),
      );
      expect(await app.acceptContactSuggestion(suggestion), isNull);
      expect(app.contacts.single.id, 'existing');
      expect(app.contacts.single.identities.single.accountId, 'first');
    },
  );

  test(
    'failed suggestion save rolls back every link and allows a retry',
    () async {
      await seed(firstRoute);
      await seed(secondRoute, platform: 'telegram');
      for (final route in [firstRoute, secondRoute]) {
        await store.saveConversation(
          ConversationRecord(
            route: route,
            title: 'Alex Chen',
            identityId: 'shared',
            latestActivity: instant,
          ),
        );
      }
      final app = await start();
      final suggestion = app.contactSuggestions.single;
      await store.saveContact(
        ContactRecord(
          id: 'other-writer',
          displayName: 'Existing',
          identities: const [IdentityLink('second', 'shared')],
        ),
      );
      expect(await app.acceptContactSuggestion(suggestion), isNull);
      expect(app.error, contains('Your existing profile has been kept'));
      final saved = (await store.loadContacts()).single;
      expect(saved.id, 'other-writer');
      expect(saved.identities.single.accountId, 'second');
      expect(app.contacts, isEmpty);
      await app.removeContact(saved.id);
      expect(await app.acceptContactSuggestion(suggestion), isNotNull);
      expect(app.error, isNull);
      expect(app.contacts.single.identities, hasLength(2));
    },
  );

  test(
    'recipient Contacts are read on demand only for connected iMessage',
    () async {
      native.imessageAvailable = true;
      await seed(firstRoute);
      final engine = _FakeEngine();
      final app = await start(engine: engine);
      expect(
        native.calls.where(
          (call) => call['method'] == 'imessageRecipientContacts',
        ),
        isEmpty,
      );
      expect(
        (await app.recipientContacts(firstRoute.accountId)).recipients,
        isEmpty,
      );
      await app.beginLogin('imessage');
      native.recipientSnapshot = {
        'status': 'available',
        'recipients': [
          {
            'name': 'Zoë Fixture',
            'address': 'zoe@example.com',
            'search_text': 'zoe fixture zoe@example.com',
          },
          {
            'name': 'Zoë Fixture',
            'address': '+14155550101',
            'search_text': 'zoe fixture +14155550101',
          },
        ],
      };
      final contacts = await app.recipientContacts('imessage-local');
      expect(contacts.status, LocalRecipientStatus.available);
      expect(contacts.recipients.map((contact) => contact.address), [
        'zoe@example.com',
        '+14155550101',
      ]);
      expect(
        contacts.recipients.every((contact) => contact.matches('  ZOE  ')),
        isTrue,
      );
      expect(contacts.recipients.first.matches('Zoë'), isTrue);
      expect(await store.loadContacts(), isEmpty);
      expect(engine.sends, isEmpty);
      await app.disconnectAccount('imessage-local');
      expect(
        (await app.recipientContacts('imessage-local')).recipients,
        isEmpty,
      );
      expect(
        native.calls.where(
          (call) => call['method'] == 'imessageRecipientContacts',
        ),
        hasLength(1),
      );
    },
  );

  test('recipient Contacts report denied and failed reads without leaking diagnostics', () async {
    native.imessageAvailable = true;
    final app = await start(engine: _FakeEngine());
    await app.beginLogin('imessage');
    native.recipientSnapshot = {'status': 'access_unavailable'};
    expect(
      (await app.recipientContacts('imessage-local')).status,
      LocalRecipientStatus.accessUnavailable,
    );
    for (final malformed in [
      null,
      {'status': 'failed'},
      {
        'status': 'available',
        'recipients': [
          {'name': 123},
        ],
      },
    ]) {
      native.recipientSnapshot = malformed;
      expect(
        (await app.recipientContacts('imessage-local')).status,
        LocalRecipientStatus.failed,
      );
    }
    native.failRecipientContacts = true;
    expect(
      (await app.recipientContacts('imessage-local')).status,
      LocalRecipientStatus.failed,
    );
    expect(app.error, isNull);
    expect(await store.loadContacts(), isEmpty);
  });

  test('opening an iMessage recipient creates no send or draft', () async {
    native.imessageAvailable = true;
    final engine = _FakeEngine();
    final app = await start(engine: engine);
    await app.beginLogin('imessage');
    native.imessageStartResult = {
      'id': 'new-local-chat',
      'identity_id': 'fixture@example.com',
      'title': 'Fixture recipient',
      'timestamp': instant.millisecondsSinceEpoch,
    };
    await app.startConversation('imessage-local', ' fixture@example.com ');
    const route = ConversationRoute('imessage-local', 'new-local-chat');
    expect(app.selectedRoute, route);
    expect(await store.loadRecentMessages(route), isEmpty);
    expect(await store.loadDraft(route), isNull);
    expect(await store.loadPendingSends(), isEmpty);
    expect(
      native.calls.where((call) => call['method'] == 'imessageSend'),
      isEmpty,
    );
    expect(engine.sends, isEmpty);
  });

  test(
    'desktop theme and notification choices survive reopening the profile',
    () async {
      final app = await start(engine: _FakeEngine());
      await app.setPreference('appearance', 'dark');
      await app.setPreference('themePreset', 'nightSwim');
      await app.setPreference('customColors', [0x102a43, 0x3a86ff, 0x00c2d1]);
      await app.setPreference('notificationPreviews', false);
      await app.setPreference('notificationSound', false);
      await app.setPreference('messageRetentionDays', 90);
      await app.setPreference('iMessageHistory', 'quarter');
      await app.setPreference('playsInstagramReels', true);
      await closeController();
      store = await LocalStore.open(file: database, key: key);
      storeClosed = false;
      final reopened = await start(engine: _FakeEngine());

      expect(reopened.preferences.appearance, 'dark');
      expect(reopened.preferences.themePreset, 'custom');
      expect(reopened.preferences.customColors, [0x102a43, 0x3a86ff, 0x00c2d1]);
      expect(reopened.preferences.notificationPreviews, isFalse);
      expect(reopened.preferences.notificationSound, isFalse);
      expect(reopened.preferences.messageRetentionDays, 90);
      expect(reopened.preferences.iMessageHistory, 'quarter');
      expect(reopened.preferences.playsInstagramReels, isTrue);
      await reopened.setPreference('customColors', [0xffffff]);
      await reopened.setPreference('themePreset', 'invalid');
      expect(reopened.preferences.themePreset, 'custom');
      expect(reopened.preferences.customColors, hasLength(3));
    },
  );

  test(
    'reaction counts toggle once, remain scoped and survive reopening',
    () async {
      await seed(firstRoute);
      await seed(secondRoute);
      for (final route in [firstRoute, secondRoute]) {
        await store.saveMessage(
          MessageRecord(
            id: 'message',
            route: route,
            body: 'Fixture',
            timestamp: instant,
            isOutgoing: false,
            senderId: 'author',
          ),
        );
      }
      final engine = _FakeEngine();
      final app = await start(engine: engine);
      final event = {
        'type': 'reaction',
        'account_id': firstRoute.accountId,
        'conversation_id': firstRoute.conversationId,
        'id': 'message',
        'sender_id': 'other-actor',
        'emoji': '👍',
        'timestamp': instant.millisecondsSinceEpoch,
      };
      engine.emit(event);
      engine.emit(event);
      await _eventually(
        () => app.reactionsFor(firstRoute, 'message')['👍'] == 1,
      );
      await app.react(firstRoute, 'message', '👍');
      expect(app.reactionsFor(firstRoute, 'message'), {'👍': 2});
      expect(app.ownReactionsFor(firstRoute, 'message'), {'👍'});
      await app.react(firstRoute, 'message', '👍');
      expect(app.reactionsFor(firstRoute, 'message'), {'👍': 1});
      expect(app.ownReactionsFor(firstRoute, 'message'), isEmpty);
      expect(app.reactionsFor(secondRoute, 'message'), isEmpty);
      final commands = engine.commands
          .where((c) => c['op'] == 'react')
          .toList();
      expect(commands.map((c) => c['emoji']), ['👍', '']);
      expect(commands.first['message_sender_id'], 'author');
      expect(native.notifications, isEmpty);
      expect(app.conversations.every((c) => c.unreadCount == 0), isTrue);
      await closeController();
      store = await LocalStore.open(file: database, key: key);
      storeClosed = false;
      final reopened = await start(engine: _FakeEngine());
      expect(reopened.reactionsFor(firstRoute, 'message'), {'👍': 1});
    },
  );

  test('reaction updates arriving before a message survive edits and clear with deletion', () async {
    await seed(firstRoute);
    final engine = _FakeEngine();
    final app = await start(engine: engine);
    engine.emit({
      'type': 'reaction',
      'account_id': firstRoute.accountId,
      'conversation_id': firstRoute.conversationId,
      'id': 'later',
      'sender_id': 'actor',
      'emoji': '❤️',
      'outgoing': true,
    });
    await _eventually(() => app.reactionsFor(firstRoute, 'later').isNotEmpty);
    engine.emit({
      'type': 'message',
      'account_id': firstRoute.accountId,
      'conversation_id': firstRoute.conversationId,
      'id': 'later',
      'body': 'Original',
      'timestamp': instant.millisecondsSinceEpoch,
    });
    await _eventually(() => app.messagesFor(firstRoute).isNotEmpty);
    engine.emit({
      'type': 'message_edit',
      'account_id': firstRoute.accountId,
      'conversation_id': firstRoute.conversationId,
      'id': 'later',
      'body': 'Edited',
    });
    await _eventually(
      () => app.messagesFor(firstRoute).single.body == 'Edited',
    );
    expect(app.reactionsFor(firstRoute, 'later'), {'❤️': 1});
    engine.emit({
      'type': 'message_delete',
      'account_id': firstRoute.accountId,
      'conversation_id': firstRoute.conversationId,
      'id': 'later',
    });
    await _eventually(() => app.messagesFor(firstRoute).isEmpty);
    expect(app.reactionsFor(firstRoute, 'later'), isEmpty);
    expect(await store.loadReactions(firstRoute, 'later'), isEmpty);
  });

  test('partial reaction totals retain ownership until a full snapshot clears them', () async {
    await seed(firstRoute, platform: 'telegram');
    final engine = _FakeEngine();
    final app = await start(engine: engine);
    final scope = {
      'type': 'reactions',
      'account_id': firstRoute.accountId,
      'conversation_id': firstRoute.conversationId,
      'id': 'message',
    };
    engine.emit({
      ...scope,
      'reactions': [
        {'key': '👍', 'count': 3, 'includes_me': true},
      ],
    });
    await _eventually(
      () => app.ownReactionsFor(firstRoute, 'message').contains('👍'),
    );
    engine.emit({
      ...scope,
      'reactions_partial': true,
      'reactions': [
        {'key': '👍', 'count': 4},
      ],
    });
    await _eventually(() => app.reactionsFor(firstRoute, 'message')['👍'] == 4);
    expect(app.ownReactionsFor(firstRoute, 'message'), {'👍'});
    engine.emit({...scope, 'reactions': []});
    await _eventually(() => app.reactionsFor(firstRoute, 'message').isEmpty);
    expect(app.ownReactionsFor(firstRoute, 'message'), isEmpty);
  });

  test('unconfirmed and duplicate reaction requests do not create optimistic counts', () async {
    await seed(firstRoute);
    await store.saveMessage(
      MessageRecord(
        id: 'message',
        route: firstRoute,
        body: 'Fixture',
        timestamp: instant,
        isOutgoing: false,
      ),
    );
    final response = Completer<Map<String, Object?>>();
    final engine = _FakeEngine(onReact: (_) => response.future);
    final app = await start(engine: engine);
    final first = app.react(firstRoute, 'message', '👍');
    await _eventually(() => engine.commands.any((c) => c['op'] == 'react'));
    await app.react(firstRoute, 'message', '👍');
    expect(engine.commands.where((c) => c['op'] == 'react'), hasLength(1));
    expect(app.reactionsFor(firstRoute, 'message'), isEmpty);
    response.complete({'applied': false});
    await first;
    expect(app.reactionsFor(firstRoute, 'message'), isEmpty);
    expect(app.error, isNotNull);
  });

  test(
    'queued replies retain their scoped target through reopening and sending',
    () async {
      await seed(firstRoute);
      await seed(secondRoute);
      for (final route in [firstRoute, secondRoute]) {
        await store.saveMessage(
          MessageRecord(
            id: 'original',
            route: route,
            body: 'Original in ${route.accountId}',
            timestamp: instant,
            isOutgoing: false,
            senderId: 'sender-${route.accountId}',
          ),
        );
      }
      final offline = await start();
      offline.setReplyTo(firstRoute, 'original');
      offline.updateDraft(firstRoute, 'An offline reply');
      await offline.sendDraft(firstRoute);
      expect(
        (await store.loadPendingSends()).single.replyToMessageId,
        'original',
      );
      await closeController();

      store = await LocalStore.open(file: database, key: key);
      storeClosed = false;
      final sentAt = instant.add(const Duration(minutes: 1));
      final engine = _FakeEngine(
        onSend: (_) async => {
          'id': 'confirmed-reply',
          'timestamp': sentAt.millisecondsSinceEpoch,
        },
      );
      final reopened = await start(engine: engine);
      await _eventually(() => engine.sends.isNotEmpty && !reopened.isBusy);
      final command = engine.sends.single;
      expect(command['account_id'], firstRoute.accountId);
      expect(command['conversation_id'], firstRoute.conversationId);
      expect(command['reply_to_message_id'], 'original');
      expect(command['reply_to_sender_id'], 'sender-first');
      expect(command['reply_to_body'], 'Original in first');
      expect(command['reply_to_outgoing'], isFalse);
      final sent = reopened
          .messagesFor(firstRoute)
          .where((m) => m.isOutgoing)
          .single;
      expect(sent.replyToMessageId, 'original');
      expect(reopened.conversations.first.route, firstRoute);
      expect(reopened.conversations.first.latestActivity, sentAt);
      expect((await store.loadConversations()).first.latestActivity, sentAt);
      expect(reopened.draftFor(firstRoute)?.body, isEmpty);
      expect(reopened.draftFor(firstRoute)?.replyToMessageId, isNull);
      expect(await store.loadPendingSends(), isEmpty);
    },
  );

  test(
    'a missing reply target preserves the draft without sending plain text',
    () async {
      await seed(firstRoute);
      final engine = _FakeEngine();
      final app = await start(engine: engine);
      app.setReplyTo(firstRoute, 'missing');
      app.updateDraft(firstRoute, 'Keep this reply');
      await app.sendDraft(firstRoute);
      expect(engine.sends, isEmpty);
      expect(app.draftFor(firstRoute)?.body, 'Keep this reply');
      expect(app.draftFor(firstRoute)?.replyToMessageId, 'missing');
      expect(
        (await store.loadPendingSends()).single.status,
        PendingSendStatus.failed,
      );
      expect(app.error, contains('reply target'));
    },
  );

  test(
    'incoming replies retain authors and quotes after message edits',
    () async {
      await seed(firstRoute);
      final engine = _FakeEngine();
      final app = await start(engine: engine);
      engine.emit({
        'type': 'message',
        'account_id': firstRoute.accountId,
        'conversation_id': firstRoute.conversationId,
        'id': 'reply',
        'body': 'A reply',
        'timestamp': instant.millisecondsSinceEpoch,
        'sender_id': 'author',
        'reply_to_message_id': 'original',
      });
      await _eventually(() => app.messagesFor(firstRoute).isNotEmpty);
      engine.emit({
        'type': 'message_edit',
        'account_id': firstRoute.accountId,
        'conversation_id': firstRoute.conversationId,
        'id': 'reply',
        'body': 'Edited reply',
      });
      await _eventually(
        () => app.messagesFor(firstRoute).single.body == 'Edited reply',
      );
      final saved = await store.loadMessage(firstRoute, 'reply');
      expect(saved?.senderId, 'author');
      expect(saved?.replyToMessageId, 'original');
    },
  );

  test(
    'system notification denial keeps saved choices and restores on refresh',
    () async {
      final app = await start();
      await app.setPreference('notificationPreviews', false);
      await app.setPreference('notificationSound', false);
      final saved = Map<String, String>.of(secrets.values);
      native.notificationStatus = {
        'status': 'denied',
        'can_open_settings': true,
      };
      await app.refreshNotificationStatus();
      expect(
        app.notificationStatus.authorization,
        NotificationAuthorization.denied,
      );
      expect(app.notificationStatus.canConfigure, isFalse);
      expect(secrets.values, saved);
      await app.openNotificationSettings();
      expect(
        native.calls.where(
          (call) => call['method'] == 'openNotificationSettings',
        ),
        hasLength(1),
      );
      native.notificationStatus = {
        'status': 'allowed',
        'sound_enabled': true,
        'alerts_enabled': true,
        'badges_enabled': true,
      };
      await app.refreshNotificationStatus();
      expect(app.notificationStatus.canConfigure, isTrue);
      expect(app.notificationStatus.soundEnabled, isTrue);
      expect(app.preferences.notificationPreviews, isFalse);
      expect(app.preferences.notificationSound, isFalse);
      expect(secrets.values, saved);
    },
  );

  test('requesting notification permission refreshes denial without changing saved preference', () async {
    native.notificationStatus = {'status': 'not_determined'};
    final app = await start();
    await app.setPreference('notificationsEnabled', false);
    native.notificationStatusAfterRequest = {
      'status': 'denied',
      'can_open_settings': true,
    };
    await app.requestNotificationPermission();
    expect(
      app.notificationStatus.authorization,
      NotificationAuthorization.denied,
    );
    expect(app.preferences.notificationsEnabled, isFalse);
    native.notificationStatusAfterRequest = {
      'status': 'allowed',
      'sound_enabled': false,
    };
    await app.requestNotificationPermission();
    expect(
      app.notificationStatus.authorization,
      NotificationAuthorization.allowed,
    );
    expect(app.notificationStatus.soundEnabled, isFalse);
    expect(app.preferences.notificationsEnabled, isFalse);
  });

  test(
    'enabling notifications rechecks system permission after a denied prompt',
    () async {
      final app = await start();
      await app.setPreference('notificationsEnabled', false);
      native.notificationStatusAfterRequest = {'status': 'denied'};
      await app.setPreference('notificationsEnabled', true);
      expect(app.preferences.notificationsEnabled, isTrue);
      expect(
        app.notificationStatus.authorization,
        NotificationAuthorization.denied,
      );
      expect(app.error, isNull);
    },
  );

  test('unavailable and malformed notification status never claims system permission', () async {
    final app = await start();
    for (final value in [
      null,
      'PRIVATE_PERMISSION_DETAIL',
      {'status': 'future', 'sound_enabled': 'yes'},
    ]) {
      native.notificationStatus = value;
      await app.refreshNotificationStatus();
      expect(
        app.notificationStatus.authorization,
        NotificationAuthorization.unavailable,
      );
      expect(app.notificationStatus.soundEnabled, isNull);
      expect(app.notificationStatus.canOpenSettings, isFalse);
      expect(app.error, isNull);
    }
    await app.openNotificationSettings();
    expect(
      native.calls.where(
        (call) => call['method'] == 'openNotificationSettings',
      ),
      isEmpty,
    );
    native.failNotificationStatus = true;
    await app.refreshNotificationStatus();
    expect(
      app.notificationStatus.authorization,
      NotificationAuthorization.unavailable,
    );
    expect(app.error, isNull);
  });

  test(
    'an older notification permission read never replaces a newer result',
    () async {
      final app = await start();
      final old = Completer<Object?>();
      var reads = 0;
      native.notificationStatusReader = () {
        if (++reads == 1) return old.future;
        return Future<Object?>.value({
          'status': 'allowed',
          'sound_enabled': true,
        });
      };
      final pending = app.refreshNotificationStatus();
      await app.refreshNotificationStatus();
      old.complete({'status': 'denied'});
      await pending;
      expect(
        app.notificationStatus.authorization,
        NotificationAuthorization.allowed,
      );
      expect(app.notificationStatus.soundEnabled, isTrue);
      await closeController();
      native.calls.clear();
      await app.refreshNotificationStatus();
      expect(native.calls, isEmpty);
    },
  );

  test('notification activation consumes an account-scoped route and preserves both drafts', () async {
    await seed(firstRoute);
    await seed(secondRoute);
    final app = await start();
    app.updateDraft(firstRoute, 'First draft');
    app.updateDraft(secondRoute, 'Second draft');
    app.selectConversation(firstRoute);
    native.notificationRoute = {
      'account_id': secondRoute.accountId,
      'conversation_id': secondRoute.conversationId,
    };
    await app.openPendingNotification();
    expect(app.selectedRoute, secondRoute);
    expect(app.notificationActivation, 1);
    expect(app.draftFor(firstRoute)?.body, 'First draft');
    expect(app.draftFor(secondRoute)?.body, 'Second draft');
    await app.openPendingNotification();
    expect(app.notificationActivation, 1);
    native.notificationRoute = {
      'account_id': secondRoute.accountId,
      'conversation_id': secondRoute.conversationId,
    };
    await app.openPendingNotification();
    expect(app.notificationActivation, 2);
  });

  test('startup drains a pending notification only after stored conversations are loaded', () async {
    await seed(secondRoute);
    native.notificationRoute = {
      'account_id': secondRoute.accountId,
      'conversation_id': secondRoute.conversationId,
    };
    final app = await start();
    expect(app.selectedRoute, secondRoute);
    expect(app.notificationActivation, 1);
    expect(native.notificationRoute, isNull);
  });

  test('stale and malformed notification routes preserve selection without leaking details', () async {
    await seed(firstRoute);
    final app = await start();
    app.selectConversation(firstRoute);
    for (final value in [
      null,
      'PRIVATE_NOTIFICATION_DETAIL',
      {'account_id': 'first'},
      {'account_id': 1, 'conversation_id': 'same-chat'},
      {'account_id': '', 'conversation_id': 'same-chat'},
      {'account_id': 'deleted', 'conversation_id': 'same-chat'},
      {'account_id': 'first', 'conversation_id': 'deleted'},
    ]) {
      native.notificationRoute = value;
      await app.openPendingNotification();
      expect(app.selectedRoute, firstRoute);
      expect(app.notificationActivation, 0);
      expect(app.error, isNull);
    }
    native.failNotificationRoute = true;
    await app.openPendingNotification();
    expect(app.error, contains('notification could not be opened'));
    expect(app.error, isNot(contains('PRIVATE_NOTIFICATION_DETAIL')));
    native.failNotificationRoute = false;
    native.notificationRoute = {
      'account_id': 'first',
      'conversation_id': 'same-chat',
    };
    await app.openPendingNotification();
    expect(app.error, isNull);
    expect(app.notificationActivation, 1);
  });

  test(
    'notification callbacks drain in order while a native result is pending',
    () async {
      await seed(firstRoute);
      await seed(secondRoute);
      final app = await start();
      final first = Completer<Object?>();
      var calls = 0;
      native.notificationReader = () {
        calls++;
        if (calls == 1) return first.future;
        return Future<Object?>.value({
          'account_id': secondRoute.accountId,
          'conversation_id': secondRoute.conversationId,
        });
      };
      final opening = app.openPendingNotification();
      final following = app.openPendingNotification();
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
      first.complete({
        'account_id': firstRoute.accountId,
        'conversation_id': firstRoute.conversationId,
      });
      await Future.wait([opening, following]);
      expect(calls, 2);
      expect(app.selectedRoute, secondRoute);
      expect(app.notificationActivation, 2);
    },
  );

  test(
    'notification activation after closure never calls the native channel',
    () async {
      await seed(firstRoute);
      final app = await start();
      await closeController();
      native.calls.clear();
      await app.openPendingNotification();
      expect(native.calls, isEmpty);
    },
  );

  test(
    'notification preview and sound choices reach the operating system',
    () async {
      await seed(firstRoute);
      final engine = _FakeEngine();
      final app = await start(engine: engine);
      await app.setPreference('notificationPreviews', false);
      await app.setPreference('notificationSound', false);
      engine.emit({
        'type': 'message',
        'account_id': 'first',
        'conversation_id': 'same-chat',
        'id': 'incoming-private',
        'body': 'Synthetic private preview',
        'timestamp': instant.millisecondsSinceEpoch,
      });
      await _eventually(() => native.notifications.isNotEmpty);
      expect(native.notifications.single['body'], 'New message');
      expect(native.notifications.single['title'], 'Inbox+');
      expect(native.notifications.single['sound'], isFalse);
      await app.setPreference('notificationPreviews', true);
      await app.setPreference('notificationSound', true);
      engine.emit({
        'type': 'message',
        'account_id': 'first',
        'conversation_id': 'same-chat',
        'id': 'incoming-preview',
        'body': 'Synthetic visible preview',
        'timestamp': instant.millisecondsSinceEpoch + 1,
      });
      await _eventually(() => native.notifications.length == 2);
      expect(native.notifications.last['body'], 'Synthetic visible preview');
      expect(native.notifications.last['title'], 'Fixture conversation');
      expect(native.notifications.last['sound'], isTrue);
    },
  );

  test(
    'manual unread survives source refresh and selection clears it',
    () async {
      await seed(firstRoute);
      final engine = _FakeEngine();
      final app = await start(engine: engine);
      await app.setUnread(firstRoute, true);
      expect(app.conversations.single.unreadCount, 1);
      expect(app.preferencesFor(firstRoute).markedUnread, isTrue);
      engine.emit({
        'type': 'chat',
        'account_id': 'first',
        'id': 'same-chat',
        'unread_count': 0,
      });
      await _eventually(() => !app.isBusy);
      expect(app.conversations.single.unreadCount, 1);
      app.selectConversation(firstRoute);
      await _eventually(() => !app.preferencesFor(firstRoute).markedUnread);
      expect(app.conversations.single.unreadCount, 0);
      expect(
        (await store.loadConversationPreferences()).single.markedUnread,
        isFalse,
      );
    },
  );

  test('diagnostics contain component counts without private account or message data', () async {
    await seed(firstRoute);
    await store.saveMessage(
      MessageRecord(
        id: 'private-message-id',
        route: firstRoute,
        body: 'PRIVATE_BODY https://example.test/private-attachment',
        senderName: 'PRIVATE_PERSON',
        timestamp: instant,
        isOutgoing: false,
      ),
    );
    await store.saveDraft(firstRoute, 'PRIVATE_DRAFT');
    final app = await start(engine: _FakeEngine());
    final diagnostics = app.diagnosticsJson();
    final data = jsonDecode(diagnostics) as Map;
    expect((data['accounts'] as List).single, {
      'platform': 'whatsapp',
      'connected': true,
    });
    expect((data['storage'] as Map)['messages'], 1);
    for (final private in [
      'PRIVATE_BODY',
      'PRIVATE_PERSON',
      'PRIVATE_DRAFT',
      'private-message-id',
      'same-chat',
      'example.test',
      directory.path,
      'Fixture account',
    ]) {
      expect(diagnostics, isNot(contains(private)));
    }
  });

  test(
    'retention applies on the next launch and rejects older backfill',
    () async {
      await seed(firstRoute);
      await store.saveMessage(
        MessageRecord(
          id: 'three-days',
          route: firstRoute,
          body: 'Recent enough initially',
          timestamp: instant.subtract(const Duration(days: 3)),
          isOutgoing: false,
        ),
      );
      final app = await start(engine: _FakeEngine());
      await app.setPreference('messageRetentionDays', 1);
      expect(app.messagesFor(firstRoute), hasLength(1));
      await closeController();
      store = await LocalStore.open(file: database, key: key);
      storeClosed = false;
      final engine = _FakeEngine();
      final reopened = await start(engine: engine);
      expect(reopened.messagesFor(firstRoute), isEmpty);
      engine.emit({
        'type': 'message',
        'account_id': 'first',
        'conversation_id': 'same-chat',
        'id': 'old-backfill',
        'body': 'Too old',
        'historical': true,
        'timestamp': instant
            .subtract(const Duration(days: 2))
            .millisecondsSinceEpoch,
      });
      engine.emit({
        'type': 'message',
        'account_id': 'first',
        'conversation_id': 'same-chat',
        'id': 'recent',
        'body': 'Retained',
        'historical': true,
        'timestamp': instant.millisecondsSinceEpoch,
      });
      await _eventually(() => reopened.messagesFor(firstRoute).isNotEmpty);
      expect(reopened.messagesFor(firstRoute).single.id, 'recent');
      expect((await store.loadRecentMessages(firstRoute)).single.id, 'recent');
    },
  );

  test(
    'login setting reflects the system result and preserves state on failure',
    () async {
      final app = await start(engine: _FakeEngine());
      expect(app.launchAtLoginStatus, 'off');
      await app.setPreference('launchAtLogin', true);
      expect(app.launchAtLoginStatus, 'on');
      native.failLaunchAtLogin = true;
      await app.setPreference('launchAtLogin', false);
      expect(app.launchAtLoginStatus, 'on');
      expect(app.error, isNotNull);
    },
  );

  test('accounts with the same chat and message IDs remain isolated', () async {
    await seed(firstRoute);
    await seed(secondRoute);
    final engine = _FakeEngine();
    final app = await start(engine: engine);

    engine.emit({
      'type': 'message',
      'account_id': 'first',
      'conversation_id': 'same-chat',
      'id': 'same-message',
      'body': 'First account message',
      'timestamp': instant.millisecondsSinceEpoch,
      'historical': true,
    });
    engine.emit({
      'type': 'message',
      'account_id': 'second',
      'conversation_id': 'same-chat',
      'id': 'same-message',
      'body': 'Second account message',
      'timestamp': instant.millisecondsSinceEpoch,
      'historical': true,
    });
    await _eventually(
      () =>
          app.messagesFor(firstRoute).isNotEmpty &&
          app.messagesFor(secondRoute).isNotEmpty,
    );

    expect(app.messagesFor(firstRoute).single.body, 'First account message');
    expect(app.messagesFor(secondRoute).single.body, 'Second account message');
    expect(
      (await store.loadRecentMessages(firstRoute)).single.body,
      'First account message',
    );
    expect(
      (await store.loadRecentMessages(secondRoute)).single.body,
      'Second account message',
    );
    expect(native.notifications, isEmpty);
  });

  test('protocol message edits and deletions update only the matching account route', () async {
    await seed(firstRoute, platform: 'instagram');
    await seed(secondRoute, platform: 'instagram');
    const attachment = AttachmentRecord(
      id: 'fixture-media',
      kind: 'image',
      fileName: 'image.png',
    );
    for (final route in [firstRoute, secondRoute]) {
      await store.saveMessage(
        MessageRecord(
          id: 'editable',
          route: route,
          body: 'Original text',
          timestamp: instant,
          isOutgoing: false,
          senderName: 'Fixture sender',
          attachments: const [attachment],
        ),
      );
    }
    final engine = _FakeEngine();
    final app = await start(engine: engine);
    engine.emit({
      'type': 'message_edit',
      'account_id': 'first',
      'conversation_id': 'same-chat',
      'id': 'editable',
      'body': 'Edited text',
    });
    await _eventually(
      () => app.messagesFor(firstRoute).single.body == 'Edited text',
    );

    expect(app.messagesFor(firstRoute).single.timestamp, instant);
    expect(
      app.messagesFor(firstRoute).single.attachments.single.id,
      'fixture-media',
    );
    expect(app.messagesFor(secondRoute).single.body, 'Original text');
    engine.emit({
      'type': 'message_delete',
      'account_id': 'first',
      'conversation_id': 'same-chat',
      'id': 'editable',
    });
    await _eventually(() => app.messagesFor(firstRoute).isEmpty);
    expect(await store.loadRecentMessages(firstRoute), isEmpty);
    expect(
      (await store.loadRecentMessages(secondRoute)).single.body,
      'Original text',
    );
    expect(native.notifications, isEmpty);
  });

  test(
    'refresh imports WhatsApp chat snapshots returned by the connector',
    () async {
      await store.saveAccount(
        const AccountRecord(
          id: 'first',
          platform: 'whatsapp',
          displayName: 'WhatsApp fixture',
        ),
      );
      final engine = _FakeEngine(
        chats: [
          {
            'id': 'same-chat',
            'title': 'Restored WhatsApp conversation',
            'timestamp': instant.millisecondsSinceEpoch,
            'unread_count': 4,
            'is_group': true,
          },
        ],
      );
      final app = await start(engine: engine);

      expect(app.conversations.single.route, firstRoute);
      expect(app.conversations.single.title, 'Restored WhatsApp conversation');
      expect(app.conversations.single.unreadCount, 4);
      expect(app.conversations.single.isGroup, isTrue);
      expect(
        (await store.loadConversations()).single.title,
        'Restored WhatsApp conversation',
      );
      expect(
        engine.commands.where((command) => command['op'] == 'list_chats'),
        isNotEmpty,
      );
    },
  );

  test('live incoming messages increment unread once and selecting the conversation clears it', () async {
    await seed(firstRoute);
    await store.saveConversation(
      ConversationRecord(
        route: firstRoute,
        title: 'Conversation',
        latestActivity: instant,
        unreadCount: 2,
      ),
    );
    final engine = _FakeEngine();
    final app = await start(engine: engine);
    engine.emit({
      'type': 'message',
      'account_id': 'first',
      'conversation_id': 'same-chat',
      'id': 'historical',
      'body': 'Historic message',
      'timestamp': instant.millisecondsSinceEpoch,
      'historical': true,
    });
    await _eventually(() => app.messagesFor(firstRoute).isNotEmpty);
    expect(app.conversations.single.unreadCount, 2);
    final incoming = <String, Object?>{
      'type': 'message',
      'account_id': 'first',
      'conversation_id': 'same-chat',
      'id': 'live-message',
      'body': 'Live message',
      'timestamp': instant
          .add(const Duration(seconds: 1))
          .millisecondsSinceEpoch,
    };
    engine.emit(incoming);
    engine.emit(incoming);
    engine.emit({
      'type': 'message_edit',
      'account_id': 'first',
      'conversation_id': 'same-chat',
      'id': 'live-message',
      'body': 'Event queue reached marker',
    });
    await _eventually(
      () => app
          .messagesFor(firstRoute)
          .any((message) => message.body == 'Event queue reached marker'),
    );
    expect(app.conversations.single.unreadCount, 3);

    app.selectConversation(firstRoute);
    await _eventually(() => app.conversations.single.unreadCount == 0);
    expect((await store.loadConversations()).single.unreadCount, 0);
    engine.emit({...incoming, 'id': 'selected-live-message'});
    await _eventually(() => app.messagesFor(firstRoute).length == 3);
    expect(app.conversations.single.unreadCount, 0);
  });

  test('iMessage uses the selected profile and never clears a draft for pending native delivery', () async {
    native.imessageAvailable = true;
    native.imessageSnapshot = {
      'conversations': [
        {
          'id': 'local-chat',
          'title': 'Local fixture',
          'timestamp': instant.millisecondsSinceEpoch,
        },
      ],
      'messages': [],
    };
    native.imessageSendResult = {
      'id': 'native-pending',
      'timestamp': instant.millisecondsSinceEpoch,
      'delivery_state': 'pending',
    };
    final app = await start(profileName: 'work');
    expect(
      native.calls.where(
        (call) => (call['method'] as String).startsWith('imessage'),
      ),
      isEmpty,
    );

    await app.beginLogin('imessage');
    const route = ConversationRoute('imessage-local', 'local-chat');
    app.updateDraft(route, 'Pending Apple message');
    await app.sendDraft(route);

    expect(
      native.calls.where((call) => call['method'] == 'imessageSend'),
      hasLength(1),
    );
    final imessageCalls = native.calls.where(
      (call) => (call['method'] as String).startsWith('imessage'),
    );
    expect(
      imessageCalls.every(
        (call) => (call['arguments'] as Map)['profile_name'] == 'work',
      ),
      isTrue,
    );
    expect(app.draftFor(route)?.body, 'Pending Apple message');
    expect(
      (await store.loadPendingSends()).single.status,
      PendingSendStatus.unknown,
    );
    expect(
      app.messagesFor(route).single.deliveryState,
      isNot(DeliveryState.acknowledged),
    );
  });

  test('editing a draft during delivery preserves the newer revision after acknowledgement', () async {
    await seed(firstRoute);
    final response = Completer<Map<String, Object?>>();
    final started = Completer<void>();
    final engine = _FakeEngine(
      onSend: (_) {
        started.complete();
        return response.future;
      },
    );
    final app = await start(engine: engine);
    app.updateDraft(firstRoute, 'Send this revision');
    final send = app.sendDraft(firstRoute);
    await started.future;

    app.updateDraft(firstRoute, 'Keep this newer revision');
    await _eventually(() => !app.isLoading);
    response.complete({
      'id': 'remote-ack',
      'timestamp': instant.millisecondsSinceEpoch,
    });
    await send;

    expect(app.error, isNull);
    expect(engine.sends.single['body'], 'Send this revision');
    expect(app.draftFor(firstRoute)?.body, 'Keep this newer revision');
    expect(
      (await store.loadDraft(firstRoute))?.body,
      'Keep this newer revision',
    );
    expect(await store.loadPendingSends(), isEmpty);
    expect(app.messagesFor(firstRoute).single.id, 'remote-ack');
    expect(
      app.messagesFor(firstRoute).single.deliveryState,
      DeliveryState.acknowledged,
    );
  });

  test(
    'repeated Send while offline queues one durable command per draft revision',
    () async {
      await seed(firstRoute);
      final engine = _FakeEngine(connectState: 'disconnected');
      final app = await start(engine: engine);
      app.updateDraft(firstRoute, 'Queued once');

      await Future.wait([app.sendDraft(firstRoute), app.sendDraft(firstRoute)]);
      await app.sendDraft(firstRoute);

      expect(app.isOffline, isTrue);
      expect(engine.sends, isEmpty);
      expect(await store.loadPendingSends(), hasLength(1));
      expect(app.messagesFor(firstRoute), hasLength(1));
      expect(app.draftFor(firstRoute)?.body, 'Queued once');

      await closeController();
      store = await LocalStore.open(file: database, key: key);
      storeClosed = false;
      final reopened = await start(
        engine: _FakeEngine(connectState: 'disconnected'),
      );
      expect(reopened.draftFor(firstRoute)?.body, 'Queued once');
      expect(reopened.messagesFor(firstRoute), hasLength(1));
      expect(
        (await store.loadPendingSends()).single.status,
        PendingSendStatus.queued,
      );
    },
  );

  test('uncertain delivery keeps the draft and never resends automatically or through Retry', () async {
    await seed(firstRoute);
    const secret = 'private-token-that-must-not-escape';
    final engine = _FakeEngine(
      onSend: (_) async {
        throw const ConnectorException(secret);
      },
    );
    final app = await start(engine: engine);
    app.updateDraft(firstRoute, 'Private fixture body');
    await app.sendDraft(firstRoute);

    final pending = (await store.loadPendingSends()).single;
    expect(pending.status, PendingSendStatus.unknown);
    expect(app.error, contains('Delivery could not be confirmed'));
    expect(app.error, isNot(contains(secret)));
    expect(app.error, isNot(contains('Private fixture body')));
    expect(app.draftFor(firstRoute)?.body, 'Private fixture body');
    expect(
      app.messagesFor(firstRoute).single.deliveryState,
      DeliveryState.failed,
    );

    await app.refresh();
    await app.retryMessage(firstRoute, pending.id);
    expect(engine.sends, hasLength(1));
    expect(app.error, contains('unconfirmed'));
    expect(
      (await store.loadPendingSends()).single.status,
      PendingSendStatus.unknown,
    );
  });

  test('a send interrupted by restart becomes unknown and is not transmitted on reconnect', () async {
    await seed(firstRoute);
    await store.saveDraft(firstRoute, 'Interrupted delivery');
    await store.enqueueDraft(firstRoute, sendId: 'interrupted-send');
    await store.savePendingSendStatus(
      'interrupted-send',
      PendingSendStatus.sending,
    );
    final engine = _FakeEngine();
    final app = await start(engine: engine);

    expect(
      (await store.loadPendingSends()).single.status,
      PendingSendStatus.unknown,
    );
    expect(engine.sends, isEmpty);
    expect(app.draftFor(firstRoute)?.body, 'Interrupted delivery');
  });

  test('confirming an uncertain message was not sent retains its command and waits for explicit Retry', () async {
    await seed(firstRoute);
    await store.saveDraft(firstRoute, 'Checked draft');
    await store.enqueueDraft(firstRoute, sendId: 'checked-send');
    await store.savePendingSendStatus(
      'checked-send',
      PendingSendStatus.unknown,
    );
    final engine = _FakeEngine();
    final app = await start(engine: engine);

    expect(app.isDeliveryUnconfirmed(firstRoute, 'checked-send'), isTrue);
    await app.resolveUnconfirmedSend(
      firstRoute,
      'checked-send',
      wasSent: false,
    );
    expect(engine.sends, isEmpty);
    expect(
      (await store.loadPendingSends()).single.status,
      PendingSendStatus.failed,
    );
    expect(app.draftFor(firstRoute)?.body, 'Checked draft');
    expect(app.isDeliveryUnconfirmed(firstRoute, 'checked-send'), isFalse);

    await app.refresh();
    expect(engine.sends, isEmpty);
    await app.retryMessage(firstRoute, 'checked-send');
    expect(engine.sends, hasLength(1));
    expect(await store.loadPendingSends(), isEmpty);
    expect(app.draftFor(firstRoute)?.body ?? '', isEmpty);
  });

  test('confirming non-delivery retains the earlier payload while a newer draft stays editable', () async {
    await seed(firstRoute);
    await store.saveDraft(firstRoute, 'Earlier unsent message');
    await store.enqueueDraft(firstRoute, sendId: 'earlier-uncertain');
    await store.savePendingSendStatus(
      'earlier-uncertain',
      PendingSendStatus.unknown,
    );
    final engine = _FakeEngine();
    final app = await start(engine: engine);
    app.updateDraft(firstRoute, 'Newer draft stays');

    await app.resolveUnconfirmedSend(
      firstRoute,
      'earlier-uncertain',
      wasSent: false,
    );
    final pending = (await store.loadPendingSends()).single;
    expect(pending.body, 'Earlier unsent message');
    expect(pending.status, PendingSendStatus.failed);
    expect(engine.sends, isEmpty);
    expect(app.draftFor(firstRoute)?.body, 'Newer draft stays');
    expect((await store.loadDraft(firstRoute))?.body, 'Newer draft stays');

    await app.retryMessage(firstRoute, 'earlier-uncertain');
    expect(engine.sends.single['body'], 'Earlier unsent message');
    expect(await store.loadPendingSends(), isEmpty);
    expect(app.draftFor(firstRoute)?.body, 'Newer draft stays');
    expect((await store.loadDraft(firstRoute))?.body, 'Newer draft stays');
  });

  test('confirming uncertain delivery was sent clears that captured draft without transmitting', () async {
    await seed(firstRoute);
    await store.saveDraft(firstRoute, 'Confirmed in original app');
    await store.enqueueDraft(firstRoute, sendId: 'verified-send');
    await store.savePendingSendStatus(
      'verified-send',
      PendingSendStatus.unknown,
    );
    final engine = _FakeEngine();
    final app = await start(engine: engine);

    await app.resolveUnconfirmedSend(
      firstRoute,
      'verified-send',
      wasSent: true,
    );
    expect(engine.sends, isEmpty);
    expect(await store.loadPendingSends(), isEmpty);
    expect(app.draftFor(firstRoute)?.body ?? '', isEmpty);
    expect(app.isDeliveryUnconfirmed(firstRoute, 'verified-send'), isFalse);
  });

  test('manual delivery confirmation cannot erase a newer draft or a different account command', () async {
    await seed(firstRoute);
    await seed(secondRoute);
    await store.saveDraft(firstRoute, 'Earlier sent draft');
    await store.enqueueDraft(firstRoute, sendId: 'first-uncertain');
    await store.savePendingSendStatus(
      'first-uncertain',
      PendingSendStatus.unknown,
    );
    final engine = _FakeEngine();
    final app = await start(engine: engine);

    await app.resolveUnconfirmedSend(
      secondRoute,
      'first-uncertain',
      wasSent: true,
    );
    expect(await store.loadPendingSends(), hasLength(1));
    app.updateDraft(firstRoute, 'New draft stays');
    await app.resolveUnconfirmedSend(
      firstRoute,
      'first-uncertain',
      wasSent: true,
    );
    expect(engine.sends, isEmpty);
    expect(await store.loadPendingSends(), isEmpty);
    expect(app.draftFor(firstRoute)?.body, 'New draft stays');
    expect((await store.loadDraft(firstRoute))?.body, 'New draft stays');
  });

  test(
    'a confirmed delivery clears only its captured draft and pending command',
    () async {
      await seed(firstRoute);
      final engine = _FakeEngine();
      final app = await start(engine: engine);
      app.updateDraft(firstRoute, 'Confirmed message');
      await app.sendDraft(firstRoute);

      expect(app.error, isNull);
      expect(app.draftFor(firstRoute)?.body ?? '', isEmpty);
      expect((await store.loadDraft(firstRoute))?.body ?? '', isEmpty);
      expect(await store.loadPendingSends(), isEmpty);
      expect(app.messagesFor(firstRoute).single.body, 'Confirmed message');
      await app.refresh();
      expect(engine.sends, hasLength(1));
    },
  );

  test(
    'legacy routes are retained without opening them with a direct connector',
    () async {
      const route = ConversationRoute(
        'legacy:matrix-account',
        '!legacy-room:localhost',
      );
      await seed(route, platform: 'legacy');
      final engine = _FakeEngine();
      final app = await start(engine: engine);

      expect(app.conversations.single.route, route);
      expect(
        engine.commands.where(
          (command) => command['account_id'] == route.accountId,
        ),
        isEmpty,
      );
      expect(app.accounts.single.isConnected, isFalse);
    },
  );

  test('unsupported encrypted conversations retain the draft without queueing a send', () async {
    await seed(firstRoute, platform: 'messenger');
    await store.saveConversation(
      ConversationRecord(
        route: firstRoute,
        title: 'Protected conversation',
        latestActivity: instant,
        canSend: false,
        sendingUnavailableReason:
            'Open Messenger to reply to this encrypted chat.',
      ),
    );
    final engine = _FakeEngine();
    final app = await start(engine: engine);
    app.updateDraft(firstRoute, 'Keep this draft');
    await app.sendDraft(firstRoute);

    expect(
      app.sendingUnavailableReason(firstRoute),
      contains('encrypted chat'),
    );
    expect(engine.sends, isEmpty);
    expect(await store.loadPendingSends(), isEmpty);
    expect((await store.loadDraft(firstRoute))?.body, 'Keep this draft');
  });

  test('unsupported conversations never flush an earlier queued message on reconnect', () async {
    await seed(firstRoute, platform: 'messenger');
    await store.saveConversation(
      ConversationRecord(
        route: firstRoute,
        title: 'Protected conversation',
        latestActivity: instant,
        canSend: false,
        sendingUnavailableReason:
            'Open Messenger to reply to this encrypted chat.',
      ),
    );
    await store.saveDraft(firstRoute, 'Previously queued message');
    await store.enqueueDraft(firstRoute, sendId: 'protected-queued');
    final engine = _FakeEngine();
    final app = await start(engine: engine);
    await _eventually(() => !app.isBusy);

    expect(engine.sends, isEmpty);
    expect(
      (await store.loadPendingSends()).single.status,
      PendingSendStatus.failed,
    );
    expect(
      (await store.loadDraft(firstRoute))?.body,
      'Previously queued message',
    );
    expect(app.sendingUnavailableReason(firstRoute), isNotNull);
  });

  group('attachment export', () {
    late FilePickerPlatform originalPicker;
    late _SavePicker picker;

    setUp(() {
      originalPicker = FilePickerPlatform.instance;
      FilePickerPlatform.instance = picker = _SavePicker();
    });

    tearDown(() => FilePickerPlatform.instance = originalPicker);

    Future<File> receive({
      String? name = 'Itinerary.txt',
      String mime = 'text/plain',
      String? path,
    }) async {
      await seed(firstRoute);
      final source = File(path ?? '${directory.path}/media/itinerary.txt');
      await source.parent.create(recursive: true);
      await source.writeAsBytes([0, 255, 42, 13, 10]);
      await store.saveMessage(
        MessageRecord(
          id: 'received-file',
          route: firstRoute,
          body: 'Synthetic attachment',
          timestamp: instant,
          isOutgoing: false,
          attachments: [
            AttachmentRecord(
              id: 'file',
              kind: 'file',
              fileName: name,
              mimeType: mime,
              localPath: source.path,
              isDownloadable: false,
            ),
          ],
        ),
      );
      return source;
    }

    test(
      'copies original local-only bytes and preserves source and draft',
      () async {
        final source = await receive();
        final destination = File('${directory.path}/export/selected.txt');
        picker.destination = destination;
        final app = await start();
        app.updateDraft(firstRoute, 'Keep this draft');
        await app.saveAttachment(firstRoute, 'received-file', 'file');

        expect(app.error, isNull);
        expect(picker.fileName, 'Itinerary.txt');
        expect(picker.mimeType, 'text/plain');
        expect(picker.dialogTitle, 'Save Attachment');
        expect(await destination.readAsBytes(), [0, 255, 42, 13, 10]);
        expect(await source.readAsBytes(), [0, 255, 42, 13, 10]);
        expect((await store.loadDraft(firstRoute))?.body, 'Keep this draft');
        expect(
          (await store.loadMessage(
            firstRoute,
            'received-file',
          ))?.attachments.single.localPath,
          source.path,
        );
      },
    );

    test(
      'cancel and failed save preserve the source and allow retry',
      () async {
        final source = await receive();
        final app = await start();
        await app.saveAttachment(firstRoute, 'received-file', 'file');
        expect(app.error, isNull);
        expect(await source.exists(), isTrue);

        picker.fail = true;
        await app.saveAttachment(firstRoute, 'received-file', 'file');
        expect(app.error, isNotNull);
        expect(app.error, isNot(contains('PRIVATE_SAVE_DETAIL')));
        expect(await source.readAsBytes(), [0, 255, 42, 13, 10]);

        picker.fail = false;
        picker.destination = File('${directory.path}/retry.txt');
        await app.saveAttachment(firstRoute, 'received-file', 'file');
        expect(app.error, isNull);
        expect(await picker.destination!.readAsBytes(), [0, 255, 42, 13, 10]);
      },
    );

    test('missing or oversized sources never open a save dialog', () async {
      final source = await receive();
      final app = await start();
      final output = await source.open(mode: FileMode.write);
      await output.truncate(32 * 1024 * 1024 + 1);
      await output.close();
      await app.saveAttachment(firstRoute, 'received-file', 'file');
      expect(app.error, contains('size limit'));
      expect(picker.calls, 0);

      await source.delete();
      await app.saveAttachment(firstRoute, 'received-file', 'file');
      expect(app.error, contains('no longer available'));
      expect(picker.calls, 0);
    });

    test(
      'outside-profile paths and symlink escapes never open a save dialog',
      () async {
        final outside = await Directory.systemTemp.createTemp(
          'inboxplus-export-source-',
        );
        addTearDown(() => outside.delete(recursive: true));
        final source = await receive(path: '${outside.path}/outside.txt');
        final app = await start();
        await app.saveAttachment(firstRoute, 'received-file', 'file');
        expect(app.error, contains('outside the private attachment store'));
        expect(picker.calls, 0);

        if (!Platform.isWindows) {
          final link = Link('${directory.path}/escape.txt');
          await link.create(source.path);
          final message = (await store.loadMessage(
            firstRoute,
            'received-file',
          ))!;
          await store.saveMessage(
            MessageRecord(
              id: message.id,
              route: message.route,
              body: message.body,
              timestamp: message.timestamp,
              isOutgoing: false,
              attachments: [
                AttachmentRecord(
                  id: 'file',
                  kind: 'file',
                  localPath: link.path,
                ),
              ],
            ),
          );
          await app.saveAttachment(firstRoute, 'received-file', 'file');
          expect(app.error, contains('outside the private attachment store'));
          expect(picker.calls, 0);
        }
      },
    );

    for (final example in [
      (
        name: r'C:\sender\Itinerary.txt',
        mime: 'text/plain',
        expected: 'Itinerary.txt',
      ),
      (name: '../../photo?.png', mime: 'image/png', expected: 'photo_.png'),
      (name: null, mime: 'image/png', expected: 'Attachment.png'),
    ]) {
      test('proposes a usable filename for ${example.name}', () async {
        await receive(name: example.name, mime: example.mime);
        final app = await start();
        await app.saveAttachment(firstRoute, 'received-file', 'file');
        expect(app.error, isNull);
        expect(picker.fileName, example.expected);
      });
    }
  });

  test(
    'removing an account signs out first and deletes its downloads',
    () async {
      await seed(firstRoute);
      await seed(secondRoute);
      final media = await Directory.fromUri(directory.uri.resolve('media/'))
          .create();
      final download = await File.fromUri(media.uri.resolve('download'))
          .writeAsString('x');
      await store.saveMessage(
        MessageRecord(
          id: 'with-download',
          route: firstRoute,
          body: 'Synthetic attachment',
          timestamp: instant,
          isOutgoing: false,
          attachments: [
            AttachmentRecord(
              id: 'file',
              kind: 'file',
              localPath: download.path,
            ),
          ],
        ),
      );
      final engine = _FakeEngine();
      final app = await start(engine: engine);
      await app.disconnectAccount('first');
      engine.commands.clear();
      await app.removeAccount('first');

      expect(
        engine.commands
            .where((c) => c['account_id'] == 'first')
            .map((c) => c['op'])
            .where((op) => op != 'initialize'),
        ['connect', 'logout', 'cancel', 'close'],
      );
      expect(app.error, isNull);
      expect(await download.exists(), isFalse);
      expect(app.accounts.map((a) => a.id), ['second']);
      expect(app.preferences.disconnectedAccountIds, isEmpty);
      expect(app.isChangingAccount('first'), isFalse);

      engine.failLogout = true;
      await app.removeAccount('second');
      expect(app.accounts, isEmpty);
      expect(app.error, contains('could not sign out of'));
      expect(
        app.error,
        contains('may still list Inbox+ as a signed-in device'),
      );
    },
  );

  test('connection reports become account network problems', () async {
    await seed(firstRoute);
    final engine = _FakeEngine();
    final app = await start(engine: engine);
    for (final (state, problem) in [
      ('connecting', AccountNetworkProblem.connecting),
      ('disconnected', AccountNetworkProblem.reconnecting),
      ('logged_out', AccountNetworkProblem.signedOut),
      ('error', AccountNetworkProblem.failed),
      ('connected', null),
    ]) {
      engine.emit({
        'type': 'connection',
        'account_id': 'first',
        'state': state,
      });
      await _eventually(() => app.networkProblem('first') == problem);
    }
  });

  for (final platform in ['instagram', 'messenger']) {
    test(
      '$platform removal warns that a local logout leaves the remote session',
      () async {
        await seed(firstRoute, platform: platform);
        final app = await start(engine: _FakeEngine());
        await app.removeAccount(firstRoute.accountId);
        expect(app.accounts, isEmpty);
        expect(
          app.error,
          contains('may still list Inbox+ as a signed-in device'),
        );
        expect(await store.loadAccounts(), isEmpty);
      },
    );
  }

  test('offline removal cannot claim a remote session was revoked', () async {
    await seed(firstRoute);
    final app = await start();
    await app.removeAccount(firstRoute.accountId);
    expect(app.accounts, isEmpty);
    expect(app.error, contains('could not sign out of'));
  });

  test('disconnect keeps history and drafts and stays paused until an explicit reconnect', () async {
    await seed(firstRoute);
    await store.saveMessage(
      MessageRecord(
        id: 'retained',
        route: firstRoute,
        body: 'Synthetic history',
        timestamp: instant,
        isOutgoing: false,
      ),
    );
    await store.saveDraft(firstRoute, 'Keep this unsent draft');
    final app = await start(engine: _FakeEngine());
    await app.disconnectAccount('first');
    expect(app.accounts.single.isConnected, isFalse);
    expect(app.preferences.disconnectedAccountIds, ['first']);
    await closeController();
    store = await LocalStore.open(file: database, key: key);
    storeClosed = false;
    final engine = _FakeEngine();
    final reopened = await start(engine: engine);
    expect(engine.commands.where((c) => c['op'] == 'connect'), isEmpty);
    expect(reopened.accounts.single.isConnected, isFalse);
    expect(reopened.messagesFor(firstRoute).single.id, 'retained');
    expect(reopened.draftFor(firstRoute)!.body, 'Keep this unsent draft');
    await reopened.reconnectAccount('first');
    expect(reopened.accounts.single.isConnected, isTrue);
    expect(reopened.preferences.disconnectedAccountIds, isEmpty);
    expect(reopened.accounts.single.id, 'first');
  });

  test('reconnecting reuses the account and preserves its local draft and conversation choices', () async {
    await seed(firstRoute);
    await store.saveDraft(firstRoute, 'Existing account draft');
    await store.saveConversationPreferences(
      const ConversationPreferencesRecord(
        route: firstRoute,
        isFavorite: true,
        isMuted: true,
      ),
    );
    final engine = _FakeEngine(connectState: 'disconnected');
    final app = await start(engine: engine);
    engine.connectState = 'connected';
    await app.reconnectAccount(firstRoute.accountId);

    expect(app.error, isNull);
    expect(app.accounts, hasLength(1));
    expect(app.accounts.single.id, 'first');
    expect(app.accounts.single.isConnected, isTrue);
    expect((await store.loadAccounts()).single.id, 'first');
    expect(app.draftFor(firstRoute)?.body, 'Existing account draft');
    expect(app.preferencesFor(firstRoute).isFavorite, isTrue);
    expect(app.preferencesFor(firstRoute).isMuted, isTrue);
    expect(app.login?.step, LoginStep.complete);
  });

  test(
    'canceling new account setup removes the empty unauthenticated account',
    () async {
      final engine = _FakeEngine(connectState: 'phone');
      final app = await start(engine: engine);
      await app.beginLogin('telegram');
      final accountId = app.accounts.single.id;
      expect(await store.loadAccounts(), hasLength(1));

      await app.cancelLogin();

      expect(app.login, isNull);
      expect(app.accounts, isEmpty);
      expect(await store.loadAccounts(), isEmpty);
      expect(
        engine.commands
            .where((command) => command['op'] == 'close')
            .single['account_id'],
        accountId,
      );
      expect(secrets.values, isEmpty);
    },
  );

  test('canceling reconnect preserves an existing account without a current session', () async {
    await seed(firstRoute);
    await store.saveDraft(firstRoute, 'Keep the existing draft');
    final engine = _FakeEngine(connectState: 'disconnected');
    final app = await start(engine: engine);
    await app.reconnectAccount(firstRoute.accountId);

    await app.cancelLogin();

    expect(app.accounts.single.id, firstRoute.accountId);
    expect((await store.loadAccounts()).single.id, firstRoute.accountId);
    expect(
      (await store.loadDraft(firstRoute))?.body,
      'Keep the existing draft',
    );
    expect(app.conversations.single.route, firstRoute);
  });

  test('canceling setup preserves a native session saved before its connection event', () async {
    final engine = _FakeEngine(connectState: 'phone', hasSessionOnClose: true);
    final app = await start(engine: engine);
    await app.beginLogin('telegram');
    final account = app.accounts.single;
    expect(account.isConnected, isFalse);

    await app.cancelLogin();

    expect(app.accounts.single.id, account.id);
    expect((await store.loadAccounts()).single.id, account.id);
    expect(secrets.values, isNotEmpty);
  });

  test('canceling while secure setup is in progress waits before removing the new account', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    final engine = _FakeEngine(
      onInitialize: () {
        started.complete();
        return release.future;
      },
    );
    final app = await start(engine: engine);
    final login = app.beginLogin('telegram');
    await started.future;

    final cancellation = app.cancelLogin();
    release.complete();
    await Future.wait([login, cancellation]);

    expect(app.error, isNull);
    expect(app.accounts, isEmpty);
    expect(await store.loadAccounts(), isEmpty);
    expect(
      engine.commands.where((command) => command['op'] == 'connect'),
      isEmpty,
    );
    expect(secrets.values, isEmpty);
  });

  test('canceling private web login removes the abandoned setup without a late error', () async {
    final engine = _FakeEngine();
    final app = await start(engine: engine);
    native.webLoginResponse = Completer<Object?>();
    final login = app.beginLogin('messenger');
    await _eventually(() => native.webLoginActive);

    await app.cancelLogin();
    await login;

    expect(app.error, isNull);
    expect(app.login, isNull);
    expect(app.accounts, isEmpty);
    expect(await store.loadAccounts(), isEmpty);
    expect(secrets.values, isEmpty);
  });

  test(
    'canceling before setup starts cannot leave an account behind',
    () async {
      final engine = _FakeEngine();
      final app = await start(engine: engine);

      final login = app.beginLogin('telegram');
      await app.cancelLogin();
      await login;

      expect(app.login, isNull);
      expect(app.accounts, isEmpty);
      expect(await store.loadAccounts(), isEmpty);
      expect(
        engine.commands.where((command) => command['op'] == 'initialize'),
        isEmpty,
      );
    },
  );

  test(
    'two simultaneous setup choices start only the latest account',
    () async {
      final engine = _FakeEngine();
      final app = await start(engine: engine);

      await Future.wait([
        app.beginLogin('whatsapp'),
        app.beginLogin('telegram'),
      ]);

      expect(app.accounts.single.platform, 'telegram');
      expect((await store.loadAccounts()).single.platform, 'telegram');
      expect(
        engine.commands.where((command) => command['op'] == 'initialize'),
        hasLength(1),
      );
    },
  );

  test('canceling setup preserves conversations and drafts already received for the new account', () async {
    final engine = _FakeEngine(connectState: 'phone');
    final app = await start(engine: engine);
    await app.beginLogin('telegram');
    final id = app.accounts.single.id;
    final route = ConversationRoute(id, 'received-chat');
    engine.emit({
      'type': 'chat',
      'account_id': id,
      'id': route.conversationId,
      'title': 'Received conversation',
      'timestamp': instant.millisecondsSinceEpoch,
    });
    await _eventually(() => app.conversations.isNotEmpty);
    app.updateDraft(route, 'Keep this work');

    await app.cancelLogin();

    expect(app.accounts.single.id, id);
    expect((await store.loadAccounts()).single.id, id);
    expect((await store.loadDraft(route))?.body, 'Keep this work');
    expect(app.conversations.single.route, route);
  });

  test(
    'canceling setup preserves an account if native session status is unknown',
    () async {
      final engine = _FakeEngine(
        connectState: 'phone',
        hasSessionOnClose: null,
      );
      final app = await start(engine: engine);
      await app.beginLogin('telegram');
      final id = app.accounts.single.id;

      await app.cancelLogin();

      expect(app.accounts.single.id, id);
      expect((await store.loadAccounts()).single.id, id);
      expect(secrets.values, isNotEmpty);
    },
  );

  test('missing native messaging leaves encrypted cached history and drafts usable', () async {
    await seed(firstRoute);
    await store.saveMessage(
      MessageRecord(
        id: 'cached-message',
        route: firstRoute,
        body: 'Cached history',
        timestamp: instant,
        isOutgoing: false,
      ),
    );
    await store.saveDraft(firstRoute, 'Saved draft');
    final app = await start();

    expect(app.isOffline, isTrue);
    expect(app.accounts.single.isConnected, isFalse);
    expect(app.conversations.single.route, firstRoute);
    expect(app.messagesFor(firstRoute).single.body, 'Cached history');
    expect(app.draftFor(firstRoute)?.body, 'Saved draft');
    expect(app.networks.where((network) => network.available), isEmpty);
    expect(app.networks, hasLength(8));
    expect(
      app.networks.map((network) => network.id),
      isNot(contains('imessage')),
    );
    expect(
      app.networks.map((network) => network.id),
      isNot(contains('matrix')),
    );
    expect(app.networks.map((network) => network.id), isNot(contains('x')));
    expect(
      app.networks
          .where((network) => network.comingSoon)
          .map((network) => network.id),
      ['slack'],
    );

    app.updateDraft(firstRoute, 'Edited offline');
    await app.sendDraft(firstRoute);
    expect((await store.loadDraft(firstRoute))?.body, 'Edited offline');
    expect(
      (await store.loadPendingSends()).single.status,
      PendingSendStatus.queued,
    );
  });

  test(
    'Telegram setup advances through credentials, phone, code and password',
    () async {
      final engine = _FakeEngine(connectState: 'phone');
      final app = await start(engine: engine);
      await app.beginLogin('telegram');
      expect(app.login?.fields.map((field) => field.id), [
        'api_id',
        'api_hash',
      ]);

      await app.submitLogin({
        'api_id': '12345',
        'api_hash': '0123456789abcdef0123456789abcdef',
      });
      expect(app.login?.fields.single.id, 'phone');
      await app.submitLogin({'phone': '+12025550123'});
      expect(app.login?.fields.single.id, 'code');
      await app.submitLogin({'code': '12345'});
      expect(app.login?.fields.single.id, 'password');
      await app.submitLogin({'password': 'fixture-password'});
      expect(app.login?.step, LoginStep.complete);
      expect(
        engine.commands
            .where((command) => command['op'] == 'login_password')
            .single['password'],
        'fixture-password',
      );
      expect(app.error, isNull);
    },
  );
}

Future<void> _eventually(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Controller did not reach the expected fixture state.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

class _MemorySecrets implements SecretStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class _SavePicker extends FilePickerPlatform {
  File? destination;
  bool fail = false;
  int calls = 0;
  String? fileName;
  String? mimeType;
  String? dialogTitle;

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    calls++;
    this.fileName = fileName;
    this.mimeType = mimeType;
    this.dialogTitle = dialogTitle;
    if (fail) {
      throw PlatformException(
        code: 'save_failed',
        message: 'PRIVATE_SAVE_DETAIL',
      );
    }
    final target = destination;
    if (target == null) return null;
    await target.parent.create(recursive: true);
    await target.writeAsBytes(bytes);
    return target.uri;
  }
}

class _NativeFixture {
  bool loginBackgroundExpired = false;
  bool photosDenied = false;
  bool launchAtLogin = false;
  bool failLaunchAtLogin = false;
  var imessageAvailable = false;
  Object? recipientSnapshot = {'status': 'available', 'recipients': []};
  bool failRecipientContacts = false;
  Map<String, Object?> imessageStartResult = {};
  Map<String, Object?> imessageSnapshot = {'conversations': [], 'messages': []};
  Map<String, Object?> imessageSendResult = {};
  final notifications = <Map<String, Object?>>[];
  Object? notificationRoute;
  bool failNotificationRoute = false;
  Object? notificationStatus = {'status': 'allowed', 'sound_enabled': true};
  Object? notificationStatusAfterRequest;
  bool failNotificationStatus = false;
  Future<Object?> Function()? notificationStatusReader;
  Future<Object?> Function()? notificationReader;
  final calls = <Map<String, Object?>>[];
  Completer<Object?>? webLoginResponse;
  bool webLoginActive = false;
  Future<Object?> call(String method, Map<String, Object?> arguments) async {
    calls.add({
      'method': method,
      'arguments': Map<String, Object?>.of(arguments),
    });
    switch (method) {
      case 'loginBackgroundStatus':
        return {'expired': loginBackgroundExpired};
      case 'saveLoginQr':
        if (photosDenied) {
          throw PlatformException(code: 'photos_denied');
        }
        return true;
      case 'capabilities':
        return {
          'web_login_platforms': ['instagram', 'messenger'],
          'imessage': imessageAvailable,
          'launch_at_login_status': launchAtLogin ? 'on' : 'off',
        };
      case 'setLaunchAtLogin':
        if (failLaunchAtLogin) {
          throw PlatformException(code: 'launch_at_login_failed');
        }
        launchAtLogin = arguments['enabled'] as bool;
        return {'status': launchAtLogin ? 'on' : 'off'};
      case 'imessageSnapshot':
        return imessageSnapshot;
      case 'imessageRecipientContacts':
        if (failRecipientContacts) {
          throw PlatformException(
            code: 'contacts_failed',
            message: 'PRIVATE_CONTACT_DETAIL',
          );
        }
        return recipientSnapshot;
      case 'imessageStartConversation':
        return imessageStartResult;
      case 'imessageSend':
        return imessageSendResult;
      case 'webLogin':
        webLoginActive = true;
        return webLoginResponse?.future;
      case 'cancelWebLogin':
        if (webLoginActive && webLoginResponse?.isCompleted == false) {
          webLoginActive = false;
          webLoginResponse!.completeError(
            PlatformException(code: 'login_cancelled'),
          );
        }
        return null;
      case 'notify':
        notifications.add(arguments);
        return null;
      case 'notificationStatus':
        if (notificationStatusReader != null) {
          return notificationStatusReader!();
        }
        if (failNotificationStatus) {
          throw PlatformException(
            code: 'status_failed',
            message: 'PRIVATE_PERMISSION_DETAIL',
          );
        }
        return notificationStatus;
      case 'requestNotificationPermission':
        notificationStatus =
            notificationStatusAfterRequest ?? notificationStatus;
        return notificationStatus is Map &&
            (notificationStatus as Map)['status'] == 'allowed';
      case 'takeNotificationRoute':
        if (notificationReader != null) return notificationReader!();
        if (failNotificationRoute) {
          throw PlatformException(
            code: 'notification_failed',
            message: 'PRIVATE_NOTIFICATION_DETAIL',
          );
        }
        final route = notificationRoute;
        notificationRoute = null;
        return route;
      default:
        return null;
    }
  }
}

class _FakeEngine implements ConnectorEngine {
  final platforms = <String, String>{};
  _FakeEngine({
    this.connectState = 'connected',
    this.hasSessionOnClose = false,
    this.onInitialize,
    this.onSend,
    this.onReact,
    this.chats = const [],
    this.additionalPlatforms = const [],
    this.onConnect,
    this.onPairPhone,
  });
  String connectState;
  bool failLogout = false;
  bool? hasSessionOnClose;
  final Future<void> Function()? onInitialize;
  final List<String> additionalPlatforms;
  final Future<Map<String, Object?>> Function(Map<String, Object?>)? onConnect;
  final Future<Map<String, Object?>> Function(Map<String, Object?>)?
  onPairPhone;
  final List<Map<String, Object?>> chats;
  final Future<Map<String, Object?>> Function(Map<String, Object?>)? onSend;
  final Future<Map<String, Object?>> Function(Map<String, Object?>)? onReact;
  final commands = <Map<String, Object?>>[];
  final _events = StreamController<ConnectorEvent>.broadcast();

  List<Map<String, Object?>> get sends => commands
      .where(
        (command) =>
            command['op'] == 'send_text' || command['op'] == 'send_attachment',
      )
      .toList();
  void emit(ConnectorEvent event) => _events.add(event);
  @override
  Stream<ConnectorEvent> get events => _events.stream;
  @override
  Future<Map<String, Object?>> request(Map<String, Object?> command) async {
    commands.add(Map.of(command));
    switch (command['op']) {
      case 'capabilities':
        return {
          'abi_version': 1,
          'platforms': [
            'whatsapp',
            'telegram',
            'instagram',
            'messenger',
            ...additionalPlatforms,
          ],
          'features': {
            for (final platform in [
              'whatsapp',
              'telegram',
              'instagram',
              'messenger',
              ...additionalPlatforms,
            ])
              platform: {
                'replies': !{'wechat', 'linkedIn'}.contains(platform),
                'reactions': !additionalPlatforms.contains(platform),
                'send_attachment': !{
                  'messenger',
                  'wechat',
                  'linkedIn',
                }.contains(platform),
                if (platform == 'discord')
                  'max_attachment_bytes': 10 * 1024 * 1024,
                'start_conversation':
                    platform == 'whatsapp' || platform == 'telegram',
              },
          },
        };
      case 'initialize':
        platforms[command['account_id'] as String] =
            command['platform'] as String;
        await onInitialize?.call();
        return {'initialized': true};
      case 'close':
        return {
          'closed': true,
          if (hasSessionOnClose != null) 'has_session': hasSessionOnClose,
        };
      case 'connect':
      case 'login':
        return onConnect == null
            ? {'state': connectState}
            : onConnect!(command);
      case 'logout':
        if (failLogout) throw const ConnectorException('operation_failed');
        return {
          'logged_out': true,
          'remote_session_revoked': !{
            'instagram',
            'messenger',
          }.contains(platforms[command['account_id']]),
        };
      case 'list_chats':
        return {'chats': chats};
      case 'login_phone':
        return {'state': 'code'};
      case 'pair_phone':
        return onPairPhone == null
            ? {'code': 'ABCD-EFGH'}
            : onPairPhone!(command);
      case 'login_code':
        if (additionalPlatforms.contains(platforms[command['account_id']])) {
          return {'state': 'connected'};
        }
        return {'state': 'password'};
      case 'login_wait':
        return {'state': 'connected'};
      case 'login_password':
        return {'state': 'connected'};
      case 'react':
        return onReact == null
            ? {
                'applied': true,
                'type': 'reaction',
                'sender_id': 'own-actor',
                'outgoing': true,
                'emoji': command['emoji'],
              }
            : await onReact!(command);
      case 'send_text':
      case 'send_attachment':
        return onSend == null
            ? {
                'id': 'remote-${command['id']}',
                'timestamp': DateTime.now().millisecondsSinceEpoch,
              }
            : onSend!(command);
      default:
        return {};
    }
  }

  @override
  Future<void> close() => _events.close();
}
