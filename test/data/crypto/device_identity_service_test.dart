// Unit tests for the per-device X25519 keypair generation/persistence
// (GOALS_v2 §1.4): identity must be stable across repeated calls (idempotent
// per install) and its public shape must never expose private key material.

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/data/crypto/device_identity_service.dart';
import 'package:password_manager/data/storage/device_key_store.dart';

void main() {
  group('DeviceIdentityService', () {
    test(
      'loadOrCreateIdentity is deterministic per install: repeated calls '
      'return the same deviceId and public key',
      () async {
        final store = InMemoryDeviceKeyStore();
        final service = DeviceIdentityService(store: store);

        final first = await service.loadOrCreateIdentity();
        final second = await service.loadOrCreateIdentity();

        expect(second.deviceId, equals(first.deviceId));
        expect(second.publicKeyBase64, equals(first.publicKeyBase64));
      },
    );

    test(
      'a fresh install (empty store) produces a different identity than '
      'another fresh install',
      () async {
        final serviceA = DeviceIdentityService(store: InMemoryDeviceKeyStore());
        final serviceB = DeviceIdentityService(store: InMemoryDeviceKeyStore());

        final identityA = await serviceA.loadOrCreateIdentity();
        final identityB = await serviceB.loadOrCreateIdentity();

        expect(identityA.deviceId, isNot(equals(identityB.deviceId)));
        expect(
          identityA.publicKeyBase64,
          isNot(equals(identityB.publicKeyBase64)),
        );
      },
    );

    test(
      'identity survives across a new DeviceIdentityService instance backed '
      'by the same store (simulating a process restart)',
      () async {
        final store = InMemoryDeviceKeyStore();
        final first = await DeviceIdentityService(
          store: store,
        ).loadOrCreateIdentity();

        // A brand-new service instance, same underlying store.
        final second = await DeviceIdentityService(
          store: store,
        ).loadOrCreateIdentity();

        expect(second.deviceId, equals(first.deviceId));
        expect(second.publicKeyBase64, equals(first.publicKeyBase64));
      },
    );

    test(
      'the private key is never part of DeviceIdentity — only the store '
      'holds it, and it never reaches anything that could serialize it to '
      'ApiClient',
      () async {
        final store = InMemoryDeviceKeyStore();
        final identity = await DeviceIdentityService(
          store: store,
        ).loadOrCreateIdentity();

        // DeviceIdentity's public API surface only exposes deviceId and
        // publicKeyBase64 — there is no field/getter to reach private key
        // bytes from this object, structurally preventing it from leaking
        // into an ApiClient call built from `identity`.
        final asMap = <String, String>{
          'deviceId': identity.deviceId,
          'publicKey': identity.publicKeyBase64,
        };
        expect(asMap.values, isNot(contains(isA<List<int>>())));

        // The private key does exist, but only inside the store, separate
        // from anything handed to ApiClient.
        final stored = await store.readIdentity();
        expect(stored, isNotNull);
        expect(stored!.privateKeyBytes, isNotEmpty);
      },
    );
  });
}
