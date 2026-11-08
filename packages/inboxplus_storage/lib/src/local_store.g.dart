// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_store.dart';

// ignore_for_file: type=lint
class $AccountsTable extends Accounts
    with TableInfo<$AccountsTable, AccountRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AccountsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _platformMeta = const VerificationMeta(
    'platform',
  );
  @override
  late final GeneratedColumn<String> platform = GeneratedColumn<String>(
    'platform',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isConnectedMeta = const VerificationMeta(
    'isConnected',
  );
  @override
  late final GeneratedColumn<bool> isConnected = GeneratedColumn<bool>(
    'is_connected',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_connected" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    platform,
    displayName,
    isConnected,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'accounts';
  @override
  VerificationContext validateIntegrity(
    Insertable<AccountRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('platform')) {
      context.handle(
        _platformMeta,
        platform.isAcceptableOrUnknown(data['platform']!, _platformMeta),
      );
    } else if (isInserting) {
      context.missing(_platformMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_displayNameMeta);
    }
    if (data.containsKey('is_connected')) {
      context.handle(
        _isConnectedMeta,
        isConnected.isAcceptableOrUnknown(
          data['is_connected']!,
          _isConnectedMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AccountRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AccountRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      platform: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}platform'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      )!,
      isConnected: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_connected'],
      )!,
    );
  }

  @override
  $AccountsTable createAlias(String alias) {
    return $AccountsTable(attachedDatabase, alias);
  }
}

