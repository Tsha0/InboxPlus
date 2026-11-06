import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'models.dart';

part 'local_store.g.dart';

@DataClassName('AccountRow')
class Accounts extends Table {
  TextColumn get id => text()();
  TextColumn get platform => text()();
  TextColumn get displayName => text()();
  BoolColumn get isConnected => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('ConversationRow')
class Conversations extends Table {
  TextColumn get accountId =>
      text().references(Accounts, #id, onDelete: KeyAction.cascade)();
  TextColumn get conversationId => text()();
  TextColumn get title => text()();
  IntColumn get latestActivityMicros => integer()();
  IntColumn get unreadCount => integer().withDefault(const Constant(0))();
  BoolColumn get isGroup => boolean().withDefault(const Constant(false))();
  TextColumn get identityId => text().nullable()();
  BoolColumn get canSend => boolean().withDefault(const Constant(true))();
  TextColumn get sendingUnavailableReason => text().nullable()();
  BoolColumn get isFromUnknownSender =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {accountId, conversationId};
}

@DataClassName('MessageRow')
@TableIndex(
  name: 'messages_recent',
  columns: {#accountId, #conversationId, #timestampMicros, #id},
)
class Messages extends Table {
  TextColumn get accountId => text()();
  TextColumn get conversationId => text()();
  TextColumn get id => text()();
  TextColumn get body => text()();
  IntColumn get timestampMicros => integer()();
  BoolColumn get isOutgoing => boolean()();
  TextColumn get senderId => text().nullable()();
  TextColumn get senderName => text().nullable()();
  TextColumn get kind => text()();
  TextColumn get deliveryState => text()();
  TextColumn get replyToMessageId => text().nullable()();
  TextColumn get attachmentsJson => text()();

  @override
  Set<Column> get primaryKey => {accountId, conversationId, id};

  @override
  List<String> get customConstraints => [
    'FOREIGN KEY (account_id, conversation_id) REFERENCES '
        'conversations (account_id, conversation_id) ON DELETE CASCADE',
  ];
}

@DataClassName('DraftRow')
class Drafts extends Table {
  TextColumn get accountId => text()();
  TextColumn get conversationId => text()();
  TextColumn get body => text()();
  IntColumn get revision => integer()();
  TextColumn get replyToMessageId => text().nullable()();
  TextColumn get attachmentsJson => text()();

  @override
  Set<Column> get primaryKey => {accountId, conversationId};

  @override
  List<String> get customConstraints => [
    'FOREIGN KEY (account_id, conversation_id) REFERENCES '
        'conversations (account_id, conversation_id) ON DELETE CASCADE',
  ];
}

@DataClassName('PendingSendRow')
class PendingSends extends Table {
  TextColumn get id => text()();
  TextColumn get accountId => text()();
  TextColumn get conversationId => text()();
  TextColumn get body => text()();
  IntColumn get createdAtMicros => integer()();
  IntColumn get draftRevision => integer()();
  TextColumn get status => text()();
  TextColumn get replyToMessageId => text().nullable()();
  TextColumn get attachmentsJson => text()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'FOREIGN KEY (account_id, conversation_id) REFERENCES '
        'conversations (account_id, conversation_id) ON DELETE CASCADE',
  ];
}

@DataClassName('PersonRow')
class People extends Table {
  TextColumn get id => text()();
  TextColumn get displayName => text()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('ContactLinkRow')
class ContactLinks extends Table {
  TextColumn get accountId =>
      text().references(Accounts, #id, onDelete: KeyAction.cascade)();
  TextColumn get identityId => text()();
  TextColumn get personId =>
      text().references(People, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {accountId, identityId};
}

@DataClassName('PreferenceRow')
class ConversationPreferences extends Table {
  TextColumn get accountId =>
      text().references(Accounts, #id, onDelete: KeyAction.cascade)();
  TextColumn get conversationId => text()();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  BoolColumn get markedUnread => boolean().withDefault(const Constant(false))();
  BoolColumn get isMuted => boolean().withDefault(const Constant(false))();
  IntColumn get mutedUntilMicros => integer().nullable()();
  IntColumn get hiddenAtMicros => integer().nullable()();

  @override
  Set<Column> get primaryKey => {accountId, conversationId};
}

@DataClassName('MessageReactionRow')
class MessageReactions extends Table {
  TextColumn get accountId =>
      text().references(Accounts, #id, onDelete: KeyAction.cascade)();
  TextColumn get conversationId => text()();
  TextColumn get messageId => text()();
  TextColumn get sourceId => text()();
  TextColumn get reactionKey => text()();
  IntColumn get count => integer()();
  BoolColumn get includesMe => boolean()();
  IntColumn get recordedAtMicros => integer()();

  @override
  Set<Column> get primaryKey => {
    accountId,
    conversationId,
    messageId,
    sourceId,
  };
}

const _applicationId = 0x494e4250;
const _schemaVersion = 5;

@DriftDatabase(
  tables: [
    Accounts,
    Conversations,
    Messages,
    Drafts,
    PendingSends,
    People,
    ContactLinks,
    ConversationPreferences,
    MessageReactions,
  ],
)
class StorageDatabase extends _$StorageDatabase {
  StorageDatabase(super.executor);

  @override
  int get schemaVersion => _schemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
      await customStatement('PRAGMA application_id = $_applicationId');
    },
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        await migrator.addColumn(conversations, conversations.canSend);
        await migrator.addColumn(
          conversations,
          conversations.sendingUnavailableReason,
        );
      }
      if (from < 3) {
        await migrator.addColumn(
          conversations,
          conversations.isFromUnknownSender,
        );
      }
      if (from < 4) {
        await migrator.addColumn(messages, messages.senderId);
      }
      if (from < 5) {
        await migrator.createTable(messageReactions);
      }
    },
    beforeOpen: (_) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await customStatement('PRAGMA secure_delete = ON');
      await customStatement('PRAGMA temp_store = MEMORY');
    },
  );
}

class LocalStore {
  LocalStore._(this._db);

