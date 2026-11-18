import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:inboxplus_storage/inboxplus_storage.dart';

import 'confirmation.dart';
import 'inbox_ui_controller.dart';
import 'network_badge.dart';
import 'person_avatar.dart';

class InboxContactsPage extends StatefulWidget {
  const InboxContactsPage({
    super.key,
    required this.controller,
    required this.onOpenConversation,
    required this.onCompose,
  });

  final InboxUiController controller;
  final VoidCallback onOpenConversation;
  final ValueChanged<IdentityLink?> onCompose;

  @override
  State<InboxContactsPage> createState() => _InboxContactsPageState();
}

class _InboxContactsPageState extends State<InboxContactsPage> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _open(ContactRecord contact, [IdentityLink? only]) {
    final identities = only == null ? contact.identities : [only];
    final existing = widget.controller.conversations
        .where(
          (conversation) => identities.any(
            (identity) =>
                identity.accountId == conversation.route.accountId &&
                identity.identityId == conversation.identityId,
          ),
        )
        .firstOrNull;
    if (existing != null) {
      widget.controller.selectConversation(existing.route);
      widget.onOpenConversation();
    } else {
      widget.onCompose(identities.firstOrNull);
    }
  }

  Future<void> _edit([ContactRecord? contact]) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (context) => _ContactEditor(
        controller: widget.controller,
        contact: contact,
        onMessage: contact == null
            ? null
            : (identity) {
                Navigator.pop(context);
                _open(contact, identity);
              },
      ),
    ),
  );

  String? _platformFor(IdentityLink identity) => widget.controller.accounts
      .where((account) => account.id == identity.accountId)
      .firstOrNull
      ?.platform;

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final contacts =
        widget.controller.contacts
            .where(
              (contact) =>
                  query.isEmpty ||
                  contact.displayName.toLowerCase().contains(query) ||
                  contact.identities.any(
                    (identity) =>
                        identity.identityId.toLowerCase().contains(query),
                  ),
            )
            .toList()
          ..sort((a, b) => a.displayName.compareTo(b.displayName));
    return _buildList(context, contacts, query);
  }

  Widget _buildList(
    BuildContext context,
    List<ContactRecord> contacts,
    String query,
  ) {
    final scheme = Theme.of(context).colorScheme;
    String letter(ContactRecord contact) {
      final first = contact.displayName.trim().characters.firstOrNull;
      return first == null || !RegExp(r'[A-Za-z]').hasMatch(first)
          ? '#'
          : first.toUpperCase();
    }

    final rows = <Widget>[];
    String? current;
    for (final contact in contacts) {
      final heading = letter(contact);
      if (heading != current) {
        current = heading;
        rows.add(
          Padding(
            key: Key('contacts-letter-$heading'),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: Text(
              heading,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        );
      }
      final platforms = contact.identities
          .map(_platformFor)
          .whereType<String>()
          .toSet()
          .toList();
      final photo = personPhoto(
        contact.identities.expand(
          (identity) => widget.controller.conversations.where(
            (conversation) =>
                conversation.route.accountId == identity.accountId &&
                conversation.identityId == identity.identityId,
          ),
        ),
      );
      rows.add(
        InkWell(
          key: Key('contact-${contact.id}'),
          onTap: () => _edit(contact),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 7, 8, 7),
            child: Row(
              children: [
                PersonAvatar(name: contact.displayName, bytes: photo, size: 46),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        contact.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          for (final platform in platforms)
                            Padding(
                              padding: const EdgeInsets.only(right: 3),
                              child: NetworkBadge(
                                network: platform,
                                size: 16,
                                labelled: false,
                              ),
                            ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              platforms.map(_networkName).join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13.5,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Message ${contact.displayName}',
                  onPressed: () => _open(contact),
                  icon: Icon(
                    CupertinoIcons.chat_bubble,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 16, 0),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Contacts',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.5,
                  ),
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Add contact',
                onPressed: widget.controller.accounts.isEmpty
                    ? null
                    : () => _edit(),
                icon: const Icon(CupertinoIcons.person_add, size: 21),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Search names or account IDs',
              prefixIcon: const Icon(CupertinoIcons.search, size: 18),
              filled: true,
              fillColor: scheme.surfaceContainerHigh,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: BorderSide(color: scheme.outlineVariant),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: BorderSide(color: scheme.outlineVariant),
              ),
            ),
          ),
        ),
        Expanded(
          child: contacts.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      query.isEmpty
                          ? 'Contacts from connected accounts appear here. Link their accounts to keep the same person together.'
                          : 'No contacts found. Try another name or account ID.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.only(bottom: 120),
                  children: rows,
                ),
        ),
      ],
    );
  }

  String _networkName(String platform) =>
      widget.controller.networks
          .where((network) => network.id == platform)
          .firstOrNull
          ?.name ??
      platform;
}

class _ContactEditor extends StatefulWidget {
  const _ContactEditor({
    required this.controller,
    this.contact,
    this.onMessage,
  });

  final InboxUiController controller;
  final ContactRecord? contact;
  final ValueChanged<IdentityLink>? onMessage;

  @override
  State<_ContactEditor> createState() => _ContactEditorState();
}

