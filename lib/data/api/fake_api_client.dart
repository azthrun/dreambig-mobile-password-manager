import 'dart:math';

import 'package:password_manager/data/api/api_client.dart';
import 'package:password_manager/data/api/encrypted_envelope.dart';
import 'package:password_manager/domain/models/auth_session.dart';
import 'package:password_manager/domain/models/device_status.dart';
import 'package:password_manager/domain/models/registered_device.dart';
import 'package:password_manager/domain/models/vault_item_summary.dart';

/// Bookkeeping for a single issued access token: which account/device it
/// belongs to, and when it stops being valid.
class _AccessTokenRecord {
  _AccessTokenRecord({
    required this.userId,
    required this.deviceId,
    required this.expiresAt,
  });

  final String userId;

  /// Null only for tokens issued by [FakeApiClient.signUp], which happens
  /// before any device has been registered for the (brand-new) account —
  /// see `ApiClient.signIn`'s doc comment for why device-scoping starts at
  /// sign-in.
  final String? deviceId;
  final DateTime expiresAt;
}

/// Bookkeeping for a single issued refresh token — same shape as
/// [_AccessTokenRecord] but tracked separately since the two have different
/// TTLs and a refresh token is single-use (rotated on every
/// [FakeApiClient.refreshSession] call).
class _RefreshTokenRecord {
  _RefreshTokenRecord({
    required this.userId,
    required this.deviceId,
    required this.expiresAt,
  });

  final String userId;
  final String? deviceId;
  final DateTime expiresAt;
}

/// In-memory [ApiClient] implementation used until a real backend exists.
///
/// Simulates network latency-free, persists nothing across process
/// restarts, and never performs real cryptographic validation — it exists
/// purely so upper layers can be built and tested against a stable
/// contract. Not intended for any real credential data.
///
/// **Session token lifecycle (GOALS_v2 §2.7).** Access tokens are
/// short-lived ([accessTokenTtl], 15 minutes by default) and refresh tokens
/// longer-lived ([refreshTokenTtl], 30 days by default), each tracked with a
/// real expiry rather than being opaque forever-valid strings. Tokens issued
/// by [signIn]/[refreshSession] are tied to the [String] `deviceId` that
/// requested them; [revokeDevice] immediately removes every outstanding
/// access/refresh token for that device, so a call authenticated with one of
/// those tokens fails on its very next use — not merely once the token's
/// TTL happens to elapse. This directly closes the Phase 4 gap where a
/// revoked device's existing tokens kept working.
class FakeApiClient implements ApiClient {
  FakeApiClient({
    Random? random,
    DateTime Function()? now,
    this.accessTokenTtl = const Duration(minutes: 15),
    this.refreshTokenTtl = const Duration(days: 30),
  }) : _random = random ?? Random(),
       _now = now ?? DateTime.now;

  final Random _random;

  /// Injectable clock, mirroring `LocalVaultRepository`'s pattern — lets
  /// tests exercise expiry without real `Duration`-length waits.
  final DateTime Function() _now;

  final Duration accessTokenTtl;
  final Duration refreshTokenTtl;

  final Map<String, String> _accountsByEmail = <String, String>{};
  final Map<String, String> _userIdByEmail = <String, String>{};
  final Map<String, bool> _emailConfirmed = <String, bool>{};
  final Map<String, List<RegisteredDevice>> _devicesByUserId =
      <String, List<RegisteredDevice>>{};
  final Map<String, VaultItemSummary> _vaultItems = <String, VaultItemSummary>{};

  final Map<String, _RefreshTokenRecord> _refreshTokens =
      <String, _RefreshTokenRecord>{};
  final Map<String, _AccessTokenRecord> _accessTokens =
      <String, _AccessTokenRecord>{};

  String _newId(String prefix) =>
      '$prefix-${_now().microsecondsSinceEpoch}-${_random.nextInt(1 << 32)}';

  AuthSession _newSession(String userId, {String? deviceId}) {
    final now = _now();
    final refreshToken = _newId('refresh');
    final accessToken = _newId('access');
    _refreshTokens[refreshToken] = _RefreshTokenRecord(
      userId: userId,
      deviceId: deviceId,
      expiresAt: now.add(refreshTokenTtl),
    );
    final accessExpiresAt = now.add(accessTokenTtl);
    _accessTokens[accessToken] = _AccessTokenRecord(
      userId: userId,
      deviceId: deviceId,
      expiresAt: accessExpiresAt,
    );
    return AuthSession(
      userId: userId,
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: accessExpiresAt,
    );
  }

