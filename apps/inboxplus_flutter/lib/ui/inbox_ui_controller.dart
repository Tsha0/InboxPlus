import 'package:flutter/foundation.dart';
import 'package:inboxplus_storage/inboxplus_storage.dart';

import '../contact_suggestions.dart';

enum LoginStep { preparing, qr, pairingCode, fields, complete, failed }

enum LocalRecipientStatus { available, accessUnavailable, failed }

enum AccountNetworkProblem { connecting, reconnecting, signedOut, failed }

enum AttachmentLoadState { loading, failed, tooLarge }

enum NotificationAuthorization { unavailable, notDetermined, denied, allowed }

@immutable
class SystemNotificationStatus {
  const SystemNotificationStatus({
    this.authorization = NotificationAuthorization.unavailable,
    this.soundEnabled,
    this.alertsEnabled,
    this.badgesEnabled,
    this.canOpenSettings = false,
  });

  factory SystemNotificationStatus.fromNative(Object? value) {
    if (value is! Map) return const SystemNotificationStatus();
    return SystemNotificationStatus(
      authorization: switch (value['status']) {
        'not_determined' => NotificationAuthorization.notDetermined,
        'denied' => NotificationAuthorization.denied,
        'allowed' => NotificationAuthorization.allowed,
        _ => NotificationAuthorization.unavailable,
      },
      soundEnabled: value['sound_enabled'] is bool
          ? value['sound_enabled'] as bool
          : null,
      alertsEnabled: value['alerts_enabled'] is bool
          ? value['alerts_enabled'] as bool
          : null,
      badgesEnabled: value['badges_enabled'] is bool
          ? value['badges_enabled'] as bool
          : null,
      canOpenSettings: value['can_open_settings'] == true,
    );
  }

  final NotificationAuthorization authorization;
  final bool? soundEnabled;
  final bool? alertsEnabled;
  final bool? badgesEnabled;
  final bool canOpenSettings;

  bool get canConfigure =>
      authorization == NotificationAuthorization.allowed ||
      authorization == NotificationAuthorization.unavailable;
}

@immutable
class LocalRecipient {
  const LocalRecipient({
    required this.name,
    required this.address,
    this.searchText = '',
  });

  final String name;
  final String address;
  final String searchText;

  bool matches(String query) {
    final value = query.trim().toLowerCase();
    return value.isNotEmpty &&
        (name.toLowerCase().contains(value) ||
            address.toLowerCase().contains(value) ||
            searchText.contains(value));
  }
}

@immutable
class LocalRecipientSnapshot {
  const LocalRecipientSnapshot.available([this.recipients = const []])
    : status = LocalRecipientStatus.available;
  const LocalRecipientSnapshot.accessUnavailable()
    : status = LocalRecipientStatus.accessUnavailable,
      recipients = const [];
  const LocalRecipientSnapshot.failed()
    : status = LocalRecipientStatus.failed,
      recipients = const [];

  final LocalRecipientStatus status;
  final List<LocalRecipient> recipients;
}

const inboxPlusVersion = String.fromEnvironment(
  'INBOXPLUS_VERSION',
  defaultValue: '0.9.0',
);
const inboxPlusBuild = String.fromEnvironment(
  'INBOXPLUS_BUILD',
  defaultValue: '115',
);

@immutable
class NetworkCapability {
  const NetworkCapability({
    required this.id,
    required this.name,
    required this.available,
    this.comingSoon = false,
    this.reason,
    this.description = '',
    this.canAttach = false,
    this.canReply = false,
    this.canReact = false,
    this.canStartConversation = false,
  });

  final String id;
  final String name;
  final bool available;
  final bool comingSoon;
  final String? reason;
  final String description;
  final bool canAttach;
  final bool canReply;
  final bool canReact;
  final bool canStartConversation;
}

@immutable
class LoginField {
  const LoginField({
    required this.id,
    required this.label,
    this.hint,
    this.secret = false,
    this.phone = false,
    this.optional = false,
  });

  final String id;
  final String label;
  final String? hint;
  final bool secret;
  final bool phone;
  final bool optional;
}

@immutable
class LoginState {
  const LoginState({
    required this.networkId,
    required this.step,
    this.title = 'Connect account',
    this.instructions = '',
    this.qrData,
    this.qrImage,
    this.pairingCode,
    this.expiresAt,
    this.fields = const [],
    this.error,
    this.busy = false,
  });

