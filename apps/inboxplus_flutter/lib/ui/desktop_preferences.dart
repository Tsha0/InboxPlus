part of 'inbox_app.dart';

Color _legibleOn(Color color) =>
    color.computeLuminance() > .179 ? Colors.black : Colors.white;

class _DesktopPalette {
  _DesktopPalette(InboxThemePalette palette)
    : id = palette.id,
      name = palette.name,
      background = Color(0xff000000 | palette.background),
      accent = Color(0xff000000 | palette.accent),
      logo = Color(0xff000000 | palette.logo);

  final String id;
  final String name;
  final Color background;
  final Color accent;
  final Color logo;
  static final presets = InboxThemePalette.presets
      .map(_DesktopPalette.new)
      .toList();
  static _DesktopPalette? forPreferences(PreferencesRecord preferences) {
    final palette = preferences.palette;
    return palette == null ? null : _DesktopPalette(palette);
  }
}

class _DesktopLogo extends StatelessWidget {
  const _DesktopLogo({required this.color, this.size = 32, this.turns = 0});
  final Color color;
  final double size;
  final double turns;

  @override
  Widget build(BuildContext context) {
    final foreground = _legibleOn(color);
    final filter = <double>[
      0,
      0,
      0,
      0,
      foreground.r * 255,
      0,
      0,
      0,
      0,
      foreground.g * 255,
      0,
      0,
      0,
      0,
      foreground.b * 255,
      .2126,
      .7152,
      .0722,
      0,
      0,
    ];
    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 4),
      child: ColoredBox(
        color: color,
        child: Transform.rotate(
          key: const Key('desktop-logo-mark'),
          angle: turns * math.pi * 2,
          child: ColorFiltered(
            colorFilter: ColorFilter.matrix(filter),
            child: Image.asset(
              'assets/inboxplus-logo.png',
              width: size,
              height: size,
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopPreferences extends StatelessWidget {
  const _DesktopPreferences({required this.controller});
  final InboxUiController controller;

  @override
  Widget build(BuildContext context) {
    final preferences = controller.preferences;
    final notifications = controller.notificationStatus;
    final muted = controller.conversations
        .where(
          (c) => controller.preferencesFor(c.route).isMutedAt(DateTime.now()),
        )
        .toList();
    final buttons = Theme.of(context).textButtonTheme.style?.copyWith(
      backgroundColor: WidgetStatePropertyAll(
        Theme.of(context).colorScheme.surfaceContainer,
      ),
    );
    return TextButtonTheme(
      data: TextButtonThemeData(style: buttons),
      child: ListView(
        key: const Key('desktop-preferences'),
        padding: const EdgeInsets.all(20),
        children: [
          _DesktopPreferenceGroup(
            title: 'Notifications',
            footer: 'Mute a conversation with the bell at the top of it, or by right-clicking it in the inbox. Muted conversations never notify and are left out of the unread badge.',
            children: [
              _toggle(
                'Show notifications',
                preferences.notificationsEnabled,
                'notificationsEnabled',
                enabled: notifications.canConfigure,
              ),
              _toggle(
                'Show message previews',
                preferences.notificationPreviews,
                'notificationPreviews',
                enabled:
                    preferences.notificationsEnabled &&
                    notifications.canConfigure,
              ),
              _toggle(
                'Play a sound',
                preferences.notificationSound,
                'notificationSound',
                enabled:
                    preferences.notificationsEnabled &&
                    notifications.canConfigure &&
                    notifications.soundEnabled != false,
              ),
              if (_notificationWarning != null)
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_notificationWarning!),
                      const SizedBox(height: 8),
                      if (notifications.authorization ==
                          NotificationAuthorization.notDetermined)
                        TextButton(
                          onPressed: controller.isBusy
                              ? null
                              : controller.requestNotificationPermission,
                          child: const Text('Allow Notifications…'),
                        ),
                      if (notifications.canOpenSettings)
                        TextButton(
                          onPressed: controller.isBusy
                              ? null
                              : controller.openNotificationSettings,
                          child: const Text('Open Notifications Settings…'),
                        ),
                    ],
                  ),
                ),
              _row(
                'Muted conversations',
                trailing: Text(
                  muted.isEmpty ? 'None' : '${muted.length}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              for (final conversation in muted)
                _row(
                  conversation.title,
                  trailing: TextButton(
                    onPressed: () =>
                        controller.setMuted(conversation.route, false),
                    child: const Text('Unmute'),
                  ),
                ),
            ],
          ),
          _DesktopPreferenceGroup(
            title: 'Appearance',
            footer: 'Pick a theme or mix your own. Text on colored backgrounds turns light or dark to stay readable.',
            children: [
              _row('Appearance', trailing: _appearance(context)),
              Padding(
                padding: const EdgeInsets.all(10),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = (constraints.maxWidth / 100).floor().clamp(
                      2,
                      6,
                    );
                    final width =
                        (constraints.maxWidth - (columns - 1) * 12) / columns;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final palette in [
                          ..._DesktopPalette.presets,
                          if (preferences.themePreset == 'custom')
                            _DesktopPalette(preferences.palette!),
                        ])
                          SizedBox(
                            width: width,
                            child: _themeChoice(context, palette),
                          ),
                      ],
                    );
                  },
                ),
              ),
              for (final (index, label) in [
                'Background',
                'Accent',
                'Logo',
              ].indexed)
                _row(label, trailing: _colorButton(context, index, label)),
              _row(
                '',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: _surprise,
                      child: const Text('Surprise Me'),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: preferences.themePreset == 'classic'
                          ? null
                          : () => controller.setPreference(
                              'themePreset',
                              'classic',
                            ),
                      child: const Text('Reset to Classic'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          _DesktopPreferenceGroup(
            title: 'General',
            children: [
              _row(
                'Open Inbox+ at login',
                trailing: _switch(
                  context,
                  'Open Inbox+ at login',
                  {
                    'on',
                    'needsApproval',
                  }.contains(controller.launchAtLoginStatus),
                  controller.isBusy ||
                          controller.launchAtLoginStatus == 'unavailable'
                      ? null
                      : (value) =>
                            controller.setPreference('launchAtLogin', value),
                ),
              ),
              if (controller.launchAtLoginStatus == 'unavailable')
                _footnote(
                  context,
                  'Available once Inbox+ is installed as an app.',
                ),
              if (controller.launchAtLoginStatus == 'needsApproval')
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Allow Inbox+ in Login Items to finish turning this on.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      TextButton(
                        onPressed: controller.openLoginItemsSettings,
                        child: const Text('Open Login Items…'),
                      ),
                    ],
                  ),
                ),
              _toggle(
                defaultTargetPlatform == TargetPlatform.macOS
                    ? 'Show the unread count in the Dock and menu bar'
                    : 'Show the unread count in the taskbar and tray',
                preferences.showsUnreadBadge,
                'showsUnreadBadge',
              ),
              if (defaultTargetPlatform == TargetPlatform.macOS &&
                  (notifications.authorization ==
                          NotificationAuthorization.denied ||
                      notifications.badgesEnabled == false))
                _footnote(
                  context,
                  'Dock badges may also be blocked by macOS. The menu bar count still works.',
                ),
            ],
          ),
          _DesktopPreferenceGroup(
            title: 'Instagram Reels',
            footer: 'When off, Reels appear as labeled thumbnails that open in Instagram. When on, available videos play here when you press Play.',
            children: [
              _toggle(
                'Play Instagram Reels in Inbox+',
                preferences.playsInstagramReels,
                'playsInstagramReels',
              ),
            ],
          ),
          _DesktopPreferenceGroup(
            title: 'Storage',
            children: [
              _row(
                'Downloaded media',
                trailing: Text(
                  formatByteCount(controller.storageSummary.mediaBytes),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Photos, videos and files download again when you open them.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed:
                          controller.isBusy ||
                              controller.storageSummary.mediaBytes == 0
                          ? null
                          : () => _clearCache(context),
                      child: const Text('Clear Cache…'),
                    ),
                  ],
                ),
              ),
              _row(
                'Keep messages for',
                trailing: _choice<int>(
                  'Keep messages for',
                  preferences.messageRetentionDays,
                  'messageRetentionDays',
                  const {
                    1: '1 day',
                    7: '1 week',
                    30: '1 month',
                    90: '3 months',
                    365: '1 year',
                  },
                ),
              ),
              _footnote(
                context,
                'Older messages are deleted from this device and stay on the network. iMessage uses its own history below. Applies the next time Inbox+ opens.',
              ),
              if (defaultTargetPlatform == TargetPlatform.macOS) ...[
                _row(
                  'iMessage history',
                  trailing: _choice<String>(
                    'iMessage history',
                    preferences.iMessageHistory,
                    'iMessageHistory',
                    const {
                      'month': '1 month',
                      'quarter': '3 months',
                      'year': '1 year',
                      'all': 'All history',
                    },
                  ),
                ),
                _footnote(
                  context,
                  'Chats with nothing newer are left out of the inbox. Applies the next time Inbox+ opens.',
                ),
              ],
            ],
          ),
          _DesktopPreferenceGroup(
            title: 'About',
            children: [
              _row('Version', trailing: const Text(inboxPlusVersion)),
              _row('Build', trailing: const Text(inboxPlusBuild)),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'App settings and component status with account identifiers, tokens, cookies, messages and links left out, safe to attach to a bug report.',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(height: 1.5),
                      ),
                    ),
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: controller.isBusy
                          ? null
                          : controller.exportDiagnostics,
                      child: const Text('Export Diagnostics…'),
                    ),
                  ],
                ),
              ),
              _row(
                'Open source licenses',
                trailing: TextButton(
                  onPressed: () => showLicensePage(
                    context: context,
                    applicationName: 'Inbox+',
                  ),
                  child: const Text('View…'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _choice<T extends Object>(
    String label,
    T value,
    String key,
    Map<T, String> options,
  ) => Semantics(
    container: true,
    button: true,
    label: label,
    value: options[value],
    child: PopupMenuButton<T>(
      enabled: !controller.isBusy,
      tooltip: '',
      initialValue: value,
      onSelected: (value) => controller.setPreference(key, value),
      itemBuilder: (_) => [
        for (final entry in options.entries)
          PopupMenuItem(
            value: entry.key,
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  child: entry.key == value
                      ? const Icon(Icons.check, size: 13)
                      : null,
                ),
                Text(entry.value),
              ],
            ),
          ),
      ],
      child: ExcludeSemantics(
        child: Builder(
          builder: (context) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                options[value] ?? '',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface
                      .withValues(alpha: .7),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Icon(
                  Icons.unfold_more,
                  size: 13,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _footnote(BuildContext context, String message) => Padding(
    padding: const EdgeInsets.all(10),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.5),
      ),
    ),
  );

  String? get _notificationWarning {
    final status = controller.notificationStatus;
    final restrictions = [
      if (status.alertsEnabled == false)
        'Notification banners are turned off for Inbox+ in System Settings.',
      if (status.soundEnabled == false)
        'Notification sounds are turned off for Inbox+ in System Settings.',
    ];
    final system = defaultTargetPlatform == TargetPlatform.macOS
        ? 'macOS'
        : 'Your system';
    return switch (status.authorization) {
      NotificationAuthorization.denied =>
        '$system is blocking Inbox+ notifications. Enable them in System Settings.',
      NotificationAuthorization.notDetermined =>
        'Allow Inbox+ to show notifications in the system permission prompt.',
      NotificationAuthorization.unavailable => 'Notification permission could not be checked on this desktop. Delivery depends on your system notification settings.',
      NotificationAuthorization.allowed =>
        restrictions.isEmpty ? null : restrictions.join('\n'),
    };
  }

  Widget _toggle(String label, bool value, String key, {bool enabled = true}) =>
      _row(
        label,
        trailing: Builder(
          builder: (context) => _switch(
            context,
            label,
            value,
            controller.isBusy || !enabled
                ? null
                : (value) => controller.setPreference(key, value),
          ),
        ),
      );

  Widget _switch(
    BuildContext context,
    String label,
    bool value,
    ValueChanged<bool>? onChanged,
  ) => Semantics(
    label: label,
    child: SizedBox(
      width: 40,
      height: 24,
      child: FittedBox(
        child: CupertinoSwitch(
          value: value,
          activeTrackColor: _DesktopWindowActive.of(context)
              ? Theme.of(context).colorScheme.primary
              : const Color(0xffa3a3a3),
          onChanged: onChanged,
        ),
      ),
    ),
  );

  Widget _row(String title, {required Widget trailing}) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 38),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(title)),
          const SizedBox(width: 12),
          trailing,
        ],
      ),
    ),
  );

  Widget _appearance(BuildContext context) => Container(
    padding: const EdgeInsets.all(1),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final value in ['system', 'light', 'dark'])
          Semantics(
            selected: controller.preferences.appearance == value,
            child: TextButton(
              style: TextButton.styleFrom(
                backgroundColor: controller.preferences.appearance != value
                    ? Colors.transparent
                    : _DesktopWindowActive.of(context)
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurface
                          .withValues(alpha: .12),
                foregroundColor:
                    controller.preferences.appearance == value &&
                        _DesktopWindowActive.of(context)
                    ? Theme.of(context).colorScheme.onPrimary
                    : null,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 3,
                ),
                minimumSize: const Size(0, 23),
              ),
              onPressed: () => controller.setPreference('appearance', value),
              child: Text('${value[0].toUpperCase()}${value.substring(1)}'),
            ),
          ),
      ],
    ),
  );

  Widget _themeChoice(BuildContext context, _DesktopPalette palette) =>
      Semantics(
        label: '${palette.name} theme',
        selected: controller.preferences.themePreset == palette.id,
        button: true,
        child: InkWell(
          onTap: () => controller.setPreference('themePreset', palette.id),
          borderRadius: BorderRadius.circular(8),
          child: Column(
            children: [
              Container(
                height: 52,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Color.alphaBlend(
                    palette.background.withValues(alpha: .08),
                    Theme.of(context).colorScheme.surfaceContainerLow,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: controller.preferences.themePreset == palette.id
                        ? Theme.of(context).colorScheme.onSurface
                        : Theme.of(context).dividerColor,
                    width: controller.preferences.themePreset == palette.id
                        ? 2.5
                        : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 18,
                      color: palette.background,
                      alignment: Alignment.topCenter,
                      padding: const EdgeInsets.only(top: 5),
                      child: _DesktopLogo(color: palette.logo, size: 11),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(7),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 30,
                              height: 7,
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.onSurface
                                    .withValues(alpha: .10),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Align(
                              alignment: Alignment.centerRight,
                              child: Container(
                                width: 34,
                                height: 7,
                                decoration: BoxDecoration(
                                  color: palette.accent,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              width: 22,
                              height: 7,
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.onSurface
                                    .withValues(alpha: .10),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 5),
              Text(
                palette.name,
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 1,
              ),
            ],
          ),
        ),
      );

  Future<void> _surprise() {
    final random = math.Random();
    final hue = random.nextDouble() * 360;
    final light = random.nextBool();
    int color(double offset, double saturation, double brightness) =>
        HSVColor.fromAHSV(
          1,
          (hue + offset) % 360,
          saturation,
          brightness,
        ).toColor().toARGB32() &
        0xffffff;
    return controller.setPreference('customColors', [
      color(0, light ? .2 : .6, light ? .97 : .3),
      color(14.4, light ? .75 : .65, light ? .78 : .88),
      color(180, light ? .7 : .65, light ? .75 : .95),
    ]);
  }

  List<int> _colors(BuildContext context) {
    final palette = _DesktopPalette.forPreferences(controller.preferences);
    return palette == null
        ? Theme.of(context).brightness == Brightness.dark
              ? [0x2a2a2e, 0xf5f5f7, 0x000000]
              : [0xe8e8ed, 0x1d1d1f, 0x000000]
        : [
            palette.background.toARGB32() & 0xffffff,
            palette.accent.toARGB32() & 0xffffff,
            palette.logo.toARGB32() & 0xffffff,
          ];
  }

  Widget _colorButton(BuildContext context, int index, String label) =>
      Semantics(
        label: '$label color',
        button: true,
        child: InkWell(
          onTap: () => _chooseColor(context, index, label),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 46,
            height: 23,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color(0xff000000 | _colors(context)[index]),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: Theme.of(context).colorScheme.onSurface
                      .withValues(alpha: .15),
                ),
              ),
            ),
          ),
        ),
      );

  Future<void> _chooseColor(
    BuildContext context,
    int index,
    String label,
  ) async {
    final colors = _colors(context);
    final input = TextEditingController(
      text: colors[index].toRadixString(16).padLeft(6, '0').toUpperCase(),
    );
    final chosen = await showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final hex = input.text.replaceFirst('#', '').trim();
          final value = RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)
              ? int.parse(hex, radix: 16)
              : null;
          return AlertDialog(
            title: Text('$label color'),
            content: TextField(
              controller: input,
              autofocus: true,
              maxLength: 7,
              decoration: const InputDecoration(
                labelText: 'Hex color',
                prefixText: '#',
              ),
              onChanged: (_) => setState(() {}),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: value == null
                    ? null
                    : () => Navigator.pop(context, value),
                child: const Text('Choose'),
              ),
            ],
          );
        },
      ),
    );
    input.dispose();
    if (chosen != null) {
      colors[index] = chosen;
      await controller.setPreference('customColors', colors);
    }
  }

  Future<void> _clearCache(BuildContext context) async {
    if (await confirmClearMediaCache(context)) {
      await controller.clearMediaCache();
    }
  }
}

class _DesktopPreferenceGroup extends StatelessWidget {
  const _DesktopPreferenceGroup({
    required this.title,
    required this.children,
    this.footer,
  });
  final String title;
  final List<Widget> children;
  final String? footer;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 30),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 10, bottom: 12),
          child: Text(
            title,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              for (final (index, child) in children.indexed) ...[
                if (index > 0) const Divider(indent: 10, endIndent: 10),
                child,
              ],
            ],
          ),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
            child: Text(
              footer!,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(height: 1.5),
            ),
          ),
      ],
    ),
  );
}