  bool _isDeviceRevoked(String userId, String deviceId) {
    final devices = _devicesByUserId[userId];
    if (devices == null) return false;
    for (final device in devices) {
      if (device.deviceId == deviceId) return device.status.isRevoked;
    }
    // Device not registered yet — nothing to revoke against.
    return false;
  }

  String _userIdForAccessToken(String accessToken) {
    final record = _accessTokens[accessToken];
    if (record == null) {
      throw StateError('Invalid or expired access token');
    }
    if (!_now().isBefore(record.expiresAt)) {
      _accessTokens.remove(accessToken);
      throw StateError('Access token has expired');
    }
    final deviceId = record.deviceId;
    if (deviceId != null && _isDeviceRevoked(record.userId, deviceId)) {
      // The device was revoked after this token was issued — treat the
      // token as dead immediately rather than waiting for its TTL.
      _accessTokens.remove(accessToken);
      throw StateError('Access token belongs to a revoked device');
    }
    return record.userId;
  }

  @override
  Future<AuthSession> signUp({
    required String email,
    required String authKey,
  }) async {
    if (_accountsByEmail.containsKey(email)) {
      throw StateError('Account already exists for $email');
    }
    final userId = _newId('user');
    _accountsByEmail[email] = authKey;
    _userIdByEmail[email] = userId;
    _emailConfirmed[email] = false;
    // No device is registered yet for a brand-new account, so this initial
    // session's tokens aren't device-scoped (see `_AccessTokenRecord.deviceId`
    // doc comment). Device scoping begins at the first `signIn` call.
    return _newSession(userId);
  }

  @override
  Future<void> confirmEmail({
    required String email,
    required String confirmationCode,
  }) async {
    if (!_accountsByEmail.containsKey(email)) {
      throw StateError('No account for $email');
    }
    _emailConfirmed[email] = true;
  }

  @override
  Future<AuthSession> signIn({
    required String email,
    required String authKey,
    required String deviceId,
  }) async {
    final storedKey = _accountsByEmail[email];
    if (storedKey == null || storedKey != authKey) {
      throw StateError('Invalid credentials');
    }
    if (_emailConfirmed[email] != true) {
      throw StateError('Email not confirmed');
    }
    final userId = _userIdByEmail[email]!;
    if (_isDeviceRevoked(userId, deviceId)) {
      throw StateError(
        'This device has been revoked and can no longer sign in',
      );
    }
    return _newSession(userId, deviceId: deviceId);
  }

  @override
  Future<void> signOut({required String accessToken}) async {
    // Access tokens are short-lived (GOALS_v2 §2.7); dropping the mapping
    // here means it can no longer be used to authorize device calls.
    // Device *identity* itself is untouched — it belongs to the install,
    // not the session (see `DeviceKeyStore`'s doc comment).
    _accessTokens.remove(accessToken);
  }

  @override
  Future<AuthSession> refreshSession({required String refreshToken}) async {
    final record = _refreshTokens[refreshToken];
    if (record == null) {
      throw StateError('Invalid refresh token');
    }
    if (!_now().isBefore(record.expiresAt)) {
      _refreshTokens.remove(refreshToken);
      throw StateError('Refresh token has expired');
    }
    final deviceId = record.deviceId;
    if (deviceId != null && _isDeviceRevoked(record.userId, deviceId)) {
      _refreshTokens.remove(refreshToken);
      throw StateError('Refresh token belongs to a revoked device');
    }
    // Refresh tokens are single-use/rotated: the old one is consumed here
    // and a fresh access+refresh pair is issued, still scoped to the same
    // device.
    _refreshTokens.remove(refreshToken);
    return _newSession(record.userId, deviceId: deviceId);
  }

  @override
  Future<RegisteredDevice> registerDevice({
    required String accessToken,
    required String deviceId,
    required String publicKey,
    required String deviceName,
  }) async {
    final userId = _userIdForAccessToken(accessToken);
    final devices = _devicesByUserId.putIfAbsent(
      userId,
      () => <RegisteredDevice>[],
    );

    final existingIndex = devices.indexWhere((d) => d.deviceId == deviceId);
    if (existingIndex != -1) {
      // Re-registration from the same install is a no-op check-in, not a
      // fresh pending request.
      final checkedIn = devices[existingIndex].copyWith(
        lastSeenAt: _now(),
      );
      devices[existingIndex] = checkedIn;
      return checkedIn;
    }

    final hasTrustedDevice = devices.any((d) => d.status.isActive);
    final now = _now();
    final device = RegisteredDevice(
      deviceId: deviceId,
      publicKey: publicKey,
      deviceName: deviceName,
      // The first device for an account has nothing to be authorized by,
      // so it is auto-trusted; every later device requires approval from
      // an already-active device (GOALS_v2 §1.4).
      status: hasTrustedDevice ? DeviceStatus.pending : DeviceStatus.active,
      registeredAt: now,
      lastSeenAt: now,
    );
    devices.add(device);
    return device;
  }

