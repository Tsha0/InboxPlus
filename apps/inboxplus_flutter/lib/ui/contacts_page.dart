import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:inboxplus_storage/inboxplus_storage.dart';

import 'confirmation.dart';
import 'inbox_ui_controller.dart';
import 'person_avatar.dart';

class InboxContactsPage extends StatefulWidget {
  const InboxContactsPage({
    super.key,
    required this.controller,
    required this.onConnect,
    required this.onOpenConversation,
    required this.onCompose,
  });

  final InboxUiController controller;
  final VoidCallback onConnect;
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

  void _open(ContactRecord contact) {
    final existing = widget.controller.conversations
        .where(
          (conversation) => contact.identities.any(
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
      widget.onCompose(contact.identities.firstOrNull);
    }
  }

  Future<void> _edit([ContactRecord? contact]) => showDialog<void>(
    context: context,
    builder: (context) =>
        _ContactEditor(controller: widget.controller, contact: contact),
  );

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 12, 16),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Contacts',
                  style: TextStyle(
                    fontSize: 27,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.8,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Connect an account',
                onPressed: widget.onConnect,
                icon: const Icon(Icons.person_add_alt),
              ),
              IconButton(
                tooltip: 'Add contact',
                onPressed: widget.controller.accounts.isEmpty
                    ? null
                    : () => _edit(),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'Search contacts',
              prefixIcon: Icon(Icons.search),
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: contacts.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          query.isEmpty
                              ? Icons.people_outline
                              : Icons.search_off,
                          size: 40,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          query.isEmpty
                              ? 'Your people, together'
                              : 'No contacts found',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          query.isEmpty
                              ? 'Contacts from connected accounts appear here. Link their accounts to keep the same person together.'
                              : 'Try another name or account ID.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: contacts.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final contact = contacts[index];
                    final networks = contact.identities
                        .map(
                          (identity) => widget.controller.accounts
                              .where(
                                (account) => account.id == identity.accountId,
                              )
                              .firstOrNull
                              ?.platform,
                        )
                        .whereType<String>()
                        .map(_networkName)
                        .toSet();
                    final photo = contact.identities
                        .expand(
                          (identity) => widget.controller.conversations.where(
                            (conversation) =>
                                !conversation.isGroup &&
                                conversation.route.accountId ==
                                    identity.accountId &&
                                conversation.identityId ==
                                    identity.identityId &&
                                conversation.avatarBytes?.isNotEmpty == true,
                          ),
                        )
                        .firstOrNull;
                    return ListTile(
                      key: Key('contact-${contact.id}'),
                      leading: defaultTargetPlatform == TargetPlatform.iOS
                          ? PersonAvatar(
                              name: contact.displayName,
                              bytes: photo?.avatarBytes,
                            )
                          : CircleAvatar(
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              child: Text(
                                contact.displayName.characters.firstOrNull
                                        ?.toUpperCase() ??
                                    '?',
                              ),
                            ),
                      title: Text(contact.displayName),
                      subtitle: Text(networks.join(' · ')),
                      onTap: () => _open(contact),
                      trailing: IconButton(
                        tooltip: 'Edit ${contact.displayName}',
                        onPressed: () => _edit(contact),
                        icon: const Icon(Icons.edit_outlined, size: 20),
                      ),
                    );
                  },
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
  const _ContactEditor({required this.controller, this.contact});

  final InboxUiController controller;
  final ContactRecord? contact;

  @override
  State<_ContactEditor> createState() => _ContactEditorState();
}

class _ContactEditorState extends State<_ContactEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final List<_EditableIdentity> _identities;
  bool _saving = false;
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
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.contact == null ? 'Add contact' : 'Edit contact'),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Name'),
                textCapitalization: TextCapitalization.words,
                validator: (value) =>
                    value?.trim().isEmpty != false ? 'Enter a name.' : null,
              ),
              const SizedBox(height: 20),
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
                              decoration: const InputDecoration(
                                labelText: 'Account',
                              ),
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
                                for (final account
                                    in widget.controller.accounts)
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
                                  : (value) => setState(
                                      () => identity.accountId = value!,
                                    ),
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
        ),
      ),
    ),
    actions: [
      if (widget.contact != null)
        TextButton(
          onPressed: _saving ? null : _remove,
          child: const Text('Remove'),
        ),
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: Text(_saving ? 'Saving…' : 'Save contact'),
      ),
    ],
  );
}

class _EditableIdentity {
  _EditableIdentity(this.accountId, String identityId)
    : value = TextEditingController(text: identityId);

  String accountId;
  final TextEditingController value;
}