  final StorageDatabase _db;

  static Future<LocalStore> open({
    required File file,
    required Uint8List key,
  }) async {
    if (key.length != 32) {
      throw const StorageException(StorageErrorCode.invalidKey);
    }
    final hexKey = key
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    StorageDatabase? database;
    try {
      await _prepareFile(file);
      final hasContents = await file.length() != 0;
      if (hasContents) {
        final handle = await file.open();
        try {
          final header = await handle.read(16);
          if (ascii.decode(header, allowInvalid: true) ==
              'SQLite format 3\u0000') {
            throw const StorageException(StorageErrorCode.openFailed);
          }
        } finally {
          await handle.close();
        }
        final probe = sqlite.sqlite3.open(
          file.path,
          mode: sqlite.OpenMode.readOnly,
        );
        try {
          _configure(probe, hexKey);
          _validateSchema(probe);
        } finally {
          probe.close();
        }
      }
      database = StorageDatabase(
        NativeDatabase.createInBackground(
          file,
          setup: (connection) {
            _configure(connection, hexKey);
            _validateSchema(connection);
          },
        ),
      );
      await database.customSelect('SELECT 1').get();
      return LocalStore._(database);
    } catch (error) {
      try {
        await database?.close();
      } catch (_) {}
      if (error is StorageException) rethrow;
      throw const StorageException(StorageErrorCode.openFailed);
    }
  }

  static void _configure(sqlite.Database db, String hexKey) {
    db.execute("PRAGMA cipher = 'chacha20'");
    final cipher = db.select('PRAGMA cipher');
    if (cipher.isEmpty || cipher.first.values.first != 'chacha20') {
      throw const StorageException(StorageErrorCode.openFailed);
    }
    db.execute("PRAGMA key = 'raw:$hexKey'");
    db.select('SELECT count(*) FROM sqlite_master');
  }

  static void _validateSchema(sqlite.Database db) {
    final version = db.userVersion;
    if (version > _schemaVersion) {
      throw const StorageException(StorageErrorCode.unsupportedSchema);
    }
    final applicationId = db.select('PRAGMA application_id').first.values.first;
    if ((applicationId != 0 && applicationId != _applicationId) ||
        (version != 0 && applicationId != _applicationId)) {
      throw const StorageException(StorageErrorCode.openFailed);
    }
    if (version == 0 &&
        db
            .select("SELECT name FROM sqlite_master WHERE type = 'table'")
            .isNotEmpty) {
      throw const StorageException(StorageErrorCode.openFailed);
    }
  }

  Future<void> close() => _write(() => _db.close());

  Future<void> importLegacy({
    List<AccountRecord> accounts = const [],
    List<ContactRecord> contacts = const [],
    List<ConversationPreferencesRecord> preferences = const [],
  }) => _write(
    () => _db.transaction(() async {
      for (final account in accounts) {
        await saveAccount(account);
      }
      for (final contact in contacts) {
        await saveContact(contact);
      }
      for (final preference in preferences) {
        await saveConversationPreferences(preference);
      }
    }),
  );

  Future<T> _read<T>(Future<T> Function() action) =>
      _guard(action, StorageErrorCode.readFailed);
  Future<T> _write<T>(Future<T> Function() action) =>
      _guard(action, StorageErrorCode.writeFailed);

  Future<T> _guard<T>(
    Future<T> Function() action,
    StorageErrorCode code,
  ) async {
    try {
      return await action();
    } on StorageException {
      rethrow;
    } catch (_) {
      throw StorageException(code);
    }
  }

  Future<void> saveAccount(AccountRecord account) => _write(() async {
    _requireId(account.id);
    _requireId(account.platform);
    await _db
        .into(_db.accounts)
        .insertOnConflictUpdate(
          AccountRow(
            id: account.id,
            platform: account.platform,
            displayName: account.displayName,
            isConnected: account.isConnected,
          ),
        );
  });

  Future<List<AccountRecord>> loadAccounts() => _read(() async {
    final rows = await (_db.select(
      _db.accounts,
    )..orderBy([(t) => OrderingTerm.asc(t.id)])).get();
    return rows
        .map(
          (r) => AccountRecord(
            id: r.id,
            platform: r.platform,
            displayName: r.displayName,
            isConnected: r.isConnected,
          ),
        )
        .toList();
  });

  /// Deletes the account with everything stored for it and returns the files it downloaded into
  /// [mediaDirectory], which the caller deletes once the rows are gone.
  Future<List<String>> removeAccount(
    String accountId, {
    String? mediaDirectory,
  }) => _write(
    () => _db.transaction(() async {
      final root = mediaDirectory == null
          ? null
          : await _mediaRoot(mediaDirectory);
      final paths = <String>{};
      if (root != null) {
        final rows = await _db
            .customSelect(
              'SELECT attachments_json FROM messages WHERE account_id = ?',
              variables: [Variable.withString(accountId)],
              readsFrom: {_db.messages},
            )
            .get();
        for (final row in rows) {
          for (final attachment in _decodeAttachments(
            row.read<String>('attachments_json'),
          )) {
            final path = attachment.localPath;
            if (attachment.isDownloadable &&
                path != null &&
                await _isPrivateMediaPath(path, root)) {
              paths.add(_normalizedPath(path));
            }
          }
        }
      }
      await (_db.delete(
        _db.accounts,
      )..where((t) => t.id.equals(accountId))).go();
      return paths.toList()..sort();
    }),
  );

