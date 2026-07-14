import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// This install's persisted device keypair (GOALS_v2 §1.4).
///
/// [privateKeyBytes] must never be handed to `ApiClient` or anything else
/// that could serialize/transmit it — only [publicKeyBase64] is ever
/// intended to cross that boundary (see `DeviceIdentityService`, which is
/// the only thing that reads this class's private key field).
class StoredDeviceIdentity {
  const StoredDeviceIdentity({
    required this.deviceId,
    required this.privateKeyBytes,
    required this.publicKeyBase64,
  });

  final String deviceId;
  final Uint8List privateKeyBytes;
  final String publicKeyBase64;

  /// Defense-in-depth against key-material leakage into logs/crash reports
  /// (GOALS_v2 §2.8) — [privateKeyBytes] must never appear in a log line;
  /// [publicKeyBase64] is safe since it is, by design, the half of this
  /// keypair that's already meant to leave the device.
  @override
  String toString() =>
      'StoredDeviceIdentity(deviceId: $deviceId, privateKeyBytes: <redacted>, '
      'publicKeyBase64: $publicKeyBase64)';
}

/// Abstraction over secure, platform-backed storage for this install's
/// device identity keypair — kept as its own store (mirroring
/// `SecureStorageService`'s interface pattern) rather than folded into
/// [SecureStorageService] because it is deliberately **not** cleared by
/// `SecureStorageService.clear()` on sign-out: the device identity is a
/// property of this physical install, not of any one signed-in account, so
/// it must survive sign-out/sign-in cycles (GOALS_v2 §1.4 — "a device only
/// needs registering once per install").
abstract class DeviceKeyStore {
  Future<StoredDeviceIdentity?> readIdentity();

  Future<void> writeIdentity(StoredDeviceIdentity identity);

  /// Wipes this install's device identity keypair.
  ///
  /// Deliberately **not** called by sign-out (see this class's doc comment
  /// on why device identity outlives a session) — the one legitimate caller
  /// is account deletion (GOALS_v2 §1.7), which is a stronger, irreversible
  /// action: nothing tied to the deleted account should remain on the
  /// device afterward, including this install's device identity.
  Future<void> clear();
}

const String _kDeviceId = 'device.id';
const String _kDevicePrivateKey = 'device.privateKey';
const String _kDevicePublicKey = 'device.publicKey';

/// Namespace/account name used to physically isolate this store's entries
/// from [SecureStorageService]'s.
///
/// `flutter_secure_storage`'s `deleteAll()` clears *every* key visible to
/// the [FlutterSecureStorage] instance that calls it, scoped only by
/// platform-level namespace/account options — not by which Dart object
/// wrote a given key. Both stores previously used
/// `const FlutterSecureStorage()` with no namespace override, which put
/// them in the same underlying namespace: `SecureStorageService.clear()`
/// (called on sign-out, see `AuthController`) would silently delete this
/// store's device keypair too, contradicting the documented intent that
/// device identity survives sign-out and forcing an unwanted
/// re-registration/re-approval on next sign-in. Giving this store its own
/// `storageNamespace`/`accountName` makes that isolation real instead of
/// aspirational.
const String _kDeviceIdentityNamespace = 'device_identity';

/// [FlutterSecureStorage]-backed implementation (Android Keystore-backed on
/// Android). Used everywhere in the running app.
///
/// Uses a dedicated storage namespace (see [_kDeviceIdentityNamespace]) so
/// that clearing account-scoped secure storage on sign-out
/// (`SecureStorageService.clear()`) cannot also delete this install's
/// device keypair.
class FlutterDeviceKeyStore implements DeviceKeyStore {
  FlutterDeviceKeyStore([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(
              storageNamespace: _kDeviceIdentityNamespace,
            ),
            iOptions: IOSOptions(accountName: _kDeviceIdentityNamespace),
            mOptions: MacOsOptions(accountName: _kDeviceIdentityNamespace),
          );

  final FlutterSecureStorage _storage;

  @override
  Future<StoredDeviceIdentity?> readIdentity() async {
    final values = await Future.wait(<Future<String?>>[
      _storage.read(key: _kDeviceId),
      _storage.read(key: _kDevicePrivateKey),
      _storage.read(key: _kDevicePublicKey),
    ]);
    final deviceId = values[0];
    final privateKeyB64 = values[1];
    final publicKeyB64 = values[2];
    if (deviceId == null || privateKeyB64 == null || publicKeyB64 == null) {
      return null;
    }
    return StoredDeviceIdentity(
      deviceId: deviceId,
      privateKeyBytes: base64Decode(privateKeyB64),
      publicKeyBase64: publicKeyB64,
    );
  }

  @override
  Future<void> writeIdentity(StoredDeviceIdentity identity) async {
    await Future.wait(<Future<void>>[
      _storage.write(key: _kDeviceId, value: identity.deviceId),
      _storage.write(
        key: _kDevicePrivateKey,
        value: base64Encode(identity.privateKeyBytes),
      ),
      _storage.write(key: _kDevicePublicKey, value: identity.publicKeyBase64),
    ]);
  }

  @override
  Future<void> clear() async {
    // Safe to use `deleteAll()` here (unlike `SecureStorageService.clear()`
    // would be if it shared a namespace) precisely because this store has
    // its own dedicated [_kDeviceIdentityNamespace] — nothing else's keys
    // live in it.
    await _storage.deleteAll();
  }
}

/// In-memory fake for tests, mirroring `InMemorySecureStorageService`'s
/// role for `SecureStorageService`.
class InMemoryDeviceKeyStore implements DeviceKeyStore {
  StoredDeviceIdentity? _identity;

  @override
  Future<StoredDeviceIdentity?> readIdentity() async => _identity;

  @override
  Future<void> writeIdentity(StoredDeviceIdentity identity) async {
    _identity = identity;
  }

  @override
  Future<void> clear() async {
    _identity = null;
  }
}
