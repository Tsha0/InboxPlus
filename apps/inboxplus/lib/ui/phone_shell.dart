part of 'inbox_app.dart';

enum _ShowFilter {
  all('All'),
  unread('Unread'),
  unanswered('Unanswered'),
  drafts('Drafts'),
  dms('DMs'),
  groups('Groups');

  const _ShowFilter(this.label);
  final String label;
}

const _phoneBarHeight = 52.0;

class _PhoneBottomBar extends StatelessWidget {
  const _PhoneBottomBar({
    required this.section,
    required this.onSelect,
    required this.unreadCount,
    required this.settingsNeedAttention,
    this.onFilter,
    this.filterActive = false,
    this.onCompose,
  });

  final _Section section;
  final ValueChanged<_Section> onSelect;
  final int unreadCount;
  final bool settingsNeedAttention;
  final VoidCallback? onFilter;
  final bool filterActive;
  final VoidCallback? onCompose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final inset = MediaQuery.viewPaddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, inset > 0 ? inset - 6 : 14),
      child: SizedBox(
        height: _phoneBarHeight,
        child: Row(
          children: [
            if (onFilter case final onFilter?)
              _PhoneRoundButton(
                key: const Key('inbox-filter'),
                tooltip: filterActive
                    ? 'Filter inbox, filters on'
                    : 'Filter inbox',
                onPressed: onFilter,
                filled: filterActive,
                child: const Icon(CupertinoIcons.line_horizontal_3_decrease),
              )
            else
              const SizedBox(width: _phoneBarHeight),
            Expanded(
              child: Center(
                child: _PhoneTabPill(
                  section: section,
                  onSelect: onSelect,
                  unreadCount: unreadCount,
                  settingsNeedAttention: settingsNeedAttention,
                ),
              ),
            ),
            if (onCompose case final onCompose?)
              _PhoneRoundButton(
                tooltip: 'New message',
                onPressed: onCompose,
                background: scheme.primary,
                foreground: scheme.onPrimary,
                child: const Icon(CupertinoIcons.square_pencil),
              )
            else
              const SizedBox(width: _phoneBarHeight),
          ],
        ),
      ),
    );
  }
}

class _PhoneGlass extends StatelessWidget {
  const _PhoneGlass({required this.child, this.radius = 26, this.color});

  final Widget child;
  final double radius;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final shape = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? .45 : .14),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: shape,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: shape,
              color:
                  color ??
                  (dark
                      ? const Color(0xff1f2024).withValues(alpha: .88)
                      : Colors.white.withValues(alpha: .82)),
              border: Border.all(
                color: dark
                    ? Colors.white.withValues(alpha: .1)
                    : Colors.black.withValues(alpha: .06),
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _PhoneRoundButton extends StatelessWidget {
  const _PhoneRoundButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
    required this.child,
    this.filled = false,
    this.background,
    this.foreground,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final Widget child;
  final bool filled;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ink = foreground ?? (filled ? scheme.surface : scheme.onSurface);
    final button = IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      iconSize: 22,
      color: ink,
      style: IconButton.styleFrom(
        fixedSize: const Size.square(_phoneBarHeight),
        backgroundColor: filled ? scheme.onSurface : background,
      ),
      icon: child,
    );
    if (background != null || filled) {
      return DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .25),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: button,
      );
    }
    return _PhoneGlass(radius: _phoneBarHeight / 2, child: button);
  }
}

class _PhoneTabPill extends StatelessWidget {
  const _PhoneTabPill({
    required this.section,
    required this.onSelect,
    required this.unreadCount,
    required this.settingsNeedAttention,
  });

