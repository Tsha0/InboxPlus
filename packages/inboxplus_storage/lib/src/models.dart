class ConversationRoute {
  const ConversationRoute(this.accountId, this.conversationId);

  final String accountId;
  final String conversationId;

  @override
  bool operator ==(Object other) =>
      other is ConversationRoute &&
      accountId == other.accountId &&
      conversationId == other.conversationId;

  @override
  int get hashCode => Object.hash(accountId, conversationId);
}

class AccountRecord {
  const AccountRecord({
    required this.id,
    required this.platform,
    required this.displayName,
    this.isConnected = false,
  });

  final String id;
  final String platform;
  final String displayName;
  final bool isConnected;
}

class ConversationRecord {
  const ConversationRecord({
    required this.route,
    required this.title,
    required this.latestActivity,
    this.unreadCount = 0,
    this.isGroup = false,
    this.identityId,
    this.canSend = true,
    this.sendingUnavailableReason,
    this.isFromUnknownSender = false,
  });

  final ConversationRoute route;
  final String title;
  final DateTime latestActivity;
  final int unreadCount;
  final bool isGroup;
  final String? identityId;
  final bool canSend;
  final String? sendingUnavailableReason;
  final bool isFromUnknownSender;

  ConversationRecord copyWith({int? unreadCount, DateTime? latestActivity}) =>
      ConversationRecord(
        route: route,
        title: title,
        latestActivity: latestActivity ?? this.latestActivity,
        unreadCount: unreadCount ?? this.unreadCount,
        isGroup: isGroup,
        identityId: identityId,
        canSend: canSend,
        sendingUnavailableReason: sendingUnavailableReason,
        isFromUnknownSender: isFromUnknownSender,
      );
}

enum DeliveryState { pending, acknowledged, failed }

class AttachmentRecord {
  const AttachmentRecord({
    required this.id,
    required this.kind,
    this.fileName,
    this.mimeType,
    this.byteCount,
    this.localPath,
    this.remoteSource,
    this.deepLink,
    this.isDownloadable = true,
  });

  final String id;
  final String kind;
  final String? fileName;
  final String? mimeType;
  final int? byteCount;
  final String? localPath;
  final String? remoteSource;
  final String? deepLink;
  final bool isDownloadable;
}

class MessageRecord {
  MessageRecord({
    required this.id,
    required this.route,
    required this.body,
    required this.timestamp,
    required this.isOutgoing,
    this.senderId,
    this.senderName,
    this.kind = 'text',
    this.deliveryState = DeliveryState.acknowledged,
    this.replyToMessageId,
    List<AttachmentRecord> attachments = const [],
  }) : attachments = List.unmodifiable(attachments);

  final String id;
  final ConversationRoute route;
  final String body;
  final DateTime timestamp;
  final bool isOutgoing;
  final String? senderId;
  final String? senderName;
  final String kind;
  final DeliveryState deliveryState;
  final String? replyToMessageId;
  final List<AttachmentRecord> attachments;

  bool get acceptsResponses =>
      deliveryState == DeliveryState.acknowledged &&
      !{
        'system',
        'notice',
        'redacted',
        'encrypted',
        'membership',
        'state',
      }.contains(kind);
}

class MessageReactionRecord {
  const MessageReactionRecord({
    required this.key,
    this.count = 1,
    this.includesMe = false,
    this.senderId,
    this.timestamp,
  });
  final String key;
  final int count;
  final bool includesMe;
  final String? senderId;
  final DateTime? timestamp;
}

class MessageReactionsRecord {
  const MessageReactionsRecord({
    required this.route,
    required this.messageId,
    required this.reactions,
  });
  final ConversationRoute route;
  final String messageId;
  final List<MessageReactionRecord> reactions;
}

class DraftRecord {
  DraftRecord({
    required this.route,
    required this.body,
    required this.revision,
    this.replyToMessageId,
    List<AttachmentRecord> attachments = const [],
  }) : attachments = List.unmodifiable(attachments);

  final ConversationRoute route;
  final String body;
  final int revision;
  final String? replyToMessageId;
  final List<AttachmentRecord> attachments;
}

enum PendingSendStatus { queued, sending, failed, unknown }

class PendingSendRecord {
  PendingSendRecord({
    required this.id,
    required this.route,
    required this.body,
    required this.createdAt,
    required this.draftRevision,
    this.status = PendingSendStatus.queued,
    this.replyToMessageId,
    List<AttachmentRecord> attachments = const [],
  }) : attachments = List.unmodifiable(attachments);

  final String id;
  final ConversationRoute route;
  final String body;
  final DateTime createdAt;
  final int draftRevision;
  final PendingSendStatus status;
  final String? replyToMessageId;
  final List<AttachmentRecord> attachments;
}

class IdentityLink {
  const IdentityLink(this.accountId, this.identityId);

  final String accountId;
  final String identityId;
}

class ContactRecord {
  ContactRecord({
    required this.id,
    required this.displayName,
    List<IdentityLink> identities = const [],
  }) : identities = List.unmodifiable(identities);

  final String id;
  final String displayName;
  final List<IdentityLink> identities;
}

class ConversationPreferencesRecord {
  const ConversationPreferencesRecord({
    required this.route,
    this.isFavorite = false,
    this.markedUnread = false,
    this.isMuted = false,
    this.mutedUntil,
    this.hiddenAt,
  });

  final ConversationRoute route;
  final bool isFavorite;
  final bool markedUnread;
  final bool isMuted;
  final DateTime? mutedUntil;
  final DateTime? hiddenAt;

  bool isMutedAt(DateTime now) =>
      isMuted && (mutedUntil == null || mutedUntil!.isAfter(now));
}

class LocalStorageSummary {
  const LocalStorageSummary({
    required this.messageCount,
    required this.attachmentCount,
  });

  final int messageCount;
  final int attachmentCount;
}

enum StorageErrorCode {
  invalidKey,
  invalidData,
  openFailed,
  unsupportedSchema,
  readFailed,
  writeFailed,
}

class StorageException implements Exception {
  const StorageException(this.code);

  final StorageErrorCode code;

  @override
  String toString() => 'Inbox+ local storage: ${code.name}.';
}
