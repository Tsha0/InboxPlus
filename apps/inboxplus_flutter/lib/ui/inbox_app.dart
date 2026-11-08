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
import 'reaction_picker.dart';

part 'desktop_shell.dart';
part 'desktop_preferences.dart';

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
    final accent = _DesktopPalette.forPreferences(controller.preferences)
        ?.accent;
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
  bool _unreadOnly = false;
  bool _unknownOnly = false;
  bool _hidden = false;
  double _logoTurns = 0;
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
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _searchFocus.requestFocus(),
    );
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
    final floatingTabs =
        showsTabs && defaultTargetPlatform == TargetPlatform.iOS;
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
          extendBody: floatingTabs,
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
              : floatingTabs
              ? _GlassTabBar(
                  section: _section,
                  onSelect: _selectSection,
                  unreadCount: _unreadTotal,
                )
              : _PhoneNavigationBar(
                  controller: controller,
                  section: _section,
                  onSelect: _selectSection,
                  unreadCount: _unreadTotal,
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
          onConnect: _connect,
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

  void _animateLogo() => setState(() => _logoTurns += 1);

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
          if ((preferences.hiddenAt != null) != _hidden) return false;
          if (_networks.isNotEmpty &&
              !_networks.contains(
                _accountFor(controller, item.route)?.platform,
              )) {
            return false;
          }
          if ((item.isFromUnknownSender &&
                  _personFor(controller, item) == null) !=
              _unknownOnly) {
            return false;
          }
          if (_unreadOnly &&
              item.unreadCount == 0 &&
              !preferences.markedUnread) {
            return false;
          }
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
    const networkOrder = [
      'whatsapp',
      'instagram',
      'messenger',
      'telegram',
      'imessage',
    ];
    final networks =
        <String>{
          for (final chat in controller.conversations)
            if ((controller.preferencesFor(chat.route).hiddenAt != null) ==
                _hidden)
              ?_accountFor(controller, chat.route)?.platform,
          ..._networks,
        }.where((platform) => platform != 'legacy').toList()..sort(
          (a, b) => networkOrder.indexOf(a).compareTo(networkOrder.indexOf(b)),
        );
    final hiddenCount = controller.conversations
        .where((chat) => controller.preferencesFor(chat.route).hiddenAt != null)
        .length;
    final hasUnknownSenders = controller.conversations.any(
      (chat) =>
          chat.isFromUnknownSender && _personFor(controller, chat) == null,
    );
    final unread = _unreadTotal;
    final apple = defaultTargetPlatform == TargetPlatform.iOS;
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
                title: _hidden ? 'Hidden' : inboxPlusAppName,
                unread: unread,
                ink: headerInk,
                background: headerColor,
                translucent: apple,
                leading: Semantics(
                  label: 'Inbox+ logo',
                  button: true,
                  onTap: _animateLogo,
                  excludeSemantics: true,
                  child: GestureDetector(
                    onTap: _animateLogo,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: AnimatedRotation(
                        turns: _logoTurns,
                        duration: const Duration(milliseconds: 700),
                        curve: Curves.easeInOutBack,
                        child: _DesktopLogo(
                          color: palette?.logo ?? scheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),
                trailing: IconButton(
                  tooltip: 'New message',
                  onPressed: _compose,
                  color: headerInk,
                  icon: Icon(
                    apple ? CupertinoIcons.square_pencil : Icons.edit_square,
                    size: 23,
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
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: SizedBox(
                        height: 36,
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
                            fillColor: scheme.onSurface.withValues(alpha: .06),
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
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: Row(
                        children: [
                          _PhonePill(
                            label: 'All',
                            selected:
                                !_unreadOnly &&
                                !_unknownOnly &&
                                _networks.isEmpty,
                            onPressed: () => setState(() {
                              _unreadOnly = false;
                              _unknownOnly = false;
                              _networks.clear();
                            }),
                          ),
                          _PhonePill(
                            label: 'Unread',
                            selected: _unreadOnly,
                            onPressed: () => setState(() {
                              _unreadOnly = true;
                              _unknownOnly = false;
                            }),
                          ),
                          if (_unknownOnly || hasUnknownSenders)
                            _PhonePill(
                              label: 'Unknown senders',
                              selected: _unknownOnly,
                              onPressed: () => setState(() {
                                _unknownOnly = true;
                                _unreadOnly = false;
                              }),
                            ),
                        ],
                      ),
                    ),
                    if (networks.length > 1 || _networks.isNotEmpty)
                      SizedBox(
                        height: 36,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                          children: [
                            for (final network in networks)
                              _PhonePill(
                                label: _networkName(controller, network),
                                selected: _networks.contains(network),
                                outlined: true,
                                leading: NetworkBadge(
                                  network: network,
                                  size: 18,
                                  labelled: false,
                                ),
                                onPressed: () => setState(() {
                                  if (!_networks.remove(network)) {
                                    _networks.add(network);
                                  }
                                }),
                              ),
                          ],
                        ),
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
                        : _unreadOnly
                        ? 'All caught up'
                        : _hidden
                        ? 'No hidden conversations'
                        : 'Your inbox starts here',
                    message: query.isNotEmpty
                        ? 'Try another name or message.'
                        : _hidden
                        ? 'Conversations you hide will appear here.'
                        : controller.accounts.isEmpty
                        ? 'Connect an account and your conversations will appear here.'
                        : 'New conversations will appear here.',
                    action: _hidden
                        ? TextButton(
                            onPressed: () => setState(() => _hidden = false),
                            child: const Text('Back to Inbox'),
                          )
                        : controller.accounts.isEmpty && query.isEmpty
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
                itemCount:
                    conversations.length + (_hidden || hiddenCount > 0 ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == conversations.length) {
                    return ColoredBox(
                      color: sheetColor,
                      child: Center(
                        child: TextButton(
                          onPressed: () => setState(() => _hidden = !_hidden),
                          child: Text(
                            _hidden ? 'Back to Inbox' : '$hiddenCount hidden',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ),
                    );
                  }
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
    await _showConversationActions(context, controller, item);
  }
}

Color _phoneHeaderColor(BuildContext context, InboxUiController controller) =>
    _DesktopPalette.forPreferences(controller.preferences)?.background ??
    Theme.of(context).colorScheme.surfaceContainerLow;

ContactRecord? _personFor(
  InboxUiController controller,
  ConversationRecord conversation,
) => controller.contacts
    .where(
      (person) => person.identities.any(
        (identity) =>
            identity.accountId == conversation.route.accountId &&
            identity.identityId == conversation.identityId,
      ),
    )
    .firstOrNull;

class _PhoneInboxHeader extends SliverPersistentHeaderDelegate {
  _PhoneInboxHeader({
    required this.title,
    required this.unread,
    required this.ink,
    required this.background,
    required this.translucent,
    required this.leading,
    required this.trailing,
  });

  static const _barHeight = 52.0;
  static const _titleHeight = 52.0;

  final String title;
  final int unread;
  final Color ink;
  final Color background;
  final bool translucent;
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
              child: translucent && collapse == 1
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

class _PhonePill extends StatelessWidget {
  const _PhonePill({
    required this.label,
    required this.selected,
    required this.onPressed,
    this.outlined = false,
    this.leading,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;
  final bool outlined;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Semantics(
        selected: selected,
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            minimumSize: Size(0, outlined ? 28 : 30),
            padding: EdgeInsets.fromLTRB(leading == null ? 12 : 5, 0, 12, 0),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            foregroundColor: scheme.onSurface,
            backgroundColor: selected
                ? scheme.onSurface.withValues(alpha: .09)
                : outlined
                ? scheme.surface
                : Colors.transparent,
            shape: StadiumBorder(
              side: outlined
                  ? BorderSide(color: scheme.outlineVariant)
                  : BorderSide.none,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leading case final leading?) ...[
                leading,
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: outlined ? 12 : 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
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
    final favorite = preferences.isFavorite;
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
    void mute() => _run(() => controller.setMuted(item.route, !muted));
    void hide() => _run(
      () => controller.setHidden(item.route, preferences.hiddenAt == null),
    );
    return Semantics(
      customSemanticsActions: {
        CustomSemanticsAction(label: muteLabel): mute,
        CustomSemanticsAction(label: hideLabel): hide,
      },
      child: GestureDetector(
        onHorizontalDragUpdate: (details) => setState(
          () =>
              _reveal = (_reveal - details.delta.dx).clamp(0, _actionWidth * 2),
        ),
        onHorizontalDragEnd: (_) => setState(
          () => _reveal = _reveal > _actionWidth ? _actionWidth * 2 : 0,
        ),
        child: ClipRect(
          child: SizedBox(
            height: 64,
            child: Stack(
              children: [
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
                      onTap: _reveal > 0
                          ? () => setState(() => _reveal = 0)
                          : widget.onOpen,
                      onLongPress: widget.onActions,
                      child: Row(
                        children: [
                          const SizedBox(width: 16),
                          NetworkBadge(network: account?.platform, size: 40),
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
                          IconButton(
                            tooltip:
                                '${favorite ? 'Unfavourite' : 'Favourite'} ${item.title}',
                            onPressed: () =>
                                controller.setFavorite(item.route, !favorite),
                            icon: Icon(
                              favorite ? Icons.star : Icons.star_border,
                              size: 20,
                              color: favorite
                                  ? scheme.onSurface
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 4),
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
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

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
            Icon(icon, size: 19, color: Colors.white),
            const SizedBox(height: 3),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _GlassTabBar extends StatelessWidget {
  const _GlassTabBar({
    required this.section,
    required this.onSelect,
    required this.unreadCount,
  });

  final _Section section;
  final ValueChanged<_Section> onSelect;
  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = Theme.of(context).colorScheme.onSurface;
    final inset = MediaQuery.viewPaddingOf(context).bottom;
    const radius = BorderRadius.all(Radius.circular(31));
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, inset > 0 ? inset - 8 : 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? .4 : .14),
              blurRadius: 32,
              offset: const Offset(0, 12),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: .06),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              height: 62,
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(
                  color: Colors.white.withValues(alpha: dark ? .14 : .85),
                ),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: dark
                      ? [
                          const Color(0xff2c2c2e).withValues(alpha: .82),
                          const Color(0xff2c2c2e).withValues(alpha: .62),
                        ]
                      : [
                          Colors.white.withValues(alpha: .82),
                          Colors.white.withValues(alpha: .55),
                        ],
                ),
              ),
              child: Row(
                children: [
                  for (final (value, label, icon, selectedIcon) in [
                    (
                      _Section.inbox,
                      'Inbox',
                      CupertinoIcons.tray,
                      CupertinoIcons.tray_fill,
                    ),
                    (
                      _Section.contacts,
                      'Contacts',
                      CupertinoIcons.person_2,
                      CupertinoIcons.person_2_fill,
                    ),
                    (
                      _Section.settings,
                      'Settings',
                      CupertinoIcons.gear,
                      CupertinoIcons.gear_solid,
                    ),
                  ])
                    Expanded(
                      child: Semantics(
                        button: true,
                        selected: section == value,
                        label: label,
                        excludeSemantics: true,
                        onTap: () => onSelect(value),
                        child: GestureDetector(
                          key: Key('phone-tab-${value.name}'),
                          behavior: HitTestBehavior.opaque,
                          onTap: () => onSelect(value),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            decoration: BoxDecoration(
                              color: section == value
                                  ? ink.withValues(alpha: dark ? .14 : .07)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(26),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Badge(
                                  isLabelVisible:
                                      value == _Section.inbox &&
                                      unreadCount > 0,
                                  label: Text('$unreadCount'),
                                  backgroundColor: Theme.of(context)
                                      .colorScheme
                                      .primary,
                                  textColor: Theme.of(context)
                                      .colorScheme
                                      .onPrimary,
                                  child: Icon(
                                    section == value ? selectedIcon : icon,
                                    size: 24,
                                    color: section == value
                                        ? ink
                                        : ink.withValues(alpha: .72),
                                  ),
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  label,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: section == value
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                    color: section == value
                                        ? ink
                                        : ink.withValues(alpha: .72),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PhoneNavigationBar extends StatelessWidget {
  const _PhoneNavigationBar({
    required this.controller,
    required this.section,
    required this.onSelect,
    required this.unreadCount,
  });

  final InboxUiController controller;
  final _Section section;
  final ValueChanged<_Section> onSelect;
  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = _DesktopPalette.forPreferences(controller.preferences);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: NavigationBar(
        height: 72,
        selectedIndex: section.index,
        onDestinationSelected: (value) => onSelect(_Section.values[value]),
        backgroundColor: palette == null
            ? scheme.surfaceContainerLow
            : Color.alphaBlend(
                palette.background.withValues(alpha: .11),
                scheme.surface,
              ),
        indicatorColor: palette == null
            ? scheme.onSurface.withValues(alpha: .09)
            : palette.accent.withValues(alpha: .22),
        surfaceTintColor: Colors.transparent,
        destinations: [
          NavigationDestination(
            icon: Badge(
              isLabelVisible: unreadCount > 0,
              label: Text('$unreadCount'),
              backgroundColor: scheme.primary,
              textColor: scheme.onPrimary,
              child: const Icon(Icons.inbox_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: unreadCount > 0,
              label: Text('$unreadCount'),
              backgroundColor: scheme.primary,
              textColor: scheme.onPrimary,
              child: const Icon(Icons.inbox),
            ),
            label: 'Inbox',
          ),
          const NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Contacts',
          ),
          const NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
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
  final _messageKeys = <String, GlobalKey>{};

  Future<void> _revealMessage(String id) async {
    if (!_scroll.hasClients) return;
    _scroll.jumpTo(_scroll.position.maxScrollExtent);
    while (mounted && widget.highlightedMessageId == id && _scroll.hasClients) {
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
    if (_highlightedMessageId != widget.highlightedMessageId) {
      _highlightedMessageId = widget.highlightedMessageId;
      if (_highlightedMessageId case final id?) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _revealMessage(id));
      }
    }
    final account = _accountFor(controller, item.route);
    final capability = controller.networks
        .where((network) => network.id == account?.platform)
        .firstOrNull;
    final muted = controller
        .preferencesFor(item.route)
        .isMutedAt(DateTime.now());
    if (_messageCount != messages.length) {
      final wasNearBottom =
          !_scroll.hasClients ||
          _scroll.position.maxScrollExtent - _scroll.offset < 180;
      _messageCount = messages.length;
      if (wasNearBottom && widget.highlightedMessageId == null) {
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
          Container(
            constraints: const BoxConstraints(minHeight: 60),
            padding: const EdgeInsets.fromLTRB(4, 6, 6, 6),
            child: Row(
              children: [
                if (widget.onBack != null)
                  IconButton(
                    key: const Key('back-to-inbox'),
                    tooltip: 'Back to inbox',
                    onPressed: widget.onBack,
                    icon: Icon(
                      defaultTargetPlatform == TargetPlatform.iOS
                          ? CupertinoIcons.back
                          : Icons.arrow_back,
                    ),
                  )
                else
                  const SizedBox(width: 12),
                NetworkBadge(network: account?.platform, size: 32),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '${_networkName(controller, account?.platform)}${item.isGroup ? ' · Group conversation' : ''}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: muted ? 'Unmute conversation' : 'Mute conversation',
                  onPressed: () => controller.setMuted(item.route, !muted),
                  icon: Icon(
                    muted
                        ? Icons.notifications_off_outlined
                        : Icons.notifications_none,
                    size: 22,
                  ),
                ),
                IconButton(
                  tooltip: 'Conversation actions',
                  onPressed: () =>
                      _showConversationActions(context, controller, item),
                  icon: const Icon(Icons.more_horiz),
                ),
              ],
            ),
          ),
        const Divider(height: 1),
        Expanded(
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
                        : messages
                              .where(
                                (item) => item.id == message.replyToMessageId,
                              )
                              .firstOrNull;
                    return Container(
                      key: _messageKeys.putIfAbsent(message.id, GlobalKey.new),
                      decoration: widget.highlightedMessageId == message.id
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
                          _MessageBubble(
                            message: message,
                            conversation: item,
                            controller: controller,
                            capability: capability,
                            replyPreview: repliedTo?.body,
                            desktop: widget.desktop,
                            showsTimestamp:
                                !widget.desktop ||
                                index + 1 == messages.length ||
                                !_sameMessageRun(message, messages[index + 1]),
                            showsSender:
                                !widget.desktop ||
                                index == 0 ||
                                !_sameMessageRun(messages[index - 1], message),
                          ),
                        ],
                      ),
                    );
                  },
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

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.conversation,
    required this.controller,
    this.capability,
    this.desktop = false,
    this.replyPreview,
    this.showsTimestamp = true,
    this.showsSender = true,
  });

  final MessageRecord message;
  final ConversationRecord conversation;
  final InboxUiController controller;
  final NetworkCapability? capability;
  final bool desktop;
  final String? replyPreview;
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
                        borderRadius: BorderRadius.circular(desktop ? 12 : 17),
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
                              Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.only(left: 8),
                                decoration: BoxDecoration(
                                  border: Border(
                                    left: BorderSide(
                                      color:
                                          (own
                                                  ? scheme.onPrimary
                                                  : scheme.primary)
                                              .withValues(alpha: .5),
                                      width: 2,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  replyPreview?.isNotEmpty == true
                                      ? replyPreview!
                                      : 'Reply to a message',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            for (final attachment in message.attachments)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: _AttachmentTile(
                                  attachment: attachment,
                                  foreground: own
                                      ? scheme.onPrimary
                                      : scheme.onSurface,
                                  onDownload: () =>
                                      controller.downloadAttachment(
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
                            if (message.body.isNotEmpty)
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
              if (!desktop && (message.body.isNotEmpty || canReply || canReact))
                PopupMenuButton<String>(
                  tooltip: 'Message actions',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 160),
                  iconSize: 17,
                  icon: Icon(Icons.more_horiz, color: scheme.onSurfaceVariant),
                  onSelected: (action) {
                    if (action == 'copy') {
                      Clipboard.setData(ClipboardData(text: message.body));
                    }
                    if (action == 'reply') {
                      controller.setReplyTo(message.route, message.id);
                    }
                    if (action == 'react') _chooseReaction(context);
                  },
                  itemBuilder: (_) => [
                    if (canReply)
                      const PopupMenuItem(
                        value: 'reply',
                        child: ListTile(
                          leading: Icon(Icons.reply),
                          title: Text('Reply'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    if (canReact)
                      const PopupMenuItem(
                        value: 'react',
                        child: ListTile(
                          leading: Icon(Icons.add_reaction_outlined),
                          title: Text('React'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    if (message.body.isNotEmpty)
                      const PopupMenuItem(
                        value: 'copy',
                        child: ListTile(
                          leading: Icon(Icons.copy_outlined),
                          title: Text('Copy text'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                  ],
                ),
              if (!own) SizedBox(width: desktop ? 60 : 24),
            ],
          ),
        ),
      ),
    );
    if (!desktop) return bubble;
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
          if (draft?.attachments.isNotEmpty ?? false)
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
                      tooltip: 'Attach files',
                      onPressed: controller.isBusy
                          ? null
                          : () => controller.stageAttachments(route),
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
                              semanticLabel: 'Attach files',
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
                          hintText: 'Message',
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
    required this.foreground,
    required this.onDownload,
    required this.onOpen,
    required this.onOpenLink,
    this.onSave,
    this.linkPlatform,
    this.playsInstagramReels = false,
  });

  final AttachmentRecord attachment;
  final Color foreground;
  final Future<void> Function() onDownload;
  final Future<void> Function() onOpen;
  final Future<void> Function() onOpenLink;
  final Future<void> Function()? onSave;
  final String? linkPlatform;
  final bool playsInstagramReels;

  @override
  Widget build(BuildContext context) {
    final link = Uri.tryParse(attachment.deepLink ?? '');
    final isReel =
        linkPlatform == 'instagram' &&
        (attachment.kind == 'reel' ||
            link?.pathSegments.firstOrNull == 'reel' ||
            link?.pathSegments.firstOrNull == 'reels');
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
    final destination = switch (linkPlatform) {
      'instagram' => 'Instagram',
      'messenger' => 'Facebook',
      _ => null,
    };
    return SizedBox(
      width: 280,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _fileCard(
            context,
            Icons.link,
            attachment.fileName ?? 'Shared content',
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
  final action = isDesktopPlatform
      ? await showMenu<_ConversationAction>(
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
        )
      : await showModalBottomSheet<_ConversationAction>(
          context: context,
          showDragHandle: true,
          builder: (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                  child: Text(
                    conversation.title,
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ListTile(
                  leading: Icon(favorite ? Icons.star : Icons.star_border),
                  title: Text(
                    favorite ? 'Remove from favorites' : 'Add to favorites',
                  ),
                  onTap: () =>
                      Navigator.pop(context, _ConversationAction.favorite),
                ),
                ListTile(
                  leading: Icon(
                    muted
                        ? Icons.notifications_outlined
                        : Icons.notifications_off_outlined,
                  ),
                  title: Text(
                    muted ? 'Unmute conversation' : 'Mute conversation',
                  ),
                  onTap: () => Navigator.pop(context, _ConversationAction.mute),
                ),
                ListTile(
                  leading: Icon(
                    preferences.hiddenAt == null
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                  title: Text(
                    preferences.hiddenAt == null
                        ? 'Hide conversation'
                        : 'Unhide conversation',
                  ),
                  subtitle: preferences.hiddenAt == null
                      ? const Text('Find it later in Hidden or Settings.')
                      : null,
                  onTap: () => Navigator.pop(context, _ConversationAction.hide),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
  DateTime? mutedUntil;
  if (action == _ConversationAction.mute && !muted && isDesktopPlatform) {
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
