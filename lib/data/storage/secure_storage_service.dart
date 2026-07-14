import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:password_manager/domain/auth/recovery_mode.dart';

/// Everything about a session that's safe to persist on-device (in secure
/// storage only — never SharedPreferences/plain files, per GOALS_v2 §1.4).
///
/// The master secret itself is deliberately absent: it is never persisted
/// anywhere.
class StoredSession {
  const StoredSession({
    required this.email,
    required this.userId,
    required this.accessToken,
    required this.refreshToken,
    required this.accessTokenExpiresAt,
    required this.vaultKey,
    required this.vaultKeyVerifier,
    required this.recoveryMode,
    required this.biometricEnabled,
  });

  final String email;
  final String userId;
  final String accessToken;
  final String refreshToken;

  /// When [accessToken] stops being valid (GOALS_v2 §2.7). Used by
  /// `AuthController.ensureValidSession` to proactively refresh before a
  /// call would otherwise fail, rather than only reacting to a failure.
  final DateTime? accessTokenExpiresAt;
  final Uint8List vaultKey;

  /// SHA-256 of [vaultKey], stored alongside it so a re-entered master
  /// secret can be verified against the *already-derived* vault key purely
  /// on-device (no network round-trip needed to unlock), without ever
  /// storing the master secret or the auth key.
  final Uint8List vaultKeyVerifier;
  final RecoveryMode recoveryMode;
  final bool biometricEnabled;

  /// Defense-in-depth against secret leakage into logs/crash reports
  /// (GOALS_v2 §2.8) — this is the fully-materialized on-device session
  /// record (tokens + vault key), so it gets the same redaction as
  /// `AuthState`/`AuthSession` rather than relying on the default
  /// `Object.toString()`.
  @override
  String toString() =>
      'StoredSession(email: $email, userId: $userId, '
      'accessToken: <redacted>, refreshToken: <redacted>, '
      'accessTokenExpiresAt: $accessTokenExpiresAt, vaultKey: <redacted>, '
      'vaultKeyVerifier: <redacted>, recoveryMode: $recoveryMode, '
      'biometricEnabled: $biometricEnabled)';
}

/// Abstraction over secure, platform-backed key/value storage.
///
/// Kept as an interface (mirroring the `ApiClient` pattern in this repo) so
/// widget/unit tests can substitute [InMemorySecureStorageService] instead
/// of exercising real platform channels.
abstract class SecureStorageService {
  Future<void> writeSession({
    required String email,
    required String userId,
    required String accessToken,
    required String refreshToken,
    DateTime? accessTokenExpiresAt,
    required Uint8List vaultKey,
    required RecoveryMode recoveryMode,
  });

  Future<StoredSession?> readSession();

  Future<void> updateTokens({
    required String accessToken,
    required String refreshToken,
    DateTime? accessTokenExpiresAt,
  });

  Future<void> setBiometricEnabled(bool enabled);

  /// Clears everything (sign-out / account switch).
  Future<void> clear();
}

const String _kEmail = 'auth.email';
const String _kUserId = 'auth.userId';
const String _kAccessToken = 'auth.accessToken';
const String _kRefreshToken = 'auth.refreshToken';
const String _kAccessTokenExpiresAt = 'auth.accessTokenExpiresAt';
const String _kVaultKey = 'auth.vaultKey';
const String _kVaultKeyVerifier = 'auth.vaultKeyVerifier';
const String _kRecoveryMode = 'auth.recoveryMode';
const String _kBiometricEnabled = 'auth.biometricEnabled';

Future<Uint8List> vaultKeyVerifierOf(Uint8List vaultKey) async {
  final digest = await Sha256().hash(vaultKey);
  return Uint8List.fromList(digest.bytes);
}