class _ContactEditorState extends State<_ContactEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final List<_EditableIdentity> _identities;
  bool _saving = false;
  late bool _editingName = widget.contact == null;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.contact?.displayName ?? '');
    _identities = [
      for (final identity in widget.contact?.identities ?? <IdentityLink>[])
        _EditableIdentity(identity.accountId, identity.identityId),
    ];
    if (_identities.isEmpty && widget.controller.accounts.isNotEmpty) {
      _identities.add(
        _EditableIdentity(widget.controller.accounts.first.id, ''),
      );
    }
  }

  @override
  void dispose() {
    _name.dispose();
    for (final identity in _identities) {
      identity.value.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false) || _saving) return;
    final links = _identities
        .map(
          (identity) =>
              IdentityLink(identity.accountId, identity.value.text.trim()),
        )
        .toList();
    if (links
            .map(
              (identity) => '${identity.accountId}\u0000${identity.identityId}',
            )
            .toSet()
            .length !=
        links.length) {
      setState(() => _error = 'Each linked account ID must be different.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.controller.saveContact(
        ContactRecord(
          id:
              widget.contact?.id ??
              'contact-${DateTime.now().microsecondsSinceEpoch}',
          displayName: _name.text.trim(),
          identities: links,
        ),
      );
      if (!mounted) return;
      if (widget.controller.error case final error?) {
        setState(() {
          _saving = false;
          _error = error;
        });
      } else {
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'This contact could not be saved. Try again.';
        });
      }
    }
  }

  Future<void> _remove() async {
    final confirmed = await confirmAction(
      context,
      title: 'Remove ${widget.contact!.displayName}?',
      message: 'This removes the saved contact and its linked identities. Your conversations and messages stay on this device.',
      confirmLabel: 'Remove contact',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.controller.removeContact(widget.contact!.id);
      if (!mounted) return;
      if (widget.controller.error case final error?) {
        setState(() {
          _saving = false;
          _error = error;
        });
      } else {
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'This contact could not be removed. Try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final contact = widget.contact;
    final saved = contact?.identities ?? const <IdentityLink>[];
    return Scaffold(
      appBar: AppBar(
        leadingWidth: 92,
        leading: TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        title: Text(contact == null ? 'Add contact' : 'Contact'),
        centerTitle: true,
        scrolledUnderElevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              key: const Key('contact-save'),
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Save'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          MediaQuery.paddingOf(context).bottom + 24,
        ),
        children: [
          Center(
            child: PersonAvatar(
              name: _name.text.trim().isEmpty ? '?' : _name.text,
              size: 84,
            ),
          ),
          if (!_editingName) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(width: 48),
                Flexible(
                  child: Text(
                    _name.text,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Edit name',
                  onPressed: _saving
                      ? null
                      : () => setState(() => _editingName = true),
                  icon: Icon(
                    CupertinoIcons.pencil,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
          if (widget.onMessage != null && saved.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final identity in saved)
                  ActionChip(
                    avatar: NetworkBadge(
                      network: widget.controller.accounts
                          .where((account) => account.id == identity.accountId)
                          .firstOrNull
                          ?.platform,
                      size: 20,
                      labelled: false,
                    ),
                    label: Text(
                      'Message on ${_networkName(identity.accountId)}',
                    ),
                    onPressed: () => widget.onMessage!(identity),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          _form(context),
          if (contact != null) ...[
            const SizedBox(height: 28),
            TextButton(
              onPressed: _saving ? null : _remove,
              style: TextButton.styleFrom(foregroundColor: scheme.error),
              child: const Text('Remove contact'),
            ),
            Text(
              'Your conversations and messages stay on this device.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }

  String _networkName(String accountId) {
    final platform = widget.controller.accounts
        .where((account) => account.id == accountId)
        .firstOrNull
        ?.platform;
    if (platform == null) return 'Disconnected account';
    return widget.controller.networks
            .where((network) => network.id == platform)
            .firstOrNull
            ?.name ??
        platform;
  }

  Widget _form(BuildContext context) => Form(
    key: _formKey,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_editingName)
          TextFormField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Name'),
            textCapitalization: TextCapitalization.words,
            validator: (value) =>
                value?.trim().isEmpty != false ? 'Enter a name.' : null,
          ),
        if (_editingName) const SizedBox(height: 20),
        const Text(
          'Linked identities',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        const Text(
          'Use the contact’s ID on each network. Linking identities keeps one person together in your contacts.',
          style: TextStyle(fontSize: 12, height: 1.5),
        ),
        for (final identity in _identities)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: identity.accountId,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Account'),
                        items: [
                          if (!widget.controller.accounts.any(
                            (account) => account.id == identity.accountId,
                          ))
                            DropdownMenuItem(
                              value: identity.accountId,
                              child: const Text(
                                'Disconnected account',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          for (final account in widget.controller.accounts)
                            DropdownMenuItem(
                              value: account.id,
                              child: Text(
                                account.displayName,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: _saving
                            ? null
                            : (value) =>
                                  setState(() => identity.accountId = value!),
                      ),
                    ),
                    if (_identities.length > 1)
                      IconButton(
                        tooltip: 'Remove linked identity',
                        onPressed: _saving
                            ? null
                            : () => setState(() {
                                _identities.remove(identity);
                                identity.value.dispose();
                              }),
                        icon: const Icon(Icons.close, size: 20),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: identity.value,
                  decoration: const InputDecoration(
                    labelText: 'Contact ID or username',
                  ),
                  autocorrect: false,
                  validator: (value) => value?.trim().isEmpty != false
                      ? 'Enter this contact’s account ID.'
                      : null,
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _saving || widget.controller.accounts.isEmpty
                ? null
                : () => setState(
                    () => _identities.add(
                      _EditableIdentity(
                        widget.controller.accounts.first.id,
                        '',
                      ),
                    ),
                  ),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Link another identity'),
          ),
        ),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    ),
  );
}

class _EditableIdentity {
  _EditableIdentity(this.accountId, String identityId)
    : value = TextEditingController(text: identityId);

  String accountId;
  final TextEditingController value;
}
