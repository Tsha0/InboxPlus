part of 'account_pages.dart';

class _PhoneSettingsPage extends StatelessWidget {
  const _PhoneSettingsPage({required this.page});

  final InboxSettingsPage page;

  InboxUiController get controller => page.controller;

  void _push(BuildContext context, Widget child) =>
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => child));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final preferences = controller.preferences;
    final disconnected = controller.accounts
        .where((account) => !account.isConnected)
        .firstOrNull;
    final hiddenCount = controller.conversations
        .where((chat) => controller.preferencesFor(chat.route).hiddenAt != null)
        .length;
    final mutedCount = controller.conversations
        .where(
          (chat) =>
              controller.preferencesFor(chat.route).isMutedAt(DateTime.now()),
        )
        .length;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        MediaQuery.paddingOf(context).bottom + 24,
      ),
      children: [
        Text(
          'Settings',
          style: const TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w700,
            letterSpacing: -.4,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Make Inbox+ feel like home.',
          style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
        ),
        if (disconnected != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            decoration: BoxDecoration(
              color: const Color(0xfff0a37a).withValues(alpha: .14),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: const Color(0xfff0a37a).withValues(alpha: .45),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  CupertinoIcons.exclamationmark_circle_fill,
                  color: Color(0xffd9773f),
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${page._networkName(disconnected.platform)} is disconnected',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'New messages won’t arrive until you reconnect.',
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton(
                  onPressed: controller.isBusy
                      ? null
                      : () => page._reconnect(context, disconnected.id),
                  child: const Text('Reconnect'),
                ),
              ],
            ),
          ),
        ],
        _PhoneGroup(
          title: 'Connected accounts',
          children: [
            for (final account in controller.accounts)
              _PhoneRow(
                leading: NetworkBadge(
                  network: account.platform,
                  size: 32,
                  labelled: false,
                ),
                title: account.displayName,
                subtitle:
                    '${page._networkName(account.platform)} · ${account.isConnected ? 'Connected' : 'Disconnected'}',
                subtitleColor: account.isConnected
                    ? null
                    : const Color(0xffd9773f),
                trailing: IconButton(
                  tooltip: 'Remove ${account.displayName}',
                  onPressed: controller.isBusy
                      ? null
                      : () async {
                          if (await confirmAccountRemoval(
                            context,
                            page._networkName(account.platform),
                          )) {
                            await controller.removeAccount(account.id);
                          }
                        },
                  icon: Icon(
                    CupertinoIcons.minus_circle,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                onTap: account.isConnected || controller.isBusy
                    ? null
                    : () => page._reconnect(context, account.id),
              ),
            _PhoneRow(
              leading: Icon(CupertinoIcons.add, color: scheme.primary),
              title: 'Add account',
              titleColor: scheme.primary,
              onTap: controller.isBusy ? null : page.onConnect,
            ),
          ],
        ),
        _PhoneGroup(
          title: 'Preferences',
          children: [
            _PhoneRow(
              icon: CupertinoIcons.bell,
              title: 'Notifications',
              value: preferences.notificationsEnabled ? 'On' : 'Off',
              chevron: true,
              onTap: () => _push(
                context,
                _PhoneNotificationsPage(controller: controller),
              ),
            ),
            _PhoneRow(
              icon: CupertinoIcons.paintbrush,
              title: 'Appearance',
              value: preferences.palette?.name ?? 'Classic',
              chevron: true,
              onTap: () =>
                  _push(context, _PhoneAppearancePage(controller: controller)),
            ),
            _PhoneRow(
              icon: CupertinoIcons.archivebox,
              title: 'Hidden conversations',
              value: '$hiddenCount',
              chevron: true,
              onTap: () => _push(
                context,
                _PhoneConversationListPage(
                  controller: controller,
                  hidden: true,
                  onOpen: page.onOpenConversation,
                ),
              ),
            ),
            _PhoneRow(
              icon: CupertinoIcons.bell_slash,
              title: 'Muted conversations',
              value: '$mutedCount',
              chevron: true,
              onTap: () => _push(
                context,
                _PhoneConversationListPage(
                  controller: controller,
                  hidden: false,
                  onOpen: page.onOpenConversation,
                ),
              ),
            ),
            _PhoneRow(
              icon: CupertinoIcons.tray_2,
              title: 'Storage',
              value: formatByteCount(controller.storageSummary.mediaBytes),
              chevron: true,
              onTap: () => _push(context, _PhoneStoragePage(page: page)),
            ),
            _PhoneSwitchRow(
              icon: CupertinoIcons.play_rectangle,
              title: 'Play Instagram Reels here',
              subtitle: 'Off: Reels show as thumbnails that open Instagram.',
              value: preferences.playsInstagramReels,
              onChanged: controller.isBusy
                  ? null
                  : (value) =>
                        controller.setPreference('playsInstagramReels', value),
            ),
            _PhoneSwitchRow(
              icon: CupertinoIcons.keyboard,
              title: 'Press Enter to send',
              subtitle:
                  'With a hardware keyboard. Off: Enter starts a new line.',
              value: preferences.enterToSend,
              onChanged: controller.isBusy
                  ? null
                  : (value) => controller.setPreference('enterToSend', value),
            ),
          ],
        ),
        _PhoneGroup(
          title: 'Help',
          children: [
            _PhoneRow(
              icon: CupertinoIcons.chat_bubble_text,
              title: 'Send feedback',
              chevron: true,
              onTap: () => _push(context, FeedbackPage(controller: controller)),
            ),
          ],
        ),
        _PhoneGroup(
          title: 'About',
          children: [
            _PhoneRow(
              title: 'Version',
              value: '$inboxPlusVersion ($inboxPlusBuild)',
            ),
            _PhoneRow(
              title: 'Open source licenses',
              chevron: true,
              onTap: () =>
                  showLicensePage(context: context, applicationName: 'Inbox+'),
            ),
          ],
        ),
        if (controller.error case final error?) ...[
          const SizedBox(height: 20),
          _Notice(message: error, isError: true),
        ],
      ],
    );
  }
}

