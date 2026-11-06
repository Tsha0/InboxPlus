import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:inboxplus_storage/inboxplus_storage.dart';

import 'inbox_ui_controller.dart';

class NewConversationDialog extends StatefulWidget {
  const NewConversationDialog({
    super.key,
    required this.controller,
    this.initialIdentity,
    this.desktop = false,
  });

  final InboxUiController controller;
  final IdentityLink? initialIdentity;
  final bool desktop;

  @override
  State<NewConversationDialog> createState() => _NewConversationDialogState();
}

class _NewConversationDialogState extends State<NewConversationDialog> {
  late final TextEditingController _query;
  final _queryFocus = FocusNode();
  String? _accountId;
  LocalRecipient? _selected;
  LocalRecipientSnapshot _contacts = const LocalRecipientSnapshot.available();
  int _contactRefresh = 0;
  bool _loadingContacts = false;
  bool _submitting = false;
  String? _error;

  List<AccountRecord> get _accounts => widget.controller.accounts;
  AccountRecord? get _account =>
      _accounts.where((account) => account.id == _accountId).firstOrNull;
  bool get _isIMessage => _account?.platform == 'imessage';
  bool _supportsStart(AccountRecord account) =>
      account.isConnected &&
      widget.controller.networks.any(
        (network) =>
            network.id == account.platform && network.canStartConversation,
      );
  bool get _supported => _account != null && _supportsStart(_account!);
  String get _recipient {
    if (_selected != null) return _selected!.address;
    final text = _query.text.trim();
    return !_isIMessage || text.contains('@') || text.startsWith('+')
        ? text
        : '';
  }

