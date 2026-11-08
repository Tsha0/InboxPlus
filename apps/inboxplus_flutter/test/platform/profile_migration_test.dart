import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:inboxplus_flutter/platform/app_environment.dart';
import 'package:inboxplus_flutter/platform/profile_migration.dart';
import 'package:inboxplus_storage/inboxplus_storage.dart';
import 'package:path/path.dart' as p;

class MemorySecrets implements SecretStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  late MemorySecrets secrets;

  setUp(() async {
    final created = await Directory.systemTemp.createTemp(
      'inboxplus-profile-test-',
    );
    temporary = Directory(await created.resolveSymbolicLinks());
    secrets = MemorySecrets();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          AppEnvironment.native,
          (call) async => call.method == 'protectPath' ? true : null,
        );
  });

  tearDown(() async => temporary.delete(recursive: true));

  Future<Directory> legacyProfile(String name) async {
    final directory = Directory(
      p.join(temporary.path, 'Inbox+', 'DeveloperRuntime', name),
    );
    await Directory(p.join(directory.path, 'state')).create(recursive: true);
    return directory;
  }

  Future<AppEnvironment> open({Map<String, String> variables = const {}}) =>
      AppEnvironment.open(
        supportDirectory: temporary,
        secrets: secrets,
        environment: variables,
        isMacOS: true,
      );

  Future<LocalStore> storeFor(AppEnvironment environment) async {
    final key = await environment.keyFor('test-database', existingData: false);
    return LocalStore.open(
      file: File(p.join(environment.directory.path, 'test.sqlite')),
      key: key,
    );
  }

  test(
    'keeps the sole existing profile and places new data beneath it',
    () async {
      final profile = await legacyProfile('personal');
      final environment = await open();
      expect(environment.profileName, 'personal');
      expect(environment.legacyProfileDirectory?.path, profile.path);
      expect(environment.directory.path, p.join(profile.path, 'flutter'));
      expect(await Directory(p.join(profile.path, 'state')).exists(), isTrue);
      if (!Platform.isWindows) {
        expect((await environment.directory.stat()).mode & 511, 448);
      }
    },
  );

  test('requires an explicit choice for several existing profiles', () async {
    await legacyProfile('personal');
    await legacyProfile('work');
    await expectLater(open(), throwsA(isA<AppStorageException>()));
    expect(
      await Directory(
        p.join(temporary.path, 'Inbox+', 'DeveloperRuntime', 'default'),
      ).exists(),
      isFalse,
    );
    final selected = await open(variables: {'INBOXPLUS_PROFILE': 'work'});
    expect(selected.profileName, 'work');
  });

  test(
    'a compiled preview profile stays separate from existing profiles',
    () async {
      final original = await legacyProfile('personal');
      final preview = await AppEnvironment.open(
        supportDirectory: temporary,
        secrets: secrets,
        environment: const {},
        isMacOS: true,
        compiledProfile: 'v2-preview',
      );
      expect(preview.profileName, 'v2-preview');
      expect(
        preview.directory.path,
        p.join(original.parent.path, 'v2-preview', 'flutter'),
      );
      expect(preview.legacyProfileDirectory, isNull);
      expect(
        await Directory(p.join(original.path, 'flutter')).exists(),
        isFalse,
      );

      final explicit = await AppEnvironment.open(
        supportDirectory: temporary,
        secrets: secrets,
        environment: const {'INBOXPLUS_PROFILE': 'personal'},
        isMacOS: true,
        compiledProfile: 'v2-preview',
      );
      expect(explicit.profileName, 'personal');
    },
  );

  test('rejects profile traversal and symbolic profile roots', () async {
    await expectLater(
      open(variables: {'INBOXPLUS_PROFILE': '../outside'}),
      throwsA(isA<AppStorageException>()),
    );
    final real = await Directory(p.join(temporary.path, 'real')).create();
    final link = Link(p.join(temporary.path, 'linked'));
    await link.create(real.path);
    await expectLater(
      open(variables: {'INBOXPLUS_RUNTIME_ROOT': link.path}),
      throwsA(isA<AppStorageException>()),
    );
  }, skip: Platform.isWindows);

  test(
    'does not treat a newly created Flutter profile as an old runtime profile',
    () async {
      final first = await open();
      final second = await open();
      expect(first.directory.path, second.directory.path);
      expect(second.legacyProfileDirectory, isNull);
    },
  );

  test(
    'scopes encryption keys by profile and refuses to replace a missing key',
    () async {
      await legacyProfile('personal');
      await legacyProfile('work');
      final personal = await open(variables: {'INBOXPLUS_PROFILE': 'personal'});
      final work = await open(variables: {'INBOXPLUS_PROFILE': 'work'});
      final key = await personal.keyFor('database', existingData: false);
      expect(key.length, 32);
      expect(
        await personal.keyFor('database', existingData: true),
        orderedEquals(key),
      );
      await expectLater(
        work.keyFor('database', existingData: true),
        throwsA(isA<AppStorageException>()),
      );
      final other = await work.keyFor('database', existingData: false);
      expect(other, isNot(orderedEquals(key)));
      expect(secrets.values.length, 2);
    },
  );

  test('iOS restores keep encryption keys and preferences after the container path changes', () async {
    Future<AppEnvironment> iosEnvironment(String container, String profile) =>
        AppEnvironment.open(
          supportDirectory: Directory(
            p.join(temporary.path, container, 'Library', 'Application Support'),
          ),
          secrets: secrets,
          environment: {'INBOXPLUS_PROFILE': profile},
          isMacOS: false,
          isIOS: true,
        );
    final original = await iosEnvironment('first-container-uuid', 'personal');
    final originalKey = await original.keyFor('database', existingData: false);
    final database = File(p.join(original.directory.path, 'inbox.sqlite'));
    final store = await LocalStore.open(file: database, key: originalKey);
    await store.saveContact(
      ContactRecord(id: 'friend', displayName: 'Saved before update'),
    );
    await store.close();
    await secrets.write(
      original.secretName('preferences'),
      'saved-preferences',
    );

    final restored = await iosEnvironment(
      'replacement-container-uuid',
      'personal',
    );
    expect(restored.directory.path, isNot(original.directory.path));
    final restoredDatabase = await database.copy(
      p.join(restored.directory.path, 'inbox.sqlite'),
    );
    final restoredKey = await restored.keyFor('database', existingData: true);
    expect(restoredKey, orderedEquals(originalKey));
    expect(
      await secrets.read(restored.secretName('preferences')),
      'saved-preferences',
    );
    final restoredStore = await LocalStore.open(
      file: restoredDatabase,
      key: restoredKey,
    );
    addTearDown(restoredStore.close);
    expect(
      (await restoredStore.loadContacts()).single.displayName,
      'Saved before update',
    );

    final otherProfile = await iosEnvironment(
      'replacement-container-uuid',
      'work',
    );
    await expectLater(
      otherProfile.keyFor('database', existingData: true),
      throwsA(isA<AppStorageException>()),
    );
    expect(
      otherProfile.secretName('preferences'),
      isNot(restored.secretName('preferences')),
    );
  });

  test('iOS profile restore rebases staged and cached attachments before loading state', () async {
    Future<AppEnvironment> iosEnvironment(String container) =>
        AppEnvironment.open(
          supportDirectory: Directory(
            p.join(temporary.path, container, 'Library', 'Application Support'),
          ),
          secrets: secrets,
          environment: {'INBOXPLUS_PROFILE': 'personal'},
          isMacOS: false,
          isIOS: true,
        );
    final original = await iosEnvironment('original-container');
    final key = await original.keyFor('database', existingData: false);
    final database = File(p.join(original.directory.path, 'inbox.sqlite'));
    final store = await LocalStore.open(file: database, key: key);
    const route = ConversationRoute('telegram', 'user:42');
    final instant = DateTime.utc(2026, 11, 5);
    final media = File(p.join(original.directory.path, 'media', 'photo.png'));
    final staged = File(
      p.join(original.directory.path, 'staging', 'draft.pdf'),
    );
    await original.writePrivate(media, utf8.encode('Saved photo bytes'));
    await original.writePrivate(staged, utf8.encode('Unsent attachment bytes'));
    await store.saveAccount(
      const AccountRecord(
        id: 'telegram',
        platform: 'telegram',
        displayName: 'Saved account',
      ),
    );
    await store.saveConversation(
      ConversationRecord(
        route: route,
        title: 'Saved conversation',
        latestActivity: instant,
      ),
    );
    await store.saveMessage(
      MessageRecord(
        id: 'saved-message',
        route: route,
        body: 'Saved message',
        timestamp: instant,
        isOutgoing: false,
        attachments: [
          AttachmentRecord(id: 'photo', kind: 'image', localPath: media.path),
        ],
      ),
    );
    final draft = await store.saveDraft(
      route,
      'Keep this draft',
      attachments: [
        AttachmentRecord(id: 'staged', kind: 'file', localPath: staged.path),
      ],
    );
    await store.enqueueDraft(route, sendId: 'saved-send', now: instant);
    await store.savePendingSendStatus('saved-send', PendingSendStatus.unknown);
    final originalResult = await ProfileMigration(original).run(store);
    expect(originalResult.didMigrate, isFalse);
    expect(
      await secrets.read(original.secretName('profile-directory')),
      original.directory.path,
    );
    await store.close();
    final originalBytes = await database.readAsBytes();

    final restored = await iosEnvironment('replacement-container');
    final restoredDatabase = await database.copy(
      p.join(restored.directory.path, 'inbox.sqlite'),
    );
    final restoredMedia = File(
      p.join(restored.directory.path, 'media', 'photo.png'),
    );
    final restoredStaged = File(
      p.join(restored.directory.path, 'staging', 'draft.pdf'),
    );
    await restored.writePrivate(restoredMedia, await media.readAsBytes());
    await restored.writePrivate(restoredStaged, await staged.readAsBytes());
    final restoredKey = await restored.keyFor('database', existingData: true);
    final restoredStore = await LocalStore.open(
      file: restoredDatabase,
      key: restoredKey,
    );
    addTearDown(restoredStore.close);

    await ProfileMigration(restored).run(restoredStore);
    final message = (await restoredStore.loadMessage(route, 'saved-message'))!;
    expect(message.body, 'Saved message');
    expect(message.attachments.single.localPath, restoredMedia.path);
    final restoredDraft = (await restoredStore.loadDraft(route))!;
    expect(restoredDraft.body, 'Keep this draft');
    expect(restoredDraft.revision, draft.revision);
    expect(restoredDraft.attachments.single.localPath, restoredStaged.path);
    final pending = (await restoredStore.loadPendingSends()).single;
    expect(pending.id, 'saved-send');
    expect(pending.status, PendingSendStatus.unknown);
    expect(pending.attachments.single.localPath, restoredStaged.path);
    expect(await restoredMedia.readAsString(), 'Saved photo bytes');
    expect(await restoredStaged.readAsString(), 'Unsent attachment bytes');
    expect(await database.readAsBytes(), orderedEquals(originalBytes));
    expect(
      await secrets.read(restored.secretName('profile-directory')),
      restored.directory.path,
    );
    await ProfileMigration(restored).run(restoredStore);
    expect(
      (await restoredStore.loadPendingSends())
          .single
          .attachments
          .single
          .localPath,
      restoredStaged.path,
    );
  });

  test('invalid restored profile markers fail without substituting an empty profile', () async {
    final environment = await open();
    final store = await storeFor(environment);
    addTearDown(store.close);
    await store.saveContact(
      ContactRecord(id: 'keep', displayName: 'Keep this contact'),
    );
    final marker = environment.secretName('profile-directory');
    await secrets.write(marker, 'relative/profile');

    await expectLater(
      ProfileMigration(environment).run(store),
      throwsA(isA<AppStorageException>()),
    );
    expect(
      (await store.loadContacts()).single.displayName,
      'Keep this contact',
    );
    expect(await secrets.read(marker), 'relative/profile');
  });

  test('macOS custom roots retain separate credential namespaces', () async {
    Future<AppEnvironment> atRoot(String name) => AppEnvironment.open(
      supportDirectory: temporary,
      secrets: secrets,
      environment: {
        'INBOXPLUS_PROFILE': 'personal',
        'INBOXPLUS_RUNTIME_ROOT': p.join(temporary.path, name),
      },
      isMacOS: true,
      isIOS: false,
    );
    final first = await atRoot('first-runtime-root');
    final second = await atRoot('second-runtime-root');
    final firstKey = await first.keyFor('database', existingData: false);
    await expectLater(
      second.keyFor('database', existingData: true),
      throwsA(isA<AppStorageException>()),
    );
    final secondKey = await second.keyFor('database', existingData: false);
    expect(firstKey, isNot(orderedEquals(secondKey)));
  });

  test(
    'rejects a malformed stored key without generating a replacement',
    () async {
      final environment = await open();
      final name = environment.secretName('database');
      secrets.values[name] = base64Encode(Uint8List(4));
      await expectLater(
        environment.keyFor('database', existingData: true),
        throwsA(isA<AppStorageException>()),
      );
      expect(secrets.values[name], base64Encode(Uint8List(4)));
    },
  );

  test('writes private files and refuses paths outside the profile or through a link', () async {
    final environment = await open();
    final destination = File(
      p.join(environment.directory.path, 'media', 'fixture.bin'),
    );
    await environment.writePrivate(destination, [1, 2, 3]);
    expect(await destination.readAsBytes(), [1, 2, 3]);
    if (!Platform.isWindows) expect((await destination.stat()).mode & 511, 384);
    final outside = File(p.join(temporary.path, 'outside.bin'));
    await expectLater(
      environment.writePrivate(outside, [9]),
      throwsA(isA<AppStorageException>()),
    );
    final linked = File(p.join(environment.directory.path, 'linked.bin'));
    await Link(linked.path).create(destination.path);
    await expectLater(
      environment.writePrivate(linked, [9]),
      throwsA(isA<AppStorageException>()),
    );
    expect(await destination.readAsBytes(), [1, 2, 3]);
    expect(await destination.parent.list().length, 1);
  }, skip: Platform.isWindows);

  test('imports contacts and choices once with Swift date conversion and no session access', () async {
    final profile = await legacyProfile('personal');
    final contacts = File(p.join(profile.path, 'contacts', 'directory.json'));
    await contacts.parent.create();
    await contacts.writeAsString(
      jsonEncode({
        'schemaVersion': 1,
        'people': {
          'friend': {'id': 'friend', 'displayName': 'A friend'},
        },
        'links': {
          'friend': {
            'personID': 'friend',
            'remoteIdentityIDs': ['@whatsapp_fixture:localhost'],
          },
        },
      }),
    );
    final route = {
      'accountID': 'whatsapp',
      'conversationID': '!old-room:localhost',
    };
    await File(p.join(profile.path, 'inbox-favourites.json'))
        .writeAsString(jsonEncode([route]));
    await File(p.join(profile.path, 'inbox-conversation-preferences.json'))
        .writeAsString(
          jsonEncode({
            'markedUnread': [route],
            'mutes': [
              {'route': route, 'until': 100.25},
            ],
            'hides': [
              {'route': route, 'latestActivity': 50.125},
            ],
          }),
        );
    final session = File(p.join(profile.path, 'state', 'session.json'));
    await session.writeAsString('deliberately not a readable runtime session');
    final originalContacts = await contacts.readAsBytes();
    final environment = await open();
    final store = await storeFor(environment);
    addTearDown(store.close);

    final result = await ProfileMigration(environment).run(store);
    expect(result.didMigrate, isTrue);
    expect(result.requiresReconnect, isTrue);
    final people = await store.loadContacts();
    expect(people.single.displayName, 'A friend');
    expect(
      people.single.identities.single.identityId,
      '@whatsapp_fixture:localhost',
    );
    expect(people.single.identities.single.accountId, 'legacy:identities');
    final choices = (await store.loadConversationPreferences()).single;
    expect(
      choices.route,
      const ConversationRoute('legacy:whatsapp', '!old-room:localhost'),
    );
    expect(choices.isFavorite, isTrue);
    expect(choices.markedUnread, isTrue);
    expect(
      choices.mutedUntil,
      DateTime.utc(2001, 1, 1).add(const Duration(milliseconds: 100250)),
    );
    expect(
      choices.hiddenAt,
      DateTime.utc(2001, 1, 1).add(const Duration(milliseconds: 50125)),
    );
    expect(
      (await store.loadAccounts()).every(
        (a) => a.platform == 'legacy' && !a.isConnected,
      ),
      isTrue,
    );
    expect(await contacts.readAsBytes(), originalContacts);
    expect(
      await session.readAsString(),
      'deliberately not a readable runtime session',
    );
    await store.saveContact(
      ContactRecord(id: 'friend', displayName: 'Renamed'),
    );
    expect(
      (await ProfileMigration(environment).run(store)).didMigrate,
      isFalse,
    );
    expect((await store.loadContacts()).single.displayName, 'Renamed');
  });

  test('malformed previous state blocks migration without importing a partial profile', () async {
    final profile = await legacyProfile('personal');
    final contacts = File(p.join(profile.path, 'contacts', 'directory.json'));
    await contacts.parent.create();
    await contacts.writeAsString(
      jsonEncode({
        'schemaVersion': 1,
        'people': {
          'friend': {'id': 'friend', 'displayName': 'A friend'},
        },
        'links': {},
      }),
    );
    final choices = File(
      p.join(profile.path, 'inbox-conversation-preferences.json'),
    );
    await choices.writeAsString('{malformed');
    final environment = await open();
    final store = await storeFor(environment);
    addTearDown(store.close);
    await expectLater(
      ProfileMigration(environment).run(store),
      throwsA(isA<AppStorageException>()),
    );
    expect(await store.loadContacts(), isEmpty);
    expect(await store.loadAccounts(), isEmpty);
    expect(await choices.readAsString(), '{malformed');
    expect(
      secrets.values[environment.secretName('profile-migration-v1')],
      isNull,
    );
  });

  test('does not follow legacy data symlinks', () async {
    final profile = await legacyProfile('personal');
    final outside = File(p.join(temporary.path, 'outside.json'));
    await outside.writeAsString('[]');
    await Link(p.join(profile.path, 'inbox-favourites.json'))
        .create(outside.path);
    final environment = await open();
    final store = await storeFor(environment);
    addTearDown(store.close);
    await expectLater(
      ProfileMigration(environment).run(store),
      throwsA(isA<AppStorageException>()),
    );
    expect(await outside.readAsString(), '[]');
  }, skip: Platform.isWindows);
}
