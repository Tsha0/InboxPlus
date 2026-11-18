import 'dart:io';
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons, CupertinoSwitch;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:inboxplus_storage/inboxplus_storage.dart';
import 'package:url_launcher/url_launcher.dart';

import '../contact_suggestions.dart';
import 'account_pages.dart';
import 'confirmation.dart';
import 'contacts_page.dart';
import 'inbox_ui_controller.dart';
import 'media_preview.dart';
import 'new_conversation_dialog.dart';
import 'network_badge.dart';
import 'person_avatar.dart';
import 'reaction_picker.dart';

part 'desktop_shell.dart';
part 'desktop_preferences.dart';
part 'phone_chat.dart';
part 'phone_shell.dart';

PopupMenuItem<T> _menuItem<T>(T value, String label) => PopupMenuItem<T>(
  value: value,
  height: 24,
  padding: const EdgeInsets.symmetric(horizontal: 10),
  child: Text(label),
);

const _menuDivider = PopupMenuDivider(height: 11);

bool get isDesktopPlatform => switch (defaultTargetPlatform) {
  TargetPlatform.macOS ||
  TargetPlatform.windows ||
  TargetPlatform.linux => true,
  _ => false,
};

const inboxPlusAppName = String.fromEnvironment(
  'INBOXPLUS_APP_NAME',
  defaultValue: 'Inbox+',
);

class InboxPlusApp extends StatelessWidget {
  const InboxPlusApp({super.key, required this.controller});

  final InboxUiController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => MaterialApp(
      title: inboxPlusAppName,
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: switch (controller.preferences.appearance) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      },
      home: isDesktopPlatform
          ? _DesktopHome(controller: controller)
          : InboxHome(controller: controller),
    ),
  );

  ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final override = controller.preferences.accentOverride;
    final accent = override != null
        ? Color(0xff000000 | override)
        : _DesktopPalette.forPreferences(controller.preferences)?.accent;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: dark ? Colors.white : const Color(0xff202124),
          brightness: brightness,
        ).copyWith(
          primary:
              accent ??
              (dark ? const Color(0xfff3f3f3) : const Color(0xff202124)),
          onPrimary: accent == null
              ? (dark ? const Color(0xff202124) : Colors.white)
              : _legibleOn(accent),
          surface: dark ? const Color(0xff171819) : const Color(0xfffcfcfc),
          surfaceContainerLow: dark
              ? const Color(0xff1d1e20)
              : const Color(0xfff5f5f5),
          surfaceContainer: dark
              ? const Color(0xff252628)
              : const Color(0xffeeeeef),
        );
    if (isDesktopPlatform) {
      return _desktopTheme(brightness, controller.preferences);
    }
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      dividerColor: scheme.outlineVariant.withValues(alpha: .55),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(44, 44)),
      ),
      tooltipTheme: const TooltipThemeData(
        waitDuration: Duration(milliseconds: 400),
      ),
    );
  }
}

enum _Section { inbox, contacts, settings }

class InboxHome extends StatefulWidget {
  const InboxHome({super.key, required this.controller});

  final InboxUiController controller;

  @override
  State<InboxHome> createState() => _InboxHomeState();
}

class _InboxHomeState extends State<InboxHome> {
  _Section _section = _Section.inbox;
  final _networks = <String>{};
  _ShowFilter _show = _ShowFilter.all;
  bool _searching = false;
  final _search = TextEditingController();
  final _searchFocus = FocusNode();

  InboxUiController get controller => widget.controller;