class _PhoneGroup extends StatelessWidget {
  const _PhoneGroup({required this.children, this.title, this.footer});

  final String? title;
  final List<Widget> children;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title case final title?)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Semantics(
                header: true,
                child: Text(
                  title.toUpperCase(),
                  style: TextStyle(
                    fontSize: 12,
                    letterSpacing: .6,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Material(
              color: dark
                  ? scheme.surfaceContainer
                  : scheme.surfaceContainerLowest,
              child: Column(
                children: [
                  for (final (index, child) in children.indexed) ...[
                    if (index > 0)
                      Divider(
                        height: 1,
                        indent: 16,
                        color: scheme.outlineVariant.withValues(alpha: .5),
                      ),
                    child,
                  ],
                ],
              ),
            ),
          ),
          if (footer case final footer?)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: Text(
                footer,
                style: TextStyle(
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PhoneRow extends StatelessWidget {
  const _PhoneRow({
    super.key,
    required this.title,
    this.icon,
    this.leading,
    this.subtitle,
    this.subtitleColor,
    this.titleColor,
    this.value,
    this.trailing,
    this.chevron = false,
    this.onTap,
  });

  final String title;
  final IconData? icon;
  final Widget? leading;
  final String? subtitle;
  final Color? subtitleColor;
  final Color? titleColor;
  final String? value;
  final Widget? trailing;
  final bool chevron;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lead =
        leading ??
        (icon == null
            ? null
            : Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: scheme.onSurface.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 18, color: scheme.onSurface),
              ));
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
          child: Row(
            children: [
              if (lead != null) ...[lead, const SizedBox(width: 12)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(fontSize: 16, color: titleColor),
                    ),
                    if (subtitle case final subtitle?)
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: subtitleColor ?? scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (value case final value?)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 15,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ?trailing,
              if (chevron)
                Icon(
                  CupertinoIcons.chevron_right,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhoneSwitchRow extends StatelessWidget {
  const _PhoneSwitchRow({
    required this.title,
    required this.value,
    required this.onChanged,
    this.icon,
    this.subtitle,
  });

  final String title;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final IconData? icon;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: _PhoneRow(
      icon: icon,
      title: title,
      subtitle: subtitle,
      onTap: onChanged == null ? null : () => onChanged!(!value),
      trailing: Switch.adaptive(value: value, onChanged: onChanged),
    ),
  );
}

class _PhoneSegmented<T> extends StatelessWidget {
  const _PhoneSegmented({
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: label,
      container: true,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: scheme.onSurface.withValues(alpha: .07),
          borderRadius: BorderRadius.circular(19),
        ),
        child: Row(
          children: [
            for (final (option, text) in options)
              Expanded(
                child: Semantics(
                  selected: option == value,
                  button: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onChanged == null ? null : () => onChanged!(option),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      constraints: const BoxConstraints(minHeight: 32),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: option == value
                            ? scheme.onSurface.withValues(alpha: .16)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: option == value
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PhoneSegmentRow extends StatelessWidget {
  const _PhoneSegmentRow({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: const TextStyle(fontSize: 16)),
        const SizedBox(height: 8),
        child,
      ],
    ),
  );
}

class _PhoneSubpage extends StatelessWidget {
  const _PhoneSubpage({
    required this.title,
    required this.controller,
    required this.builder,
  });

  final String title;
  final InboxUiController controller;
  final List<Widget> Function(BuildContext context) builder;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(title),
      centerTitle: true,
      scrolledUnderElevation: 0,
    ),
    body: AnimatedBuilder(
      animation: controller,
      builder: (context, _) => ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          MediaQuery.paddingOf(context).bottom + 24,
        ),
        children: [
          if (controller.error case final error?) ...[
            const SizedBox(height: 12),
            _Notice(message: error, isError: true),
          ],
          ...builder(context),
        ],
      ),
    ),
  );
}

class _PhoneNotificationsPage extends StatelessWidget {
  const _PhoneNotificationsPage({required this.controller});

  final InboxUiController controller;

  @override
  Widget build(BuildContext context) => _PhoneSubpage(
    title: 'Notifications',
    controller: controller,
    builder: (context) {
      final preferences = controller.preferences;
      final busy = controller.isBusy;
      void set(String key, Object value) =>
          controller.setPreference(key, value);
      return [
        _PhoneGroup(
          footer: 'While Inbox+ is running, with device permission. Background notifications on phones are not available yet.',
          children: [
            _PhoneSwitchRow(
              title: 'Show notifications',
              value: preferences.notificationsEnabled,
              onChanged: busy
                  ? null
                  : (value) => set('notificationsEnabled', value),
            ),
            _PhoneSwitchRow(
              title: 'Show message previews',
              value: preferences.notificationPreviews,
              onChanged: busy
                  ? null
                  : (value) => set('notificationPreviews', value),
            ),
            _PhoneSwitchRow(
              title: 'Play a sound',
              value: preferences.notificationSound,
              onChanged: busy
                  ? null
                  : (value) => set('notificationSound', value),
            ),
            _PhoneSwitchRow(
              title: 'Unread count on app icon',
              value: preferences.showsUnreadBadge,
              onChanged: busy
                  ? null
                  : (value) => set('showsUnreadBadge', value),
            ),
          ],
        ),
        if (controller.notificationStatus.canOpenSettings)
          _PhoneGroup(
            children: [
              _PhoneRow(
                title: defaultTargetPlatform == TargetPlatform.iOS
                    ? 'Open iOS Settings'
                    : 'Open Android settings',
                subtitle: 'Sounds, banners and permission',
                chevron: true,
                onTap: controller.openNotificationSettings,
              ),
            ],
          ),
      ];
    },
  );
}

class _PhoneConversationListPage extends StatelessWidget {
  const _PhoneConversationListPage({
    required this.controller,
    required this.hidden,
    required this.onOpen,
  });

  final InboxUiController controller;
  final bool hidden;
  final ValueChanged<ConversationRoute> onOpen;

  @override
  Widget build(BuildContext context) => _PhoneSubpage(
    title: hidden ? 'Hidden conversations' : 'Muted conversations',
    controller: controller,
    builder: (context) {
      final now = DateTime.now();
      final chats = controller.conversations.where((chat) {
        final preferences = controller.preferencesFor(chat.route);
        return hidden
            ? preferences.hiddenAt != null
            : preferences.isMutedAt(now);
      }).toList();
      return [
        _PhoneGroup(
          footer: hidden
              ? 'Hidden conversations stay on this device. Restore one to show it in your inbox again.'
              : 'Muted conversations never notify and are left out of the unread badge.',
          children: [
            if (chats.isEmpty)
              _PhoneRow(
                title: hidden
                    ? 'No hidden conversations'
                    : 'No muted conversations',
              ),
            for (final chat in chats)
              Row(
                children: [
                  Expanded(
                    child: _PhoneRow(
                      title: chat.title,
                      onTap: () {
                        Navigator.of(context)
                            .popUntil((route) => route.isFirst);
                        onOpen(chat.route);
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: TextButton(
                      onPressed: controller.isBusy
                          ? null
                          : () => hidden
                                ? controller.setHidden(chat.route, false)
                                : controller.setMuted(chat.route, false),
                      child: Text(hidden ? 'Restore' : 'Unmute'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ];
    },
  );
}

class _PhoneStoragePage extends StatelessWidget {
  const _PhoneStoragePage({required this.page});

  final InboxSettingsPage page;

  @override
  Widget build(BuildContext context) => _PhoneSubpage(
    title: 'Storage',
    controller: page.controller,
    builder: (context) {
      final controller = page.controller;
      final summary = controller.storageSummary;
      final canClear = !controller.isBusy && summary.mediaBytes > 0;
      return [
        _PhoneGroup(
          children: [
            _PhoneRow(
              title: 'Downloaded media',
              subtitle: '${summary.attachmentCount} attachments',
              value: formatByteCount(summary.mediaBytes),
            ),
            _PhoneRow(
              title: 'Saved messages',
              value: '${summary.messageCount}',
            ),
          ],
        ),
        _PhoneGroup(
          footer: 'Messages, drafts and unsent attachments are kept.',
          children: [
            _PhoneRow(
              title: 'Clear downloaded media',
              titleColor: canClear ? Theme.of(context).colorScheme.error : null,
              onTap: canClear ? () => page._confirmClearCache(context) : null,
            ),
          ],
        ),
      ];
    },
  );
}

class _PhoneAppearancePage extends StatelessWidget {
  const _PhoneAppearancePage({required this.controller});

  final InboxUiController controller;

  @override
  Widget build(BuildContext context) => _PhoneSubpage(
    title: 'Appearance',
    controller: controller,
    builder: (context) {
      final preferences = controller.preferences;
      final scheme = Theme.of(context).colorScheme;
      final busy = controller.isBusy;
      void set(String key, Object value) =>
          controller.setPreference(key, value);
      final radius = switch (preferences.bubbleShape) {
        'soft' => 11.0,
        'square' => 5.0,
        _ => 17.0,
      };
      Widget bubble(String text, bool own) => Align(
        alignment: own ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: own ? scheme.primary : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(radius),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 15,
              color: own ? scheme.onPrimary : scheme.onSurface,
            ),
          ),
        ),
      );
      final themeAccent = switch (preferences.palette) {
        final palette? => Color(0xff000000 | palette.accent),
        null =>
          Theme.of(context).brightness == Brightness.dark
              ? const Color(0xfff3f3f3)
              : const Color(0xff202124),
      };
      Widget swatch({
        required String label,
        required Color color,
        required bool selected,
        required VoidCallback onTap,
        Widget? child,
      }) => Semantics(
        label: label,
        selected: selected,
        button: true,
        excludeSemantics: true,
        onTap: busy ? null : onTap,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: busy ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                border: Border.all(
                  width: 3,
                  color: selected ? scheme.onSurface : Colors.transparent,
                  strokeAlign: BorderSide.strokeAlignOutside,
                ),
              ),
              child: child,
            ),
          ),
        ),
      );
      return [
        const SizedBox(height: 8),
        Semantics(
          label: 'Preview of a conversation with your settings',
          container: true,
          excludeSemantics: true,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Column(
              children: [
                bubble('Save me a seat?', false),
                SizedBox(height: preferences.inboxDensity == 'compact' ? 4 : 8),
                bubble('Got one by the window', true),
              ],
            ),
          ),
        ),
        _PhoneGroup(
          title: 'Accent colour',
          footer: 'Changes buttons, unread badges and your message bubbles. Text on the accent turns light or dark to stay readable.',
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  swatch(
                    label: 'Theme accent',
                    color: themeAccent,
                    selected: preferences.accentOverride == null,
                    onTap: () => set('accentOverride', 'theme'),
                    child: Text(
                      'A',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: _legibleOnColor(themeAccent),
                      ),
                    ),
                  ),
                  for (final (value, name) in _accentChoices)
                    swatch(
                      label: '$name accent',
                      color: Color(0xff000000 | value),
                      selected: preferences.accentOverride == value,
                      onTap: () => set('accentOverride', value),
                    ),
                ],
              ),
            ),
          ],
        ),
        _PhoneGroup(
          title: 'Theme',
          children: [
            _PhoneSegmentRow(
              title: 'Mode',
              child: _PhoneSegmented<String>(
                label: 'Light or dark',
                options: const [
                  ('system', 'System'),
                  ('light', 'Light'),
                  ('dark', 'Dark'),
                ],
                value: preferences.appearance,
                onChanged: busy ? null : (value) => set('appearance', value),
              ),
            ),
            _PhoneRow(
              title: 'Theme',
              value: preferences.palette?.name ?? 'Classic',
              chevron: true,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => _PhoneSubpage(
                    title: 'Themes',
                    controller: controller,
                    builder: (context) => [
                      _PhoneGroup(
                        footer: 'A theme sets the background, logo and accent colours. A custom accent colour stays on top of it.',
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: _ThemeGrid(controller: controller),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        _PhoneGroup(
          title: 'Chats',
          children: [
            _PhoneSegmentRow(
              title: 'Bubble shape',
              child: _PhoneSegmented<String>(
                label: 'Bubble shape',
                options: const [
                  ('round', 'Round'),
                  ('soft', 'Soft'),
                  ('square', 'Square'),
                ],
                value: preferences.bubbleShape,
                onChanged: busy ? null : (value) => set('bubbleShape', value),
              ),
            ),
            _PhoneSegmentRow(
              title: 'Chat wallpaper',
              child: _PhoneSegmented<String>(
                label: 'Chat wallpaper',
                options: const [
                  ('none', 'None'),
                  ('tint', 'Tint'),
                  ('dots', 'Dots'),
                  ('grid', 'Grid'),
                ],
                value: preferences.chatWallpaper,
                onChanged: busy ? null : (value) => set('chatWallpaper', value),
              ),
            ),
          ],
        ),
        _PhoneGroup(
          title: 'Text & layout',
          children: [
            _PhoneSegmentRow(
              title: 'Text size',
              child: _PhoneSegmented<String>(
                label: 'Text size',
                options: const [
                  ('small', 'Small'),
                  ('default', 'Default'),
                  ('large', 'Large'),
                ],
                value: preferences.textSize,
                onChanged: busy ? null : (value) => set('textSize', value),
              ),
            ),
            _PhoneSegmentRow(
              title: 'Inbox density',
              child: _PhoneSegmented<String>(
                label: 'Inbox density',
                options: const [
                  ('comfortable', 'Comfortable'),
                  ('compact', 'Compact'),
                ],
                value: preferences.inboxDensity,
                onChanged: busy ? null : (value) => set('inboxDensity', value),
              ),
            ),
          ],
        ),
      ];
    },
  );
}

const _accentChoices = [
  (0x3d5bd9, 'Blue'),
  (0x00838f, 'Teal'),
  (0x2e7d4f, 'Green'),
  (0xb07a00, 'Gold'),
  (0xd2553a, 'Orange'),
  (0xc2185b, 'Pink'),
  (0x7b4fd6, 'Purple'),
];

Color _legibleOnColor(Color color) =>
    color.computeLuminance() > .179 ? Colors.black : Colors.white;

class FeedbackPage extends StatefulWidget {
  const FeedbackPage({super.key, required this.controller});

  final InboxUiController controller;

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  final _form = FeedbackForm();
  bool _attaching = false;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _form.dispose();
    super.dispose();
  }

  Future<void> _attachScreenshot() async {
    setState(() {
      _attaching = true;
      _error = null;
    });
    try {
      final image = await chooseFeedbackImage(widget.controller);
      if (mounted && image != null) setState(() => _form.image = image);
    } on Exception catch (error) {
      if (mounted) setState(() => _error = feedbackImageError(error));
    } finally {
      if (mounted) setState(() => _attaching = false);
    }
  }

  Future<void> _send() async {
    final draft = _form.draft;
    if (draft == null || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final receipt = await widget.controller.sendFeedback(draft);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            draft.kind.isPublic
                ? 'Thanks. Your feedback is posted on GitHub.'
                : 'Thanks. Your feedback was sent.',
          ),
          action: switch (receipt.issueUrl) {
            final url? => SnackBarAction(
              label: 'View',
              onPressed: () =>
                  launchUrl(url, mode: LaunchMode.externalApplication),
            ),
            null => null,
          },
        ),
      );
    } on FeedbackFailure catch (failure) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = failure.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final kind = _form.kind;
    final image = _form.image;
    final editable = !_sending;
    final supporting = TextStyle(fontSize: 13, color: scheme.onSurfaceVariant);
    return PopScope(
      canPop: !_sending,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: !_sending,
          title: const Text('Send feedback'),
          centerTitle: true,
          scrolledUnderElevation: 0,
        ),
        body: ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            8,
            16,
            MediaQuery.paddingOf(context).bottom + 24,
          ),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in FeedbackKind.values)
                  ChoiceChip(
                    key: Key('feedback-kind-${option.wireName}'),
                    label: Text(option.label),
                    selected: kind == option,
                    onSelected: editable
                        ? (_) => setState(() => _form.kind = option)
                        : null,
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(switch (kind) {
              null => 'Bugs, requests and suggestions are posted publicly on GitHub. Praise is sent privately.',
              FeedbackKind(isPublic: true) =>
                'Posted publicly on GitHub. Don’t include private messages.',
              _ => 'Sent privately to the developer.',
            }, style: supporting),
            const SizedBox(height: 8),
            Text(feedbackDiagnosticsNotice, style: supporting),
            const SizedBox(height: 12),
            TextField(
              key: const Key('feedback-text'),
              controller: _form.text,
              enabled: editable,
              minLines: 5,
              maxLines: 10,
              maxLength: 5000,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Tell us what went wrong, or share general feedback.',
                counterText: '',
              ),
            ),
            _PhoneGroup(
              children: [
                if (image != null)
                  _PhoneRow(
                    key: const Key('feedback-screenshot'),
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.memory(
                        image,
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                        cacheWidth: 120,
                      ),
                    ),
                    title: 'Screenshot',
                    subtitle: 'Sent with your feedback.',
                    trailing: IconButton(
                      tooltip: 'Remove screenshot',
                      icon: const Icon(CupertinoIcons.xmark_circle_fill),
                      onPressed: editable
                          ? () => setState(() => _form.image = null)
                          : null,
                    ),
                  )
                else
                  _PhoneRow(
                    key: const Key('feedback-attach-screenshot'),
                    icon: CupertinoIcons.photo,
                    title: 'Attach a screenshot',
                    subtitle: 'Choose a photo that shows the problem.',
                    chevron: true,
                    onTap: editable && !_attaching ? _attachScreenshot : null,
                  ),
              ],
            ),
            if (_error case final error?) ...[
              const SizedBox(height: 12),
              Text(error, style: TextStyle(color: scheme.error)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('feedback-send'),
              onPressed: _form.draft != null && editable && !_attaching
                  ? _send
                  : null,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
              child: Text(_sending ? 'Sending…' : 'Send feedback'),
            ),
          ],
        ),
      ),
    );
  }
}
