import 'dart:convert';

import 'package:inboxplus_storage/inboxplus_storage.dart';
import 'package:unorm_dart/unorm_dart.dart' as unicode;

class ContactSuggestion {
  ContactSuggestion({
    required this.displayName,
    required List<IdentityLink> identities,
    required List<String> platforms,
  }) : identities = List.unmodifiable(identities),
       platforms = List.unmodifiable(platforms);

  final String displayName;
  final List<IdentityLink> identities;
  final List<String> platforms;

  String get id => jsonEncode([
    for (final identity in identities)
      [identity.accountId, identity.identityId],
  ]);
}

String normalizeContactName(String name) => unicode
    .nfd(name.trim())
    // Vowel signs and points outside this accent block distinguish names in other scripts.
    .replaceAll(RegExp('[\u0300-\u036f]'), '')
    .toLowerCase()
    .replaceAll('ß', 'ss')
    .replaceAll('ς', 'σ');

List<ContactSuggestion> suggestContactLinks({
  required List<AccountRecord> accounts,
  required List<ConversationRecord> conversations,
  required List<ContactRecord> contacts,
}) {
  final platforms = {
    for (final account in accounts) account.id: account.platform,
  };
  final linked = {
    for (final person in contacts)
      for (final identity in person.identities)
        (identity.accountId, identity.identityId),
  };
  final names = <String, List<ConversationRecord>>{};
  for (final chat in conversations) {
    if (chat.isGroup ||
        chat.identityId == null ||
        chat.identityId!.trim().isEmpty ||
        linked.contains((chat.route.accountId, chat.identityId)) ||
        platforms[chat.route.accountId] == null ||
        platforms[chat.route.accountId] == 'legacy') {
      continue;
    }
    final name = normalizeContactName(chat.title);
    if (name.isEmpty || name == 'unknown' || name == 'unknown user') continue;
    names.putIfAbsent(name, () => []).add(chat);
  }
  final suggestions = <ContactSuggestion>[];
  for (final chats in names.values) {
    final networks = chats
        .map((chat) => platforms[chat.route.accountId]!)
        .toSet();
    if (networks.length < 2 || networks.length != chats.length) continue;
    chats.sort((a, b) {
      final identity = a.identityId!.compareTo(b.identityId!);
      return identity == 0
          ? a.route.accountId.compareTo(b.route.accountId)
          : identity;
    });
    suggestions.add(
      ContactSuggestion(
        displayName: chats.first.title.trim(),
        identities: [
          for (final chat in chats)
            IdentityLink(chat.route.accountId, chat.identityId!),
        ],
        platforms: networks.toList(),
      ),
    );
  }
  return suggestions..sort((a, b) => a.id.compareTo(b.id));
}
