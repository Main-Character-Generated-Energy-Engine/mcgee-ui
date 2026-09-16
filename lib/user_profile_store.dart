import 'package:shared_preferences/shared_preferences.dart';

const _protagonistNameKey = 'mcgee.protagonistName';

abstract interface class UserProfileStore {
  Future<String?> loadName();

  Future<void> saveName(String name);
}

final class SharedPreferencesUserProfileStore implements UserProfileStore {
  const SharedPreferencesUserProfileStore();

  @override
  Future<String?> loadName() async {
    final preferences = await SharedPreferences.getInstance();
    final stored = preferences.getString(_protagonistNameKey);
    if (stored == null) return null;
    try {
      return normalizeCharacterName(stored);
    } on FormatException {
      await preferences.remove(_protagonistNameKey);
      return null;
    }
  }

  @override
  Future<void> saveName(String name) async {
    final normalized = normalizeCharacterName(name);
    final preferences = await SharedPreferences.getInstance();
    if (!await preferences.setString(_protagonistNameKey, normalized)) {
      throw StateError('The name could not be saved on this device.');
    }
  }
}

String normalizeCharacterName(String value) {
  if (RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
    throw const FormatException('The name contains unsupported characters.');
  }
  final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (normalized.isEmpty) {
    throw const FormatException('Enter the name the narrator should use.');
  }
  if (normalized.length > 60) {
    throw const FormatException('Keep the name to 60 characters or fewer.');
  }
  return normalized;
}