  final String networkId;
  final LoginStep step;
  final String title;
  final String instructions;
  final String? qrData;
  final String? qrImage;
  final String? pairingCode;
  final DateTime? expiresAt;
  final List<LoginField> fields;
  final String? error;
  final bool busy;
}

@immutable
class StorageSummary {
  const StorageSummary({
    this.mediaBytes = 0,
    this.messageCount = 0,
    this.attachmentCount = 0,
  });

  final int mediaBytes;
  final int messageCount;
  final int attachmentCount;
}

@immutable
class InboxThemePalette {
  const InboxThemePalette(
    this.id,
    this.name,
    this.background,
    this.accent,
    this.logo,
  );
  final String id;
  final String name;
  final int background;
  final int accent;
  final int logo;
  static const presets = [
    InboxThemePalette('classic', 'Classic', 0xf4f4f4, 0x000000, 0x000000),
    InboxThemePalette('grapeSoda', 'Grape Soda', 0x4b2a6e, 0x8e5ce6, 0xf25ca2),
    InboxThemePalette('nightSwim', 'Night Swim', 0x102a43, 0x3a86ff, 0x00c2d1),
    InboxThemePalette('matcha', 'Matcha', 0x2e4a36, 0x4ca36b, 0xa7d49b),
    InboxThemePalette('sunset', 'Sunset', 0x5a1e33, 0xf26a3d, 0xffb238),
    InboxThemePalette('toast', 'Toast', 0x3b2a20, 0xd9893b, 0xf4e3c1),
    InboxThemePalette('arcade', 'Arcade', 0x14111f, 0x00c27a, 0xff3ea5),
    InboxThemePalette('bubblegum', 'Bubblegum', 0xf9d3e5, 0xe2559c, 0x5bc0eb),
    InboxThemePalette('lemonade', 'Lemonade', 0xfff1a8, 0xe3a600, 0x2f9e44),
    InboxThemePalette('mintChip', 'Mint Chip', 0xd8f3e8, 0x0e9f6e, 0x3b2a20),
  ];
}

@immutable
class PreferencesRecord {
  const PreferencesRecord({
    this.appearance = 'system',
    this.notificationsEnabled = true,
    this.notificationPreviews = true,
    this.notificationSound = true,
    this.enterToSend = true,
    this.themePreset = 'classic',
    this.customColors = const [0xe8e8ed, 0x000000, 0x000000],
    this.messageRetentionDays = 7,
    this.iMessageHistory = 'year',
    this.playsInstagramReels = true,
    this.showsUnreadBadge = true,
    this.disconnectedAccountIds = const [],
  });

  final String appearance;
  final bool notificationsEnabled;
  final bool notificationPreviews;
  final bool notificationSound;
  final bool enterToSend;
  final String themePreset;
  final List<int> customColors;
  final int messageRetentionDays;
  final String iMessageHistory;
  final bool playsInstagramReels;
  final bool showsUnreadBadge;
  final List<String> disconnectedAccountIds;

  InboxThemePalette? get palette => themePreset == 'classic'
      ? null
      : themePreset == 'custom'
      ? InboxThemePalette(
          'custom',
          'Custom',
          customColors[0],
          customColors[1],
          customColors[2],
        )
      : InboxThemePalette.presets.where((p) => p.id == themePreset).firstOrNull;

  factory PreferencesRecord.fromJson(Map<String, Object?> value) =>
      PreferencesRecord(
        appearance: value['appearance'] as String? ?? 'system',
        notificationsEnabled: value['notificationsEnabled'] as bool? ?? true,
        notificationPreviews: value['notificationPreviews'] as bool? ?? true,
        notificationSound: value['notificationSound'] as bool? ?? true,
        enterToSend: value['enterToSend'] as bool? ?? true,
        themePreset: value['themePreset'] as String? ?? 'classic',
        messageRetentionDays: value['messageRetentionDays'] as int? ?? 7,
        iMessageHistory: value['iMessageHistory'] as String? ?? 'year',
        playsInstagramReels: value['playsInstagramReels'] as bool? ?? true,
        showsUnreadBadge: value['showsUnreadBadge'] as bool? ?? true,
        disconnectedAccountIds: List<String>.unmodifiable(
          (value['disconnectedAccountIds'] as List? ?? []).cast<String>(),
        ),
        customColors: value['customColors'] == null
            ? const [0xe8e8ed, 0x000000, 0x000000]
            : List<int>.unmodifiable(
                (value['customColors'] as List).cast<int>(),
              ),
      );