class AccountRow extends DataClass implements Insertable<AccountRow> {
  final String id;
  final String platform;
  final String displayName;
  final bool isConnected;
  const AccountRow({
    required this.id,
    required this.platform,
    required this.displayName,
    required this.isConnected,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['platform'] = Variable<String>(platform);
    map['display_name'] = Variable<String>(displayName);
    map['is_connected'] = Variable<bool>(isConnected);
    return map;
  }

  AccountsCompanion toCompanion(bool nullToAbsent) {
    return AccountsCompanion(
      id: Value(id),
      platform: Value(platform),
      displayName: Value(displayName),
      isConnected: Value(isConnected),
    );
  }

  factory AccountRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AccountRow(
      id: serializer.fromJson<String>(json['id']),
      platform: serializer.fromJson<String>(json['platform']),
      displayName: serializer.fromJson<String>(json['displayName']),
      isConnected: serializer.fromJson<bool>(json['isConnected']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'platform': serializer.toJson<String>(platform),
      'displayName': serializer.toJson<String>(displayName),
      'isConnected': serializer.toJson<bool>(isConnected),
    };
  }

  AccountRow copyWith({
    String? id,
    String? platform,
    String? displayName,
    bool? isConnected,
  }) => AccountRow(
    id: id ?? this.id,
    platform: platform ?? this.platform,
    displayName: displayName ?? this.displayName,
    isConnected: isConnected ?? this.isConnected,
  );
  AccountRow copyWithCompanion(AccountsCompanion data) {
    return AccountRow(
      id: data.id.present ? data.id.value : this.id,
      platform: data.platform.present ? data.platform.value : this.platform,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      isConnected: data.isConnected.present
          ? data.isConnected.value
          : this.isConnected,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AccountRow(')
          ..write('id: $id, ')
          ..write('platform: $platform, ')
          ..write('displayName: $displayName, ')
          ..write('isConnected: $isConnected')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, platform, displayName, isConnected);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AccountRow &&
          other.id == this.id &&
          other.platform == this.platform &&
          other.displayName == this.displayName &&
          other.isConnected == this.isConnected);
}

class AccountsCompanion extends UpdateCompanion<AccountRow> {
  final Value<String> id;
  final Value<String> platform;
  final Value<String> displayName;
  final Value<bool> isConnected;
  final Value<int> rowid;
  const AccountsCompanion({
    this.id = const Value.absent(),
    this.platform = const Value.absent(),
    this.displayName = const Value.absent(),
    this.isConnected = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AccountsCompanion.insert({
    required String id,
    required String platform,
    required String displayName,
    this.isConnected = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       platform = Value(platform),
       displayName = Value(displayName);
  static Insertable<AccountRow> custom({
    Expression<String>? id,
    Expression<String>? platform,
    Expression<String>? displayName,
    Expression<bool>? isConnected,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (platform != null) 'platform': platform,
      if (displayName != null) 'display_name': displayName,
      if (isConnected != null) 'is_connected': isConnected,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AccountsCompanion copyWith({
    Value<String>? id,
    Value<String>? platform,
    Value<String>? displayName,
    Value<bool>? isConnected,
    Value<int>? rowid,
  }) {
    return AccountsCompanion(
      id: id ?? this.id,
      platform: platform ?? this.platform,
      displayName: displayName ?? this.displayName,
      isConnected: isConnected ?? this.isConnected,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (platform.present) {
      map['platform'] = Variable<String>(platform.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (isConnected.present) {
      map['is_connected'] = Variable<bool>(isConnected.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AccountsCompanion(')
          ..write('id: $id, ')
          ..write('platform: $platform, ')
          ..write('displayName: $displayName, ')
          ..write('isConnected: $isConnected, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ConversationsTable extends Conversations
    with TableInfo<$ConversationsTable, ConversationRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ConversationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES accounts (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _conversationIdMeta = const VerificationMeta(
    'conversationId',
  );
  @override
  late final GeneratedColumn<String> conversationId = GeneratedColumn<String>(
    'conversation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _latestActivityMicrosMeta =
      const VerificationMeta('latestActivityMicros');
  @override
  late final GeneratedColumn<int> latestActivityMicros = GeneratedColumn<int>(
    'latest_activity_micros',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _unreadCountMeta = const VerificationMeta(
    'unreadCount',
  );
  @override
  late final GeneratedColumn<int> unreadCount = GeneratedColumn<int>(
    'unread_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _isGroupMeta = const VerificationMeta(
    'isGroup',
  );
  @override
  late final GeneratedColumn<bool> isGroup = GeneratedColumn<bool>(
    'is_group',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_group" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _identityIdMeta = const VerificationMeta(
    'identityId',
  );
  @override
  late final GeneratedColumn<String> identityId = GeneratedColumn<String>(
    'identity_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _canSendMeta = const VerificationMeta(
    'canSend',
  );
  @override
  late final GeneratedColumn<bool> canSend = GeneratedColumn<bool>(
    'can_send',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("can_send" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _sendingUnavailableReasonMeta =
      const VerificationMeta('sendingUnavailableReason');
  @override
  late final GeneratedColumn<String> sendingUnavailableReason =
      GeneratedColumn<String>(
        'sending_unavailable_reason',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _isFromUnknownSenderMeta =
      const VerificationMeta('isFromUnknownSender');
  @override
  late final GeneratedColumn<bool> isFromUnknownSender = GeneratedColumn<bool>(
    'is_from_unknown_sender',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_from_unknown_sender" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    accountId,
    conversationId,
    title,
    latestActivityMicros,
    unreadCount,
    isGroup,
    identityId,
    canSend,
    sendingUnavailableReason,
    isFromUnknownSender,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'conversations';
  @override
  VerificationContext validateIntegrity(
    Insertable<ConversationRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('conversation_id')) {
      context.handle(
        _conversationIdMeta,
        conversationId.isAcceptableOrUnknown(
          data['conversation_id']!,
          _conversationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_conversationIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('latest_activity_micros')) {
      context.handle(
        _latestActivityMicrosMeta,
        latestActivityMicros.isAcceptableOrUnknown(
          data['latest_activity_micros']!,
          _latestActivityMicrosMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_latestActivityMicrosMeta);
    }
    if (data.containsKey('unread_count')) {
      context.handle(
        _unreadCountMeta,
        unreadCount.isAcceptableOrUnknown(
          data['unread_count']!,
          _unreadCountMeta,
        ),
      );
    }
    if (data.containsKey('is_group')) {
      context.handle(
        _isGroupMeta,
        isGroup.isAcceptableOrUnknown(data['is_group']!, _isGroupMeta),
      );
    }
    if (data.containsKey('identity_id')) {
      context.handle(
        _identityIdMeta,
        identityId.isAcceptableOrUnknown(data['identity_id']!, _identityIdMeta),
      );
    }
    if (data.containsKey('can_send')) {
      context.handle(
        _canSendMeta,
        canSend.isAcceptableOrUnknown(data['can_send']!, _canSendMeta),
      );
    }
    if (data.containsKey('sending_unavailable_reason')) {
      context.handle(
        _sendingUnavailableReasonMeta,
        sendingUnavailableReason.isAcceptableOrUnknown(
          data['sending_unavailable_reason']!,
          _sendingUnavailableReasonMeta,
        ),
      );
    }
    if (data.containsKey('is_from_unknown_sender')) {
      context.handle(
        _isFromUnknownSenderMeta,
        isFromUnknownSender.isAcceptableOrUnknown(
          data['is_from_unknown_sender']!,
          _isFromUnknownSenderMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {accountId, conversationId};
  @override
  ConversationRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ConversationRow(
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      conversationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conversation_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      latestActivityMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}latest_activity_micros'],
      )!,
      unreadCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}unread_count'],
      )!,
      isGroup: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_group'],
      )!,
      identityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}identity_id'],
      ),
      canSend: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}can_send'],
      )!,
      sendingUnavailableReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sending_unavailable_reason'],
      ),
      isFromUnknownSender: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_from_unknown_sender'],
      )!,
    );
  }

  @override
  $ConversationsTable createAlias(String alias) {
    return $ConversationsTable(attachedDatabase, alias);
  }
}

class ConversationRow extends DataClass implements Insertable<ConversationRow> {
  final String accountId;
  final String conversationId;
  final String title;
  final int latestActivityMicros;
  final int unreadCount;
  final bool isGroup;
  final String? identityId;
  final bool canSend;
  final String? sendingUnavailableReason;
  final bool isFromUnknownSender;
  const ConversationRow({
    required this.accountId,
    required this.conversationId,
    required this.title,
    required this.latestActivityMicros,
    required this.unreadCount,
    required this.isGroup,
    this.identityId,
    required this.canSend,
    this.sendingUnavailableReason,
    required this.isFromUnknownSender,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['account_id'] = Variable<String>(accountId);
    map['conversation_id'] = Variable<String>(conversationId);
    map['title'] = Variable<String>(title);
    map['latest_activity_micros'] = Variable<int>(latestActivityMicros);
    map['unread_count'] = Variable<int>(unreadCount);
    map['is_group'] = Variable<bool>(isGroup);
    if (!nullToAbsent || identityId != null) {
      map['identity_id'] = Variable<String>(identityId);
    }
    map['can_send'] = Variable<bool>(canSend);
    if (!nullToAbsent || sendingUnavailableReason != null) {
      map['sending_unavailable_reason'] = Variable<String>(
        sendingUnavailableReason,
      );
    }
    map['is_from_unknown_sender'] = Variable<bool>(isFromUnknownSender);
    return map;
  }

  ConversationsCompanion toCompanion(bool nullToAbsent) {
    return ConversationsCompanion(
      accountId: Value(accountId),
      conversationId: Value(conversationId),
      title: Value(title),
      latestActivityMicros: Value(latestActivityMicros),
      unreadCount: Value(unreadCount),
      isGroup: Value(isGroup),
      identityId: identityId == null && nullToAbsent
          ? const Value.absent()
          : Value(identityId),
      canSend: Value(canSend),
      sendingUnavailableReason: sendingUnavailableReason == null && nullToAbsent
          ? const Value.absent()
          : Value(sendingUnavailableReason),
      isFromUnknownSender: Value(isFromUnknownSender),
    );
  }

  factory ConversationRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ConversationRow(
      accountId: serializer.fromJson<String>(json['accountId']),
      conversationId: serializer.fromJson<String>(json['conversationId']),
      title: serializer.fromJson<String>(json['title']),
      latestActivityMicros: serializer.fromJson<int>(
        json['latestActivityMicros'],
      ),
      unreadCount: serializer.fromJson<int>(json['unreadCount']),
      isGroup: serializer.fromJson<bool>(json['isGroup']),
      identityId: serializer.fromJson<String?>(json['identityId']),
      canSend: serializer.fromJson<bool>(json['canSend']),
      sendingUnavailableReason: serializer.fromJson<String?>(
        json['sendingUnavailableReason'],
      ),
      isFromUnknownSender: serializer.fromJson<bool>(
        json['isFromUnknownSender'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'accountId': serializer.toJson<String>(accountId),
      'conversationId': serializer.toJson<String>(conversationId),
      'title': serializer.toJson<String>(title),
      'latestActivityMicros': serializer.toJson<int>(latestActivityMicros),
      'unreadCount': serializer.toJson<int>(unreadCount),
      'isGroup': serializer.toJson<bool>(isGroup),
      'identityId': serializer.toJson<String?>(identityId),
      'canSend': serializer.toJson<bool>(canSend),
      'sendingUnavailableReason': serializer.toJson<String?>(
        sendingUnavailableReason,
      ),
      'isFromUnknownSender': serializer.toJson<bool>(isFromUnknownSender),
    };
  }

  ConversationRow copyWith({
    String? accountId,
    String? conversationId,
    String? title,
    int? latestActivityMicros,
    int? unreadCount,
    bool? isGroup,
    Value<String?> identityId = const Value.absent(),
    bool? canSend,
    Value<String?> sendingUnavailableReason = const Value.absent(),
    bool? isFromUnknownSender,
  }) => ConversationRow(
    accountId: accountId ?? this.accountId,
    conversationId: conversationId ?? this.conversationId,
    title: title ?? this.title,
    latestActivityMicros: latestActivityMicros ?? this.latestActivityMicros,
    unreadCount: unreadCount ?? this.unreadCount,
    isGroup: isGroup ?? this.isGroup,
    identityId: identityId.present ? identityId.value : this.identityId,
    canSend: canSend ?? this.canSend,
    sendingUnavailableReason: sendingUnavailableReason.present
        ? sendingUnavailableReason.value
        : this.sendingUnavailableReason,
    isFromUnknownSender: isFromUnknownSender ?? this.isFromUnknownSender,
  );
  ConversationRow copyWithCompanion(ConversationsCompanion data) {
    return ConversationRow(
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      title: data.title.present ? data.title.value : this.title,
      latestActivityMicros: data.latestActivityMicros.present
          ? data.latestActivityMicros.value
          : this.latestActivityMicros,
      unreadCount: data.unreadCount.present
          ? data.unreadCount.value
          : this.unreadCount,
      isGroup: data.isGroup.present ? data.isGroup.value : this.isGroup,
      identityId: data.identityId.present
          ? data.identityId.value
          : this.identityId,
      canSend: data.canSend.present ? data.canSend.value : this.canSend,
      sendingUnavailableReason: data.sendingUnavailableReason.present
          ? data.sendingUnavailableReason.value
          : this.sendingUnavailableReason,
      isFromUnknownSender: data.isFromUnknownSender.present
          ? data.isFromUnknownSender.value
          : this.isFromUnknownSender,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ConversationRow(')
          ..write('accountId: $accountId, ')
          ..write('conversationId: $conversationId, ')
          ..write('title: $title, ')
          ..write('latestActivityMicros: $latestActivityMicros, ')
          ..write('unreadCount: $unreadCount, ')
          ..write('isGroup: $isGroup, ')
          ..write('identityId: $identityId, ')
          ..write('canSend: $canSend, ')
          ..write('sendingUnavailableReason: $sendingUnavailableReason, ')
          ..write('isFromUnknownSender: $isFromUnknownSender')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    accountId,
    conversationId,
    title,
    latestActivityMicros,
    unreadCount,
    isGroup,
    identityId,
    canSend,
    sendingUnavailableReason,
    isFromUnknownSender,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ConversationRow &&
          other.accountId == this.accountId &&
          other.conversationId == this.conversationId &&
          other.title == this.title &&
          other.latestActivityMicros == this.latestActivityMicros &&
          other.unreadCount == this.unreadCount &&
          other.isGroup == this.isGroup &&
          other.identityId == this.identityId &&
          other.canSend == this.canSend &&
          other.sendingUnavailableReason == this.sendingUnavailableReason &&
          other.isFromUnknownSender == this.isFromUnknownSender);
}

class ConversationsCompanion extends UpdateCompanion<ConversationRow> {
  final Value<String> accountId;
  final Value<String> conversationId;
  final Value<String> title;
  final Value<int> latestActivityMicros;
  final Value<int> unreadCount;
  final Value<bool> isGroup;
  final Value<String?> identityId;
  final Value<bool> canSend;
  final Value<String?> sendingUnavailableReason;
  final Value<bool> isFromUnknownSender;
  final Value<int> rowid;
  const ConversationsCompanion({
    this.accountId = const Value.absent(),
    this.conversationId = const Value.absent(),
    this.title = const Value.absent(),
    this.latestActivityMicros = const Value.absent(),
    this.unreadCount = const Value.absent(),
    this.isGroup = const Value.absent(),
    this.identityId = const Value.absent(),
    this.canSend = const Value.absent(),
    this.sendingUnavailableReason = const Value.absent(),
    this.isFromUnknownSender = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ConversationsCompanion.insert({
    required String accountId,
    required String conversationId,
    required String title,
    required int latestActivityMicros,
    this.unreadCount = const Value.absent(),
    this.isGroup = const Value.absent(),
    this.identityId = const Value.absent(),
    this.canSend = const Value.absent(),
    this.sendingUnavailableReason = const Value.absent(),
    this.isFromUnknownSender = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : accountId = Value(accountId),
       conversationId = Value(conversationId),
       title = Value(title),
       latestActivityMicros = Value(latestActivityMicros);
  static Insertable<ConversationRow> custom({
    Expression<String>? accountId,
    Expression<String>? conversationId,
    Expression<String>? title,
    Expression<int>? latestActivityMicros,
    Expression<int>? unreadCount,
    Expression<bool>? isGroup,
    Expression<String>? identityId,
    Expression<bool>? canSend,
    Expression<String>? sendingUnavailableReason,
    Expression<bool>? isFromUnknownSender,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (accountId != null) 'account_id': accountId,
      if (conversationId != null) 'conversation_id': conversationId,
      if (title != null) 'title': title,
      if (latestActivityMicros != null)
        'latest_activity_micros': latestActivityMicros,
      if (unreadCount != null) 'unread_count': unreadCount,
      if (isGroup != null) 'is_group': isGroup,
      if (identityId != null) 'identity_id': identityId,
      if (canSend != null) 'can_send': canSend,
      if (sendingUnavailableReason != null)
        'sending_unavailable_reason': sendingUnavailableReason,
      if (isFromUnknownSender != null)
        'is_from_unknown_sender': isFromUnknownSender,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ConversationsCompanion copyWith({
    Value<String>? accountId,
    Value<String>? conversationId,
    Value<String>? title,
    Value<int>? latestActivityMicros,
    Value<int>? unreadCount,
    Value<bool>? isGroup,
    Value<String?>? identityId,
    Value<bool>? canSend,
    Value<String?>? sendingUnavailableReason,
    Value<bool>? isFromUnknownSender,
    Value<int>? rowid,
  }) {
    return ConversationsCompanion(
      accountId: accountId ?? this.accountId,
      conversationId: conversationId ?? this.conversationId,
      title: title ?? this.title,
      latestActivityMicros: latestActivityMicros ?? this.latestActivityMicros,
      unreadCount: unreadCount ?? this.unreadCount,
      isGroup: isGroup ?? this.isGroup,
      identityId: identityId ?? this.identityId,
      canSend: canSend ?? this.canSend,
      sendingUnavailableReason:
          sendingUnavailableReason ?? this.sendingUnavailableReason,
      isFromUnknownSender: isFromUnknownSender ?? this.isFromUnknownSender,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (conversationId.present) {
      map['conversation_id'] = Variable<String>(conversationId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (latestActivityMicros.present) {
      map['latest_activity_micros'] = Variable<int>(latestActivityMicros.value);
    }
    if (unreadCount.present) {
      map['unread_count'] = Variable<int>(unreadCount.value);
    }
    if (isGroup.present) {
      map['is_group'] = Variable<bool>(isGroup.value);
    }
    if (identityId.present) {
      map['identity_id'] = Variable<String>(identityId.value);
    }
    if (canSend.present) {
      map['can_send'] = Variable<bool>(canSend.value);
    }
    if (sendingUnavailableReason.present) {
      map['sending_unavailable_reason'] = Variable<String>(
        sendingUnavailableReason.value,
      );
    }
    if (isFromUnknownSender.present) {
      map['is_from_unknown_sender'] = Variable<bool>(isFromUnknownSender.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ConversationsCompanion(')
          ..write('accountId: $accountId, ')
          ..write('conversationId: $conversationId, ')
          ..write('title: $title, ')
          ..write('latestActivityMicros: $latestActivityMicros, ')
          ..write('unreadCount: $unreadCount, ')
          ..write('isGroup: $isGroup, ')
          ..write('identityId: $identityId, ')
          ..write('canSend: $canSend, ')
          ..write('sendingUnavailableReason: $sendingUnavailableReason, ')
          ..write('isFromUnknownSender: $isFromUnknownSender, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MessagesTable extends Messages
    with TableInfo<$MessagesTable, MessageRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _conversationIdMeta = const VerificationMeta(
    'conversationId',
  );
  @override
  late final GeneratedColumn<String> conversationId = GeneratedColumn<String>(
    'conversation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timestampMicrosMeta = const VerificationMeta(
    'timestampMicros',
  );
  @override
  late final GeneratedColumn<int> timestampMicros = GeneratedColumn<int>(
    'timestamp_micros',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isOutgoingMeta = const VerificationMeta(
    'isOutgoing',
  );
  @override
  late final GeneratedColumn<bool> isOutgoing = GeneratedColumn<bool>(
    'is_outgoing',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_outgoing" IN (0, 1))',
    ),
  );
  static const VerificationMeta _senderIdMeta = const VerificationMeta(
    'senderId',
  );
  @override
  late final GeneratedColumn<String> senderId = GeneratedColumn<String>(
    'sender_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _senderNameMeta = const VerificationMeta(
    'senderName',
  );
  @override
  late final GeneratedColumn<String> senderName = GeneratedColumn<String>(
    'sender_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deliveryStateMeta = const VerificationMeta(
    'deliveryState',
  );
  @override
  late final GeneratedColumn<String> deliveryState = GeneratedColumn<String>(
    'delivery_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _replyToMessageIdMeta = const VerificationMeta(
    'replyToMessageId',
  );
  @override
  late final GeneratedColumn<String> replyToMessageId = GeneratedColumn<String>(
    'reply_to_message_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _attachmentsJsonMeta = const VerificationMeta(
    'attachmentsJson',
  );
  @override
  late final GeneratedColumn<String> attachmentsJson = GeneratedColumn<String>(
    'attachments_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    accountId,
    conversationId,
    id,
    body,
    timestampMicros,
    isOutgoing,
    senderId,
    senderName,
    kind,
    deliveryState,
    replyToMessageId,
    attachmentsJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'messages';
  @override
  VerificationContext validateIntegrity(
    Insertable<MessageRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('conversation_id')) {
      context.handle(
        _conversationIdMeta,
        conversationId.isAcceptableOrUnknown(
          data['conversation_id']!,
          _conversationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_conversationIdMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    if (data.containsKey('timestamp_micros')) {
      context.handle(
        _timestampMicrosMeta,
        timestampMicros.isAcceptableOrUnknown(
          data['timestamp_micros']!,
          _timestampMicrosMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_timestampMicrosMeta);
    }
    if (data.containsKey('is_outgoing')) {
      context.handle(
        _isOutgoingMeta,
        isOutgoing.isAcceptableOrUnknown(data['is_outgoing']!, _isOutgoingMeta),
      );
    } else if (isInserting) {
      context.missing(_isOutgoingMeta);
    }
    if (data.containsKey('sender_id')) {
      context.handle(
        _senderIdMeta,
        senderId.isAcceptableOrUnknown(data['sender_id']!, _senderIdMeta),
      );
    }
    if (data.containsKey('sender_name')) {
      context.handle(
        _senderNameMeta,
        senderName.isAcceptableOrUnknown(data['sender_name']!, _senderNameMeta),
      );
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('delivery_state')) {
      context.handle(
        _deliveryStateMeta,
        deliveryState.isAcceptableOrUnknown(
          data['delivery_state']!,
          _deliveryStateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_deliveryStateMeta);
    }
    if (data.containsKey('reply_to_message_id')) {
      context.handle(
        _replyToMessageIdMeta,
        replyToMessageId.isAcceptableOrUnknown(
          data['reply_to_message_id']!,
          _replyToMessageIdMeta,
        ),
      );
    }
    if (data.containsKey('attachments_json')) {
      context.handle(
        _attachmentsJsonMeta,
        attachmentsJson.isAcceptableOrUnknown(
          data['attachments_json']!,
          _attachmentsJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_attachmentsJsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {accountId, conversationId, id};
  @override
  MessageRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MessageRow(
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      conversationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conversation_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
      timestampMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}timestamp_micros'],
      )!,
      isOutgoing: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_outgoing'],
      )!,
      senderId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sender_id'],
      ),
      senderName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sender_name'],
      ),
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      deliveryState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}delivery_state'],
      )!,
      replyToMessageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reply_to_message_id'],
      ),
      attachmentsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}attachments_json'],
      )!,
    );
  }

  @override
  $MessagesTable createAlias(String alias) {
    return $MessagesTable(attachedDatabase, alias);
  }
}

class MessageRow extends DataClass implements Insertable<MessageRow> {
  final String accountId;
  final String conversationId;
  final String id;
  final String body;
  final int timestampMicros;
  final bool isOutgoing;
  final String? senderId;
  final String? senderName;
  final String kind;
  final String deliveryState;
  final String? replyToMessageId;
  final String attachmentsJson;
  const MessageRow({
    required this.accountId,
    required this.conversationId,
    required this.id,
    required this.body,
    required this.timestampMicros,
    required this.isOutgoing,
    this.senderId,
    this.senderName,
    required this.kind,
    required this.deliveryState,
    this.replyToMessageId,
    required this.attachmentsJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['account_id'] = Variable<String>(accountId);
    map['conversation_id'] = Variable<String>(conversationId);
    map['id'] = Variable<String>(id);
    map['body'] = Variable<String>(body);
    map['timestamp_micros'] = Variable<int>(timestampMicros);
    map['is_outgoing'] = Variable<bool>(isOutgoing);
    if (!nullToAbsent || senderId != null) {
      map['sender_id'] = Variable<String>(senderId);
    }
    if (!nullToAbsent || senderName != null) {
      map['sender_name'] = Variable<String>(senderName);
    }
    map['kind'] = Variable<String>(kind);
    map['delivery_state'] = Variable<String>(deliveryState);
    if (!nullToAbsent || replyToMessageId != null) {
      map['reply_to_message_id'] = Variable<String>(replyToMessageId);
    }
    map['attachments_json'] = Variable<String>(attachmentsJson);
    return map;
  }

  MessagesCompanion toCompanion(bool nullToAbsent) {
    return MessagesCompanion(
      accountId: Value(accountId),
      conversationId: Value(conversationId),
      id: Value(id),
      body: Value(body),
      timestampMicros: Value(timestampMicros),
      isOutgoing: Value(isOutgoing),
      senderId: senderId == null && nullToAbsent
          ? const Value.absent()
          : Value(senderId),
      senderName: senderName == null && nullToAbsent
          ? const Value.absent()
          : Value(senderName),
      kind: Value(kind),
      deliveryState: Value(deliveryState),
      replyToMessageId: replyToMessageId == null && nullToAbsent
          ? const Value.absent()
          : Value(replyToMessageId),
      attachmentsJson: Value(attachmentsJson),
    );
  }

  factory MessageRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MessageRow(
      accountId: serializer.fromJson<String>(json['accountId']),
      conversationId: serializer.fromJson<String>(json['conversationId']),
      id: serializer.fromJson<String>(json['id']),
      body: serializer.fromJson<String>(json['body']),
      timestampMicros: serializer.fromJson<int>(json['timestampMicros']),
      isOutgoing: serializer.fromJson<bool>(json['isOutgoing']),
      senderId: serializer.fromJson<String?>(json['senderId']),
      senderName: serializer.fromJson<String?>(json['senderName']),
      kind: serializer.fromJson<String>(json['kind']),
      deliveryState: serializer.fromJson<String>(json['deliveryState']),
      replyToMessageId: serializer.fromJson<String?>(json['replyToMessageId']),
      attachmentsJson: serializer.fromJson<String>(json['attachmentsJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'accountId': serializer.toJson<String>(accountId),
      'conversationId': serializer.toJson<String>(conversationId),
      'id': serializer.toJson<String>(id),
      'body': serializer.toJson<String>(body),
      'timestampMicros': serializer.toJson<int>(timestampMicros),
      'isOutgoing': serializer.toJson<bool>(isOutgoing),
      'senderId': serializer.toJson<String?>(senderId),
      'senderName': serializer.toJson<String?>(senderName),
      'kind': serializer.toJson<String>(kind),
      'deliveryState': serializer.toJson<String>(deliveryState),
      'replyToMessageId': serializer.toJson<String?>(replyToMessageId),
      'attachmentsJson': serializer.toJson<String>(attachmentsJson),
    };
  }

  MessageRow copyWith({
    String? accountId,
    String? conversationId,
    String? id,
    String? body,
    int? timestampMicros,
    bool? isOutgoing,
    Value<String?> senderId = const Value.absent(),
    Value<String?> senderName = const Value.absent(),
    String? kind,
    String? deliveryState,
    Value<String?> replyToMessageId = const Value.absent(),
    String? attachmentsJson,
  }) => MessageRow(
    accountId: accountId ?? this.accountId,
    conversationId: conversationId ?? this.conversationId,
    id: id ?? this.id,
    body: body ?? this.body,
    timestampMicros: timestampMicros ?? this.timestampMicros,
    isOutgoing: isOutgoing ?? this.isOutgoing,
    senderId: senderId.present ? senderId.value : this.senderId,
    senderName: senderName.present ? senderName.value : this.senderName,
    kind: kind ?? this.kind,
    deliveryState: deliveryState ?? this.deliveryState,
    replyToMessageId: replyToMessageId.present
        ? replyToMessageId.value
        : this.replyToMessageId,
    attachmentsJson: attachmentsJson ?? this.attachmentsJson,
  );
  MessageRow copyWithCompanion(MessagesCompanion data) {
    return MessageRow(
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      id: data.id.present ? data.id.value : this.id,
      body: data.body.present ? data.body.value : this.body,
      timestampMicros: data.timestampMicros.present
          ? data.timestampMicros.value
          : this.timestampMicros,
      isOutgoing: data.isOutgoing.present
          ? data.isOutgoing.value
          : this.isOutgoing,
      senderId: data.senderId.present ? data.senderId.value : this.senderId,
      senderName: data.senderName.present
          ? data.senderName.value
          : this.senderName,
      kind: data.kind.present ? data.kind.value : this.kind,
      deliveryState: data.deliveryState.present
          ? data.deliveryState.value
          : this.deliveryState,
      replyToMessageId: data.replyToMessageId.present
          ? data.replyToMessageId.value
          : this.replyToMessageId,
      attachmentsJson: data.attachmentsJson.present
          ? data.attachmentsJson.value
          : this.attachmentsJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MessageRow(')
          ..write('accountId: $accountId, ')
          ..write('conversationId: $conversationId, ')
          ..write('id: $id, ')
          ..write('body: $body, ')
          ..write('timestampMicros: $timestampMicros, ')
          ..write('isOutgoing: $isOutgoing, ')
          ..write('senderId: $senderId, ')
          ..write('senderName: $senderName, ')
          ..write('kind: $kind, ')
          ..write('deliveryState: $deliveryState, ')
          ..write('replyToMessageId: $replyToMessageId, ')
          ..write('attachmentsJson: $attachmentsJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    accountId,
    conversationId,
    id,
    body,
    timestampMicros,
    isOutgoing,
    senderId,
    senderName,
    kind,
    deliveryState,
    replyToMessageId,
    attachmentsJson,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MessageRow &&
          other.accountId == this.accountId &&
          other.conversationId == this.conversationId &&
          other.id == this.id &&
          other.body == this.body &&
          other.timestampMicros == this.timestampMicros &&
          other.isOutgoing == this.isOutgoing &&
          other.senderId == this.senderId &&
          other.senderName == this.senderName &&
          other.kind == this.kind &&
          other.deliveryState == this.deliveryState &&
          other.replyToMessageId == this.replyToMessageId &&
          other.attachmentsJson == this.attachmentsJson);
}

class MessagesCompanion extends UpdateCompanion<MessageRow> {
  final Value<String> accountId;
  final Value<String> conversationId;
  final Value<String> id;
  final Value<String> body;
  final Value<int> timestampMicros;
  final Value<bool> isOutgoing;
  final Value<String?> senderId;
  final Value<String?> senderName;
  final Value<String> kind;
  final Value<String> deliveryState;
  final Value<String?> replyToMessageId;
  final Value<String> attachmentsJson;
  final Value<int> rowid;
  const MessagesCompanion({
    this.accountId = const Value.absent(),
    this.conversationId = const Value.absent(),
    this.id = const Value.absent(),
    this.body = const Value.absent(),
    this.timestampMicros = const Value.absent(),
    this.isOutgoing = const Value.absent(),
    this.senderId = const Value.absent(),
    this.senderName = const Value.absent(),
    this.kind = const Value.absent(),
    this.deliveryState = const Value.absent(),
    this.replyToMessageId = const Value.absent(),
    this.attachmentsJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MessagesCompanion.insert({
    required String accountId,
    required String conversationId,
    required String id,
    required String body,
    required int timestampMicros,
    required bool isOutgoing,
    this.senderId = const Value.absent(),
    this.senderName = const Value.absent(),
    required String kind,
    required String deliveryState,
    this.replyToMessageId = const Value.absent(),
    required String attachmentsJson,
    this.rowid = const Value.absent(),
  }) : accountId = Value(accountId),
       conversationId = Value(conversationId),
       id = Value(id),
       body = Value(body),
       timestampMicros = Value(timestampMicros),
       isOutgoing = Value(isOutgoing),
       kind = Value(kind),
       deliveryState = Value(deliveryState),
       attachmentsJson = Value(attachmentsJson);
  static Insertable<MessageRow> custom({
    Expression<String>? accountId,
    Expression<String>? conversationId,
    Expression<String>? id,
    Expression<String>? body,
    Expression<int>? timestampMicros,
    Expression<bool>? isOutgoing,
    Expression<String>? senderId,
    Expression<String>? senderName,
    Expression<String>? kind,
    Expression<String>? deliveryState,
    Expression<String>? replyToMessageId,
    Expression<String>? attachmentsJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (accountId != null) 'account_id': accountId,
      if (conversationId != null) 'conversation_id': conversationId,
      if (id != null) 'id': id,
      if (body != null) 'body': body,
      if (timestampMicros != null) 'timestamp_micros': timestampMicros,
      if (isOutgoing != null) 'is_outgoing': isOutgoing,
      if (senderId != null) 'sender_id': senderId,
      if (senderName != null) 'sender_name': senderName,
      if (kind != null) 'kind': kind,
      if (deliveryState != null) 'delivery_state': deliveryState,
      if (replyToMessageId != null) 'reply_to_message_id': replyToMessageId,
      if (attachmentsJson != null) 'attachments_json': attachmentsJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MessagesCompanion copyWith({
    Value<String>? accountId,
    Value<String>? conversationId,
    Value<String>? id,
    Value<String>? body,
    Value<int>? timestampMicros,
    Value<bool>? isOutgoing,
    Value<String?>? senderId,
    Value<String?>? senderName,
    Value<String>? kind,
    Value<String>? deliveryState,
    Value<String?>? replyToMessageId,
    Value<String>? attachmentsJson,
    Value<int>? rowid,
  }) {
    return MessagesCompanion(
      accountId: accountId ?? this.accountId,
      conversationId: conversationId ?? this.conversationId,
      id: id ?? this.id,
      body: body ?? this.body,
      timestampMicros: timestampMicros ?? this.timestampMicros,
      isOutgoing: isOutgoing ?? this.isOutgoing,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      kind: kind ?? this.kind,
      deliveryState: deliveryState ?? this.deliveryState,
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
      attachmentsJson: attachmentsJson ?? this.attachmentsJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (conversationId.present) {
      map['conversation_id'] = Variable<String>(conversationId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (timestampMicros.present) {
      map['timestamp_micros'] = Variable<int>(timestampMicros.value);
    }
    if (isOutgoing.present) {
      map['is_outgoing'] = Variable<bool>(isOutgoing.value);
    }
    if (senderId.present) {
      map['sender_id'] = Variable<String>(senderId.value);
    }
    if (senderName.present) {
      map['sender_name'] = Variable<String>(senderName.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (deliveryState.present) {
      map['delivery_state'] = Variable<String>(deliveryState.value);
    }
    if (replyToMessageId.present) {
      map['reply_to_message_id'] = Variable<String>(replyToMessageId.value);
    }
    if (attachmentsJson.present) {
      map['attachments_json'] = Variable<String>(attachmentsJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MessagesCompanion(')
          ..write('accountId: $accountId, ')
          ..write('conversationId: $conversationId, ')
          ..write('id: $id, ')
          ..write('body: $body, ')
          ..write('timestampMicros: $timestampMicros, ')
          ..write('isOutgoing: $isOutgoing, ')
          ..write('senderId: $senderId, ')
          ..write('senderName: $senderName, ')
          ..write('kind: $kind, ')
          ..write('deliveryState: $deliveryState, ')
          ..write('replyToMessageId: $replyToMessageId, ')
          ..write('attachmentsJson: $attachmentsJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DraftsTable extends Drafts with TableInfo<$DraftsTable, DraftRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DraftsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _conversationIdMeta = const VerificationMeta(
    'conversationId',
  );
  @override
  late final GeneratedColumn<String> conversationId = GeneratedColumn<String>(
    'conversation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _replyToMessageIdMeta = const VerificationMeta(
    'replyToMessageId',
  );
  @override
  late final GeneratedColumn<String> replyToMessageId = GeneratedColumn<String>(
    'reply_to_message_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _attachmentsJsonMeta = const VerificationMeta(
    'attachmentsJson',
  );
  @override
  late final GeneratedColumn<String> attachmentsJson = GeneratedColumn<String>(
    'attachments_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    accountId,
    conversationId,
    body,
    revision,
    replyToMessageId,
    attachmentsJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'drafts';
  @override
  VerificationContext validateIntegrity(
    Insertable<DraftRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('conversation_id')) {
      context.handle(
        _conversationIdMeta,
        conversationId.isAcceptableOrUnknown(
          data['conversation_id']!,
          _conversationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_conversationIdMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    } else if (isInserting) {
      context.missing(_revisionMeta);
    }
    if (data.containsKey('reply_to_message_id')) {
      context.handle(
        _replyToMessageIdMeta,
        replyToMessageId.isAcceptableOrUnknown(
          data['reply_to_message_id']!,
          _replyToMessageIdMeta,
        ),
      );
    }
    if (data.containsKey('attachments_json')) {
      context.handle(
        _attachmentsJsonMeta,
        attachmentsJson.isAcceptableOrUnknown(
          data['attachments_json']!,
          _attachmentsJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_attachmentsJsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {accountId, conversationId};
  @override
  DraftRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DraftRow(
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      conversationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conversation_id'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      replyToMessageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reply_to_message_id'],
      ),
      attachmentsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}attachments_json'],
      )!,
    );
  }

  @override
  $DraftsTable createAlias(String alias) {
    return $DraftsTable(attachedDatabase, alias);
  }
}

class DraftRow extends DataClass implements Insertable<DraftRow> {
  final String accountId;
  final String conversationId;
  final String body;
  final int revision;
  final String? replyToMessageId;
  final String attachmentsJson;
  const DraftRow({
    required this.accountId,
    required this.conversationId,
    required this.body,
    required this.revision,
    this.replyToMessageId,
    required this.attachmentsJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['account_id'] = Variable<String>(accountId);
    map['conversation_id'] = Variable<String>(conversationId);
    map['body'] = Variable<String>(body);
    map['revision'] = Variable<int>(revision);
    if (!nullToAbsent || replyToMessageId != null) {
      map['reply_to_message_id'] = Variable<String>(replyToMessageId);
    }
    map['attachments_json'] = Variable<String>(attachmentsJson);
    return map;
  }

  DraftsCompanion toCompanion(bool nullToAbsent) {
    return DraftsCompanion(
      accountId: Value(accountId),
      conversationId: Value(conversationId),
      body: Value(body),
      revision: Value(revision),
      replyToMessageId: replyToMessageId == null && nullToAbsent
          ? const Value.absent()
          : Value(replyToMessageId),
      attachmentsJson: Value(attachmentsJson),
    );
  }

  factory DraftRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DraftRow(
      accountId: serializer.fromJson<String>(json['accountId']),
      conversationId: serializer.fromJson<String>(json['conversationId']),
      body: serializer.fromJson<String>(json['body']),
      revision: serializer.fromJson<int>(json['revision']),
      replyToMessageId: serializer.fromJson<String?>(json['replyToMessageId']),
      attachmentsJson: serializer.fromJson<String>(json['attachmentsJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'accountId': serializer.toJson<String>(accountId),
      'conversationId': serializer.toJson<String>(conversationId),
      'body': serializer.toJson<String>(body),
      'revision': serializer.toJson<int>(revision),
      'replyToMessageId': serializer.toJson<String?>(replyToMessageId),
      'attachmentsJson': serializer.toJson<String>(attachmentsJson),
    };
  }

  DraftRow copyWith({
    String? accountId,
    String? conversationId,
    String? body,
    int? revision,
    Value<String?> replyToMessageId = const Value.absent(),
    String? attachmentsJson,
  }) => DraftRow(
    accountId: accountId ?? this.accountId,
    conversationId: conversationId ?? this.conversationId,
    body: body ?? this.body,
    revision: revision ?? this.revision,
    replyToMessageId: replyToMessageId.present
        ? replyToMessageId.value
        : this.replyToMessageId,
    attachmentsJson: attachmentsJson ?? this.attachmentsJson,
  );
  DraftRow copyWithCompanion(DraftsCompanion data) {
    return DraftRow(
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      body: data.body.present ? data.body.value : this.body,
      revision: data.revision.present ? data.revision.value : this.revision,
      replyToMessageId: data.replyToMessageId.present
          ? data.replyToMessageId.value
          : this.replyToMessageId,
      attachmentsJson: data.attachmentsJson.present
          ? data.attachmentsJson.value
          : this.attachmentsJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DraftRow(')
          ..write('accountId: $accountId, ')
          ..write('conversationId: $conversationId, ')
          ..write('body: $body, ')
          ..write('revision: $revision, ')
          ..write('replyToMessageId: $replyToMessageId, ')
          ..write('attachmentsJson: $attachmentsJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    accountId,
    conversationId,
    body,
    revision,
    replyToMessageId,
    attachmentsJson,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DraftRow &&
          other.accountId == this.accountId &&
          other.conversationId == this.conversationId &&
          other.body == this.body &&
          other.revision == this.revision &&
          other.replyToMessageId == this.replyToMessageId &&
          other.attachmentsJson == this.attachmentsJson);
}

class DraftsCompanion extends UpdateCompanion<DraftRow> {
  final Value<String> accountId;
  final Value<String> conversationId;
  final Value<String> body;
  final Value<int> revision;
  final Value<String?> replyToMessageId;
  final Value<String> attachmentsJson;
  final Value<int> rowid;
  const DraftsCompanion({
    this.accountId = const Value.absent(),
    this.conversationId = const Value.absent(),
    this.body = const Value.absent(),
    this.revision = const Value.absent(),
    this.replyToMessageId = const Value.absent(),
    this.attachmentsJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DraftsCompanion.insert({
    required String accountId,
    required String conversationId,
    required String body,
    required int revision,
    this.replyToMessageId = const Value.absent(),
    required String attachmentsJson,
    this.rowid = const Value.absent(),
  }) : accountId = Value(accountId),
       conversationId = Value(conversationId),
       body = Value(body),
       revision = Value(revision),
       attachmentsJson = Value(attachmentsJson);
  static Insertable<DraftRow> custom({
    Expression<String>? accountId,
    Expression<String>? conversationId,
    Expression<String>? body,
    Expression<int>? revision,
    Expression<String>? replyToMessageId,
    Expression<String>? attachmentsJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (accountId != null) 'account_id': accountId,
      if (conversationId != null) 'conversation_id': conversationId,
      if (body != null) 'body': body,
      if (revision != null) 'revision': revision,
      if (replyToMessageId != null) 'reply_to_message_id': replyToMessageId,
      if (attachmentsJson != null) 'attachments_json': attachmentsJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DraftsCompanion copyWith({
    Value<String>? accountId,
    Value<String>? conversationId,
    Value<String>? body,
    Value<int>? revision,
    Value<String?>? replyToMessageId,
    Value<String>? attachmentsJson,
    Value<int>? rowid,
  }) {
    return DraftsCompanion(
      accountId: accountId ?? this.accountId,
      conversationId: conversationId ?? this.conversationId,
      body: body ?? this.body,
      revision: revision ?? this.revision,
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
      attachmentsJson: attachmentsJson ?? this.attachmentsJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (conversationId.present) {
      map['conversation_id'] = Variable<String>(conversationId.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (replyToMessageId.present) {
      map['reply_to_message_id'] = Variable<String>(replyToMessageId.value);
    }
    if (attachmentsJson.present) {
      map['attachments_json'] = Variable<String>(attachmentsJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DraftsCompanion(')
          ..write('accountId: $accountId, ')
          ..write('conversationId: $conversationId, ')
          ..write('body: $body, ')
          ..write('revision: $revision, ')
          ..write('replyToMessageId: $replyToMessageId, ')
          ..write('attachmentsJson: $attachmentsJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PendingSendsTable extends PendingSends
    with TableInfo<$PendingSendsTable, PendingSendRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PendingSendsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _conversationIdMeta = const VerificationMeta(
    'conversationId',
  );
  @override
  late final GeneratedColumn<String> conversationId = GeneratedColumn<String>(
    'conversation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMicrosMeta = const VerificationMeta(
    'createdAtMicros',
  );
  @override
  late final GeneratedColumn<int> createdAtMicros = GeneratedColumn<int>(
    'created_at_micros',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _draftRevisionMeta = const VerificationMeta(
    'draftRevision',
  );
  @override
  late final GeneratedColumn<int> draftRevision = GeneratedColumn<int>(
    'draft_revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _replyToMessageIdMeta = const VerificationMeta(
    'replyToMessageId',
  );
  @override
  late final GeneratedColumn<String> replyToMessageId = GeneratedColumn<String>(
    'reply_to_message_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _attachmentsJsonMeta = const VerificationMeta(
    'attachmentsJson',
  );
  @override
  late final GeneratedColumn<String> attachmentsJson = GeneratedColumn<String>(
    'attachments_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    accountId,
    conversationId,
    body,
    createdAtMicros,
    draftRevision,
    status,
    replyToMessageId,
    attachmentsJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pending_sends';
  @override
  VerificationContext validateIntegrity(
    Insertable<PendingSendRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('conversation_id')) {
      context.handle(
        _conversationIdMeta,
        conversationId.isAcceptableOrUnknown(
          data['conversation_id']!,
          _conversationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_conversationIdMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    if (data.containsKey('created_at_micros')) {
      context.handle(
        _createdAtMicrosMeta,
        createdAtMicros.isAcceptableOrUnknown(
          data['created_at_micros']!,
          _createdAtMicrosMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtMicrosMeta);
    }
    if (data.containsKey('draft_revision')) {
      context.handle(
        _draftRevisionMeta,
        draftRevision.isAcceptableOrUnknown(
          data['draft_revision']!,
          _draftRevisionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_draftRevisionMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('reply_to_message_id')) {
      context.handle(
        _replyToMessageIdMeta,
        replyToMessageId.isAcceptableOrUnknown(
          data['reply_to_message_id']!,
          _replyToMessageIdMeta,
        ),
      );
    }
    if (data.containsKey('attachments_json')) {
      context.handle(
        _attachmentsJsonMeta,
        attachmentsJson.isAcceptableOrUnknown(
          data['attachments_json']!,
          _attachmentsJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_attachmentsJsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PendingSendRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PendingSendRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      conversationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conversation_id'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
      createdAtMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_micros'],
      )!,
      draftRevision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}draft_revision'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      replyToMessageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reply_to_message_id'],
      ),
      attachmentsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}attachments_json'],
      )!,
    );
  }

  @override
  $PendingSendsTable createAlias(String alias) {
    return $PendingSendsTable(attachedDatabase, alias);
  }
}

class PendingSendRow extends DataClass implements Insertable<PendingSendRow> {
  final String id;
  final String accountId;
  final String conversationId;
  final String body;
  final int createdAtMicros;
  final int draftRevision;
  final String status;
  final String? replyToMessageId;
  final String attachmentsJson;
  const PendingSendRow({
    required this.id,
    required this.accountId,
    required this.conversationId,
    required this.body,
    required this.createdAtMicros,
    required this.draftRevision,
    required this.status,
    this.replyToMessageId,
    required this.attachmentsJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['account_id'] = Variable<String>(accountId);
    map['conversation_id'] = Variable<String>(conversationId);
    map['body'] = Variable<String>(body);
    map['created_at_micros'] = Variable<int>(createdAtMicros);
    map['draft_revision'] = Variable<int>(draftRevision);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || replyToMessageId != null) {
      map['reply_to_message_id'] = Variable<String>(replyToMessageId);
    }
    map['attachments_json'] = Variable<String>(attachmentsJson);
    return map;
  }

  PendingSendsCompanion toCompanion(bool nullToAbsent) {
    return PendingSendsCompanion(
      id: Value(id),
      accountId: Value(accountId),
      conversationId: Value(conversationId),
      body: Value(body),
      createdAtMicros: Value(createdAtMicros),
      draftRevision: Value(draftRevision),
      status: Value(status),
      replyToMessageId: replyToMessageId == null && nullToAbsent
          ? const Value.absent()
          : Value(replyToMessageId),
      attachmentsJson: Value(attachmentsJson),
    );
  }

  factory PendingSendRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PendingSendRow(
      id: serializer.fromJson<String>(json['id']),
      accountId: serializer.fromJson<String>(json['accountId']),
      conversationId: serializer.fromJson<String>(json['conversationId']),
      body: serializer.fromJson<String>(json['body']),
      createdAtMicros: serializer.fromJson<int>(json['createdAtMicros']),
      draftRevision: serializer.fromJson<int>(json['draftRevision']),
      status: serializer.fromJson<String>(json['status']),
      replyToMessageId: serializer.fromJson<String?>(json['replyToMessageId']),
      attachmentsJson: serializer.fromJson<String>(json['attachmentsJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'accountId': serializer.toJson<String>(accountId),
      'conversationId': serializer.toJson<String>(conversationId),
      'body': serializer.toJson<String>(body),
      'createdAtMicros': serializer.toJson<int>(createdAtMicros),
      'draftRevision': serializer.toJson<int>(draftRevision),
      'status': serializer.toJson<String>(status),
      'replyToMessageId': serializer.toJson<String?>(replyToMessageId),
      'attachmentsJson': serializer.toJson<String>(attachmentsJson),
    };
  }

  PendingSendRow copyWith({
    String? id,
    String? accountId,
    String? conversationId,
    String? body,
    int? createdAtMicros,
    int? draftRevision,
    String? status,
    Value<String?> replyToMessageId = const Value.absent(),
    String? attachmentsJson,
  }) => PendingSendRow(
    id: id ?? this.id,
    accountId: accountId ?? this.accountId,
    conversationId: conversationId ?? this.conversationId,
    body: body ?? this.body,
    createdAtMicros: createdAtMicros ?? this.createdAtMicros,
    draftRevision: draftRevision ?? this.draftRevision,
    status: status ?? this.status,
    replyToMessageId: replyToMessageId.present
        ? replyToMessageId.value
        : this.replyToMessageId,
    attachmentsJson: attachmentsJson ?? this.attachmentsJson,
  );
  PendingSendRow copyWithCompanion(PendingSendsCompanion data) {
    return PendingSendRow(
      id: data.id.present ? data.id.value : this.id,
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      body: data.body.present ? data.body.value : this.body,
      createdAtMicros: data.createdAtMicros.present
          ? data.createdAtMicros.value
          : this.createdAtMicros,
      draftRevision: data.draftRevision.present
          ? data.draftRevision.value
          : this.draftRevision,
      status: data.status.present ? data.status.value : this.status,
      replyToMessageId: data.replyToMessageId.present
          ? data.replyToMessageId.value
          : this.replyToMessageId,
      attachmentsJson: data.attachmentsJson.present
          ? data.attachmentsJson.value
          : this.attachmentsJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PendingSendRow(')
          ..write('id: $id, ')
          ..write('accountId: $accountId, ')
          ..write('conversationId: $conversationId, ')
          ..write('body: $body, ')
          ..write('createdAtMicros: $createdAtMicros, ')
          ..write('draftRevision: $draftRevision, ')
          ..write('status: $status, ')
          ..write('replyToMessageId: $replyToMessageId, ')
          ..write('attachmentsJson: $attachmentsJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    accountId,
    conversationId,
    body,
    createdAtMicros,
    draftRevision,
    status,
    replyToMessageId,
    attachmentsJson,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PendingSendRow &&
          other.id == this.id &&
          other.accountId == this.accountId &&
          other.conversationId == this.conversationId &&
          other.body == this.body &&
          other.createdAtMicros == this.createdAtMicros &&
          other.draftRevision == this.draftRevision &&
          other.status == this.status &&
          other.replyToMessageId == this.replyToMessageId &&
          other.attachmentsJson == this.attachmentsJson);
}

class PendingSendsCompanion extends UpdateCompanion<PendingSendRow> {
  final Value<String> id;
  final Value<String> accountId;
  final Value<String> conversationId;
  final Value<String> body;
  final Value<int> createdAtMicros;
  final Value<int> draftRevision;
  final Value<String> status;
  final Value<String?> replyToMessageId;
  final Value<String> attachmentsJson;
  final Value<int> rowid;
  const PendingSendsCompanion({
    this.id = const Value.absent(),
    this.accountId = const Value.absent(),
    this.conversationId = const Value.absent(),
    this.body = const Value.absent(),
    this.createdAtMicros = const Value.absent(),
    this.draftRevision = const Value.absent(),
    this.status = const Value.absent(),
    this.replyToMessageId = const Value.absent(),
    this.attachmentsJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PendingSendsCompanion.insert({
    required String id,
    required String accountId,
    required String conversationId,
    required String body,
    required int createdAtMicros,
    required int draftRevision,
    required String status,
    this.replyToMessageId = const Value.absent(),
    required String attachmentsJson,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       accountId = Value(accountId),
       conversationId = Value(conversationId),
       body = Value(body),
       createdAtMicros = Value(createdAtMicros),
       draftRevision = Value(draftRevision),
       status = Value(status),
       attachmentsJson = Value(attachmentsJson);
  static Insertable<PendingSendRow> custom({
    Expression<String>? id,
    Expression<String>? accountId,
    Expression<String>? conversationId,
    Expression<String>? body,
    Expression<int>? createdAtMicros,
    Expression<int>? draftRevision,
    Expression<String>? status,
    Expression<String>? replyToMessageId,
    Expression<String>? attachmentsJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (accountId != null) 'account_id': accountId,
      if (conversationId != null) 'conversation_id': conversationId,
      if (body != null) 'body': body,
      if (createdAtMicros != null) 'created_at_micros': createdAtMicros,
      if (draftRevision != null) 'draft_revision': draftRevision,
      if (status != null) 'status': status,
      if (replyToMessageId != null) 'reply_to_message_id': replyToMessageId,
      if (attachmentsJson != null) 'attachments_json': attachmentsJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PendingSendsCompanion copyWith({
    Value<String>? id,
    Value<String>? accountId,
    Value<String>? conversationId,
    Value<String>? body,
    Value<int>? createdAtMicros,
    Value<int>? draftRevision,
    Value<String>? status,
    Value<String?>? replyToMessageId,
    Value<String>? attachmentsJson,
    Value<int>? rowid,
  }) {
    return PendingSendsCompanion(
      id: id ?? this.id,
      accountId: accountId ?? this.accountId,
      conversationId: conversationId ?? this.conversationId,
      body: body ?? this.body,
      createdAtMicros: createdAtMicros ?? this.createdAtMicros,
      draftRevision: draftRevision ?? this.draftRevision,
      status: status ?? this.status,
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
      attachmentsJson: attachmentsJson ?? this.attachmentsJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (conversationId.present) {
      map['conversation_id'] = Variable<String>(conversationId.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (createdAtMicros.present) {
      map['created_at_micros'] = Variable<int>(createdAtMicros.value);
    }
    if (draftRevision.present) {
      map['draft_revision'] = Variable<int>(draftRevision.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (replyToMessageId.present) {
      map['reply_to_message_id'] = Variable<String>(replyToMessageId.value);
    }
    if (attachmentsJson.present) {
      map['attachments_json'] = Variable<String>(attachmentsJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PendingSendsCompanion(')
          ..write('id: $id, ')
          ..write('accountId: $accountId, ')
          ..write('conversationId: $conversationId, ')
          ..write('body: $body, ')
          ..write('createdAtMicros: $createdAtMicros, ')
          ..write('draftRevision: $draftRevision, ')
          ..write('status: $status, ')
          ..write('replyToMessageId: $replyToMessageId, ')
          ..write('attachmentsJson: $attachmentsJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PeopleTable extends People with TableInfo<$PeopleTable, PersonRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PeopleTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, displayName];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'people';
  @override
  VerificationContext validateIntegrity(
    Insertable<PersonRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_displayNameMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PersonRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PersonRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      )!,
    );
  }

  @override
  $PeopleTable createAlias(String alias) {
    return $PeopleTable(attachedDatabase, alias);
  }
}

class PersonRow extends DataClass implements Insertable<PersonRow> {
  final String id;
  final String displayName;
  const PersonRow({required this.id, required this.displayName});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['display_name'] = Variable<String>(displayName);
    return map;
  }

  PeopleCompanion toCompanion(bool nullToAbsent) {
    return PeopleCompanion(id: Value(id), displayName: Value(displayName));
  }

  factory PersonRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PersonRow(
      id: serializer.fromJson<String>(json['id']),
      displayName: serializer.fromJson<String>(json['displayName']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'displayName': serializer.toJson<String>(displayName),
    };
  }

  PersonRow copyWith({String? id, String? displayName}) => PersonRow(
    id: id ?? this.id,
    displayName: displayName ?? this.displayName,
  );
  PersonRow copyWithCompanion(PeopleCompanion data) {
    return PersonRow(
      id: data.id.present ? data.id.value : this.id,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PersonRow(')
          ..write('id: $id, ')
          ..write('displayName: $displayName')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, displayName);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PersonRow &&
          other.id == this.id &&
          other.displayName == this.displayName);
}

class PeopleCompanion extends UpdateCompanion<PersonRow> {
  final Value<String> id;
  final Value<String> displayName;
  final Value<int> rowid;
  const PeopleCompanion({
    this.id = const Value.absent(),
    this.displayName = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PeopleCompanion.insert({
    required String id,
    required String displayName,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       displayName = Value(displayName);
  static Insertable<PersonRow> custom({
    Expression<String>? id,
    Expression<String>? displayName,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (displayName != null) 'display_name': displayName,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PeopleCompanion copyWith({
    Value<String>? id,
    Value<String>? displayName,
    Value<int>? rowid,
  }) {
    return PeopleCompanion(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PeopleCompanion(')
          ..write('id: $id, ')
          ..write('displayName: $displayName, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ContactLinksTable extends ContactLinks
    with TableInfo<$ContactLinksTable, ContactLinkRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ContactLinksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES accounts (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _identityIdMeta = const VerificationMeta(
    'identityId',
  );
  @override
  late final GeneratedColumn<String> identityId = GeneratedColumn<String>(
    'identity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _personIdMeta = const VerificationMeta(
    'personId',
  );
  @override
  late final GeneratedColumn<String> personId = GeneratedColumn<String>(
    'person_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES people (id) ON DELETE CASCADE',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [accountId, identityId, personId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'contact_links';
  @override
  VerificationContext validateIntegrity(
    Insertable<ContactLinkRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('identity_id')) {
      context.handle(
        _identityIdMeta,
        identityId.isAcceptableOrUnknown(data['identity_id']!, _identityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_identityIdMeta);
    }
    if (data.containsKey('person_id')) {
      context.handle(
        _personIdMeta,
        personId.isAcceptableOrUnknown(data['person_id']!, _personIdMeta),
      );
    } else if (isInserting) {
      context.missing(_personIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {accountId, identityId};
  @override
  ContactLinkRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ContactLinkRow(
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      identityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}identity_id'],
      )!,
      personId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}person_id'],
      )!,
    );
  }

  @override
  $ContactLinksTable createAlias(String alias) {
    return $ContactLinksTable(attachedDatabase, alias);
  }
}

class ContactLinkRow extends DataClass implements Insertable<ContactLinkRow> {
  final String accountId;
  final String identityId;
  final String personId;
  const ContactLinkRow({
    required this.accountId,
    required this.identityId,
    required this.personId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['account_id'] = Variable<String>(accountId);
    map['identity_id'] = Variable<String>(identityId);
    map['person_id'] = Variable<String>(personId);
    return map;
  }

  ContactLinksCompanion toCompanion(bool nullToAbsent) {
    return ContactLinksCompanion(
      accountId: Value(accountId),
      identityId: Value(identityId),
      personId: Value(personId),
    );
  }

  factory ContactLinkRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ContactLinkRow(
      accountId: serializer.fromJson<String>(json['accountId']),
      identityId: serializer.fromJson<String>(json['identityId']),
      personId: serializer.fromJson<String>(json['personId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'accountId': serializer.toJson<String>(accountId),
      'identityId': serializer.toJson<String>(identityId),
      'personId': serializer.toJson<String>(personId),
    };
  }

  ContactLinkRow copyWith({
    String? accountId,
    String? identityId,
    String? personId,
  }) => ContactLinkRow(
    accountId: accountId ?? this.accountId,
    identityId: identityId ?? this.identityId,
    personId: personId ?? this.personId,
  );
  ContactLinkRow copyWithCompanion(ContactLinksCompanion data) {
    return ContactLinkRow(
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      identityId: data.identityId.present
          ? data.identityId.value
          : this.identityId,
      personId: data.personId.present ? data.personId.value : this.personId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ContactLinkRow(')
          ..write('accountId: $accountId, ')
          ..write('identityId: $identityId, ')
          ..write('personId: $personId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(accountId, identityId, personId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ContactLinkRow &&
          other.accountId == this.accountId &&
          other.identityId == this.identityId &&
          other.personId == this.personId);
}

class ContactLinksCompanion extends UpdateCompanion<ContactLinkRow> {
  final Value<String> accountId;
  final Value<String> identityId;
  final Value<String> personId;
  final Value<int> rowid;
  const ContactLinksCompanion({
    this.accountId = const Value.absent(),
    this.identityId = const Value.absent(),
    this.personId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ContactLinksCompanion.insert({
    required String accountId,
    required String identityId,
    required String personId,
    this.rowid = const Value.absent(),
  }) : accountId = Value(accountId),
       identityId = Value(identityId),
       personId = Value(personId);
  static Insertable<ContactLinkRow> custom({
    Expression<String>? accountId,
    Expression<String>? identityId,
    Expression<String>? personId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (accountId != null) 'account_id': accountId,
      if (identityId != null) 'identity_id': identityId,
      if (personId != null) 'person_id': personId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ContactLinksCompanion copyWith({
    Value<String>? accountId,
    Value<String>? identityId,
    Value<String>? personId,
    Value<int>? rowid,
  }) {
    return ContactLinksCompanion(
      accountId: accountId ?? this.accountId,
      identityId: identityId ?? this.identityId,
      personId: personId ?? this.personId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (identityId.present) {
      map['identity_id'] = Variable<String>(identityId.value);
    }
    if (personId.present) {
      map['person_id'] = Variable<String>(personId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ContactLinksCompanion(')
          ..write('accountId: $accountId, ')
          ..write('identityId: $identityId, ')
          ..write('personId: $personId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ConversationPreferencesTable extends ConversationPreferences
    with TableInfo<$ConversationPreferencesTable, PreferenceRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ConversationPreferencesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES accounts (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _conversationIdMeta = const VerificationMeta(
    'conversationId',
  );
  @override
  late final GeneratedColumn<String> conversationId = GeneratedColumn<String>(
    'conversation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isFavoriteMeta = const VerificationMeta(
    'isFavorite',
  );
  @override
  late final GeneratedColumn<bool> isFavorite = GeneratedColumn<bool>(
    'is_favorite',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_favorite" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _markedUnreadMeta = const VerificationMeta(
    'markedUnread',
  );
  @override
  late final GeneratedColumn<bool> markedUnread = GeneratedColumn<bool>(
    'marked_unread',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("marked_unread" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _isMutedMeta = const VerificationMeta(
    'isMuted',
  );
  @override
  late final GeneratedColumn<bool> isMuted = GeneratedColumn<bool>(
    'is_muted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_muted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _mutedUntilMicrosMeta = const VerificationMeta(
    'mutedUntilMicros',
  );
  @override
  late final GeneratedColumn<int> mutedUntilMicros = GeneratedColumn<int>(
    'muted_until_micros',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _hiddenAtMicrosMeta = const VerificationMeta(
    'hiddenAtMicros',
  );
  @override
  late final GeneratedColumn<int> hiddenAtMicros = GeneratedColumn<int>(
    'hidden_at_micros',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _readThroughMicrosMeta = const VerificationMeta(
    'readThroughMicros',
  );
  @override
  late final GeneratedColumn<int> readThroughMicros = GeneratedColumn<int>(
    'read_through_micros',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    accountId,
    conversationId,
    isFavorite,
    markedUnread,
    isMuted,
    mutedUntilMicros,
    hiddenAtMicros,
    readThroughMicros,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'conversation_preferences';
  @override
  VerificationContext validateIntegrity(
    Insertable<PreferenceRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('conversation_id')) {
      context.handle(
        _conversationIdMeta,
        conversationId.isAcceptableOrUnknown(
          data['conversation_id']!,
          _conversationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_conversationIdMeta);
    }
    if (data.containsKey('is_favorite')) {
      context.handle(
        _isFavoriteMeta,
        isFavorite.isAcceptableOrUnknown(data['is_favorite']!, _isFavoriteMeta),
      );
    }
    if (data.containsKey('marked_unread')) {
      context.handle(
        _markedUnreadMeta,
        markedUnread.isAcceptableOrUnknown(
          data['marked_unread']!,
          _markedUnreadMeta,
        ),
      );
    }
    if (data.containsKey('is_muted')) {
      context.handle(
        _isMutedMeta,
        isMuted.isAcceptableOrUnknown(data['is_muted']!, _isMutedMeta),
      );
    }
    if (data.containsKey('muted_until_micros')) {
      context.handle(
        _mutedUntilMicrosMeta,
        mutedUntilMicros.isAcceptableOrUnknown(
          data['muted_until_micros']!,
          _mutedUntilMicrosMeta,
        ),
      );
    }
    if (data.containsKey('hidden_at_micros')) {
      context.handle(
        _hiddenAtMicrosMeta,
        hiddenAtMicros.isAcceptableOrUnknown(
          data['hidden_at_micros']!,
          _hiddenAtMicrosMeta,
        ),
      );
    }
    if (data.containsKey('read_through_micros')) {
      context.handle(
        _readThroughMicrosMeta,
        readThroughMicros.isAcceptableOrUnknown(
          data['read_through_micros']!,
          _readThroughMicrosMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {accountId, conversationId};
  @override
  PreferenceRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PreferenceRow(
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      conversationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conversation_id'],
      )!,
      isFavorite: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_favorite'],
      )!,
      markedUnread: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}marked_unread'],
      )!,
      isMuted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_muted'],
      )!,
      mutedUntilMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}muted_until_micros'],
      ),
      hiddenAtMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}hidden_at_micros'],
      ),
      readThroughMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}read_through_micros'],
      ),
    );
  }

  @override
  $ConversationPreferencesTable createAlias(String alias) {
    return $ConversationPreferencesTable(attachedDatabase, alias);
  }
}

class PreferenceRow extends DataClass implements Insertable<PreferenceRow> {
  final String accountId;
  final String conversationId;
  final bool isFavorite;
  final bool markedUnread;
  final bool isMuted;
  final int? mutedUntilMicros;
  final int? hiddenAtMicros;
  final int? readThroughMicros;
  const PreferenceRow({
    required this.accountId,
    required this.conversationId,
    required this.isFavorite,
    required this.markedUnread,
    required this.isMuted,
    this.mutedUntilMicros,
    this.hiddenAtMicros,
    this.readThroughMicros,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['account_id'] = Variable<String>(accountId);
    map['conversation_id'] = Variable<String>(conversationId);
    map['is_favorite'] = Variable<bool>(isFavorite);
    map['marked_unread'] = Variable<bool>(markedUnread);
    map['is_muted'] = Variable<bool>(isMuted);
    if (!nullToAbsent || mutedUntilMicros != null) {
      map['muted_until_micros'] = Variable<int>(mutedUntilMicros);
    }
    if (!nullToAbsent || hiddenAtMicros != null) {
      map['hidden_at_micros'] = Variable<int>(hiddenAtMicros);
    }
    if (!nullToAbsent || readThroughMicros != null) {
      map['read_through_micros'] = Variable<int>(readThroughMicros);
    }
    return map;
  }

  ConversationPreferencesCompanion toCompanion(bool nullToAbsent) {
    return ConversationPreferencesCompanion(
      accountId: Value(accountId),
      conversationId: Value(conversationId),
      isFavorite: Value(isFavorite),
      markedUnread: Value(markedUnread),
      isMuted: Value(isMuted),
      mutedUntilMicros: mutedUntilMicros == null && nullToAbsent
          ? const Value.absent()
          : Value(mutedUntilMicros),
      hiddenAtMicros: hiddenAtMicros == null && nullToAbsent
          ? const Value.absent()
          : Value(hiddenAtMicros),
      readThroughMicros: readThroughMicros == null && nullToAbsent
          ? const Value.absent()
          : Value(readThroughMicros),
    );
  }

  factory PreferenceRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PreferenceRow(
      accountId: serializer.fromJson<String>(json['accountId']),
      conversationId: serializer.fromJson<String>(json['conversationId']),
      isFavorite: serializer.fromJson<bool>(json['isFavorite']),
      markedUnread: serializer.fromJson<bool>(json['markedUnread']),
      isMuted: serializer.fromJson<bool>(json['isMuted']),
      mutedUntilMicros: serializer.fromJson<int?>(json['mutedUntilMicros']),
      hiddenAtMicros: serializer.fromJson<int?>(json['hiddenAtMicros']),
      readThroughMicros: serializer.fromJson<int?>(json['readThroughMicros']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'accountId': serializer.toJson<String>(accountId),
      'conversationId': serializer.toJson<String>(conversationId),
      'isFavorite': serializer.toJson<bool>(isFavorite),
      'markedUnread': serializer.toJson<bool>(markedUnread),
      'isMuted': serializer.toJson<bool>(isMuted),
      'mutedUntilMicros': serializer.toJson<int?>(mutedUntilMicros),
      'hiddenAtMicros': serializer.toJson<int?>(hiddenAtMicros),
      'readThroughMicros': serializer.toJson<int?>(readThroughMicros),
    };
  }

  PreferenceRow copyWith({
    String? accountId,
    String? conversationId,
    bool? isFavorite,
    bool? markedUnread,
    bool? isMuted,
    Value<int?> mutedUntilMicros = const Value.absent(),
    Value<int?> hiddenAtMicros = const Value.absent(),
    Value<int?> readThroughMicros = const Value.absent(),
  }) => PreferenceRow(
    accountId: accountId ?? this.accountId,
    conversationId: conversationId ?? this.conversationId,
    isFavorite: isFavorite ?? this.isFavorite,
    markedUnread: markedUnread ?? this.markedUnread,
    isMuted: isMuted ?? this.isMuted,
    mutedUntilMicros: mutedUntilMicros.present
        ? mutedUntilMicros.value
        : this.mutedUntilMicros,
    hiddenAtMicros: hiddenAtMicros.present
        ? hiddenAtMicros.value
        : this.hiddenAtMicros,
    readThroughMicros: readThroughMicros.present
        ? readThroughMicros.value
        : this.readThroughMicros,
  );
  PreferenceRow copyWithCompanion(ConversationPreferencesCompanion data) {
    return PreferenceRow(
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      isFavorite: data.isFavorite.present
          ? data.isFavorite.value
          : this.isFavorite,
      markedUnread: data.markedUnread.present
          ? data.markedUnread.value
          : this.markedUnread,
      isMuted: data.isMuted.present ? data.isMuted.value : this.isMuted,
      mutedUntilMicros: data.mutedUntilMicros.present
          ? data.mutedUntilMicros.value
          : this.mutedUntilMicros,
      hiddenAtMicros: data.hiddenAtMicros.present
          ? data.hiddenAtMicros.value
          : this.hiddenAtMicros,
      readThroughMicros: data.readThroughMicros.present
          ? data.readThroughMicros.value
          : this.readThroughMicros,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PreferenceRow(')
          ..write('accountId: $accountId, ')
          ..write('conversationId: $conversationId, ')
          ..write('isFavorite: $isFavorite, ')
          ..write('markedUnread: $markedUnread, ')
          ..write('isMuted: $isMuted, ')
          ..write('mutedUntilMicros: $mutedUntilMicros, ')
          ..write('hiddenAtMicros: $hiddenAtMicros, ')
          ..write('readThroughMicros: $readThroughMicros')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    accountId,
    conversationId,
    isFavorite,
    markedUnread,
    isMuted,
    mutedUntilMicros,
    hiddenAtMicros,
    readThroughMicros,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PreferenceRow &&
          other.accountId == this.accountId &&
          other.conversationId == this.conversationId &&
          other.isFavorite == this.isFavorite &&
          other.markedUnread == this.markedUnread &&
          other.isMuted == this.isMuted &&
          other.mutedUntilMicros == this.mutedUntilMicros &&
          other.hiddenAtMicros == this.hiddenAtMicros &&
          other.readThroughMicros == this.readThroughMicros);
}

class ConversationPreferencesCompanion extends UpdateCompanion<PreferenceRow> {
  final Value<String> accountId;
  final Value<String> conversationId;
  final Value<bool> isFavorite;
  final Value<bool> markedUnread;
  final Value<bool> isMuted;
  final Value<int?> mutedUntilMicros;
  final Value<int?> hiddenAtMicros;
  final Value<int?> readThroughMicros;
  final Value<int> rowid;
  const ConversationPreferencesCompanion({
    this.accountId = const Value.absent(),
    this.conversationId = const Value.absent(),
    this.isFavorite = const Value.absent(),
    this.markedUnread = const Value.absent(),
    this.isMuted = const Value.absent(),
    this.mutedUntilMicros = const Value.absent(),
    this.hiddenAtMicros = const Value.absent(),
    this.readThroughMicros = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ConversationPreferencesCompanion.insert({
    required String accountId,
    required String conversationId,
    this.isFavorite = const Value.absent(),
    this.markedUnread = const Value.absent(),
    this.isMuted = const Value.absent(),
    this.mutedUntilMicros = const Value.absent(),
    this.hiddenAtMicros = const Value.absent(),
    this.readThroughMicros = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : accountId = Value(accountId),
       conversationId = Value(conversationId);
  static Insertable<PreferenceRow> custom({
    Expression<String>? accountId,
    Expression<String>? conversationId,
    Expression<bool>? isFavorite,
    Expression<bool>? markedUnread,
    Expression<bool>? isMuted,
    Expression<int>? mutedUntilMicros,
    Expression<int>? hiddenAtMicros,
    Expression<int>? readThroughMicros,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (accountId != null) 'account_id': accountId,
      if (conversationId != null) 'conversation_id': conversationId,
      if (isFavorite != null) 'is_favorite': isFavorite,
      if (markedUnread != null) 'marked_unread': markedUnread,
      if (isMuted != null) 'is_muted': isMuted,
      if (mutedUntilMicros != null) 'muted_until_micros': mutedUntilMicros,
      if (hiddenAtMicros != null) 'hidden_at_micros': hiddenAtMicros,
      if (readThroughMicros != null) 'read_through_micros': readThroughMicros,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ConversationPreferencesCompanion copyWith({
    Value<String>? accountId,
    Value<String>? conversationId,
    Value<bool>? isFavorite,
    Value<bool>? markedUnread,
    Value<bool>? isMuted,
    Value<int?>? mutedUntilMicros,
    Value<int?>? hiddenAtMicros,
    Value<int?>? readThroughMicros,
    Value<int>? rowid,
  }) {
    return ConversationPreferencesCompanion(
      accountId: accountId ?? this.accountId,
      conversationId: conversationId ?? this.conversationId,
      isFavorite: isFavorite ?? this.isFavorite,
      markedUnread: markedUnread ?? this.markedUnread,
      isMuted: isMuted ?? this.isMuted,
      mutedUntilMicros: mutedUntilMicros ?? this.mutedUntilMicros,
      hiddenAtMicros: hiddenAtMicros ?? this.hiddenAtMicros,
      readThroughMicros: readThroughMicros ?? this.readThroughMicros,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (conversationId.present) {
      map['conversation_id'] = Variable<String>(conversationId.value);
    }
    if (isFavorite.present) {
      map['is_favorite'] = Variable<bool>(isFavorite.value);
    }
    if (markedUnread.present) {
      map['marked_unread'] = Variable<bool>(markedUnread.value);
    }
    if (isMuted.present) {
      map['is_muted'] = Variable<bool>(isMuted.value);
    }
    if (mutedUntilMicros.present) {
      map['muted_until_micros'] = Variable<int>(mutedUntilMicros.value);
    }
    if (hiddenAtMicros.present) {
      map['hidden_at_micros'] = Variable<int>(hiddenAtMicros.value);
    }
    if (readThroughMicros.present) {
      map['read_through_micros'] = Variable<int>(readThroughMicros.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ConversationPreferencesCompanion(')
          ..write('accountId: $accountId, ')
          ..write('conversationId: $conversationId, ')
          ..write('isFavorite: $isFavorite, ')
          ..write('markedUnread: $markedUnread, ')
          ..write('isMuted: $isMuted, ')
          ..write('mutedUntilMicros: $mutedUntilMicros, ')
          ..write('hiddenAtMicros: $hiddenAtMicros, ')
          ..write('readThroughMicros: $readThroughMicros, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MessageReactionsTable extends MessageReactions
    with TableInfo<$MessageReactionsTable, MessageReactionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MessageReactionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES accounts (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _conversationIdMeta = const VerificationMeta(
    'conversationId',
  );
  @override
  late final GeneratedColumn<String> conversationId = GeneratedColumn<String>(
    'conversation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _messageIdMeta = const VerificationMeta(
    'messageId',
  );
  @override
  late final GeneratedColumn<String> messageId = GeneratedColumn<String>(
    'message_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceIdMeta = const VerificationMeta(
    'sourceId',
  );
  @override
  late final GeneratedColumn<String> sourceId = GeneratedColumn<String>(
    'source_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _reactionKeyMeta = const VerificationMeta(
    'reactionKey',
  );
  @override
  late final GeneratedColumn<String> reactionKey = GeneratedColumn<String>(
    'reaction_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _countMeta = const VerificationMeta('count');
  @override
  late final GeneratedColumn<int> count = GeneratedColumn<int>(
    'count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _includesMeMeta = const VerificationMeta(
    'includesMe',
  );
  @override
  late final GeneratedColumn<bool> includesMe = GeneratedColumn<bool>(
    'includes_me',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("includes_me" IN (0, 1))',
    ),
  );
  static const VerificationMeta _recordedAtMicrosMeta = const VerificationMeta(
    'recordedAtMicros',
  );
  @override
  late final GeneratedColumn<int> recordedAtMicros = GeneratedColumn<int>(
    'recorded_at_micros',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    accountId,
    conversationId,
    messageId,
    sourceId,
    reactionKey,
    count,
    includesMe,
    recordedAtMicros,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'message_reactions';
  @override
  VerificationContext validateIntegrity(
    Insertable<MessageReactionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('conversation_id')) {
      context.handle(
        _conversationIdMeta,
        conversationId.isAcceptableOrUnknown(
          data['conversation_id']!,
          _conversationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_conversationIdMeta);
    }
    if (data.containsKey('message_id')) {
      context.handle(
        _messageIdMeta,
        messageId.isAcceptableOrUnknown(data['message_id']!, _messageIdMeta),
      );
    } else if (isInserting) {
      context.missing(_messageIdMeta);
    }
    if (data.containsKey('source_id')) {
      context.handle(
        _sourceIdMeta,
        sourceId.isAcceptableOrUnknown(data['source_id']!, _sourceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceIdMeta);
    }
    if (data.containsKey('reaction_key')) {
      context.handle(
        _reactionKeyMeta,
        reactionKey.isAcceptableOrUnknown(
          data['reaction_key']!,
          _reactionKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_reactionKeyMeta);
    }
    if (data.containsKey('count')) {
      context.handle(
        _countMeta,
        count.isAcceptableOrUnknown(data['count']!, _countMeta),
      );
    } else if (isInserting) {
      context.missing(_countMeta);
    }
    if (data.containsKey('includes_me')) {
      context.handle(
        _includesMeMeta,
        includesMe.isAcceptableOrUnknown(data['includes_me']!, _includesMeMeta),
      );
    } else if (isInserting) {
      context.missing(_includesMeMeta);
    }
    if (data.containsKey('recorded_at_micros')) {
      context.handle(
        _recordedAtMicrosMeta,
        recordedAtMicros.isAcceptableOrUnknown(
          data['recorded_at_micros']!,
          _recordedAtMicrosMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_recordedAtMicrosMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {
    accountId,
    conversationId,
    messageId,
    sourceId,
  };
  @override
  MessageReactionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MessageReactionRow(
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      conversationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conversation_id'],
      )!,
      messageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message_id'],
      )!,
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_id'],
      )!,
      reactionKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reaction_key'],
      )!,
      count: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}count'],
      )!,
      includesMe: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}includes_me'],
      )!,
      recordedAtMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}recorded_at_micros'],
      )!,
    );
  }

  @override
  $MessageReactionsTable createAlias(String alias) {
    return $MessageReactionsTable(attachedDatabase, alias);
  }
}

class MessageReactionRow extends DataClass
    implements Insertable<MessageReactionRow> {
  final String accountId;
  final String conversationId;
  final String messageId;
  final String sourceId;
  final String reactionKey;
  final int count;
  final bool includesMe;
  final int recordedAtMicros;
  const MessageReactionRow({
    required this.accountId,
    required this.conversationId,
    required this.messageId,
    required this.sourceId,
    required this.reactionKey,
    required this.count,
    required this.includesMe,
    required this.recordedAtMicros,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['account_id'] = Variable<String>(accountId);
    map['conversation_id'] = Variable<String>(conversationId);
    map['message_id'] = Variable<String>(messageId);
    map['source_id'] = Variable<String>(sourceId);
    map['reaction_key'] = Variable<String>(reactionKey);
    map['count'] = Variable<int>(count);
    map['includes_me'] = Variable<bool>(includesMe);
    map['recorded_at_micros'] = Variable<int>(recordedAtMicros);
    return map;
  }

  MessageReactionsCompanion toCompanion(bool nullToAbsent) {
    return MessageReactionsCompanion(
      accountId: Value(accountId),
      conversationId: Value(conversationId),
      messageId: Value(messageId),
      sourceId: Value(sourceId),
      reactionKey: Value(reactionKey),
      count: Value(count),
      includesMe: Value(includesMe),
      recordedAtMicros: Value(recordedAtMicros),
    );
  }

  factory MessageReactionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MessageReactionRow(
      accountId: serializer.fromJson<String>(json['accountId']),
      conversationId: serializer.fromJson<String>(json['conversationId']),
      messageId: serializer.fromJson<String>(json['messageId']),
      sourceId: serializer.fromJson<String>(json['sourceId']),
      reactionKey: serializer.fromJson<String>(json['reactionKey']),
      count: serializer.fromJson<int>(json['count']),
      includesMe: serializer.fromJson<bool>(json['includesMe']),
      recordedAtMicros: serializer.fromJson<int>(json['recordedAtMicros']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'accountId': serializer.toJson<String>(accountId),
      'conversationId': serializer.toJson<String>(conversationId),
      'messageId': serializer.toJson<String>(messageId),
      'sourceId': serializer.toJson<String>(sourceId),
      'reactionKey': serializer.toJson<String>(reactionKey),
      'count': serializer.toJson<int>(count),
      'includesMe': serializer.toJson<bool>(includesMe),
      'recordedAtMicros': serializer.toJson<int>(recordedAtMicros),
    };
  }

  MessageReactionRow copyWith({
    String? accountId,
    String? conversationId,
    String? messageId,
    String? sourceId,
    String? reactionKey,
    int? count,
    bool? includesMe,
    int? recordedAtMicros,
  }) => MessageReactionRow(
    accountId: accountId ?? this.accountId,
    conversationId: conversationId ?? this.conversationId,
    messageId: messageId ?? this.messageId,
    sourceId: sourceId ?? this.sourceId,
    reactionKey: reactionKey ?? this.reactionKey,
    count: count ?? this.count,
    includesMe: includesMe ?? this.includesMe,
    recordedAtMicros: recordedAtMicros ?? this.recordedAtMicros,
  );
  MessageReactionRow copyWithCompanion(MessageReactionsCompanion data) {
    return MessageReactionRow(
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      messageId: data.messageId.present ? data.messageId.value : this.messageId,
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      reactionKey: data.reactionKey.present
          ? data.reactionKey.value
          : this.reactionKey,
      count: data.count.present ? data.count.value : this.count,
      includesMe: data.includesMe.present
          ? data.includesMe.value
          : this.includesMe,
      recordedAtMicros: data.recordedAtMicros.present
          ? data.recordedAtMicros.value
          : this.recordedAtMicros,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MessageReactionRow(')
          ..write('accountId: $accountId, ')
          ..write('conversationId: $conversationId, ')
          ..write('messageId: $messageId, ')
          ..write('sourceId: $sourceId, ')
          ..write('reactionKey: $reactionKey, ')
          ..write('count: $count, ')
          ..write('includesMe: $includesMe, ')
          ..write('recordedAtMicros: $recordedAtMicros')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    accountId,
    conversationId,
    messageId,
    sourceId,
    reactionKey,
    count,
    includesMe,
    recordedAtMicros,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MessageReactionRow &&
          other.accountId == this.accountId &&
          other.conversationId == this.conversationId &&
          other.messageId == this.messageId &&
          other.sourceId == this.sourceId &&
          other.reactionKey == this.reactionKey &&
          other.count == this.count &&
          other.includesMe == this.includesMe &&
          other.recordedAtMicros == this.recordedAtMicros);
}

class MessageReactionsCompanion extends UpdateCompanion<MessageReactionRow> {
  final Value<String> accountId;
  final Value<String> conversationId;
  final Value<String> messageId;
  final Value<String> sourceId;
  final Value<String> reactionKey;
  final Value<int> count;
  final Value<bool> includesMe;
  final Value<int> recordedAtMicros;
  final Value<int> rowid;
  const MessageReactionsCompanion({
    this.accountId = const Value.absent(),
    this.conversationId = const Value.absent(),
    this.messageId = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.reactionKey = const Value.absent(),
    this.count = const Value.absent(),
    this.includesMe = const Value.absent(),
    this.recordedAtMicros = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MessageReactionsCompanion.insert({
    required String accountId,
    required String conversationId,
    required String messageId,
    required String sourceId,
    required String reactionKey,
    required int count,
    required bool includesMe,
    required int recordedAtMicros,
    this.rowid = const Value.absent(),
  }) : accountId = Value(accountId),
       conversationId = Value(conversationId),
       messageId = Value(messageId),
       sourceId = Value(sourceId),
       reactionKey = Value(reactionKey),
       count = Value(count),
       includesMe = Value(includesMe),
       recordedAtMicros = Value(recordedAtMicros);
  static Insertable<MessageReactionRow> custom({
    Expression<String>? accountId,
    Expression<String>? conversationId,
    Expression<String>? messageId,
    Expression<String>? sourceId,
    Expression<String>? reactionKey,
    Expression<int>? count,
    Expression<bool>? includesMe,
    Expression<int>? recordedAtMicros,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (accountId != null) 'account_id': accountId,
      if (conversationId != null) 'conversation_id': conversationId,
      if (messageId != null) 'message_id': messageId,
      if (sourceId != null) 'source_id': sourceId,
      if (reactionKey != null) 'reaction_key': reactionKey,
      if (count != null) 'count': count,
      if (includesMe != null) 'includes_me': includesMe,
      if (recordedAtMicros != null) 'recorded_at_micros': recordedAtMicros,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MessageReactionsCompanion copyWith({
    Value<String>? accountId,
    Value<String>? conversationId,
    Value<String>? messageId,
    Value<String>? sourceId,
    Value<String>? reactionKey,
    Value<int>? count,
    Value<bool>? includesMe,
    Value<int>? recordedAtMicros,
    Value<int>? rowid,
  }) {
    return MessageReactionsCompanion(
      accountId: accountId ?? this.accountId,
      conversationId: conversationId ?? this.conversationId,
      messageId: messageId ?? this.messageId,
      sourceId: sourceId ?? this.sourceId,
      reactionKey: reactionKey ?? this.reactionKey,
      count: count ?? this.count,
      includesMe: includesMe ?? this.includesMe,
      recordedAtMicros: recordedAtMicros ?? this.recordedAtMicros,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (conversationId.present) {
      map['conversation_id'] = Variable<String>(conversationId.value);
    }
    if (messageId.present) {
      map['message_id'] = Variable<String>(messageId.value);
    }
    if (sourceId.present) {
      map['source_id'] = Variable<String>(sourceId.value);
    }
    if (reactionKey.present) {
      map['reaction_key'] = Variable<String>(reactionKey.value);
    }
    if (count.present) {
      map['count'] = Variable<int>(count.value);
    }
    if (includesMe.present) {
      map['includes_me'] = Variable<bool>(includesMe.value);
    }
    if (recordedAtMicros.present) {
      map['recorded_at_micros'] = Variable<int>(recordedAtMicros.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MessageReactionsCompanion(')
          ..write('accountId: $accountId, ')
          ..write('conversationId: $conversationId, ')
          ..write('messageId: $messageId, ')
          ..write('sourceId: $sourceId, ')
          ..write('reactionKey: $reactionKey, ')
          ..write('count: $count, ')
          ..write('includesMe: $includesMe, ')
          ..write('recordedAtMicros: $recordedAtMicros, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$StorageDatabase extends GeneratedDatabase {
  _$StorageDatabase(QueryExecutor e) : super(e);
  $StorageDatabaseManager get managers => $StorageDatabaseManager(this);
  late final $AccountsTable accounts = $AccountsTable(this);
  late final $ConversationsTable conversations = $ConversationsTable(this);
  late final $MessagesTable messages = $MessagesTable(this);
  late final $DraftsTable drafts = $DraftsTable(this);
  late final $PendingSendsTable pendingSends = $PendingSendsTable(this);
  late final $PeopleTable people = $PeopleTable(this);
  late final $ContactLinksTable contactLinks = $ContactLinksTable(this);
  late final $ConversationPreferencesTable conversationPreferences =
      $ConversationPreferencesTable(this);
  late final $MessageReactionsTable messageReactions = $MessageReactionsTable(
    this,
  );
  late final Index messagesRecent = Index(
    'messages_recent',
    'CREATE INDEX messages_recent ON messages (account_id, conversation_id, timestamp_micros, id)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    accounts,
    conversations,
    messages,
    drafts,
    pendingSends,
    people,
    contactLinks,
    conversationPreferences,
    messageReactions,
    messagesRecent,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'accounts',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('conversations', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'accounts',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('contact_links', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'people',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('contact_links', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'accounts',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [
        TableUpdate('conversation_preferences', kind: UpdateKind.delete),
      ],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'accounts',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('message_reactions', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$AccountsTableCreateCompanionBuilder =
    AccountsCompanion Function({
      required String id,
      required String platform,
      required String displayName,
      Value<bool> isConnected,
      Value<int> rowid,
    });
typedef $$AccountsTableUpdateCompanionBuilder =
    AccountsCompanion Function({
      Value<String> id,
      Value<String> platform,
      Value<String> displayName,
      Value<bool> isConnected,
      Value<int> rowid,
    });

final class $$AccountsTableReferences
    extends BaseReferences<_$StorageDatabase, $AccountsTable, AccountRow> {
  $$AccountsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$ConversationsTable, List<ConversationRow>>
  _conversationsRefsTable(_$StorageDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.conversations,
        aliasName: 'accounts__id__conversations__account_id',
      );

  $$ConversationsTableProcessedTableManager get conversationsRefs {
    final manager = $$ConversationsTableTableManager(
      $_db,
      $_db.conversations,
    ).filter((f) => f.accountId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_conversationsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ContactLinksTable, List<ContactLinkRow>>
  _contactLinksRefsTable(_$StorageDatabase db) => MultiTypedResultKey.fromTable(
    db.contactLinks,
    aliasName: 'accounts__id__contact_links__account_id',
  );

  $$ContactLinksTableProcessedTableManager get contactLinksRefs {
    final manager = $$ContactLinksTableTableManager(
      $_db,
      $_db.contactLinks,
    ).filter((f) => f.accountId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_contactLinksRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ConversationPreferencesTable, List<PreferenceRow>>
  _conversationPreferencesRefsTable(_$StorageDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.conversationPreferences,
        aliasName: 'accounts__id__conversation_preferences__account_id',
      );

  $$ConversationPreferencesTableProcessedTableManager
  get conversationPreferencesRefs {
    final manager = $$ConversationPreferencesTableTableManager(
      $_db,
      $_db.conversationPreferences,
    ).filter((f) => f.accountId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _conversationPreferencesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$MessageReactionsTable, List<MessageReactionRow>>
  _messageReactionsRefsTable(_$StorageDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.messageReactions,
        aliasName: 'accounts__id__message_reactions__account_id',
      );

  $$MessageReactionsTableProcessedTableManager get messageReactionsRefs {
    final manager = $$MessageReactionsTableTableManager(
      $_db,
      $_db.messageReactions,
    ).filter((f) => f.accountId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _messageReactionsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$AccountsTableFilterComposer
    extends Composer<_$StorageDatabase, $AccountsTable> {
  $$AccountsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get platform => $composableBuilder(
    column: $table.platform,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isConnected => $composableBuilder(
    column: $table.isConnected,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> conversationsRefs(
    Expression<bool> Function($$ConversationsTableFilterComposer f) f,
  ) {
    final $$ConversationsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.conversations,
      getReferencedColumn: (t) => t.accountId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ConversationsTableFilterComposer(
            $db: $db,
            $table: $db.conversations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> contactLinksRefs(
    Expression<bool> Function($$ContactLinksTableFilterComposer f) f,
  ) {
    final $$ContactLinksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.contactLinks,
      getReferencedColumn: (t) => t.accountId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ContactLinksTableFilterComposer(
            $db: $db,
            $table: $db.contactLinks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> conversationPreferencesRefs(
    Expression<bool> Function($$ConversationPreferencesTableFilterComposer f) f,
  ) {
    final $$ConversationPreferencesTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.conversationPreferences,
          getReferencedColumn: (t) => t.accountId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ConversationPreferencesTableFilterComposer(
                $db: $db,
                $table: $db.conversationPreferences,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<bool> messageReactionsRefs(
    Expression<bool> Function($$MessageReactionsTableFilterComposer f) f,
  ) {
    final $$MessageReactionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.messageReactions,
      getReferencedColumn: (t) => t.accountId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessageReactionsTableFilterComposer(
            $db: $db,
            $table: $db.messageReactions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$AccountsTableOrderingComposer
    extends Composer<_$StorageDatabase, $AccountsTable> {
  $$AccountsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get platform => $composableBuilder(
    column: $table.platform,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isConnected => $composableBuilder(
    column: $table.isConnected,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AccountsTableAnnotationComposer
    extends Composer<_$StorageDatabase, $AccountsTable> {
  $$AccountsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get platform =>
      $composableBuilder(column: $table.platform, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isConnected => $composableBuilder(
    column: $table.isConnected,
    builder: (column) => column,
  );

  Expression<T> conversationsRefs<T extends Object>(
    Expression<T> Function($$ConversationsTableAnnotationComposer a) f,
  ) {
    final $$ConversationsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.conversations,
      getReferencedColumn: (t) => t.accountId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ConversationsTableAnnotationComposer(
            $db: $db,
            $table: $db.conversations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> contactLinksRefs<T extends Object>(
    Expression<T> Function($$ContactLinksTableAnnotationComposer a) f,
  ) {
    final $$ContactLinksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.contactLinks,
      getReferencedColumn: (t) => t.accountId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ContactLinksTableAnnotationComposer(
            $db: $db,
            $table: $db.contactLinks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> conversationPreferencesRefs<T extends Object>(
    Expression<T> Function($$ConversationPreferencesTableAnnotationComposer a)
    f,
  ) {
    final $$ConversationPreferencesTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.conversationPreferences,
          getReferencedColumn: (t) => t.accountId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ConversationPreferencesTableAnnotationComposer(
                $db: $db,
                $table: $db.conversationPreferences,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> messageReactionsRefs<T extends Object>(
    Expression<T> Function($$MessageReactionsTableAnnotationComposer a) f,
  ) {
    final $$MessageReactionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.messageReactions,
      getReferencedColumn: (t) => t.accountId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessageReactionsTableAnnotationComposer(
            $db: $db,
            $table: $db.messageReactions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$AccountsTableTableManager
    extends
        RootTableManager<
          _$StorageDatabase,
          $AccountsTable,
          AccountRow,
          $$AccountsTableFilterComposer,
          $$AccountsTableOrderingComposer,
          $$AccountsTableAnnotationComposer,
          $$AccountsTableCreateCompanionBuilder,
          $$AccountsTableUpdateCompanionBuilder,
          (AccountRow, $$AccountsTableReferences),
          AccountRow,
          PrefetchHooks Function({
            bool conversationsRefs,
            bool contactLinksRefs,
            bool conversationPreferencesRefs,
            bool messageReactionsRefs,
          })
        > {
  $$AccountsTableTableManager(_$StorageDatabase db, $AccountsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AccountsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AccountsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AccountsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> platform = const Value.absent(),
                Value<String> displayName = const Value.absent(),
                Value<bool> isConnected = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AccountsCompanion(
                id: id,
                platform: platform,
                displayName: displayName,
                isConnected: isConnected,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String platform,
                required String displayName,
                Value<bool> isConnected = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AccountsCompanion.insert(
                id: id,
                platform: platform,
                displayName: displayName,
                isConnected: isConnected,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AccountsTable, AccountRow>(table),
                  $$AccountsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                conversationsRefs = false,
                contactLinksRefs = false,
                conversationPreferencesRefs = false,
                messageReactionsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (conversationsRefs) db.conversations,
                    if (contactLinksRefs) db.contactLinks,
                    if (conversationPreferencesRefs) db.conversationPreferences,
                    if (messageReactionsRefs) db.messageReactions,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (conversationsRefs)
                        await $_getPrefetchedDataByColumns<
                          AccountRow,
                          $AccountsTable,
                          ConversationRow,
                          $ConversationsTable
                        >(
                          currentTable: table,
                          referencedTable: $$AccountsTableReferences
                              ._conversationsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$AccountsTableReferences(
                                db,
                                table,
                                p0,
                              ).conversationsRefs,
                          currentColumn: 'id',
                          referencedColumn: 'account_id',
                          typedResults: items,
                        ),
                      if (contactLinksRefs)
                        await $_getPrefetchedDataByColumns<
                          AccountRow,
                          $AccountsTable,
                          ContactLinkRow,
                          $ContactLinksTable
                        >(
                          currentTable: table,
                          referencedTable: $$AccountsTableReferences
                              ._contactLinksRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$AccountsTableReferences(
                                db,
                                table,
                                p0,
                              ).contactLinksRefs,
                          currentColumn: 'id',
                          referencedColumn: 'account_id',
                          typedResults: items,
                        ),
                      if (conversationPreferencesRefs)
                        await $_getPrefetchedDataByColumns<
                          AccountRow,
                          $AccountsTable,
                          PreferenceRow,
                          $ConversationPreferencesTable
                        >(
                          currentTable: table,
                          referencedTable: $$AccountsTableReferences
                              ._conversationPreferencesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$AccountsTableReferences(
                                db,
                                table,
                                p0,
                              ).conversationPreferencesRefs,
                          currentColumn: 'id',
                          referencedColumn: 'account_id',
                          typedResults: items,
                        ),
                      if (messageReactionsRefs)
                        await $_getPrefetchedDataByColumns<
                          AccountRow,
                          $AccountsTable,
                          MessageReactionRow,
                          $MessageReactionsTable
                        >(
                          currentTable: table,
                          referencedTable: $$AccountsTableReferences
                              ._messageReactionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$AccountsTableReferences(
                                db,
                                table,
                                p0,
                              ).messageReactionsRefs,
                          currentColumn: 'id',
                          referencedColumn: 'account_id',
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$AccountsTableProcessedTableManager =
    ProcessedTableManager<
      _$StorageDatabase,
      $AccountsTable,
      AccountRow,
      $$AccountsTableFilterComposer,
      $$AccountsTableOrderingComposer,
      $$AccountsTableAnnotationComposer,
      $$AccountsTableCreateCompanionBuilder,
      $$AccountsTableUpdateCompanionBuilder,
      (AccountRow, $$AccountsTableReferences),
      AccountRow,
      PrefetchHooks Function({
        bool conversationsRefs,
        bool contactLinksRefs,
        bool conversationPreferencesRefs,
        bool messageReactionsRefs,
      })
    >;
typedef $$ConversationsTableCreateCompanionBuilder =
    ConversationsCompanion Function({
      required String accountId,
      required String conversationId,
      required String title,
      required int latestActivityMicros,
      Value<int> unreadCount,
      Value<bool> isGroup,
      Value<String?> identityId,
      Value<bool> canSend,
      Value<String?> sendingUnavailableReason,
      Value<bool> isFromUnknownSender,
      Value<int> rowid,
    });
typedef $$ConversationsTableUpdateCompanionBuilder =
    ConversationsCompanion Function({
      Value<String> accountId,
      Value<String> conversationId,
      Value<String> title,
      Value<int> latestActivityMicros,
      Value<int> unreadCount,
      Value<bool> isGroup,
      Value<String?> identityId,
      Value<bool> canSend,
      Value<String?> sendingUnavailableReason,
      Value<bool> isFromUnknownSender,
      Value<int> rowid,
    });

final class $$ConversationsTableReferences
    extends
        BaseReferences<
          _$StorageDatabase,
          $ConversationsTable,
          ConversationRow
        > {
  $$ConversationsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $AccountsTable _accountIdTable(_$StorageDatabase db) =>
      db.accounts.createAlias('conversations__account_id__accounts__id');

  $$AccountsTableProcessedTableManager get accountId {
    final $_column = $_itemColumn<String>('account_id')!;

    final manager = $$AccountsTableTableManager(
      $_db,
      $_db.accounts,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_accountIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ConversationsTableFilterComposer
    extends Composer<_$StorageDatabase, $ConversationsTable> {
  $$ConversationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get latestActivityMicros => $composableBuilder(
    column: $table.latestActivityMicros,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isGroup => $composableBuilder(
    column: $table.isGroup,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get identityId => $composableBuilder(
    column: $table.identityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get canSend => $composableBuilder(
    column: $table.canSend,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sendingUnavailableReason => $composableBuilder(
    column: $table.sendingUnavailableReason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isFromUnknownSender => $composableBuilder(
    column: $table.isFromUnknownSender,
    builder: (column) => ColumnFilters(column),
  );

  $$AccountsTableFilterComposer get accountId {
    final $$AccountsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableFilterComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ConversationsTableOrderingComposer
    extends Composer<_$StorageDatabase, $ConversationsTable> {
  $$ConversationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get latestActivityMicros => $composableBuilder(
    column: $table.latestActivityMicros,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isGroup => $composableBuilder(
    column: $table.isGroup,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get identityId => $composableBuilder(
    column: $table.identityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get canSend => $composableBuilder(
    column: $table.canSend,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sendingUnavailableReason => $composableBuilder(
    column: $table.sendingUnavailableReason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isFromUnknownSender => $composableBuilder(
    column: $table.isFromUnknownSender,
    builder: (column) => ColumnOrderings(column),
  );

  $$AccountsTableOrderingComposer get accountId {
    final $$AccountsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableOrderingComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ConversationsTableAnnotationComposer
    extends Composer<_$StorageDatabase, $ConversationsTable> {
  $$ConversationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<int> get latestActivityMicros => $composableBuilder(
    column: $table.latestActivityMicros,
    builder: (column) => column,
  );

  GeneratedColumn<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isGroup =>
      $composableBuilder(column: $table.isGroup, builder: (column) => column);

  GeneratedColumn<String> get identityId => $composableBuilder(
    column: $table.identityId,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get canSend =>
      $composableBuilder(column: $table.canSend, builder: (column) => column);

  GeneratedColumn<String> get sendingUnavailableReason => $composableBuilder(
    column: $table.sendingUnavailableReason,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isFromUnknownSender => $composableBuilder(
    column: $table.isFromUnknownSender,
    builder: (column) => column,
  );

  $$AccountsTableAnnotationComposer get accountId {
    final $$AccountsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableAnnotationComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ConversationsTableTableManager
    extends
        RootTableManager<
          _$StorageDatabase,
          $ConversationsTable,
          ConversationRow,
          $$ConversationsTableFilterComposer,
          $$ConversationsTableOrderingComposer,
          $$ConversationsTableAnnotationComposer,
          $$ConversationsTableCreateCompanionBuilder,
          $$ConversationsTableUpdateCompanionBuilder,
          (ConversationRow, $$ConversationsTableReferences),
          ConversationRow,
          PrefetchHooks Function({bool accountId})
        > {
  $$ConversationsTableTableManager(
    _$StorageDatabase db,
    $ConversationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ConversationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ConversationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ConversationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> accountId = const Value.absent(),
                Value<String> conversationId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<int> latestActivityMicros = const Value.absent(),
                Value<int> unreadCount = const Value.absent(),
                Value<bool> isGroup = const Value.absent(),
                Value<String?> identityId = const Value.absent(),
                Value<bool> canSend = const Value.absent(),
                Value<String?> sendingUnavailableReason = const Value.absent(),
                Value<bool> isFromUnknownSender = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ConversationsCompanion(
                accountId: accountId,
                conversationId: conversationId,
                title: title,
                latestActivityMicros: latestActivityMicros,
                unreadCount: unreadCount,
                isGroup: isGroup,
                identityId: identityId,
                canSend: canSend,
                sendingUnavailableReason: sendingUnavailableReason,
                isFromUnknownSender: isFromUnknownSender,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String accountId,
                required String conversationId,
                required String title,
                required int latestActivityMicros,
                Value<int> unreadCount = const Value.absent(),
                Value<bool> isGroup = const Value.absent(),
                Value<String?> identityId = const Value.absent(),
                Value<bool> canSend = const Value.absent(),
                Value<String?> sendingUnavailableReason = const Value.absent(),
                Value<bool> isFromUnknownSender = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ConversationsCompanion.insert(
                accountId: accountId,
                conversationId: conversationId,
                title: title,
                latestActivityMicros: latestActivityMicros,
                unreadCount: unreadCount,
                isGroup: isGroup,
                identityId: identityId,
                canSend: canSend,
                sendingUnavailableReason: sendingUnavailableReason,
                isFromUnknownSender: isFromUnknownSender,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ConversationsTable, ConversationRow>(table),
                  $$ConversationsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({accountId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (accountId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.accountId,
                                referencedTable: $$ConversationsTableReferences
                                    ._accountIdTable(db),
                                referencedColumn: $$ConversationsTableReferences
                                    ._accountIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ConversationsTableProcessedTableManager =
    ProcessedTableManager<
      _$StorageDatabase,
      $ConversationsTable,
      ConversationRow,
      $$ConversationsTableFilterComposer,
      $$ConversationsTableOrderingComposer,
      $$ConversationsTableAnnotationComposer,
      $$ConversationsTableCreateCompanionBuilder,
      $$ConversationsTableUpdateCompanionBuilder,
      (ConversationRow, $$ConversationsTableReferences),
      ConversationRow,
      PrefetchHooks Function({bool accountId})
    >;
typedef $$MessagesTableCreateCompanionBuilder =
    MessagesCompanion Function({
      required String accountId,
      required String conversationId,
      required String id,
      required String body,
      required int timestampMicros,
      required bool isOutgoing,
      Value<String?> senderId,
      Value<String?> senderName,
      required String kind,
      required String deliveryState,
      Value<String?> replyToMessageId,
      required String attachmentsJson,
      Value<int> rowid,
    });
typedef $$MessagesTableUpdateCompanionBuilder =
    MessagesCompanion Function({
      Value<String> accountId,
      Value<String> conversationId,
      Value<String> id,
      Value<String> body,
      Value<int> timestampMicros,
      Value<bool> isOutgoing,
      Value<String?> senderId,
      Value<String?> senderName,
      Value<String> kind,
      Value<String> deliveryState,
      Value<String?> replyToMessageId,
      Value<String> attachmentsJson,
      Value<int> rowid,
    });

class $$MessagesTableFilterComposer
    extends Composer<_$StorageDatabase, $MessagesTable> {
  $$MessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get timestampMicros => $composableBuilder(
    column: $table.timestampMicros,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isOutgoing => $composableBuilder(
    column: $table.isOutgoing,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get senderId => $composableBuilder(
    column: $table.senderId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get senderName => $composableBuilder(
    column: $table.senderName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deliveryState => $composableBuilder(
    column: $table.deliveryState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get replyToMessageId => $composableBuilder(
    column: $table.replyToMessageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get attachmentsJson => $composableBuilder(
    column: $table.attachmentsJson,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MessagesTableOrderingComposer
    extends Composer<_$StorageDatabase, $MessagesTable> {
  $$MessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get timestampMicros => $composableBuilder(
    column: $table.timestampMicros,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isOutgoing => $composableBuilder(
    column: $table.isOutgoing,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get senderId => $composableBuilder(
    column: $table.senderId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get senderName => $composableBuilder(
    column: $table.senderName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deliveryState => $composableBuilder(
    column: $table.deliveryState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get replyToMessageId => $composableBuilder(
    column: $table.replyToMessageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get attachmentsJson => $composableBuilder(
    column: $table.attachmentsJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MessagesTableAnnotationComposer
    extends Composer<_$StorageDatabase, $MessagesTable> {
  $$MessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<int> get timestampMicros => $composableBuilder(
    column: $table.timestampMicros,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isOutgoing => $composableBuilder(
    column: $table.isOutgoing,
    builder: (column) => column,
  );

  GeneratedColumn<String> get senderId =>
      $composableBuilder(column: $table.senderId, builder: (column) => column);

  GeneratedColumn<String> get senderName => $composableBuilder(
    column: $table.senderName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get deliveryState => $composableBuilder(
    column: $table.deliveryState,
    builder: (column) => column,
  );

  GeneratedColumn<String> get replyToMessageId => $composableBuilder(
    column: $table.replyToMessageId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get attachmentsJson => $composableBuilder(
    column: $table.attachmentsJson,
    builder: (column) => column,
  );
}

class $$MessagesTableTableManager
    extends
        RootTableManager<
          _$StorageDatabase,
          $MessagesTable,
          MessageRow,
          $$MessagesTableFilterComposer,
          $$MessagesTableOrderingComposer,
          $$MessagesTableAnnotationComposer,
          $$MessagesTableCreateCompanionBuilder,
          $$MessagesTableUpdateCompanionBuilder,
          (
            MessageRow,
            BaseReferences<_$StorageDatabase, $MessagesTable, MessageRow>,
          ),
          MessageRow,
          PrefetchHooks Function()
        > {
  $$MessagesTableTableManager(_$StorageDatabase db, $MessagesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> accountId = const Value.absent(),
                Value<String> conversationId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<int> timestampMicros = const Value.absent(),
                Value<bool> isOutgoing = const Value.absent(),
                Value<String?> senderId = const Value.absent(),
                Value<String?> senderName = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> deliveryState = const Value.absent(),
                Value<String?> replyToMessageId = const Value.absent(),
                Value<String> attachmentsJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MessagesCompanion(
                accountId: accountId,
                conversationId: conversationId,
                id: id,
                body: body,
                timestampMicros: timestampMicros,
                isOutgoing: isOutgoing,
                senderId: senderId,
                senderName: senderName,
                kind: kind,
                deliveryState: deliveryState,
                replyToMessageId: replyToMessageId,
                attachmentsJson: attachmentsJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String accountId,
                required String conversationId,
                required String id,
                required String body,
                required int timestampMicros,
                required bool isOutgoing,
                Value<String?> senderId = const Value.absent(),
                Value<String?> senderName = const Value.absent(),
                required String kind,
                required String deliveryState,
                Value<String?> replyToMessageId = const Value.absent(),
                required String attachmentsJson,
                Value<int> rowid = const Value.absent(),
              }) => MessagesCompanion.insert(
                accountId: accountId,
                conversationId: conversationId,
                id: id,
                body: body,
                timestampMicros: timestampMicros,
                isOutgoing: isOutgoing,
                senderId: senderId,
                senderName: senderName,
                kind: kind,
                deliveryState: deliveryState,
                replyToMessageId: replyToMessageId,
                attachmentsJson: attachmentsJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$MessagesTable, MessageRow>(table),
                  BaseReferences<_$StorageDatabase, $MessagesTable, MessageRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MessagesTableProcessedTableManager =
    ProcessedTableManager<
      _$StorageDatabase,
      $MessagesTable,
      MessageRow,
      $$MessagesTableFilterComposer,
      $$MessagesTableOrderingComposer,
      $$MessagesTableAnnotationComposer,
      $$MessagesTableCreateCompanionBuilder,
      $$MessagesTableUpdateCompanionBuilder,
      (
        MessageRow,
        BaseReferences<_$StorageDatabase, $MessagesTable, MessageRow>,
      ),
      MessageRow,
      PrefetchHooks Function()
    >;
typedef $$DraftsTableCreateCompanionBuilder =
    DraftsCompanion Function({
      required String accountId,
      required String conversationId,
      required String body,
      required int revision,
      Value<String?> replyToMessageId,
      required String attachmentsJson,
      Value<int> rowid,
    });
typedef $$DraftsTableUpdateCompanionBuilder =
    DraftsCompanion Function({
      Value<String> accountId,
      Value<String> conversationId,
      Value<String> body,
      Value<int> revision,
      Value<String?> replyToMessageId,
      Value<String> attachmentsJson,
      Value<int> rowid,
    });

class $$DraftsTableFilterComposer
    extends Composer<_$StorageDatabase, $DraftsTable> {
  $$DraftsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get replyToMessageId => $composableBuilder(
    column: $table.replyToMessageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get attachmentsJson => $composableBuilder(
    column: $table.attachmentsJson,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DraftsTableOrderingComposer
    extends Composer<_$StorageDatabase, $DraftsTable> {
  $$DraftsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get replyToMessageId => $composableBuilder(
    column: $table.replyToMessageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get attachmentsJson => $composableBuilder(
    column: $table.attachmentsJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DraftsTableAnnotationComposer
    extends Composer<_$StorageDatabase, $DraftsTable> {
  $$DraftsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<String> get replyToMessageId => $composableBuilder(
    column: $table.replyToMessageId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get attachmentsJson => $composableBuilder(
    column: $table.attachmentsJson,
    builder: (column) => column,
  );
}

class $$DraftsTableTableManager
    extends
        RootTableManager<
          _$StorageDatabase,
          $DraftsTable,
          DraftRow,
          $$DraftsTableFilterComposer,
          $$DraftsTableOrderingComposer,
          $$DraftsTableAnnotationComposer,
          $$DraftsTableCreateCompanionBuilder,
          $$DraftsTableUpdateCompanionBuilder,
          (DraftRow, BaseReferences<_$StorageDatabase, $DraftsTable, DraftRow>),
          DraftRow,
          PrefetchHooks Function()
        > {
  $$DraftsTableTableManager(_$StorageDatabase db, $DraftsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DraftsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DraftsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DraftsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> accountId = const Value.absent(),
                Value<String> conversationId = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<String?> replyToMessageId = const Value.absent(),
                Value<String> attachmentsJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DraftsCompanion(
                accountId: accountId,
                conversationId: conversationId,
                body: body,
                revision: revision,
                replyToMessageId: replyToMessageId,
                attachmentsJson: attachmentsJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String accountId,
                required String conversationId,
                required String body,
                required int revision,
                Value<String?> replyToMessageId = const Value.absent(),
                required String attachmentsJson,
                Value<int> rowid = const Value.absent(),
              }) => DraftsCompanion.insert(
                accountId: accountId,
                conversationId: conversationId,
                body: body,
                revision: revision,
                replyToMessageId: replyToMessageId,
                attachmentsJson: attachmentsJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$DraftsTable, DraftRow>(table),
                  BaseReferences<_$StorageDatabase, $DraftsTable, DraftRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DraftsTableProcessedTableManager =
    ProcessedTableManager<
      _$StorageDatabase,
      $DraftsTable,
      DraftRow,
      $$DraftsTableFilterComposer,
      $$DraftsTableOrderingComposer,
      $$DraftsTableAnnotationComposer,
      $$DraftsTableCreateCompanionBuilder,
      $$DraftsTableUpdateCompanionBuilder,
      (DraftRow, BaseReferences<_$StorageDatabase, $DraftsTable, DraftRow>),
      DraftRow,
      PrefetchHooks Function()
    >;
typedef $$PendingSendsTableCreateCompanionBuilder =
    PendingSendsCompanion Function({
      required String id,
      required String accountId,
      required String conversationId,
      required String body,
      required int createdAtMicros,
      required int draftRevision,
      required String status,
      Value<String?> replyToMessageId,
      required String attachmentsJson,
      Value<int> rowid,
    });
typedef $$PendingSendsTableUpdateCompanionBuilder =
    PendingSendsCompanion Function({
      Value<String> id,
      Value<String> accountId,
      Value<String> conversationId,
      Value<String> body,
      Value<int> createdAtMicros,
      Value<int> draftRevision,
      Value<String> status,
      Value<String?> replyToMessageId,
      Value<String> attachmentsJson,
      Value<int> rowid,
    });

class $$PendingSendsTableFilterComposer
    extends Composer<_$StorageDatabase, $PendingSendsTable> {
  $$PendingSendsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtMicros => $composableBuilder(
    column: $table.createdAtMicros,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get draftRevision => $composableBuilder(
    column: $table.draftRevision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get replyToMessageId => $composableBuilder(
    column: $table.replyToMessageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get attachmentsJson => $composableBuilder(
    column: $table.attachmentsJson,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PendingSendsTableOrderingComposer
    extends Composer<_$StorageDatabase, $PendingSendsTable> {
  $$PendingSendsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtMicros => $composableBuilder(
    column: $table.createdAtMicros,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get draftRevision => $composableBuilder(
    column: $table.draftRevision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get replyToMessageId => $composableBuilder(
    column: $table.replyToMessageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get attachmentsJson => $composableBuilder(
    column: $table.attachmentsJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PendingSendsTableAnnotationComposer
    extends Composer<_$StorageDatabase, $PendingSendsTable> {
  $$PendingSendsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<int> get createdAtMicros => $composableBuilder(
    column: $table.createdAtMicros,
    builder: (column) => column,
  );

  GeneratedColumn<int> get draftRevision => $composableBuilder(
    column: $table.draftRevision,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get replyToMessageId => $composableBuilder(
    column: $table.replyToMessageId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get attachmentsJson => $composableBuilder(
    column: $table.attachmentsJson,
    builder: (column) => column,
  );
}

class $$PendingSendsTableTableManager
    extends
        RootTableManager<
          _$StorageDatabase,
          $PendingSendsTable,
          PendingSendRow,
          $$PendingSendsTableFilterComposer,
          $$PendingSendsTableOrderingComposer,
          $$PendingSendsTableAnnotationComposer,
          $$PendingSendsTableCreateCompanionBuilder,
          $$PendingSendsTableUpdateCompanionBuilder,
          (
            PendingSendRow,
            BaseReferences<
              _$StorageDatabase,
              $PendingSendsTable,
              PendingSendRow
            >,
          ),
          PendingSendRow,
          PrefetchHooks Function()
        > {
  $$PendingSendsTableTableManager(
    _$StorageDatabase db,
    $PendingSendsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PendingSendsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PendingSendsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PendingSendsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> accountId = const Value.absent(),
                Value<String> conversationId = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<int> createdAtMicros = const Value.absent(),
                Value<int> draftRevision = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> replyToMessageId = const Value.absent(),
                Value<String> attachmentsJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PendingSendsCompanion(
                id: id,
                accountId: accountId,
                conversationId: conversationId,
                body: body,
                createdAtMicros: createdAtMicros,
                draftRevision: draftRevision,
                status: status,
                replyToMessageId: replyToMessageId,
                attachmentsJson: attachmentsJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String accountId,
                required String conversationId,
                required String body,
                required int createdAtMicros,
                required int draftRevision,
                required String status,
                Value<String?> replyToMessageId = const Value.absent(),
                required String attachmentsJson,
                Value<int> rowid = const Value.absent(),
              }) => PendingSendsCompanion.insert(
                id: id,
                accountId: accountId,
                conversationId: conversationId,
                body: body,
                createdAtMicros: createdAtMicros,
                draftRevision: draftRevision,
                status: status,
                replyToMessageId: replyToMessageId,
                attachmentsJson: attachmentsJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PendingSendsTable, PendingSendRow>(table),
                  BaseReferences<
                    _$StorageDatabase,
                    $PendingSendsTable,
                    PendingSendRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PendingSendsTableProcessedTableManager =
    ProcessedTableManager<
      _$StorageDatabase,
      $PendingSendsTable,
      PendingSendRow,
      $$PendingSendsTableFilterComposer,
      $$PendingSendsTableOrderingComposer,
      $$PendingSendsTableAnnotationComposer,
      $$PendingSendsTableCreateCompanionBuilder,
      $$PendingSendsTableUpdateCompanionBuilder,
      (
        PendingSendRow,
        BaseReferences<_$StorageDatabase, $PendingSendsTable, PendingSendRow>,
      ),
      PendingSendRow,
      PrefetchHooks Function()
    >;
typedef $$PeopleTableCreateCompanionBuilder =
    PeopleCompanion Function({
      required String id,
      required String displayName,
      Value<int> rowid,
    });
typedef $$PeopleTableUpdateCompanionBuilder =
    PeopleCompanion Function({
      Value<String> id,
      Value<String> displayName,
      Value<int> rowid,
    });

final class $$PeopleTableReferences
    extends BaseReferences<_$StorageDatabase, $PeopleTable, PersonRow> {
  $$PeopleTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$ContactLinksTable, List<ContactLinkRow>>
  _contactLinksRefsTable(_$StorageDatabase db) => MultiTypedResultKey.fromTable(
    db.contactLinks,
    aliasName: 'people__id__contact_links__person_id',
  );

  $$ContactLinksTableProcessedTableManager get contactLinksRefs {
    final manager = $$ContactLinksTableTableManager(
      $_db,
      $_db.contactLinks,
    ).filter((f) => f.personId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_contactLinksRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$PeopleTableFilterComposer
    extends Composer<_$StorageDatabase, $PeopleTable> {
  $$PeopleTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> contactLinksRefs(
    Expression<bool> Function($$ContactLinksTableFilterComposer f) f,
  ) {
    final $$ContactLinksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.contactLinks,
      getReferencedColumn: (t) => t.personId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ContactLinksTableFilterComposer(
            $db: $db,
            $table: $db.contactLinks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$PeopleTableOrderingComposer
    extends Composer<_$StorageDatabase, $PeopleTable> {
  $$PeopleTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PeopleTableAnnotationComposer
    extends Composer<_$StorageDatabase, $PeopleTable> {
  $$PeopleTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  Expression<T> contactLinksRefs<T extends Object>(
    Expression<T> Function($$ContactLinksTableAnnotationComposer a) f,
  ) {
    final $$ContactLinksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.contactLinks,
      getReferencedColumn: (t) => t.personId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ContactLinksTableAnnotationComposer(
            $db: $db,
            $table: $db.contactLinks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$PeopleTableTableManager
    extends
        RootTableManager<
          _$StorageDatabase,
          $PeopleTable,
          PersonRow,
          $$PeopleTableFilterComposer,
          $$PeopleTableOrderingComposer,
          $$PeopleTableAnnotationComposer,
          $$PeopleTableCreateCompanionBuilder,
          $$PeopleTableUpdateCompanionBuilder,
          (PersonRow, $$PeopleTableReferences),
          PersonRow,
          PrefetchHooks Function({bool contactLinksRefs})
        > {
  $$PeopleTableTableManager(_$StorageDatabase db, $PeopleTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PeopleTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PeopleTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PeopleTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> displayName = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PeopleCompanion(
                id: id,
                displayName: displayName,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String displayName,
                Value<int> rowid = const Value.absent(),
              }) => PeopleCompanion.insert(
                id: id,
                displayName: displayName,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PeopleTable, PersonRow>(table),
                  $$PeopleTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({contactLinksRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (contactLinksRefs) db.contactLinks],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (contactLinksRefs)
                    await $_getPrefetchedDataByColumns<
                      PersonRow,
                      $PeopleTable,
                      ContactLinkRow,
                      $ContactLinksTable
                    >(
                      currentTable: table,
                      referencedTable: $$PeopleTableReferences
                          ._contactLinksRefsTable(db),
                      managerFromTypedResult: (p0) => $$PeopleTableReferences(
                        db,
                        table,
                        p0,
                      ).contactLinksRefs,
                      currentColumn: 'id',
                      referencedColumn: 'person_id',
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$PeopleTableProcessedTableManager =
    ProcessedTableManager<
      _$StorageDatabase,
      $PeopleTable,
      PersonRow,
      $$PeopleTableFilterComposer,
      $$PeopleTableOrderingComposer,
      $$PeopleTableAnnotationComposer,
      $$PeopleTableCreateCompanionBuilder,
      $$PeopleTableUpdateCompanionBuilder,
      (PersonRow, $$PeopleTableReferences),
      PersonRow,
      PrefetchHooks Function({bool contactLinksRefs})
    >;
typedef $$ContactLinksTableCreateCompanionBuilder =
    ContactLinksCompanion Function({
      required String accountId,
      required String identityId,
      required String personId,
      Value<int> rowid,
    });
typedef $$ContactLinksTableUpdateCompanionBuilder =
    ContactLinksCompanion Function({
      Value<String> accountId,
      Value<String> identityId,
      Value<String> personId,
      Value<int> rowid,
    });

final class $$ContactLinksTableReferences
    extends
        BaseReferences<_$StorageDatabase, $ContactLinksTable, ContactLinkRow> {
  $$ContactLinksTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $AccountsTable _accountIdTable(_$StorageDatabase db) =>
      db.accounts.createAlias('contact_links__account_id__accounts__id');

  $$AccountsTableProcessedTableManager get accountId {
    final $_column = $_itemColumn<String>('account_id')!;

    final manager = $$AccountsTableTableManager(
      $_db,
      $_db.accounts,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_accountIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $PeopleTable _personIdTable(_$StorageDatabase db) =>
      db.people.createAlias('contact_links__person_id__people__id');

  $$PeopleTableProcessedTableManager get personId {
    final $_column = $_itemColumn<String>('person_id')!;

    final manager = $$PeopleTableTableManager(
      $_db,
      $_db.people,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_personIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ContactLinksTableFilterComposer
    extends Composer<_$StorageDatabase, $ContactLinksTable> {
  $$ContactLinksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get identityId => $composableBuilder(
    column: $table.identityId,
    builder: (column) => ColumnFilters(column),
  );

  $$AccountsTableFilterComposer get accountId {
    final $$AccountsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableFilterComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$PeopleTableFilterComposer get personId {
    final $$PeopleTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personId,
      referencedTable: $db.people,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PeopleTableFilterComposer(
            $db: $db,
            $table: $db.people,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ContactLinksTableOrderingComposer
    extends Composer<_$StorageDatabase, $ContactLinksTable> {
  $$ContactLinksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get identityId => $composableBuilder(
    column: $table.identityId,
    builder: (column) => ColumnOrderings(column),
  );

  $$AccountsTableOrderingComposer get accountId {
    final $$AccountsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableOrderingComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$PeopleTableOrderingComposer get personId {
    final $$PeopleTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personId,
      referencedTable: $db.people,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PeopleTableOrderingComposer(
            $db: $db,
            $table: $db.people,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ContactLinksTableAnnotationComposer
    extends Composer<_$StorageDatabase, $ContactLinksTable> {
  $$ContactLinksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get identityId => $composableBuilder(
    column: $table.identityId,
    builder: (column) => column,
  );

  $$AccountsTableAnnotationComposer get accountId {
    final $$AccountsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableAnnotationComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$PeopleTableAnnotationComposer get personId {
    final $$PeopleTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personId,
      referencedTable: $db.people,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PeopleTableAnnotationComposer(
            $db: $db,
            $table: $db.people,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ContactLinksTableTableManager
    extends
        RootTableManager<
          _$StorageDatabase,
          $ContactLinksTable,
          ContactLinkRow,
          $$ContactLinksTableFilterComposer,
          $$ContactLinksTableOrderingComposer,
          $$ContactLinksTableAnnotationComposer,
          $$ContactLinksTableCreateCompanionBuilder,
          $$ContactLinksTableUpdateCompanionBuilder,
          (ContactLinkRow, $$ContactLinksTableReferences),
          ContactLinkRow,
          PrefetchHooks Function({bool accountId, bool personId})
        > {
  $$ContactLinksTableTableManager(
    _$StorageDatabase db,
    $ContactLinksTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ContactLinksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ContactLinksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ContactLinksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> accountId = const Value.absent(),
                Value<String> identityId = const Value.absent(),
                Value<String> personId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ContactLinksCompanion(
                accountId: accountId,
                identityId: identityId,
                personId: personId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String accountId,
                required String identityId,
                required String personId,
                Value<int> rowid = const Value.absent(),
              }) => ContactLinksCompanion.insert(
                accountId: accountId,
                identityId: identityId,
                personId: personId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ContactLinksTable, ContactLinkRow>(table),
                  $$ContactLinksTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({accountId = false, personId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (accountId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.accountId,
                                referencedTable: $$ContactLinksTableReferences
                                    ._accountIdTable(db),
                                referencedColumn: $$ContactLinksTableReferences
                                    ._accountIdTable(db)
                                    .id,
                              )
                              as T;
                    }
                    if (personId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.personId,
                                referencedTable: $$ContactLinksTableReferences
                                    ._personIdTable(db),
                                referencedColumn: $$ContactLinksTableReferences
                                    ._personIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ContactLinksTableProcessedTableManager =
    ProcessedTableManager<
      _$StorageDatabase,
      $ContactLinksTable,
      ContactLinkRow,
      $$ContactLinksTableFilterComposer,
      $$ContactLinksTableOrderingComposer,
      $$ContactLinksTableAnnotationComposer,
      $$ContactLinksTableCreateCompanionBuilder,
      $$ContactLinksTableUpdateCompanionBuilder,
      (ContactLinkRow, $$ContactLinksTableReferences),
      ContactLinkRow,
      PrefetchHooks Function({bool accountId, bool personId})
    >;
typedef $$ConversationPreferencesTableCreateCompanionBuilder =
    ConversationPreferencesCompanion Function({
      required String accountId,
      required String conversationId,
      Value<bool> isFavorite,
      Value<bool> markedUnread,
      Value<bool> isMuted,
      Value<int?> mutedUntilMicros,
      Value<int?> hiddenAtMicros,
      Value<int?> readThroughMicros,
      Value<int> rowid,
    });
typedef $$ConversationPreferencesTableUpdateCompanionBuilder =
    ConversationPreferencesCompanion Function({
      Value<String> accountId,
      Value<String> conversationId,
      Value<bool> isFavorite,
      Value<bool> markedUnread,
      Value<bool> isMuted,
      Value<int?> mutedUntilMicros,
      Value<int?> hiddenAtMicros,
      Value<int?> readThroughMicros,
      Value<int> rowid,
    });

final class $$ConversationPreferencesTableReferences
    extends
        BaseReferences<
          _$StorageDatabase,
          $ConversationPreferencesTable,
          PreferenceRow
        > {
  $$ConversationPreferencesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $AccountsTable _accountIdTable(_$StorageDatabase db) => db.accounts
      .createAlias('conversation_preferences__account_id__accounts__id');

  $$AccountsTableProcessedTableManager get accountId {
    final $_column = $_itemColumn<String>('account_id')!;

    final manager = $$AccountsTableTableManager(
      $_db,
      $_db.accounts,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_accountIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ConversationPreferencesTableFilterComposer
    extends Composer<_$StorageDatabase, $ConversationPreferencesTable> {
  $$ConversationPreferencesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get markedUnread => $composableBuilder(
    column: $table.markedUnread,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isMuted => $composableBuilder(
    column: $table.isMuted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get mutedUntilMicros => $composableBuilder(
    column: $table.mutedUntilMicros,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get hiddenAtMicros => $composableBuilder(
    column: $table.hiddenAtMicros,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get readThroughMicros => $composableBuilder(
    column: $table.readThroughMicros,
    builder: (column) => ColumnFilters(column),
  );

  $$AccountsTableFilterComposer get accountId {
    final $$AccountsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableFilterComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ConversationPreferencesTableOrderingComposer
    extends Composer<_$StorageDatabase, $ConversationPreferencesTable> {
  $$ConversationPreferencesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get markedUnread => $composableBuilder(
    column: $table.markedUnread,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isMuted => $composableBuilder(
    column: $table.isMuted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get mutedUntilMicros => $composableBuilder(
    column: $table.mutedUntilMicros,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get hiddenAtMicros => $composableBuilder(
    column: $table.hiddenAtMicros,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get readThroughMicros => $composableBuilder(
    column: $table.readThroughMicros,
    builder: (column) => ColumnOrderings(column),
  );

  $$AccountsTableOrderingComposer get accountId {
    final $$AccountsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableOrderingComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ConversationPreferencesTableAnnotationComposer
    extends Composer<_$StorageDatabase, $ConversationPreferencesTable> {
  $$ConversationPreferencesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get markedUnread => $composableBuilder(
    column: $table.markedUnread,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isMuted =>
      $composableBuilder(column: $table.isMuted, builder: (column) => column);

  GeneratedColumn<int> get mutedUntilMicros => $composableBuilder(
    column: $table.mutedUntilMicros,
    builder: (column) => column,
  );

  GeneratedColumn<int> get hiddenAtMicros => $composableBuilder(
    column: $table.hiddenAtMicros,
    builder: (column) => column,
  );

  GeneratedColumn<int> get readThroughMicros => $composableBuilder(
    column: $table.readThroughMicros,
    builder: (column) => column,
  );

  $$AccountsTableAnnotationComposer get accountId {
    final $$AccountsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableAnnotationComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ConversationPreferencesTableTableManager
    extends
        RootTableManager<
          _$StorageDatabase,
          $ConversationPreferencesTable,
          PreferenceRow,
          $$ConversationPreferencesTableFilterComposer,
          $$ConversationPreferencesTableOrderingComposer,
          $$ConversationPreferencesTableAnnotationComposer,
          $$ConversationPreferencesTableCreateCompanionBuilder,
          $$ConversationPreferencesTableUpdateCompanionBuilder,
          (PreferenceRow, $$ConversationPreferencesTableReferences),
          PreferenceRow,
          PrefetchHooks Function({bool accountId})
        > {
  $$ConversationPreferencesTableTableManager(
    _$StorageDatabase db,
    $ConversationPreferencesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ConversationPreferencesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$ConversationPreferencesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ConversationPreferencesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> accountId = const Value.absent(),
                Value<String> conversationId = const Value.absent(),
                Value<bool> isFavorite = const Value.absent(),
                Value<bool> markedUnread = const Value.absent(),
                Value<bool> isMuted = const Value.absent(),
                Value<int?> mutedUntilMicros = const Value.absent(),
                Value<int?> hiddenAtMicros = const Value.absent(),
                Value<int?> readThroughMicros = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ConversationPreferencesCompanion(
                accountId: accountId,
                conversationId: conversationId,
                isFavorite: isFavorite,
                markedUnread: markedUnread,
                isMuted: isMuted,
                mutedUntilMicros: mutedUntilMicros,
                hiddenAtMicros: hiddenAtMicros,
                readThroughMicros: readThroughMicros,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String accountId,
                required String conversationId,
                Value<bool> isFavorite = const Value.absent(),
                Value<bool> markedUnread = const Value.absent(),
                Value<bool> isMuted = const Value.absent(),
                Value<int?> mutedUntilMicros = const Value.absent(),
                Value<int?> hiddenAtMicros = const Value.absent(),
                Value<int?> readThroughMicros = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ConversationPreferencesCompanion.insert(
                accountId: accountId,
                conversationId: conversationId,
                isFavorite: isFavorite,
                markedUnread: markedUnread,
                isMuted: isMuted,
                mutedUntilMicros: mutedUntilMicros,
                hiddenAtMicros: hiddenAtMicros,
                readThroughMicros: readThroughMicros,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ConversationPreferencesTable, PreferenceRow>(
                    table,
                  ),
                  $$ConversationPreferencesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({accountId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (accountId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.accountId,
                                referencedTable:
                                    $$ConversationPreferencesTableReferences
                                        ._accountIdTable(db),
                                referencedColumn:
                                    $$ConversationPreferencesTableReferences
                                        ._accountIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ConversationPreferencesTableProcessedTableManager =
    ProcessedTableManager<
      _$StorageDatabase,
      $ConversationPreferencesTable,
      PreferenceRow,
      $$ConversationPreferencesTableFilterComposer,
      $$ConversationPreferencesTableOrderingComposer,
      $$ConversationPreferencesTableAnnotationComposer,
      $$ConversationPreferencesTableCreateCompanionBuilder,
      $$ConversationPreferencesTableUpdateCompanionBuilder,
      (PreferenceRow, $$ConversationPreferencesTableReferences),
      PreferenceRow,
      PrefetchHooks Function({bool accountId})
    >;
typedef $$MessageReactionsTableCreateCompanionBuilder =
    MessageReactionsCompanion Function({
      required String accountId,
      required String conversationId,
      required String messageId,
      required String sourceId,
      required String reactionKey,
      required int count,
      required bool includesMe,
      required int recordedAtMicros,
      Value<int> rowid,
    });
typedef $$MessageReactionsTableUpdateCompanionBuilder =
    MessageReactionsCompanion Function({
      Value<String> accountId,
      Value<String> conversationId,
      Value<String> messageId,
      Value<String> sourceId,
      Value<String> reactionKey,
      Value<int> count,
      Value<bool> includesMe,
      Value<int> recordedAtMicros,
      Value<int> rowid,
    });

final class $$MessageReactionsTableReferences
    extends
        BaseReferences<
          _$StorageDatabase,
          $MessageReactionsTable,
          MessageReactionRow
        > {
  $$MessageReactionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $AccountsTable _accountIdTable(_$StorageDatabase db) =>
      db.accounts.createAlias('message_reactions__account_id__accounts__id');

  $$AccountsTableProcessedTableManager get accountId {
    final $_column = $_itemColumn<String>('account_id')!;

    final manager = $$AccountsTableTableManager(
      $_db,
      $_db.accounts,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_accountIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$MessageReactionsTableFilterComposer
    extends Composer<_$StorageDatabase, $MessageReactionsTable> {
  $$MessageReactionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reactionKey => $composableBuilder(
    column: $table.reactionKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get count => $composableBuilder(
    column: $table.count,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get includesMe => $composableBuilder(
    column: $table.includesMe,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get recordedAtMicros => $composableBuilder(
    column: $table.recordedAtMicros,
    builder: (column) => ColumnFilters(column),
  );

  $$AccountsTableFilterComposer get accountId {
    final $$AccountsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableFilterComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MessageReactionsTableOrderingComposer
    extends Composer<_$StorageDatabase, $MessageReactionsTable> {
  $$MessageReactionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reactionKey => $composableBuilder(
    column: $table.reactionKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get count => $composableBuilder(
    column: $table.count,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get includesMe => $composableBuilder(
    column: $table.includesMe,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get recordedAtMicros => $composableBuilder(
    column: $table.recordedAtMicros,
    builder: (column) => ColumnOrderings(column),
  );

  $$AccountsTableOrderingComposer get accountId {
    final $$AccountsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableOrderingComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MessageReactionsTableAnnotationComposer
    extends Composer<_$StorageDatabase, $MessageReactionsTable> {
  $$MessageReactionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get messageId =>
      $composableBuilder(column: $table.messageId, builder: (column) => column);

  GeneratedColumn<String> get sourceId =>
      $composableBuilder(column: $table.sourceId, builder: (column) => column);

  GeneratedColumn<String> get reactionKey => $composableBuilder(
    column: $table.reactionKey,
    builder: (column) => column,
  );

  GeneratedColumn<int> get count =>
      $composableBuilder(column: $table.count, builder: (column) => column);

  GeneratedColumn<bool> get includesMe => $composableBuilder(
    column: $table.includesMe,
    builder: (column) => column,
  );

  GeneratedColumn<int> get recordedAtMicros => $composableBuilder(
    column: $table.recordedAtMicros,
    builder: (column) => column,
  );

  $$AccountsTableAnnotationComposer get accountId {
    final $$AccountsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableAnnotationComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MessageReactionsTableTableManager
    extends
        RootTableManager<
          _$StorageDatabase,
          $MessageReactionsTable,
          MessageReactionRow,
          $$MessageReactionsTableFilterComposer,
          $$MessageReactionsTableOrderingComposer,
          $$MessageReactionsTableAnnotationComposer,
          $$MessageReactionsTableCreateCompanionBuilder,
          $$MessageReactionsTableUpdateCompanionBuilder,
          (MessageReactionRow, $$MessageReactionsTableReferences),
          MessageReactionRow,
          PrefetchHooks Function({bool accountId})
        > {
  $$MessageReactionsTableTableManager(
    _$StorageDatabase db,
    $MessageReactionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MessageReactionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MessageReactionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MessageReactionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> accountId = const Value.absent(),
                Value<String> conversationId = const Value.absent(),
                Value<String> messageId = const Value.absent(),
                Value<String> sourceId = const Value.absent(),
                Value<String> reactionKey = const Value.absent(),
                Value<int> count = const Value.absent(),
                Value<bool> includesMe = const Value.absent(),
                Value<int> recordedAtMicros = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MessageReactionsCompanion(
                accountId: accountId,
                conversationId: conversationId,
                messageId: messageId,
                sourceId: sourceId,
                reactionKey: reactionKey,
                count: count,
                includesMe: includesMe,
                recordedAtMicros: recordedAtMicros,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String accountId,
                required String conversationId,
                required String messageId,
                required String sourceId,
                required String reactionKey,
                required int count,
                required bool includesMe,
                required int recordedAtMicros,
                Value<int> rowid = const Value.absent(),
              }) => MessageReactionsCompanion.insert(
                accountId: accountId,
                conversationId: conversationId,
                messageId: messageId,
                sourceId: sourceId,
                reactionKey: reactionKey,
                count: count,
                includesMe: includesMe,
                recordedAtMicros: recordedAtMicros,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$MessageReactionsTable, MessageReactionRow>(
                    table,
                  ),
                  $$MessageReactionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({accountId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (accountId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.accountId,
                                referencedTable:
                                    $$MessageReactionsTableReferences
                                        ._accountIdTable(db),
                                referencedColumn:
                                    $$MessageReactionsTableReferences
                                        ._accountIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$MessageReactionsTableProcessedTableManager =
    ProcessedTableManager<
      _$StorageDatabase,
      $MessageReactionsTable,
      MessageReactionRow,
      $$MessageReactionsTableFilterComposer,
      $$MessageReactionsTableOrderingComposer,
      $$MessageReactionsTableAnnotationComposer,
      $$MessageReactionsTableCreateCompanionBuilder,
      $$MessageReactionsTableUpdateCompanionBuilder,
      (MessageReactionRow, $$MessageReactionsTableReferences),
      MessageReactionRow,
      PrefetchHooks Function({bool accountId})
    >;

class $StorageDatabaseManager {
  final _$StorageDatabase _db;
  $StorageDatabaseManager(this._db);
  $$AccountsTableTableManager get accounts =>
      $$AccountsTableTableManager(_db, _db.accounts);
  $$ConversationsTableTableManager get conversations =>
      $$ConversationsTableTableManager(_db, _db.conversations);
  $$MessagesTableTableManager get messages =>
      $$MessagesTableTableManager(_db, _db.messages);
  $$DraftsTableTableManager get drafts =>
      $$DraftsTableTableManager(_db, _db.drafts);
  $$PendingSendsTableTableManager get pendingSends =>
      $$PendingSendsTableTableManager(_db, _db.pendingSends);
  $$PeopleTableTableManager get people =>
      $$PeopleTableTableManager(_db, _db.people);
  $$ContactLinksTableTableManager get contactLinks =>
      $$ContactLinksTableTableManager(_db, _db.contactLinks);
  $$ConversationPreferencesTableTableManager get conversationPreferences =>
      $$ConversationPreferencesTableTableManager(
        _db,
        _db.conversationPreferences,
      );
  $$MessageReactionsTableTableManager get messageReactions =>
      $$MessageReactionsTableTableManager(_db, _db.messageReactions);
}
