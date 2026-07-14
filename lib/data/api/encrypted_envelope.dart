import 'dart:convert';

import 'package:password_manager/domain/crypto/vault_item_cipher.dart';

/// Application-layer encryption envelope (GOALS_v2 §1.5): defense in depth
/// on top of transport encryption (HTTPS/TLS).
///
/// This is the *only* shape sensitive payloads may take when crossing the
/// [ApiClient] boundary. There is deliberately no public constructor that
/// accepts a bare [String]/plaintext — the only way to build one is
/// [EncryptedEnvelope.fromVaultPayload], which requires an
/// [EncryptedVaultPayload] that can itself only be produced by
/// `VaultItemCipher.encryptJson` (real AES-256-GCM ciphertext). This makes
/// "an `ApiClient` method that takes a raw `String secret`" a compile error
/// rather than a code-review-time judgment call: nothing in this codebase
/// can construct an [EncryptedEnvelope] from plaintext.
///
/// Note this does not itself perform any additional encryption beyond what
/// [VaultItemCipher] already does — the vault payload handed to
/// [ApiClient.pushVaultItem] is already AES-256-GCM ciphertext from Phase 2
/// (confirmed: the server never sees plaintext). What this type adds is the
/// *structural* guarantee for future call sites: a real `HttpApiClient` can
/// serialize [toWireJson] directly onto an HTTPS request body without any
/// call site being able to accidentally widen the contract back to a raw
/// string.
class EncryptedEnvelope {
  const EncryptedEnvelope._({
    required this.ciphertextBase64,
    required this.nonceBase64,
    required this.macBase64,
    required this.algorithm,
  });

  /// The only production constructor. [payload] must come from
  /// `VaultItemCipher.encryptJson` — see class doc.
  factory EncryptedEnvelope.fromVaultPayload(EncryptedVaultPayload payload) {
    return EncryptedEnvelope._(
      ciphertextBase64: base64Encode(payload.cipherText),
      nonceBase64: base64Encode(payload.nonce),
      macBase64: base64Encode(payload.mac),
      algorithm: 'AES-256-GCM',
    );
  }

  final String ciphertextBase64;
  final String nonceBase64;
  final String macBase64;

  /// Cipher identifier, carried alongside the ciphertext so a future real
  /// backend (or a later client version) can validate/route decryption
  /// without guessing which algorithm produced it.
  final String algorithm;

  /// Serializes to the shape a real `HttpApiClient` would put on an HTTPS
  /// request body. Named distinctly from a generic `toJson` to make clear
  /// this is specifically the wire representation used once a real
  /// transport exists — see `HttpApiClient`'s doc comment.
  Map<String, String> toWireJson() => <String, String>{
    'ciphertext': ciphertextBase64,
    'nonce': nonceBase64,
    'mac': macBase64,
    'algorithm': algorithm,
  };
}
