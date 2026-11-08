import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:inboxplus_storage/inboxplus_storage.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late File file;
  late Uint8List key;
  LocalStore? store;
  const route = ConversationRoute('instagram', 'chat');
  final instant = DateTime.fromMicrosecondsSinceEpoch(
    1793764800123456,
    isUtc: true,
  );

  Future<void> seed(ConversationRoute target) async {
    await store!.saveAccount(
      AccountRecord(
        id: target.accountId,
        platform: target.accountId,
        displayName: 'Account',
      ),
    );
    await store!.saveConversation(
      ConversationRecord(
        route: target,
        title: 'Conversation',
        latestActivity: instant,
      ),
    );
  }

  MessageRecord message(
    ConversationRoute target,
    String id, {
    String body = 'Hello',
    bool outgoing = false,
    DateTime? timestamp,
  }) => MessageRecord(
    id: id,
    route: target,
    body: body,
    timestamp: timestamp ?? instant,
    isOutgoing: outgoing,
  );

  Future<void> reopen() async {
    await store!.close();
    store = null;
    store = await LocalStore.open(file: file, key: key);
  }

  setUp(() async {
    final temporary = await Directory.systemTemp.createTemp(
      'inboxplus-storage-',
    );
    directory = Directory(await temporary.resolveSymbolicLinks());
    file = File.fromUri(directory.uri.resolve('profile/inbox.sqlite'));
    key = Uint8List.fromList(List.generate(32, (index) => index + 1));
    store = await LocalStore.open(file: file, key: key);
  });

  tearDown(() async {
    await store?.close();
    store = null;
    await directory.delete(recursive: true);
  });

  test(
    'encrypted data and attachment metadata survive a file-backed reopen',
    () async {
      await seed(route);
      const attachment = AttachmentRecord(
        id: 'photo',
        kind: 'image',
        fileName: 'photo.png',
        mimeType: 'image/png',
        byteCount: 42,
        localPath: 'media/opaque.png',
        remoteSource: 'opaque-source',
        deepLink: 'https://www.instagram.com/reel/example/',
        isDownloadable: false,
      );
      await store!.saveMessage(
        MessageRecord(
          id: 'm1',
          route: route,
          body: 'PRIVATE_BODY_7d37e',
          timestamp: instant,
          isOutgoing: false,
          senderId: 'private-sender-id',
          senderName: 'Private sender',
          attachments: [attachment],
        ),
      );
      await store!.saveDraft(
        route,
        'Saved draft',
        replyToMessageId: 'm1',
        attachments: [attachment],
      );
      await store!.saveContact(
        ContactRecord(
          id: 'person',
          displayName: 'Private contact',
          identities: [const IdentityLink('instagram', 'remote-person')],
        ),
      );
      await store!.saveConversationPreferences(
        ConversationPreferencesRecord(
          route: route,
          isFavorite: true,
          markedUnread: true,
          isMuted: true,
          mutedUntil: instant.add(const Duration(hours: 1)),
          hiddenAt: instant,
        ),
      );
      await reopen();

      final records = await store!.loadRecentMessages(route);
      expect(records.single.body, 'PRIVATE_BODY_7d37e');
      expect(records.single.timestamp, instant);
      expect(records.single.senderId, 'private-sender-id');
      expect(records.single.attachments.single.localPath, 'media/opaque.png');
      expect(
        records.single.attachments.single.deepLink,
        'https://www.instagram.com/reel/example/',
      );
      expect(records.single.attachments.single.isDownloadable, isFalse);
      expect((await store!.loadAccounts()).single.id, 'instagram');
      expect((await store!.loadConversations()).single.latestActivity, instant);
      expect(
        (await store!.loadContacts()).single.identities.single.identityId,
        'remote-person',
      );
      expect((await store!.loadDraft(route))!.replyToMessageId, 'm1');
      expect(
        (await store!.loadDraft(route))!.attachments.single.isDownloadable,
        isFalse,
      );
      final preferences = (await store!.loadConversationPreferences()).single;
      expect(preferences.isFavorite, isTrue);
      expect(preferences.markedUnread, isTrue);
      expect(preferences.hiddenAt, instant);
      expect(
        preferences.isMutedAt(instant.add(const Duration(minutes: 59))),
        isTrue,
      );
      expect(
        preferences.isMutedAt(instant.add(const Duration(hours: 1))),
        isFalse,
      );
      final bytes = await file.readAsBytes();
      expect(latin1.decode(bytes), isNot(contains('PRIVATE_BODY_7d37e')));
      expect(latin1.decode(bytes), isNot(contains('private-sender-id')));
      expect(latin1.decode(bytes), isNot(contains('Private contact')));
      expect(
        bytes.take(16),
        isNot(orderedEquals(ascii.encode('SQLite format 3\u0000'))),
      );
      if (!Platform.isWindows) {
        expect((await file.stat()).mode & 0x1ff, 0x180);
        expect((await file.parent.stat()).mode & 0x1ff, 0x1c0);
      }
    },
  );

  test(
    'reaction actors are idempotent, scoped and durable before their message arrives',
    () async {
      const other = ConversationRoute('telegram', 'chat');
      await seed(route);
      await seed(other);
      await store!.setReaction(
        route,
        'm1',
        'actor-a',
        '👍',
        includesMe: false,
        timestamp: instant,
      );
      await store!.setReaction(
        route,
        'm1',
        'actor-a',
        '👍',
        includesMe: false,
        timestamp: instant,
      );
      await store!.setReaction(
        route,
        'm1',
        'private-own-actor',
        '👍',
        includesMe: true,
        timestamp: instant,
      );
      await store!.setReaction(
        other,
        'm1',
        'actor-a',
        '❤️',
        includesMe: false,
        timestamp: instant,
      );
      await store!.saveMessage(message(route, 'm1'));
      await reopen();
      final values = await store!.loadReactions(route, 'm1');
      expect(values.single.key, '👍');
      expect(values.single.count, 2);
      expect(values.single.includesMe, isTrue);
      expect((await store!.loadReactions(other, 'm1')).single.key, '❤️');
      expect(
        latin1.decode(await file.readAsBytes()),
        isNot(contains('private-own-actor')),
      );
      await store!.setReaction(
        route,
        'm1',
        'private-own-actor',
        '❤️',
        includesMe: true,
        timestamp: instant.add(const Duration(seconds: 1)),
      );
      expect(
        {
          for (final r in await store!.loadReactions(route, 'm1'))
            r.key: r.count,
        },
        {'👍': 1, '❤️': 1},
      );
      await store!.setReaction(
        route,
        'm1',
        'private-own-actor',
        '',
        includesMe: true,
        timestamp: instant.add(const Duration(seconds: 2)),
      );
      await store!.setReaction(
        route,
        'm1',
        'private-own-actor',
        '❤️',
        includesMe: true,
        timestamp: instant,
      );
      final remaining = await store!.loadReactions(route, 'm1');
      expect(remaining.single.key, '👍');
      expect(remaining.single.includesMe, isFalse);
      await store!.deleteMessage(route, 'm1');
      expect(await store!.loadReactions(route, 'm1'), isEmpty);
      expect((await store!.loadReactions(other, 'm1')).single.key, '❤️');
    },
  );

  test(
    'reaction snapshots replace totals atomically and reject duplicate actors',
    () async {
      await seed(route);
      await store!.replaceReactions(route, 'm1', const [
        MessageReactionRecord(key: '👍', count: 5, includesMe: true),
      ]);
      await expectLater(
        store!.replaceReactions(route, 'm1', const [
          MessageReactionRecord(key: '❤️', senderId: 'same'),
          MessageReactionRecord(key: '👍', senderId: 'same'),
        ]),
        throwsA(isA<StorageException>()),
      );
      expect((await store!.loadReactions(route, 'm1')).single.count, 5);
      await reopen();
      expect(
        (await store!.loadMessageReactions())
            .single
            .reactions
            .single
            .includesMe,
        isTrue,
      );
      await store!.replaceReactions(route, 'm1', []);
      expect(await store!.loadReactions(route, 'm1'), isEmpty);
    },
  );

  test('wrong and missing keys fail without changing database bytes', () async {
    await seed(route);
    await store!.saveMessage(message(route, 'm1', body: 'Private message'));
    await store!.close();
    store = null;
    final before = await file.readAsBytes();
    for (final invalid in [Uint8List(32), Uint8List(0), Uint8List(31)]) {
      await expectLater(
        LocalStore.open(file: file, key: invalid),
        throwsA(isA<StorageException>()),
      );
      expect(await file.readAsBytes(), orderedEquals(before));
    }
    store = await LocalStore.open(file: file, key: key);
    expect(
      (await store!.loadRecentMessages(route)).single.body,
      'Private message',
    );
  });

  test('newer encrypted schema is rejected without mutation', () async {
    await store!.close();
    store = null;
    final raw = sqlite.sqlite3.open(file.path);
    final hex = key.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    raw.execute("PRAGMA cipher = 'chacha20'");
    raw.execute("PRAGMA key = 'raw:$hex'");
    raw.execute('PRAGMA user_version = 99');
    raw.close();
    final before = await file.readAsBytes();
    await expectLater(
      LocalStore.open(file: file, key: key),
      throwsA(
        isA<StorageException>().having(
          (e) => e.code,
          'code',
          StorageErrorCode.unsupportedSchema,
        ),
      ),
    );
    expect(await file.readAsBytes(), orderedEquals(before));
  });

  test('plaintext and corrupt stores are never adopted or replaced', () async {
    await store!.close();
    store = null;
    await file.delete();
    final plain = sqlite.sqlite3.open(file.path);
    plain.execute('CREATE TABLE private_data(body TEXT)');
    plain.execute('INSERT INTO private_data VALUES (?)', ['Private data']);
    plain.close();
    final before = await file.readAsBytes();
    await expectLater(
      LocalStore.open(file: file, key: key),
      throwsA(isA<StorageException>()),
    );
    expect(await file.readAsBytes(), orderedEquals(before));
    await file.writeAsBytes(List.filled(128, 42));
    final corrupt = await file.readAsBytes();
    await expectLater(
      LocalStore.open(file: file, key: key),
      throwsA(isA<StorageException>()),
    );
    expect(await file.readAsBytes(), orderedEquals(corrupt));
  });

  test('account and route identities isolate messages and drafts', () async {
    const other = ConversationRoute('telegram', 'chat');
    const anotherChat = ConversationRoute('instagram', 'another-chat');
    await seed(route);
    await seed(other);
    await seed(anotherChat);
    for (final target in [route, other, anotherChat]) {
      await store!.saveMessage(
        message(
          target,
          'same-id',
          body: target.accountId + target.conversationId,
        ),
      );
      await store!.saveDraft(target, target.accountId + target.conversationId);
    }
    expect(
      (await store!.loadRecentMessages(route)).single.body,
      'instagramchat',
    );
    expect(
      (await store!.loadRecentMessages(other)).single.body,
      'telegramchat',
    );
    await store!.saveMessage(message(route, 'same-id', body: 'Edited'));
    expect((await store!.loadRecentMessages(route)).single.body, 'Edited');
    await store!.deleteMessage(route, 'same-id');
    expect(await store!.loadRecentMessages(route), isEmpty);
    expect(
      (await store!.loadRecentMessages(other)).single.body,
      'telegramchat',
    );
    expect(
      (await store!.loadDraft(anotherChat))!.body,
      'instagramanother-chat',
    );
  });

  test(
    'recent window is deterministic and returned in chronological order',
    () async {
      await seed(route);
      for (var i = 0; i < 60; i++) {
        await store!.saveMessage(
          message(
            route,
            'm${i.toString().padLeft(2, '0')}',
            timestamp: instant.add(Duration(seconds: i)),
          ),
        );
      }
      final recent = await store!.loadRecentMessages(route);
      expect(recent.length, 50);
      expect(recent.first.id, 'm10');
      expect(recent.last.id, 'm59');
      expect(
        (await store!.loadRecentMessages(route, limit: 2)).map((m) => m.id),
        ['m58', 'm59'],
      );
    },
  );

  test('send completion is atomic and cannot erase a newer draft', () async {
    await seed(route);
    final captured = await store!.saveDraft(route, 'First draft');
    final pending = await store!.enqueueDraft(
      route,
      sendId: 'send-1',
      now: instant,
    );
    expect(pending.draftRevision, captured.revision);
    final newer = await store!.saveDraft(route, 'Newer draft');
    expect(newer.revision, greaterThan(captured.revision));
    await store!.savePendingSendStatus('send-1', PendingSendStatus.sending);
    await reopen();
    expect(
      (await store!.loadPendingSends()).single.status,
      PendingSendStatus.sending,
    );
    expect(
      await store!.completeSend(
        'send-1',
        message(route, 'sent-1', body: 'First draft', outgoing: true),
      ),
      isTrue,
    );
    expect((await store!.loadDraft(route))!.body, 'Newer draft');
    expect(await store!.loadPendingSends(), isEmpty);
    expect(
      await store!.completeSend(
        'send-1',
        message(route, 'sent-1', outgoing: true),
      ),
      isFalse,
    );
    expect((await store!.loadRecentMessages(route)).single.body, 'First draft');
  });

  test(
    'send completion advances activity without moving it backwards on a late acknowledgement',
    () async {
      await seed(route);
      final sentAt = instant.add(const Duration(minutes: 2));
      for (final (id, timestamp) in [('newer', sentAt), ('late', instant)]) {
        await store!.saveDraft(route, id);
        await store!.enqueueDraft(route, sendId: id);
        await store!.completeSend(
          id,
          message(route, id, outgoing: true, timestamp: timestamp),
        );
        expect(
          (await store!.loadConversations()).single.latestActivity,
          sentAt,
        );
      }
      await reopen();
      expect((await store!.loadConversations()).single.latestActivity, sentAt);
    },
  );

  test(
    'draft revisions remain monotonic after clear and enqueue is idempotent',
    () async {
      await seed(route);
      final first = await store!.saveDraft(route, 'First');
      await store!.enqueueDraft(route, sendId: 'same-command');
      final second = await store!.saveDraft(route, 'Second');
      expect(
        (await store!.enqueueDraft(route, sendId: 'same-command')).body,
        'First',
      );
      expect(
        await store!.clearDraft(route, expectedRevision: first.revision),
        isFalse,
      );
      expect(
        await store!.clearDraft(route, expectedRevision: second.revision),
        isTrue,
      );
      final third = await store!.saveDraft(route, 'Third');
      expect(third.revision, greaterThan(second.revision));
      await store!.removePendingSend('same-command');
      expect((await store!.loadDraft(route))!.body, 'Third');
    },
  );

  test(
    'resolving an uncertain send preserves the chosen draft and never replays',
    () async {
      await seed(route);
      await store!.saveDraft(route, 'Unconfirmed send');
      await store!.enqueueDraft(route, sendId: 'unknown-send');
      await store!.savePendingSendStatus(
        'unknown-send',
        PendingSendStatus.unknown,
      );
      expect(
        await store!.resolvePendingSend(
          'unknown-send',
          clearCapturedDraft: false,
        ),
        isTrue,
      );
      expect((await store!.loadDraft(route))!.body, 'Unconfirmed send');
      await reopen();
      expect(await store!.loadPendingSends(), isEmpty);
      expect(await store!.loadRecentMessages(route), isEmpty);
      expect(
        await store!.resolvePendingSend(
          'unknown-send',
          clearCapturedDraft: true,
        ),
        isFalse,
      );
      expect((await store!.loadDraft(route))!.body, 'Unconfirmed send');

      await store!.enqueueDraft(route, sendId: 'clear-send');
      expect(
        await store!.resolvePendingSend('clear-send', clearCapturedDraft: true),
        isTrue,
      );
      expect((await store!.loadDraft(route))!.body, isEmpty);
      await store!.saveDraft(route, 'Another unconfirmed send');
      await store!.enqueueDraft(route, sendId: 'newer-send');
      await store!.saveDraft(route, 'Newer draft');
      expect(
        await store!.resolvePendingSend('newer-send', clearCapturedDraft: true),
        isTrue,
      );
      await reopen();
      expect((await store!.loadDraft(route))!.body, 'Newer draft');
      expect(await store!.loadPendingSends(), isEmpty);
      expect(await store!.loadRecentMessages(route), isEmpty);
    },
  );

  test('uncertain and failed sends persist without automatic retry', () async {
    await seed(route);
    await store!.saveDraft(route, 'Keep me');
    await store!.enqueueDraft(route, sendId: 'unknown-send');
    await store!.savePendingSendStatus(
      'unknown-send',
      PendingSendStatus.unknown,
    );
    await reopen();
    expect(
      (await store!.loadPendingSends()).single.status,
      PendingSendStatus.unknown,
    );
    expect((await store!.loadDraft(route))!.body, 'Keep me');
    await store!.savePendingSendStatus(
      'unknown-send',
      PendingSendStatus.failed,
    );
    await reopen();
    expect(
      (await store!.loadPendingSends()).single.status,
      PendingSendStatus.failed,
    );
  });

  test(
    'cross-route send completion rolls back and errors expose no payload',
    () async {
      await seed(route);
      const other = ConversationRoute('telegram', 'chat');
      await seed(other);
      await store!.saveDraft(route, 'PRIVATE_PAYLOAD_8822');
      await store!.enqueueDraft(route, sendId: 'pending');
      try {
        await store!.completeSend(
          'pending',
          message(other, 'wrong-route', outgoing: true),
        );
        fail('Completion should reject a different route');
      } on StorageException catch (error) {
        expect(error.toString(), isNot(contains('PRIVATE_PAYLOAD_8822')));
        expect(error.toString(), isNot(contains(file.path)));
      }
      expect(await store!.loadRecentMessages(other), isEmpty);
      expect((await store!.loadPendingSends()).single.id, 'pending');
    },
  );

  test(
    'moving an identity is atomic and preserves other links and history',
    () async {
      await seed(route);
      await store!.saveMessage(message(route, 'history'));
      await store!.saveDraft(route, 'Keep draft');
      const identity = IdentityLink('instagram', 'identity');
      await store!.saveContact(
        ContactRecord(id: 'one', displayName: 'First', identities: [identity]),
      );
      await store!.saveContact(
        ContactRecord(
          id: 'two',
          displayName: 'Second',
          identities: [const IdentityLink('instagram', 'other')],
        ),
      );

      await store!.moveIdentityToContact(
        identity,
        ContactRecord(id: 'two', displayName: 'Second'),
      );
      await reopen();
      var people = await store!.loadContacts();
      expect(people.first.identities, isEmpty);
      expect(people.last.identities.map((i) => i.identityId), [
        'identity',
        'other',
      ]);
      expect((await store!.loadRecentMessages(route)).single.id, 'history');
      expect((await store!.loadDraft(route))!.body, 'Keep draft');

      await expectLater(
        store!.moveIdentityToContact(
          const IdentityLink('missing', 'identity'),
          ContactRecord(id: 'two', displayName: 'Uncommitted rename'),
        ),
        throwsA(isA<StorageException>()),
      );
      people = await store!.loadContacts();
      expect(people.last.displayName, 'Second');
      expect(people.last.identities, hasLength(2));
    },
  );

  test(
    'retention prunes network history while preserving iMessage and unsent work',
    () async {
      await seed(route);
      const appleRoute = ConversationRoute('apple', 'chat');
      await store!.saveAccount(
        const AccountRecord(
          id: 'apple',
          platform: 'imessage',
          displayName: 'iMessage',
        ),
      );
      await store!.saveConversation(
        ConversationRecord(
          route: appleRoute,
          title: 'Local chat',
          latestActivity: instant,
        ),
      );
      final old = instant.subtract(const Duration(days: 20));
      for (final id in ['expired', 'quoted', 'pending']) {
        await store!.saveMessage(message(route, id, timestamp: old));
      }
      await store!.saveMessage(message(route, 'recent'));
      await store!.saveMessage(
        message(appleRoute, 'apple-old', timestamp: old),
      );
      for (final id in ['expired', 'quoted', 'pending', 'orphan']) {
        await store!.setReaction(
          route,
          id,
          'actor',
          '👍',
          includesMe: false,
          timestamp: old,
        );
      }
      for (final target in [route, appleRoute]) {
        await store!.setReaction(
          target,
          'recent-orphan',
          'actor',
          '❤️',
          includesMe: false,
          timestamp: target == appleRoute ? old : instant,
        );
      }
      await store!.saveDraft(route, 'Unsent reply', replyToMessageId: 'quoted');
      await store!.enqueueDraft(route, sendId: 'pending');
      await store!.saveDraft(
        route,
        'Keep current draft',
        replyToMessageId: 'quoted',
      );

      expect(
        await store!.pruneMessagesBefore(
          instant.subtract(const Duration(days: 7)),
        ),
        1,
      );
      await reopen();
      expect((await store!.loadRecentMessages(route)).map((m) => m.id), [
        'pending',
        'quoted',
        'recent',
      ]);
      expect(
        (await store!.loadRecentMessages(appleRoute)).single.id,
        'apple-old',
      );
      expect((await store!.loadDraft(route))!.body, 'Keep current draft');
      expect((await store!.loadPendingSends()).single.id, 'pending');
      expect(await store!.loadReactions(route, 'expired'), isEmpty);
      expect(await store!.loadReactions(route, 'orphan'), isEmpty);
      for (final id in ['quoted', 'pending', 'recent-orphan']) {
        expect(await store!.loadReactions(route, id), hasLength(1));
      }
      expect(
        (await store!.loadReactions(appleRoute, 'recent-orphan')).single.key,
        '❤️',
      );
    },
  );

  test('duplicate contact links roll back the entire contact update', () async {
    await seed(route);
    await store!.saveContact(
      ContactRecord(
        id: 'one',
        displayName: 'First',
        identities: [const IdentityLink('instagram', 'identity')],
      ),
    );
    await store!.saveContact(ContactRecord(id: 'two', displayName: 'Second'));
    await expectLater(
      store!.saveContact(
        ContactRecord(
          id: 'two',
          displayName: 'PRIVATE_NAME',
          identities: [const IdentityLink('instagram', 'identity')],
        ),
      ),
      throwsA(isA<StorageException>()),
    );
    final contacts = await store!.loadContacts();
    expect(contacts.first.displayName, 'First');
    expect(contacts.last.displayName, 'Second');
    expect(contacts.last.identities, isEmpty);
    await expectLater(
      store!.saveContact(
        ContactRecord(
          id: 'three',
          displayName: 'Missing account',
          identities: [const IdentityLink('missing', 'identity')],
        ),
      ),
      throwsA(isA<StorageException>()),
    );
    expect((await store!.loadContacts()).length, 2);
  });

  test(
    'preferences survive conversations absent from the current cache',
    () async {
      await seed(route);
      const unloaded = ConversationRoute('instagram', 'not-loaded');
      await store!.saveConversationPreferences(
        const ConversationPreferencesRecord(
          route: unloaded,
          isFavorite: true,
          isMuted: true,
        ),
      );
      await reopen();
      final preferences = (await store!.loadConversationPreferences()).single;
      expect(preferences.route, unloaded);
      expect(preferences.isMutedAt(DateTime.utc(2099)), isTrue);
    },
  );

  test('account removal only erases that accounts data and links', () async {
    await seed(route);
    const other = ConversationRoute('telegram', 'chat');
    await seed(other);
    for (final target in [route, other]) {
      await store!.saveMessage(message(target, 'same-id'));
      await store!.setReaction(
        target,
        'same-id',
        'actor',
        '👍',
        includesMe: true,
        timestamp: instant,
      );
      await store!.saveDraft(target, 'Draft');
      await store!.enqueueDraft(target, sendId: 'pending-${target.accountId}');
      await store!.saveConversationPreferences(
        ConversationPreferencesRecord(route: target, isFavorite: true),
      );
    }
    await store!.saveContact(
      ContactRecord(
        id: 'person',
        displayName: 'Keep person',
        identities: [
          const IdentityLink('instagram', 'person'),
          const IdentityLink('telegram', 'person'),
        ],
      ),
    );
    await store!.removeAccount('instagram');
    await reopen();
    expect((await store!.loadAccounts()).single.id, 'telegram');
    expect((await store!.loadConversations()).single.route, other);
    expect(await store!.loadRecentMessages(route), isEmpty);
    expect(await store!.loadReactions(route, 'same-id'), isEmpty);
    expect((await store!.loadReactions(other, 'same-id')).single.key, '👍');
    expect(await store!.loadDraft(route), isNull);
    expect((await store!.loadRecentMessages(other)).single.id, 'same-id');
    expect((await store!.loadDraft(other))!.body, 'Draft');
    expect((await store!.loadPendingSends()).single.route, other);
    expect((await store!.loadConversationPreferences()).single.route, other);
    final contact = (await store!.loadContacts()).single;
    expect(contact.displayName, 'Keep person');
    expect(contact.identities.single.accountId, 'telegram');
  });

  test('account removal returns only that accounts downloaded media', () async {
    await seed(route);
    const other = ConversationRoute('telegram', 'chat');
    await seed(other);
    final cache = await Directory.fromUri(
      directory.uri.resolve('media'),
    ).create();
    final paths = <String, String>{};
    for (final (index, (target, id, downloadable)) in [
      (route, 'mine', true),
      (route, 'kept', false),
      (other, 'theirs', true),
    ].indexed) {
      final file = await File.fromUri(cache.uri.resolve(id)).writeAsString(id);
      paths[id] = file.path;
      await store!.saveMessage(
        MessageRecord(
          id: id,
          route: target,
          body: 'Attachment',
          timestamp: instant.add(Duration(seconds: index)),
          isOutgoing: false,
          attachments: [
            AttachmentRecord(
              id: id,
              kind: 'file',
              localPath: file.path,
              isDownloadable: downloadable,
            ),
          ],
        ),
      );
    }
    final outside = await File('${directory.path}/outside').writeAsString('x');
    await store!.saveMessage(
      MessageRecord(
        id: 'outside',
        route: route,
        body: 'Attachment',
        timestamp: instant.add(const Duration(seconds: 3)),
        isOutgoing: false,
        attachments: [
          AttachmentRecord(
            id: 'outside',
            kind: 'file',
            localPath: outside.path,
          ),
        ],
      ),
    );
    expect(
      await store!.removeAccount('instagram', mediaDirectory: cache.path),
      [paths['mine']],
    );
    expect((await store!.loadAccounts()).single.id, 'telegram');
    expect(
      (await store!.loadMessage(other, 'theirs'))!.attachments.single.localPath,
      paths['theirs'],
    );
  });

  test(
    'database does not delete attachment bytes owned by its caller',
    () async {
      await seed(route);
      final selected = File('${directory.path}/chosen.txt');
      await selected.writeAsString('Chosen content');
      await store!.saveDraft(
        route,
        '',
        attachments: [
          AttachmentRecord(
            id: 'chosen',
            kind: 'file',
            localPath: selected.path,
          ),
        ],
      );
      await store!.removeAccount('instagram');
      expect(await selected.readAsString(), 'Chosen content');
    },
  );

  test('symlinked database paths and sidecars are rejected', () async {
    if (Platform.isWindows) return;
    await seed(route);
    await store!.close();
    store = null;
    final before = await file.readAsBytes();
    final databaseLink = Link('${directory.path}/database-link.sqlite');
    await databaseLink.create(file.path);
    await expectLater(
      LocalStore.open(file: File(databaseLink.path), key: key),
      throwsA(isA<StorageException>()),
    );
    final directoryLink = Link('${directory.path}/directory-link');
    await directoryLink.create(file.parent.path);
    await expectLater(
      LocalStore.open(
        file: File('${directoryLink.path}/inbox.sqlite'),
        key: key,
      ),
      throwsA(isA<StorageException>()),
    );
    final sidecarTarget = File('${directory.path}/unrelated-file');
    await sidecarTarget.writeAsString('Keep these bytes');
    final journalLink = Link('${file.path}-journal');
    await journalLink.create(sidecarTarget.path);
    await expectLater(
      LocalStore.open(file: file, key: key),
      throwsA(isA<StorageException>()),
    );
    expect(await file.readAsBytes(), orderedEquals(before));
    expect(await sidecarTarget.readAsString(), 'Keep these bytes');
  });

  test(
    'foreign encrypted database cannot be adopted as an Inbox+ profile',
    () async {
      await store!.close();
      store = null;
      final raw = sqlite.sqlite3.open(file.path);
      final hex = key.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      raw.execute("PRAGMA cipher = 'chacha20'");
      raw.execute("PRAGMA key = 'raw:$hex'");
      raw.execute('PRAGMA application_id = 7');
      raw.close();
      final before = await file.readAsBytes();
      await expectLater(
        LocalStore.open(file: file, key: key),
        throwsA(isA<StorageException>()),
      );
      expect(await file.readAsBytes(), orderedEquals(before));
    },
  );

  test('foreign empty encrypted database is not initialized', () async {
    await store!.close();
    store = null;
    await file.delete();
    final raw = sqlite.sqlite3.open(file.path);
    final hex = key.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    raw.execute("PRAGMA cipher = 'chacha20'");
    raw.execute("PRAGMA key = 'raw:$hex'");
    raw.execute('PRAGMA application_id = 7');
    raw.close();
    final before = await file.readAsBytes();
    await expectLater(
      LocalStore.open(file: file, key: key),
      throwsA(isA<StorageException>()),
    );
    expect(await file.readAsBytes(), orderedEquals(before));
  });

  test(
    'storage summary counts all retained messages and attachment metadata',
    () async {
      expect((await store!.loadStorageSummary()).messageCount, 0);
      expect((await store!.loadStorageSummary()).attachmentCount, 0);
      await seed(route);
      for (var i = 0; i < 60; i++) {
        await store!.saveMessage(
          MessageRecord(
            id: '$i',
            route: route,
            body: 'Message',
            timestamp: instant.add(Duration(seconds: i)),
            isOutgoing: false,
            attachments: i.isEven
                ? [const AttachmentRecord(id: 'file', kind: 'file')]
                : const [],
          ),
        );
      }
      expect((await store!.loadRecentMessages(route)).length, 50);
      final summary = await store!.loadStorageSummary();
      expect(summary.messageCount, 60);
      expect(summary.attachmentCount, 30);
    },
  );

  test(
    'cache eviction clears old downloadable metadata and protects unsent files',
    () async {
      await seed(route);
      final cache = await Directory('${directory.path}/media').create();
      final staged = await Directory('${directory.path}/staging').create();
      Future<File> create(String path) async =>
          File(path).writeAsString('Attachment bytes');
      Future<void> save(String id, AttachmentRecord attachment, int offset) =>
          store!.saveMessage(
            MessageRecord(
              id: id,
              route: route,
              body: 'Attachment',
              timestamp: instant.add(Duration(seconds: offset)),
              isOutgoing: false,
              attachments: [attachment],
            ),
          );
      for (var i = 0; i < 60; i++) {
        final file = await create('${cache.path}/$i');
        await save(
          'download-$i',
          AttachmentRecord(
            id: 'attachment-$i',
            kind: 'file',
            localPath: file.path,
            remoteSource: 'opaque-$i',
            deepLink: 'https://www.instagram.com/p/example/',
          ),
          i,
        );
      }
      final selected = await create('${staged.path}/selected');
      await save(
        'staged',
        AttachmentRecord(id: 'staged', kind: 'file', localPath: selected.path),
        61,
      );
      final permanent = await create('${cache.path}/non-downloadable');
      await save(
        'permanent',
        AttachmentRecord(
          id: 'permanent',
          kind: 'file',
          localPath: permanent.path,
          isDownloadable: false,
        ),
        62,
      );
      final pendingFile = await create('${cache.path}/pending');
      final pendingAttachment = AttachmentRecord(
        id: 'pending',
        kind: 'file',
        localPath: pendingFile.path,
      );
      await save('pending', pendingAttachment, 63);
      await store!.saveDraft(
        route,
        'Pending',
        attachments: [pendingAttachment],
      );
      await store!.enqueueDraft(route, sendId: 'keep-pending');
      final draftFile = await create('${cache.path}/draft');
      final draftAttachment = AttachmentRecord(
        id: 'draft',
        kind: 'file',
        localPath: draftFile.path,
      );
      await save('draft', draftAttachment, 64);
      await store!.saveDraft(route, 'Draft', attachments: [draftAttachment]);
      final outside = await create('${directory.path}/outside');
      await save(
        'outside',
        AttachmentRecord(
          id: 'outside',
          kind: 'file',
          localPath: '${cache.path}/../outside',
        ),
        65,
      );
      if (!Platform.isWindows) {
        final link = await Link('${cache.path}/link').create(outside.path);
        await save(
          'link',
          AttachmentRecord(id: 'link', kind: 'file', localPath: link.path),
          66,
        );
      }
      expect(
        (await store!.loadRecentMessages(
          route,
        )).any((m) => m.id == 'download-0'),
        isFalse,
      );
      final paths = await store!.clearDownloadedMediaPaths(cache.path);
      expect(paths.length, 60);
      expect(paths, contains(File.fromUri(cache.uri.resolve('0')).path));
      final old = await store!.loadMessage(route, 'download-0');
      expect(old!.attachments.single.localPath, isNull);
      expect(old.attachments.single.remoteSource, 'opaque-0');
      expect(
        old.attachments.single.deepLink,
        'https://www.instagram.com/p/example/',
      );
      expect(
        await store!.loadMessage(
          const ConversationRoute('other', 'chat'),
          'download-0',
        ),
        isNull,
      );
      for (final id in ['staged', 'permanent', 'pending', 'draft', 'outside']) {
        expect(
          (await store!.loadMessage(route, id))!.attachments.single.localPath,
          isNotNull,
        );
      }
      expect(await File(paths.first).exists(), isTrue);
      for (final path in paths) {
        await File(path).delete();
      }
      for (final file in [
        selected,
        permanent,
        pendingFile,
        draftFile,
        outside,
      ]) {
        expect(await file.readAsString(), 'Attachment bytes');
      }
      await reopen();
      expect(
        (await store!.loadMessage(
          route,
          'download-0',
        ))!.attachments.single.localPath,
        isNull,
      );
      expect(
        (await store!.loadPendingSends()).single.attachments.single.localPath,
        pendingFile.path,
      );
      expect(
        (await store!.loadDraft(route))!.attachments.single.localPath,
        draftFile.path,
      );
      expect(await store!.clearDownloadedMediaPaths(cache.path), isEmpty);
    },
  );

  test(
    'cache clearing finds orphaned files after pruning or deletion',
    () async {
      await seed(route);
      final cache = await Directory('${directory.path}/media').create();
      final files = <File>[];
      for (final id in ['expired', 'deleted']) {
        final file = await File.fromUri(
          cache.uri.resolve(id),
        ).writeAsString('Fixture bytes');
        files.add(file);
        await store!.saveMessage(
          MessageRecord(
            id: id,
            route: route,
            body: '',
            timestamp: instant,
            isOutgoing: false,
            attachments: [
              AttachmentRecord(
                id: id,
                kind: 'file',
                localPath: file.path,
                isDownloadable: true,
              ),
            ],
          ),
        );
      }
      await store!.deleteMessage(route, 'deleted');
      await store!.pruneMessagesBefore(instant.add(const Duration(days: 1)));
      expect(await store!.loadRecentMessages(route), isEmpty);
      expect(
        await store!.clearDownloadedMediaPaths(cache.path),
        unorderedEquals(files.map((f) => f.path)),
      );
    },
  );

  test(
    'schema five upgrade retains drafts and adds a durable read watermark',
    () async {
      await seed(route);
      await store!.saveDraft(route, 'Keep this draft');
      await store!.saveConversationPreferences(
        const ConversationPreferencesRecord(route: route, isFavorite: true),
      );
      await store!.close();
      store = null;
      final raw = sqlite.sqlite3.open(file.path);
      final hex = key.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      raw.execute("PRAGMA cipher = 'chacha20'");
      raw.execute("PRAGMA key = 'raw:$hex'");
      raw.execute(
        'ALTER TABLE conversation_preferences DROP COLUMN read_through_micros',
      );
      raw.execute('PRAGMA user_version = 5');
      raw.close();
      store = await LocalStore.open(file: file, key: key);
      expect((await store!.loadDraft(route))?.body, 'Keep this draft');
      expect(
        (await store!.loadConversationPreferences()).single.isFavorite,
        isTrue,
      );
      expect(
        (await store!.loadConversationPreferences()).single.readThrough,
        isNull,
      );
      await store!.saveConversationPreferences(
        ConversationPreferencesRecord(route: route, readThrough: instant),
      );
      await reopen();
      expect(
        (await store!.loadConversationPreferences()).single.readThrough,
        instant,
      );
    },
  );

  test(
    'restored profiles rebase attachment metadata without changing payloads or files',
    () async {
      await seed(route);
      final previous = Directory.fromUri(
        directory.uri.resolve('old-container/flutter'),
      );
      final current = file.parent;
      await previous.create(recursive: true);
      final previousMedia = File.fromUri(
        previous.uri.resolve('media/photo.png'),
      ).path;
      final previousStaged = File.fromUri(
        previous.uri.resolve('staging/draft.pdf'),
      ).path;
      final media = File.fromUri(current.uri.resolve('media/photo.png'));
      final staged = File.fromUri(current.uri.resolve('staging/draft.pdf'));
      for (final entry in [media, staged]) {
        await entry.parent.create(recursive: true);
        await entry.writeAsString('Kept attachment bytes');
      }
      final outside = '${directory.path}/external/file.pdf';
      await store!.saveMessage(
        MessageRecord(
          id: 'restored-message',
          route: route,
          body: 'Saved message',
          timestamp: instant,
          isOutgoing: false,
          attachments: [
            AttachmentRecord(
              id: 'photo',
              kind: 'image',
              localPath: previousMedia,
              deepLink: 'https://www.instagram.com/p/example/',
              isDownloadable: false,
            ),
            AttachmentRecord(id: 'external', kind: 'file', localPath: outside),
          ],
        ),
      );
      final draft = await store!.saveDraft(
        route,
        'Saved draft',
        attachments: [
          AttachmentRecord(
            id: 'staged',
            kind: 'file',
            localPath: previousStaged,
          ),
        ],
      );
      await store!.enqueueDraft(route, sendId: 'restored-send', now: instant);
      await store!.savePendingSendStatus(
        'restored-send',
        PendingSendStatus.unknown,
      );
      await previous.delete(recursive: true);

      expect(
        await store!.rebaseAttachmentPaths(
          previousDirectory: previous.path,
          currentDirectory: current.path,
        ),
        3,
      );
      await reopen();
      final message = (await store!.loadMessage(route, 'restored-message'))!;
      expect(message.body, 'Saved message');
      expect(message.attachments.first.localPath, media.path);
      expect(
        message.attachments.first.deepLink,
        'https://www.instagram.com/p/example/',
      );
      expect(message.attachments.first.isDownloadable, isFalse);
      expect(message.attachments.last.localPath, outside);
      final savedDraft = (await store!.loadDraft(route))!;
      expect(savedDraft.body, 'Saved draft');
      expect(savedDraft.revision, draft.revision);
      expect(savedDraft.attachments.single.localPath, staged.path);
      final pending = (await store!.loadPendingSends()).single;
      expect(pending.body, 'Saved draft');
      expect(pending.draftRevision, draft.revision);
      expect(pending.status, PendingSendStatus.unknown);
      expect(pending.createdAt, instant);
      expect(pending.attachments.single.localPath, staged.path);
      expect(await media.readAsString(), 'Kept attachment bytes');
      expect(await staged.readAsString(), 'Kept attachment bytes');
      expect(await previous.exists(), isFalse);
      expect(
        await store!.rebaseAttachmentPaths(
          previousDirectory: previous.path,
          currentDirectory: current.path,
        ),
        0,
      );
    },
  );

  test(
    'unsafe restored attachment paths roll back all metadata changes',
    () async {
      if (Platform.isWindows) return;
      await seed(route);
      final previous = '${directory.path}/old-container/flutter';
      final current = file.parent.path;
      final outside = Directory('${directory.path}/outside');
      await outside.create();
      await Directory('$current/media').create();
      await Link('$current/staging').create(outside.path);
      await store!.saveMessage(
        MessageRecord(
          id: 'restored-message',
          route: route,
          body: 'Keep both paths',
          timestamp: instant,
          isOutgoing: false,
          attachments: [
            AttachmentRecord(
              id: 'safe',
              kind: 'image',
              localPath: '$previous/media/photo.png',
            ),
            AttachmentRecord(
              id: 'unsafe',
              kind: 'file',
              localPath: '$previous/staging/file.pdf',
            ),
          ],
        ),
      );

      await expectLater(
        store!.rebaseAttachmentPaths(
          previousDirectory: previous,
          currentDirectory: current,
        ),
        throwsA(isA<StorageException>()),
      );
      final message = (await store!.loadMessage(route, 'restored-message'))!;
      expect(message.attachments.map((a) => a.localPath), [
        '$previous/media/photo.png',
        '$previous/staging/file.pdf',
      ]);
      await expectLater(
        store!.rebaseAttachmentPaths(
          previousDirectory: 'relative/profile',
          currentDirectory: current,
        ),
        throwsA(isA<StorageException>()),
      );
    },
  );

  test('legacy import is atomic and can be retried', () async {
    const account = AccountRecord(
      id: 'legacy',
      platform: 'telegram',
      displayName: 'Legacy Telegram',
    );
    final contact = ContactRecord(
      id: 'person',
      displayName: 'Person',
      identities: [const IdentityLink('legacy', 'identity')],
    );
    final invalidContact = ContactRecord(
      id: 'invalid-person',
      displayName: 'Invalid person',
      identities: [const IdentityLink('missing-account', 'identity')],
    );
    await expectLater(
      store!.importLegacy(
        accounts: [account],
        contacts: [contact, invalidContact],
      ),
      throwsA(isA<StorageException>()),
    );
    expect(await store!.loadAccounts(), isEmpty);
    expect(await store!.loadContacts(), isEmpty);
    const preference = ConversationPreferencesRecord(
      route: ConversationRoute('legacy', 'not-cached'),
      isFavorite: true,
    );
    for (var attempt = 0; attempt < 2; attempt++) {
      await store!.importLegacy(
        accounts: [account],
        contacts: [contact],
        preferences: [preference],
      );
    }
    await reopen();
    expect((await store!.loadAccounts()).single.id, 'legacy');
    expect(
      (await store!.loadContacts()).single.identities.single.identityId,
      'identity',
    );
    expect(
      (await store!.loadConversationPreferences()).single.isFavorite,
      isTrue,
    );
  });

  test(
    'schema four upgrade preserves message senders and adds reactions',
    () async {
      await seed(route);
      await store!.saveMessage(
        MessageRecord(
          id: 'original',
          route: route,
          body: 'Keep message',
          timestamp: instant,
          isOutgoing: false,
          senderId: 'original-sender',
        ),
      );
      await store!.saveDraft(
        route,
        'Reply draft',
        replyToMessageId: 'original',
      );
      await store!.enqueueDraft(route, sendId: 'queued-reply');
      await store!.close();
      store = null;
      final raw = sqlite.sqlite3.open(file.path);
      final hex = key.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      raw.execute("PRAGMA cipher = 'chacha20'");
      raw.execute("PRAGMA key = 'raw:$hex'");
      raw.execute('DROP TABLE message_reactions');
      raw.execute(
        'ALTER TABLE conversation_preferences DROP COLUMN read_through_micros',
      );
      raw.execute('PRAGMA user_version = 4');
      raw.close();
      store = await LocalStore.open(file: file, key: key);
      expect(
        (await store!.loadRecentMessages(route)).single.senderId,
        'original-sender',
      );
      expect((await store!.loadDraft(route))!.replyToMessageId, 'original');
      expect(
        (await store!.loadPendingSends()).single.replyToMessageId,
        'original',
      );
      expect(await store!.loadMessageReactions(), isEmpty);
      await store!.setReaction(
        route,
        'original',
        'actor',
        '👍',
        includesMe: true,
      );
      await reopen();
      expect(
        (await store!.loadReactions(route, 'original')).single.includesMe,
        isTrue,
      );
    },
  );

  test(
    'schema three upgrade retains conversations, messages and reply drafts',
    () async {
      await seed(route);
      await store!.saveMessage(message(route, 'original'));
      await store!.saveDraft(
        route,
        'Reply draft',
        replyToMessageId: 'original',
      );
      await store!.enqueueDraft(route, sendId: 'queued-reply');
      await store!.close();
      store = null;
      final raw = sqlite.sqlite3.open(file.path);
      final hex = key.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      raw.execute("PRAGMA cipher = 'chacha20'");
      raw.execute("PRAGMA key = 'raw:$hex'");
      raw.execute('ALTER TABLE messages DROP COLUMN sender_id');
      raw.execute('DROP TABLE message_reactions');
      raw.execute(
        'ALTER TABLE conversation_preferences DROP COLUMN read_through_micros',
      );
      raw.execute('PRAGMA user_version = 3');
      raw.close();
      store = await LocalStore.open(file: file, key: key);
      expect((await store!.loadConversations()).single.route, route);
      final original = (await store!.loadRecentMessages(route)).single;
      expect(original.id, 'original');
      expect(original.senderId, isNull);
      expect((await store!.loadDraft(route))!.replyToMessageId, 'original');
      expect(
        (await store!.loadPendingSends()).single.replyToMessageId,
        'original',
      );
    },
  );

  test(
    'schema one upgrade preserves profile and send capabilities persist',
    () async {
      await seed(route);
      await store!.saveMessage(message(route, 'm1'));
      await store!.saveDraft(route, 'Keep draft');
      await store!.enqueueDraft(route, sendId: 'pending');
      await store!.saveContact(
        ContactRecord(id: 'person', displayName: 'Person'),
      );
      await store!.saveConversationPreferences(
        const ConversationPreferencesRecord(route: route, isFavorite: true),
      );
      await store!.close();
      store = null;
      final raw = sqlite.sqlite3.open(file.path);
      final hex = key.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      raw.execute("PRAGMA cipher = 'chacha20'");
      raw.execute("PRAGMA key = 'raw:$hex'");
      raw.execute('ALTER TABLE conversations DROP COLUMN can_send');
      raw.execute('ALTER TABLE messages DROP COLUMN sender_id');
      raw.execute('DROP TABLE message_reactions');
      raw.execute(
        'ALTER TABLE conversations DROP COLUMN is_from_unknown_sender',
      );
      raw.execute(
        'ALTER TABLE conversations DROP COLUMN sending_unavailable_reason',
      );
      raw.execute(
        'ALTER TABLE conversation_preferences DROP COLUMN read_through_micros',
      );
      raw.execute('PRAGMA user_version = 1');
      raw.close();

      store = await LocalStore.open(file: file, key: key);
      final conversation = (await store!.loadConversations()).single;
      expect(conversation.canSend, isTrue);
      expect(conversation.sendingUnavailableReason, isNull);
      expect(conversation.isFromUnknownSender, isFalse);
      expect((await store!.loadRecentMessages(route)).single.id, 'm1');
      expect((await store!.loadRecentMessages(route)).single.senderId, isNull);
      expect((await store!.loadDraft(route))!.body, 'Keep draft');
      expect((await store!.loadPendingSends()).single.id, 'pending');
      expect((await store!.loadContacts()).single.id, 'person');
      expect(
        (await store!.loadConversationPreferences()).single.isFavorite,
        isTrue,
      );

      await store!.saveConversation(
        ConversationRecord(
          route: route,
          title: conversation.title,
          latestActivity: conversation.latestActivity,
          canSend: false,
          sendingUnavailableReason: 'encrypted_thread_unsupported',
          isFromUnknownSender: true,
        ),
      );
      await reopen();
      final restored = (await store!.loadConversations()).single;
      expect(restored.canSend, isFalse);
      expect(restored.isFromUnknownSender, isTrue);
      expect(restored.sendingUnavailableReason, 'encrypted_thread_unsupported');
    },
  );

  test('concurrent draft clearing cannot erase a later edit', () async {
    await seed(route);
    for (var i = 0; i < 15; i++) {
      final first = await store!.saveDraft(route, 'First');
      await Future.wait([
        store!.clearDraft(route, expectedRevision: first.revision),
        store!.saveDraft(route, 'Later'),
      ]);
      expect((await store!.loadDraft(route))!.body, 'Later');
    }
  });
}
