import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:inboxplus_storage/inboxplus_storage.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import 'connectors/connector_engine.dart';
import 'connectors/native_connector_engine.dart';
import 'contact_suggestions.dart';
import 'platform/app_environment.dart';
import 'platform/profile_migration.dart';
import 'ui/inbox_ui_controller.dart';

typedef NativeCall = Future<Object?> Function(
  String method,
  Map<String, Object?> arguments,
);

class AppController extends InboxUiController {
  AppController({
    required this.store,
    required this.environment,
    this.engine,
    NativeCall? nativeCall,
    DateTime Function()? now,
  }) : _nativeCall = nativeCall ?? _invokeNative,
       _now = now ?? DateTime.now;

  final LocalStore store;
  final AppEnvironment environment;
  final ConnectorEngine? engine;
  final NativeCall _nativeCall;
  final DateTime Function() _now;
  late DateTime _messageCutoff;
  final _uuid = const Uuid();
  final _accounts = <String, AccountRecord>{};
  final _conversations = <ConversationRoute, ConversationRecord>{};
  final _messages = <ConversationRoute, List<MessageRecord>>{};
  final _reactions =
      <ConversationRoute, Map<String, List<MessageReactionRecord>>>{};
  final _reacting = <(ConversationRoute, String)>{};
  final _inlineImageLoads =
      <(ConversationRoute, String), AttachmentLoadState>{};
  final _drafts = <ConversationRoute, DraftRecord>{};
  final _conversationPreferences =
      <ConversationRoute, ConversationPreferencesRecord>{};
  final _draftWrites = <ConversationRoute, Future<void>>{};
  final _sending = <String>{};
  final _enqueueing = <ConversationRoute>{};
  final _initialized = <String>{};
  final _newLoginAccounts = <String>{};
  final _loginStorageSetup = <String, Future<void>>{};
  List<PendingSendRecord> _pending = [];
  List<ContactRecord> _contacts = [];
  final _acceptingContactSuggestions = <String>{};
  List<NetworkCapability> _networks = [];
  final _attachmentLimits = <String, int>{};
  PreferencesRecord _preferences = const PreferencesRecord();
  String _launchAtLoginStatus = 'unavailable';
  bool _supportsUpdates = false;
  SystemNotificationStatus _notificationStatus =
      const SystemNotificationStatus();
  int _notificationStatusGeneration = 0;
  final _networkProblems = <String, AccountNetworkProblem>{};
  final _changingAccounts = <String>{};
  final _deletingAccounts = <String>{};
  final _stagingAttachments = <ConversationRoute>{};
  int? _publishedUnreadCount;
  StorageSummary _storageSummary = const StorageSummary();
  Timer? _statisticsTimer;
  Future<void> _statisticsFuture = Future.value();
  StreamSubscription<ConnectorEvent>? _events;
  Timer? _imessageTimer;
  Future<void> _eventQueue = Future.value();
  ConversationRoute? _selectedRoute;
  int _notificationActivation = 0;
  Future<void> _notificationOpening = Future.value();
  LoginState? _login;
  String? _loginAccount;
  bool _loginPhonePairing = false;
  bool _loginQrSelected = true;
  bool _nativeLoginActive = false;
  Timer? _loginExpiryTimer;
  int _loginGeneration = 0;
  bool _loading = true;
  Future<void> _avatarQueue = Future.value();
  final _requestedAvatars = <ConversationRoute, String>{};
  bool _closed = false;
  bool _isClosing = false;
  Future<void>? _closing;
  final _operations = <Future<void>>{};
  final _accountWork = <String, Set<Future<void>>>{};
  Future<void>? _refreshing;
  bool _syncingIMessage = false;
  int _busy = 0;
  String? _error;
  int _maxAttachmentBytes = 32 * 1024 * 1024;
  Future<void> _previewDownloads = Future.value();

  static Future<Object?> _invokeNative(
    String method,
    Map<String, Object?> arguments,
  ) => AppEnvironment.native.invokeMethod<Object?>(method, arguments);

  static Future<AppController> open() async {
    final environment = await AppEnvironment.open();
    final database = File(p.join(environment.directory.path, 'inbox.sqlite'));
    final key = await environment.keyFor(
      'database',
      existingData: await database.exists(),
    );
    final store = await LocalStore.open(file: database, key: key);
    ConnectorEngine? engine;
    try {
      engine = await NativeConnectorEngine.open();
    } on ConnectorException {
      // Cached conversations remain usable when the native component is missing.
    }
    final controller = AppController(
      store: store,
      environment: environment,
      engine: engine,
    );
    try {
      final migration = await ProfileMigration(environment).run(store);
      await controller.initialize(reconnect: false);
      controller._error ??= migration.notice;
      return controller;
    } catch (_) {
      await controller.close();
      rethrow;
    }
  }

  Future<void> initialize({bool reconnect = true}) async {
    _accounts.addEntries(
      (await store.loadAccounts()).map(
        (a) => MapEntry(
          a.id,
          AccountRecord(
            id: a.id,
            platform: a.platform,
            displayName: a.displayName,
          ),
        ),
      ),
    );
    for (final conversation in await store.loadConversations()) {
      _conversations[conversation.route] = conversation;
      _messages[conversation.route] = await store.loadRecentMessages(
        conversation.route,
      );
      final draft = await store.loadDraft(conversation.route);
      if (draft != null) _drafts[conversation.route] = draft;
    }
    for (final item in await store.loadConversationPreferences()) {
      _conversationPreferences[item.route] = item;
    }
    _contacts = await store.loadContacts();
    _pending = await store.loadPendingSends();
    for (final send in _pending.where(
      (s) => s.status == PendingSendStatus.sending,
    )) {
      await store.savePendingSendStatus(send.id, PendingSendStatus.unknown);
    }
    _pending = await store.loadPendingSends();
    final savedPreferences = await environment.secrets.read(
      environment.secretName('preferences'),
    );
    if (savedPreferences != null) {
      _preferences = PreferencesRecord.fromJson(
        (jsonDecode(savedPreferences) as Map).cast<String, Object?>(),
      );
    } else if (environment.legacyProfileDirectory != null) {
      final legacy = await _optionalNative('legacyPreferences');
      final appearance = legacy['appearance'];
      _preferences = PreferencesRecord(
        appearance:
            appearance is String &&
                {'system', 'light', 'dark'}.contains(appearance)
            ? appearance
            : 'system',
        notificationsEnabled: legacy['notifications_enabled'] as bool? ?? true,
        notificationPreviews: legacy['notification_previews'] as bool? ?? true,
        notificationSound: legacy['notification_sound'] as bool? ?? true,
        messageRetentionDays: legacy['message_retention_days'] as int? ?? 90,
        iMessageHistory: legacy['imessage_history'] as String? ?? 'year',
        playsInstagramReels: legacy['plays_instagram_reels'] as bool? ?? true,
        showsUnreadBadge: legacy['shows_unread_badge'] as bool? ?? true,
        themePreset: legacy['theme_preset'] as String? ?? 'classic',
        customColors: legacy['custom_colors'] == null
            ? const [0xe8e8ed, 0x000000, 0x000000]
            : (legacy['custom_colors'] as List).cast<int>(),
      );
      await environment.secrets.write(
        environment.secretName('preferences'),
        jsonEncode(_preferences.toJson()),
      );
    }
    _messageCutoff = _now().subtract(
      Duration(days: _preferences.messageRetentionDays),
    );
    await store.pruneMessagesBefore(_messageCutoff);
    for (final route in _messages.keys.toList()) {
      _messages[route] = await store.loadRecentMessages(route);
    }
    for (final state in await store.loadMessageReactions()) {
      _reactions.putIfAbsent(state.route, () => {})[state.messageId] =
          state.reactions;
    }
    final nativeCapabilities = await _optionalNative('capabilities');
    _supportsUpdates = nativeCapabilities['updates'] == true;
    await refreshNotificationStatus();
    _launchAtLoginStatus =
        nativeCapabilities['launch_at_login_status'] as String? ??
        'unavailable';
    await _syncWindowTheme();
    Map<String, Object?> capabilities = {};
    if (engine != null) {
      capabilities = await engine!.request({'op': 'capabilities'});
      _maxAttachmentBytes =
          (capabilities['max_attachment_bytes'] as num?)?.toInt() ??
          _maxAttachmentBytes;
      _events = engine!.events.listen((event) {
        _eventQueue = _eventQueue.then((_) => _handleEvent(event)).catchError((
          Object error,
        ) {
          _error = _safeError(error);
          _publish();
        });
      });
    }
    final platforms =
        (capabilities['platforms'] as List?)?.whereType<String>().toSet() ??
        <String>{};
    final webLogin =
        (nativeCapabilities['web_login_platforms'] as List?)
            ?.whereType<String>()
            .toSet() ??
        <String>{};
    final features = capabilities['features'] as Map? ?? {};
    for (final platform in platforms) {
      final limit = (features[platform] as Map?)?['max_attachment_bytes'];
      if (limit is num && limit > 0) {
        _attachmentLimits[platform] = limit.toInt().clamp(
          1,
          _maxAttachmentBytes,
        );
      }
    }
    final hasIMessage =
        defaultTargetPlatform == TargetPlatform.macOS &&
        nativeCapabilities['imessage'] == true;
    _networks = [
      for (final entry in {
        'whatsapp': 'WhatsApp',
        'telegram': 'Telegram',
        'instagram': 'Instagram',
        'messenger': 'Messenger',
        'wechat': 'WeChat',
        'discord': 'Discord',
        'linkedIn': 'LinkedIn',
      }.entries)
        NetworkCapability(
          id: entry.key,
          name: entry.value,
          available:
              platforms.contains(entry.key) &&
              (!{'instagram', 'messenger'}.contains(entry.key) ||
                  webLogin.contains(entry.key)),
          reason: !platforms.contains(entry.key)
              ? 'The messaging component is unavailable in this build.'
              : !webLogin.contains(entry.key) &&
                    {'instagram', 'messenger'}.contains(entry.key)
              ? 'Private web sign-in is unavailable on this device.'
              : null,
          description: entry.key == 'telegram'
              ? 'Sign in with your phone number and Telegram app credentials.'
              : entry.key == 'messenger'
              ? 'Connect Facebook chats. Encrypted chats are currently unavailable.'
              : entry.key == 'wechat'
              ? 'Scan with WeChat. Available history depends on WeChat web access.'
              : entry.key == 'discord'
              ? 'Direct and group messages. Discord restricts unofficial personal clients.'
              : 'Connect directly from this device.',
          canAttach: (features[entry.key] as Map?)?['send_attachment'] == true,
          canReply: (features[entry.key] as Map?)?['replies'] == true,
          canReact: (features[entry.key] as Map?)?['reactions'] == true,
          canStartConversation:
              (features[entry.key] as Map?)?['start_conversation'] == true,
        ),
      if (hasIMessage)
        const NetworkCapability(
          id: 'imessage',
          name: 'iMessage',
          available: true,
          description: 'Use Messages on this Mac. Requires Full Disk Access and automation permission.',
          canStartConversation: true,
        )
      else if (defaultTargetPlatform == TargetPlatform.iOS)
        const NetworkCapability(
          id: 'imessage',
          name: 'iMessage',
          available: false,
          comingSoon: true,
          reason: 'Coming soon · Experimental iOS integration',
        ),
      for (final entry in {'slack': 'Slack'}.entries)
        NetworkCapability(
          id: entry.key,
          name: entry.value,
          available: false,
          comingSoon: true,
          reason: "It's coming soon",
        ),
    ];
    _loading = false;
    await _reloadStatistics();
    _publish();
    await _updateCloseGuard();
    if (reconnect) {
      await refresh();
    } else {
      unawaited(refresh());
    }
    if (hasIMessage) {
      _imessageTimer = Timer.periodic(const Duration(seconds: 15), (_) {
        if (_accounts['imessage-local']?.isConnected == true) {
          unawaited(
            _perform(
              () => _accountTask('imessage-local', _syncIMessage),
              background: true,
            ),
          );
        }
      });
    }
    await openPendingNotification();
  }

  @override
  bool get isLoading => _loading;
  @override
  bool get isBusy => _busy > 0;
  @override
  bool get isOffline => !_accounts.values.any((a) => a.isConnected);
  @override
  String? get error => _error;
  @override
  List<AccountRecord> get accounts => List.unmodifiable(_accounts.values);
  @override
  List<ConversationRecord> get conversations {
    final items =
        _conversations.values
            .map(
              (chat) =>
                  preferencesFor(chat.route).markedUnread &&
                      chat.unreadCount == 0
                  ? chat.copyWith(unreadCount: 1)
                  : chat,
            )
            .toList()
          ..sort((a, b) => b.latestActivity.compareTo(a.latestActivity));
    return List.unmodifiable(items);
  }