  Future<void> saveConversation(ConversationRecord conversation) =>
      _write(() async {
        _requireRoute(conversation.route);
        if (conversation.unreadCount < 0)
          throw const StorageException(StorageErrorCode.invalidData);
        await _db
            .into(_db.conversations)
            .insertOnConflictUpdate(
              ConversationRow(
                accountId: conversation.route.accountId,
                conversationId: conversation.route.conversationId,
                title: conversation.title,
                latestActivityMicros:
                    conversation.latestActivity.microsecondsSinceEpoch,
                unreadCount: conversation.unreadCount,
                isGroup: conversation.isGroup,
                identityId: conversation.identityId,
                canSend: conversation.canSend,
                sendingUnavailableReason: conversation.sendingUnavailableReason,
                isFromUnknownSender: conversation.isFromUnknownSender,
              ),
            );
      });

  Future<List<ConversationRecord>> loadConversations() => _read(() async {
    final rows =
        await (_db.select(_db.conversations)..orderBy([
              (t) => OrderingTerm.desc(t.latestActivityMicros),
              (t) => OrderingTerm.asc(t.accountId),
              (t) => OrderingTerm.asc(t.conversationId),
            ]))
            .get();
    return rows
        .map(
          (r) => ConversationRecord(
            route: ConversationRoute(r.accountId, r.conversationId),
            title: r.title,
            latestActivity: _date(r.latestActivityMicros),
            unreadCount: r.unreadCount,
            isGroup: r.isGroup,
            identityId: r.identityId,
            canSend: r.canSend,
            sendingUnavailableReason: r.sendingUnavailableReason,
            isFromUnknownSender: r.isFromUnknownSender,
          ),
        )
        .toList();
  });

  Future<void> saveMessage(MessageRecord message) =>
      _write(() => _saveMessage(message));

  Future<int> pruneMessagesBefore(DateTime cutoff) => _write(() async {
    final accounts = _db.selectOnly(_db.accounts)
      ..addColumns([_db.accounts.id])
      ..where(_db.accounts.platform.isNotIn(['imessage', 'legacy']));
    final pending = _db.selectOnly(_db.pendingSends)
      ..addColumns([_db.pendingSends.id]);
    final draftQuotes = _db.selectOnly(_db.drafts)
      ..addColumns([_db.drafts.replyToMessageId])
      ..where(_db.drafts.replyToMessageId.isNotNull());
    final pendingQuotes = _db.selectOnly(_db.pendingSends)
      ..addColumns([_db.pendingSends.replyToMessageId])
      ..where(_db.pendingSends.replyToMessageId.isNotNull());
    final deleted =
        await (_db.delete(_db.messages)..where(
              (m) =>
                  m.timestampMicros.isSmallerThanValue(
                    cutoff.microsecondsSinceEpoch,
                  ) &
                  m.accountId.isInQuery(accounts) &
                  m.id.isNotInQuery(pending) &
                  m.id.isNotInQuery(draftQuotes) &
                  m.id.isNotInQuery(pendingQuotes),
            ))
            .go();
    await _db.customUpdate(
      'DELETE FROM message_reactions WHERE recorded_at_micros < ? '
      "AND account_id IN (SELECT id FROM accounts WHERE platform NOT IN ('imessage', 'legacy')) "
      'AND (account_id, conversation_id, message_id) NOT IN (SELECT account_id, conversation_id, id FROM messages)',
      variables: [Variable.withInt(cutoff.microsecondsSinceEpoch)],
      updates: {_db.messageReactions},
    );
    return deleted;
  });

  Future<void> _saveMessage(MessageRecord message) async {
    _requireId(message.id);
    _requireRoute(message.route);
    await _db
        .into(_db.messages)
        .insertOnConflictUpdate(
          MessageRow(
            accountId: message.route.accountId,
            conversationId: message.route.conversationId,
            id: message.id,
            body: message.body,
            timestampMicros: message.timestamp.microsecondsSinceEpoch,
            isOutgoing: message.isOutgoing,
            senderId: message.senderId,
            senderName: message.senderName,
            kind: message.kind,
            deliveryState: message.deliveryState.name,
            replyToMessageId: message.replyToMessageId,
            attachmentsJson: _encodeAttachments(message.attachments),
          ),
        );
  }

  Future<LocalStorageSummary> loadStorageSummary() => _read(() async {
    final row = await _db
        .customSelect(
          'SELECT COUNT(*) AS message_count, '
          'COALESCE(SUM(json_array_length(attachments_json)), 0) AS attachment_count '
          'FROM messages',
          readsFrom: {_db.messages},
        )
        .getSingle();
    return LocalStorageSummary(
      messageCount: row.read<int>('message_count'),
      attachmentCount: row.read<int>('attachment_count'),
    );
  });

