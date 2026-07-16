import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Result of deriving the two independent keys from the user's two
/// independent secrets (GOALS_v2 §1.3): [authKey] from the account
/// password, [vaultKey] from the master secret.
///
/// [authKey] and [vaultKey] are derived from *different* user-supplied
/// secrets, so neither is computable from the other even in principle.
/// [vaultKey] must never be transmitted or leave the device; only
/// [authKey] (already stretched/hashed) is ever sent to `ApiClient`.
class DerivedKeyMaterial {
  const DerivedKeyMaterial({required this.authKey, required this.vaultKey});

  /// Sent to the backend as the authentication credential. Never used to
  /// encrypt vault data.
  final Uint8List authKey;

  /// Used only locally to encrypt/decrypt vault contents. Never transmitted.
  final Uint8List vaultKey;

  /// Best-effort zeroing of key material once it's no longer needed.
  ///
  /// Dart strings/lists aren't guaranteed to be free of copies elsewhere
  /// (e.g. GC-moved buffers), so this is defense-in-depth, not a guarantee.
  void dispose() {
    authKey.fillRange(0, authKey.length, 0);
    vaultKey.fillRange(0, vaultKey.length, 0);
  }

  /// Defense-in-depth against key-material leakage into logs/crash reports
  /// (GOALS_v2 §2.8), matching the redaction pattern used by
  /// `AuthState`/`AuthSession`/`StoredSession` — this class exists
  /// specifically to carry the two most sensitive secrets in the app
  /// (the auth key and the never-transmitted vault key), so it must not
  /// rely on the default `Object.toString()` staying harmless forever.
  @override
  String toString() => 'DerivedKeyMaterial(authKey: <redacted>, vaultKey: <redacted>)';
}

/// Derives the two domain-separated keys described in GOALS_v2 §1.3 from
/// the user's **two distinct secrets**: the account password (which
/// authenticates to the backend) and the master secret (which protects the
/// vault). Keeping the inputs separate means the backend-facing credential
/// chain never even touches the secret that encrypts vault data.
///
/// Derivation pipeline (run independently per secret):
///  1. **Slow stretch** — `Argon2id(secret, salt)` produces intermediate
///     key material (IKM). This is the only step exposed to the secret's
///     comparatively low entropy; Argon2id's memory-hardness makes offline
///     brute force expensive.
///  2. **Domain-separated expansion** — HKDF (RFC 5869) with a
///     purpose-specific `info` label (`auth-key` for the account password,
///     `vault-key` for the master secret), so even identical inputs could
///     never yield colliding outputs across the two domains.
///
/// The Argon2id salt is derived deterministically from the account email so
/// sign-in can reproduce the same keys without a backend ever storing or
/// returning the master secret or vault key. A production system with a
/// real backend should prefer a per-account random salt fetched (or
/// established) before authentication rather than one derived purely from
/// email; that hardening is left for a later phase since it requires a
/// backend contract the current fake `ApiClient` doesn't model.
class MasterKeyDeriver {
  /// [argon2id] is injectable so tests can use cheaper parameters; the
  /// default follows OWASP's Argon2id guidance for interactive login use.
  MasterKeyDeriver({Argon2id? argon2id})
    : _argon2id =
          argon2id ??
          Argon2id(
            parallelism: 1,
            memory: 19 * 1024, // ~19 MiB, per OWASP guidance.
            iterations: 2,
            hashLength: stretchedKeyLength,
          );

  static const int stretchedKeyLength = 32;
  static const int derivedKeyLength = 32;

  static final List<int> _saltContext = utf8.encode(
    'password-manager/argon2-salt/v1',
  );
  static final List<int> authKeyInfo = utf8.encode(
    'password-manager/auth-key/v1',
  );
  static final List<int> vaultKeyInfo = utf8.encode(
    'password-manager/vault-key/v1',
  );

  final Argon2id _argon2id;

  Future<List<int>> _saltForEmail(String normalizedEmail) async {
    final digest = await Sha256().hash(<int>[
      ..._saltContext,
      ...utf8.encode(normalizedEmail),
    ]);
    return digest.bytes;
  }

  Future<Uint8List> _derive({
    required String email,
    required String secret,
    required List<int> info,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final salt = await _saltForEmail(normalizedEmail);

    final stretched = await _argon2id.deriveKey(
      secretKey: SecretKey(utf8.encode(secret)),
      nonce: salt,
    );

    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: derivedKeyLength);
    final derived = await hkdf.deriveKey(
      secretKey: stretched,
      nonce: salt,
      info: info,
    );
    return Uint8List.fromList(await derived.extractBytes());
  }

  /// Derives the backend authentication key from the [email] +
  /// [accountPassword]. Deterministic, so sign-in reproduces the exact
  /// credential the backend stored at sign-up.
  ///
  /// Never derived from the master secret: the account password is the
  /// only secret whose (stretched) derivative ever leaves the device.
  Future<Uint8List> deriveAuthKey({
    required String email,
    required String accountPassword,
  }) => _derive(email: email, secret: accountPassword, info: authKeyInfo);

  /// Derives the vault encryption key from the [email] + [masterSecret].
  /// Deterministic, so sign-in/unlock re-derives the same vault key the
  /// device used at sign-up time. Never transmitted.
  Future<Uint8List> deriveVaultKey({
    required String email,
    required String masterSecret,
  }) => _derive(email: email, secret: masterSecret, info: vaultKeyInfo);

  /// Derives both keys from their respective secrets — see [deriveAuthKey]
  /// and [deriveVaultKey]. [accountPassword] and [masterSecret] are
  /// deliberately two different user-supplied values (enforced at sign-up).
  Future<DerivedKeyMaterial> deriveKeys({
    required String email,
    required String accountPassword,
    required String masterSecret,
  }) async {
    return DerivedKeyMaterial(
      authKey: await deriveAuthKey(email: email, accountPassword: accountPassword),
      vaultKey: await deriveVaultKey(email: email, masterSecret: masterSecret),
    );
  }

  /// Encodes the stretched auth key as the transport string `ApiClient`
  /// expects. Still never the raw master secret or the vault key.
  String encodeAuthKeyForTransport(Uint8List authKey) => base64Encode(authKey);
}
