part of 'inbox_app.dart';

ThemeData _desktopTheme(Brightness brightness, PreferencesRecord preferences) {
  final dark = brightness == Brightness.dark;
  final ink = dark ? Colors.white : Colors.black;
  final palette = _DesktopPalette.forPreferences(preferences);
  final accent = palette?.accent ?? ink;
  final paper = dark ? const Color(0xff1e1e1e) : Colors.white;
  final scheme = ColorScheme.fromSeed(seedColor: ink, brightness: brightness)
      .copyWith(
        primary: accent,
        onPrimary: _legibleOn(accent),
        surface: paper,
        onSurface: dark ? const Color(0xffededed) : const Color(0xff262626),
        onSurfaceVariant: const Color(0xff858585),
        surfaceContainerLow: dark
            ? const Color(0xff292929)
            : const Color(0xfff4f4f4),
        surfaceContainer: dark
            ? const Color(0xff363636)
            : const Color(0xffe7e7e7),
        surfaceContainerHighest: dark
            ? const Color(0xff414141)
            : const Color(0xffdfdfdf),
        outlineVariant: dark
            ? const Color(0xff414141)
            : const Color(0xffe5e5e5),
      );
  final font = defaultTargetPlatform == TargetPlatform.macOS
      ? 'CupertinoSystemText'
      : null;
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: paper,
    fontFamily: font,
    visualDensity: VisualDensity.compact,
    textTheme: TextTheme(
      bodyMedium: TextStyle(
        fontSize: 13,
        fontFamily: font,
        height: 1.2,
        letterSpacing: 0,
      ),
      bodyLarge: TextStyle(
        fontSize: 13,
        fontFamily: font,
        height: 1.2,
        letterSpacing: 0,
      ),
      bodySmall: TextStyle(
        fontSize: 11,
        fontFamily: font,
        height: 1.2,
        letterSpacing: 0,
        color: scheme.onSurfaceVariant,
      ),
      titleMedium: TextStyle(
        fontSize: 13,
        fontFamily: font,
        height: 1.2,
        letterSpacing: 0,
        fontWeight: FontWeight.w600,
      ),
      titleLarge: TextStyle(
        fontSize: 17,
        fontFamily: font,
        height: 1.2,
        letterSpacing: 0,
        fontWeight: FontWeight.w700,
      ),
      labelLarge: TextStyle(
        fontSize: 13,
        fontFamily: font,
        height: 1.2,
        letterSpacing: 0,
      ),
    ),
    dividerColor: scheme.outlineVariant,
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    iconTheme: IconThemeData(size: 17, color: scheme.onSurfaceVariant),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(24, 24),
        maximumSize: const Size(30, 30),
        padding: EdgeInsets.zero,
        iconSize: 17,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.standard,
        foregroundColor: scheme.onSurface,
        backgroundColor: scheme.surfaceContainerLow,
        minimumSize: const Size(0, 24),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      isDense: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    ),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 500),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: dark ? const Color(0xff2b2b2b) : const Color(0xfff7f7f7),
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      menuPadding: const EdgeInsets.all(5),
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: scheme.outlineVariant, width: .5),
      ),
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(fontSize: 13, fontFamily: font, color: scheme.onSurface),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: dark ? const Color(0xff2b2b2b) : const Color(0xfff7f7f7),
      surfaceTintColor: Colors.transparent,
    ),
  );
}

class _DesktopLogoButton extends StatefulWidget {
  const _DesktopLogoButton({required this.color, required this.glowColor});

  final Color color;
  final Color glowColor;

  @override
  State<_DesktopLogoButton> createState() => _DesktopLogoButtonState();
}