  Future<List<String>> clearDownloadedMediaPaths(String directory) => _write(
    () => _db.transaction(() async {
      final rootPath = await _mediaRoot(directory);
      if (rootPath == null) return <String>[];
      final protectedPaths = <String>{};
      Future<void> protect(List<AttachmentRecord> attachments) async {
        for (final attachment in attachments) {
          final path = attachment.localPath;
          if (path == null) continue;
          protectedPaths.add(_normalizedPath(path));
          if (await File(path).exists()) {
            protectedPaths.add(await File(path).resolveSymbolicLinks());
          }
        }
      }

      final drafts = await _db.select(_db.drafts).get();
      final pending = await _db.select(_db.pendingSends).get();
      for (final row in drafts) {
        await protect(_decodeAttachments(row.attachmentsJson));
      }
      for (final row in pending) {
        await protect(_decodeAttachments(row.attachmentsJson));
      }
      final rows = await _db
          .customSelect(
            'SELECT account_id, conversation_id, id, attachments_json FROM messages',
            readsFrom: {_db.messages},
          )
          .get();
      final attachments = <List<AttachmentRecord>>[];
      for (final row in rows) {
        final decoded = _decodeAttachments(
          row.read<String>('attachments_json'),
        );
        attachments.add(decoded);
        await protect(decoded.where((a) => !a.isDownloadable).toList());
      }
      final paths = <String>{};
      for (var index = 0; index < rows.length; index++) {
        final updated = <AttachmentRecord>[];
        var changed = false;
        for (final attachment in attachments[index]) {
          final path = attachment.localPath;
          if (attachment.isDownloadable &&
              path != null &&
              !protectedPaths.contains(_normalizedPath(path)) &&
              await _isPrivateMediaPath(path, rootPath)) {
            changed = true;
            paths.add(_normalizedPath(path));
            updated.add(_attachmentWithPath(attachment, null));
          } else {
            updated.add(attachment);
          }
        }
        if (changed) {
          final row = rows[index];
          await (_db.update(_db.messages)..where(
                (t) =>
                    t.accountId.equals(row.read<String>('account_id')) &
                    t.conversationId.equals(
                      row.read<String>('conversation_id'),
                    ) &
                    t.id.equals(row.read<String>('id')),
              ))
              .write(
                MessagesCompanion(
                  attachmentsJson: Value(_encodeAttachments(updated)),
                ),
              );
        }
      }
      return paths.toList()..sort();
    }),
  );

  Future<int> rebaseAttachmentPaths({
    required String previousDirectory,
    required String currentDirectory,
  }) => _write(
    () => _db.transaction(() async {
      if (previousDirectory != _normalizedPath(previousDirectory) ||
          currentDirectory != _normalizedPath(currentDirectory)) {
        throw const StorageException(StorageErrorCode.invalidData);
      }
      final current = Directory(currentDirectory);
      if (await FileSystemEntity.type(currentDirectory, followLinks: false) !=
              FileSystemEntityType.directory ||
          await current.resolveSymbolicLinks() != currentDirectory ||
          (!Platform.isWindows &&
              (await current.stat()).mode & 0x1ff != 0x1c0)) {
        throw const StorageException(StorageErrorCode.invalidData);
      }
      var ancestor = Directory(previousDirectory);
      while (true) {
        final type = await FileSystemEntity.type(
          ancestor.path,
          followLinks: false,
        );
        if (type != FileSystemEntityType.notFound &&
            type != FileSystemEntityType.directory) {
          throw const StorageException(StorageErrorCode.invalidData);
        }
        final parent = ancestor.parent;
        if (parent.path == ancestor.path) break;
        ancestor = parent;
      }
      if (previousDirectory == currentDirectory) return 0;
      var count = 0;
      for (final table in <TableInfo>[
        _db.messages,
        _db.drafts,
        _db.pendingSends,
      ]) {
        final rows = await _db
            .customSelect(
              'SELECT rowid AS row_id, attachments_json FROM ${table.actualTableName}',
              readsFrom: {table},
            )
            .get();
        for (final row in rows) {
          final attachments = _decodeAttachments(
            row.read<String>('attachments_json'),
          );
          final updated = <AttachmentRecord>[];
          var changed = false;
          for (final attachment in attachments) {
            final path = attachment.localPath;
            if (path == null ||
                path != _normalizedPath(path) ||
                !['media', 'staging'].any(
                  (folder) => path.startsWith(
                    '$previousDirectory${Platform.pathSeparator}$folder${Platform.pathSeparator}',
                  ),
                )) {
              updated.add(attachment);
              continue;
            }
            final rebased =
                '$currentDirectory${path.substring(previousDirectory.length)}';
            if (!await _isPrivateMediaPath(rebased, currentDirectory)) {
              throw const StorageException(StorageErrorCode.invalidData);
            }
            updated.add(_attachmentWithPath(attachment, rebased));
            changed = true;
            count++;
          }
          if (changed) {
            await _db.customUpdate(
              'UPDATE ${table.actualTableName} SET attachments_json = ? WHERE rowid = ?',
              variables: [
                Variable(_encodeAttachments(updated)),
                Variable(row.read<int>('row_id')),
              ],
              updates: {table},
            );
          }
        }
      }
      return count;
    }),
  );

  Future<List<MessageRecord>> loadRecentMessages(
    ConversationRoute route, {
    int limit = 50,
  }) => _read(() async {
    if (limit <= 0) throw const StorageException(StorageErrorCode.invalidData);
    final rows =
        await (_db.select(_db.messages)
              ..where(
                (t) =>
                    t.accountId.equals(route.accountId) &
                    t.conversationId.equals(route.conversationId),
              )
              ..orderBy([
                (t) => OrderingTerm.desc(t.timestampMicros),
                (t) => OrderingTerm.desc(t.id),
              ])
              ..limit(limit))
            .get();
    return rows.reversed.map(_message).toList();
  });

