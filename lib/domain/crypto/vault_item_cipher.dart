import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// An encrypted vault-item payload, ready to persist. All three fields are
/// required to decrypt — none of them are secret on their own (nonce/MAC
/// are not secrets), but [cipherText] never contains plaintext.
class EncryptedVaultPayload {
  // Private: the only ways to obtain an [EncryptedVaultPayload] are
  // [VaultItemCipher.encryptJson] (real AES-256-GCM ciphertext) or
  // [EncryptedVaultPayload.fromJson] (deserializing an already-encrypted
  // wire payload). There is deliberately no public constructor that would
  // let arbitrary bytes — including plaintext — be labeled as `cipherText`.
  const EncryptedVaultPayload._({
    required this.cipherText,
    required this.nonce,
    required this.mac,
  });

  final Uint8List cipherText;
  final Uint8List nonce;
  final Uint8List mac;

  Map<String, String> toJson() => <String, String>{
    'cipherText': base64Encode(cipherText),
    'nonce': base64Encode(nonce),
    'mac': base64Encode(mac),
  };

  factory EncryptedVaultPayload.fromJson(Map<String, dynamic> json) {
    return EncryptedVaultPayload._(
      cipherText: base64Decode(json['cipherText'] as String),
      nonce: base64Decode(json['nonce'] as String),
      mac: base64Decode(json['mac'] as String),
    );
  }
}

/// Encrypts/decrypts individual vault-item payloads at rest, using the
/// vault encryption key that already lives in `AuthState.vaultKey`
/// (GOALS_v2 §1.3) — this class never derives or stores that key itself,
/// it only consumes it per-call.
///
/// AES-256-GCM is used: authenticated encryption so tampering with the
/// on-disk ciphertext is detected on decrypt rather than silently producing
/// garbage plaintext, with a fresh random nonce per encryption (required
/// for GCM's security — nonces must never repeat under the same key).
class VaultItemCipher {
  final AesGcm _algorithm = AesGcm.with256bits();

  Future<EncryptedVaultPayload> encryptJson(
    Uint8List vaultKey,
    Map<String, dynamic> json,
  ) async {
    final plainText = utf8.encode(jsonEncode(json));
    final secretKey = SecretKey(vaultKey);
    final nonce = _algorithm.newNonce();
    final box = await _algorithm.encrypt(
      plainText,
      secretKey: secretKey,
      nonce: nonce,
    );
    return EncryptedVaultPayload._(
      cipherText: Uint8List.fromList(box.cipherText),
      nonce: Uint8List.fromList(nonce),
      mac: Uint8List.fromList(box.mac.bytes),
    );
  }

  Future<Map<String, dynamic>> decryptJson(
    Uint8List vaultKey,
    EncryptedVaultPayload payload,
  ) async {
    final secretKey = SecretKey(vaultKey);
    final secretBox = SecretBox(
      payload.cipherText,
      nonce: payload.nonce,
      mac: Mac(payload.mac),
    );
    final plainText = await _algorithm.decrypt(secretBox, secretKey: secretKey);
    return jsonDecode(utf8.decode(plainText)) as Map<String, dynamic>;
  }
}