  @override
  List<ContactRecord> get contacts => List.unmodifiable(_contacts);
  @override
  List<NetworkCapability> get networks => List.unmodifiable(_networks);
  @override
  ConversationRoute? get selectedRoute => _selectedRoute;
  @override
  LoginState? get login => _login;
  @override
  PreferencesRecord get preferences => _preferences;
  @override
  String get launchAtLoginStatus => _launchAtLoginStatus;
  @override
  bool get supportsUpdates => _supportsUpdates;
  @override
  Future<void> checkForUpdates() async {
    if (_supportsUpdates) await _nativeCall('checkForUpdates', {});
  }

  @override
  SystemNotificationStatus get notificationStatus => _notificationStatus;
  @override
  AccountNetworkProblem? networkProblem(String accountId) =>
      _networkProblems[accountId];
  @override
  bool isChangingAccount(String accountId) =>
      _changingAccounts.contains(accountId);
  @override
  StorageSummary get storageSummary {
    return _storageSummary;
  }

  @override
  List<MessageRecord> messagesFor(ConversationRoute route) {
    final result = [...?_messages[route]];
    for (final send in _pending.where((s) => s.route == route)) {
      result.add(
        MessageRecord(
          id: send.id,
          route: route,
          body: send.body,
          timestamp: send.createdAt,
          isOutgoing: true,
          attachments: send.attachments,
          replyToMessageId: send.replyToMessageId,
          deliveryState:
              send.status == PendingSendStatus.queued ||
                  send.status == PendingSendStatus.sending
              ? DeliveryState.pending
              : DeliveryState.failed,
        ),
      );
    }
    result.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return List.unmodifiable(result);
  }

  @override
  DraftRecord? draftFor(ConversationRoute route) => _drafts[route];
  @override
  ConversationPreferencesRecord preferencesFor(ConversationRoute route) =>
      _conversationPreferences[route] ??
      ConversationPreferencesRecord(route: route);
  @override
  Map<String, int> reactionsFor(ConversationRoute route, String messageId) => {
    for (final reaction
        in _reactions[route]?[messageId] ?? <MessageReactionRecord>[])
      reaction.key: reaction.count,
  };
  @override
  Set<String> ownReactionsFor(ConversationRoute route, String messageId) => {
    for (final reaction
        in _reactions[route]?[messageId] ?? <MessageReactionRecord>[])
      if (reaction.includesMe) reaction.key,
  };
  @override
  String? sendingUnavailableReason(ConversationRoute route) {
    final conversation = _conversations[route];
    if (conversation?.canSend == false) {
      return conversation?.sendingUnavailableReason ??
          'Send this message in the original app.';
    }
    if (_accounts[route.accountId]?.platform == 'legacy') {
      return 'Reconnect this network and relink your contact to start a new conversation.';
    }
    return null;
  }

  @override
  bool isDeliveryUnconfirmed(ConversationRoute route, String messageId) =>
      _pending.any(
        (send) =>
            send.route == route &&
            send.id == messageId &&
            send.status == PendingSendStatus.unknown,
      );

  @override
  Future<void> resolveUnconfirmedSend(
    ConversationRoute route,
    String messageId, {
    required bool wasSent,
  }) => _perform(() async {
    if (!isDeliveryUnconfirmed(route, messageId)) return;
    await _draftWrites[route];
    if (wasSent) {
      await store.resolvePendingSend(messageId, clearCapturedDraft: true);
    } else {
      await store.savePendingSendStatus(messageId, PendingSendStatus.failed);
    }
    _pending = await store.loadPendingSends();
    final saved = await store.loadDraft(route);
    if (saved == null) {
      _drafts.remove(route);
    } else {
      _drafts[route] = saved;
    }
    await _updateCloseGuard();
  });

  @override
  int get notificationActivation => _notificationActivation;

  Future<void> openPendingNotification() {
    if (_loading || _closed || _isClosing) return Future.value();
    return _notificationOpening = _notificationOpening.then(
      (_) => _openPendingNotification(),
    );
  }

  Future<void> _openPendingNotification() async {
    if (_closed || _isClosing) return;
    try {
      final data = await _nativeCall('takeNotificationRoute', {});
      if (_closed || _isClosing || data is! Map) return;
      final account = data['account_id'];
      final conversation = data['conversation_id'];
      if (account is! String ||
          account.isEmpty ||
          conversation is! String ||
          conversation.isEmpty) {
        return;
      }
      final route = ConversationRoute(account, conversation);
      if (!_conversations.containsKey(route) ||
          _changingAccounts.contains(account)) {
        return;
      }
      _error = null;
      _notificationActivation++;
      selectConversation(route);
    } on MissingPluginException {
      return;
    } on PlatformException {
      _error = 'The notification could not be opened. Your conversations and drafts have been kept.';
      _publish();
    }
  }

  @override
  void selectConversation(ConversationRoute? route) {
    _selectedRoute = route;
    _publish();
    if (route != null) {
      unawaited(
        _perform(() async {
          final current = _conversations[route];
          if (preferencesFor(route).markedUnread) {
            await _changeConversationPreference(route, markedUnread: false);
          }
          if (current != null) {
            await _changeConversationPreference(
              route,
              readThrough: current.latestActivity,
            );
            await _saveChat({
              'account_id': route.accountId,
              'id': route.conversationId,
              'unread_count': 0,
            }, local: true);
          }
          final account = _accounts[route.accountId];
          if (account?.isConnected != true ||
              _changingAccounts.contains(route.accountId)) {
            return;
          }
          await _accountTask(route.accountId, () async {
            if (account!.platform == 'imessage') {
              await _imessage('imessageMarkRead', {
                'conversation_id': route.conversationId,
              });
              await _syncIMessage(route: route);
            } else if (!{'whatsapp', 'wechat'}.contains(account.platform)) {
              await engine!.request({
                'op': 'history',
                'account_id': route.accountId,
                'conversation_id': route.conversationId,
                'limit': 50,
              });
            }
          });
        }, background: true),
      );
    }
  }

  @override
  Future<void> refresh() => _refreshing ??= _perform(() async {
    for (final account in _accounts.values.toList()) {
      if (_preferences.disconnectedAccountIds.contains(account.id)) continue;
      if (account.platform == 'legacy') continue;
      if (_changingAccounts.contains(account.id)) continue;
      if (account.platform != 'imessage' && engine == null) continue;
      await _accountTask(account.id, () => _refreshAccount(account));
    }
  }, background: true).whenComplete(() => _refreshing = null);

  Future<void> _refreshAccount(AccountRecord account) async {
    try {
      if (account.platform == 'imessage') {
        await _syncIMessage();
        await _setConnection(account.id, true);
        return;
      }
      await _initializeAccount(account);
      final credentials = await _telegramCredentials(account.id);
      final result = await engine!.request({
        'op': 'connect',
        'account_id': account.id,
        ...credentials,
      });
      if (result['state'] == 'connected' || result['connected'] == true) {
        await _setConnection(account.id, true, sync: false);
      }
      if (account.isConnected || result['state'] == 'connected') {
        await _syncAccount(account);
      }
    } catch (error) {
      _networkProblems[account.id] = AccountNetworkProblem.failed;
      await _setConnection(account.id, false);
      _error = _safeError(error);
    }
  }

  Future<void> _accountTask(String accountId, Future<void> Function() work) {
    final task = work();
    final tasks = _accountWork.putIfAbsent(accountId, () => {})..add(task);
    unawaited(
      task
          .then((_) {}, onError: (Object _) {})
          .whenComplete(() => tasks.remove(task)),
    );
    return task;
  }

  Future<void> _accountWorkSettled(String accountId) => Future.wait([
    for (final task in _accountWork[accountId] ?? const <Future<void>>{})
      task.then((_) {}, onError: (Object _) {}),
  ]);

  Future<void> _initializeAccount(AccountRecord account) async {
    if (_initialized.contains(account.id)) return;
    if (engine == null) {
      throw const ConnectorException('native_library_unavailable');
    }
    final identifier = sha256.convert(utf8.encode(account.id)).toString();
    final directory = Directory(
      p.join(environment.directory.path, 'accounts', identifier),
    );
    final existing =
        await directory.exists() && await directory.list().isEmpty == false;
    final key = await environment.keyFor(
      'account.$identifier',
      existingData: existing,
    );
    await environment.privateDirectory(directory);
    await engine!.request({
      'op': 'initialize',
      'account_id': account.id,
      'platform': account.platform,
      'directory': directory.path,
      'key': base64Encode(key),
    });
    _initialized.add(account.id);
  }

  Future<Map<String, Object?>> _telegramCredentials(String accountId) async {
    if (_accounts[accountId]?.platform != 'telegram') return {};
    final value = await environment.secrets.read(
      environment.secretName('telegram.$accountId'),
    );
    return value == null
        ? {}
        : Map<String, Object?>.from(jsonDecode(value) as Map);
  }

  @override
  Future<void> beginLogin(String networkId, {bool? useQr}) => _beginLogin(
    networkId,
    useQr: useQr ?? (_login?.networkId == networkId ? _loginQrSelected : null),
    accountId: _login?.networkId == networkId ? _loginAccount : null,
    editCredentials:
        _login?.networkId == networkId && _login?.step == LoginStep.failed,
  );

  @override
  Future<void> reconnectAccount(String accountId) async {
    final account = _accounts[accountId];
    if (account == null) return;
    if (account.platform == 'legacy') {
      await _perform(() async {
        throw const AppStorageException(
          'Choose Add account to connect this network again, then relink your saved contacts.',
        );
      });
      return;
    }
    await _beginLogin(account.platform, accountId: accountId);
  }

  Future<void> _rememberDisconnected(
    String accountId,
    bool disconnected,
  ) async {
    final ids = _preferences.disconnectedAccountIds.toSet();
    if (disconnected) {
      ids.add(accountId);
    } else {
      ids.remove(accountId);
    }
    final updated = PreferencesRecord.fromJson({
      ..._preferences.toJson(),
      'disconnectedAccountIds': ids.toList(),
    });
    await environment.secrets.write(
      environment.secretName('preferences'),
      jsonEncode(updated.toJson()),
    );
    _preferences = updated;
  }

  @override
  Future<void> disconnectAccount(String accountId) =>
      _changingAccount(accountId, () async {
        final account = _accounts[accountId];
        if (account == null) return;
        if (_sending.any(
          (id) => _pending.any(
            (send) => send.id == id && send.route.accountId == accountId,
          ),
        )) {
          throw const AppStorageException(
            'Wait for the current send to finish before disconnecting.',
          );
        }
        await _rememberDisconnected(accountId, true);
        _networkProblems.remove(accountId);
        if (account.platform == 'imessage') {
          await _imessage('imessageDisconnect');
        } else if (_initialized.contains(accountId)) {
          await engine!.request({'op': 'cancel', 'account_id': accountId});
          await engine!.request({'op': 'close', 'account_id': accountId});
          _initialized.remove(accountId);
        }
        await _setConnection(accountId, false);
      });

  Future<void> _changingAccount(
    String accountId,
    Future<void> Function() operation,
  ) {
    if (!_changingAccounts.add(accountId)) return Future.value();
    return _perform(() async {
      try {
        await _accountWorkSettled(accountId);
        await operation();
      } finally {
        _changingAccounts.remove(accountId);
      }
    });
  }