class _DesktopLogoButtonState extends State<_DesktopLogoButton>
    with TickerProviderStateMixin {
  late final _rotation = AnimationController.unbounded(vsync: this);
  late final _glow = AnimationController(vsync: this);
  late final _animation = Listenable.merge([_rotation, _glow]);
  Timer? _fade;
  double _turns = 0;
  bool _hovering = false;
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) {
      _turns = 0;
      _rotation.value = 0;
    }
  }

  void _play() {
    if (!_reduceMotion) {
      _turns += 1;
      _rotation.animateTo(
        _turns,
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOut,
      );
    }
    _glow.animateTo(
      1,
      duration: const Duration(milliseconds: 130),
      curve: Curves.easeOut,
    );
    _fade?.cancel();
    _fade = Timer(const Duration(milliseconds: 180), () {
      _glow.animateTo(
        0,
        duration: const Duration(milliseconds: 850),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _fade?.cancel();
    _rotation.dispose();
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Animate the Inbox+ logo',
    child: Semantics(
      label: 'Inbox+ logo',
      hint: _reduceMotion ? 'Glow the logo' : 'Spin and glow the logo',
      button: true,
      onTap: _play,
      excludeSemantics: true,
      child: TextButton(
        onPressed: _play,
        onHover: (value) => setState(() => _hovering = value),
        style: TextButton.styleFrom(
          backgroundColor: Colors.transparent,
          padding: EdgeInsets.zero,
          minimumSize: const Size.square(32),
          maximumSize: const Size.square(32),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          overlayColor: Colors.transparent,
        ),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: _hovering ? 1 : 0),
          duration: _reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          builder: (context, hover, _) => AnimatedBuilder(
            animation: _animation,
            builder: (context, _) {
              final glow = _glow.value;
              return Transform.scale(
                scale: _reduceMotion ? 1 : 1 + hover * .04 + glow * .04,
                child: DecoratedBox(
                  key: const Key('desktop-logo-glow'),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: widget.glowColor.withValues(alpha: glow * .4),
                        blurRadius: glow * 7,
                      ),
                    ],
                  ),
                  child: DecoratedBox(
                    position: DecorationPosition.foreground,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _legibleOn(widget.color)
                            .withValues(alpha: glow * .45),
                      ),
                    ),
                    child: _DesktopLogo(
                      color: widget.color,
                      turns: _rotation.value,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
}

/// Whether the window is the one taking input, which macOS shows by tinting switches and selected
/// segments with the accent and greying them otherwise.
class _DesktopWindowActive extends InheritedWidget {
  const _DesktopWindowActive({required this.active, required super.child});
  final bool active;

  static bool of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_DesktopWindowActive>()
          ?.active ??
      true;

  @override
  bool updateShouldNotify(_DesktopWindowActive old) => active != old.active;
}

class _DesktopHome extends StatefulWidget {
  const _DesktopHome({required this.controller});
  final InboxUiController controller;
  @override
  State<_DesktopHome> createState() => _DesktopHomeState();
}

class _DesktopHomeState extends State<_DesktopHome> {
  _Section _section = _Section.inbox;
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _networks = <String>{};
  bool _unreadOnly = false;
  bool _unknownOnly = false;
  bool _hidden = false;
  String? _personId;
  String? _highlightedMessageId;
  bool _windowActive =
      WidgetsBinding.instance.lifecycleState != AppLifecycleState.inactive;
  late final AppLifecycleListener _lifecycle;
  late int _notificationActivation;
  InboxUiController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _notificationActivation = controller.notificationActivation;
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        setState(() => _windowActive = state == AppLifecycleState.resumed);
        if (state == AppLifecycleState.resumed) {
          controller.refreshNotificationStatus();
        }
      },
    );
  }

  @override
  void didUpdateWidget(covariant _DesktopHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_notificationActivation != controller.notificationActivation) {
      _notificationActivation = controller.notificationActivation;
      _section = _Section.inbox;
      _personId = null;
      _highlightedMessageId = null;
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _connect() => showDialog<void>(
    context: context,
    builder: (_) => ConnectAccountsDialog(controller: controller),
  );
  Future<void> _compose() async {
    final opened = await showDialog<bool>(
      context: context,
      builder: (_) =>
          NewConversationDialog(controller: controller, desktop: true),
    );
    if (opened == true && mounted) {
      setState(() {
        _section = _Section.inbox;
        _personId = null;
      });
    }
  }

  void _sectionChanged(_Section section) {
    setState(() => _section = section);
    if (section == _Section.settings) controller.refreshNotificationStatus();
  }

  void _focusSearch() {
    _sectionChanged(_Section.inbox);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _searchFocus.requestFocus(),
    );
  }

  ContactRecord? _owner(ConversationRecord conversation) => controller.contacts
      .where(
        (person) => person.identities.any(
          (identity) =>
              identity.accountId == conversation.route.accountId &&
              identity.identityId == conversation.identityId,
        ),
      )
      .firstOrNull;
  List<ConversationRecord> _chatsFor(ContactRecord person) => controller
      .conversations
      .where(
        (chat) => person.identities.any(
          (identity) =>
              identity.accountId == chat.route.accountId &&
              identity.identityId == chat.identityId,
        ),
      )
      .toList();
  String _preview(ConversationRecord chat) {
    final draft = controller.draftFor(chat.route);
    if (draft != null &&
        (draft.body.isNotEmpty || draft.attachments.isNotEmpty)) {
      return 'Draft: ${draft.body.isEmpty ? 'Attachment' : draft.body}';
    }
    final last = controller.messagesFor(chat.route).lastOrNull;
    if (last == null) return '';
    final body = last.body.isEmpty ? 'Attachment' : last.body;
    return chat.isGroup && !last.isOutgoing && last.senderName != null
        ? '${last.senderName}: $body'
        : body;
  }

  Iterable<ConversationRecord> get _scopedChats =>
      controller.conversations.where((chat) {
        if ((controller.preferencesFor(chat.route).hiddenAt != null) !=
            _hidden) {
          return false;
        }
        if (_networks.isNotEmpty &&
            !_networks.contains(
              _accountFor(controller, chat.route)?.platform,
            )) {
          return false;
        }
        final unknown = _owner(chat) == null && chat.isFromUnknownSender;
        return unknown == _unknownOnly;
      });

  List<_DesktopInboxItem> get _items {
    final grouped = <String, _DesktopInboxItem>{};
    final query = _search.text.trim().toLowerCase();
    for (final chat in _scopedChats) {
      final person = _owner(chat);
      final id =
          person?.id ?? '${chat.route.accountId}/${chat.route.conversationId}';
      final item = grouped.putIfAbsent(id, () => _DesktopInboxItem(person, []));
      item.chats.add(chat);
    }
    return grouped.values.where((item) {
      if (_unreadOnly && item.unread(controller) == 0) return false;
      return query.isEmpty || item.title.toLowerCase().contains(query);
    }).toList()..sort((a, b) {
      final star = b
          .favorite(controller)
          .toString()
          .compareTo(a.favorite(controller).toString());
      return star != 0
          ? star
          : b.latest.latestActivity.compareTo(a.latest.latestActivity);
    });
  }

  List<({ConversationRecord chat, MessageRecord message})> get _messageMatches {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return [];
    final matches = [
      for (final chat in _scopedChats)
        for (final message in controller.messagesFor(chat.route))
          if (message.body.toLowerCase().contains(query))
            (chat: chat, message: message),
    ]..sort((a, b) => b.message.timestamp.compareTo(a.message.timestamp));
    return matches.take(100).toList();
  }

  void _selectItem(_DesktopInboxItem item) {
    setState(() {
      _personId = item.person?.id;
      _highlightedMessageId = null;
    });
    if (_personId != null) {
      controller.selectConversation(null);
    } else {
      controller.selectConversation(item.latest.route);
    }
  }

  void _navigate(bool next) {
    final chats = _items.expand((item) => item.chats).toList();
    if (chats.isEmpty) return;
    final index = chats.indexWhere(
      (chat) => chat.route == controller.selectedRoute,
    );
    setState(() {
      _section = _Section.inbox;
      _personId = null;
      _highlightedMessageId = null;
    });
    controller.selectConversation(
      chats[index < 0
              ? (next ? 0 : chats.length - 1)
              : (index + (next ? 1 : chats.length - 1)) % chats.length]
          .route,
    );
  }

  void _toggleUnread() {
    final chats = controller.selectedRoute == null
        ? controller.contacts
              .where((p) => p.id == _personId)
              .expand(_chatsFor)
              .toList()
        : controller.conversations
              .where((c) => c.route == controller.selectedRoute)
              .toList();
    final unread = chats.any(
      (c) =>
          c.unreadCount > 0 || controller.preferencesFor(c.route).markedUnread,
    );
    for (final chat in chats) {
      controller.setUnread(chat.route, !unread);
    }
  }

  @override
  Widget build(BuildContext context) => _withMenus(
    CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.digit1, meta: true): () =>
            _sectionChanged(_Section.inbox),
        const SingleActivator(LogicalKeyboardKey.digit2, meta: true): () =>
            _sectionChanged(_Section.contacts),
        const SingleActivator(LogicalKeyboardKey.digit3, meta: true): () =>
            _sectionChanged(_Section.settings),
        const SingleActivator(LogicalKeyboardKey.digit1, control: true): () =>
            _sectionChanged(_Section.inbox),
        const SingleActivator(LogicalKeyboardKey.digit2, control: true): () =>
            _sectionChanged(_Section.contacts),
        const SingleActivator(LogicalKeyboardKey.digit3, control: true): () =>
            _sectionChanged(_Section.settings),
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
            _focusSearch,
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _focusSearch,
        const SingleActivator(LogicalKeyboardKey.comma, meta: true): () =>
            _sectionChanged(_Section.settings),
        const SingleActivator(LogicalKeyboardKey.comma, control: true): () =>
            _sectionChanged(_Section.settings),
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true): _compose,
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): _compose,
        if (defaultTargetPlatform != TargetPlatform.macOS)
          const SingleActivator(LogicalKeyboardKey.keyQ, control: true):
              controller.requestQuit,
        const SingleActivator(LogicalKeyboardKey.keyU, meta: true, shift: true):
            _toggleUnread,
        const SingleActivator(
          LogicalKeyboardKey.keyU,
          control: true,
          shift: true,
        ): _toggleUnread,
        const SingleActivator(
          LogicalKeyboardKey.arrowDown,
          control: true,
          alt: true,
        ): () =>
            _navigate(true),
        const SingleActivator(
          LogicalKeyboardKey.arrowUp,
          control: true,
          alt: true,
        ): () =>
            _navigate(false),
        const SingleActivator(
          LogicalKeyboardKey.arrowDown,
          meta: true,
          alt: true,
        ): () =>
            _navigate(true),
        const SingleActivator(
          LogicalKeyboardKey.arrowUp,
          meta: true,
          alt: true,
        ): () =>
            _navigate(false),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Column(
            children: [
              if (controller.isLoading)
                const _StatusBanner(
                  icon: Icons.more_horiz,
                  text: 'Preparing your inbox…',
                ),
              if (controller.error != null)
                _StatusBanner(
                  icon: Icons.warning_amber,
                  text: controller.error!,
                  action: controller.refresh,
                ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final sidebarWidth = ((constraints.maxWidth - 214) / 2)
                        .clamp(260.0, 380.0);
                    return Row(
                      children: [
                        _rail(),
                        Expanded(
                          child: ColoredBox(
                            color:
                                _DesktopPalette.forPreferences(
                                  controller.preferences,
                                )?.background ??
                                Theme.of(context).colorScheme.surface,
                            child: ClipRRect(
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(
                                  controller.preferences.palette == null
                                      ? 0
                                      : 10,
                                ),
                              ),
                              child: Row(
                                children: [
                                  if (controller.preferences.palette == null)
                                    const VerticalDivider(width: 1),
                                  SizedBox(
                                    width: sidebarWidth,
                                    child: ColoredBox(
                                      color: _sidebarColor(),
                                      child: switch (_section) {
                                        _Section.inbox => _inbox(),
                                        _Section.contacts => _contacts(),
                                        _Section.settings => _accounts(),
                                      },
                                    ),
                                  ),
                                  const VerticalDivider(width: 1),
                                  Expanded(
                                    child: ColoredBox(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .surface,
                                      child: _section == _Section.settings
                                          ? _DesktopPreferences(
                                              controller: controller,
                                            )
                                          : _detail(),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _withMenus(Widget child) {
    child = _DesktopWindowActive(active: _windowActive, child: child);
    final mac = defaultTargetPlatform == TargetPlatform.macOS;
    SingleActivator shortcut(
      LogicalKeyboardKey key, {
      bool shift = false,
      bool alt = false,
    }) =>
        SingleActivator(key, meta: mac, control: !mac, shift: shift, alt: alt);
    final hasSelection = controller.selectedRoute != null || _personId != null;
    final selectedUnread = controller.conversations.any(
      (c) => c.route == controller.selectedRoute && c.unreadCount > 0,
    );
    final menus = [
      PlatformMenu(
        label: 'File',
        menus: [
          PlatformMenuItem(
            label: 'New Message…',
            shortcut: shortcut(LogicalKeyboardKey.keyN),
            onSelected: _compose,
          ),
          if (!mac)
            PlatformMenuItem(
              label: 'Settings…',
              shortcut: shortcut(LogicalKeyboardKey.comma),
              onSelected: () => _sectionChanged(_Section.settings),
            ),
          if (!mac)
            PlatformMenuItem(
              label: 'Quit Inbox+',
              shortcut: shortcut(LogicalKeyboardKey.keyQ),
              onSelected: controller.requestQuit,
            ),
        ],
      ),
      PlatformMenu(
        label: 'Edit',
        menus: [
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: 'Undo',
                shortcut: shortcut(LogicalKeyboardKey.keyZ),
                onSelectedIntent: const UndoTextIntent(
                  SelectionChangedCause.keyboard,
                ),
              ),
              PlatformMenuItem(
                label: 'Redo',
                shortcut: shortcut(LogicalKeyboardKey.keyZ, shift: true),
                onSelectedIntent: const RedoTextIntent(
                  SelectionChangedCause.keyboard,
                ),
              ),
            ],
          ),
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: 'Cut',
                shortcut: shortcut(LogicalKeyboardKey.keyX),
                onSelectedIntent: const CopySelectionTextIntent.cut(
                  SelectionChangedCause.keyboard,
                ),
              ),
              PlatformMenuItem(
                label: 'Copy',
                shortcut: shortcut(LogicalKeyboardKey.keyC),
                onSelectedIntent: CopySelectionTextIntent.copy,
              ),
              PlatformMenuItem(
                label: 'Paste',
                shortcut: shortcut(LogicalKeyboardKey.keyV),
                onSelectedIntent: const PasteTextIntent(
                  SelectionChangedCause.keyboard,
                ),
              ),
              PlatformMenuItem(
                label: 'Select All',
                shortcut: shortcut(LogicalKeyboardKey.keyA),
                onSelectedIntent: const SelectAllTextIntent(
                  SelectionChangedCause.keyboard,
                ),
              ),
            ],
          ),
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: 'Search Inbox',
                shortcut: shortcut(LogicalKeyboardKey.keyF),
                onSelected: _focusSearch,
              ),
              PlatformMenuItem(
                label: 'Clear Inbox Search',
                onSelected: _search.text.isEmpty
                    ? null
                    : () => setState(_search.clear),
              ),
            ],
          ),
        ],
      ),
      if (mac)
        const PlatformMenu(
          label: 'View',
          menus: [
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.toggleFullScreen,
            ),
          ],
        ),
      PlatformMenu(
        label: 'Navigate',
        menus: [
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: 'Inbox',
                shortcut: shortcut(LogicalKeyboardKey.digit1),
                onSelected: () => _sectionChanged(_Section.inbox),
              ),
              PlatformMenuItem(
                label: 'Contacts',
                shortcut: shortcut(LogicalKeyboardKey.digit2),
                onSelected: () => _sectionChanged(_Section.contacts),
              ),
              PlatformMenuItem(
                label: 'Settings',
                shortcut: shortcut(LogicalKeyboardKey.digit3),
                onSelected: () => _sectionChanged(_Section.settings),
              ),
            ],
          ),
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: 'Next Conversation',
                shortcut: shortcut(LogicalKeyboardKey.arrowDown, alt: true),
                onSelected: _items.isEmpty ? null : () => _navigate(true),
              ),
              PlatformMenuItem(
                label: 'Previous Conversation',
                shortcut: shortcut(LogicalKeyboardKey.arrowUp, alt: true),
                onSelected: _items.isEmpty ? null : () => _navigate(false),
              ),
            ],
          ),
        ],
      ),
      PlatformMenu(
        label: 'Conversation',
        menus: [
          PlatformMenuItem(
            label: selectedUnread ? 'Mark as Read' : 'Mark as Unread',
            shortcut: shortcut(LogicalKeyboardKey.keyU, shift: true),
            onSelected: hasSelection ? _toggleUnread : null,
          ),
        ],
      ),
      if (mac)
        const PlatformMenu(
          label: 'Window',
          menus: [
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.minimizeWindow,
            ),
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.zoomWindow,
            ),
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.arrangeWindowsInFront,
            ),
          ],
        ),
      PlatformMenu(
        label: 'Help',
        menus: [
          PlatformMenuItem(
            label: 'Inbox+ Help',
            onSelected: () => launchUrl(
              Uri.parse('https://github.com/Tsha0/InboxPlus#readme'),
            ),
          ),
        ],
      ),
    ];
    if (mac) {
      return PlatformMenuBar(
        menus: [
          PlatformMenu(
            label: inboxPlusAppName,
            menus: [
              const PlatformProvidedMenuItem(
                type: PlatformProvidedMenuItemType.about,
              ),
              PlatformMenuItemGroup(
                members: [
                  if (controller.supportsUpdates)
                    PlatformMenuItem(
                      label: 'Check for Updates…',
                      onSelected: controller.checkForUpdates,
                    ),
                  PlatformMenuItem(
                    label: 'Settings…',
                    shortcut: shortcut(LogicalKeyboardKey.comma),
                    onSelected: () => _sectionChanged(_Section.settings),
                  ),
                ],
              ),
              const PlatformProvidedMenuItem(
                type: PlatformProvidedMenuItemType.servicesSubmenu,
              ),
              const PlatformMenuItemGroup(
                members: [
                  PlatformProvidedMenuItem(
                    type: PlatformProvidedMenuItemType.hide,
                  ),
                  PlatformProvidedMenuItem(
                    type: PlatformProvidedMenuItemType.hideOtherApplications,
                  ),
                  PlatformProvidedMenuItem(
                    type: PlatformProvidedMenuItemType.showAllApplications,
                  ),
                ],
              ),
              const PlatformProvidedMenuItem(
                type: PlatformProvidedMenuItemType.quit,
              ),
            ],
          ),
          ...menus,
        ],
        child: child,
      );
    }
    List<Widget> entries(Iterable<PlatformMenuItem> items) => [
      for (final item in items)
        if (item is PlatformMenuItemGroup) ...[
          ...entries(item.members),
          const Divider(),
        ] else
          MenuItemButton(
            shortcut: item.shortcut,
            onPressed:
                item.onSelected ??
                (item.onSelectedIntent == null
                    ? null
                    : () {
                        final focusContext =
                            FocusManager.instance.primaryFocus?.context;
                        if (focusContext != null) {
                          Actions.maybeInvoke(
                            focusContext,
                            item.onSelectedIntent!,
                          );
                        }
                      }),
            child: Text(item.label),
          ),
    ];
    return Column(
      children: [
        TextFieldTapRegion(
          child: MenuBar(
            style: MenuStyle(
              backgroundColor: WidgetStatePropertyAll(
                Theme.of(context).colorScheme.surface,
              ),
              elevation: const WidgetStatePropertyAll(0),
              padding: const WidgetStatePropertyAll(EdgeInsets.zero),
            ),
            children: [
              for (final menu in menus)
                SubmenuButton(
                  menuChildren: entries(menu.menus),
                  child: MenuAcceleratorLabel('&${menu.label}'),
                ),
            ],
          ),
        ),
        Expanded(child: child),
      ],
    );
  }

  Widget _rail() => Container(
    width: 53,
    color:
        _DesktopPalette.forPreferences(controller.preferences)?.background ??
        Theme.of(context).colorScheme.surfaceContainerLow.withValues(alpha: .6),
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Column(
      children: [
        _DesktopLogoButton(
          color:
              _DesktopPalette.forPreferences(controller.preferences)?.logo ??
              Colors.black,
          glowColor:
              _DesktopPalette.forPreferences(controller.preferences)?.logo ??
              Theme.of(context).colorScheme.onSurface,
        ),
        const SizedBox(height: 18),
        _railButton(_Section.inbox, 'Inbox', CupertinoIcons.tray_full_fill),
        const SizedBox(height: 14),
        _railButton(
          _Section.contacts,
          'Contacts',
          CupertinoIcons.person_2_fill,
        ),
        const SizedBox(height: 14),
        Semantics(
          label: 'New message',
          button: true,
          onTap: _compose,
          excludeSemantics: true,
          child: IconButton(
            tooltip: 'New message',
            onPressed: _compose,
            icon: const Icon(CupertinoIcons.square_pencil, size: 17),
          ),
        ),
        const Spacer(),
        _railButton(
          _Section.settings,
          'Settings',
          CupertinoIcons.gear_alt_fill,
        ),
      ],
    ),
  );

  Color _sidebarColor() {
    final palette = _DesktopPalette.forPreferences(controller.preferences);
    final surface = Theme.of(context).colorScheme.surface;
    if (palette == null) return surface;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final opacity = dark
        ? (_legibleOn(palette.background) == Colors.black ? .1 : .22)
        : .12;
    return Color.alphaBlend(
      palette.background.withValues(alpha: opacity),
      surface,
    );
  }

  Widget _railButton(_Section value, String label, IconData icon) => Semantics(
    label: label,
    button: true,
    onTap: () => _sectionChanged(value),
    excludeSemantics: true,
    selected: _section == value,
    child: IconButton(
      key: Key('desktop-rail-${value.name}'),
      tooltip: label,
      onPressed: () => _sectionChanged(value),
      style: IconButton.styleFrom(
        minimumSize: const Size(30, 30),
        maximumSize: const Size(30, 30),
        foregroundColor: _legibleOn(
          _DesktopPalette.forPreferences(controller.preferences)?.background ??
              Theme.of(context).colorScheme.surface,
        ).withValues(alpha: _section == value ? 1 : .55),
        backgroundColor: _section == value
            ? Theme.of(context).colorScheme.onSurface.withValues(alpha: .15)
            : Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      icon: Icon(icon, size: 17),
    ),
  );
  Widget _title(String title, {Widget? trailing}) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
        ),
        ?trailing,
      ],
    ),
  );
  Widget _pill(
    String label,
    bool selected,
    VoidCallback action, {
    Widget? leading,
  }) => TextButton(
    onPressed: action,
    style: TextButton.styleFrom(
      backgroundColor: selected
          ? Theme.of(context).colorScheme.surfaceContainer
          : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      minimumSize: const Size(0, 26),
      visualDensity: VisualDensity.standard,
      shape: const StadiumBorder(),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (leading != null) ...[leading, const SizedBox(width: 5)],
        Text(
          label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );

  Widget _inbox() {
    final items = _items;
    final matches = _messageMatches;
    final unread = controller.conversations.fold(
      0,
      (sum, chat) =>
          sum +
          (controller.preferencesFor(chat.route).hiddenAt != null ||
                  controller
                      .preferencesFor(chat.route)
                      .isMutedAt(DateTime.now())
              ? 0
              : chat.unreadCount),
    );
    final platformOf = {
      for (final account in controller.accounts) account.id: account.platform,
    };
    final networks = <String>{
      for (final chat in controller.conversations)
        if (platformOf[chat.route.accountId] case final platform?
            when (controller.preferencesFor(chat.route).hiddenAt != null) ==
                _hidden)
          platform,
      ..._networks,
    }.where((p) => p != 'legacy').toList();
    final order = [
      'whatsapp',
      'instagram',
      'messenger',
      'telegram',
      'imessage',
    ];
    networks.sort((a, b) => order.indexOf(a).compareTo(order.indexOf(b)));
    final hiddenCount = controller.conversations
        .where((c) => controller.preferencesFor(c.route).hiddenAt != null)
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title(
          _hidden ? 'Hidden' : 'Inbox',
          trailing: unread > 0 ? _DesktopCount(unread) : null,
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            height: 26,
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape): () =>
                    setState(_search.clear),
              },
              child: Semantics(
                label: 'Search inbox',
                onTap: _searchFocus.requestFocus,
                child: TextField(
                  key: const Key('inbox-search'),
                  controller: _search,
                  focusNode: _searchFocus,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'Search',
                    floatingLabelBehavior: FloatingLabelBehavior.never,
                    hintText: 'Search',
                    prefixIcon: const Icon(Icons.search, size: 17),
                    prefixIconConstraints: const BoxConstraints(minWidth: 29),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            onPressed: () => setState(_search.clear),
                            icon: const Icon(
                              Icons.cancel,
                              size: 13,
                              semanticLabel: 'Clear search',
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Row(
            children: [
              _pill(
                'All',
                !_unreadOnly && !_unknownOnly && _networks.isEmpty,
                () => setState(() {
                  _unreadOnly = false;
                  _unknownOnly = false;
                  _networks.clear();
                }),
              ),
              const SizedBox(width: 6),
              _pill(
                'Unread',
                _unreadOnly,
                () => setState(() {
                  _unreadOnly = true;
                  _unknownOnly = false;
                }),
              ),
              if (_unknownOnly ||
                  controller.conversations.any(
                    (chat) => chat.isFromUnknownSender && _owner(chat) == null,
                  )) ...[
                const SizedBox(width: 6),
                _pill(
                  'Unknown senders',
                  _unknownOnly,
                  () => setState(() {
                    _unknownOnly = true;
                    _unreadOnly = false;
                  }),
                ),
              ],
            ],
          ),
        ),
        if (networks.length > 1 || _networks.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: SizedBox(
              height: 28,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  for (final network in networks)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _pill(
                        _desktopNetworkName(controller, network),
                        _networks.contains(network),
                        () => setState(() {
                          if (!_networks.remove(network)) {
                            _networks.add(network);
                          }
                        }),
                        leading: NetworkBadge(
                          network: network,
                          size: 15,
                          labelled: false,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        Expanded(
          child: items.isEmpty && matches.isEmpty
              ? _DesktopEmpty(
                  icon: _unreadOnly ? Icons.check_circle_outline : Icons.search,
                  title: _search.text.isNotEmpty
                      ? 'No matches'
                      : _hidden
                      ? 'Nothing hidden'
                      : _unreadOnly
                      ? 'Nothing unread'
                      : 'Inbox is empty',
                )
              : ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    for (final item in items) _inboxRow(item),
                    if (matches.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                        child: Text(
                          'Messages',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      for (final match in matches)
                        _messageMatch(match.chat, match.message),
                    ],
                  ],
                ),
        ),
        if (_hidden || hiddenCount > 0)
          Padding(
            padding: const EdgeInsets.all(10),
            child: TextButton(
              onPressed: () => setState(() => _hidden = !_hidden),
              style: TextButton.styleFrom(backgroundColor: Colors.transparent),
              child: Text(
                _hidden ? 'Back to Inbox' : '$hiddenCount hidden',
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ),
      ],
    );
  }

  Widget _inboxRow(_DesktopInboxItem item) {
    final chat = item.latest;
    final network = _accountFor(controller, chat.route)?.platform;
    final selected =
        (_personId != null && item.person?.id == _personId) ||
        item.chats.any((c) => c.route == controller.selectedRoute);
    final unread = item.unread(controller);
    final starred = item.favorite(controller);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 0),
      child: Material(
        color: selected
            ? Theme.of(context).colorScheme.surfaceContainerHighest
            : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          key: Key(
            'conversation-${chat.route.accountId}-${chat.route.conversationId}',
          ),
          onTap: () => _selectItem(item),
          onSecondaryTapDown: (details) => _showConversationActions(
            context,
            controller,
            chat,
            position: details.globalPosition,
            conversations: item.chats,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            child: Row(
              children: [
                NetworkBadge(network: network, size: 22),
                if (item.chats.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      '+${item.chats.length - 1}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _relativeTime(chat.latestActivity),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _preview(chat),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          ),
                          if (unread > 0) ...[
                            const SizedBox(width: 6),
                            _DesktopCount(unread),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip:
                      '${starred ? 'Unfavourite' : 'Favourite'} ${item.title}',
                  onPressed: () {
                    for (final c in item.chats) {
                      controller.setFavorite(c.route, !starred);
                    }
                  },
                  icon: Icon(
                    starred ? Icons.star : Icons.star_border,
                    semanticLabel:
                        '${starred ? 'Unfavourite' : 'Favourite'} ${item.title}',
                    size: 19,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _messageMatch(
    ConversationRecord chat,
    MessageRecord message,
  ) => Semantics(
    button: true,
    child: InkWell(
      key: Key(
        'search-result-${chat.route.accountId}-${chat.route.conversationId}-${message.id}',
      ),
      onTap: () {
        setState(() {
          _personId = null;
          _highlightedMessageId = message.id;
        });
        controller.selectConversation(chat.route);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(
          children: [
            NetworkBadge(
              network: _accountFor(controller, chat.route)?.platform,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          chat.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Text(
                        _relativeTime(message.timestamp),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    message.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _contacts() {
    final suggestions = controller.contactSuggestions;
    final people = controller.contacts.toList()
      ..sort((a, b) {
        final name = normalizeContactName(a.displayName)
            .compareTo(normalizeContactName(b.displayName));
        return name == 0 ? a.id.compareTo(b.id) : name;
      });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title('Contacts'),
        const SizedBox(height: 10),
        Expanded(
          child: CustomScrollView(
            slivers: [
              if (suggestions.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Suggested links',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        for (final suggestion in suggestions)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        suggestion.displayName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        suggestion.platforms
                                            .map(
                                              (platform) => _desktopNetworkName(
                                                controller,
                                                platform,
                                              ),
                                            )
                                            .join(' · '),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Semantics(
                                  button: true,
                                  enabled: !controller.isBusy,
                                  excludeSemantics: true,
                                  onTap: controller.isBusy
                                      ? null
                                      : () => _acceptContactSuggestion(
                                          suggestion,
                                        ),
                                  label:
                                      'Link ${suggestion.displayName} across networks',
                                  child: TextButton(
                                    onPressed: controller.isBusy
                                        ? null
                                        : () => _acceptContactSuggestion(
                                            suggestion,
                                          ),
                                    child: const Text('Link these?'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              if (people.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _DesktopEmpty(
                    icon: Icons.people_outline,
                    title: 'No people yet',
                    message:
                        'Link a conversation to a person to group it here.',
                  ),
                )
              else
                SliverList.list(
                  children: [for (final person in people) _contactRow(person)],
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _acceptContactSuggestion(ContactSuggestion suggestion) async {
    final id = await controller.acceptContactSuggestion(suggestion);
    if (id == null || !mounted) return;
    setState(() => _personId = id);
    controller.selectConversation(null);
  }

  Widget _contactRow(ContactRecord person) {
    final chats = _chatsFor(person);
    final networks = chats
        .map(
          (chat) => _desktopNetworkName(
            controller,
            _accountFor(controller, chat.route)?.platform,
          ),
        )
        .join(' · ');
    final description = chats.isEmpty ? 'No linked conversations' : networks;
    final initials = person.displayName
        .trim()
        .split(RegExp(r'\s+'))
        .map((word) => word.characters.firstOrNull ?? '')
        .take(2)
        .join()
        .toUpperCase();
    void select() {
      setState(() => _personId = person.id);
      controller.selectConversation(null);
    }

    final colors = Theme.of(context).colorScheme;
    return Semantics(
      key: ValueKey('contact-row-${person.id}'),
      button: true,
      selected: _personId == person.id,
      label: person.displayName,
      value: description,
      excludeSemantics: true,
      onTap: select,
      child: Material(
        color: _personId == person.id
            ? colors.surfaceContainerHighest
            : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          borderRadius: BorderRadius.circular(7),
          onTap: select,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: colors.surfaceContainer,
                  foregroundColor: colors.onSurface,
                  child: Text(
                    initials.isEmpty ? '?' : initials,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        person.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                for (final chat in chats)
                  Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: NetworkBadge(
                      network: _accountFor(controller, chat.route)?.platform,
                      size: 22,
                      labelled: false,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _accounts() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _title('Settings'),
      const SizedBox(height: 12),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Icon(
              controller.error == null
                  ? Icons.check_circle
                  : Icons.error_outline,
              size: 14,
              color: controller.error == null
                  ? Theme.of(context).colorScheme.onSurface
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Text(
              controller.error == null
                  ? 'Inbox+ is running'
                  : 'Inbox+ needs attention',
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Connected accounts',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            TextButton(
              onPressed: _connect,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, size: 15),
                  SizedBox(width: 5),
                  Text('Add'),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Expanded(
        child: controller.accounts.isEmpty
            ? const _DesktopEmpty(
                icon: Icons.person_add_alt,
                title: 'No accounts yet',
                message: 'Add a network to start bringing conversations into Inbox+.',
              )
            : ListView(
                children: [
                  for (final account in _orderedAccounts) _accountRow(account),
                ],
              ),
      ),
    ],
  );

  Widget _accountRow(AccountRecord account) {
    final theme = Theme.of(context);
    final network = _desktopNetworkName(controller, account.platform);
    final connected = _accountIsConnected(account);
    final changing = controller.isChangingAccount(account.id);
    final identity = account.displayName.trim();
    final canDisconnect = account.platform != 'legacy';
    final canRemove = account.platform != 'imessage';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      child: Row(
        children: [
          NetworkBadge(network: account.platform, labelled: false),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  network,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (identity.isNotEmpty &&
                    identity.toLowerCase() != network.toLowerCase()) ...[
                  const SizedBox(height: 4),
                  SelectableText(
                    identity,
                    maxLines: 1,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  _accountStatus(account, network, connected: connected),
                  style: TextStyle(
                    fontSize: 10,
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.75,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          if (changing)
            SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                semanticsLabel: 'Updating $network',
              ),
            )
          else
            Semantics(
              label: connected ? 'Connected' : 'Disconnected',
              child: Icon(
                Icons.circle,
                size: 8,
                color: connected
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            enabled: !changing,
            tooltip: 'Manage $network',
            padding: EdgeInsets.zero,
            onSelected: (value) async {
              if (value == 'reconnect') {
                final future = controller.reconnectAccount(account.id);
                await showDialog<void>(
                  context: context,
                  builder: (_) => ConnectAccountsDialog(controller: controller),
                );
                await future;
              } else if (value == 'disconnect') {
                await controller.disconnectAccount(account.id);
              } else if (value == 'remove') {
                await _removeAccount(account, network);
              }
            },
            itemBuilder: (_) => [
              if (canDisconnect)
                _menuItem(
                  connected ? 'disconnect' : 'reconnect',
                  connected ? 'Disconnect' : 'Reconnect',
                ),
              if (canDisconnect && canRemove) _menuDivider,
              if (canRemove) _menuItem('remove', 'Remove account…'),
            ],
            child: Semantics(
              label: 'Manage $network',
              button: true,
              excludeSemantics: true,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.pending_outlined,
                      size: 16,
                      color: changing
                          ? theme.disabledColor
                          : theme.colorScheme.onSurface,
                    ),
                    Icon(
                      Icons.keyboard_arrow_down,
                      size: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _accountIsConnected(AccountRecord account) =>
      account.platform != 'legacy' &&
      !controller.preferences.disconnectedAccountIds.contains(account.id);

  List<AccountRecord> get _orderedAccounts {
    const order = [
      'whatsapp',
      'telegram',
      'instagram',
      'messenger',
      'imessage',
      'legacy',
    ];
    return controller.accounts.toList()..sort(
      (a, b) => order.indexOf(a.platform).compareTo(order.indexOf(b.platform)),
    );
  }

  String _accountStatus(
    AccountRecord account,
    String network, {
    required bool connected,
  }) {
    if (account.platform == 'legacy') {
      return 'Add $network again to bring its conversations back';
    }
    if (!connected) return 'Disconnected — messages are kept';
    switch (controller.networkProblem(account.id)) {
      case AccountNetworkProblem.connecting:
        return 'Connecting to $network…';
      case AccountNetworkProblem.reconnecting:
        return '$network dropped the connection — reconnecting…';
      case AccountNetworkProblem.signedOut:
        return 'Signed out of $network — remove it and add it again';
      case AccountNetworkProblem.failed:
        return '$network reports a connection problem';
      case null:
        break;
    }
    if (!account.isConnected) return 'Connecting to $network…';
    final latest = controller.conversations
        .where(
          (c) =>
              c.route.accountId == account.id &&
              c.latestActivity.microsecondsSinceEpoch > 0,
        )
        .map((c) => c.latestActivity)
        .fold<DateTime?>(
          null,
          (latest, date) =>
              latest == null || date.isAfter(latest) ? date : latest,
        );
    if (latest == null) return 'Connected';
    return 'Last message ${namedRelativeTime(latest, DateTime.now())}';
  }

  Future<void> _removeAccount(AccountRecord account, String network) async {
    if (await confirmAccountRemoval(context, network)) {
      await controller.removeAccount(account.id);
    }
  }

  Widget _detail() {
    final person = controller.contacts
        .where((p) => p.id == _personId)
        .firstOrNull;
    if (person != null) return _personSummary(person);
    final selected = controller.conversations
        .where((c) => c.route == controller.selectedRoute)
        .firstOrNull;
    if (selected != null) {
      return _ConversationPane(
        key: ValueKey(selected.route),
        controller: controller,
        conversation: selected,
        desktop: true,
        highlightedMessageId: _highlightedMessageId,
        onManagePerson: () => _linkPerson(selected),
      );
    }
    return const _DesktopEmpty(
      icon: Icons.chat_bubble_outline,
      title: 'Choose a conversation',
      message: 'Pick someone from the list to see their messages.',
    );
  }

  Widget _personSummary(ContactRecord person) {
    final chats = _chatsFor(person);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            person.displayName,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            chats.isEmpty
                ? 'No linked conversations yet'
                : '${chats.length} conversation${chats.length == 1 ? '' : 's'} across your networks',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              TextButton(
                onPressed: () => _renamePerson(person),
                child: const Text('Rename person…'),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => _removePerson(person),
                child: const Text('Remove person…'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Changes affect only Inbox+ grouping. Network conversations and messages are kept.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          Expanded(
            child: chats.isEmpty
                ? const _DesktopEmpty(
                    icon: Icons.link,
                    title: 'Nothing linked',
                    message: 'Open a conversation and choose “Link to person…” to group it here.',
                  )
                : ListView(
                    children: [
                      for (final chat in chats)
                        _personConversationCard(person, chat),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _personConversationCard(
    ContactRecord person,
    ConversationRecord chat,
  ) {
    final platform = _accountFor(controller, chat.route)?.platform;
    final network = _desktopNetworkName(controller, platform);
    final date = _desktopTimestamp(context, chat.latestActivity);
    final unread = chat.unreadCount > 0 ? '${chat.unreadCount} unread' : 'Read';
    final canLink = chat.identityId != null && !chat.isGroup;
    final destinations = controller.contacts.where(
      (other) => other.id != person.id,
    );
    void open() {
      setState(() {
        _personId = null;
        _section = _Section.inbox;
      });
      controller.selectConversation(chat.route);
    }

    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: MenuAnchor(
        menuChildren: [
          MenuItemButton(
            autofocus: true,
            onPressed: canLink ? () => _unlinkPerson(chat, person) : null,
            child: const Text('Unlink conversation from this person'),
          ),
          SubmenuButton(
            menuChildren: [
              for (final other in destinations)
                MenuItemButton(
                  onPressed: canLink
                      ? () => controller.linkIdentity(
                          IdentityLink(chat.route.accountId, chat.identityId!),
                          other,
                        )
                      : null,
                  child: Text(other.displayName),
                ),
            ],
            child: const Text('Move conversation to person'),
          ),
        ],
        builder: (context, menu, child) => GestureDetector(
          onSecondaryTapDown: (details) =>
              menu.open(position: details.localPosition),
          child: Semantics(
            key: ValueKey(
              'conversation-card-${chat.route.accountId}-${chat.route.conversationId}',
            ),
            button: true,
            label: '$network, ${chat.title}, ${_preview(chat)}, $date, $unread',
            excludeSemantics: true,
            onTap: open,
            customSemanticsActions: {
              const CustomSemanticsAction(
                label: 'Manage conversation link',
              ): () =>
                  menu.open(),
            },
            child: Material(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: Theme.of(context).dividerColor),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: open,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      NetworkBadge(network: platform, labelled: false),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    network,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    chat.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _preview(chat),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: colors.onSurfaceVariant),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              date,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: colors.onSurface.withValues(
                                      alpha: .3,
                                    ),
                                  ),
                            ),
                          ],
                        ),
                      ),
                      if (chat.unreadCount > 0) _DesktopCount(chat.unreadCount),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: colors.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _unlinkPerson(ConversationRecord chat, ContactRecord person) =>
      controller.saveContact(
        ContactRecord(
          id: person.id,
          displayName: person.displayName,
          identities: person.identities
              .where(
                (identity) =>
                    !(identity.accountId == chat.route.accountId &&
                        identity.identityId == chat.identityId),
              )
              .toList(),
        ),
      );

  Future<void> _renamePerson(ContactRecord person) => showDialog<void>(
    context: context,
    builder: (_) =>
        _DesktopRenamePerson(controller: controller, person: person),
  );

  Future<void> _removePerson(ContactRecord person) async {
    final yes = await confirmAction(
      context,
      title: 'Remove this person and their Inbox+ links?',
      message: 'Conversations and messages stay on their networks and in Inbox+ as separate chats.',
      confirmLabel: 'Remove person',
      destructive: true,
    );
    if (yes) {
      await controller.removeContact(person.id);
      if (controller.error == null && mounted) setState(() => _personId = null);
    }
  }

  Future<void> _linkPerson(ConversationRecord chat) async {
    final owner = _owner(chat);
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(owner == null ? 'Link to person' : 'Manage person'),
        children: [
          if (owner != null)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, 'unlink'),
              child: const Text('Unlink this conversation'),
            ),
          for (final person in controller.contacts)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, person.id),
              child: Text(person.displayName),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'create'),
            child: const Text('Create a new person…'),
          ),
        ],
      ),
    );
    if (picked == null || chat.identityId == null) return;
    if (picked == 'unlink' && owner != null) {
      await _unlinkPerson(chat, owner);
    }
    if (picked == 'unlink') return;
    final target = controller.contacts.where((p) => p.id == picked).firstOrNull;
    final person =
        target ??
        ContactRecord(
          id: 'person-${DateTime.now().microsecondsSinceEpoch}',
          displayName: chat.title,
        );
    await controller.linkIdentity(
      IdentityLink(chat.route.accountId, chat.identityId!),
      person,
    );
  }
}

class _DesktopRenamePerson extends StatefulWidget {
  const _DesktopRenamePerson({required this.controller, required this.person});
  final InboxUiController controller;
  final ContactRecord person;
  @override
  State<_DesktopRenamePerson> createState() => _DesktopRenamePersonState();
}

class _DesktopRenamePersonState extends State<_DesktopRenamePerson> {
  late final _text = TextEditingController(text: widget.person.displayName);
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    await widget.controller.saveContact(
      ContactRecord(
        id: widget.person.id,
        displayName: _text.text.trim(),
        identities: widget.person.identities,
      ),
    );
    if (!mounted) return;
    if (widget.controller.error == null) {
      Navigator.pop(context);
    } else {
      setState(() {
        _saving = false;
        _error = widget.controller.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Rename person'),
    content: TextField(
      key: const Key('desktop-person-name'),
      controller: _text,
      autofocus: true,
      enabled: !_saving,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(labelText: 'Name', errorText: _error),
      onSubmitted: _saving || _text.text.trim().isEmpty ? null : (_) => _save(),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      TextButton(
        onPressed: _saving || _text.text.trim().isEmpty ? null : _save,
        child: const Text('Save'),
      ),
    ],
  );
}

class _DesktopInboxItem {
  _DesktopInboxItem(this.person, this.chats);
  final ContactRecord? person;
  final List<ConversationRecord> chats;
  String get title => person?.displayName ?? latest.title;
  ConversationRecord get latest => chats.reduce(
    (a, b) => a.latestActivity.isAfter(b.latestActivity) ? a : b,
  );
  int unread(InboxUiController controller) => chats.fold(
    0,
    (sum, chat) =>
        sum +
        chat.unreadCount +
        (controller.preferencesFor(chat.route).markedUnread &&
                chat.unreadCount == 0
            ? 1
            : 0),
  );
  bool favorite(InboxUiController controller) =>
      chats.any((chat) => controller.preferencesFor(chat.route).isFavorite);
}

class _DesktopCount extends StatelessWidget {
  const _DesktopCount(this.count);
  final int count;
  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
    alignment: Alignment.center,
    padding: const EdgeInsets.symmetric(horizontal: 5),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primary,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      '$count',
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onPrimary,
      ),
    ),
  );
}

class _DesktopEmpty extends StatelessWidget {
  const _DesktopEmpty({required this.icon, required this.title, this.message});
  final IconData icon;
  final String title;
  final String? message;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon == Icons.chat_bubble_outline)
            CustomPaint(
              size: const Size(40, 40),
              painter: _DesktopMessageSymbol(
                Theme.of(context).colorScheme.onSurfaceVariant
                    .withValues(alpha: .55),
              ),
            )
          else
            Icon(
              icon,
              size: 40,
              color: Theme.of(context).colorScheme.onSurfaceVariant
                  .withValues(alpha: .55),
            ),
          const SizedBox(height: 24),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          if (message != null) ...[
            const SizedBox(height: 8),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class _DesktopMessageSymbol extends CustomPainter {
  const _DesktopMessageSymbol(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(20, 4)
      ..cubicTo(8, 4, 1, 10, 1, 19)
      ..cubicTo(1, 24, 3, 28, 6, 30)
      ..lineTo(4, 35)
      ..quadraticBezierTo(8, 35, 11, 33)
      ..cubicTo(14, 34, 17, 35, 20, 35)
      ..cubicTo(32, 35, 39, 29, 39, 19)
      ..cubicTo(39, 10, 32, 4, 20, 4)
      ..close();
    canvas.scale(size.width / 40, size.height / 40);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_DesktopMessageSymbol old) => old.color != color;
}

String _desktopTimestamp(BuildContext context, DateTime timestamp) {
  if (timestamp.microsecondsSinceEpoch <= 0) return '';
  final date = timestamp.toLocal();
  final localization = MaterialLocalizations.of(context);
  final time = localization.formatTimeOfDay(
    TimeOfDay.fromDateTime(date),
    alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
  );
  return '${localization.formatShortMonthDay(date)}, ${date.year} at $time';
}

class _DesktopConversationHeader extends StatelessWidget {
  const _DesktopConversationHeader({
    required this.controller,
    required this.conversation,
    this.onManagePerson,
  });
  final InboxUiController controller;
  final ConversationRecord conversation;
  final VoidCallback? onManagePerson;
  @override
  Widget build(BuildContext context) {
    final account = _accountFor(controller, conversation.route);
    final muted = controller
        .preferencesFor(conversation.route)
        .isMutedAt(DateTime.now());
    final linked = controller.contacts.any(
      (person) => person.identities.any(
        (identity) =>
            identity.accountId == conversation.route.accountId &&
            identity.identityId == conversation.identityId,
      ),
    );
    return Container(
      constraints: const BoxConstraints(minHeight: 59),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Row(
        children: [
          NetworkBadge(network: account?.platform),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  conversation.title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  _desktopNetworkName(controller, account?.platform),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: muted ? 'Unmute conversation' : 'Mute conversation',
            onPressed: () => controller.setMuted(conversation.route, !muted),
            icon: Icon(
              muted
                  ? Icons.notifications_off_outlined
                  : Icons.notifications_none,
              size: 17,
              semanticLabel: muted
                  ? 'Unmute conversation'
                  : 'Mute conversation',
            ),
          ),
          if (!conversation.isGroup && conversation.identityId != null) ...[
            const SizedBox(width: 10),
            TextButton(
              onPressed: onManagePerson,
              child: Text(linked ? 'Manage person…' : 'Link to person…'),
            ),
          ],
        ],
      ),
    );
  }
}

/// The wording of Foundation's named relative date style: clock units round to the nearest one,
/// while days, weeks, months and years count calendar boundaries crossed.
@visibleForTesting
String namedRelativeTime(DateTime date, DateTime now) {
  final seconds = now.difference(date).inMilliseconds / 1000;
  String ago(int count, String unit) =>
      '$count $unit${count == 1 ? '' : 's'} ago';
  if (seconds.round() <= 0) return 'now';
  if (seconds.round() < 60) return ago(seconds.round(), 'second');
  if ((seconds / 60).round() < 60) return ago((seconds / 60).round(), 'minute');
  if ((seconds / 3600).round() < 24) {
    return ago((seconds / 3600).round(), 'hour');
  }
  final then = DateTime.utc(date.year, date.month, date.day);
  final today = DateTime.utc(now.year, now.month, now.day);
  final fullMonths =
      (today.year - then.year) * 12 +
      today.month -
      then.month -
      (today.day < then.day ? 1 : 0);
  if (fullMonths >= 1) {
    final months = (today.year - then.year) * 12 + today.month - then.month;
    if (fullMonths < 12 && months < 12) {
      return months == 1 ? 'last month' : '$months months ago';
    }
    final years = today.year - then.year;
    return years == 1 ? 'last year' : '$years years ago';
  }
  final days = today.difference(then).inDays;
  if (days >= 7) {
    DateTime weekStart(DateTime day) =>
        day.subtract(Duration(days: day.weekday % 7));
    final weeks = weekStart(today).difference(weekStart(then)).inDays ~/ 7;
    return weeks == 1 ? 'last week' : '$weeks weeks ago';
  }
  if (days < 1) return ago((seconds / 3600).floor(), 'hour');
  return days == 1 ? 'yesterday' : ago(days, 'day');
}

String _relativeTime(DateTime date) {
  if (date.microsecondsSinceEpoch <= 0) return '';
  final elapsed = DateTime.now().difference(date);
  if (elapsed.inMinutes < 1) return 'now';
  if (elapsed.inMinutes < 60) return '${elapsed.inMinutes}m';
  if (elapsed.inHours < 24) return '${elapsed.inHours}h';
  if (elapsed.inDays < 7) return '${elapsed.inDays}d';
  return '${date.month}/${date.day}';
}

String _desktopNetworkName(InboxUiController controller, String? platform) =>
    platform == 'messenger'
    ? 'Facebook Messenger'
    : _networkName(controller, platform);
