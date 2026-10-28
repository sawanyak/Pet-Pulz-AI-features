import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pet_core/pet_core.dart';

/// Keeps the cat profile in memory AND saved on the phone.
///
/// `shared_preferences` is a tiny key-value store that survives app
/// restarts (UserDefaults on iOS, SharedPreferences on Android). We save the
/// whole profile as one JSON string under a single key.
///
/// It is a [ChangeNotifier], so any screen showing the profile rebuilds
/// automatically when it changes.
class CatProfileStore extends ChangeNotifier {
  CatProfileStore(this._prefs) : _profile = _read(_prefs);

  static const _key = 'cat_profile_v1';

  final SharedPreferences _prefs;
  CatProfile? _profile;

  /// Null until the user creates one.
  CatProfile? get profile => _profile;

  /// Opens the phone's storage. Called once at app startup.
  static Future<CatProfileStore> load() async =>
      CatProfileStore(await SharedPreferences.getInstance());

  Future<void> save(CatProfile profile) async {
    _profile = profile;
    notifyListeners(); // update the UI right away
    await _prefs.setString(_key, jsonEncode(profile.toJson()));
  }

  Future<void> clear() async {
    _profile = null;
    notifyListeners();
    await _prefs.remove(_key);
  }

  static CatProfile? _read(SharedPreferences prefs) {
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      final profile = CatProfile.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      return profile.name.isEmpty ? null : profile;
    } catch (_) {
      // Corrupt data must never stop the app from starting.
      return null;
    }
  }
}