  Future<MessageRecord?> loadMessage(ConversationRoute route, String id) =>
      _read(() async {
        final row =
            await (_db.select(_db.messages)..where(
                  (t) =>
                      t.accountId.equals(route.accountId) &
                      t.conversationId.equals(route.conversationId) &
                      t.id.equals(id),
                ))
                .getSingleOrNull();
        return row == null ? null : _message(row);
      });

  Future<List<MessageReactionsRecord>> loadMessageReactions() => _read(
    () async =>
        _reactionSummaries(await _db.select(_db.messageReactions).get()),
  );

  Future<List<MessageReactionRecord>> loadReactions(
    ConversationRoute route,
    String messageId,
  ) => _read(() async {
    final rows =
        await (_db.select(_db.messageReactions)..where(
              (r) =>
                  r.accountId.equals(route.accountId) &
                  r.conversationId.equals(route.conversationId) &
                  r.messageId.equals(messageId),
            ))
            .get();
    return _reactionSummaries(rows).firstOrNull?.reactions ?? [];
  });

  Future<void> setReaction(
    ConversationRoute route,
    String messageId,
    String senderId,
    String key, {
    required bool includesMe,
    DateTime? timestamp,
  }) => _write(
    () => _db.transaction(() async {
      _requireRoute(route);
      _requireId(messageId);
      _requireId(senderId);
      final sourceId = 'actor:$senderId';
      final recordedAt = (timestamp ?? DateTime.now()).microsecondsSinceEpoch;
      final previous =
          await (_db.select(_db.messageReactions)..where(
                (r) =>
                    r.accountId.equals(route.accountId) &
                    r.conversationId.equals(route.conversationId) &
                    r.messageId.equals(messageId) &
                    r.sourceId.equals(sourceId),
              ))
              .getSingleOrNull();
      if (previous != null && previous.recordedAtMicros > recordedAt) return;
      await _db
          .into(_db.messageReactions)
          .insertOnConflictUpdate(
            MessageReactionRow(
              accountId: route.accountId,
              conversationId: route.conversationId,
              messageId: messageId,
              sourceId: sourceId,
              reactionKey: key,
              count: key.isEmpty ? 0 : 1,
              includesMe: includesMe,
              recordedAtMicros: recordedAt,
            ),
          );
    }),
  );

  Future<void> replaceReactions(
    ConversationRoute route,
    String messageId,
    List<MessageReactionRecord> reactions,
  ) => _write(
    () => _db.transaction(() async {
      _requireRoute(route);
      _requireId(messageId);
      await (_db.delete(_db.messageReactions)..where(
            (r) =>
                r.accountId.equals(route.accountId) &
                r.conversationId.equals(route.conversationId) &
                r.messageId.equals(messageId),
          ))
          .go();
      final now = DateTime.now().microsecondsSinceEpoch;
      for (final reaction in reactions) {
        _requireId(reaction.key);
        if (reaction.count < 1 ||
            (reaction.senderId != null && reaction.count != 1)) {
          throw const StorageException(StorageErrorCode.invalidData);
        }
        if (reaction.senderId != null) _requireId(reaction.senderId!);
        await _db
            .into(_db.messageReactions)
            .insert(
              MessageReactionRow(
                accountId: route.accountId,
                conversationId: route.conversationId,
                messageId: messageId,
                sourceId: reaction.senderId == null
                    ? 'emoji:${reaction.key}'
                    : 'actor:${reaction.senderId}',
                reactionKey: reaction.key,
                count: reaction.count,
                includesMe: reaction.includesMe,
                recordedAtMicros:
                    reaction.timestamp?.microsecondsSinceEpoch ??
                    (reaction.senderId == null ? now : 0),
              ),
            );
      }
    }),
  );

  List<MessageReactionsRecord> _reactionSummaries(
    List<MessageReactionRow> rows,
  ) {
    final grouped =
        <(ConversationRoute, String), Map<String, MessageReactionRecord>>{};
    for (final row in rows) {
      if (row.count == 0) continue;
      final values = grouped.putIfAbsent((
        ConversationRoute(row.accountId, row.conversationId),
        row.messageId,
      ), () => {});
      final previous = values[row.reactionKey];
      values[row.reactionKey] = MessageReactionRecord(
        key: row.reactionKey,
        count: (previous?.count ?? 0) + row.count,
        includesMe: row.includesMe || previous?.includesMe == true,
      );
    }
    return [
      for (final entry in grouped.entries)
        MessageReactionsRecord(
          route: entry.key.$1,
          messageId: entry.key.$2,
          reactions: List.unmodifiable(entry.value.values),
        ),
    ];
  }

  Future<void> deleteMessage(ConversationRoute route, String messageId) =>
      _write(
        () => _db.transaction(() async {
          await (_db.delete(_db.messages)..where(
                (t) =>
                    t.accountId.equals(route.accountId) &
                    t.conversationId.equals(route.conversationId) &
                    t.id.equals(messageId),
              ))
              .go();
          await (_db.delete(_db.messageReactions)..where(
                (r) =>
                    r.accountId.equals(route.accountId) &
                    r.conversationId.equals(route.conversationId) &
                    r.messageId.equals(messageId),
              ))
              .go();
        }),
      );

