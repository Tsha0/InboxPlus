import 'dart:convert';
import 'dart:io';

import 'package:inboxplus_storage/inboxplus_storage.dart';
import 'package:path/path.dart' as p;

import 'app_environment.dart';

class MigrationResult {
  const MigrationResult({
    this.didMigrate = false,
    this.requiresReconnect = false,
    this.notice,
  });

  final bool didMigrate;
  final bool requiresReconnect;
  final String? notice;
}

class ProfileMigration {
  const ProfileMigration(this.environment);

  final AppEnvironment environment;

  Future<MigrationResult> run(LocalStore store) async {
    final directoryMarker = environment.secretName('profile-directory');
    try {
      final previous = await environment.secrets.read(directoryMarker);
      final current = environment.directory.path;
      if (previous != null && previous != current) {
        await store.rebaseAttachmentPaths(
          previousDirectory: previous,
          currentDirectory: current,
        );
      }
      if (previous != current) {
        await environment.secrets.write(directoryMarker, current);
      }
    } catch (_) {
      throw const AppStorageException(
        'The restored profile could not be migrated. Its data has been kept.',
      );
    }
    final legacy = environment.legacyProfileDirectory;
    if (legacy == null) return const MigrationResult();
    final marker = environment.secretName('profile-migration-v1');
    if (await environment.secrets.read(marker) == 'complete') {
      return const MigrationResult();
    }
    try {
      final contacts = await _contacts(legacy);
      final preferences = await _preferences(legacy);
      final accountIds = {
        for (final contact in contacts)
          for (final identity in contact.identities) identity.accountId,
        for (final preference in preferences) preference.route.accountId,
      };
      final accounts = [
        for (final id in accountIds)
          AccountRecord(
            id: id,
            platform: 'legacy',
            displayName: _accountName(id),
          ),
      ];
      await store.importLegacy(
        accounts: accounts,
        contacts: contacts,
        preferences: preferences,
      );
      await environment.secrets.write(marker, 'complete');
      return const MigrationResult(
        didMigrate: true,
        requiresReconnect: true,
        notice: 'Your saved contacts and conversation choices were imported. Connect your accounts again and relink their identities. Previous message history and staged files remain in the original profile.',
      );
    } catch (_) {
      throw const AppStorageException(
        'The previous profile could not be migrated. Its data has been kept, and no empty inbox was substituted.',
      );
    }
  }

  Future<List<ContactRecord>> _contacts(Directory legacy) async {
    final value = await _read(legacy, 'contacts/directory.json');
    if (value == null) return [];
    final record = _map(value);
    if (record['schemaVersion'] != 1) throw const FormatException();
    final people = _map(record['people']);
    final links = _map(record['links']);
    final identities = <String>{};
    for (final entry in links.entries) {
      final link = _map(entry.value);
      if (!people.containsKey(entry.key) || link['personID'] != entry.key) {
        throw const FormatException();
      }
      for (final identity in _list(link['remoteIdentityIDs'])) {
        if (!identities.add(_string(identity))) throw const FormatException();
      }
    }
    return [
      for (final entry in people.entries)
        _contact(entry.key, _map(entry.value), links[entry.key]),
    ];
  }

  ContactRecord _contact(
    String id,
    Map<String, Object?> person,
    Object? value,
  ) {
    if (_string(person['id']) != id) throw const FormatException();
    final link = value == null ? null : _map(value);
    return ContactRecord(
      id: _string(id),
      displayName: _string(person['displayName']),
      identities: [
        if (link != null)
          for (final identity in _list(link['remoteIdentityIDs']))
            IdentityLink('legacy:identities', _string(identity)),
      ],
    );
  }

  Future<List<ConversationPreferencesRecord>> _preferences(
    Directory legacy,
  ) async {
    final favoritesValue = await _read(legacy, 'inbox-favourites.json');
    final choicesValue = await _read(
      legacy,
      'inbox-conversation-preferences.json',
    );
    final favorites = {
      for (final value in _list(favoritesValue ?? [])) _route(value),
    };
    final choices = choicesValue == null
        ? <String, Object?>{}
        : _map(choicesValue);
    final unread = {
      for (final value in _list(choices['markedUnread'] ?? [])) _route(value),
    };
    final mutes = <ConversationRoute, DateTime?>{};
    final hides = <ConversationRoute, DateTime>{};
    for (final value in _list(choices['mutes'] ?? [])) {
      final mute = _map(value);
      final route = _route(mute['route']);
      if (mutes.containsKey(route)) throw const FormatException();
      mutes[route] = mute['until'] == null ? null : _swiftDate(mute['until']);
    }
    for (final value in _list(choices['hides'] ?? [])) {
      final hide = _map(value);
      final route = _route(hide['route']);
      if (hides.containsKey(route)) throw const FormatException();
      hides[route] = _swiftDate(hide['latestActivity']);
    }
    return [
      for (final route in {
        ...favorites,
        ...unread,
        ...mutes.keys,
        ...hides.keys,
      })
        ConversationPreferencesRecord(
          route: route,
          isFavorite: favorites.contains(route),
          markedUnread: unread.contains(route),
          isMuted: mutes.containsKey(route),
          mutedUntil: mutes[route],
          hiddenAt: hides[route],
        ),
    ];
  }

  Future<Object?> _read(Directory root, String relative) async {
    final file = File(p.join(root.path, relative));
    var ancestor = file.absolute.path;
    while (ancestor != p.dirname(ancestor)) {
      if (await FileSystemEntity.isLink(ancestor)) {
        throw const FormatException();
      }
      ancestor = p.dirname(ancestor);
    }
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return null;
    if (type != FileSystemEntityType.file ||
        await file.length() > 16 * 1024 * 1024) {
      throw const FormatException();
    }
    final decoded = jsonDecode(await file.readAsString());
    if (decoded == null) throw const FormatException();
    return decoded;
  }

  static ConversationRoute _route(Object? value) {
    final route = _map(value);
    return ConversationRoute(
      'legacy:${_string(route['accountID'])}',
      _string(route['conversationID']),
    );
  }

  static DateTime _swiftDate(Object? value) {
    if (value is! num || !value.isFinite) throw const FormatException();
    return DateTime.fromMicrosecondsSinceEpoch(
      ((value + 978307200) * 1000000).round(),
      isUtc: true,
    );
  }

  static Map<String, Object?> _map(Object? value) {
    if (value is! Map<String, dynamic>) throw const FormatException();
    return Map<String, Object?>.from(value);
  }

  static List<Object?> _list(Object? value) {
    if (value is! List) throw const FormatException();
    return List<Object?>.from(value);
  }

  static String _string(Object? value) {
    if (value is! String || value.trim().isEmpty) throw const FormatException();
    return value;
  }

  static String _accountName(String id) => switch (id) {
    'legacy:whatsapp' => 'Previous WhatsApp',
    'legacy:telegram' => 'Previous Telegram',
    'legacy:instagram' => 'Previous Instagram',
    'legacy:messenger' => 'Previous Messenger',
    'legacy:imessage-local' => 'Previous iMessage',
    'legacy:identities' => 'Previous linked accounts',
    _ => 'Previous account',
  };
}
