part of 'inbox_app.dart';

int _otherUnreadChats(InboxUiController controller, ConversationRoute route) =>
    controller.conversations.where((chat) {
      final preferences = controller.preferencesFor(chat.route);
      return chat.route != route &&
          preferences.hiddenAt == null &&
          (chat.unreadCount > 0 || preferences.markedUnread);
    }).length;

class _PhoneChatHeader extends StatelessWidget {
  const _PhoneChatHeader({
    required this.controller,
    required this.conversation,
    required this.onBack,
    required this.onInfo,
    required this.onActions,
  });

  final InboxUiController controller;
  final ConversationRecord conversation;
  final VoidCallback? onBack;
  final VoidCallback onInfo;
  final VoidCallback onActions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final unread = _otherUnreadChats(controller, conversation.route);
    final account = _accountFor(controller, conversation.route);
    final pill = BoxDecoration(
      color: scheme.surfaceContainerHigh,
      border: Border.all(color: scheme.outlineVariant),
      borderRadius: BorderRadius.circular(22),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Align(
              alignment: Alignment.centerLeft,
              child: onBack == null
                  ? null
                  : Semantics(
                      button: true,
                      label: unread > 0
                          ? 'Back to inbox, $unread unread'
                          : 'Back to inbox',
                      excludeSemantics: true,
                      onTap: onBack,
                      child: Material(
                        type: MaterialType.transparency,
                        child: InkWell(
                          key: const Key('back-to-inbox'),
                          onTap: onBack,
                          borderRadius: BorderRadius.circular(22),
                          child: Container(
                            height: 44,
                            constraints: const BoxConstraints(minWidth: 44),
                            padding: EdgeInsets.fromLTRB(
                              8,
                              0,
                              unread > 0 ? 14 : 8,
                              0,
                            ),
                            decoration: pill,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(CupertinoIcons.back, size: 22),
                                if (unread > 0)
                                  Text(
                                    unread > 99 ? '99+' : '$unread',
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
          Expanded(
            child: Semantics(
              button: true,
              label: 'Chat info for ${conversation.title}',
              excludeSemantics: true,
              onTap: onInfo,
              child: GestureDetector(
                key: const Key('chat-info-button'),
                behavior: HitTestBehavior.opaque,
                onTap: onInfo,
                child: Column(
                  children: [
                    PersonAvatar(
                      name: conversation.title,
                      bytes: conversation.avatarBytes,
                      network: account?.platform,
                      isGroup: conversation.isGroup,
                      size: 44,
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: pill.copyWith(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        conversation.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(
            width: 76,
            child: Align(
              alignment: Alignment.centerRight,
              child: Material(
                type: MaterialType.transparency,
                child: Ink(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: pill.color,
                    border: pill.border,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    tooltip: 'Conversation actions',
                    onPressed: onActions,
                    icon: const Icon(Icons.more_horiz, size: 20),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _muteWithDuration(
  BuildContext context,
  InboxUiController controller,
  ConversationRoute route,
) async {
  final hours = await showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (value, label) in const [
            (1, 'For 1 hour'),
            (8, 'For 8 hours'),
            (0, 'Until I turn it back on'),
          ])
            ListTile(
              title: Text(label),
              onTap: () => Navigator.pop(sheetContext, value),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (hours == null) return;
  await controller.setMuted(
    route,
    true,
    until: hours == 0 ? null : DateTime.now().add(Duration(hours: hours)),
  );
}

class _PhoneChatInfoPage extends StatelessWidget {
  const _PhoneChatInfoPage({required this.controller, required this.route});

  final InboxUiController controller;
  final ConversationRoute route;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final conversation = controller.conversations
          .where((chat) => chat.route == route)
          .firstOrNull;
      if (conversation == null) return const Scaffold();
      return _build(context, conversation);
    },
  );

  Widget _build(BuildContext context, ConversationRecord conversation) {
    final scheme = Theme.of(context).colorScheme;
    final preferences = controller.preferencesFor(route);
    final muted = preferences.isMutedAt(DateTime.now());
    final unread = conversation.unreadCount > 0 || preferences.markedUnread;
    final account = _accountFor(controller, route);
    final attachments = [
      for (final message in controller.messagesFor(route).reversed)
        for (final attachment in message.attachments)
          (message: message, attachment: attachment),
    ];
    final media = attachments
        .where(
          (item) =>
              item.attachment.kind == 'image' &&
              item.attachment.localPath != null,
        )
        .toList();
    final files = attachments
        .where(
          (item) =>
              item.attachment.kind != 'image' &&
              item.attachment.kind != 'video' &&
              item.attachment.fileName != null,
        )
        .toList();
    Widget heading(String text, {Widget? trailing}) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                letterSpacing: .6,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
    Widget quick({
      required Key key,
      required IconData icon,
      required String label,
      required VoidCallback onTap,
      bool active = false,
    }) => Expanded(
      child: Material(
        color: active
            ? scheme.primary.withValues(alpha: .16)
            : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          key: key,
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 68,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 22,
                  color: active ? scheme.primary : scheme.onSurface,
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton.filledTonal(
                tooltip: 'Close chat info',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, size: 20),
              ),
            ),
            Center(
              child: PersonAvatar(
                name: conversation.title,
                bytes: conversation.avatarBytes,
                isGroup: conversation.isGroup,
                size: 92,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              conversation.title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                NetworkBadge(
                  network: account?.platform,
                  size: 18,
                  labelled: false,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    [
                      _networkName(controller, account?.platform),
                      if (conversation.isGroup) 'Group',
                      if (account != null) account.displayName,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              spacing: 8,
              children: [
                quick(
                  key: const Key('chat-info-mute'),
                  icon: muted
                      ? CupertinoIcons.bell_slash_fill
                      : CupertinoIcons.bell_slash,
                  label: muted ? 'Unmute' : 'Mute',
                  active: muted,
                  onTap: () async {
                    if (muted) {
                      await controller.setMuted(route, false);
                      return;
                    }
                    await _muteWithDuration(context, controller, route);
                  },
                ),
                quick(
                  key: const Key('chat-info-favorite'),
                  icon: preferences.isFavorite
                      ? CupertinoIcons.star_fill
                      : CupertinoIcons.star,
                  label: 'Favourite',
                  active: preferences.isFavorite,
                  onTap: () =>
                      controller.setFavorite(route, !preferences.isFavorite),
                ),
                quick(
                  key: const Key('chat-info-unread'),
                  icon: unread
                      ? CupertinoIcons.envelope_open
                      : CupertinoIcons.envelope_badge,
                  label: unread ? 'Read' : 'Unread',
                  onTap: () => controller.setUnread(route, !unread),
                ),
                quick(
                  key: const Key('chat-info-hide'),
                  icon: CupertinoIcons.eye_slash,
                  label: preferences.hiddenAt == null ? 'Hide' : 'Unhide',
                  active: preferences.hiddenAt != null,
                  onTap: () =>
                      controller.setHidden(route, preferences.hiddenAt == null),
                ),
              ],
            ),
            heading(
              'Photos',
              trailing: Text(
                '${media.length}',
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
            ),
            if (media.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'Photos you open in this chat appear here.',
                  style: TextStyle(
                    fontSize: 14,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              GridView.count(
                crossAxisCount: 4,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  for (final item in media.take(12))
                    Semantics(
                      button: true,
                      label: 'Open ${item.attachment.fileName ?? 'photo'}',
                      child: GestureDetector(
                        onTap: () => controller.openAttachment(
                          item.attachment.localPath!,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(
                            File(item.attachment.localPath!),
                            fit: BoxFit.cover,
                            cacheWidth: 240,
                            errorBuilder: (_, _, _) =>
                                ColoredBox(color: scheme.surfaceContainerHigh),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            heading('Files'),
            _PhoneInfoCard(
              children: files.isEmpty
                  ? [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'No files in recent messages.',
                          style: TextStyle(
                            fontSize: 14,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ]
                  : [
                      for (final item in files.take(20))
                        ListTile(
                          leading: const Icon(CupertinoIcons.doc),
                          title: Text(
                            item.attachment.fileName!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(_dayLabel(item.message.timestamp)),
                          trailing: switch ((
                            item.attachment.localPath,
                            controller.attachmentLoadState(
                              route,
                              item.attachment.id,
                            ),
                          )) {
                            (_?, _) => IconButton(
                              tooltip: 'Save ${item.attachment.fileName}',
                              icon: const Icon(
                                CupertinoIcons.arrow_down_to_line,
                              ),
                              onPressed: () => controller.saveAttachment(
                                route,
                                item.message.id,
                                item.attachment.id,
                              ),
                            ),
                            (null, AttachmentLoadState.loading) =>
                              const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            (null, _) when item.attachment.isDownloadable =>
                              IconButton(
                                tooltip: 'Download ${item.attachment.fileName}',
                                icon: const Icon(CupertinoIcons.cloud_download),
                                onPressed: () => controller.downloadAttachment(
                                  route,
                                  item.message.id,
                                  item.attachment.id,
                                ),
                              ),
                            _ => null,
                          },
                        ),
                    ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PhoneInfoCard extends StatelessWidget {
  const _PhoneInfoCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(18),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Column(children: children),
      ),
    );
  }
}

enum _PeekAction { unread, favorite, mute, unmute, hide }

Future<void> _showPhoneChatPeek(
  BuildContext context,
  InboxUiController controller,
  ConversationRecord conversation, {
  bool preview = true,
}) async {
  final route = conversation.route;
  final preferences = controller.preferencesFor(route);
  final muted = preferences.isMutedAt(DateTime.now());
  final unread = conversation.unreadCount > 0 || preferences.markedUnread;
  final hidden = preferences.hiddenAt != null;
  final action = await showGeneralDialog<_PeekAction>(
    context: context,
    barrierDismissible: true,
    barrierLabel: preview ? 'Close chat preview' : 'Close chat actions',
    barrierColor: Colors.black.withValues(alpha: preview ? .45 : .2),
    transitionDuration: const Duration(milliseconds: 180),
    transitionBuilder: (context, animation, _, child) => FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        scale: Tween(begin: .96, end: 1.0).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        ),
        child: child,
      ),
    ),
    pageBuilder: (dialogContext, _, _) => SafeArea(
      child: Padding(
        padding: preview
            ? const EdgeInsets.fromLTRB(16, 24, 16, 24)
            : const EdgeInsets.fromLTRB(16, 58, 12, 24),
        child: _PhoneChatPeek(
          controller: controller,
          conversation: conversation,
          preview: preview,
          unread: unread,
          favorite: preferences.isFavorite,
          muted: muted,
          hidden: hidden,
          onPick: (action) => Navigator.pop(dialogContext, action),
        ),
      ),
    ),
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case _PeekAction.unread:
      await controller.setUnread(route, !unread);
    case _PeekAction.favorite:
      await controller.setFavorite(route, !preferences.isFavorite);
    case _PeekAction.unmute:
      await controller.setMuted(route, false);
    case _PeekAction.mute:
      await _muteWithDuration(context, controller, route);
    case _PeekAction.hide:
      await controller.setHidden(route, !hidden);
  }
}

class _PhoneChatPeek extends StatelessWidget {
  const _PhoneChatPeek({
    required this.controller,
    required this.conversation,
    required this.unread,
    required this.favorite,
    required this.muted,
    required this.hidden,
    required this.onPick,
    this.preview = true,
  });

  final InboxUiController controller;
  final ConversationRecord conversation;
  final bool preview;
  final bool unread;
  final bool favorite;
  final bool muted;
  final bool hidden;
  final ValueChanged<_PeekAction> onPick;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final account = _accountFor(controller, conversation.route);
    final messages = controller.messagesFor(conversation.route);
    final recent = messages.length > 4
        ? messages.sublist(messages.length - 4)
        : messages;
    Widget item(_PeekAction action, String label, IconData icon) => InkWell(
      key: Key('peek-${action.name}'),
      onTap: () => onPick(action),
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 16))),
            Icon(icon, size: 20),
          ],
        ),
      ),
    );
    final surface = dark ? const Color(0xff16171a) : Colors.white;
    return Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: preview
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.end,
        children: [
          if (preview)
            Flexible(
              child: _PhoneGlass(
                radius: 24,
                color: surface,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      child: Row(
                        children: [
                          PersonAvatar(
                            name: conversation.title,
                            bytes: conversation.avatarBytes,
                            network: account?.platform,
                            isGroup: conversation.isGroup,
                            size: 34,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  conversation.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  [
                                    _networkName(controller, account?.platform),
                                    if (conversation.unreadCount > 0)
                                      '${conversation.unreadCount} unread',
                                  ].join(' · '),
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: scheme.outlineVariant),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          spacing: 6,
                          children: recent.isEmpty
                              ? [
                                  Text(
                                    'No recent messages',
                                    style: TextStyle(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ]
                              : [
                                  for (final message in recent)
                                    Align(
                                      alignment: message.isOutgoing
                                          ? Alignment.centerRight
                                          : Alignment.centerLeft,
                                      child: Container(
                                        constraints: const BoxConstraints(
                                          maxWidth: 260,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 13,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: message.isOutgoing
                                              ? scheme.primary
                                              : scheme.surfaceContainerHighest,
                                          borderRadius: BorderRadius.circular(
                                            18,
                                          ),
                                        ),
                                        child: Text(
                                          message.body.isEmpty
                                              ? 'Attachment'
                                              : message.body,
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 14.5,
                                            color: message.isOutgoing
                                                ? scheme.onPrimary
                                                : scheme.onSurface,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (preview) const SizedBox(height: 12),
          SizedBox(
            width: 264,
            child: _PhoneGlass(
              radius: 20,
              color: dark ? const Color(0xff232428) : Colors.white,
              child: Material(
                type: MaterialType.transparency,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      item(
                        _PeekAction.unread,
                        unread ? 'Mark as read' : 'Mark as unread',
                        unread
                            ? CupertinoIcons.envelope_open
                            : CupertinoIcons.envelope_badge,
                      ),
                      item(
                        _PeekAction.favorite,
                        favorite
                            ? 'Remove from favourites'
                            : 'Add to favourites',
                        favorite
                            ? CupertinoIcons.star_slash
                            : CupertinoIcons.star,
                      ),
                      Divider(height: 12, color: scheme.outlineVariant),
                      item(
                        muted ? _PeekAction.unmute : _PeekAction.mute,
                        muted ? 'Unmute' : 'Mute…',
                        muted ? CupertinoIcons.bell : CupertinoIcons.bell_slash,
                      ),
                      item(
                        _PeekAction.hide,
                        hidden ? 'Show in inbox' : 'Hide',
                        hidden ? CupertinoIcons.eye : CupertinoIcons.eye_slash,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatWallpaper extends CustomPainter {
  const _ChatWallpaper(this.style, this.color);

  final String style;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    switch (style) {
      case 'tint':
        canvas.drawRect(Offset.zero & size, paint);
      case 'dots':
        for (var y = 12.0; y < size.height; y += 22) {
          for (var x = 12.0; x < size.width; x += 22) {
            canvas.drawCircle(Offset(x, y), 1.4, paint);
          }
        }
      case 'grid':
        paint.strokeWidth = 1;
        for (var x = 0.0; x < size.width; x += 28) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
        }
        for (var y = 0.0; y < size.height; y += 28) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
        }
    }
  }

  @override
  bool shouldRepaint(_ChatWallpaper old) =>
      old.style != style || old.color != color;
}