  Future<DraftRecord> saveDraft(
    ConversationRoute route,
    String body, {
    String? replyToMessageId,
    List<AttachmentRecord> attachments = const [],
  }) => _write(
    () => _db.transaction(() async {
      _requireRoute(route);
      final previous = await _loadDraft(route);
      final revision = (previous?.revision ?? 0) + 1;
      await _db
          .into(_db.drafts)
          .insertOnConflictUpdate(
            DraftRow(
              accountId: route.accountId,
              conversationId: route.conversationId,
              body: body,
              revision: revision,
              replyToMessageId: replyToMessageId,
              attachmentsJson: _encodeAttachments(attachments),
            ),
          );
      return DraftRecord(
        route: route,
        body: body,
        revision: revision,
        replyToMessageId: replyToMessageId,
        attachments: attachments,
      );
    }),
  );

  Future<DraftRecord?> loadDraft(ConversationRoute route) =>
      _read(() => _loadDraft(route));

  Future<DraftRecord?> _loadDraft(ConversationRoute route) async {
    final row =
        await (_db.select(_db.drafts)..where(
              (t) =>
                  t.accountId.equals(route.accountId) &
                  t.conversationId.equals(route.conversationId),
            ))
            .getSingleOrNull();
    return row == null
        ? null
        : DraftRecord(
            route: route,
            body: row.body,
            revision: row.revision,
            replyToMessageId: row.replyToMessageId,
            attachments: _decodeAttachments(row.attachmentsJson),
          );
  }

  Future<bool> clearDraft(
    ConversationRoute route, {
    required int expectedRevision,
  }) => _write(() => _clearDraft(route, expectedRevision));

  Future<bool> _clearDraft(
    ConversationRoute route,
    int expectedRevision,
  ) async {
    final updated = await _db.customUpdate(
      'UPDATE drafts SET body = ?, revision = revision + 1, '
      'reply_to_message_id = NULL, attachments_json = ? '
      'WHERE account_id = ? AND conversation_id = ? AND revision = ?',
      variables: [
        const Variable(''),
        const Variable('[]'),
        Variable(route.accountId),
        Variable(route.conversationId),
        Variable(expectedRevision),
      ],
      updates: {_db.drafts},
    );
    return updated != 0;
  }

  Future<PendingSendRecord> enqueueDraft(
    ConversationRoute route, {
    required String sendId,
    DateTime? now,
  }) => _write(
    () => _db.transaction(() async {
      _requireId(sendId);
      final existing = await (_db.select(
        _db.pendingSends,
      )..where((t) => t.id.equals(sendId))).getSingleOrNull();
      if (existing != null) {
        if (existing.accountId != route.accountId ||
            existing.conversationId != route.conversationId)
          throw const StorageException(StorageErrorCode.invalidData);
        return _pending(existing);
      }
      final draft = await _loadDraft(route);
      if (draft == null ||
          (draft.body.trim().isEmpty && draft.attachments.isEmpty))
        throw const StorageException(StorageErrorCode.invalidData);
      final row = PendingSendRow(
        id: sendId,
        accountId: route.accountId,
        conversationId: route.conversationId,
        body: draft.body,
        createdAtMicros: (now ?? DateTime.now()).microsecondsSinceEpoch,
        draftRevision: draft.revision,
        status: PendingSendStatus.queued.name,
        replyToMessageId: draft.replyToMessageId,
        attachmentsJson: _encodeAttachments(draft.attachments),
      );
      await _db.into(_db.pendingSends).insert(row);
      return _pending(row);
    }),
  );

  Future<List<PendingSendRecord>> loadPendingSends() => _read(() async {
    final rows =
        await (_db.select(_db.pendingSends)..orderBy([
              (t) => OrderingTerm.asc(t.createdAtMicros),
              (t) => OrderingTerm.asc(t.id),
            ]))
            .get();
    return rows.map(_pending).toList();
  });

  Future<void> savePendingSendStatus(String sendId, PendingSendStatus status) =>
      _write(() async {
        await (_db.update(_db.pendingSends)..where((t) => t.id.equals(sendId)))
            .write(PendingSendsCompanion(status: Value(status.name)));
      });

  Future<void> removePendingSend(String sendId) => _write(() async {
    await (_db.delete(
      _db.pendingSends,
    )..where((t) => t.id.equals(sendId))).go();
  });

  Future<bool> resolvePendingSend(
    String sendId, {
    required bool clearCapturedDraft,
  }) => _write(
    () => _db.transaction(() async {
      final row = await (_db.select(
        _db.pendingSends,
      )..where((t) => t.id.equals(sendId))).getSingleOrNull();
      if (row == null) return false;
      if (clearCapturedDraft) {
        await _clearDraft(
          ConversationRoute(row.accountId, row.conversationId),
          row.draftRevision,
        );
      }
      await (_db.delete(
        _db.pendingSends,
      )..where((t) => t.id.equals(sendId))).go();
      return true;
    }),
  );

  Future<bool> completeSend(String sendId, MessageRecord message) => _write(
    () => _db.transaction(() async {
      final row = await (_db.select(
        _db.pendingSends,
      )..where((t) => t.id.equals(sendId))).getSingleOrNull();
      if (row == null) return false;
      final route = ConversationRoute(row.accountId, row.conversationId);
      if (message.route != route ||
          !message.isOutgoing ||
          message.deliveryState != DeliveryState.acknowledged)
        throw const StorageException(StorageErrorCode.invalidData);
      await _saveMessage(message);
      await (_db.update(_db.conversations)..where(
            (t) =>
                t.accountId.equals(route.accountId) &
                t.conversationId.equals(route.conversationId) &
                t.latestActivityMicros.isSmallerThanValue(
                  message.timestamp.microsecondsSinceEpoch,
                ),
          ))
          .write(
            ConversationsCompanion(
              latestActivityMicros: Value(
                message.timestamp.microsecondsSinceEpoch,
              ),
            ),
          );
      await (_db.delete(
        _db.pendingSends,
      )..where((t) => t.id.equals(sendId))).go();
      await _clearDraft(route, row.draftRevision);
      return true;
    }),
  );

