import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle, LogicalKeyboardKey;
import 'package:inboxplus_storage/inboxplus_storage.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;

import 'app_controller.dart';
import 'connectors/connector_engine.dart';
import 'platform/app_environment.dart';
import 'ui/inbox_app.dart';

Future<void> main() async {
  if (kReleaseMode) {
    throw StateError('Desktop comparison fixtures require a debug build.');
  }
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final fixture = jsonDecode(
    await File(const String.fromEnvironment('INBOXPLUS_DESKTOP_FIXTURE'))
        .readAsString(),
  ) as Map;
  final temporary = await Directory.systemTemp.createTemp(
    'inboxplus-desktop-preview-',
  );
  final directory = Directory(await temporary.resolveSymbolicLinks());
  final environment = AppEnvironment(
    directory: directory,
    secrets: _PreviewSecrets(),
  );
  final store = await LocalStore.open(
    file: File(p.join(directory.path, 'inbox.sqlite')),
    key: Uint8List.fromList(List.generate(32, (index) => index + 1)),
  );
  final now = DateTime.parse(fixture['referenceTime'] as String);
  final platforms = {
    'whatsApp': 'whatsapp',
    'facebookMessenger': 'messenger',
    'iMessage': 'imessage',
  };
  for (final account in fixture['accounts'] as List) {
    await store.saveAccount(
      AccountRecord(
        id: account['id'] as String,
        platform:
            platforms[account['platform']] ?? account['platform'] as String,
        displayName: account['identity'] as String,
      ),
    );
  }
  for (final chat in fixture['conversations'] as List) {
    await store.saveConversation(
      ConversationRecord(
        route: ConversationRoute(
          chat['account'] as String,
          chat['id'] as String,
        ),
        title: chat['title'] as String,
        latestActivity: now.subtract(
          Duration(minutes: chat['minutesAgo'] as int),
        ),
        unreadCount: chat['unread'] as int,
        isGroup: chat['group'] as bool,
        identityId: chat['identity'] as String,
      ),
    );
  }
  for (final message in fixture['messages'] as List) {
    final attachments = <AttachmentRecord>[];
    for (final attachment in message['attachments'] as List? ?? []) {
      final bytes = attachment['asset'] == null
          ? Uint8List.fromList(utf8.encode(attachment['text'] as String))
          : (await rootBundle.load('assets/${attachment['asset']}')).buffer
                .asUint8List();
      final file = File(
        p.join(directory.path, 'media', attachment['name'] as String),
      );
      await environment.writePrivate(file, bytes);
      attachments.add(
        AttachmentRecord(
          id: attachment['id'] as String,
          kind: attachment['kind'] as String,
          fileName: attachment['name'] as String,
          mimeType: attachment['mimeType'] as String,
          byteCount: bytes.length,
          localPath: file.path,
          isDownloadable: false,
        ),
      );
    }
    await store.saveMessage(
      MessageRecord(
        id: message['id'] as String,
        route: ConversationRoute(
          message['account'] as String,
          message['conversation'] as String,
        ),
        body: message['body'] as String,
        timestamp: now.subtract(
          Duration(minutes: message['minutesAgo'] as int),
        ),
        isOutgoing: message['outgoing'] as bool,
        senderName: message['sender'] as String,
        attachments: attachments,
      ),
    );
  }
  final reactionStates =
      <(String, String, String), List<MessageReactionRecord>>{};
  for (final reaction in fixture['reactions'] as List) {
    final scope = (
      reaction['account'] as String,
      reaction['conversation'] as String,
      reaction['message'] as String,
    );
    reactionStates
        .putIfAbsent(scope, () => [])
        .add(
          MessageReactionRecord(
            key: reaction['key'] as String,
            count: reaction['count'] as int,
            includesMe: reaction['own'] as bool,
          ),
        );
  }
  for (final entry in reactionStates.entries) {
    await store.replaceReactions(
      ConversationRoute(entry.key.$1, entry.key.$2),
      entry.key.$3,
      entry.value,
    );
  }
  for (final person in fixture['contacts'] as List) {
    final identities = <IdentityLink>[];
    for (final identity in person['identities'] as List) {
      final chat = (fixture['conversations'] as List).firstWhere(
        (chat) => chat['identity'] == identity,
      );
      identities.add(
        IdentityLink(chat['account'] as String, identity as String),
      );
    }
    await store.saveContact(
      ContactRecord(
        id: person['id'] as String,
        displayName: person['name'] as String,
        identities: identities,
      ),
    );
  }
  await environment.secrets.write(
    environment.secretName('preferences'),
    jsonEncode({
      'appearance': 'light',
      'notificationsEnabled': true,
      'enterToSend': true,
    }),
  );
  final appleChats = <Map<String, Object?>>[];
  final controller = AppController(
    store: store,
    environment: environment,
    engine: _PreviewEngine(reactionStates),
    nativeCall: (method, arguments) async {
      switch (method) {
        case 'setWindowTheme':
        case 'setUnreadBadge':
        case 'setHasUnfinishedWork':
        case 'takeNotificationRoute':
          return AppEnvironment.native.invokeMethod<Object?>(method, arguments);
        case 'capabilities':
          return {
            'web_login_platforms': ['instagram', 'messenger'],
            'imessage': true,
            'launch_at_login_status': 'off',
          };
        case 'notificationStatus':
          return {
            'status': const String.fromEnvironment(
              'INBOXPLUS_PREVIEW_NOTIFICATION_STATUS',
              defaultValue: 'allowed',
            ),
            'sound_enabled': const bool.fromEnvironment(
              'INBOXPLUS_PREVIEW_NOTIFICATION_SOUND',
              defaultValue: true,
            ),
            'alerts_enabled': true,
            'badges_enabled': true,
            'can_open_settings': true,
          };
        case 'setLaunchAtLogin':
          return {'status': arguments['enabled'] == true ? 'on' : 'off'};
        case 'imessageSnapshot':
          return {'conversations': appleChats, 'messages': []};
        case 'imessageRecipientContacts':
          return {'status': 'available', 'recipients': fixture['recipients']};
        case 'imessageStartConversation':
          final recipient = arguments['recipient'] as String;
          final chat = <String, Object?>{
            'id': 'preview-$recipient',
            'identity_id': recipient,
            'title': recipient,
            'timestamp': 0,
            'is_group': false,
          };
          appleChats.add(chat);
          return chat;
        default:
          return null;
      }
    },
  );
  await controller.initialize();
  AppEnvironment.native.setMethodCallHandler((call) async {
    if (call.method == 'notificationActivated') {
      await controller.openPendingNotification();
      return null;
    }
    if (call.method == 'prepareToClose') {
      await controller.flushBeforeClose();
      return true;
    }
    return null;
  });
  runApp(
    CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f8): () =>
            AppEnvironment.native.invokeMethod<void>('previewNotification', {
              'route': {'account_id': 'whatsapp', 'conversation_id': 'team'},
            }),
      },
      child: InboxPlusApp(controller: controller),
    ),
  );
}

