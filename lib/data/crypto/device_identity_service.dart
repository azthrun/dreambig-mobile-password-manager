import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:password_manager/data/storage/device_key_store.dart';

/// The public-facing identity of this device install — the only shape that
/// is ever safe to hand to `ApiClient`.
///
/// Deliberately carries **no** private key material: the private key never
/// leaves [DeviceIdentityService]/[DeviceKeyStore], so nothing constructed
/// from a [DeviceIdentity] can ever accidentally be serialized/transmitted.
class DeviceIdentity {
  const DeviceIdentity({
    required this.deviceId,
    required this.publicKeyBase64,
  });

  final String deviceId;
  final String publicKeyBase64;
}

/// Generates and persists this install's per-device asymmetric keypair
/// (GOALS_v2 §1.4: "Devices register a public/private keypair for
/// encryption purposes").
///
/// **Algorithm choice — X25519.** The app already depends on the
/// `cryptography` package for AES-256-GCM (`VaultItemCipher`) and
/// Argon2id/HKDF (`MasterKeyDeriver`), and that package ships a
/// constant-time X25519 implementation, so no new dependency is needed.
/// X25519 also fits the device-authorization use case better than RSA:
/// keys are a fixed 32 bytes (cheap to store/transmit/display as a
/// fingerprint), and ECDH key agreement is the natural primitive for the
/// eventual "wrap the vault key for a newly-approved device" step that
/// per-device asymmetric keys exist to support — an RSA keypair would need
/// a separate wrap/encrypt scheme (e.g. RSA-OAEP) for the same job.
///
/// **Idempotent per install.** The first call generates a keypair and
/// persists it via [DeviceKeyStore]; every subsequent call — including
/// across process restarts, since [DeviceKeyStore] is backed by platform
/// secure storage — returns the *same* [DeviceIdentity] rather than
/// generating a new one. This is what makes device registration safe to
/// call idempotently from every sign-in/unlock (see `AuthController`):
/// re-registering the same [DeviceIdentity.deviceId] is a no-op check-in on
/// the backend, not a new pending-approval request.
class DeviceIdentityService {
  DeviceIdentityService({
    DeviceKeyStore? store,
    X25519? algorithm,
    Random? random,
  }) : _store = store ?? FlutterDeviceKeyStore(),
       _algorithm = algorithm ?? X25519(),
       _random = random ?? Random.secure();

  final DeviceKeyStore _store;
  final X25519 _algorithm;
  final Random _random;

  Future<DeviceIdentity> loadOrCreateIdentity() async {
    final stored = await _store.readIdentity();
    if (stored != null) {
      return DeviceIdentity(
        deviceId: stored.deviceId,
        publicKeyBase64: stored.publicKeyBase64,
      );
    }

    final keyPair = await _algorithm.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final privateKeyBytes = await keyPair.extractPrivateKeyBytes();
    final deviceId = _newDeviceId();
    final publicKeyBase64 = base64Encode(publicKey.bytes);

    await _store.writeIdentity(
      StoredDeviceIdentity(
        deviceId: deviceId,
        privateKeyBytes: Uint8List.fromList(privateKeyBytes),
        publicKeyBase64: publicKeyBase64,
      ),
    );

    return DeviceIdentity(
      deviceId: deviceId,
      publicKeyBase64: publicKeyBase64,
    );
  }

  String _newDeviceId() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return 'device-$hex';
  }
}
