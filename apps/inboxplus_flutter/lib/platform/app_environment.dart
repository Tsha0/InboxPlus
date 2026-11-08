import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

abstract interface class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class PlatformSecretStore implements SecretStore {
  const PlatformSecretStore();
  static const _storage = FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class AppEnvironment {
  AppEnvironment({
    required this.directory,
    required this.secrets,
    this.profileName = 'default',
    this.legacyProfileDirectory,
    bool? isIOS,
  }) : _isIOS = isIOS ?? Platform.isIOS;

  final Directory directory;
  final SecretStore secrets;
  final String profileName;
  final Directory? legacyProfileDirectory;
  final bool _isIOS;
  static const native = MethodChannel('inboxplus/native');
  static final _random = Random.secure();

  String secretName(String identity) {
    final scope = sha256.convert(
      utf8.encode(
        _isIOS
            ? 'ios:profile:$profileName'
            : p.normalize(directory.absolute.path),
      ),
    );
    return 'com.inboxplus.app.local.v1.$scope.$identity';
  }

  static Future<AppEnvironment> open({
    Directory? supportDirectory,
    SecretStore secrets = const PlatformSecretStore(),
    Map<String, String>? environment,
    bool? isMacOS,
    bool? isIOS,
    String compiledProfile = const String.fromEnvironment('INBOXPLUS_PROFILE'),
  }) async {
    final variables = environment ?? Platform.environment;
    final macOS = isMacOS ?? Platform.isMacOS;
    final requested =
        variables['INBOXPLUS_PROFILE'] ??
        (compiledProfile.isEmpty ? null : compiledProfile);
    if (requested != null && !_validProfileName(requested)) {
      throw const AppStorageException(
        'The selected profile name is invalid. Your data has been kept.',
      );
    }
    try {
      final support = await _canonicalSystemDirectory(
        supportDirectory ?? await getApplicationSupportDirectory(),
      );
      Directory profile;
      Directory? legacy;
      String profileName;
      if (macOS) {
        final override = variables['INBOXPLUS_RUNTIME_ROOT'];
        if (override != null &&
            override.isNotEmpty &&
            !p.isAbsolute(override)) {
          throw const AppStorageException(
            'The selected profile root must be an absolute path.',
          );
        }
        final home = variables['HOME'];
        if (override == null && supportDirectory == null && home == null) {
          throw const AppStorageException(
            'The existing profile location could not be determined.',
          );
        }
        final userSupport = supportDirectory != null
            ? support
            : await _canonicalSystemDirectory(
                Directory(p.join(home!, 'Library', 'Application Support')),
              );
        final root = Directory(
          override != null && override.isNotEmpty
              ? p.normalize(override)
              : p.join(userSupport.path, 'Inbox+', 'DeveloperRuntime'),
        );
        await _rejectLinks(root);
        final profiles = await _existingProfiles(root);
        if (requested == null && profiles.length > 1) {
          throw const AppStorageException(
            'Several existing profiles were found. Set INBOXPLUS_PROFILE to the profile to open. Your data has been kept.',
          );
        }
        profileName =
            requested ?? (profiles.isEmpty ? 'default' : profiles.single);
        profile = Directory(p.join(root.path, profileName));
        await _rejectLinks(profile);
        if (await _hasLegacyState(profile)) legacy = profile;
      } else {
        profileName = requested ?? 'default';
        profile = Directory(
          p.join(support.path, 'InboxPlus', 'profiles', profileName),
        );
      }
      final result = AppEnvironment(
        directory: Directory(p.join(profile.path, 'flutter')),
        secrets: secrets,
        profileName: profileName,
        legacyProfileDirectory: legacy,
        isIOS: isIOS,
      );
      await result.privateDirectory(result.directory);
      return result;
    } on AppStorageException {
      rethrow;
    } catch (_) {
      throw const AppStorageException(
        'The local profile could not be opened. Your data has been kept.',
      );
    }
  }

  Future<Uint8List> keyFor(
    String identity, {
    required bool existingData,
  }) async {
    final name = secretName(identity);
    final saved = await secrets.read(name);
    if (saved != null) {
      final Uint8List key;
      try {
        key = base64Decode(saved);
      } on FormatException {
        throw const AppStorageException(
          'The saved encryption key is invalid. Your data has been kept.',
        );
      }
      if (key.length != 32) {
        throw const AppStorageException(
          'The saved encryption key is invalid. Your data has been kept.',
        );
      }
      return key;
    }
    if (existingData) {
      throw const AppStorageException(
        'The encryption key for this profile is unavailable. Your data has been kept.',
      );
    }
    final key = Uint8List.fromList(
      List.generate(32, (_) => _random.nextInt(256)),
    );
    await secrets.write(name, base64Encode(key));
    return key;
  }

  Future<Directory> privateDirectory(Directory target) async {
    _requireContained(target.path);
    await _rejectLinks(target);
    final missing = <Directory>[];
    var parent = target.absolute;
    while (!await parent.exists()) {
      missing.add(parent);
      parent = parent.parent;
    }
    for (final item in missing.reversed) {
      await item.create();
      await protect(item.path, 448);
    }
    await protect(target.path, 448);
    return target;
  }

  Future<File> writePrivate(File destination, List<int> bytes) async {
    _requireContained(destination.path);
    await privateDirectory(destination.parent);
    final type = await FileSystemEntity.type(
      destination.path,
      followLinks: false,
    );
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.file) {
      throw const AppStorageException('The private file location is invalid.');
    }
    final suffix = List.generate(
      16,
      (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final temporary = File(
      p.join(destination.parent.path, '.inboxplus-$suffix'),
    );
    try {
      await temporary.create(exclusive: true);
      await protect(temporary.path, 384);
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(destination.path);
    } catch (_) {
      if (await temporary.exists()) await temporary.delete();
      throw const AppStorageException(
        'The private file could not be saved. Your data has been kept.',
      );
    }
    return destination;
  }

  Future<void> protect(String path, int permissions) async {
    if (Platform.isWindows) {
      final applied = await native.invokeMethod<bool>('protectPath', {
        'path': path,
        'mode': permissions,
      });
      if (applied != true) {
        throw const AppStorageException(
          'Private storage permissions could not be applied.',
        );
      }
      return;
    }
    final chmod = DynamicLibrary.process()
        .lookupFunction<
          Int32 Function(Pointer<Utf8>, Uint32),
          int Function(Pointer<Utf8>, int)
        >('chmod');
    final encoded = path.toNativeUtf8();
    try {
      if (chmod(encoded, permissions) != 0) {
        throw const AppStorageException(
          'Private storage permissions could not be applied.',
        );
      }
    } finally {
      malloc.free(encoded);
    }
  }

  void _requireContained(String path) {
    final root = p.normalize(directory.absolute.path);
    final target = p.normalize(p.absolute(path));
    if (target != root && !p.isWithin(root, target)) {
      throw const AppStorageException(
        'The private file must stay inside the selected profile.',
      );
    }
  }

  static bool _validProfileName(String name) =>
      RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$').hasMatch(name);

  static Future<List<String>> _existingProfiles(Directory root) async {
    if (!await root.exists()) return [];
    final result = <String>[];
    await for (final entry in root.list(followLinks: false)) {
      if (!_validProfileName(p.basename(entry.path))) {
        continue;
      }
      if (entry is Link) {
        throw const AppStorageException(
          'An existing profile is a symbolic link. Your data has been kept.',
        );
      }
      if (entry is! Directory) continue;
      final markers = [
        'state',
        'contacts',
        'composer',
        'data',
        'inbox-favourites.json',
        'inbox-conversation-preferences.json',
        'flutter',
      ];
      for (final marker in markers) {
        if (await FileSystemEntity.type(
              p.join(entry.path, marker),
              followLinks: false,
            ) !=
            FileSystemEntityType.notFound) {
          result.add(p.basename(entry.path));
          break;
        }
      }
    }
    return result..sort();
  }

  static Future<bool> _hasLegacyState(Directory profile) async {
    for (final marker in [
      'state',
      'contacts',
      'composer',
      'data',
      'inbox-favourites.json',
      'inbox-conversation-preferences.json',
    ]) {
      if (await FileSystemEntity.type(
            p.join(profile.path, marker),
            followLinks: false,
          ) !=
          FileSystemEntityType.notFound) {
        return true;
      }
    }
    return false;
  }

  static Future<void> _rejectLinks(Directory target) async {
    var ancestor = target.absolute;
    while (ancestor.path != ancestor.parent.path) {
      if (await FileSystemEntity.isLink(ancestor.path)) {
        throw const AppStorageException(
          'The private data directory cannot be a symbolic link.',
        );
      }
      ancestor = ancestor.parent;
    }
  }

  static Future<Directory> _canonicalSystemDirectory(
    Directory directory,
  ) async {
    var existing = directory.absolute;
    final components = <String>[];
    while (!await existing.exists()) {
      components.add(p.basename(existing.path));
      existing = existing.parent;
    }
    return Directory(
      p.joinAll([
        await existing.resolveSymbolicLinks(),
        ...components.reversed,
      ]),
    );
  }
}

class AppStorageException implements Exception {
  const AppStorageException(this.message);
  final String message;
  @override
  String toString() => message;
}