  Future<void> saveContact(ContactRecord contact) => _write(
    () => _db.transaction(() async {
      _requireId(contact.id);
      await _db
          .into(_db.people)
          .insertOnConflictUpdate(
            PersonRow(id: contact.id, displayName: contact.displayName),
          );
      await (_db.delete(
        _db.contactLinks,
      )..where((t) => t.personId.equals(contact.id))).go();
      for (final identity in contact.identities) {
        _requireId(identity.identityId);
        await _db
            .into(_db.contactLinks)
            .insert(
              ContactLinkRow(
                accountId: identity.accountId,
                identityId: identity.identityId,
                personId: contact.id,
              ),
            );
      }
    }),
  );

  Future<List<ContactRecord>> loadContacts() => _read(
    () => _db.transaction(() async {
      final people = await (_db.select(
        _db.people,
      )..orderBy([(t) => OrderingTerm.asc(t.id)])).get();
      final links =
          await (_db.select(_db.contactLinks)..orderBy([
                (t) => OrderingTerm.asc(t.accountId),
                (t) => OrderingTerm.asc(t.identityId),
              ]))
              .get();
      return people
          .map(
            (p) => ContactRecord(
              id: p.id,
              displayName: p.displayName,
              identities: links
                  .where((l) => l.personId == p.id)
                  .map((l) => IdentityLink(l.accountId, l.identityId))
                  .toList(),
            ),
          )
          .toList();
    }),
  );

  Future<void> moveIdentityToContact(
    IdentityLink identity,
    ContactRecord person,
  ) => _write(
    () => _db.transaction(() async {
      _requireId(identity.identityId);
      _requireId(person.id);
      await _db
          .into(_db.people)
          .insertOnConflictUpdate(
            PersonRow(id: person.id, displayName: person.displayName),
          );
      await _db
          .into(_db.contactLinks)
          .insertOnConflictUpdate(
            ContactLinkRow(
              accountId: identity.accountId,
              identityId: identity.identityId,
              personId: person.id,
            ),
          );
    }),
  );

  Future<void> removeContact(String personId) => _write(() async {
    await (_db.delete(_db.people)..where((t) => t.id.equals(personId))).go();
  });

  Future<void> saveConversationPreferences(
    ConversationPreferencesRecord preferences,
  ) => _write(() async {
    _requireRoute(preferences.route);
    if (!preferences.isMuted && preferences.mutedUntil != null)
      throw const StorageException(StorageErrorCode.invalidData);
    await _db
        .into(_db.conversationPreferences)
        .insertOnConflictUpdate(
          PreferenceRow(
            accountId: preferences.route.accountId,
            conversationId: preferences.route.conversationId,
            isFavorite: preferences.isFavorite,
            markedUnread: preferences.markedUnread,
            isMuted: preferences.isMuted,
            mutedUntilMicros: preferences.mutedUntil?.microsecondsSinceEpoch,
            hiddenAtMicros: preferences.hiddenAt?.microsecondsSinceEpoch,
          ),
        );
  });