  Future<void> _beginLogin(
    String networkId, {
    String? accountId,
    bool editCredentials = false,
    bool? useQr,
  }) => _perform(() async {
    final capability = _networks.where((n) => n.id == networkId).firstOrNull;
    if (capability?.available != true) {
      throw const ConnectorException('platform_unavailable');
    }
    final generation = ++_loginGeneration;
    await _cancelCurrentLogin();
    if (accountId != null) await _accountWorkSettled(accountId);
    if (generation != _loginGeneration) return;
    final id =
        accountId ?? (networkId == 'imessage' ? 'imessage-local' : _uuid.v4());
    _loginAccount = id;
    _loginPhonePairing = false;
    _loginQrSelected =
        useQr ??
        (defaultTargetPlatform != TargetPlatform.iOS &&
            defaultTargetPlatform != TargetPlatform.android);
    _login = LoginState(
      networkId: networkId,
      step: LoginStep.preparing,
      instructions: 'Preparing secure account storage…',
      busy: true,
    );
    _publish();
    final account = AccountRecord(
      id: id,
      platform: networkId,
      displayName: capability!.name,
    );
    try {
      if (networkId == 'imessage') {
        final snapshot = await _imessage('imessageSnapshot');
        if (generation != _loginGeneration) return;
        await store.saveAccount(account);
        _accounts[id] = account;
        await _applySnapshot(snapshot);
        await _setConnection(id, true);
        _login = const LoginState(
          networkId: 'imessage',
          step: LoginStep.complete,
          title: 'iMessage connected',
        );
      } else {
        if (!_accounts.containsKey(id)) _newLoginAccounts.add(id);
        final setup = Completer<void>();
        _loginStorageSetup[id] = setup.future;
        try {
          await store.saveAccount(account);
          _accounts[id] = account;
          await _initializeAccount(account);
        } finally {
          setup.complete();
          _loginStorageSetup.remove(id);
        }
        if (generation != _loginGeneration) return;
        if (networkId == 'telegram') {
          final credentials = editCredentials
              ? <String, Object?>{}
              : await _telegramCredentials(id);
          if (credentials.isNotEmpty) {
            final result = await engine!.request({
              'op': 'connect',
              'account_id': id,
              ...credentials,
            });
            if (generation != _loginGeneration) return;
            _updateLoginState(id, result['state'] as String? ?? '', result);
            if (result['state'] == 'connected') await _setConnection(id, true);
          } else {
            _login = const LoginState(
              networkId: 'telegram',
              step: LoginStep.fields,
              title: 'Connect Telegram',
              instructions: 'Create app credentials at my.telegram.org, then enter them here. They stay on this device.',
              fields: [
                LoginField(id: 'api_id', label: 'Telegram API ID'),
                LoginField(
                  id: 'api_hash',
                  label: 'Telegram API hash',
                  secret: true,
                ),
              ],
            );
          }
        } else if (networkId == 'discord' || networkId == 'linkedIn') {
          _login = LoginState(
            networkId: networkId,
            step: LoginStep.fields,
            title: 'Connect ${capability.name}',
            instructions: networkId == 'discord'
                ? 'Enter your Discord email and password, or use a session token. Only the session is saved on this device. Discord prohibits unofficial personal-account automation and may restrict your account. Captcha and security-key challenges are not supported.'
                : 'Sign in to LinkedIn. Your password is not saved. Complete any verification code or approval requested by LinkedIn.',
            fields: [
              LoginField(
                id: 'username',
                label: 'Email',
                optional: networkId == 'discord',
              ),
              LoginField(
                id: 'password',
                label: 'Password',
                secret: true,
                optional: networkId == 'discord',
              ),
              if (networkId == 'discord')
                const LoginField(
                  id: 'token',
                  label: 'Session token (optional)',
                  secret: true,
                  optional: true,
                ),
            ],
          );
        } else if (networkId == 'whatsapp' || networkId == 'wechat') {
          _login = LoginState(
            networkId: networkId,
            step: LoginStep.preparing,
            title: 'Connect ${capability.name}',
            instructions: networkId == 'wechat'
                ? 'Preparing a WeChat sign-in QR code…'
                : _loginQrSelected
                ? 'Open WhatsApp on your phone, then Linked devices → Link a device.'
                : 'Preparing phone-number linking. You will enter a code in WhatsApp on this phone.',
          );
          _publish();
          final result = await engine!.request({
            'op': 'connect',
            'account_id': id,
            if (networkId == 'wechat') 'interactive': true,
          });
          if (generation != _loginGeneration) return;
          if (result['state'] == 'connected') {
            await _setConnection(id, true);
            _updateLoginState(id, 'connected', result);
          }
        } else {
          final cookies = await _nativeCall('webLogin', {
            'platform': networkId,
          });
          if (generation != _loginGeneration) return;
          await engine!.request({
            'op': 'connect',
            'account_id': id,
            'cookies': cookies,
          });
        }
      }
    } catch (_) {
      if (generation == _loginGeneration) rethrow;
    }
    _publish();
  }, loginOperation: true);

  @override
  Future<void> submitLogin(Map<String, String> fields) => _perform(() async {
    final id = _loginAccount;
    final current = _login;
    if (id == null ||
        current == null ||
        current.busy ||
        engine == null ||
        (current.step != LoginStep.fields && current.step != LoginStep.qr)) {
      return;
    }
    final generation = _loginGeneration;
    final Map<String, Object?> command;
    if ((current.networkId == 'discord' || current.networkId == 'linkedIn') &&
        fields.containsKey('username')) {
      final username = fields['username']?.trim() ?? '';
      final password = fields['password'] ?? '';
      final token = fields['token']?.trim() ?? '';
      if (token.isEmpty && (username.isEmpty || password.isEmpty)) {
        throw const AppStorageException(
          'Enter your email and password, or a Discord session token.',
        );
      }
      command = {
        'op': 'login',
        if (token.isNotEmpty) 'token': token,
        if (token.isEmpty) ...{'username': username, 'password': password},
      };
    } else if (current.networkId == 'linkedIn' && current.fields.isEmpty) {
      command = {'op': 'login_wait'};
    } else if (fields.containsKey('api_id')) {
      final apiId = int.tryParse(fields['api_id']!.trim());
      final apiHash = fields['api_hash']?.trim() ?? '';
      if (apiId == null ||
          apiId <= 0 ||
          !RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(apiHash)) {
        throw const AppStorageException(
          'Enter a valid Telegram API ID and 32-character API hash.',
        );
      }
      final credentials = {'api_id': apiId, 'api_hash': apiHash};
      await environment.secrets.write(
        environment.secretName('telegram.$id'),
        jsonEncode(credentials),
      );
      command = {'op': 'connect', ...credentials};
    } else if (fields.containsKey('phone')) {
      var phone = fields['phone']!.trim();
      if (current.networkId == 'whatsapp') {
        final country = fields['country_code']?.trim();
        if (country != null) {
          if (!RegExp(r'^\+?[1-9][0-9]{0,2}$').hasMatch(country) ||
              phone.startsWith('+')) {
            throw const AppStorageException(
              'Enter the country code separately from your phone number.',
            );
          }
          phone = '$country$phone';
        }
        phone = phone
            .replaceAll(RegExp(r'[ ().\-\u00a0]'), '')
            .replaceFirst(RegExp(r'^\+'), '');
        if (!RegExp(r'^[1-9][0-9]{6,14}$').hasMatch(phone)) {
          throw const AppStorageException(
            'Enter a valid phone number including its country code.',
          );
        }
      }
      if (current.networkId == 'whatsapp') _loginPhonePairing = true;
      command = {
        'op': current.networkId == 'whatsapp' ? 'pair_phone' : 'login_phone',
        'phone': phone,
      };
    } else if (fields.containsKey('code')) {
      command = {'op': 'login_code', 'code': fields['code']!.trim()};
    } else {
      command = {'op': 'login_password', 'password': fields['password'] ?? ''};
    }
    if (generation != _loginGeneration) return;
    _login = LoginState(
      networkId: current.networkId,
      step: current.step,
      title: current.title,
      instructions: current.instructions,
      qrData: current.qrData,
      qrImage: current.qrImage,
      pairingCode: current.pairingCode,
      expiresAt: current.expiresAt,
      fields: current.fields,
      busy: true,
    );
    _publish();
    final Map<String, Object?> result;
    try {
      result = await engine!.request({...command, 'account_id': id});
    } catch (_) {
      if (generation != _loginGeneration ||
          _login?.step == LoginStep.complete) {
        return;
      }
      rethrow;
    }
    if (generation != _loginGeneration) return;
    if (_login?.step == LoginStep.complete) return;
    if (current.networkId == 'whatsapp' && result['code'] is String) {
      final expiresAt = result['expires_at'] is num
          ? _timestamp(result['expires_at'])
          : null;
      _login = LoginState(
        networkId: 'whatsapp',
        step: LoginStep.pairingCode,
        title: 'Link WhatsApp',
        pairingCode: result['code'] as String,
        expiresAt: expiresAt,
        instructions: 'Copy this code, then switch to WhatsApp on this phone. Open Settings → Linked devices → Link a device → Link with phone number instead and enter the code. Return to Inbox+ after approving. This is a device-linking code, not an SMS code.',
      );
      if (expiresAt != null) _expireLoginAt(expiresAt);
      _publish();
      return;
    }
    if (result['state'] == 'connected') await _setConnection(id, true);
    _updateLoginState(id, result['state'] as String? ?? '', result);
  }, loginOperation: true);