  bool get _canOpen => _supported && !_submitting && _recipient.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _query = TextEditingController(
      text: widget.initialIdentity?.identityId ?? '',
    );
    _accountId =
        widget.initialIdentity?.accountId ??
        _accounts.where(_supportsStart).firstOrNull?.id ??
        _accounts.where((account) => account.isConnected).firstOrNull?.id ??
        _accounts.firstOrNull?.id;
    if (_isIMessage && _supported) unawaited(_refreshContacts());
  }

  @override
  void dispose() {
    _query.dispose();
    _queryFocus.dispose();
    super.dispose();
  }

  void _changeAccount(String? value) {
    setState(() {
      _accountId = value;
      _query.clear();
      _selected = null;
      _error = null;
      _contacts = const LocalRecipientSnapshot.available();
      _contactRefresh++;
      _loadingContacts = false;
    });
    if (_isIMessage && _supported) unawaited(_refreshContacts());
  }

  Future<void> _refreshContacts() async {
    final accountId = _accountId!;
    final refresh = ++_contactRefresh;
    setState(() => _loadingContacts = true);
    final contacts = await widget.controller.recipientContacts(accountId);
    if (!mounted || refresh != _contactRefresh || accountId != _accountId) {
      return;
    }
    setState(() {
      _contacts = contacts;
      _loadingContacts = false;
    });
  }

  Future<void> _open() async {
    if (!_canOpen) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.controller.startConversation(_accountId!, _recipient);
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = widget.controller.error;
      });
      if (_error == null) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'This conversation could not be opened. Check the recipient and try again.';
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => PopScope(
      canPop: !_submitting,
      child: widget.desktop
          ? Dialog(
              backgroundColor: Theme.of(context).colorScheme.surface,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              insetPadding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 480,
                  maxHeight: math.max(
                    0,
                    MediaQuery.sizeOf(context).height -
                        MediaQuery.viewInsetsOf(context).bottom -
                        48,
                  ),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'New message',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ..._fields(context),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: _actions(context),
                      ),
                    ],
                  ),
                ),
              ),
            )
          : AlertDialog(
              title: const Text('New message'),
              scrollable: true,
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _fields(context),
                ),
              ),
              actions: _actions(context),
            ),
    ),
  );

  List<Widget> _fields(BuildContext context) {
    if (_accounts.isEmpty) {
      return [
        const Text('Connect an account in Settings to start a conversation.'),
      ];
    }
    final scheme = Theme.of(context).colorScheme;
    final picker = DropdownButtonFormField<String>(
      key: ValueKey('new-message-account-$_accountId'),
      initialValue: _account?.id,
      isExpanded: true,
      isDense: true,
      decoration: InputDecoration(
        labelText: widget.desktop ? null : 'Send with',
        contentPadding: widget.desktop
            ? const EdgeInsets.symmetric(horizontal: 8, vertical: 6)
            : null,
      ),
      items: [
        for (final account in _accounts)
          DropdownMenuItem(
            value: account.id,
            enabled: account.isConnected,
            child: Text(
              widget.desktop
                  ? '${_networkName(account.platform)} · ${account.displayName}'
                  : '${account.displayName} · ${_networkName(account.platform)}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: _submitting ? null : _changeAccount,
    );
    return [
      KeyedSubtree(
        key: const Key('new-message-account'),
        child: widget.desktop
            ? Row(
                children: [
                  const Text('Network'),
                  const SizedBox(width: 12),
                  Expanded(child: picker),
                ],
              )
            : picker,
      ),
      const SizedBox(height: 16),
      if (!_supported)
        Text(
          _account?.isConnected == false
              ? 'Reconnect this account in Settings to start a conversation.'
              : 'Starting new conversations is not supported for this account yet. Start one in the network’s app, then return to Inbox+.',
          style: TextStyle(color: scheme.onSurfaceVariant),
        )
      else ...[
        Semantics(
          label: _isIMessage
              ? 'Name, email or international phone number'
              : 'Recipient',
          onTap: _queryFocus.requestFocus,
          child: TextField(
            key: const Key('new-message-recipient'),
            controller: _query,
            focusNode: _queryFocus,
            autofocus: true,
            enabled: !_submitting,
            autocorrect: false,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: widget.desktop ? null : 'Recipient',
              hintText: _recipientHint,
              helperText: widget.desktop || _isIMessage ? null : _recipientHint,
              helperMaxLines: 2,
            ),
            onChanged: (_) => setState(() => _selected = null),
            onSubmitted: (_) => _open(),
          ),
        ),
        if (_isIMessage) ...[
          const SizedBox(height: 12),
          ..._contactResults(context),
        ],
        const SizedBox(height: 12),
        Text(
          'Recipient: ${_selected == null ? '' : '${_selected!.name} · '}${_recipient.isEmpty ? 'Not selected' : _recipient} · ${_networkName(_account!.platform)}',
          style: TextStyle(fontSize: widget.desktop ? 12 : 13),
        ),
        const SizedBox(height: 12),
        Text(
          'Continue opens the conversation. Nothing is sent until you write a message and press Send.',
          style: TextStyle(
            fontSize: widget.desktop ? 11 : 12,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
      if (_error != null) ...[
        const SizedBox(height: 12),
        Text(_error!, style: TextStyle(color: scheme.error)),
      ],
    ];
  }

  List<Widget> _contactResults(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final matches = _contacts.recipients
        .where((contact) => contact.matches(_query.text))
        .toList();
    final notice = TextStyle(
      fontSize: widget.desktop ? 11 : 12,
      color: scheme.onSurfaceVariant,
    );
    return [
      Row(
        children: [
          Text('Mac Contacts', style: notice),
          const Spacer(),
          if (_loadingContacts) ...[
            const SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
          ],
          TextButton(
            onPressed: _loadingContacts || _submitting
                ? null
                : _refreshContacts,
            child: const Text('Refresh Contacts'),
          ),
        ],
      ),
      const SizedBox(height: 6),
      if (_contacts.status == LocalRecipientStatus.accessUnavailable)
        Text(
          'Contacts access is unavailable. Allow Inbox+ in System Settings → Privacy & Security → Contacts, then refresh. You can still enter an email or international phone number.',
          style: notice,
        )
      else if (_contacts.status == LocalRecipientStatus.failed)
        Text(
          'Contacts could not be loaded. Try refreshing, or enter an email or international phone number.',
          style: notice,
        )
      else if (_query.text.trim().isEmpty)
        Text(
          'Search by name. Contacts need an email or an international phone number (+…).',
          style: notice,
        )
      else if (matches.isEmpty && !_loadingContacts)
        Text(
          'No matching contacts. Enter an email or international phone number instead.',
          style: notice,
        )
      else if (matches.isNotEmpty)
        SizedBox(
          height: math.min(matches.length * 52, 160),
          child: ListView.builder(
            itemCount: matches.length,
            itemExtent: 52,
            itemBuilder: (context, index) {
              final contact = matches[index];
              final selected =
                  _selected?.name == contact.name &&
                  _selected?.address == contact.address;
              void choose() => setState(() => _selected = contact);
              return Semantics(
                label: 'Choose ${contact.name}, ${contact.address}',
                button: true,
                selected: selected,
                enabled: !_submitting,
                excludeSemantics: true,
                onTap: _submitting ? null : choose,
                child: InkWell(
                  onTap: _submitting ? null : choose,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                contact.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                contact.address,
                                style: notice,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        if (selected) const Icon(Icons.check, size: 16),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
    ];
  }

  List<Widget> _actions(BuildContext context) => [
    TextButton(
      onPressed: _submitting ? null : () => Navigator.pop(context),
      child: Text(_accounts.isEmpty ? 'Close' : 'Cancel'),
    ),
    if (_accounts.isNotEmpty) ...[
      const SizedBox(width: 8),
      FilledButton(
        style: widget.desktop
            ? FilledButton.styleFrom(
                minimumSize: const Size(0, 24),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(fontSize: 13),
              )
            : null,
        onPressed: _canOpen ? _open : null,
        child: _submitting
            ? const SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(widget.desktop ? 'Continue' : 'Open conversation'),
      ),
    ],
  ];

  String get _recipientHint => switch (_account?.platform) {
    'whatsapp' => 'Phone number including country code',
    'telegram' => 'Username or numeric Telegram ID',
    'imessage' => 'Name, email or international phone number (+…)',
    _ => 'Account ID or username',
  };

  String _networkName(String platform) =>
      widget.controller.networks
          .where((network) => network.id == platform)
          .firstOrNull
          ?.name ??
      platform;
}