/// [FlutterSecureStorage]-backed implementation (Android Keystore-backed on
/// Android, per GOALS_v2 §1.4). Used everywhere in the running app.
class FlutterSecureStorageService implements SecureStorageService {
  FlutterSecureStorageService([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<void> writeSession({
    required String email,
    required String userId,
    required String accessToken,
    required String refreshToken,
    DateTime? accessTokenExpiresAt,
    required Uint8List vaultKey,
    required RecoveryMode recoveryMode,
  }) async {
    final verifier = await vaultKeyVerifierOf(vaultKey);
    await Future.wait(<Future<void>>[
      _storage.write(key: _kEmail, value: email),
      _storage.write(key: _kUserId, value: userId),
      _storage.write(key: _kAccessToken, value: accessToken),
      _storage.write(key: _kRefreshToken, value: refreshToken),
      _storage.write(
        key: _kAccessTokenExpiresAt,
        value: accessTokenExpiresAt?.toIso8601String(),
      ),
      _storage.write(key: _kVaultKey, value: base64Encode(vaultKey)),
      _storage.write(key: _kVaultKeyVerifier, value: base64Encode(verifier)),
      _storage.write(key: _kRecoveryMode, value: recoveryMode.name),
    ]);
  }

  @override
  Future<StoredSession?> readSession() async {
    final values = await Future.wait(<Future<String?>>[
      _storage.read(key: _kEmail),
      _storage.read(key: _kUserId),
      _storage.read(key: _kAccessToken),
      _storage.read(key: _kRefreshToken),
      _storage.read(key: _kVaultKey),
      _storage.read(key: _kVaultKeyVerifier),
      _storage.read(key: _kRecoveryMode),
      _storage.read(key: _kBiometricEnabled),
      _storage.read(key: _kAccessTokenExpiresAt),
    ]);
    final email = values[0];
    final userId = values[1];
    final accessToken = values[2];
    final refreshToken = values[3];
    final vaultKeyB64 = values[4];
    final verifierB64 = values[5];
    final recoveryModeName = values[6];
    if (email == null ||
        userId == null ||
        accessToken == null ||
        refreshToken == null ||
        vaultKeyB64 == null ||
        verifierB64 == null ||
        recoveryModeName == null) {
      return null;
    }
    final expiresAtRaw = values[8];
    return StoredSession(
      email: email,
      userId: userId,
      accessToken: accessToken,
      refreshToken: refreshToken,
      accessTokenExpiresAt: expiresAtRaw == null
          ? null
          : DateTime.parse(expiresAtRaw),
      vaultKey: base64Decode(vaultKeyB64),
      vaultKeyVerifier: base64Decode(verifierB64),
      recoveryMode: RecoveryMode.values.byName(recoveryModeName),
      biometricEnabled: values[7] == 'true',
    );
  }

  @override
  Future<void> updateTokens({
    required String accessToken,
    required String refreshToken,
    DateTime? accessTokenExpiresAt,
  }) async {
    await Future.wait(<Future<void>>[
      _storage.write(key: _kAccessToken, value: accessToken),
      _storage.write(key: _kRefreshToken, value: refreshToken),
      _storage.write(
        key: _kAccessTokenExpiresAt,
        value: accessTokenExpiresAt?.toIso8601String(),
      ),
    ]);
  }

  @override
  Future<void> setBiometricEnabled(bool enabled) {
    return _storage.write(key: _kBiometricEnabled, value: enabled.toString());
  }

  @override
  Future<void> clear() => _storage.deleteAll();
}

/// In-memory fake for tests, mirroring `FakeApiClient`'s role for
/// `ApiClient`.
class InMemorySecureStorageService implements SecureStorageService {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<void> writeSession({
    required String email,
    required String userId,
    required String accessToken,
    required String refreshToken,
    DateTime? accessTokenExpiresAt,
    required Uint8List vaultKey,
    required RecoveryMode recoveryMode,
  }) async {
    final verifier = await vaultKeyVerifierOf(vaultKey);
    _values[_kEmail] = email;
    _values[_kUserId] = userId;
    _values[_kAccessToken] = accessToken;
    _values[_kRefreshToken] = refreshToken;
    if (accessTokenExpiresAt != null) {
      _values[_kAccessTokenExpiresAt] = accessTokenExpiresAt.toIso8601String();
    } else {
      _values.remove(_kAccessTokenExpiresAt);
    }
    _values[_kVaultKey] = base64Encode(vaultKey);
    _values[_kVaultKeyVerifier] = base64Encode(verifier);
    _values[_kRecoveryMode] = recoveryMode.name;
  }

  @override
  Future<StoredSession?> readSession() async {
    final email = _values[_kEmail];
    final userId = _values[_kUserId];
    final accessToken = _values[_kAccessToken];
    final refreshToken = _values[_kRefreshToken];
    final vaultKeyB64 = _values[_kVaultKey];
    final verifierB64 = _values[_kVaultKeyVerifier];
    final recoveryModeName = _values[_kRecoveryMode];
    if (email == null ||
        userId == null ||
        accessToken == null ||
        refreshToken == null ||
        vaultKeyB64 == null ||
        verifierB64 == null ||
        recoveryModeName == null) {
      return null;
    }
    final expiresAtRaw = _values[_kAccessTokenExpiresAt];
    return StoredSession(
      email: email,
      userId: userId,
      accessToken: accessToken,
      refreshToken: refreshToken,
      accessTokenExpiresAt: expiresAtRaw == null
          ? null
          : DateTime.parse(expiresAtRaw),
      vaultKey: base64Decode(vaultKeyB64),
      vaultKeyVerifier: base64Decode(verifierB64),
      recoveryMode: RecoveryMode.values.byName(recoveryModeName),
      biometricEnabled: _values[_kBiometricEnabled] == 'true',
    );
  }

  @override
  Future<void> updateTokens({
    required String accessToken,
    required String refreshToken,
    DateTime? accessTokenExpiresAt,
  }) async {
    _values[_kAccessToken] = accessToken;
    _values[_kRefreshToken] = refreshToken;
    if (accessTokenExpiresAt != null) {
      _values[_kAccessTokenExpiresAt] = accessTokenExpiresAt.toIso8601String();
    } else {
      _values.remove(_kAccessTokenExpiresAt);
    }
  }

  @override
  Future<void> setBiometricEnabled(bool enabled) async {
    _values[_kBiometricEnabled] = enabled.toString();
  }

  @override
  Future<void> clear() async {
    _values.clear();
  }
}
