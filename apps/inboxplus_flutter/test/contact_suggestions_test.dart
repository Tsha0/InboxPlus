import 'package:flutter_test/flutter_test.dart';
import 'package:inboxplus_flutter/contact_suggestions.dart';
import 'package:inboxplus_storage/inboxplus_storage.dart';

const accounts = [
  AccountRecord(id: 'first', platform: 'whatsapp', displayName: 'First'),
  AccountRecord(id: 'second', platform: 'telegram', displayName: 'Second'),
  AccountRecord(
    id: 'duplicate',
    platform: 'whatsapp',
    displayName: 'Duplicate',
  ),
  AccountRecord(id: 'old', platform: 'legacy', displayName: 'Old'),
];

ConversationRecord chat(
  String account,
  String identity, {
  String title = 'Alex Chen',
  bool group = false,
}) => ConversationRecord(
  route: ConversationRoute(account, identity),
  identityId: identity,
  title: title,
  latestActivity: DateTime(2026, 11, 5),
  isGroup: group,
);

List<ContactSuggestion> suggestions(
  List<ConversationRecord> chats, {
  List<ContactRecord> contacts = const [],
}) => suggestContactLinks(
  accounts: accounts,
  conversations: chats,
  contacts: contacts,
);

void main() {
  test('vowel signs and points in other scripts distinguish names', () {
    for (final pair in [('กิ', 'กี'), ('क', 'कि'), ('א', 'אָ')]) {
      expect(
        suggestions([
          chat('first', 'a', title: pair.$1),
          chat('second', 'b', title: pair.$2),
        ]),
        isEmpty,
      );
    }
  });
  for (final pair in [
    (' José Chen ', 'jose\u0301 chen'),
    ('ΣΊΓΜΑ', 'σιγμα'),
    ('Groß', 'gross'),
    ('Ægir', 'æGIR'),
    ('Łukasz', 'łUKASZ'),
  ]) {
    test('suggestions compare case and accents in ${pair.$1}', () {
      final result = suggestions([
        chat('first', 'a', title: pair.$1),
        chat('second', 'b', title: pair.$2),
      ]).single;
      expect(result.displayName, pair.$1.trim());
      expect(result.identities.map((identity) => identity.accountId), [
        'first',
        'second',
      ]);
      expect(result.platforms, ['whatsapp', 'telegram']);
    });
  }

  test('different names and ambiguous matches on one network are excluded', () {
    final first = chat('first', 'a');
    final second = chat('second', 'b');
    expect(suggestions([first, second]), hasLength(1));
    expect(suggestions([first, second, chat('duplicate', 'c')]), isEmpty);
    expect(suggestions([first, chat('duplicate', 'b')]), isEmpty);
    expect(
      suggestions([first, chat('second', 'b', title: 'Alex Smith')]),
      isEmpty,
    );
    expect(
      suggestions([
        chat('first', 'a', title: 'Ægir'),
        chat('second', 'b', title: 'Aegir'),
      ]),
      isEmpty,
    );
  });

  test('groups, unknown names, missing identities and legacy accounts are excluded', () {
    final first = chat('first', 'a');
    for (final second in [
      chat('second', 'b', group: true),
      chat('missing', 'b'),
      chat('old', 'b'),
    ]) {
      expect(suggestions([first, second]), isEmpty);
    }
    for (final title in ['', ' ', 'Unknown', ' UNKNOWN USER ']) {
      expect(
        suggestions([
          chat('first', 'a', title: title),
          chat('second', 'b', title: title),
        ]),
        isEmpty,
      );
    }
    final missing = ConversationRecord(
      route: const ConversationRoute('second', 'b'),
      title: first.title,
      latestActivity: DateTime(2026, 11, 5),
    );
    expect(suggestions([first, missing]), isEmpty);
  });

  test('links are account-scoped and suggestion order is deterministic', () {
    final chats = [chat('first', 'same'), chat('second', 'same')];
    final result = suggestions(chats).single;
    expect(result.identities, hasLength(2));
    expect(suggestions(chats.reversed.toList()).single.id, result.id);
    expect(
      suggestions(
        chats,
        contacts: [
          ContactRecord(
            id: 'person',
            displayName: 'Existing',
            identities: const [IdentityLink('first', 'same')],
          ),
        ],
      ),
      isEmpty,
    );
    expect(
      suggestions(
        chats,
        contacts: [
          ContactRecord(
            id: 'person',
            displayName: 'Existing',
            identities: const [IdentityLink('first', 'different')],
          ),
        ],
      ),
      hasLength(1),
    );
  });
}