  @override
  Future<List<RegisteredDevice>> listDevices({
    required String accessToken,
  }) async {
    final userId = _userIdForAccessToken(accessToken);
    return List<RegisteredDevice>.unmodifiable(
      _devicesByUserId[userId] ?? const <RegisteredDevice>[],
    );
  }

  @override
  Future<void> approveDevice({
    required String accessToken,
    required String deviceId,
  }) async {
    // Only an already-trusted (authenticated) device's session can approve
    // another — modeled here simply by requiring a valid accessToken for
    // the same account (GOALS_v2 §1.4).
    final userId = _userIdForAccessToken(accessToken);
    final devices = _devicesByUserId[userId];
    if (devices == null) {
      throw StateError('No devices registered for this account');
    }
    final index = devices.indexWhere((d) => d.deviceId == deviceId);
    if (index == -1) {
      throw StateError('No such device: $deviceId');
    }
    // Only a genuinely pending device may be promoted. Without this check,
    // calling approveDevice on an already-revoked device would silently
    // re-activate it — a real bypass of the revocation the caller thinks
    // they've applied. Approving an already-active device is also
    // rejected rather than treated as a harmless no-op, since neither
    // transition is a legitimate use of "authorize a new device".
    final current = devices[index].status;
    if (!current.isPending) {
      throw StateError(
        'Cannot approve device $deviceId: status is $current, not pending',
      );
    }
    devices[index] = devices[index].copyWith(status: DeviceStatus.active);
  }

  @override
  Future<void> revokeDevice({
    required String accessToken,
    required String deviceId,
  }) async {
    final userId = _userIdForAccessToken(accessToken);
    final devices = _devicesByUserId[userId];
    if (devices == null) {
      throw StateError('No devices registered for this account');
    }
    final index = devices.indexWhere((d) => d.deviceId == deviceId);
    if (index == -1) {
      throw StateError('No such device: $deviceId');
    }
    devices[index] = devices[index].copyWith(status: DeviceStatus.revoked);

    // GOALS_v2 §2.7: revocation must invalidate outstanding tokens
    // *immediately*, not merely once their TTL elapses. Blacklist every
    // access/refresh token issued to this device right now.
    _accessTokens.removeWhere(
      (_, record) => record.userId == userId && record.deviceId == deviceId,
    );
    _refreshTokens.removeWhere(
      (_, record) => record.userId == userId && record.deviceId == deviceId,
    );
  }

  @override
  Future<List<VaultItemSummary>> fetchVaultItemSummaries({
    required String accessToken,
  }) async {
    return _vaultItems.values.toList(growable: false);
  }

  @override
  Future<VaultItemSummary> pushVaultItem({
    required String accessToken,
    required String itemId,
    required EncryptedEnvelope payload,
    required String? expectedETag,
  }) async {
    final existing = _vaultItems[itemId];
    if (existing != null && expectedETag != null && existing.eTag != expectedETag) {
      throw StateError('ETag mismatch for $itemId');
    }
    final updated = VaultItemSummary(
      itemId: itemId,
      eTag: _newId('etag'),
      updatedAt: _now(),
      isDeleted: false,
    );
    _vaultItems[itemId] = updated;
    return updated;
  }

  @override
  Future<void> deleteAccount({required String accessToken}) async {
    final userId = _userIdForAccessToken(accessToken);
    final email = _userIdByEmail.entries
        .firstWhere((entry) => entry.value == userId)
        .key;

    // Unconditional hard delete (GOALS_v2 §1.7, decision #5): remove the
    // account record, every device registered to it, and blacklist every
    // outstanding token immediately — mirroring `revokeDevice`'s "takes
    // effect immediately" contract, just applied account-wide.
    _accountsByEmail.remove(email);
    _userIdByEmail.remove(email);
    _emailConfirmed.remove(email);
    _devicesByUserId.remove(userId);
    _accessTokens.removeWhere((_, record) => record.userId == userId);
    _refreshTokens.removeWhere((_, record) => record.userId == userId);

    // Note: `_vaultItems` in this fake is not partitioned by userId (no real
    // backend/remote sync exists yet — see IMPLEMENTATION_PLAN.md's note on
    // `ApiClient` being an interface-only seam). Remote vault-item deletion
    // therefore has nothing account-scoped to remove here; the real,
    // per-account local vault data is wiped client-side by
    // `AuthController.deleteAccount` via `VaultLocalStore.clear`.
  }
}