  @override
  Future<void> exportLoginQr(Uint8List image, {bool share = false}) => _perform(
    () async {
      if (_login?.step != LoginStep.qr) return;
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await _nativeCall(share ? 'shareLoginQr' : 'saveLoginQr', {
          'image': image,
        });
      } else {
        final jpeg = image.length >= 2 && image[0] == 0xff && image[1] == 0xd8;
        await _prepareFilePicker();
        await FilePicker.saveFile(
          fileName: 'Inbox+ sign-in QR.${jpeg ? 'jpg' : 'png'}',
          dialogTitle: 'Save sign-in QR code',
          mimeType: jpeg ? 'image/jpeg' : 'image/png',
          bytes: image,
        );
      }
    },
  );

  @override
  Future<void> resumeLogin() => _perform(() async {
    final generation = _loginGeneration;
    final status = defaultTargetPlatform == TargetPlatform.iOS
        ? await _optionalNative('loginBackgroundStatus')
        : const <String, Object?>{};
    await _eventQueue;
    if (generation != _loginGeneration) return;
    final current = _login;
    if (current == null ||
        current.step == LoginStep.complete ||
        current.step == LoginStep.failed) {
      return;
    }
    if (status['expired'] == true ||
        (current.expiresAt != null && !_now().isBefore(current.expiresAt!))) {
      _expireLogin();
    }
  });

  void _expireLoginAt(DateTime expiresAt) {
    _loginExpiryTimer?.cancel();
    final generation = _loginGeneration;
    _loginExpiryTimer = Timer(expiresAt.difference(_now()), () {
      if (generation == _loginGeneration) _expireLogin();
    });
  }

  void _expireLogin() {
    final current = _login;
    if (current == null ||
        current.step == LoginStep.complete ||
        current.step == LoginStep.failed) {
      return;
    }
    _loginExpiryTimer?.cancel();
    _login = LoginState(
      networkId: current.networkId,
      step: LoginStep.failed,
      title: 'Get a fresh sign-in code',
      error: 'This sign-in attempt expired. Try again to get a fresh code.',
    );
    _publish();
  }

  @override
  Future<void> cancelLogin() {
    _loginGeneration++;
    return _cancelCurrentLogin();
  }

  Future<void> _cancelCurrentLogin() async {
    _loginExpiryTimer?.cancel();
    final id = _loginAccount;
    _loginAccount = null;
    _loginPhonePairing = false;
    _login = null;
    await _optionalNative('cancelWebLogin');
    await _loginStorageSetup[id];
    if (id != null &&
        _accounts[id]?.isConnected != true &&
        _initialized.contains(id)) {
      await _perform(() async {
        await engine?.request({'op': 'cancel', 'account_id': id});
        final result = await engine?.request({'op': 'close', 'account_id': id});
        _initialized.remove(id);
        await _eventQueue;
        if (result?['has_session'] == false) {
          await _discardNewLogin(id);
        } else {
          _newLoginAccounts.remove(id);
        }
      });
    } else if (id != null && !_initialized.contains(id)) {
      await _perform(() => _discardNewLogin(id));
    }
    _publish();
  }

  Future<void> _discardNewLogin(String id) async {
    if (!_newLoginAccounts.contains(id)) return;
    await _waitForDrafts();
    if (_accounts[id]?.isConnected == true ||
        _conversations.keys.any((route) => route.accountId == id) ||
        _drafts.values.any(
          (draft) =>
              draft.route.accountId == id &&
              (draft.body.isNotEmpty || draft.attachments.isNotEmpty),
        ) ||
        _pending.any((send) => send.route.accountId == id)) {
      _newLoginAccounts.remove(id);
      return;
    }
    await store.removeAccount(id);
    final identifier = sha256.convert(utf8.encode(id)).toString();
    final directory = Directory(
      p.join(environment.directory.path, 'accounts', identifier),
    );
    if (await FileSystemEntity.isLink(directory.path)) {
      throw const AppStorageException(
        'The account storage could not be removed safely.',
      );
    }
    if (await directory.exists()) await directory.delete(recursive: true);
    await environment.secrets.delete(
      environment.secretName('account.$identifier'),
    );
    await environment.secrets.delete(environment.secretName('telegram.$id'));
    _accounts.remove(id);
    _newLoginAccounts.remove(id);
  }

  void _updateLoginState(String id, String state, Map<String, Object?> data) {
    if (_loginAccount != id) return;
    final network = _accounts[id]!.platform;
    switch (state) {
      case 'connected':
      case 'success':
        _loginExpiryTimer?.cancel();
        _login = LoginState(
          networkId: network,
          step: LoginStep.complete,
          title: 'Account connected',
        );
      case 'phone':
        _login = LoginState(
          networkId: network,
          step: LoginStep.fields,
          title: 'Your phone number',
          fields: const [
            LoginField(
              id: 'phone',
              label: 'Phone number',
              hint: '+1 202 555 0123',
              phone: true,
            ),
          ],
        );
      case 'code':
        _login = LoginState(
          networkId: network,
          step: LoginStep.fields,
          title: 'Verification code',
          instructions: network == 'discord'
              ? 'Enter your authenticator or backup code.'
              : network == 'linkedIn'
              ? 'Enter the verification code LinkedIn requested.'
              : 'Enter the code Telegram sent you.',
          fields: const [LoginField(id: 'code', label: 'Code')],
        );
      case 'approval':
        _login = LoginState(
          networkId: network,
          step: LoginStep.fields,
          title: 'Approve LinkedIn sign-in',
          instructions: 'Approve this sign-in in your LinkedIn app, then select Continue.',
        );
      case 'password':
        _login = LoginState(
          networkId: network,
          step: LoginStep.fields,
          title: 'Telegram password',
          fields: const [
            LoginField(
              id: 'password',
              label: 'Two-step verification password',
              secret: true,
            ),
          ],
        );
      case 'timeout':
      case 'error':
      case 'logged_out':
      case 'needs_login':
        _loginExpiryTimer?.cancel();
        _login = LoginState(
          networkId: network,
          step: LoginStep.failed,
          title: 'Account needs sign-in',
          error: state == 'timeout'
              ? 'This sign-in code expired. Try again to get a fresh code.'
              : 'Sign-in did not complete. Try again.',
        );
      default:
        final current = _login;
        if (current != null) {
          _login = LoginState(
            networkId: network,
            step: current.step,
            title: current.title,
            instructions: current.instructions,
            fields: current.fields,
            qrData: current.qrData,
            qrImage: current.qrImage,
            pairingCode: current.pairingCode,
            expiresAt: current.expiresAt,
            busy: current.busy,
          );
        }
    }
    _publish();
  }

  @override
  void updateDraft(ConversationRoute route, String text) {
    final current = _drafts[route];
    _editDraft(
      route,
      text,
      current?.attachments ?? [],
      current?.replyToMessageId,
    );
  }

  void _editDraft(
    ConversationRoute route,
    String body,
    List<AttachmentRecord> attachments,
    String? reply,
  ) {
    if ((_deletingAccounts.contains(route.accountId) &&
            !_stagingAttachments.contains(route)) ||
        !_conversations.containsKey(route)) {
      return;
    }
    final draft = DraftRecord(
      route: route,
      body: body,
      revision: (_drafts[route]?.revision ?? 0) + 1,
      attachments: attachments,
      replyToMessageId: reply,
    );
    _drafts[route] = draft;
    final previous = _draftWrites[route] ?? Future.value();
    final write = previous.then((_) async {
      final saved = await store.saveDraft(
        route,
        body,
        attachments: attachments,
        replyToMessageId: reply,
      );
      if (identical(_drafts[route], draft)) _drafts[route] = saved;
    });
    _draftWrites[route] = write;
    unawaited(
      write.then((_) => _updateCloseGuard()).catchError((Object error) {
        _error = _safeError(error);
        _publish();
      }),
    );
    _publish();
  }

  @override
  Future<void> stageAttachments(ConversationRoute route) => _perform(() async {
    if (_deletingAccounts.contains(route.accountId) ||
        !_conversations.containsKey(route) ||
        !_stagingAttachments.add(route)) {
      return;
    }
    try {
      final capability = _capabilityFor(route);
      if (capability?.canAttach != true) {
        throw const AppStorageException(
          'This account cannot send attachments.',
        );
      }
      if (_drafts[route]?.attachments.isNotEmpty == true) {
        throw const AppStorageException(
          'Send or remove the current attachment before adding another.',
        );
      }
      await _prepareFilePicker();
      final source = await FilePicker.pickFile();
      if (source?.path == null) return;
      final file = File(source!.path!);
      final limit = _attachmentLimit(route);
      if (await file.length() > limit) {
        throw AppStorageException(
          'Attachments must be ${limit ~/ (1024 * 1024)} MiB or smaller.',
        );
      }
      final id = _uuid.v4();
      final target = File(
        p.join(
          environment.directory.path,
          'staging',
          '$id${_safeExtension(source.name)}',
        ),
      );
      await environment.writePrivate(target, await file.readAsBytes());
      final mime = _mimeFor(source.name);
      final attachment = AttachmentRecord(
        id: id,
        kind: mime.split('/').first,
        fileName: p.basename(source.name),
        mimeType: mime,
        byteCount: await target.length(),
        localPath: target.path,
      );
      final draft = _drafts[route];
      _editDraft(route, draft?.body ?? '', [
        attachment,
      ], draft?.replyToMessageId);
      await _draftWrites[route];
    } finally {
      _stagingAttachments.remove(route);
    }
  });

  @override
  void removeDraftAttachment(ConversationRoute route, String attachmentId) {
    final draft = _drafts[route];
    if (draft == null) return;
    _editDraft(
      route,
      draft.body,
      draft.attachments.where((a) => a.id != attachmentId).toList(),
      draft.replyToMessageId,
    );
  }

  @override
  void setReplyTo(ConversationRoute route, String? messageId) {
    final draft = _drafts[route];
    _editDraft(route, draft?.body ?? '', draft?.attachments ?? [], messageId);
  }

  @override
  Future<void> sendDraft(ConversationRoute route) => _perform(() async {
    if (_deletingAccounts.contains(route.accountId)) return;
    final unavailable = sendingUnavailableReason(route);
    if (unavailable != null) throw AppStorageException(unavailable);
    if (!_enqueueing.add(route)) return;
    try {
      await _draftWrites[route];
      final draft = await store.loadDraft(route);
      if (draft == null ||
          (draft.body.trim().isEmpty && draft.attachments.isEmpty)) {
        return;
      }
      if (_pending.any(
        (s) => s.route == route && s.draftRevision == draft.revision,
      )) {
        return;
      }
      if (draft.attachments.length > 1) {
        throw const AppStorageException(
          'Send one attachment at a time. Your draft has been kept.',
        );
      }
      if (_accounts[route.accountId]?.platform == 'instagram' &&
          draft.attachments.isNotEmpty &&
          draft.body.trim().isNotEmpty) {
        throw const AppStorageException(
          'Send the Instagram attachment and its text as separate messages. Your draft has been kept.',
        );
      }
      if (draft.attachments.isNotEmpty) {
        final attachment = draft.attachments.single;
        if (_accounts[route.accountId]?.platform == 'whatsapp' &&
            attachment.mimeType?.startsWith('audio/') == true &&
            draft.body.trim().isNotEmpty) {
          throw const AppStorageException(
            'Send this audio file and its text as separate messages. Your draft has been kept.',
          );
        }
        if (_accounts[route.accountId]?.platform == 'instagram' &&
            !{
              'image',
              'video',
              'audio',
            }.contains(attachment.mimeType?.split('/').first)) {
          throw const AppStorageException(
            'Instagram supports image, video and audio attachments. Your draft has been kept.',
          );
        }
      }
      final send = await store.enqueueDraft(route, sendId: _uuid.v4());
      _pending = await store.loadPendingSends();
      await _updateCloseGuard();
      _publish();
      if (_accounts[route.accountId]?.isConnected == true) {
        await _send(send);
      }
    } finally {
      _enqueueing.remove(route);
    }
  });

  Future<void> _send(PendingSendRecord send) async {
    if (!_sending.add(send.id)) return;
    try {
      final account = _accounts[send.route.accountId];
      if (account?.isConnected != true) return;
      final unavailable = sendingUnavailableReason(send.route);
      if (unavailable != null) {
        await store.savePendingSendStatus(send.id, PendingSendStatus.failed);
        _pending = await store.loadPendingSends();
        throw AppStorageException(unavailable);
      }
      Map<String, Object?> attachmentCommand = {};
      final replyId = send.replyToMessageId;
      final reply = replyId == null
          ? null
          : await store.loadMessage(send.route, replyId);
      if (replyId != null &&
          (reply == null ||
              !networks.any(
                (network) =>
                    network.id == account?.platform && network.canReply,
              ))) {
        await store.savePendingSendStatus(send.id, PendingSendStatus.failed);
        _pending = await store.loadPendingSends();
        throw const AppStorageException(
          'The reply target is unavailable. Your draft has been kept.',
        );
      }
      if (send.attachments.isNotEmpty) {
        final attachment = send.attachments.single;
        final path = attachment.localPath;
        if (path == null || !p.isWithin(environment.directory.path, path)) {
          throw const AppStorageException(
            'The staged attachment is unavailable. Your draft has been kept.',
          );
        }
        final file = File(path);
        if (await file.length() > _attachmentLimit(send.route)) {
          throw const AppStorageException(
            'The attachment exceeds the size limit.',
          );
        }
        attachmentCommand = {
          'bytes': base64Encode(await file.readAsBytes()),
          'name': attachment.fileName ?? 'Attachment',
          'mime_type': attachment.mimeType ?? 'application/octet-stream',
        };
      }
      await store.savePendingSendStatus(send.id, PendingSendStatus.sending);
      _pending = await store.loadPendingSends();
      _publish();
      Map<String, Object?> result;
      try {
        if (account!.platform == 'imessage') {
          result = Map<String, Object?>.from(
            await _imessage('imessageSend', {
              'conversation_id': send.route.conversationId,
              'body': send.body,
            }) as Map,
          );
        } else {
          result = await engine!.request({
            'op': send.attachments.isEmpty ? 'send_text' : 'send_attachment',
            'account_id': account.id,
            'conversation_id': send.route.conversationId,
            'id': send.id,
            'body': send.body,
            if (reply != null) ...{
              'reply_to_message_id': reply.id,
              'reply_to_sender_id': reply.senderId,
              'reply_to_body': reply.body,
              'reply_to_outgoing': reply.isOutgoing,
            },
            ...attachmentCommand,
          });
        }
        if (result['id'] is! String ||
            (result['id'] as String).isEmpty ||
            result['delivery_state'] == 'pending') {
          throw const ConnectorException('outcome_unknown');
        }
      } catch (_) {
        await store.savePendingSendStatus(send.id, PendingSendStatus.unknown);
        _pending = await store.loadPendingSends();
        throw const AppStorageException(
          'Delivery could not be confirmed. Check the conversation in the original app before sending again. Your draft has been kept.',
        );
      }
      final message = MessageRecord(
        id: result['id'] as String,
        route: send.route,
        body: send.body,
        timestamp: _timestamp(result['timestamp']),
        isOutgoing: true,
        replyToMessageId: send.replyToMessageId,
        attachments: send.attachments,
      );
      await store.completeSend(send.id, message);
      final conversation = _conversations[send.route];
      if (conversation != null &&
          message.timestamp.isAfter(conversation.latestActivity)) {
        _conversations[send.route] = conversation.copyWith(
          latestActivity: message.timestamp,
        );
      }
      _pending = await store.loadPendingSends();
      _messages[send.route] = await store.loadRecentMessages(send.route);
      final current = await store.loadDraft(send.route);
      if (!_draftWrites.containsKey(send.route) ||
          identical(_drafts[send.route], current) ||
          _drafts[send.route]?.revision == send.draftRevision) {
        if (current == null) {
          _drafts.remove(send.route);
        } else {
          _drafts[send.route] = current;
        }
      }
      await _updateCloseGuard();
      _publish();
    } finally {
      _sending.remove(send.id);
    }
  }

  @override
  Future<void> retryMessage(ConversationRoute route, String messageId) =>
      _perform(() async {
        final send = _pending
            .where((s) => s.id == messageId && s.route == route)
            .firstOrNull;
        if (send == null) return;
        if (send.status == PendingSendStatus.unknown ||
            send.status == PendingSendStatus.sending) {
          throw const AppStorageException(
            'The earlier delivery is unconfirmed. Check the original app before composing a new message; automatic retry could send it twice.',
          );
        }
        if (_accounts[route.accountId]?.isConnected != true) {
          throw const AppStorageException(
            'Reconnect this account to send the queued message.',
          );
        }
        await _send(send);
      });

  @override
  Future<LocalRecipientSnapshot> recipientContacts(String accountId) async {
    final account = _accounts[accountId];
    if (defaultTargetPlatform != TargetPlatform.macOS ||
        account?.platform != 'imessage' ||
        account?.isConnected != true) {
      return const LocalRecipientSnapshot.available();
    }
    try {
      final response = await _nativeCall('imessageRecipientContacts', {});
      final data = response as Map;
      switch (data['status']) {
        case 'available':
          return LocalRecipientSnapshot.available(
            List.unmodifiable([
              for (final recipient in data['recipients'] as List)
                LocalRecipient(
                  name: recipient['name'] as String,
                  address: recipient['address'] as String,
                  searchText: recipient['search_text'] as String? ?? '',
                ),
            ]),
          );
        case 'access_unavailable':
          return const LocalRecipientSnapshot.accessUnavailable();
        default:
          return const LocalRecipientSnapshot.failed();
      }
    } catch (_) {
      return const LocalRecipientSnapshot.failed();
    }
  }

  @override
  Future<void> startConversation(String accountId, String recipient) =>
      _perform(() async {
        final account = _accounts[accountId];
        if (account?.isConnected != true) {
          throw const AppStorageException('Reconnect this account first.');
        }
        if (_networks
                .where((n) => n.id == account!.platform)
                .firstOrNull
                ?.canStartConversation !=
            true) {
          throw const AppStorageException(
            'Start this conversation in the original app, then refresh Inbox+.',
          );
        }
        final Object? response;
        if (account!.platform == 'imessage') {
          response = await _imessage('imessageStartConversation', {
            'recipient': recipient.trim(),
          });
        } else {
          response = await engine!.request({
            'op': 'start_conversation',
            'account_id': accountId,
            'recipient': recipient.trim(),
          });
        }
        final data = Map<String, Object?>.from(response as Map);
        await _saveChat({...data, 'account_id': accountId});
        final id = data['id'] as String?;
        if (id != null) selectConversation(ConversationRoute(accountId, id));
      });

  @override
  Future<void> react(ConversationRoute route, String messageId, String emoji) =>
      _perform(() async {
        final message = await store.loadMessage(route, messageId);
        final account = _accounts[route.accountId];
        if (engine == null ||
            account?.isConnected != true ||
            message?.acceptsResponses != true ||
            !networks.any(
              (network) => network.id == account?.platform && network.canReact,
            ) ||
            emoji.isEmpty ||
            emoji.runes.length > 64) {
          throw const AppStorageException(
            'Reactions are unavailable for this message.',
          );
        }
        final operation = (route, messageId);
        if (!_reacting.add(operation)) return;
        try {
          final own = ownReactionsFor(route, messageId);
          final result = await engine!.request({
            'op': 'react',
            'account_id': route.accountId,
            'conversation_id': route.conversationId,
            'message_id': messageId,
            'message_sender_id': message!.senderId,
            'message_outgoing': message.isOutgoing,
            'emoji': own.contains(emoji) ? '' : emoji,
            'previous_emoji': own.firstOrNull ?? '',
          });
          if (result['applied'] != true) {
            throw const ConnectorException('reaction_unconfirmed');
          }
          if (result['type'] == 'reaction' || result['type'] == 'reactions') {
            await _handleEvent({
              ...result,
              'account_id': route.accountId,
              'conversation_id': route.conversationId,
              'id': messageId,
            });
          }
        } finally {
          _reacting.remove(operation);
        }
      });

  @override
  Future<void> downloadAttachment(
    ConversationRoute route,
    String messageId,
    String attachmentId,
  ) => _perform(() => _downloadAttachment(route, messageId, attachmentId));

  @override
  AttachmentLoadState? attachmentLoadState(
    ConversationRoute route,
    String attachmentId,
  ) => _inlineImageLoads[(route, attachmentId)];

  @override
  Future<void> loadInlineImage(
    ConversationRoute route,
    String messageId,
    String attachmentId,
  ) {
    final key = (route, attachmentId);
    if (_closed ||
        _isClosing ||
        _inlineImageLoads[key] == AttachmentLoadState.loading) {
      return Future.value();
    }
    _inlineImageLoads[key] = AttachmentLoadState.loading;
    _publish();
    final future = () async {
      try {
        await _downloadAttachment(route, messageId, attachmentId);
        _inlineImageLoads.remove(key);
      } on _AttachmentTooLarge {
        _inlineImageLoads[key] = AttachmentLoadState.tooLarge;
      } catch (_) {
        _inlineImageLoads[key] = AttachmentLoadState.failed;
      }
      _publish();
    }();
    _operations.add(future);
    unawaited(future.whenComplete(() => _operations.remove(future)));
    return future;
  }

  // Previews are fetched one at a time without surfacing errors; a missing preview leaves the plain
  // link card in place.
  void _fetchPreview(
    ConversationRoute route,
    String messageId,
    String attachmentId,
  ) {
    final future = _previewDownloads.then((_) async {
      if (_closed || _isClosing) return;
      try {
        await _downloadAttachment(route, messageId, attachmentId);
      } catch (_) {}
    });
    _previewDownloads = future;
    _operations.add(future);
    unawaited(future.whenComplete(() => _operations.remove(future)));
  }

  Future<void> _downloadAttachment(
    ConversationRoute route,
    String messageId,
    String attachmentId,
  ) async {
    final message = await store.loadMessage(route, messageId);
    final attachment = message?.attachments
        .where((a) => a.id == attachmentId)
        .firstOrNull;
    if (message == null ||
        attachment == null ||
        !attachment.isDownloadable ||
        (attachment.localPath != null &&
            await File(attachment.localPath!).exists())) {
      return;
    }
    if ((attachment.byteCount ?? 0) > _maxAttachmentBytes) {
      throw const _AttachmentTooLarge();
    }
    final result = await engine!.request({
      'op': 'download_attachment',
      'account_id': route.accountId,
      'id': attachmentId,
    });
    final bytes = base64Decode(result['bytes'] as String);
    if (bytes.length > _maxAttachmentBytes) {
      throw const _AttachmentTooLarge();
    }
    final file = File(
      p.join(
        environment.directory.path,
        'media',
        // A Reel's name is its author, not a file name.
        '${_uuid.v4()}${attachment.kind == 'reel' ? '.mp4' : _safeExtension(attachment.fileName ?? '')}',
      ),
    );
    await environment.writePrivate(file, bytes);
    final downloaded = AttachmentRecord(
      id: attachment.id,
      kind: attachment.kind,
      fileName: attachment.fileName,
      mimeType: attachment.mimeType,
      byteCount: bytes.length,
      localPath: file.path,
      deepLink: attachment.deepLink,
      isDownloadable: attachment.isDownloadable,
    );
    final current = await store.loadMessage(route, messageId) ?? message;
    final updated = _copyMessage(
      current,
      attachments: [
        for (final a in current.attachments)
          if (a.id == attachmentId) downloaded else a,
      ],
    );
    await store.saveMessage(updated);
    _messages[route] = await store.loadRecentMessages(route);
    _scheduleStatistics();
    _publish();
  }

  @override
  Future<void> saveAttachment(
    ConversationRoute route,
    String messageId,
    String attachmentId,
  ) => _perform(() async {
    final message = await store.loadMessage(route, messageId);
    final attachment = message?.attachments
        .where((item) => item.id == attachmentId)
        .firstOrNull;
    final path = attachment?.localPath;
    if (path == null || !await File(path).exists()) {
      throw const AppStorageException(
        'This attachment is no longer available on this device.',
      );
    }
    final source = File(await File(path).resolveSymbolicLinks());
    if (!p.isWithin(environment.directory.path, source.path)) {
      throw const AppStorageException(
        'This file is outside the private attachment store.',
      );
    }
    if (await source.length() > _maxAttachmentBytes) {
      throw const AppStorageException('The attachment exceeds the size limit.');
    }
    await _prepareFilePicker();
    await FilePicker.saveFile(
      fileName: _attachmentFileName(attachment!),
      bytes: await source.readAsBytes(),
      mimeType: attachment.mimeType ?? 'application/octet-stream',
      dialogTitle: 'Save Attachment',
    );
  });

  @override
  Future<void> openAttachment(String localPath) => _perform(() async {
    final file = File(localPath);
    if (!await file.exists()) {
      throw const AppStorageException(
        'This attachment is no longer available on this device.',
      );
    }
    final resolved = await file.resolveSymbolicLinks();
    if (!p.isWithin(environment.directory.path, resolved)) {
      throw const AppStorageException(
        'This file is outside the private attachment store.',
      );
    }
    if (Platform.isAndroid || Platform.isIOS) {
      await _nativeCall('openFile', {'path': resolved});
    } else if (!await launchUrl(
      Uri.file(localPath),
      mode: LaunchMode.externalApplication,
    )) {
      throw const AppStorageException(
        'No application could open this attachment.',
      );
    }
  });

  @override
  Future<void> openAttachmentLink(
    ConversationRoute route,
    String messageId,
    String attachmentId,
  ) => _perform(() async {
    final message = await store.loadMessage(route, messageId);
    final attachment = message?.attachments
        .where((a) => a.id == attachmentId)
        .firstOrNull;
    final uri = Uri.tryParse(attachment?.deepLink ?? '');
    final platform = _accounts[route.accountId]?.platform;
    final domain = platform == 'instagram'
        ? 'instagram.com'
        : platform == 'messenger'
        ? 'facebook.com'
        : null;
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        domain == null ||
        (uri.host != domain && !uri.host.endsWith('.$domain'))) {
      throw const AppStorageException(
        'This attachment link cannot be opened safely.',
      );
    }
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw const AppStorageException(
        'The original app could not open this attachment.',
      );
    }
  });

  @override
  Future<void> setFavorite(ConversationRoute route, bool favorite) =>
      _perform(() => _changeConversationPreference(route, favorite: favorite));
  @override
  Future<void> setMuted(
    ConversationRoute route,
    bool muted, {
    DateTime? until,
  }) => _perform(
    () => _changeConversationPreference(route, muted: muted, mutedUntil: until),
  );
  @override
  Future<void> setHidden(ConversationRoute route, bool hidden) =>
      _perform(() => _changeConversationPreference(route, hidden: hidden));
  @override
  Future<void> setUnread(ConversationRoute route, bool unread) =>
      _perform(() async {
        await _changeConversationPreference(route, markedUnread: unread);
        if (!unread) {
          await _changeConversationPreference(
            route,
            readThrough: _conversations[route]?.latestActivity,
          );
          await _saveChat({
            'account_id': route.accountId,
            'id': route.conversationId,
            'unread_count': 0,
          }, local: true);
          if (_accounts[route.accountId]?.platform == 'imessage') {
            await _imessage('imessageMarkRead', {
              'conversation_id': route.conversationId,
            });
          }
        }
      });
  Future<void> _changeConversationPreference(
    ConversationRoute route, {
    bool? favorite,
    bool? muted,
    bool? hidden,
    bool? markedUnread,
    DateTime? mutedUntil,
    DateTime? readThrough,
  }) async {
    final old = preferencesFor(route);
    final value = ConversationPreferencesRecord(
      route: route,
      isFavorite: favorite ?? old.isFavorite,
      markedUnread: markedUnread ?? old.markedUnread,
      isMuted: muted ?? old.isMuted,
      mutedUntil: muted == null ? old.mutedUntil : mutedUntil,
      readThrough: readThrough ?? old.readThrough,
      hiddenAt: hidden == null
          ? old.hiddenAt
          : hidden
          ? _conversations[route]?.latestActivity ?? DateTime.now()
          : null,
    );
    await store.saveConversationPreferences(value);
    _conversationPreferences[route] = value;
  }

  @override
  Future<void> saveContact(ContactRecord contact) => _perform(() async {
    await store.saveContact(contact);
    _contacts = await store.loadContacts();
  });
  @override
  Future<String?> acceptContactSuggestion(ContactSuggestion suggestion) async {
    if (!_acceptingContactSuggestions.add(suggestion.id)) return null;
    String? acceptedId;
    try {
      await _perform(() async {
        final current = contactSuggestions
            .where(
              (item) =>
                  item.id == suggestion.id &&
                  item.displayName == suggestion.displayName,
            )
            .firstOrNull;
        if (current == null) return;
        final id = _uuid.v4();
        await store.saveContact(
          ContactRecord(
            id: id,
            displayName: current.displayName,
            identities: current.identities,
          ),
        );
        _contacts = await store.loadContacts();
        acceptedId = id;
      });
      return acceptedId;
    } finally {
      _acceptingContactSuggestions.remove(suggestion.id);
    }
  }

  @override
  Future<void> linkIdentity(IdentityLink identity, ContactRecord person) =>
      _perform(() async {
        await store.moveIdentityToContact(identity, person);
        _contacts = await store.loadContacts();
      });
  @override
  Future<void> removeContact(String contactId) => _perform(() async {
    await store.removeContact(contactId);
    _contacts = await store.loadContacts();
  });

  @override
  Future<void> removeAccount(
    String accountId,
  ) => _changingAccount(accountId, () async {
    final account = _accounts[accountId];
    if (account == null || account.platform == 'imessage') return;
    if (_hasUnfinishedAccountWork(accountId)) {
      throw const AppStorageException(
        'This account has a draft or pending message. Keep it connected until that work is resolved.',
      );
    }
    await _waitForDrafts();
    final signedOut = await _signOut(account);
    if (_initialized.contains(accountId)) {
      await engine!.request({'op': 'cancel', 'account_id': accountId});
      await engine!.request({'op': 'close', 'account_id': accountId});
      _initialized.remove(accountId);
    }
    await _setConnection(accountId, false);
    _deletingAccounts.add(accountId);
    try {
      await _waitForDrafts();
      if (_hasUnfinishedAccountWork(accountId)) {
        throw const AppStorageException(
          'This account has a draft or pending message. Its saved work has been kept. Reconnect it to finish that work.',
        );
      }
      await _deleteAccount(accountId);
    } finally {
      _deletingAccounts.remove(accountId);
    }
    if (!signedOut) {
      final network = _networkName(account.platform);
      throw AppStorageException(
        'Inbox+ could not sign out of $network. Its saved login is deleted, but $network may still list Inbox+ as a signed-in device until you remove it there.',
      );
    }
  });

  bool _hasUnfinishedAccountWork(String accountId) =>
      _pending.any((s) => s.route.accountId == accountId) ||
      _enqueueing.any((route) => route.accountId == accountId) ||
      _stagingAttachments.any((route) => route.accountId == accountId) ||
      _drafts.values.any(
        (d) =>
            d.route.accountId == accountId &&
            (d.body.isNotEmpty || d.attachments.isNotEmpty),
      );

  Future<bool> _signOut(AccountRecord account) async {
    if (account.platform == 'legacy') return true;
    if (engine == null) return false;
    const limit = Duration(seconds: 30);
    try {
      await _initializeAccount(account);
      if (!account.isConnected) {
        await engine!
            .request({
              'op': 'connect',
              'account_id': account.id,
              ...await _telegramCredentials(account.id),
            })
            .timeout(limit);
      }
      final result = await engine!
          .request({'op': 'logout', 'account_id': account.id})
          .timeout(limit);
      return result['remote_session_revoked'] == true;
    } catch (_) {
      return false;
    }
  }

  String _networkName(String platform) =>
      _networks.where((n) => n.id == platform).firstOrNull?.name ?? platform;

  Future<void> _deleteAccount(String accountId) async {
    final downloads = await store.removeAccount(
      accountId,
      mediaDirectory: p.join(environment.directory.path, 'media'),
    );
    for (final path in downloads) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
    if (_preferences.disconnectedAccountIds.contains(accountId)) {
      await _rememberDisconnected(accountId, false);
    }
    _networkProblems.remove(accountId);
    _contacts = await store.loadContacts();
    _accounts.remove(accountId);
    _conversations.removeWhere((route, _) => route.accountId == accountId);
    _messages.removeWhere((route, _) => route.accountId == accountId);
    _reactions.removeWhere((route, _) => route.accountId == accountId);
    _drafts.removeWhere((route, _) => route.accountId == accountId);
    if (_selectedRoute?.accountId == accountId) _selectedRoute = null;
    final identifier = sha256.convert(utf8.encode(accountId)).toString();
    final directory = Directory(
      p.join(environment.directory.path, 'accounts', identifier),
    );
    if (await directory.exists()) await directory.delete(recursive: true);
    await environment.secrets.delete(
      environment.secretName('account.$identifier'),
    );
    await environment.secrets.delete(
      environment.secretName('telegram.$accountId'),
    );
    await _reloadStatistics();
  }

  @override
  Future<void> openLoginItemsSettings() =>
      _perform(() => _nativeCall('openLoginItemsSettings', {}));

  @override
  Future<void> refreshNotificationStatus() async {
    if (_closed || _isClosing) return;
    final generation = ++_notificationStatusGeneration;
    SystemNotificationStatus status;
    try {
      status = SystemNotificationStatus.fromNative(
        await _nativeCall('notificationStatus', {}),
      );
    } on MissingPluginException {
      status = const SystemNotificationStatus();
    } on PlatformException {
      status = const SystemNotificationStatus();
    }
    if (_closed || _isClosing || generation != _notificationStatusGeneration) {
      return;
    }
    _notificationStatus = status;
    _publish();
  }

  @override
  Future<void> requestNotificationPermission() => _perform(() async {
    try {
      await _nativeCall('requestNotificationPermission', {});
    } finally {
      await refreshNotificationStatus();
    }
  });

  @override
  Future<void> openNotificationSettings() => _perform(() async {
    if (_notificationStatus.canOpenSettings) {
      await _nativeCall('openNotificationSettings', {});
    }
  });

  @override
  Future<void> setPreference(String key, Object value) => _perform(() async {
    final values = _preferences.toJson();
    switch (key) {
      case 'launchAtLogin':
        if (value is! bool) return;
        final result = await _nativeCall('setLaunchAtLogin', {
          'enabled': value,
        });
        _launchAtLoginStatus = (result as Map)['status'] as String;
        return;
      case 'appearance':
        if (value is! String || !{'light', 'dark', 'system'}.contains(value)) {
          return;
        }
      case 'notificationsEnabled':
        if (value is! bool) return;
        if (value) {
          await _nativeCall('requestNotificationPermission', {});
          await refreshNotificationStatus();
        }
      case 'enterToSend' ||
          'notificationPreviews' ||
          'notificationSound' ||
          'playsInstagramReels' ||
          'showsUnreadBadge':
        if (value is! bool) return;
      case 'messageRetentionDays':
        if (value is! int || !{1, 7, 30, 90, 365}.contains(value)) return;
      case 'iMessageHistory':
        if (value is! String ||
            !{'month', 'quarter', 'year', 'all'}.contains(value)) {
          return;
        }
      case 'themePreset':
        if (value is! String ||
            (value != 'custom' &&
                !InboxThemePalette.presets.any((p) => p.id == value))) {
          return;
        }
      case 'customColors':
        if (value is! List<int> ||
            value.length != 3 ||
            value.any((color) => color < 0 || color > 0xffffff)) {
          return;
        }
        values['themePreset'] = 'custom';
      default:
        return;
    }
    values[key] = value;
    final preferences = PreferencesRecord.fromJson(values);
    await environment.secrets.write(
      environment.secretName('preferences'),
      jsonEncode(preferences.toJson()),
    );
    _preferences = preferences;
    if ({'appearance', 'themePreset', 'customColors'}.contains(key)) {
      await _syncWindowTheme();
    }
  });

  Future<void> _syncWindowTheme() async {
    await _optionalNative('setWindowTheme', {
      'background': _preferences.palette?.background,
      'appearance': _preferences.appearance,
    });
  }

  @override
  Future<void> clearMediaCache() => _perform(() async {
    final cache = Directory(p.join(environment.directory.path, 'media'));
    final paths = await store.clearDownloadedMediaPaths(cache.path);
    for (final path in paths) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
    for (final route in _messages.keys.toList()) {
      _messages[route] = await store.loadRecentMessages(route);
    }
    await _reloadStatistics();
  });

  String diagnosticsJson() => const JsonEncoder.withIndent('  ').convert({
    'application': 'Inbox+',
    'version': inboxPlusVersion,
    'build': inboxPlusBuild,
    'platform': Platform.operatingSystem,
    'generatedAt': _now().toUtc().toIso8601String(),
    'accounts': [
      for (final account in _accounts.values)
        {'platform': account.platform, 'connected': account.isConnected},
    ],
    'storage': {
      'messages': _storageSummary.messageCount,
      'attachments': _storageSummary.attachmentCount,
      'mediaBytes': _storageSummary.mediaBytes,
    },
    'pendingSends': {
      for (final status in PendingSendStatus.values)
        status.name: _pending.where((send) => send.status == status).length,
    },
    'networks': [
      for (final network in _networks)
        {
          'platform': network.id,
          'available': network.available,
          'attachments': network.canAttach,
          'replies': network.canReply,
          'reactions': network.canReact,
        },
    ],
    'preferences': {
      'appearance': _preferences.appearance,
      'theme': _preferences.themePreset,
      'notifications': _preferences.notificationsEnabled,
      'previews': _preferences.notificationPreviews,
      'sound': _preferences.notificationSound,
      'messageRetentionDays': _preferences.messageRetentionDays,
      'iMessageHistory': _preferences.iMessageHistory,
    },
  });

  @override
  Future<void> exportDiagnostics() => _perform(() async {
    await _prepareFilePicker();
    await FilePicker.saveFile(
      fileName:
          'Inbox+ Diagnostics ${_now().toIso8601String().substring(0, 10)}.json',
      dialogTitle: 'Export Diagnostics',
      mimeType: 'application/json',
      bytes: Uint8List.fromList(utf8.encode(diagnosticsJson())),
    );
  });

  Future<void> _prepareFilePicker() async {
    // The macOS runner is unsandboxed; this configures the plugin's sandbox-only preflight.
    await FilePicker.skipEntitlementsChecks();
  }

  @override
  Future<void> requestQuit() async {
    await _nativeCall('requestQuit', {});
  }

  Future<void> _handleEvent(ConnectorEvent event) async {
    final id = event['account_id'] as String?;
    if (id == null || !_accounts.containsKey(id)) return;
    if (_preferences.disconnectedAccountIds.contains(id) &&
        _loginAccount != id) {
      return;
    }
    switch (event['type']) {
      case 'connection':
        final state = event['state'] as String? ?? '';
        _recordNetworkState(id, state);
        await _setConnection(id, state == 'connected');
        _updateLoginState(id, state, event);
      case 'login':
        final state = event['state'] as String? ?? '';
        if (state == 'connected' || state == 'success') {
          await _setConnection(id, true);
        }
        _updateLoginState(id, state, event);
      case 'qr':
        if (_loginAccount == id &&
            !_loginPhonePairing &&
            _login?.step != LoginStep.complete &&
            (event['code'] is String || event['image'] is String)) {
          final network = _accounts[id]!.platform;
          if (network == 'whatsapp' && !_loginQrSelected) {
            if (_login?.step != LoginStep.fields) {
              _login = const LoginState(
                networkId: 'whatsapp',
                step: LoginStep.fields,
                title: 'Link WhatsApp with a code',
                instructions: 'Use the number registered with WhatsApp. You will enter the linking code in WhatsApp on this phone.',
                fields: [
                  LoginField(
                    id: 'country_code',
                    label: 'Country calling code',
                    hint: 'For example, 65. No + needed.',
                    phone: true,
                  ),
                  LoginField(
                    id: 'phone',
                    label: 'Phone number',
                    hint: 'For example, 8123 4567. Omit a domestic dialling prefix; keep zeroes that are part of your number.',
                    phone: true,
                  ),
                ],
              );
            }
            break;
          }
          final expiresAt = event['expires_in'] is num
              ? _now().add(
                  Duration(seconds: (event['expires_in'] as num).toInt()),
                )
              : null;
          _login = LoginState(
            networkId: network,
            step: LoginStep.qr,
            title: network == 'wechat' ? 'Connect WeChat' : 'Link WhatsApp',
            instructions: network == 'wechat'
                ? 'Save the code, then open WeChat → + → Scan → Album and select it. Confirm sign-in, then return here. If WeChat rejects image-based login, share the code to another screen and scan it there. Requires WeChat web access.'
                : 'Scan this code using WhatsApp → Linked devices → Link a device.',
            qrData: event['code'] as String?,
            qrImage: event['image'] as String?,
            expiresAt: expiresAt,
          );
          if (expiresAt != null) _expireLoginAt(expiresAt);
        }
      case 'chat':
        await _saveChat(event);
      case 'message':
        await _saveIncomingMessage(event);
      case 'message_edit':
        final route = ConversationRoute(id, event['conversation_id'] as String);
        final original = await store.loadMessage(route, event['id'] as String);
        if (original != null && event['body'] is String) {
          await store.saveMessage(
            MessageRecord(
              id: original.id,
              route: route,
              body: event['body'] as String,
              timestamp: original.timestamp,
              isOutgoing: original.isOutgoing,
              senderId: original.senderId,
              senderName: original.senderName,
              kind: original.kind,
              attachments: original.attachments,
              deliveryState: original.deliveryState,
              replyToMessageId: original.replyToMessageId,
            ),
          );
          _messages[route] = await store.loadRecentMessages(route);
        }
      case 'message_delete':
        final route = ConversationRoute(id, event['conversation_id'] as String);
        await store.deleteMessage(route, event['id'] as String);
        _messages[route] = await store.loadRecentMessages(route);
        _reactions[route]?.remove(event['id']);
      case 'reaction':
        final route = ConversationRoute(id, event['conversation_id'] as String);
        final messageId = event['id'] as String;
        await store.setReaction(
          route,
          messageId,
          event['sender_id'] as String,
          event['emoji'] as String,
          includesMe: event['outgoing'] == true,
          timestamp: event['timestamp'] is num
              ? _timestamp(event['timestamp'])
              : null,
        );
        _reactions.putIfAbsent(route, () => {})[messageId] = await store
            .loadReactions(route, messageId);
      case 'reactions':
        await _saveReactions(
          ConversationRoute(id, event['conversation_id'] as String),
          event['id'] as String,
          event['reactions'] as List,
          partial: event['reactions_partial'] == true,
        );
      case 'error':
        _error = 'An account needs attention. Your saved conversations and drafts have been kept.';
    }
    _scheduleStatistics();
    _publish();
  }

  void _recordNetworkState(String id, String state) {
    final problem = switch (state) {
      'connecting' => AccountNetworkProblem.connecting,
      'reconnecting' => AccountNetworkProblem.reconnecting,
      'disconnected' when _accounts[id]?.platform == 'whatsapp' =>
        AccountNetworkProblem.reconnecting,
      'logged_out' || 'needs_login' => AccountNetworkProblem.signedOut,
      'disconnected' ||
      'error' ||
      'resync_required' => AccountNetworkProblem.failed,
      _ => null,
    };
    if (problem == null) {
      _networkProblems.remove(id);
    } else {
      _networkProblems[id] = problem;
    }
  }

  Future<void> _setConnection(
    String id,
    bool connected, {
    bool sync = true,
  }) async {
    final old = _accounts[id];
    if (old == null) return;
    if (connected && _preferences.disconnectedAccountIds.contains(id)) {
      if (_loginAccount != id) return;
      await _rememberDisconnected(id, false);
    }
    final account = AccountRecord(
      id: id,
      platform: old.platform,
      displayName: old.displayName,
      isConnected: connected,
    );
    await store.saveAccount(account);
    _accounts[id] = account;
    if (connected) {
      _networkProblems.remove(id);
      _newLoginAccounts.remove(id);
      if (sync && !old.isConnected && account.platform != 'imessage') {
        unawaited(
          _perform(
            () => _accountTask(id, () => _syncAccount(account)),
            background: true,
          ),
        );
      }
      for (final send
          in _pending
              .where(
                (s) =>
                    s.route.accountId == id &&
                    s.status == PendingSendStatus.queued,
              )
              .toList()) {
        unawaited(_perform(() => _send(send)));
      }
    }
  }

  Future<void> _syncAccount(AccountRecord account) async {
    String? cursor;
    final cursors = <String>{};
    bool stopped() => _isClosing || _changingAccounts.contains(account.id);
    do {
      if (stopped()) return;
      final result = await engine!.request({
        'op': account.platform == 'telegram' ? 'sync' : 'list_chats',
        'account_id': account.id,
        'cursor': ?cursor,
      });
      for (final raw in result['chats'] as List? ?? []) {
        if (stopped()) return;
        await _saveChat({
          ...Map<String, Object?>.from(raw as Map),
          'account_id': account.id,
        });
      }
      _publish();
      if (account.platform != 'instagram' || result['has_more'] != true) return;
      cursor = result['cursor'] as String?;
      if (cursor == null || cursor.isEmpty || !cursors.add(cursor)) {
        throw const ConnectorException('native_protocol_error');
      }
    } while (true);
  }

  Future<void> _saveChat(
    Map<String, Object?> data, {
    bool local = false,
  }) async {
    final accountId = data['account_id'] as String;
    final id = data['id'] as String? ?? data['conversation_id'] as String?;
    if (id == null || id.isEmpty) return;
    final route = ConversationRoute(accountId, id);
    final old = _conversations[route];
    final timestamp = data['timestamp'] == null
        ? old?.latestActivity ?? DateTime.now()
        : _timestamp(data['timestamp']);
    final readThrough = preferencesFor(route).readThrough;
    final staleUnread =
        !local && readThrough != null && !timestamp.isAfter(readThrough);
    final conversation = ConversationRecord(
      route: route,
      title: data['title'] as String? ?? old?.title ?? id,
      latestActivity: old != null && old.latestActivity.isAfter(timestamp)
          ? old.latestActivity
          : timestamp,
      unreadCount: staleUnread
          ? old?.unreadCount ?? 0
          : (data['unread_count'] as num?)?.toInt() ?? old?.unreadCount ?? 0,
      isGroup: data['is_group'] as bool? ?? old?.isGroup ?? false,
      identityId:
          data['identity_id'] as String? ??
          old?.identityId ??
          (data['is_group'] == false && old?.isGroup != true ? id : null),
      canSend: data['send_supported'] as bool? ?? old?.canSend ?? true,
      sendingUnavailableReason: data['send_supported'] == false
          ? 'This encrypted conversation is unavailable in Inbox+. Open the original app to reply.'
          : old?.sendingUnavailableReason,
      avatarSource: data['avatar_source'] as String? ?? old?.avatarSource,
      avatarBytes:
          data.containsKey('avatar_source') &&
              data['avatar_source'] != old?.avatarSource
          ? null
          : old?.avatarBytes,
      isFromUnknownSender:
          data['is_from_unknown_sender'] as bool? ??
          old?.isFromUnknownSender ??
          false,
    );
    await store.saveConversation(conversation);
    _conversations[route] = conversation;
    final source = conversation.avatarSource;
    if (source == null || source.isEmpty) {
      _requestedAvatars.remove(route);
    } else if (defaultTargetPlatform == TargetPlatform.iOS &&
        _requestedAvatars[route] != source) {
      _requestedAvatars[route] = source;
      _avatarQueue = _avatarQueue
          .then((_) => _downloadAvatar(route, source))
          .catchError((Object error) {
            _error = _safeError(error);
            if (!_closed && !_isClosing) notifyListeners();
          });
    }
  }

  Future<void> _downloadAvatar(ConversationRoute route, String source) async {
    if (_closed ||
        _isClosing ||
        _conversations[route]?.avatarSource != source) {
      return;
    }
    Uint8List bytes;
    try {
      final result = await engine!.request({
        'op': 'download_attachment',
        'account_id': route.accountId,
        'id': source,
      });
      final encoded = result['bytes'] as String?;
      if (encoded == null || encoded.length > 3 * 1024 * 1024) {
        throw const FormatException();
      }
      bytes = base64Decode(encoded);
      if (bytes.length > 2 * 1024 * 1024) throw const FormatException();
      if (bytes.isNotEmpty) {
        final codec = await ui.instantiateImageCodec(
          bytes,
          targetWidth: 128,
          targetHeight: 128,
          allowUpscaling: false,
        );
        try {
          final frame = await codec.getNextFrame();
          try {
            final data = await frame.image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            bytes = data!.buffer.asUint8List(
              data.offsetInBytes,
              data.lengthInBytes,
            );
          } finally {
            frame.image.dispose();
          }
        } finally {
          codec.dispose();
        }
      }
    } catch (_) {
      if (_requestedAvatars[route] == source) _requestedAvatars.remove(route);
      return;
    }
    _eventQueue = _eventQueue.then((_) async {
      if (_closed ||
          _isClosing ||
          _conversations[route]?.avatarSource != source) {
        return;
      }
      await store.saveAvatar(route, source, bytes);
      final current = _conversations[route];
      if (current == null || current.avatarSource != source) return;
      _conversations[route] = current.copyWith(avatarBytes: bytes);
      notifyListeners();
    });
    await _eventQueue;
  }

  Future<void> _saveReactions(
    ConversationRoute route,
    String messageId,
    List values, {
    bool partial = false,
  }) async {
    final own = ownReactionsFor(route, messageId);
    final reactions = <MessageReactionRecord>[];
    for (final value in values) {
      if (value is! Map ||
          value['key'] is! String ||
          (value['key'] as String).isEmpty) {
        continue;
      }
      final count = (value['count'] as num?)?.toInt() ?? 1;
      if (count < 1) continue;
      reactions.add(
        MessageReactionRecord(
          key: value['key'] as String,
          count: count,
          includesMe:
              value['includes_me'] == true ||
              (partial && own.contains(value['key'])),
          senderId: value['sender_id'] as String?,
          timestamp: value['timestamp'] is num
              ? _timestamp(value['timestamp'])
              : null,
        ),
      );
    }
    await store.replaceReactions(route, messageId, reactions);
    _reactions.putIfAbsent(route, () => {})[messageId] = await store
        .loadReactions(route, messageId);
  }

  Future<void> _saveIncomingMessage(Map<String, Object?> data) async {
    final id = data['id'] as String?;
    final conversationId = data['conversation_id'] as String?;
    if (id == null || conversationId == null) return;
    final route = ConversationRoute(
      data['account_id'] as String,
      conversationId,
    );
    if (_accounts[route.accountId]?.platform != 'imessage' &&
        data['historical'] == true &&
        data['timestamp'] != null &&
        _timestamp(data['timestamp']).isBefore(_messageCutoff)) {
      return;
    }
    if (!_conversations.containsKey(route)) {
      await _saveChat({
        'account_id': route.accountId,
        'id': conversationId,
        'timestamp': data['timestamp'],
        if (data['is_group'] is bool) 'is_group': data['is_group'],
        'identity_id': data['identity_id'],
        if (data['avatar_source'] is String)
          'avatar_source': data['avatar_source'],
      });
    }
    final existing = await store.loadMessage(route, id);
    final attachments = <AttachmentRecord>[];
    for (final raw in data['attachments'] as List? ?? []) {
      if (raw is! Map || raw['id'] is! String) continue;
      final saved = existing?.attachments
          .where((a) => a.id == raw['id'])
          .firstOrNull;
      String? localPath = saved?.localPath;
      if (localPath == null &&
          _accounts[route.accountId]?.platform == 'imessage' &&
          raw['local_path'] is String) {
        final source = File(raw['local_path'] as String);
        final home = Platform.environment['HOME'];
        if (home != null && await source.exists()) {
          final resolved = await source.resolveSymbolicLinks();
          final allowed = p.join(home, 'Library', 'Messages', 'Attachments');
          if (p.isWithin(allowed, resolved) &&
              await source.length() <= _maxAttachmentBytes) {
            final target = File(
              p.join(
                environment.directory.path,
                'media',
                '${_uuid.v4()}${_safeExtension(raw['name'] as String? ?? '')}',
              ),
            );
            await environment.writePrivate(target, await source.readAsBytes());
            localPath = target.path;
          }
        }
      }
      final previewId = raw['preview_id'];
      if (previewId is String && previewId.isNotEmpty) {
        attachments.add(
          AttachmentRecord(
            id: previewId,
            kind: 'preview',
            fileName: 'Preview.jpg',
            mimeType: 'image/jpeg',
            localPath: existing?.attachments
                .where((a) => a.id == previewId)
                .firstOrNull
                ?.localPath,
          ),
        );
      }
      attachments.add(
        AttachmentRecord(
          id: raw['id'] as String,
          kind:
              raw['kind'] as String? ??
              (raw['mime_type'] as String? ?? 'application/octet-stream')
                  .split('/')
                  .first,
          fileName: raw['name'] as String?,
          mimeType: raw['mime_type'] as String?,
          byteCount: (raw['size'] as num?)?.toInt(),
          localPath: localPath,
          deepLink: raw['deep_link'] as String?,
          isDownloadable:
              raw['downloadable'] as bool? ??
              (_accounts[route.accountId]?.platform != 'imessage'),
        ),
      );
    }
    final message = MessageRecord(
      id: id,
      route: route,
      body: data['body'] as String? ?? '',
      timestamp: _timestamp(data['timestamp']),
      isOutgoing: data['outgoing'] == true,
      senderId: data['sender_id'] as String? ?? existing?.senderId,
      senderName: data['sender_name'] as String?,
      replyToMessageId:
          data['reply_to_message_id'] as String? ?? existing?.replyToMessageId,
      kind: data['kind'] as String? ?? 'text',
      attachments: attachments,
    );
    await store.saveMessage(message);
    if (data['reactions'] is List) {
      await _saveReactions(
        route,
        id,
        data['reactions'] as List,
        partial: data['reactions_partial'] == true,
      );
    }
    _messages[route] = await store.loadRecentMessages(route);
    for (final preview in message.attachments) {
      if (preview.kind == 'preview' && preview.localPath == null) {
        _fetchPreview(route, message.id, preview.id);
      }
    }
    final chat = _conversations[route]!;
    final isNewIncoming =
        existing == null && !message.isOutgoing && data['historical'] != true;
    if (_selectedRoute == route && isNewIncoming) {
      await _changeConversationPreference(
        route,
        readThrough: message.timestamp.isAfter(chat.latestActivity)
            ? message.timestamp
            : chat.latestActivity,
      );
    }
    if (message.timestamp.isAfter(chat.latestActivity) || isNewIncoming) {
      await _saveChat({
        'account_id': route.accountId,
        'id': route.conversationId,
        'timestamp': message.timestamp.isAfter(chat.latestActivity)
            ? data['timestamp']
            : chat.latestActivity.millisecondsSinceEpoch,
        'unread_count': _selectedRoute == route
            ? 0
            : chat.unreadCount + (isNewIncoming ? 1 : 0),
      }, local: true);
    }
    final settings = preferencesFor(route);
    if (isNewIncoming &&
        settings.hiddenAt != null &&
        message.timestamp.isAfter(settings.hiddenAt!) &&
        !settings.isMutedAt(DateTime.now())) {
      final visible = ConversationPreferencesRecord(
        route: route,
        isFavorite: settings.isFavorite,
        markedUnread: settings.markedUnread,
        isMuted: settings.isMuted,
        mutedUntil: settings.mutedUntil,
        readThrough: settings.readThrough,
      );
      await store.saveConversationPreferences(visible);
      _conversationPreferences[route] = visible;
    }
    if (existing == null &&
        !message.isOutgoing &&
        data['historical'] != true &&
        _selectedRoute != route &&
        _preferences.notificationsEnabled &&
        !preferencesFor(route).isMutedAt(DateTime.now())) {
      await _optionalNative('notify', {
        'title': _preferences.notificationPreviews ? chat.title : 'Inbox+',
        'body': _preferences.notificationPreviews
            ? (message.body.isEmpty ? 'Attachment' : message.body)
            : 'New message',
        'sound': _preferences.notificationSound,
        'route': {
          'account_id': route.accountId,
          'conversation_id': route.conversationId,
        },
      });
    }
  }

  Future<void> _syncIMessage({ConversationRoute? route}) async {
    if (_syncingIMessage) return;
    _syncingIMessage = true;
    try {
      await _applySnapshot(
        await _imessage('imessageSnapshot', {
          if (route != null) 'conversation_id': route.conversationId,
        }),
      );
    } finally {
      _syncingIMessage = false;
    }
  }

  Future<Object?> _imessage(
    String method, [
    Map<String, Object?> arguments = const {},
  ]) async {
    if (defaultTargetPlatform != TargetPlatform.macOS) {
      throw const ConnectorException('platform_unavailable');
    }
    return _nativeCall(method, {
      ...arguments,
      'profile_name': environment.profileName,
      'history_window': _preferences.iMessageHistory,
    });
  }

  Future<void> _applySnapshot(Object? snapshot) async {
    final data = Map<String, Object?>.from(snapshot as Map);
    for (final raw in data['conversations'] as List? ?? []) {
      await _saveChat({
        ...Map<String, Object?>.from(raw as Map),
        'account_id': 'imessage-local',
      });
    }
    for (final raw in data['messages'] as List? ?? []) {
      await _saveIncomingMessage({
        ...Map<String, Object?>.from(raw as Map),
        'account_id': 'imessage-local',
        'historical': true,
      });
    }
    _publish();
  }

  NetworkCapability? _capabilityFor(ConversationRoute route) => _networks
      .where((n) => n.id == _accounts[route.accountId]?.platform)
      .firstOrNull;

  int _attachmentLimit(ConversationRoute route) =>
      _attachmentLimits[_accounts[route.accountId]?.platform] ??
      _maxAttachmentBytes;

  Future<Map<String, Object?>> _optionalNative(
    String method, [
    Map<String, Object?> arguments = const {},
  ]) async {
    try {
      final result = await _nativeCall(method, arguments);
      return result is Map ? Map<String, Object?>.from(result) : {};
    } on MissingPluginException {
      return {};
    } on PlatformException {
      if (method == 'notify') return {};
      rethrow;
    }
  }

  Future<void> _updateCloseGuard() => _optionalNative('setHasUnfinishedWork', {
    'value':
        _pending.isNotEmpty ||
        _drafts.values.any(
          (d) => d.body.isNotEmpty || d.attachments.isNotEmpty,
        ),
  });
  Future<void> _waitForDrafts() async {
    await Future.wait(_draftWrites.values);
  }

  void _scheduleStatistics() {
    if (_isClosing || _closed) return;
    _statisticsTimer?.cancel();
    _statisticsTimer = Timer(const Duration(milliseconds: 250), () {
      _statisticsFuture = _reloadStatistics()
          .then((_) => _publish())
          .catchError((Object error) {
            _error = _safeError(error);
            _publish();
          });
    });
  }

  Future<void> _reloadStatistics() async {
    final counts = await store.loadStorageSummary();
    final media = Directory(p.join(environment.directory.path, 'media'));
    var bytes = 0;
    if (await media.exists()) {
      await for (final entry in media.list(followLinks: false)) {
        if (entry is File) bytes += await entry.length();
      }
    }
    _storageSummary = StorageSummary(
      messageCount: counts.messageCount,
      attachmentCount: counts.attachmentCount,
      mediaBytes: bytes,
    );
  }

  Future<void> flush() => _perform(_waitForDrafts);

  Future<void> flushBeforeClose() => _waitForDrafts();

  @visibleForTesting
  Future<void> whenIdle() async {
    while (_operations.isNotEmpty) {
      await Future.wait(_operations.toList());
    }
  }

  // Background syncs can page through a whole mailbox, so they must not
  // disable controls the way user-started operations do.
  Future<void> _perform(
    Future<void> Function() operation, {
    bool loginOperation = false,
    bool background = false,
  }) {
    if (_closed || _isClosing) return Future.value();
    final future = _runOperation(
      operation,
      loginOperation: loginOperation,
      background: background,
    );
    _operations.add(future);
    unawaited(future.whenComplete(() => _operations.remove(future)));
    return future;
  }

  Future<void> _runOperation(
    Future<void> Function() operation, {
    bool loginOperation = false,
    bool background = false,
  }) async {
    if (!background) _busy++;
    _error = null;
    _publish();
    try {
      await operation();
    } catch (error) {
      _error = _safeError(error);
      if (loginOperation && _login != null) {
        final old = _login!;
        final expired =
            error is ConnectorException &&
            error.code == 'whatsapp_pairing_expired';
        _login = LoginState(
          networkId: old.networkId,
          step: expired
              ? LoginStep.failed
              : old.networkId == 'whatsapp' && old.step == LoginStep.qr
              ? LoginStep.qr
              : old.fields.isEmpty
              ? LoginStep.failed
              : LoginStep.fields,
          title: old.title,
          instructions: old.instructions,
          fields: old.fields,
          qrData: old.qrData,
          qrImage: old.qrImage,
          pairingCode: old.pairingCode,
          expiresAt: old.expiresAt,
          error: _error,
        );
      }
    } finally {
      if (!background) _busy--;
      _publish();
    }
  }

  String _safeError(Object error) {
    if (error is ConnectorException) {
      final message = switch (error.code) {
        'whatsapp_invalid_phone' =>
          'Enter a valid phone number including its country code.',
        'whatsapp_pairing_not_ready' =>
          'WhatsApp is still preparing sign-in. Wait a moment and try again.',
        'whatsapp_pairing_expired' =>
          'This sign-in attempt expired. Try again to get a fresh code.',
        'whatsapp_phone_pairing_failed' => 'WhatsApp could not create a linking code. Check your number and connection, then try again.',
        _ => null,
      };
      if (message != null) return message;
    }
    if (error is AppStorageException) return error.message;
    if (error is StorageException) {
      return 'Local data could not be saved or opened. Your existing profile has been kept.';
    }
    if (error is ConnectorException &&
        error.code == 'native_library_unavailable') {
      return 'The messaging component is unavailable in this build.';
    }
    if (error is PlatformException && error.code == 'cancelled') {
      return 'Sign-in was cancelled.';
    }
    if (error is PlatformException && error.code == 'photos_denied') {
      return 'Allow Inbox+ to add photos in iOS Settings, or use Share QR code to display the code on another screen.';
    }
    return 'This operation could not finish. Your saved conversations and drafts have been kept.';
  }

  void _publish() {
    if (_closed) return;
    final loginActive =
        !_isClosing &&
        _login != null &&
        _login!.step != LoginStep.complete &&
        _login!.step != LoginStep.failed;
    if (defaultTargetPlatform == TargetPlatform.iOS &&
        loginActive != _nativeLoginActive) {
      _nativeLoginActive = loginActive;
      unawaited(
        _optionalNative('setLoginActive', {'active': loginActive}).catchError((
          Object error,
        ) {
          _error = _safeError(error);
          return <String, Object?>{};
        }),
      );
    }
    final unread = _preferences.showsUnreadBadge
        ? conversations.fold<int>(
            0,
            (sum, chat) =>
                sum +
                (preferencesFor(chat.route).isMutedAt(_now()) ||
                        preferencesFor(chat.route).hiddenAt != null
                    ? 0
                    : chat.unreadCount),
          )
        : 0;
    if (!_loading && _publishedUnreadCount != unread) {
      _publishedUnreadCount = unread;
      unawaited(
        _optionalNative('setUnreadBadge', {
          'count': unread,
        }).catchError((Object error) => <String, Object?>{}),
      );
    }
    notifyListeners();
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _isClosing = true;
    _loginExpiryTimer?.cancel();
    if (_nativeLoginActive) {
      await _optionalNative('setLoginActive', {'active': false});
      _nativeLoginActive = false;
    }
    _imessageTimer?.cancel();
    _statisticsTimer?.cancel();
    await _statisticsFuture;
    await Future.wait(_operations.toList());
    await _waitForDrafts();
    await _events?.cancel();
    await _eventQueue;
    _statisticsTimer?.cancel();
    await _statisticsFuture;
    await _avatarQueue;
    await engine?.close();
    await store.close();
    _closed = true;
    super.dispose();
  }

  static DateTime _timestamp(Object? value) => value is num
      ? DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true)
      : DateTime.now().toUtc();
  static MessageRecord _copyMessage(
    MessageRecord message, {
    required List<AttachmentRecord> attachments,
  }) => MessageRecord(
    id: message.id,
    route: message.route,
    body: message.body,
    timestamp: message.timestamp,
    isOutgoing: message.isOutgoing,
    senderId: message.senderId,
    senderName: message.senderName,
    kind: message.kind,
    deliveryState: message.deliveryState,
    replyToMessageId: message.replyToMessageId,
    attachments: attachments,
  );
  static String _attachmentFileName(AttachmentRecord attachment) {
    final name = p.posix
        .basename(p.windows.basename(attachment.fileName ?? ''))
        .replaceAll(RegExp(r'[<>:"|?*\x00-\x1f]'), '_')
        .replaceFirst(RegExp(r'[.\s]+$'), '')
        .trim();
    if (name.isNotEmpty) return name;
    final extension = switch (attachment.mimeType) {
      'image/jpeg' => '.jpg',
      'image/png' => '.png',
      'image/gif' => '.gif',
      'image/webp' => '.webp',
      'video/mp4' => '.mp4',
      'video/quicktime' => '.mov',
      'audio/mpeg' => '.mp3',
      'audio/mp4' => '.m4a',
      'audio/ogg' => '.ogg',
      'application/pdf' => '.pdf',
      'text/plain' => '.txt',
      _ => '',
    };
    return 'Attachment$extension';
  }

  static String _safeExtension(String name) {
    final extension = p.extension(name).toLowerCase();
    return RegExp(r'^\.[a-z0-9]{1,10}$').hasMatch(extension) ? extension : '';
  }

  static String _mimeFor(String name) =>
      switch (p.extension(name).toLowerCase()) {
        '.jpg' || '.jpeg' => 'image/jpeg',
        '.png' => 'image/png',
        '.gif' => 'image/gif',
        '.webp' => 'image/webp',
        '.mp4' => 'video/mp4',
        '.mov' => 'video/quicktime',
        '.mp3' => 'audio/mpeg',
        '.m4a' => 'audio/mp4',
        '.ogg' => 'audio/ogg',
        '.pdf' => 'application/pdf',
        '.txt' => 'text/plain',
        _ => 'application/octet-stream',
      };
}

class _AttachmentTooLarge extends AppStorageException {
  const _AttachmentTooLarge() : super('The attachment exceeds the size limit.');
}
