import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../storage/local_store.dart';

@immutable
class UserProfile {
  const UserProfile({
    required this.name,
    this.wilayaId,
    this.moughataaId,
  });

  final String name;
  final String? wilayaId;
  final String? moughataaId;

  bool get hasLocation => (wilayaId != null && wilayaId!.trim().isNotEmpty);

  UserProfile copyWith({
    String? name,
    String? wilayaId,
    String? moughataaId,
  }) {
    return UserProfile(
      name: name ?? this.name,
      wilayaId: wilayaId ?? this.wilayaId,
      moughataaId: moughataaId ?? this.moughataaId,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'wilayaId': wilayaId,
        'moughataaId': moughataaId,
      };

  static UserProfile? tryFromJsonString(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return null;
      final name = (map['name'] as String?)?.trim() ?? '';
      if (name.isEmpty) return null;
      return UserProfile(
        name: name,
        wilayaId: (map['wilayaId'] as String?)?.trim(),
        moughataaId: (map['moughataaId'] as String?)?.trim(),
      );
    } catch (_) {
      return null;
    }
  }

  String toJsonString() => jsonEncode(toJson());
}

@immutable
class ProfileState {
  const ProfileState({
    required this.profile,
    required this.prompted,
    required this.isLoading,
  });

  final UserProfile? profile;
  final bool prompted; // user has seen the setup prompt at least once
  final bool isLoading;

  bool get isComplete => profile != null && profile!.name.trim().isNotEmpty;

  ProfileState copyWith({
    UserProfile? profile,
    bool? prompted,
    bool? isLoading,
  }) {
    return ProfileState(
      profile: profile ?? this.profile,
      prompted: prompted ?? this.prompted,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  static const initial =
      ProfileState(profile: null, prompted: false, isLoading: true);
}

class ProfileController extends StateNotifier<ProfileState> {
  ProfileController(this._store) : super(ProfileState.initial) {
    _load();
  }

  final LocalStore _store;

  Future<void> _load() async {
    // SharedPreferences getters are synchronous.
    final prompted = _store.getProfilePrompted();
    final raw = _store.getProfileJson();
    final profile = UserProfile.tryFromJsonString(raw);

    state =
        ProfileState(profile: profile, prompted: prompted, isLoading: false);
  }

  Future<void> saveProfile(UserProfile profile) async {
    final cleaned = profile.copyWith(name: profile.name.trim());
    await _store.setProfileJson(cleaned.toJsonString());
    await _store.setProfilePrompted(true);
    state = state.copyWith(profile: cleaned, prompted: true);
  }

  Future<void> clearProfile() async {
    await _store.setProfileJson(null);
    // keep prompted = true so we don't nag
    state = state.copyWith(profile: null, prompted: true);
  }

  Future<void> markPrompted() async {
    await _store.setProfilePrompted(true);
    state = state.copyWith(prompted: true);
  }
}

final profileProvider =
    StateNotifierProvider<ProfileController, ProfileState>((ref) {
  final store = ref.watch(localStoreProvider);
  return ProfileController(store);
});