  Future<List<ConversationPreferencesRecord>> loadConversationPreferences() =>
      _read(() async {
        final rows =
            await (_db.select(_db.conversationPreferences)..orderBy([
                  (t) => OrderingTerm.asc(t.accountId),
                  (t) => OrderingTerm.asc(t.conversationId),
                ]))
                .get();
        return rows
            .map(
              (r) => ConversationPreferencesRecord(
                route: ConversationRoute(r.accountId, r.conversationId),
                isFavorite: r.isFavorite,
                markedUnread: r.markedUnread,
                isMuted: r.isMuted,
                mutedUntil: r.mutedUntilMicros == null
                    ? null
                    : _date(r.mutedUntilMicros!),
                hiddenAt: r.hiddenAtMicros == null
                    ? null
                    : _date(r.hiddenAtMicros!),
              ),
            )
            .toList();
      });
}

PendingSendRecord _pending(PendingSendRow row) => PendingSendRecord(
  id: row.id,
  route: ConversationRoute(row.accountId, row.conversationId),
  body: row.body,
  createdAt: _date(row.createdAtMicros),
  draftRevision: row.draftRevision,
  status: PendingSendStatus.values.byName(row.status),
  replyToMessageId: row.replyToMessageId,
  attachments: _decodeAttachments(row.attachmentsJson),
);

MessageRecord _message(MessageRow row) => MessageRecord(
  id: row.id,
  route: ConversationRoute(row.accountId, row.conversationId),
  body: row.body,
  timestamp: _date(row.timestampMicros),
  isOutgoing: row.isOutgoing,
  senderId: row.senderId,
  senderName: row.senderName,
  kind: row.kind,
  deliveryState: DeliveryState.values.byName(row.deliveryState),
  replyToMessageId: row.replyToMessageId,
  attachments: _decodeAttachments(row.attachmentsJson),
);

DateTime _date(int micros) =>
    DateTime.fromMicrosecondsSinceEpoch(micros, isUtc: true);

void _requireId(String value) {
  if (value.trim().isEmpty)
    throw const StorageException(StorageErrorCode.invalidData);
}

void _requireRoute(ConversationRoute route) {
  _requireId(route.accountId);
  _requireId(route.conversationId);
}

String _encodeAttachments(List<AttachmentRecord> attachments) => jsonEncode(
  attachments.map((a) {
    _requireId(a.id);
    if (a.byteCount != null && a.byteCount! < 0)
      throw const StorageException(StorageErrorCode.invalidData);
    return {
      'id': a.id,
      'kind': a.kind,
      'fileName': a.fileName,
      'mimeType': a.mimeType,
      'byteCount': a.byteCount,
      'localPath': a.localPath,
      'remoteSource': a.remoteSource,
      'deepLink': a.deepLink,
      'isDownloadable': a.isDownloadable,
    };
  }).toList(),
);

List<AttachmentRecord> _decodeAttachments(String value) =>
    (jsonDecode(value) as List).map((entry) {
      final a = entry as Map<String, dynamic>;
      return AttachmentRecord(
        id: a['id'] as String,
        kind: a['kind'] as String,
        fileName: a['fileName'] as String?,
        mimeType: a['mimeType'] as String?,
        byteCount: a['byteCount'] as int?,
        localPath: a['localPath'] as String?,
        remoteSource: a['remoteSource'] as String?,
        deepLink: a['deepLink'] as String?,
        isDownloadable: a['isDownloadable'] as bool? ?? true,
      );
    }).toList();

String _normalizedPath(String path) =>
    File(path).absolute.uri.normalizePath().toFilePath();

AttachmentRecord _attachmentWithPath(
  AttachmentRecord attachment,
  String? path,
) => AttachmentRecord(
  id: attachment.id,
  kind: attachment.kind,
  fileName: attachment.fileName,
  mimeType: attachment.mimeType,
  byteCount: attachment.byteCount,
  localPath: path,
  remoteSource: attachment.remoteSource,
  deepLink: attachment.deepLink,
  isDownloadable: attachment.isDownloadable,
);

Future<String?> _mediaRoot(String directory) async {
  final root = Directory(directory);
  final type = await FileSystemEntity.type(root.path, followLinks: false);
  if (type == FileSystemEntityType.notFound) return null;
  if (type != FileSystemEntityType.directory ||
      await root.resolveSymbolicLinks() != _normalizedPath(root.path)) {
    throw const StorageException(StorageErrorCode.invalidData);
  }
  return _normalizedPath(root.path);
}

Future<bool> _isPrivateMediaPath(String path, String root) async {
  final normalized = _normalizedPath(path);
  if (!normalized.startsWith('$root${Platform.pathSeparator}')) return false;
  final type = await FileSystemEntity.type(normalized, followLinks: false);
  if (type != FileSystemEntityType.notFound &&
      type != FileSystemEntityType.file) {
    return false;
  }
  var ancestor = File(normalized).parent;
  while (ancestor.path != root) {
    final type = await FileSystemEntity.type(ancestor.path, followLinks: false);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.directory)
      return false;
    ancestor = ancestor.parent;
  }
  return true;
}

Future<void> _prepareFile(File file) async {
  var ancestor = file.absolute.parent;
  while (true) {
    final type = await FileSystemEntity.type(ancestor.path, followLinks: false);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.directory) {
      throw const StorageException(StorageErrorCode.openFailed);
    }
    final next = ancestor.parent;
    if (next.path == ancestor.path) break;
    ancestor = next;
  }
  final type = await FileSystemEntity.type(file.path, followLinks: false);
  if (type != FileSystemEntityType.notFound &&
      type != FileSystemEntityType.file) {
    throw const StorageException(StorageErrorCode.openFailed);
  }
  final parent = file.parent;
  if (!await parent.exists()) {
    await parent.create(recursive: true);
  }
  if (await FileSystemEntity.type(parent.path, followLinks: false) !=
      FileSystemEntityType.directory) {
    throw const StorageException(StorageErrorCode.openFailed);
  }
  _chmod(parent.path, 0x1c0);
  for (final suffix in ['-journal', '-wal', '-shm']) {
    final sidecar = File('${file.path}$suffix');
    final sidecarType = await FileSystemEntity.type(
      sidecar.path,
      followLinks: false,
    );
    if (sidecarType != FileSystemEntityType.notFound &&
        sidecarType != FileSystemEntityType.file) {
      throw const StorageException(StorageErrorCode.openFailed);
    }
    if (sidecarType == FileSystemEntityType.file) _chmod(sidecar.path, 0x180);
  }
  if (type == FileSystemEntityType.notFound) {
    await file.create(exclusive: true);
  }
  _chmod(file.path, 0x180);
}

void _chmod(String path, int mode) {
  if (Platform.isWindows) return;
  final libc = DynamicLibrary.process();
  final malloc = libc
      .lookupFunction<
        Pointer<Void> Function(IntPtr),
        Pointer<Void> Function(int)
      >('malloc');
  final free = libc
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('free');
  final chmod = libc
      .lookupFunction<
        Int32 Function(Pointer<Uint8>, Uint32),
        int Function(Pointer<Uint8>, int)
      >('chmod');
  final bytes = utf8.encode(path);
  final pointer = malloc(bytes.length + 1).cast<Uint8>();
  if (pointer.address == 0)
    throw const StorageException(StorageErrorCode.openFailed);
  try {
    pointer.asTypedList(bytes.length + 1)
      ..setAll(0, bytes)
      ..[bytes.length] = 0;
    if (chmod(pointer, mode) != 0)
      throw const StorageException(StorageErrorCode.openFailed);
  } finally {
    free(pointer.cast<Void>());
  }
}