class _PreviewSecrets implements SecretStore {
  final _values = <String, String>{};
  @override
  Future<String?> read(String key) async => _values[key];
  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}

class _PreviewEngine implements ConnectorEngine {
  _PreviewEngine(this._reactions);
  final Map<(String, String, String), List<MessageReactionRecord>> _reactions;
  final _events = StreamController<ConnectorEvent>.broadcast();
  @override
  Stream<ConnectorEvent> get events => _events.stream;
  @override
  Future<Map<String, Object?>> request(Map<String, Object?> command) async {
    switch (command['op']) {
      case 'capabilities':
        return {
          'abi_version': 1,
          'platforms': ['whatsapp', 'telegram', 'instagram', 'messenger'],
          'features': {
            for (final platform in [
              'whatsapp',
              'telegram',
              'instagram',
              'messenger',
            ])
              platform: {
                'send_attachment': true,
                'start_conversation': true,
                'replies': true,
                'reactions': true,
              },
          },
        };
      case 'connect':
        return {'state': 'connected'};
      case 'send_text':
        return {
          'id': 'preview-${command['id']}',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        };
      case 'react':
        final scope = (
          command['account_id'] as String,
          command['conversation_id'] as String,
          command['message_id'] as String,
        );
        final selected = command['emoji'] as String;
        final previous = _reactions[scope] ?? [];
        final next = <MessageReactionRecord>[];
        var found = false;
        for (final reaction in previous) {
          final mine = reaction.key == selected;
          final count =
              reaction.count - (reaction.includesMe ? 1 : 0) + (mine ? 1 : 0);
          if (count > 0) {
            next.add(
              MessageReactionRecord(
                key: reaction.key,
                count: count,
                includesMe: mine,
              ),
            );
          }
          found |= mine;
        }
        if (!found && selected.isNotEmpty) {
          next.add(MessageReactionRecord(key: selected, includesMe: true));
        }
        _reactions[scope] = next;
        return {
          'applied': true,
          'type': 'reactions',
          'reactions': [
            for (final reaction in next)
              {
                'key': reaction.key,
                'count': reaction.count,
                'includes_me': reaction.includesMe,
              },
          ],
        };
      case 'logout':
        return {'logged_out': true, 'remote_session_revoked': true};
      case 'close':
        return {'closed': true, 'has_session': false};
      default:
        return {};
    }
  }

  @override
  Future<void> close() => _events.close();
}