  int get _unreadTotal => controller.conversations.fold(0, (total, chat) {
    final preferences = controller.preferencesFor(chat.route);
    return preferences.hiddenAt != null || preferences.isMutedAt(DateTime.now())
        ? total
        : total + chat.unreadCount;
  });

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    await showDialog<void>(
      context: context,
      builder: (context) => ConnectAccountsDialog(controller: controller),
    );
  }

  Future<void> _compose({IdentityLink? identity}) async {
    final opened = await showDialog<bool>(
      context: context,
      builder: (context) => NewConversationDialog(
        controller: controller,
        initialIdentity: identity,
      ),
    );
    if (opened == true && mounted) _selectSection(_Section.inbox);
  }

  void _selectSection(_Section section) => setState(() => _section = section);

  void _focusSearch() {
    _selectSection(_Section.inbox);
    setState(() => _searching = true);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _searchFocus.requestFocus(),
    );
  }

  void _closeSearch() {
    _searchFocus.unfocus();
    setState(() {
      _search.clear();
      _searching = false;
    });
  }

  ConversationRecord? get _selected {
    for (final item in controller.conversations) {
      if (item.route == controller.selectedRoute) return item;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 900;
    final selected = _selected;
    final showsTabs =
        compact && !(selected != null && _section == _Section.inbox);
    final textFactor = switch (controller.preferences.textSize) {
      'small' => .9,
      'large' => 1.15,
      _ => 1.0,
    };
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: textFactor == 1
          ? media
          : media.copyWith(
              textScaler: TextScaler.linear(
                media.textScaler.scale(1) * textFactor,
              ),
            ),
      child: _buildHome(context, compact, selected, showsTabs),
    );
  }

  Widget _buildHome(
    BuildContext context,
    bool compact,
    ConversationRecord? selected,
    bool showsTabs,
  ) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
            _focusSearch,
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _focusSearch,
        const SingleActivator(LogicalKeyboardKey.comma, meta: true): () =>
            _selectSection(_Section.settings),
        const SingleActivator(LogicalKeyboardKey.digit1, meta: true): () =>
            _selectSection(_Section.inbox),
        const SingleActivator(LogicalKeyboardKey.digit2, meta: true): () =>
            _selectSection(_Section.contacts),
        const SingleActivator(LogicalKeyboardKey.digit3, meta: true): () =>
            _selectSection(_Section.settings),
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true): _compose,
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): _compose,
      },
      child: PopScope(
        canPop: !compact || selected == null || _section != _Section.inbox,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) controller.selectConversation(null);
        },
        child: Scaffold(
          backgroundColor:
              compact && _section == _Section.inbox && selected == null
              ? _phoneHeaderColor(context, controller)
              : null,
          extendBody: showsTabs,
          body: SafeArea(
            bottom: !showsTabs,
            child: Column(
              children: [
                if (controller.isLoading)
                  const LinearProgressIndicator(
                    minHeight: 2,
                    semanticsLabel: 'Loading your inbox',
                  ),
                if (controller.isOffline)
                  const _StatusBanner(
                    icon: Icons.cloud_off_outlined,
                    text:
                        'You’re offline. Your drafts are saved on this device.',
                  ),
                if (controller.error != null)
                  _StatusBanner(
                    icon: Icons.error_outline,
                    text: controller.error!,
                    action: controller.isBusy ? null : controller.refresh,
                  ),
                Expanded(
                  child: Row(
                    children: [
                      if (!compact)
                        _NavigationRail(
                          section: _section,
                          onSelect: _selectSection,
                          onCompose: _compose,
                          unreadCount: controller.conversations.fold(
                            0,
                            (total, item) => total + item.unreadCount,
                          ),
                        ),
                      if (!compact) const VerticalDivider(width: 1),
                      Expanded(child: _body(compact, selected)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: !showsTabs
              ? null
              : _PhoneBottomBar(
                  section: _section,
                  onSelect: _selectSection,
                  unreadCount: _unreadTotal,
                  settingsNeedAttention: controller.accounts.any(
                    (account) => !account.isConnected,
                  ),
                  onFilter: _section == _Section.inbox ? _openFilterMenu : null,
                  filterActive: _filterLabels.isNotEmpty,
                  onCompose: _section == _Section.settings ? null : _compose,
                ),
        ),
      ),
    );
  }

  Widget _body(bool compact, ConversationRecord? selected) {
    switch (_section) {
      case _Section.settings:
        return InboxSettingsPage(controller: controller, onConnect: _connect);
      case _Section.contacts:
        return InboxContactsPage(
          controller: controller,
          onOpenConversation: () => _selectSection(_Section.inbox),
          onCompose: (identity) => _compose(identity: identity),
        );
      case _Section.inbox:
        if (compact && selected != null) {
          return _ConversationPane(
            key: ValueKey(selected.route),
            controller: controller,
            conversation: selected,
            onBack: () => controller.selectConversation(null),
          );
        }
        return Row(
          children: [
            SizedBox(
              width: compact ? MediaQuery.sizeOf(context).width : 330,
              child: _inboxList(),
            ),
            if (!compact) ...[
              const VerticalDivider(width: 1),
              Expanded(
                child: selected == null
                    ? _EmptyState(
                        icon: Icons.forum_outlined,
                        title: 'A little more connected.',
                        message: controller.accounts.isEmpty
                            ? 'Bring your conversations together.\nConnect an account to get started.'
                            : 'Choose a conversation to pick up where you left off.',
                        action: controller.accounts.isEmpty
                            ? FilledButton.icon(
                                onPressed: _connect,
                                icon: const Icon(Icons.add),
                                label: const Text('Connect an account'),
                              )
                            : null,
                      )
                    : _ConversationPane(
                        key: ValueKey(selected.route),
                        controller: controller,
                        conversation: selected,
                      ),
              ),
            ],
          ],
        );
    }
  }

  bool _matchesShow(
    ConversationRecord item,
    ConversationPreferencesRecord preferences,
  ) {
    switch (_show) {
      case _ShowFilter.all:
        return true;
      case _ShowFilter.unread:
        return item.unreadCount > 0 || preferences.markedUnread;
      case _ShowFilter.unanswered:
        final last = controller.messagesFor(item.route).lastOrNull;
        return !item.isGroup && last != null && !last.isOutgoing;
      case _ShowFilter.drafts:
        final draft = controller.draftFor(item.route);
        return draft != null &&
            (draft.body.isNotEmpty || draft.attachments.isNotEmpty);
      case _ShowFilter.dms:
        return !item.isGroup;
      case _ShowFilter.groups:
        return item.isGroup;
    }
  }

  List<String> get _filterLabels => [
    if (_show != _ShowFilter.all) _show.label,
    for (final network in _networks) _networkName(controller, network),
  ];

  void _clearFilters() => setState(() {
    _show = _ShowFilter.all;
    _networks.clear();
  });

  List<String> _availableNetworks() {
    const networkOrder = [
      'whatsapp',
      'instagram',
      'messenger',
      'telegram',
      'imessage',
    ];
    return <String>{
      for (final chat in controller.conversations)
        if (controller.preferencesFor(chat.route).hiddenAt == null)
          ?_accountFor(controller, chat.route)?.platform,
      ..._networks,
    }.where((platform) => platform != 'legacy').toList()..sort(
      (a, b) => networkOrder.indexOf(a).compareTo(networkOrder.indexOf(b)),
    );
  }

  Future<void> _openFilterMenu() async {
    final media = MediaQuery.of(context);
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close filters',
      barrierColor: Colors.black.withValues(alpha: .35),
      transitionDuration: const Duration(milliseconds: 160),
      transitionBuilder: (context, animation, _, child) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          alignment: Alignment.bottomLeft,
          scale: Tween(begin: .92, end: 1.0).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          ),
          child: child,
        ),
      ),
      pageBuilder: (dialogContext, _, _) => Stack(
        children: [
          Positioned(
            left: 16,
            bottom:
                (media.viewPadding.bottom > 0
                    ? media.viewPadding.bottom - 6
                    : 14) +
                _phoneBarHeight +
                12,
            width: 276,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: media.size.height - media.viewPadding.top - 140,
              ),
              child: SingleChildScrollView(
                child: _PhoneFilterMenu(
                  controller: controller,
                  show: _show,
                  networks: _availableNetworks(),
                  selectedNetworks: _networks,
                  onShow: (show) => setState(() => _show = show),
                  onToggleNetwork: (network) => setState(() {
                    if (!_networks.remove(network)) _networks.add(network);
                  }),
                  onFeedback: () {
                    Navigator.pop(dialogContext);
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => FeedbackPage(controller: controller),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _inboxList() {
    final scheme = Theme.of(context).colorScheme;
    final palette = _DesktopPalette.forPreferences(controller.preferences);
    final headerInk = palette == null
        ? scheme.onSurface
        : _legibleOn(palette.background);
    final sheetColor = palette == null
        ? scheme.surface
        : Color.alphaBlend(
            palette.background.withValues(alpha: .08),
            scheme.surface,
          );
    final query = _search.text.trim().toLowerCase();
    final conversations =
        controller.conversations.where((item) {
          final preferences = controller.preferencesFor(item.route);
          if (preferences.hiddenAt != null) return false;
          if (_networks.isNotEmpty &&
              !_networks.contains(
                _accountFor(controller, item.route)?.platform,
              )) {
            return false;
          }
          if (!_matchesShow(item, preferences)) return false;
          return query.isEmpty ||
              item.title.toLowerCase().contains(query) ||
              controller
                  .messagesFor(item.route)
                  .any((message) => message.body.toLowerCase().contains(query));
        }).toList()..sort((a, b) {
          final favorite =
              (controller.preferencesFor(b.route).isFavorite ? 1 : 0) -
              (controller.preferencesFor(a.route).isFavorite ? 1 : 0);
          return favorite != 0
              ? favorite
              : b.latestActivity.compareTo(a.latestActivity);
        });
    final filterLabels = _filterLabels;
    final favorites = query.isEmpty && filterLabels.isEmpty
        ? conversations
              .where((item) => controller.preferencesFor(item.route).isFavorite)
              .toList()
        : const <ConversationRecord>[];
    if (favorites.isNotEmpty) {
      conversations.removeWhere(favorites.contains);
    }
    final unread = _unreadTotal;
    final headerColor = _phoneHeaderColor(context, controller);
    return ColoredBox(
      color: headerColor,
      child: RefreshIndicator(
        onRefresh: controller.refresh,
        child: CustomScrollView(
          slivers: [
            SliverPersistentHeader(
              pinned: true,
              delegate: _PhoneInboxHeader(
                title: inboxPlusAppName,
                unread: unread,
                ink: headerInk,
                background: headerColor,
                leading: Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: _DesktopLogoButton(
                    color: palette?.logo ?? scheme.onSurface,
                    glowColor: palette?.logo ?? scheme.onSurface,
                    tapSize: 44,
                  ),
                ),
                trailing: IconButton(
                  key: const Key('inbox-search-button'),
                  tooltip: _searching ? 'Close search' : 'Search',
                  onPressed: _searching ? _closeSearch : _focusSearch,
                  color: headerInk,
                  style: IconButton.styleFrom(
                    backgroundColor: headerInk.withValues(alpha: .08),
                  ),
                  icon: Icon(
                    _searching ? CupertinoIcons.xmark : CupertinoIcons.search,
                    size: 20,
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: sheetColor,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(18),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_searching)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: SizedBox(
                          height: 40,
                          child: TextField(
                            key: const Key('inbox-search'),
                            controller: _search,
                            focusNode: _searchFocus,
                            onChanged: (_) => setState(() {}),
                            style: const TextStyle(fontSize: 16),
                            decoration: InputDecoration(
                              hintText: 'Search',
                              isDense: true,
                              filled: true,
                              fillColor: scheme.onSurface.withValues(
                                alpha: .06,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 8,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                              prefixIcon: const Icon(Icons.search, size: 18),
                              prefixIconConstraints: const BoxConstraints(
                                minWidth: 34,
                              ),
                              suffixIcon: query.isEmpty
                                  ? null
                                  : IconButton(
                                      tooltip: 'Clear search',
                                      icon: const Icon(Icons.cancel, size: 16),
                                      onPressed: () => setState(_search.clear),
                                    ),
                            ),
                          ),
                        ),
                      ),
                    if (filterLabels.isNotEmpty)
                      _PhoneActiveFilters(
                        labels: filterLabels,
                        onClear: _clearFilters,
                      ),
                    if (favorites.isNotEmpty)
                      _PhoneFavoritesRow(
                        controller: controller,
                        favorites: favorites,
                        onOpen: (item) =>
                            controller.selectConversation(item.route),
                        onActions: _conversationMenu,
                      ),
                    const SizedBox(height: 6),
                  ],
                ),
              ),
            ),
            if (conversations.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: ColoredBox(
                  color: sheetColor,
                  child: _EmptyState(
                    icon: query.isNotEmpty
                        ? Icons.search_off
                        : Icons.inbox_outlined,
                    title: query.isNotEmpty
                        ? 'No conversations found'
                        : controller.isLoading
                        ? 'Opening your inbox…'
                        : _show == _ShowFilter.unread ||
                              _show == _ShowFilter.unanswered
                        ? 'All caught up'
                        : _show != _ShowFilter.all
                        ? 'No ${_show.label.toLowerCase()} conversations'
                        : _networks.isNotEmpty
                        ? 'No conversations here'
                        : 'Your inbox starts here',
                    message: query.isNotEmpty
                        ? 'Try another name or message.'
                        : filterLabels.isNotEmpty
                        ? 'Nothing matches ${filterLabels.join(' · ')}.'
                        : controller.accounts.isEmpty
                        ? 'Connect an account and your conversations will appear here.'
                        : 'New conversations will appear here.',
                    action: controller.accounts.isEmpty && query.isEmpty
                        ? TextButton.icon(
                            onPressed: _connect,
                            icon: const Icon(Icons.add),
                            label: const Text('Connect an account'),
                          )
                        : null,
                  ),
                ),
              )
            else ...[
              SliverList.builder(
                itemCount: conversations.length,
                itemBuilder: (context, index) {
                  final item = conversations[index];
                  return _PhoneInboxRow(
                    key: ValueKey(item.route),
                    controller: controller,
                    conversation: item,
                    background: sheetColor,
                    selected: item.route == controller.selectedRoute,
                    onOpen: () => controller.selectConversation(item.route),
                    onActions: () => _conversationMenu(item),
                  );
                },
              ),
              SliverFillRemaining(
                hasScrollBody: false,
                child: ColoredBox(
                  color: sheetColor,
                  child: SizedBox(
                    height: MediaQuery.paddingOf(context).bottom + 8,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _conversationMenu(ConversationRecord item) async {
    await _showPhoneChatPeek(context, controller, item);
  }
}

Color _phoneHeaderColor(BuildContext context, InboxUiController controller) =>
    _DesktopPalette.forPreferences(controller.preferences)?.background ??
    Theme.of(context).colorScheme.surfaceContainerLow;

class _PhoneInboxHeader extends SliverPersistentHeaderDelegate {
  _PhoneInboxHeader({
    required this.title,
    required this.unread,
    required this.ink,
    required this.background,
    required this.leading,
    required this.trailing,
  });

  static const _barHeight = 52.0;
  static const _titleHeight = 52.0;

  final String title;
  final int unread;
  final Color ink;
  final Color background;
  final Widget leading;
  final Widget trailing;

  @override
  double get minExtent => _barHeight;

  @override
  double get maxExtent => _barHeight + _titleHeight;

  @override
  bool shouldRebuild(_PhoneInboxHeader oldDelegate) => true;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final collapse = (shrinkOffset / _titleHeight).clamp(0.0, 1.0);
    final bar = Row(
      children: [
        const SizedBox(width: 10),
        leading,
        Expanded(
          child: Opacity(
            opacity: collapse,
            child: Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: ink,
              ),
            ),
          ),
        ),
        trailing,
        const SizedBox(width: 6),
      ],
    );
    return ClipRect(
      child: Stack(
        children: [
          Positioned(
            top: _barHeight - shrinkOffset,
            left: 16,
            right: 16,
            height: _titleHeight,
            child: ExcludeSemantics(
              excluding: collapse == 1,
              child: Opacity(
                opacity: 1 - collapse,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 34,
                          height: 1.2,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -.4,
                          color: ink,
                        ),
                      ),
                    ),
                    if (unread > 0) ...[
                      const SizedBox(width: 10),
                      Container(
                        margin: const EdgeInsets.only(top: 9),
                        constraints: const BoxConstraints(minWidth: 24),
                        height: 24,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 7),
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '$unread',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: scheme.onPrimary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: _barHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: collapse == 1
                    ? Border(bottom: BorderSide(color: scheme.outlineVariant))
                    : null,
              ),
              child: collapse == 1
                  ? ClipRect(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                        child: ColoredBox(
                          color: background.withValues(alpha: .86),
                          child: bar,
                        ),
                      ),
                    )
                  : ColoredBox(color: background, child: bar),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhoneInboxRow extends StatefulWidget {
  const _PhoneInboxRow({
    super.key,
    required this.controller,
    required this.conversation,
    required this.background,
    required this.selected,
    required this.onOpen,
    required this.onActions,
  });

  final InboxUiController controller;
  final ConversationRecord conversation;
  final Color background;
  final bool selected;
  final VoidCallback onOpen;
  final VoidCallback onActions;

  @override
  State<_PhoneInboxRow> createState() => _PhoneInboxRowState();
}

class _PhoneInboxRowState extends State<_PhoneInboxRow> {
  static const _actionWidth = 76.0;
  double _reveal = 0;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _reveal = 0);
    await action();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final item = widget.conversation;
    final scheme = Theme.of(context).colorScheme;
    final account = _accountFor(controller, item.route);
    final preferences = controller.preferencesFor(item.route);
    final muted = preferences.isMutedAt(DateTime.now());
    final unread = item.unreadCount > 0 || preferences.markedUnread;
    final draft = controller.draftFor(item.route);
    final hasDraft =
        draft != null &&
        (draft.body.isNotEmpty || draft.attachments.isNotEmpty);
    final last = controller.messagesFor(item.route).lastOrNull;
    final preview = hasDraft
        ? 'Draft: ${draft.body.isEmpty ? 'Attachment' : draft.body}'
        : last == null
        ? _networkName(controller, account?.platform)
        : '${item.isGroup && !last.isOutgoing && last.senderName != null ? '${last.senderName}: ' : ''}${last.body.isEmpty ? 'Attachment' : last.body}';
    final muteLabel = muted ? 'Unmute' : 'Mute';
    final hideLabel = preferences.hiddenAt == null ? 'Hide' : 'Unhide';
    final readLabel = unread ? 'Mark as read' : 'Mark as unread';
    final compact = controller.preferences.inboxDensity == 'compact';
    void mute() => _run(() => controller.setMuted(item.route, !muted));
    void hide() => _run(
      () => controller.setHidden(item.route, preferences.hiddenAt == null),
    );
    void toggleRead() => _run(() => controller.setUnread(item.route, !unread));
    return Semantics(
      customSemanticsActions: {
        CustomSemanticsAction(label: readLabel): toggleRead,
        CustomSemanticsAction(label: muteLabel): mute,
        CustomSemanticsAction(label: hideLabel): hide,
      },
      child: GestureDetector(
        onHorizontalDragUpdate: (details) => setState(
          () => _reveal = (_reveal - details.delta.dx).clamp(
            -_actionWidth,
            _actionWidth * 2,
          ),
        ),
        onHorizontalDragEnd: (_) => setState(
          () => _reveal = _reveal < -_actionWidth / 2
              ? -_actionWidth
              : _reveal > _actionWidth
              ? _actionWidth * 2
              : 0,
        ),
        child: ClipRect(
          child: SizedBox(
            height: compact ? 56 : 68,
            child: Stack(
              children: [
                if (_reveal < 0)
                  Positioned.fill(
                    child: Row(
                      children: [
                        _SwipeAction(
                          label: unread ? 'Read' : 'Unread',
                          icon: unread
                              ? CupertinoIcons.envelope_open
                              : CupertinoIcons.envelope_badge,
                          color: scheme.primary,
                          foreground: scheme.onPrimary,
                          onPressed: toggleRead,
                        ),
                      ],
                    ),
                  ),
                if (_reveal > 0)
                  Positioned.fill(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        _SwipeAction(
                          label: muteLabel,
                          icon: muted
                              ? Icons.notifications_outlined
                              : Icons.notifications_off_outlined,
                          color: const Color(0xff5c5c5c),
                          onPressed: mute,
                        ),
                        _SwipeAction(
                          label: hideLabel,
                          icon: preferences.hiddenAt == null
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: Colors.black,
                          onPressed: hide,
                        ),
                      ],
                    ),
                  ),
                Transform.translate(
                  offset: Offset(-_reveal, 0),
                  child: Material(
                    color: widget.selected
                        ? Color.alphaBlend(
                            scheme.onSurface.withValues(alpha: .07),
                            widget.background,
                          )
                        : widget.background,
                    child: InkWell(
                      key: Key(
                        'conversation-${item.route.accountId}-${item.route.conversationId}',
                      ),
                      onTap: _reveal != 0
                          ? () => setState(() => _reveal = 0)
                          : widget.onOpen,
                      onLongPress: widget.onActions,
                      child: Row(
                        children: [
                          const SizedBox(width: 16),
                          PersonAvatar(
                            name: item.title,
                            bytes: item.avatarBytes,
                            network: account?.platform,
                            isGroup: item.isGroup,
                            size: compact ? 40 : 48,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
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
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    if (muted)
                                      Padding(
                                        padding: const EdgeInsets.only(left: 4),
                                        child: Icon(
                                          Icons.notifications_off_outlined,
                                          size: 13,
                                          semanticLabel: 'Muted',
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _relativeTime(item.latestActivity),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        preview,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: unread
                                              ? FontWeight.w500
                                              : FontWeight.w400,
                                          color: hasDraft
                                              ? scheme.error
                                              : unread
                                              ? scheme.onSurface
                                              : scheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                    if (unread) ...[
                                      const SizedBox(width: 6),
                                      item.unreadCount > 0
                                          ? _DesktopCount(item.unreadCount)
                                          : Container(
                                              width: 10,
                                              height: 10,
                                              decoration: BoxDecoration(
                                                color: scheme.primary,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SwipeAction extends StatelessWidget {
  const _SwipeAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
    this.foreground = Colors.white,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;
  final Color foreground;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: _PhoneInboxRowState._actionWidth,
    child: Material(
      color: color,
      child: InkWell(
        onTap: onPressed,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 19, color: foreground),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: foreground,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _NavigationRail extends StatelessWidget {
  const _NavigationRail({
    required this.section,
    required this.onSelect,
    required this.onCompose,
    required this.unreadCount,
  });

  final _Section section;
  final ValueChanged<_Section> onSelect;
  final VoidCallback onCompose;
  final int unreadCount;

  @override
  Widget build(BuildContext context) => Container(
    width: 76,
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    padding: const EdgeInsets.symmetric(vertical: 20),
    child: Column(
      children: [
        Semantics(
          label: 'Inbox+',
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(13),
            ),
            alignment: Alignment.center,
            child: Text(
              'i+',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimary,
                fontSize: 28,
                fontWeight: FontWeight.w700,
                letterSpacing: -2,
              ),
            ),
          ),
        ),
        const SizedBox(height: 28),
        _button(
          context,
          _Section.inbox,
          'Inbox',
          Icons.inbox_outlined,
          Icons.inbox,
          badge: unreadCount > 0,
        ),
        const SizedBox(height: 10),
        _button(
          context,
          _Section.contacts,
          'Contacts',
          Icons.people_outline,
          Icons.people,
        ),
        const SizedBox(height: 10),
        IconButton(
          tooltip: 'New message',
          onPressed: onCompose,
          icon: const Icon(Icons.edit_square, size: 23),
        ),
        const Spacer(),
        _button(
          context,
          _Section.settings,
          'Settings',
          Icons.settings_outlined,
          Icons.settings,
        ),
      ],
    ),
  );

  Widget _button(
    BuildContext context,
    _Section value,
    String label,
    IconData icon,
    IconData selectedIcon, {
    bool badge = false,
  }) => Semantics(
    selected: section == value,
    child: IconButton(
      tooltip: label,
      isSelected: section == value,
      style: IconButton.styleFrom(
        backgroundColor: section == value
            ? Theme.of(context).colorScheme.surfaceContainerHighest
            : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.all(13),
      ),
      onPressed: () => onSelect(value),
      icon: Badge(
        isLabelVisible: badge,
        smallSize: 7,
        child: Icon(section == value ? selectedIcon : icon, size: 23),
      ),
    ),
  );
}

class _ConversationPane extends StatefulWidget {
  const _ConversationPane({
    super.key,
    required this.controller,
    required this.conversation,
    this.onBack,
    this.desktop = false,
    this.onManagePerson,
    this.highlightedMessageId,
  });

  final InboxUiController controller;
  final ConversationRecord conversation;
  final VoidCallback? onBack;
  final bool desktop;
  final VoidCallback? onManagePerson;
  final String? highlightedMessageId;

  @override
  State<_ConversationPane> createState() => _ConversationPaneState();
}

class _ConversationPaneState extends State<_ConversationPane> {
  final _scroll = ScrollController();
  int _messageCount = -1;
  String? _highlightedMessageId;
  String? _externalHighlightedMessageId;
  final _messageKeys = <String, GlobalKey>{};
  int? _firstNewIndex;

  Future<void> _revealMessage(String id) async {
    if (!_scroll.hasClients) return;
    _scroll.jumpTo(_scroll.position.maxScrollExtent);
    while (mounted && _highlightedMessageId == id && _scroll.hasClients) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !_scroll.hasClients) return;
      final target = _messageKeys[id]?.currentContext;
      if (target != null && target.mounted) {
        await Scrollable.ensureVisible(target, alignment: .5);
        return;
      }
      final offset = _scroll.offset;
      if (offset <= 0) return;
      _scroll.jumpTo(
        (offset - _scroll.position.viewportDimension * .8).clamp(
          0,
          _scroll.position.maxScrollExtent,
        ),
      );
    }
  }

  Future<void> _showReplyTarget(String id) async {
    setState(() => _highlightedMessageId = id);
    await widget.controller.revealMessage(widget.conversation.route, id);
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealMessage(id));
    setState(() {});
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final item = widget.conversation;
    final messages = controller.messagesFor(item.route);
    if (!widget.desktop && messages.isNotEmpty) {
      _firstNewIndex ??= item.unreadCount > 0
          ? messages.length - item.unreadCount
          : -1;
    }
    if (_externalHighlightedMessageId != widget.highlightedMessageId) {
      _externalHighlightedMessageId = widget.highlightedMessageId;
      _highlightedMessageId = widget.highlightedMessageId;
      if (_highlightedMessageId case final id?) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _revealMessage(id));
      }
    }
    final account = _accountFor(controller, item.route);
    final capability = controller.networks
        .where((network) => network.id == account?.platform)
        .firstOrNull;
    if (_messageCount != messages.length) {
      final wasNearBottom =
          !_scroll.hasClients ||
          _scroll.position.maxScrollExtent - _scroll.offset < 180;
      _messageCount = messages.length;
      if (wasNearBottom && _highlightedMessageId == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            _scroll.jumpTo(_scroll.position.maxScrollExtent);
          }
        });
      }
    }
    return Column(
      children: [
        if (widget.desktop)
          _DesktopConversationHeader(
            controller: controller,
            conversation: item,
            onManagePerson: widget.onManagePerson,
          ),
        if (!widget.desktop)
          _PhoneChatHeader(
            controller: controller,
            conversation: item,
            onBack: widget.onBack,
            onInfo: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => _PhoneChatInfoPage(
                  controller: controller,
                  route: item.route,
                ),
              ),
            ),
            onActions: () =>
                _showPhoneChatPeek(context, controller, item, preview: false),
          ),
        if (widget.desktop) const Divider(height: 1),
        Expanded(
          child: CustomPaint(
            painter: widget.desktop
                ? null
                : _ChatWallpaper(
                    controller.preferences.chatWallpaper,
                    Theme.of(context).colorScheme.primary.withValues(
                      alpha: controller.preferences.chatWallpaper == 'tint'
                          ? .06
                          : .14,
                    ),
                  ),
            child: messages.isEmpty
                ? widget.desktop
                      ? Align(
                          alignment: Alignment.topCenter,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'No recent messages',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        )
                      : const _EmptyState(
                          icon: Icons.chat_bubble_outline,
                          title: 'Start the conversation',
                          message: 'Messages will appear here.',
                        )
                : ListView.builder(
                    controller: _scroll,
                    padding: widget.desktop
                        ? const EdgeInsets.fromLTRB(27, 8, 27, 12)
                        : const EdgeInsets.fromLTRB(24, 20, 24, 12),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      final showDate =
                          index == 0 ||
                          !_sameDay(
                            messages[index - 1].timestamp,
                            message.timestamp,
                          );
                      final repliedTo = message.replyToMessageId == null
                          ? null
                          : controller.replyTargetFor(
                              item.route,
                              message.replyToMessageId!,
                            );
                      return Container(
                        key: _messageKeys.putIfAbsent(
                          message.id,
                          GlobalKey.new,
                        ),
                        decoration: _highlightedMessageId == message.id
                            ? BoxDecoration(
                                color: Theme.of(context).colorScheme.primary
                                    .withValues(alpha: .08),
                                borderRadius: BorderRadius.circular(8),
                              )
                            : null,
                        child: Column(
                          children: [
                            if (widget.desktop && index == 0)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  'Showing recent messages',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            if (showDate)
                              Padding(
                                padding: EdgeInsets.symmetric(
                                  vertical: widget.desktop ? 4 : 14,
                                ),
                                child: Text(
                                  _dayLabel(message.timestamp),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: widget.desktop
                                        ? FontWeight.normal
                                        : FontWeight.w600,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                ),
                              ),
                            if (index == _firstNewIndex && index > 0)
                              const _NewMessagesDivider(),
                            _MessageBubble(
                              message: message,
                              conversation: item,
                              controller: controller,
                              capability: capability,
                              replyTarget: repliedTo,
                              onRevealReply: _showReplyTarget,
                              desktop: widget.desktop,
                              showsTimestamp:
                                  !widget.desktop ||
                                  index + 1 == messages.length ||
                                  !_sameMessageRun(
                                    message,
                                    messages[index + 1],
                                  ),
                              showsSender:
                                  !widget.desktop ||
                                  index == 0 ||
                                  !_sameMessageRun(
                                    messages[index - 1],
                                    message,
                                  ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ),
        if (widget.desktop) const Divider(height: 1),
        _Composer(
          key: ValueKey(item.route),
          controller: controller,
          conversation: item,
          capability: capability,
          connected: account?.isConnected ?? false,
          desktop: widget.desktop,
        ),
      ],
    );
  }
}

class _NewMessagesDivider extends StatelessWidget {
  const _NewMessagesDivider();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final line = Expanded(
      child: Divider(height: 1, color: color.withValues(alpha: .6)),
    );
    return Semantics(
      label: 'New messages',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            line,
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                'New',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
            line,
          ],
        ),
      ),
    );
  }
}

class _ReplyQuote extends StatelessWidget {
  const _ReplyQuote({
    super.key,
    required this.target,
    required this.conversation,
    required this.foreground,
    required this.onTap,
  });

  final MessageRecord? target;
  final ConversationRecord conversation;
  final Color foreground;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final message = target;
    final attachment =
        message?.attachments
            .where(
              (item) =>
                  item.kind == 'reel' ||
                  {'reel', 'reels'}.contains(
                    Uri.tryParse(item.deepLink ?? '')?.pathSegments.firstOrNull,
                  ),
            )
            .firstOrNull ??
        message?.attachments.firstOrNull;
    final link = Uri.tryParse(attachment?.deepLink ?? '');
    final isReel =
        attachment?.kind == 'reel' ||
        {'reel', 'reels'}.contains(link?.pathSegments.firstOrNull);
    final sender = message == null
        ? ''
        : message.isOutgoing
        ? 'You'
        : message.senderName?.trim().isNotEmpty == true
        ? message.senderName!
        : conversation.title;
    final name = attachment?.fileName?.trim() ?? '';
    final body = message?.body.trim() ?? '';
    final summary = message == null
        ? 'Original message unavailable'
        : body.isNotEmpty
        ? body
        : name.isNotEmpty
        ? name
        : isReel && link != null && link.pathSegments.length > 1
        ? 'Reel ${link.pathSegments[1]}'
        : attachment != null
        ? (isReel ? 'Shared Reel' : 'Attachment')
        : 'Message';
    final label = message == null
        ? 'Reply'
        : '${isReel ? 'Reel' : 'Reply'} · $sender';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Tooltip(
        message: onTap == null
            ? 'Original message unavailable'
            : 'Show original message',
        child: Semantics(
          button: onTap != null,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(6),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 300),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: foreground.withValues(alpha: .06),
                border: Border(
                  left: BorderSide(
                    color: foreground.withValues(alpha: .45),
                    width: 2,
                  ),
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    message == null
                        ? Icons.link_off
                        : isReel
                        ? Icons.movie_outlined
                        : Icons.reply,
                    size: 20,
                    color: foreground,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: foreground,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          summary,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: foreground.withValues(alpha: .85),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (onTap != null) ...[
                    const SizedBox(width: 8),
                    Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: foreground.withValues(alpha: .65),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.conversation,
    required this.controller,
    this.capability,
    this.desktop = false,
    this.replyTarget,
    required this.onRevealReply,
    this.showsTimestamp = true,
    this.showsSender = true,
  });

  final MessageRecord message;
  final ConversationRecord conversation;
  final InboxUiController controller;
  final NetworkCapability? capability;
  final bool desktop;
  final MessageRecord? replyTarget;
  final Future<void> Function(String) onRevealReply;
  final bool showsTimestamp;
  final bool showsSender;

  @override
  Widget build(BuildContext context) => desktop
      ? _MessageHoverRegion(builder: (hovering) => _build(context, hovering))
      : _build(context, false);

  Widget _build(BuildContext context, bool hovering) {
    final scheme = Theme.of(context).colorScheme;
    final own = message.isOutgoing;
    final canReply = capability?.canReply == true && message.acceptsResponses;
    final canReact = capability?.canReact == true && message.acceptsResponses;
    final reactions = controller.reactionsFor(message.route, message.id);
    final ownReactions = controller.ownReactionsFor(message.route, message.id);
    final deliveryUnconfirmed = controller.isDeliveryUnconfirmed(
      message.route,
      message.id,
    );
    final savableAttachments = message.attachments
        .where(
          (attachment) =>
              attachment.isDownloadable || attachment.localPath != null,
        )
        .toList();
    final bubble = Align(
      alignment: own ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(bottom: desktop ? 8 : 10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (own) SizedBox(width: desktop ? 60 : 24),
              if (desktop && canReact && own) _reactButton(hovering),
              Flexible(
                child: Column(
                  crossAxisAlignment: own
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    if (!own && conversation.isGroup && showsSender)
                      Padding(
                        padding: const EdgeInsets.only(left: 12, bottom: 4),
                        child: Text(
                          message.senderName ?? conversation.title,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: desktop ? 12 : 14,
                        vertical: desktop ? 8 : 10,
                      ),
                      decoration: BoxDecoration(
                        color: own ? scheme.primary : scheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(
                          desktop
                              ? 12
                              : switch (controller.preferences.bubbleShape) {
                                  'soft' => 11,
                                  'square' => 5,
                                  _ => 17,
                                },
                        ),
                      ),
                      child: DefaultTextStyle(
                        style: TextStyle(
                          fontSize: desktop ? 13 : 14,
                          fontFamily: desktop
                              ? Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.fontFamily
                              : null,
                          letterSpacing: desktop ? 0 : null,
                          height: desktop ? 1.2 : 1.45,
                          color: own ? scheme.onPrimary : scheme.onSurface,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (message.replyToMessageId != null)
                              _ReplyQuote(
                                key: ValueKey('reply-quote-${message.id}'),
                                target: replyTarget,
                                conversation: conversation,
                                foreground: own
                                    ? scheme.onPrimary
                                    : scheme.onSurface,
                                onTap: replyTarget == null
                                    ? null
                                    : () => onRevealReply(
                                        message.replyToMessageId!,
                                      ),
                              ),
                            for (final (index, attachment)
                                in message.attachments.indexed)
                              if (attachment.kind != 'preview')
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: _AttachmentTile(
                                    attachment: attachment,
                                    // Ingestion stores a preview directly before the attachment it shows.
                                    preview:
                                        index > 0 &&
                                            message
                                                    .attachments[index - 1]
                                                    .kind ==
                                                'preview'
                                        ? message.attachments[index - 1]
                                        : null,
                                    caption: message.body,
                                    foreground: own
                                        ? scheme.onPrimary
                                        : scheme.onSurface,
                                    onDownload: () =>
                                        controller.downloadAttachment(
                                          message.route,
                                          message.id,
                                          attachment.id,
                                        ),
                                    imageLoad: controller.attachmentLoadState(
                                      message.route,
                                      attachment.id,
                                    ),
                                    onLoadImage: () =>
                                        controller.loadInlineImage(
                                          message.route,
                                          message.id,
                                          attachment.id,
                                        ),
                                    onOpen: () => controller.openAttachment(
                                      attachment.localPath!,
                                    ),
                                    onSave:
                                        desktop && attachment.localPath != null
                                        ? () => controller.saveAttachment(
                                            message.route,
                                            message.id,
                                            attachment.id,
                                          )
                                        : null,
                                    linkPlatform: _accountFor(
                                      controller,
                                      message.route,
                                    )?.platform,
                                    playsInstagramReels: controller
                                        .preferences
                                        .playsInstagramReels,
                                    onOpenLink: () =>
                                        controller.openAttachmentLink(
                                          message.route,
                                          message.id,
                                          attachment.id,
                                        ),
                                  ),
                                ),
                            if (message.body.isNotEmpty && !desktop)
                              Text(message.body)
                            else if (message.body.isNotEmpty)
                              SelectableText(
                                message.body,
                                semanticsLabel: message.body,
                                contextMenuBuilder: (_, editable) =>
                                    AdaptiveTextSelectionToolbar.buttonItems(
                                      anchors: editable.contextMenuAnchors,
                                      buttonItems: [
                                        if (desktop && canReply)
                                          ContextMenuButtonItem(
                                            label: 'Reply',
                                            onPressed: () {
                                              editable.hideToolbar();
                                              controller.setReplyTo(
                                                message.route,
                                                message.id,
                                              );
                                            },
                                          ),
                                        if (desktop && canReact)
                                          ContextMenuButtonItem(
                                            label: 'React',
                                            onPressed: () {
                                              final anchor = editable
                                                  .contextMenuAnchors
                                                  .primaryAnchor;
                                              editable.hideToolbar();
                                              _chooseReaction(
                                                context,
                                                position: anchor,
                                              );
                                            },
                                          ),
                                        if (desktop)
                                          ContextMenuButtonItem(
                                            label: 'Copy Text',
                                            onPressed: () {
                                              editable.hideToolbar();
                                              Clipboard.setData(
                                                ClipboardData(
                                                  text: message.body,
                                                ),
                                              );
                                            },
                                          )
                                        else
                                          ...editable.contextMenuButtonItems,
                                        if (desktop)
                                          for (final attachment
                                              in savableAttachments)
                                            ContextMenuButtonItem(
                                              label: _saveLabel(attachment),
                                              onPressed:
                                                  attachment.localPath == null
                                                  ? null
                                                  : () {
                                                      editable.hideToolbar();
                                                      controller.saveAttachment(
                                                        message.route,
                                                        message.id,
                                                        attachment.id,
                                                      );
                                                    },
                                            ),
                                      ],
                                    ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (reactions.isNotEmpty)
                      Wrap(
                        spacing: 4,
                        children: [
                          for (final reaction in reactions.entries)
                            if (desktop)
                              Tooltip(
                                message: ownReactions.contains(reaction.key)
                                    ? 'Remove your ${reaction.key}'
                                    : 'React with ${reaction.key}',
                                child: Semantics(
                                  button: true,
                                  selected: ownReactions.contains(reaction.key),
                                  enabled: canReact,
                                  child: InkWell(
                                    onTap: canReact
                                        ? () => controller.react(
                                            message.route,
                                            message.id,
                                            reaction.key,
                                          )
                                        : null,
                                    borderRadius: BorderRadius.circular(20),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color:
                                            ownReactions.contains(reaction.key)
                                            ? scheme.primary.withValues(
                                                alpha: .18,
                                              )
                                            : scheme.onSurface.withValues(
                                                alpha: .08,
                                              ),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        reaction.value > 1
                                            ? '${reaction.key} ${reaction.value}'
                                            : reaction.key,
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                    ),
                                  ),
                                ),
                              )
                            else
                              ActionChip(
                                label: Text(
                                  '${reaction.key} ${reaction.value}',
                                ),
                                visualDensity: VisualDensity.compact,
                                backgroundColor:
                                    ownReactions.contains(reaction.key)
                                    ? scheme.secondaryContainer
                                    : null,
                                onPressed: canReact
                                    ? () => controller.react(
                                        message.route,
                                        message.id,
                                        reaction.key,
                                      )
                                    : null,
                              ),
                        ],
                      ),
                    if (showsTimestamp ||
                        message.deliveryState != DeliveryState.acknowledged)
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          desktop ? 0 : 6,
                          4,
                          desktop ? 0 : 6,
                          0,
                        ),
                        child: Wrap(
                          spacing: 5,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              desktop
                                  ? MaterialLocalizations.of(context)
                                        .formatTimeOfDay(
                                          TimeOfDay.fromDateTime(
                                            message.timestamp.toLocal(),
                                          ),
                                        )
                                  : _time(message.timestamp),
                              style: TextStyle(
                                fontSize: 10,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            if (own &&
                                (!desktop ||
                                    message.deliveryState !=
                                        DeliveryState.acknowledged)) ...[
                              Icon(
                                switch (message.deliveryState) {
                                  DeliveryState.pending => Icons.schedule,
                                  DeliveryState.acknowledged => Icons.done,
                                  DeliveryState.failed => Icons.error_outline,
                                },
                                size: 12,
                                color:
                                    message.deliveryState ==
                                        DeliveryState.failed
                                    ? scheme.error
                                    : scheme.onSurfaceVariant,
                              ),
                            ],
                            if (message.deliveryState == DeliveryState.failed)
                              TextButton(
                                style: TextButton.styleFrom(
                                  minimumSize: const Size(40, 28),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                ),
                                onPressed: controller.isBusy
                                    ? null
                                    : () => deliveryUnconfirmed
                                          ? _checkDelivery(context)
                                          : controller.retryMessage(
                                              message.route,
                                              message.id,
                                            ),
                                child: Text(
                                  deliveryUnconfirmed
                                      ? 'Check delivery'
                                      : 'Retry',
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (desktop && canReact && !own) _reactButton(hovering),
              if (!own) SizedBox(width: desktop ? 60 : 24),
            ],
          ),
        ),
      ),
    );
    if (!desktop) {
      final canCopy = message.body.isNotEmpty;
      if (!canReply && !canReact && !canCopy && savableAttachments.isEmpty) {
        return bubble;
      }
      return Semantics(
        customSemanticsActions: {
          if (canReply)
            const CustomSemanticsAction(label: 'Reply'): () =>
                controller.setReplyTo(message.route, message.id),
          if (canReact)
            const CustomSemanticsAction(label: 'React'): () =>
                _chooseReaction(context),
          if (canCopy)
            const CustomSemanticsAction(label: 'Copy text'): () =>
                Clipboard.setData(ClipboardData(text: message.body)),
        },
        child: GestureDetector(
          key: Key('message-${message.id}'),
          behavior: HitTestBehavior.translucent,
          onLongPress: () => _showPhoneActions(
            context,
            canReply: canReply,
            canReact: canReact,
            savable: savableAttachments,
          ),
          child: bubble,
        ),
      );
    }
    return Semantics(
      customSemanticsActions: {
        if (canReact)
          const CustomSemanticsAction(label: 'React'): () =>
              _openReactionPicker(context),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onSecondaryTapDown: (details) async {
          if (!canReply &&
              !canReact &&
              message.body.isEmpty &&
              savableAttachments.isEmpty) {
            return;
          }
          final action = await showMenu<String>(
            context: context,
            position: RelativeRect.fromLTRB(
              details.globalPosition.dx,
              details.globalPosition.dy,
              details.globalPosition.dx,
              details.globalPosition.dy,
            ),
            items: [
              if (canReply) _menuItem('reply', 'Reply'),
              if (canReact) _menuItem('react', 'React'),
              if (message.body.isNotEmpty) _menuItem('copy', 'Copy Text'),
              for (final attachment in savableAttachments)
                PopupMenuItem(
                  value: 'save:${attachment.id}',
                  enabled: attachment.localPath != null,
                  height: 24,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(_saveLabel(attachment)),
                ),
            ],
          );
          if (!context.mounted) return;
          switch (action) {
            case 'copy':
              await Clipboard.setData(ClipboardData(text: message.body));
            case 'reply':
              controller.setReplyTo(message.route, message.id);
            case 'react':
              await _chooseReaction(context, position: details.globalPosition);
            case final String value when value.startsWith('save:'):
              await controller.saveAttachment(
                message.route,
                message.id,
                value.substring(5),
              );
          }
        },
        child: bubble,
      ),
    );
  }

  Future<void> _showPhoneActions(
    BuildContext context, {
    required bool canReply,
    required bool canReact,
    required List<AttachmentRecord> savable,
  }) async {
    unawaited(HapticFeedback.mediumImpact());
    final own = controller.ownReactionsFor(message.route, message.id);
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final scheme = Theme.of(sheetContext).colorScheme;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (canReact)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (final emoji in quickReactions)
                        Semantics(
                          label: 'React with $emoji',
                          selected: own.contains(emoji),
                          button: true,
                          excludeSemantics: true,
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () =>
                                Navigator.pop(sheetContext, 'emoji:$emoji'),
                            child: Container(
                              width: 46,
                              height: 46,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: own.contains(emoji)
                                    ? scheme.primary.withValues(alpha: .22)
                                    : null,
                              ),
                              child: Text(
                                emoji,
                                style: const TextStyle(fontSize: 26),
                              ),
                            ),
                          ),
                        ),
                      IconButton.filledTonal(
                        tooltip: 'More reactions',
                        onPressed: () => Navigator.pop(sheetContext, 'react'),
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                ),
              if (canReply)
                ListTile(
                  leading: const Icon(CupertinoIcons.reply),
                  title: const Text('Reply'),
                  onTap: () => Navigator.pop(sheetContext, 'reply'),
                ),
              if (message.body.isNotEmpty)
                ListTile(
                  leading: const Icon(CupertinoIcons.doc_on_doc),
                  title: const Text('Copy'),
                  onTap: () => Navigator.pop(sheetContext, 'copy'),
                ),
              for (final attachment in savable)
                ListTile(
                  enabled: attachment.localPath != null,
                  leading: const Icon(CupertinoIcons.arrow_down_to_line),
                  title: Text(_saveLabel(attachment).replaceAll('…', '')),
                  onTap: () =>
                      Navigator.pop(sheetContext, 'save:${attachment.id}'),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (!context.mounted || action == null) return;
    switch (action) {
      case 'copy':
        await Clipboard.setData(ClipboardData(text: message.body));
      case 'reply':
        controller.setReplyTo(message.route, message.id);
      case 'react':
        await _chooseReaction(context);
      case final String value when value.startsWith('emoji:'):
        await controller.react(message.route, message.id, value.substring(6));
      case final String value when value.startsWith('save:'):
        await controller.saveAttachment(
          message.route,
          message.id,
          value.substring(5),
        );
    }
  }

  String _saveLabel(AttachmentRecord attachment) =>
      message.attachments.length == 1
      ? 'Save Attachment…'
      : 'Save ${attachment.fileName ?? 'Attachment'}…';

  Widget _reactButton(bool hovering) => Builder(
    builder: (context) => ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Opacity(
          opacity: hovering ? 1 : 0,
          child: SizedBox.square(
            dimension: 26,
            child: IconButton(
              tooltip: 'React',
              padding: EdgeInsets.zero,
              icon: const Icon(
                Icons.sentiment_satisfied_alt_outlined,
                size: 20,
              ),
              onPressed: hovering ? () => _openReactionPicker(context) : null,
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> _openReactionPicker(BuildContext context) async {
    final box = context.findRenderObject()! as RenderBox;
    final selected = await showReactionPicker(
      context,
      ownReactions: controller.ownReactionsFor(message.route, message.id),
      anchor: box.localToGlobal(box.size.bottomCenter(Offset.zero)),
    );
    if (selected != null) {
      await controller.react(message.route, message.id, selected);
    }
  }

  Future<void> _checkDelivery(BuildContext context) async {
    final wasSent = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Check the original app first'),
        content: const Text(
          'Delivery could not be confirmed. Open the original app and check this conversation before choosing. If it was not sent, it stays in the conversation with Retry available. Your current draft is kept. Inbox+ will not resend it automatically.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('It was not sent'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('It was sent'),
          ),
        ],
      ),
    );
    if (wasSent != null) {
      await controller.resolveUnconfirmedSend(
        message.route,
        message.id,
        wasSent: wasSent,
      );
    }
  }

  Future<void> _chooseReaction(BuildContext context, {Offset? position}) async {
    final choices = {
      ...quickReactions,
      ...controller.reactionsFor(message.route, message.id).keys,
    };
    final own = controller.ownReactionsFor(message.route, message.id);
    if (desktop) {
      final box = context.findRenderObject()! as RenderBox;
      final anchor =
          position ?? box.localToGlobal(box.size.center(Offset.zero));
      var selected = await showMenu<String>(
        context: context,
        position: RelativeRect.fromLTRB(
          anchor.dx,
          anchor.dy,
          anchor.dx,
          anchor.dy,
        ),
        items: [
          for (final emoji in choices)
            PopupMenuItem(
              value: emoji,
              height: 24,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Semantics(
                selected: own.contains(emoji),
                child: Row(
                  children: [
                    SizedBox(
                      width: 22,
                      child: own.contains(emoji)
                          ? const Icon(Icons.check, size: 14)
                          : null,
                    ),
                    Text(emoji),
                  ],
                ),
              ),
            ),
          _menuDivider,
          _menuItem('more', 'More…'),
        ],
      );
      if (!context.mounted) return;
      if (selected == 'more') {
        selected = await showReactionPicker(
          context,
          ownReactions: own,
          anchor: anchor,
        );
      }
      if (selected != null) {
        await controller.react(message.route, message.id, selected);
      }
      return;
    }
    final selected = await showReactionPicker(context, ownReactions: own);
    if (selected != null) {
      await controller.react(message.route, message.id, selected);
    }
  }
}

class _MessageHoverRegion extends StatefulWidget {
  const _MessageHoverRegion({required this.builder});

  final Widget Function(bool hovering) builder;

  @override
  State<_MessageHoverRegion> createState() => _MessageHoverRegionState();
}

class _MessageHoverRegionState extends State<_MessageHoverRegion> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovering = true),
    onExit: (_) => setState(() => _hovering = false),
    child: widget.builder(_hovering),
  );
}

class _Composer extends StatefulWidget {
  const _Composer({
    super.key,
    required this.controller,
    required this.conversation,
    required this.connected,
    this.capability,
    this.desktop = false,
  });

  final InboxUiController controller;
  final ConversationRecord conversation;
  final NetworkCapability? capability;
  final bool connected;
  final bool desktop;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  late final TextEditingController _text;
  String? _replyTargetId;
  final _focus = FocusNode();
  final _attachButton = GlobalKey();

  ConversationRoute get route => widget.conversation.route;
  String? get _sendingUnavailableReason =>
      widget.controller.sendingUnavailableReason(route) ??
      (widget.connected ? null : 'Reconnect this account in Settings to send.');

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(
      text: widget.controller.draftFor(route)?.body ?? '',
    );
    _replyTargetId = widget.controller.draftFor(route)?.replyToMessageId;
  }

  @override
  void didUpdateWidget(covariant _Composer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final replyId = widget.controller.draftFor(route)?.replyToMessageId;
    if (replyId != _replyTargetId) {
      _replyTargetId = replyId;
      if (replyId != null) _focus.requestFocus();
    }
    final body = widget.controller.draftFor(route)?.body ?? '';
    if (_text.text != body) {
      _text.value = TextEditingValue(
        text: body,
        selection: TextSelection.collapsed(offset: body.length),
      );
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _openAttachMenu() async {
    final box = _attachButton.currentContext!.findRenderObject()! as RenderBox;
    final button = box.localToGlobal(Offset.zero) & box.size;
    final screen = MediaQuery.sizeOf(context);
    final media = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close attach menu',
      barrierColor: Colors.black.withValues(alpha: .35),
      transitionDuration: const Duration(milliseconds: 160),
      transitionBuilder: (context, animation, _, child) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          alignment: Alignment.bottomLeft,
          scale: Tween(begin: .92, end: 1.0).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          ),
          child: child,
        ),
      ),
      pageBuilder: (dialogContext, _, _) => Stack(
        children: [
          Positioned(
            left: math.max(12, button.left - 4),
            bottom: screen.height - button.top + 10,
            width: 272,
            child: _PhoneAttachMenu(
              onPick: (media) => Navigator.pop(dialogContext, media),
            ),
          ),
          Positioned.fromRect(
            rect: button,
            child: Material(
              type: MaterialType.transparency,
              child: IconButton(
                tooltip: 'Close attach menu',
                onPressed: () => Navigator.pop(dialogContext),
                icon: const Icon(Icons.close, size: 23),
              ),
            ),
          ),
        ],
      ),
    );
    if (media != null && mounted) {
      await widget.controller.stageAttachments(route, media: media);
    }
  }

  Future<void> _send() async {
    final draft = widget.controller.draftFor(route);
    if (_sendingUnavailableReason != null ||
        widget.controller.isBusy ||
        (_text.text.trim().isEmpty && (draft?.attachments.isEmpty ?? true))) {
      return;
    }
    await widget.controller.sendDraft(route);
    if (mounted) _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final sendingUnavailableReason = _sendingUnavailableReason;
    final draft = controller.draftFor(route);
    final reply = draft?.replyToMessageId == null
        ? null
        : controller
              .messagesFor(route)
              .where((message) => message.id == draft!.replyToMessageId)
              .firstOrNull;
    final canSend =
        sendingUnavailableReason == null &&
        !controller.isBusy &&
        (_text.text.trim().isNotEmpty ||
            (draft?.attachments.isNotEmpty ?? false));
    return Padding(
      padding: widget.desktop
          ? const EdgeInsets.fromLTRB(18, 12, 18, 12)
          : const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (sendingUnavailableReason != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(
                    widget.connected
                        ? Icons.lock_outline
                        : Icons.cloud_off_outlined,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      sendingUnavailableReason,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          if (draft?.replyToMessageId != null)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.reply, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          reply == null
                              ? 'Replying to message'
                              : 'Replying to ${reply.isOutgoing ? 'you' : reply.senderName ?? widget.conversation.title}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          reply?.body.isNotEmpty == true
                              ? reply!.body
                              : 'Message',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cancel reply',
                    onPressed: () => controller.setReplyTo(route, null),
                    icon: const Icon(
                      Icons.close,
                      size: 18,
                      semanticLabel: 'Cancel reply',
                    ),
                  ),
                ],
              ),
            ),
          if (!widget.desktop &&
              (draft?.attachments.every(
                    (attachment) =>
                        attachment.kind == 'image' &&
                        attachment.localPath != null,
                  ) ??
                  false) &&
              draft!.attachments.isNotEmpty)
            for (final attachment in draft.attachments)
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        ClipRRect(
                          key: const Key('draft-photo-preview'),
                          borderRadius: BorderRadius.circular(16),
                          child: Image.file(
                            File(attachment.localPath!),
                            width: 112,
                            height: 112,
                            fit: BoxFit.cover,
                            cacheWidth: 336,
                            semanticLabel: attachment.fileName ?? 'Photo',
                          ),
                        ),
                        Positioned(
                          top: -12,
                          right: -12,
                          child: IconButton(
                            tooltip: 'Remove ${attachment.fileName ?? 'photo'}',
                            onPressed: () => controller.removeDraftAttachment(
                              route,
                              attachment.id,
                            ),
                            icon: const Icon(
                              CupertinoIcons.xmark_circle_fill,
                              size: 26,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        [
                          ?attachment.fileName,
                          if (attachment.byteCount case final bytes?)
                            '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB',
                        ].join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              )
          else if (draft?.attachments.isNotEmpty ?? false)
            SizedBox(
              height: 66,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: draft!.attachments.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final attachment = draft.attachments[index];
                  return InputChip(
                    avatar: const Icon(Icons.attach_file, size: 18),
                    label: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 180),
                      child: Text(
                        attachment.fileName ?? 'Attachment',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    onDeleted: () =>
                        controller.removeDraftAttachment(route, attachment.id),
                    deleteButtonTooltipMessage:
                        'Remove ${attachment.fileName ?? 'attachment'}',
                  );
                },
              ),
            ),
          Container(
            padding: widget.desktop
                ? EdgeInsets.zero
                : const EdgeInsets.fromLTRB(5, 4, 5, 4),
            decoration: widget.desktop
                ? null
                : BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    borderRadius: BorderRadius.circular(18),
                  ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (widget.capability?.canAttach == true)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 1),
                    child: IconButton(
                      key: _attachButton,
                      tooltip: widget.desktop ? 'Attach files' : 'Attach',
                      onPressed: controller.isBusy
                          ? null
                          : widget.desktop
                          ? () => controller.stageAttachments(route)
                          : _openAttachMenu,
                      icon: widget.desktop
                          ? Transform.rotate(
                              angle: .785398,
                              child: const Icon(
                                Icons.attach_file,
                                size: 20,
                                semanticLabel: 'Attach a file',
                              ),
                            )
                          : const Icon(
                              Icons.add,
                              size: 23,
                              semanticLabel: 'Attach',
                            ),
                    ),
                  ),
                if (widget.desktop && widget.capability?.canAttach == true)
                  const SizedBox(width: 8),
                Expanded(
                  child: Focus(
                    onKeyEvent: (node, event) {
                      if (event is KeyDownEvent &&
                          event.logicalKey == LogicalKeyboardKey.enter) {
                        if ((widget.desktop ||
                                controller.preferences.enterToSend) &&
                            !HardwareKeyboard.instance.isShiftPressed &&
                            !HardwareKeyboard.instance.isAltPressed) {
                          _send();
                        } else {
                          final selection = _text.selection.isValid
                              ? _text.selection
                              : TextSelection.collapsed(
                                  offset: _text.text.length,
                                );
                          _text.value = _text.value.replaced(selection, '\n');
                          controller.updateDraft(route, _text.text);
                          setState(() {});
                        }
                        return KeyEventResult.handled;
                      }
                      if (event is KeyDownEvent &&
                          event.logicalKey == LogicalKeyboardKey.escape &&
                          draft?.replyToMessageId != null) {
                        controller.setReplyTo(route, null);
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: Semantics(
                      label: 'Message',
                      onTap: _focus.requestFocus,
                      child: TextField(
                        key: const Key('message-composer'),
                        controller: _text,
                        focusNode: _focus,
                        minLines: 1,
                        maxLines: 6,
                        textCapitalization: TextCapitalization.sentences,
                        keyboardType: TextInputType.multiline,
                        onChanged: (value) {
                          controller.updateDraft(route, value);
                          setState(() {});
                        },
                        style: widget.desktop
                            ? const TextStyle(fontSize: 13)
                            : null,
                        decoration: InputDecoration(
                          hintText: !widget.desktop && widget.capability != null
                              ? 'Reply on ${widget.capability!.name}'
                              : 'Message',
                          filled: widget.desktop,
                          border: widget.desktop
                              ? OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(9),
                                  borderSide: BorderSide.none,
                                )
                              : InputBorder.none,
                          enabledBorder: widget.desktop
                              ? OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(9),
                                  borderSide: BorderSide.none,
                                )
                              : InputBorder.none,
                          focusedBorder: widget.desktop
                              ? OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(9),
                                  borderSide: BorderSide.none,
                                )
                              : InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: widget.desktop ? 9 : 13,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (widget.desktop) const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: IconButton(
                    key: const Key('send-message'),
                    tooltip: controller.isOffline
                        ? 'Queue message'
                        : 'Send message',
                    onPressed: canSend ? _send : null,
                    style: widget.desktop
                        ? null
                        : IconButton.styleFrom(
                            backgroundColor: canSend
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.onSurface
                                      .withValues(alpha: .12),
                            foregroundColor: Theme.of(context)
                                .colorScheme
                                .onPrimary,
                          ),
                    icon: widget.desktop
                        ? Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: canSend
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.onSurface
                                        .withValues(alpha: .16),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.arrow_upward,
                              semanticLabel: controller.isOffline
                                  ? 'Queue message'
                                  : 'Send message',
                              size: 15,
                              color: Theme.of(context).colorScheme.surface,
                            ),
                          )
                        : Icon(
                            Icons.arrow_upward,
                            size: 20,
                            semanticLabel: controller.isOffline
                                ? 'Queue message'
                                : 'Send message',
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({
    required this.attachment,
    this.preview,
    this.caption = '',
    required this.foreground,
    required this.onDownload,
    required this.onLoadImage,
    required this.onOpen,
    required this.onOpenLink,
    this.imageLoad,
    this.onSave,
    this.linkPlatform,
    this.playsInstagramReels = false,
  });

  final AttachmentRecord attachment;
  final AttachmentRecord? preview;
  final String caption;
  final Color foreground;
  final Future<void> Function() onDownload;
  final Future<void> Function() onLoadImage;
  final AttachmentLoadState? imageLoad;
  final Future<void> Function() onOpen;
  final Future<void> Function() onOpenLink;
  final Future<void> Function()? onSave;
  final String? linkPlatform;
  final bool playsInstagramReels;

  String? get _destination => switch (linkPlatform) {
    'instagram' => 'Instagram',
    'messenger' => 'Facebook',
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final link = Uri.tryParse(attachment.deepLink ?? '');
    final isReel =
        linkPlatform == 'instagram' &&
        (attachment.kind == 'reel' ||
            link?.pathSegments.firstOrNull == 'reel' ||
            link?.pathSegments.firstOrNull == 'reels');
    final playable =
        isReel &&
        playsInstagramReels &&
        (attachment.isDownloadable || attachment.localPath != null);
    if (attachment.deepLink?.isNotEmpty == true &&
        _destination != null &&
        (preview?.localPath != null || playable)) {
      return _SharedPostCard(
        attachment: attachment,
        previewPath: preview?.localPath,
        isReel: isReel,
        playable: playable,
        author: attachment.fileName == caption ? null : attachment.fileName,
        destination: _destination!,
        foreground: foreground,
        onDownload: onDownload,
        onOpenLink: onOpenLink,
        onSave: onSave,
      );
    }
    if ((!attachment.isDownloadable && attachment.localPath == null) ||
        (isReel && !playsInstagramReels)) {
      return _linkedContent(context);
    }
    final image =
        attachment.kind == 'image' ||
        (attachment.mimeType?.startsWith('image/') ?? false);
    final video =
        attachment.kind == 'video' ||
        attachment.kind == 'reel' ||
        (attachment.mimeType?.startsWith('video/') ?? false);
    final audio =
        attachment.kind == 'audio' ||
        (attachment.mimeType?.startsWith('audio/') ?? false);
    if (video && preview != null) {
      return _InlineVideo(
        attachment: attachment,
        posterPath: preview!.localPath,
        onDownload: onDownload,
        onSave: onSave,
      );
    }
    if (image && attachment.localPath != null) {
      return Semantics(
        button: true,
        label: 'Preview ${attachment.fileName ?? 'image'}',
        child: InkWell(
          onTap: () => showDialog<void>(
            context: context,
            builder: (context) => Dialog.fullscreen(
              child: Scaffold(
                appBar: AppBar(
                  title: Text(attachment.fileName ?? 'Image'),
                  leading: IconButton(
                    tooltip: 'Close preview',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.close,
                      semanticLabel: 'Close preview',
                    ),
                  ),
                  actions: [
                    if (onSave != null)
                      TextButton(
                        onPressed: onSave,
                        child: const Text('Save As…'),
                      ),
                  ],
                ),
                body: Center(
                  child: InteractiveViewer(
                    minScale: .5,
                    maxScale: 5,
                    child: Image.file(
                      File(attachment.localPath!),
                      errorBuilder: (_, _, _) => const Text(
                        'This image is no longer available on this device.',
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: Image.file(
              File(attachment.localPath!),
              width: 280,
              height: 190,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _fileCard(
                context,
                Icons.broken_image_outlined,
                'Image unavailable',
              ),
            ),
          ),
        ),
      );
    }
    if (image && attachment.localPath == null) {
      return _LoadOnFirstBuild(
        onLoad: imageLoad == null ? onLoadImage : null,
        child: _inlineImageStatus(context),
      );
    }
    final VoidCallback activate = attachment.localPath == null
        ? onDownload
        : video || audio
        ? () => showDialog<void>(
            context: context,
            builder: (context) =>
                MediaPreviewDialog(attachment: attachment, onSave: onSave),
          )
        : onOpen;
    final name =
        attachment.fileName ??
        (video
            ? 'Video'
            : audio
            ? 'Audio'
            : image
            ? 'Image'
            : 'Attachment');
    final action = attachment.localPath == null
        ? 'Download'
        : video || audio
        ? 'Play'
        : 'Open';
    return InkWell(
      borderRadius: BorderRadius.circular(9),
      onTap: activate,
      child: Semantics(
        button: true,
        label:
            '$action $name${attachment.byteCount == null ? '' : ', ${formatByteCount(attachment.byteCount!)}'}',
        excludeSemantics: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: SizedBox(
            width: 280,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(
                  child: _fileCard(
                    context,
                    video
                        ? Icons.play_circle_outline
                        : audio
                        ? Icons.headphones_outlined
                        : image
                        ? Icons.image_outlined
                        : Icons.insert_drive_file_outlined,
                    name,
                  ),
                ),
                if (attachment.localPath == null)
                  Tooltip(
                    message: 'Download attachment',
                    child: Icon(
                      Icons.download_outlined,
                      size: 20,
                      color: foreground,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _linkedContent(BuildContext context) {
    final destination = _destination;
    return SizedBox(
      width: 280,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _fileCard(
            context,
            Icons.link,
            attachment.fileName == null ||
                    (attachment.fileName == caption && caption.isNotEmpty)
                ? 'Shared content'
                : attachment.fileName!,
          ),
          const SizedBox(height: 8),
          if (attachment.deepLink?.isNotEmpty == true && destination != null)
            OutlinedButton.icon(
              onPressed: onOpenLink,
              style: OutlinedButton.styleFrom(
                foregroundColor: foreground,
                side: BorderSide(color: foreground.withValues(alpha: .4)),
              ),
              icon: const Icon(Icons.open_in_new, size: 17),
              label: Text('Open in $destination'),
            )
          else
            Text(
              'This shared item is unavailable.',
              style: TextStyle(
                color: foreground.withValues(alpha: .75),
                fontSize: 12,
              ),
            ),
        ],
      ),
    );
  }

  Widget _inlineImageStatus(BuildContext context) => switch (imageLoad) {
    AttachmentLoadState.failed => SizedBox(
      width: 280,
      child: Row(
        children: [
          Expanded(
            child: _fileCard(
              context,
              Icons.broken_image_outlined,
              'Image unavailable',
            ),
          ),
          TextButton(
            onPressed: onLoadImage,
            style: TextButton.styleFrom(foregroundColor: foreground),
            child: const Text('Retry'),
          ),
        ],
      ),
    ),
    AttachmentLoadState.tooLarge => SizedBox(
      width: 280,
      child: _fileCard(
        context,
        Icons.image_not_supported_outlined,
        'Image too large to preview',
      ),
    ),
    _ => Semantics(
      container: true,
      image: true,
      label: 'Loading image',
      child: Container(
        width: 280,
        height: 190,
        decoration: BoxDecoration(
          color: foreground.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(
          Icons.image_outlined,
          size: 36,
          color: foreground.withValues(alpha: .35),
        ),
      ),
    ),
  };

  Widget _fileCard(BuildContext context, IconData icon, String name) => Row(
    children: [
      Icon(icon, size: 30, color: foreground),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: foreground, fontSize: 13),
            ),
            if (attachment.byteCount != null)
              Text(
                formatByteCount(attachment.byteCount!),
                style: TextStyle(
                  color: foreground.withValues(alpha: .75),
                  fontSize: 11,
                ),
              ),
          ],
        ),
      ),
    ],
  );
}

class _LoadOnFirstBuild extends StatefulWidget {
  const _LoadOnFirstBuild({required this.onLoad, required this.child});

  final Future<void> Function()? onLoad;
  final Widget child;

  @override
  State<_LoadOnFirstBuild> createState() => _LoadOnFirstBuildState();
}

class _LoadOnFirstBuildState extends State<_LoadOnFirstBuild> {
  @override
  void initState() {
    super.initState();
    final load = widget.onLoad;
    if (load != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) load();
      });
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _InlineVideo extends StatefulWidget {
  const _InlineVideo({
    required this.attachment,
    required this.posterPath,
    required this.onDownload,
    required this.onSave,
  });

  final AttachmentRecord attachment;
  final String? posterPath;
  final Future<void> Function() onDownload;
  final Future<void> Function()? onSave;

  @override
  State<_InlineVideo> createState() => _InlineVideoState();
}

class _InlineVideoState extends State<_InlineVideo> {
  bool _loading = false;

  Future<void> _play() async {
    if (widget.attachment.localPath == null) {
      setState(() => _loading = true);
      await widget.onDownload();
      // The downloaded file reaches this tile on the next rebuild.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      setState(() => _loading = false);
    }
    final attachment = widget.attachment;
    if (attachment.localPath == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) =>
          MediaPreviewDialog(attachment: attachment, onSave: widget.onSave),
    );
  }

  @override
  Widget build(BuildContext context) {
    final posterPath = widget.posterPath;
    final placeholder = Container(color: Colors.black);
    return Semantics(
      button: true,
      label: 'Play ${widget.attachment.fileName ?? 'video'}',
      excludeSemantics: true,
      child: InkWell(
        key: Key('inline-video-${widget.attachment.id}'),
        borderRadius: BorderRadius.circular(9),
        onTap: _loading ? null : _play,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: SizedBox(
            width: 280,
            height: 190,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (posterPath == null)
                  placeholder
                else
                  Image.file(
                    File(posterPath),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => placeholder,
                  ),
                Center(
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .55),
                      shape: BoxShape.circle,
                    ),
                    child: _loading
                        ? const Padding(
                            padding: EdgeInsets.all(16),
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(
                            Icons.play_arrow_rounded,
                            size: 36,
                            color: Colors.white,
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SharedPostCard extends StatefulWidget {
  const _SharedPostCard({
    required this.attachment,
    required this.previewPath,
    required this.isReel,
    required this.playable,
    required this.author,
    required this.destination,
    required this.foreground,
    required this.onDownload,
    required this.onOpenLink,
    required this.onSave,
  });

  final AttachmentRecord attachment;
  final String? previewPath;
  final bool isReel;
  final bool playable;
  final String? author;
  final String destination;
  final Color foreground;
  final Future<void> Function() onDownload;
  final Future<void> Function() onOpenLink;
  final Future<void> Function()? onSave;

  @override
  State<_SharedPostCard> createState() => _SharedPostCardState();
}

class _SharedPostCardState extends State<_SharedPostCard> {
  bool _loading = false;

  Future<void> _play() async {
    if (widget.attachment.localPath == null) {
      setState(() => _loading = true);
      await widget.onDownload();
      // The downloaded file reaches this card on the next rebuild.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      setState(() => _loading = false);
    }
    if (widget.attachment.localPath != null) _showPlayer(widget.attachment);
  }

  void _showPlayer(AttachmentRecord attachment) => showDialog<void>(
    context: context,
    builder: (context) =>
        MediaPreviewDialog(attachment: attachment, onSave: widget.onSave),
  );

  @override
  Widget build(BuildContext context) {
    final height = widget.isReel ? 380.0 : 280.0;
    final previewPath = widget.previewPath;
    final placeholder = Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: Icon(
        widget.isReel ? Icons.movie_outlined : Icons.image_outlined,
        size: 40,
        color: Colors.white54,
      ),
    );
    final label = widget.isReel
        ? (widget.playable ? 'Play Reel' : 'Open Reel in ${widget.destination}')
        : 'Open post in ${widget.destination}';
    return SizedBox(
      width: 280,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            label: widget.author == null
                ? label
                : '$label from ${widget.author}',
            excludeSemantics: true,
            child: InkWell(
              key: Key('shared-preview-${widget.attachment.id}'),
              borderRadius: BorderRadius.circular(12),
              onTap: _loading
                  ? null
                  : widget.playable
                  ? _play
                  : widget.onOpenLink,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  height: height,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (previewPath == null)
                        placeholder
                      else
                        Image.file(
                          File(previewPath),
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => placeholder,
                        ),
                      if (widget.isReel)
                        Positioned(
                          top: 10,
                          left: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: .6),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.movie_outlined,
                                  size: 14,
                                  color: Colors.white,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Reel',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (widget.playable)
                        Center(
                          child: Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: .55),
                              shape: BoxShape.circle,
                            ),
                            child: _loading
                                ? const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(
                                    Icons.play_arrow_rounded,
                                    size: 36,
                                    color: Colors.white,
                                  ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (widget.author != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                widget.author!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: widget.foreground,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: widget.onOpenLink,
            style: OutlinedButton.styleFrom(
              foregroundColor: widget.foreground,
              side: BorderSide(color: widget.foreground.withValues(alpha: .4)),
            ),
            icon: const Icon(Icons.open_in_new, size: 17),
            label: Text('Open in ${widget.destination}'),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                icon,
                size: 36,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                letterSpacing: -.3,
              ),
            ),
            const SizedBox(height: 9),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.6,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      ),
    ),
  );
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Future<void> Function()? action;

  @override
  Widget build(BuildContext context) => Container(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    padding: const EdgeInsets.fromLTRB(16, 7, 8, 7),
    child: Row(
      children: [
        Icon(icon, size: 17),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
        if (action != null)
          TextButton(onPressed: action, child: const Text('Retry')),
      ],
    ),
  );
}

enum _ConversationAction { favorite, mute, hide, unread }

Future<void> _showConversationActions(
  BuildContext context,
  InboxUiController controller,
  ConversationRecord conversation, {
  Offset? position,
  List<ConversationRecord>? conversations,
}) async {
  final chats = conversations ?? [conversation];
  final preferences = controller.preferencesFor(conversation.route);
  final muted = chats.every(
    (chat) => controller.preferencesFor(chat.route).isMutedAt(DateTime.now()),
  );
  final favorite = chats.any(
    (chat) => controller.preferencesFor(chat.route).isFavorite,
  );
  final unread = chats.any(
    (chat) =>
        chat.unreadCount > 0 ||
        controller.preferencesFor(chat.route).markedUnread,
  );
  final action = await showMenu<_ConversationAction>(
    context: context,
    position: RelativeRect.fromLTRB(
      position?.dx ?? 0,
      position?.dy ?? 0,
      position?.dx ?? 0,
      position?.dy ?? 0,
    ),
    items: [
      _menuItem(
        _ConversationAction.unread,
        unread ? 'Mark as Read' : 'Mark as Unread',
      ),
      _menuItem(_ConversationAction.mute, muted ? 'Unmute' : 'Mute'),
      _menuItem(
        _ConversationAction.hide,
        preferences.hiddenAt == null ? 'Hide' : 'Show in Inbox',
      ),
      _menuItem(
        _ConversationAction.favorite,
        favorite ? 'Remove from Favourites' : 'Add to Favourites',
      ),
    ],
  );
  DateTime? mutedUntil;
  if (action == _ConversationAction.mute && !muted) {
    if (!context.mounted) return;
    final hours = await showMenu<int>(
      context: context,
      position: RelativeRect.fromLTRB(
        position?.dx ?? 0,
        position?.dy ?? 0,
        position?.dx ?? 0,
        position?.dy ?? 0,
      ),
      items: [
        _menuItem(1, 'For 1 Hour'),
        _menuItem(8, 'For 8 Hours'),
        _menuItem(0, 'Forever'),
      ],
    );
    if (hours == null) return;
    if (hours > 0) mutedUntil = DateTime.now().add(Duration(hours: hours));
  }
  for (final chat in chats) {
    switch (action) {
      case _ConversationAction.unread:
        await controller.setUnread(chat.route, !unread);
      case _ConversationAction.favorite:
        await controller.setFavorite(chat.route, !favorite);
      case _ConversationAction.mute:
        await controller.setMuted(chat.route, !muted, until: mutedUntil);
      case _ConversationAction.hide:
        await controller.setHidden(chat.route, preferences.hiddenAt == null);
      case null:
        break;
    }
    if (controller.error != null) return;
  }
}

AccountRecord? _accountFor(
  InboxUiController controller,
  ConversationRoute route,
) => controller.accounts
    .where((account) => account.id == route.accountId)
    .firstOrNull;
String _networkName(InboxUiController controller, String? platform) =>
    controller.networks
        .where((network) => network.id == platform)
        .firstOrNull
        ?.name ??
    (platform ?? 'Account');
bool _sameDay(DateTime a, DateTime b) {
  final localA = a.toLocal();
  final localB = b.toLocal();
  return localA.year == localB.year &&
      localA.month == localB.month &&
      localA.day == localB.day;
}

bool _sameMessageRun(MessageRecord first, MessageRecord second) {
  final interval = second.timestamp.difference(first.timestamp);
  return first.route == second.route &&
      first.isOutgoing == second.isOutgoing &&
      (first.isOutgoing || first.senderName != null) &&
      first.senderName == second.senderName &&
      _sameDay(first.timestamp, second.timestamp) &&
      !interval.isNegative &&
      interval <= const Duration(minutes: 5);
}

String _time(DateTime date) {
  final local = date.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

String _dayLabel(DateTime date) {
  final now = DateTime.now();
  final local = date.toLocal();
  if (_sameDay(now, local)) return 'Today';
  if (_sameDay(now.subtract(const Duration(days: 1)), local)) {
    return 'Yesterday';
  }
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${local.day} ${months[local.month - 1]}${local.year == now.year ? '' : ' ${local.year}'}';
}
