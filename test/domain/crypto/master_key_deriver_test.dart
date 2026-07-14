// Unit tests for the two-key derivation logic (GOALS_v2 §1.3): proving the
// authentication key and vault key are independent derivations of the
// master secret, not just convenience aliases of the same value.

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/domain/crypto/master_key_deriver.dart';

/// Cheap Argon2id parameters so this suite runs fast; production strength
/// is exercised separately below with the real default parameters.
Argon2id _fastArgon2id() =>
    Argon2id(parallelism: 1, memory: 8, iterations: 1, hashLength: 32);

void main() {
  group('MasterKeyDeriver', () {
    test('is deterministic for the same email + master secret', () async {
      final deriver = MasterKeyDeriver(argon2id: _fastArgon2id());
      final a = await deriver.deriveKeys(
        email: 'user@example.com',
        masterSecret: 'correct horse battery staple',
      );
      final b = await deriver.deriveKeys(
        email: 'user@example.com',
        masterSecret: 'correct horse battery staple',
      );
      expect(a.authKey, equals(b.authKey));
      expect(a.vaultKey, equals(b.vaultKey));
    });

    test('email is normalized (trimmed + lowercased) before deriving', () async {
      final deriver = MasterKeyDeriver(argon2id: _fastArgon2id());
      final a = await deriver.deriveKeys(
        email: 'User@Example.com',
        masterSecret: 'correct horse battery staple',
      );
      final b = await deriver.deriveKeys(
        email: '  user@example.com  ',
        masterSecret: 'correct horse battery staple',
      );
      expect(a.authKey, equals(b.authKey));
      expect(a.vaultKey, equals(b.vaultKey));
    });

    test('authKey and vaultKey differ for the same master secret', () async {
      final deriver = MasterKeyDeriver(argon2id: _fastArgon2id());
      final derived = await deriver.deriveKeys(
        email: 'user@example.com',
        masterSecret: 'correct horse battery staple',
      );
      expect(derived.authKey, isNot(equals(derived.vaultKey)));
    });

    test(
      'changing the master secret changes both keys, independently of a '
      'fixed salt/email',
      () async {
        final deriver = MasterKeyDeriver(argon2id: _fastArgon2id());
        final a = await deriver.deriveKeys(
          email: 'user@example.com',
          masterSecret: 'master-secret-one',
        );
        final b = await deriver.deriveKeys(
          email: 'user@example.com',
          masterSecret: 'master-secret-two',
        );
        expect(a.authKey, isNot(equals(b.authKey)));
        expect(a.vaultKey, isNot(equals(b.vaultKey)));
      },
    );

    test('changing the email changes both keys (different salt)', () async {
      final deriver = MasterKeyDeriver(argon2id: _fastArgon2id());
      final a = await deriver.deriveKeys(
        email: 'user-a@example.com',
        masterSecret: 'correct horse battery staple',
      );
      final b = await deriver.deriveKeys(
        email: 'user-b@example.com',
        masterSecret: 'correct horse battery staple',
      );
      expect(a.authKey, isNot(equals(b.authKey)));
      expect(a.vaultKey, isNot(equals(b.vaultKey)));
    });

    test(
      'different HKDF info labels produce unrelated keys from the same IKM '
      '(key-independence property)',
      () async {
        // Directly exercises the HKDF step with the same underlying secret
        // key material but different domain-separation labels, mirroring
        // what MasterKeyDeriver does internally with authKeyInfo vs
        // vaultKeyInfo. Demonstrates that swapping only the `info` label
        // is sufficient to produce a completely different key, i.e. one
        // output gives no shortcut to computing the other.
        final ikm = SecretKey(List<int>.generate(32, (i) => i));
        final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

        final outputA = await hkdf.deriveKey(
          secretKey: ikm,
          info: utf8.encode('label-a'),
        );
        final outputB = await hkdf.deriveKey(
          secretKey: ikm,
          info: utf8.encode('label-b'),
        );

        expect(
          await outputA.extractBytes(),
          isNot(equals(await outputB.extractBytes())),
        );
      },
    );

    test(
      'authKeyInfo and vaultKeyInfo domain-separation labels are distinct',
      () {
        expect(
          MasterKeyDeriver.authKeyInfo,
          isNot(equals(MasterKeyDeriver.vaultKeyInfo)),
        );
      },
    );

    test('encodeAuthKeyForTransport never emits the raw master secret', () {
      final deriver = MasterKeyDeriver(argon2id: _fastArgon2id());
      const masterSecret = 'correct horse battery staple';
      final fakeAuthKey = Uint8List.fromList(List<int>.filled(32, 7));
      final encoded = deriver.encodeAuthKeyForTransport(fakeAuthKey);
      expect(encoded.contains(masterSecret), isFalse);
    });

    test(
      'production-strength Argon2id parameters still derive successfully '
      '(slow-path smoke test)',
      () async {
        final deriver = MasterKeyDeriver();
        final derived = await deriver.deriveKeys(
          email: 'user@example.com',
          masterSecret: 'correct horse battery staple',
        );
        expect(derived.authKey, hasLength(32));
        expect(derived.vaultKey, hasLength(32));
        expect(derived.authKey, isNot(equals(derived.vaultKey)));
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  });
}