  final _Section section;
  final ValueChanged<_Section> onSelect;
  final int unreadCount;
  final bool settingsNeedAttention;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return LayoutBuilder(
      builder: (context, constraints) => FittedBox(
        fit: BoxFit.scaleDown,
        child: _build(context, scheme, dark, constraints.maxWidth >= 250),
      ),
    );
  }

  Widget _build(
    BuildContext context,
    ColorScheme scheme,
    bool dark,
    bool showsLabel,
  ) {
    return _PhoneGlass(
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
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
              Semantics(
                button: true,
                selected: section == value,
                label: switch (value) {
                  _Section.inbox when unreadCount > 0 =>
                    '$label, $unreadCount unread',
                  _Section.settings when settingsNeedAttention =>
                    '$label, an account needs attention',
                  _ => label,
                },
                excludeSemantics: true,
                onTap: () => onSelect(value),
                child: GestureDetector(
                  key: Key('phone-tab-${value.name}'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onSelect(value),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    height: _phoneBarHeight - 10,
                    constraints: const BoxConstraints(minWidth: 54),
                    padding: EdgeInsets.symmetric(
                      horizontal: section == value && showsLabel ? 16 : 12,
                    ),
                    decoration: BoxDecoration(
                      color: section == value
                          ? scheme.onSurface.withValues(alpha: dark ? .14 : .08)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(21),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Badge(
                          isLabelVisible: switch (value) {
                            _Section.inbox => unreadCount > 0,
                            _Section.settings => settingsNeedAttention,
                            _Section.contacts => false,
                          },
                          smallSize: 8,
                          label: value == _Section.inbox
                              ? Text('$unreadCount')
                              : null,
                          backgroundColor: value == _Section.settings
                              ? const Color(0xfff0a37a)
                              : scheme.primary,
                          textColor: scheme.onPrimary,
                          child: Icon(
                            section == value ? selectedIcon : icon,
                            size: 22,
                            color: section == value
                                ? scheme.onSurface
                                : scheme.onSurface.withValues(alpha: .7),
                          ),
                        ),
                        if (section == value && showsLabel) ...[
                          const SizedBox(width: 7),
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurface,
                            ),
                          ),
                        ],
                      ],
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

class _PhoneFilterMenu extends StatefulWidget {
  const _PhoneFilterMenu({
    required this.controller,
    required this.show,
    required this.networks,
    required this.selectedNetworks,
    required this.onShow,
    required this.onToggleNetwork,
    required this.onFeedback,
  });

  final InboxUiController controller;
  final _ShowFilter show;
  final List<String> networks;
  final Set<String> selectedNetworks;
  final ValueChanged<_ShowFilter> onShow;
  final ValueChanged<String> onToggleNetwork;
  final VoidCallback onFeedback;

  @override
  State<_PhoneFilterMenu> createState() => _PhoneFilterMenuState();
}

class _PhoneFilterMenuState extends State<_PhoneFilterMenu> {
  late var _show = widget.show;
  late final _networks = {...widget.selectedNetworks};

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          letterSpacing: .6,
          fontWeight: FontWeight.w600,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
    Widget divider() => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Divider(height: 1, color: scheme.outlineVariant),
    );
    Widget item({
      required String label,
      required VoidCallback onTap,
      Widget? leading,
      Widget? trailing,
      bool selected = false,
      Key? key,
    }) => Semantics(
      selected: selected,
      child: InkWell(
        key: key,
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: selected
                ? scheme.onSurface.withValues(alpha: dark ? .1 : .06)
                : null,
          ),
          child: Row(
            children: [
              SizedBox(width: 22, child: leading),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label, style: const TextStyle(fontSize: 16)),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
    final check = Icon(Icons.check, size: 19, color: scheme.primary);
    return _PhoneGlass(
      radius: 22,
      color: dark ? const Color(0xff232428) : Colors.white,
      child: Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              heading('Show'),
              for (final filter in _ShowFilter.values)
                item(
                  key: Key('filter-${filter.name}'),
                  label: filter.label,
                  selected: _show == filter,
                  leading: _show == filter ? check : null,
                  onTap: () {
                    setState(() => _show = filter);
                    widget.onShow(filter);
                  },
                ),
              if (widget.networks.length > 1) ...[
                divider(),
                heading('Networks'),
                for (final network in widget.networks)
                  item(
                    label: _networkName(widget.controller, network),
                    selected: _networks.contains(network),
                    leading: NetworkBadge(
                      network: network,
                      size: 22,
                      labelled: false,
                    ),
                    trailing: Icon(
                      _networks.contains(network)
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      size: 22,
                      color: _networks.contains(network)
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                    ),
                    onTap: () {
                      setState(() {
                        if (!_networks.remove(network)) _networks.add(network);
                      });
                      widget.onToggleNetwork(network);
                    },
                  ),
              ],
              divider(),
              item(
                key: const Key('filter-send-feedback'),
                label: 'Send feedback',
                leading: Icon(
                  CupertinoIcons.chat_bubble_text,
                  size: 19,
                  color: scheme.onSurfaceVariant,
                ),
                trailing: Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
                onTap: widget.onFeedback,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhoneAttachMenu extends StatelessWidget {
  const _PhoneAttachMenu({required this.onPick});

  final ValueChanged<bool> onPick;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    Widget item({
      required Key key,
      required IconData icon,
      required String label,
      required String hint,
      required bool media,
    }) => InkWell(
      key: key,
      onTap: () => onPick(media),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        constraints: const BoxConstraints(minHeight: 60),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: scheme.onSurface.withValues(alpha: dark ? .12 : .07),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: scheme.onSurface),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    hint,
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return _PhoneGlass(
      radius: 22,
      color: dark ? const Color(0xff232428) : Colors.white,
      child: Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              item(
                key: const Key('attach-files'),
                icon: CupertinoIcons.doc,
                label: 'Files',
                hint: 'Documents from iCloud Drive or this iPhone',
                media: false,
              ),
              item(
                key: const Key('attach-photos'),
                icon: CupertinoIcons.photo,
                label: 'Photos',
                hint: 'Pictures and videos from your library',
                media: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhoneFavoritesRow extends StatelessWidget {
  const _PhoneFavoritesRow({
    required this.controller,
    required this.favorites,
    required this.onOpen,
    required this.onActions,
  });

  final InboxUiController controller;
  final List<ConversationRecord> favorites;
  final ValueChanged<ConversationRecord> onOpen;
  final ValueChanged<ConversationRecord> onActions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 104,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final item in favorites)
            Semantics(
              button: true,
              label: '${item.title}, favourite',
              excludeSemantics: true,
              onTap: () => onOpen(item),
              onLongPress: () => onActions(item),
              child: InkWell(
                key: Key(
                  'favorite-${item.route.accountId}-${item.route.conversationId}',
                ),
                borderRadius: BorderRadius.circular(16),
                onTap: () => onOpen(item),
                onLongPress: () => onActions(item),
                child: SizedBox(
                  width: 84,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Badge(
                        isLabelVisible: item.unreadCount > 0,
                        label: Text('${item.unreadCount}'),
                        backgroundColor: scheme.primary,
                        textColor: scheme.onPrimary,
                        child: PersonAvatar(
                          name: item.title,
                          bytes: item.avatarBytes,
                          network: _accountFor(
                            controller,
                            item.route,
                          )?.platform,
                          isGroup: item.isGroup,
                          size: 60,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        item.title.split(' ').first,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: scheme.onSurfaceVariant,
                        ),
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
}

class _PhoneActiveFilters extends StatelessWidget {
  const _PhoneActiveFilters({required this.labels, required this.onClear});

  final List<String> labels;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Row(
        children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
              decoration: BoxDecoration(
                color: scheme.onSurface.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    CupertinoIcons.line_horizontal_3_decrease,
                    size: 15,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      labels.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Clear filters',
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    onPressed: onClear,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