  Map<String, Object?> toJson() => {
    'appearance': appearance,
    'notificationsEnabled': notificationsEnabled,
    'notificationPreviews': notificationPreviews,
    'notificationSound': notificationSound,
    'enterToSend': enterToSend,
    'themePreset': themePreset,
    'customColors': customColors,
    'messageRetentionDays': messageRetentionDays,
    'iMessageHistory': iMessageHistory,
    'playsInstagramReels': playsInstagramReels,
    'showsUnreadBadge': showsUnreadBadge,
    'disconnectedAccountIds': disconnectedAccountIds,
  };
}

abstract class InboxUiController extends ChangeNotifier {
  bool get isLoading;
  bool get isBusy;
  bool get isOffline;
  String? get error;
  List<AccountRecord> get accounts;
  List<ConversationRecord> get conversations;
  List<ContactRecord> get contacts;
  List<ContactSuggestion> get contactSuggestions => suggestContactLinks(
    accounts: accounts,
    conversations: conversations,
    contacts: contacts,
  );
  List<NetworkCapability> get networks;
  ConversationRoute? get selectedRoute;
  int get notificationActivation;
  LoginState? get login;
  StorageSummary get storageSummary;
  PreferencesRecord get preferences;
  String get launchAtLoginStatus;
  bool get supportsUpdates;
  Future<void> checkForUpdates();
  SystemNotificationStatus get notificationStatus;

  AccountNetworkProblem? networkProblem(String accountId);
  bool isChangingAccount(String accountId);

  List<MessageRecord> messagesFor(ConversationRoute route);
  DraftRecord? draftFor(ConversationRoute route);
  ConversationPreferencesRecord preferencesFor(ConversationRoute route);
  Map<String, int> reactionsFor(ConversationRoute route, String messageId);
  Set<String> ownReactionsFor(ConversationRoute route, String messageId);
  String? sendingUnavailableReason(ConversationRoute route);
  void selectConversation(ConversationRoute? route);
  Future<void> refresh();
  Future<void> startConversation(String accountId, String recipient);
  Future<LocalRecipientSnapshot> recipientContacts(String accountId);
  void updateDraft(ConversationRoute route, String text);
  Future<void> stageAttachments(ConversationRoute route);
  void removeDraftAttachment(ConversationRoute route, String attachmentId);
  void setReplyTo(ConversationRoute route, String? messageId);
  Future<void> sendDraft(ConversationRoute route);
  Future<void> retryMessage(ConversationRoute route, String messageId);
  bool isDeliveryUnconfirmed(ConversationRoute route, String messageId);
  Future<void> resolveUnconfirmedSend(
    ConversationRoute route,
    String messageId, {
    required bool wasSent,
  });
  Future<void> react(ConversationRoute route, String messageId, String emoji);
  Future<void> downloadAttachment(
    ConversationRoute route,
    String messageId,
    String attachmentId,
  );
  AttachmentLoadState? attachmentLoadState(
    ConversationRoute route,
    String attachmentId,
  );
  Future<void> loadInlineImage(
    ConversationRoute route,
    String messageId,
    String attachmentId,
  );
  Future<void> openAttachment(String localPath);
  Future<void> saveAttachment(
    ConversationRoute route,
    String messageId,
    String attachmentId,
  );
  Future<void> openAttachmentLink(
    ConversationRoute route,
    String messageId,
    String attachmentId,
  );
  Future<void> setFavorite(ConversationRoute route, bool favorite);
  Future<void> setMuted(ConversationRoute route, bool muted, {DateTime? until});
  Future<void> setHidden(ConversationRoute route, bool hidden);
  Future<void> setUnread(ConversationRoute route, bool unread);
  Future<void> saveContact(ContactRecord contact);
  Future<String?> acceptContactSuggestion(ContactSuggestion suggestion);
  Future<void> linkIdentity(IdentityLink identity, ContactRecord person);
  Future<void> removeContact(String contactId);
  Future<void> beginLogin(String networkId, {bool? useQr});
  Future<void> reconnectAccount(String accountId);
  Future<void> disconnectAccount(String accountId);
  Future<void> submitLogin(Map<String, String> fields);
  Future<void> cancelLogin();
  Future<void> resumeLogin();
  Future<void> exportLoginQr(Uint8List image, {bool share = false});
  Future<void> removeAccount(String accountId);
  Future<void> openLoginItemsSettings();
  Future<void> refreshNotificationStatus();
  Future<void> requestNotificationPermission();
  Future<void> openNotificationSettings();
  Future<void> setPreference(String key, Object value);
  Future<void> clearMediaCache();
  Future<void> exportDiagnostics();
  Future<void> requestQuit();
}
