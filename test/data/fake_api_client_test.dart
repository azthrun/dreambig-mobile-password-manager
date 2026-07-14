// Base unit test for the Phase 0 ApiClient scaffolding: verifies the fake
// implementation honors the contract other layers will build against
// (sign-up/confirm/sign-in happy path, and a couple of guard rails).

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/data/api/encrypted_envelope.dart';
import 'package:password_manager/data/api/fake_api_client.dart';
import 'package:password_manager/domain/crypto/vault_item_cipher.dart';
import 'package:password_manager/domain/models/device_status.dart';

/// Test-only helper: builds a real [EncryptedEnvelope] the same way
/// production code would (via [VaultItemCipher.encryptJson]) since the
/// envelope has no plaintext-accepting constructor by design — see
/// `encrypted_envelope.dart`'s doc comment.
Future<EncryptedEnvelope> _envelope(String plaintextMarker) async {
  final key = Uint8List(32);
  final payload = await VaultItemCipher().encryptJson(key, <String, dynamic>{
    'marker': plaintextMarker,
  });
  return EncryptedEnvelope.fromVaultPayload(payload);
}

void main() {
  group('FakeApiClient', () {
    test('sign-up then sign-in succeeds once the email is confirmed', () async {
      final client = FakeApiClient();
      const email = 'user@example.com';
      const authKey = 'stretched-auth-key';

      final signUpSession = await client.signUp(
        email: email,
        authKey: authKey,
      );
      expect(signUpSession.userId, isNotEmpty);

      await client.confirmEmail(email: email, confirmationCode: '123456');

      final signInSession = await client.signIn(
        email: email,
        authKey: authKey,
        deviceId: 'device-1',
      );
      expect(signInSession.accessToken, isNotEmpty);
      expect(signInSession.userId, equals(signUpSession.userId));
    });

    test('refreshSession preserves the userId of the original session', () async {
      final client = FakeApiClient();
      const email = 'refresh@example.com';
      const authKey = 'stretched-auth-key';

      final signUpSession = await client.signUp(email: email, authKey: authKey);
      final refreshed = await client.refreshSession(
        refreshToken: signUpSession.refreshToken,
      );

      expect(refreshed.userId, equals(signUpSession.userId));
    });

    test('sign-in fails before the email is confirmed', () async {
      final client = FakeApiClient();
      const email = 'unconfirmed@example.com';
      const authKey = 'stretched-auth-key';

      await client.signUp(email: email, authKey: authKey);

      expect(
        () => client.signIn(
          email: email,
          authKey: authKey,
          deviceId: 'device-1',
        ),
        throwsStateError,
      );
    });

    test('pushVaultItem enforces the expected ETag for optimistic concurrency', () async {
      final client = FakeApiClient();
      final first = await client.pushVaultItem(
        accessToken: 'token',
        itemId: 'item-1',
        payload: await _envelope('cipher-v1'),
        expectedETag: null,
      );

      expect(
        () async => client.pushVaultItem(
          accessToken: 'token',
          itemId: 'item-1',
          payload: await _envelope('cipher-v2'),
          expectedETag: 'stale-etag',
        ),
        throwsStateError,
      );

      final updated = await client.pushVaultItem(
        accessToken: 'token',
        itemId: 'item-1',
        payload: await _envelope('cipher-v2'),
        expectedETag: first.eTag,
      );
      expect(updated.eTag, isNot(equals(first.eTag)));
    });

    test(
      'the first device registered for an account is auto-active; the '
      'second lands pending',
      () async {
        final client = FakeApiClient();
        const email = 'devices@example.com';
        const authKey = 'stretched-auth-key';
        await client.signUp(email: email, authKey: authKey);
        await client.confirmEmail(email: email, confirmationCode: '123456');
        final session = await client.signIn(
          email: email,
          authKey: authKey,
          deviceId: 'signed-in-device',
        );

        final firstDevice = await client.registerDevice(
          accessToken: session.accessToken,
          deviceId: 'device-1',
          publicKey: 'public-key-1',
          deviceName: 'Phone A',
        );
        expect(firstDevice.status, DeviceStatus.active);

        final secondDevice = await client.registerDevice(
          accessToken: session.accessToken,
          deviceId: 'device-2',
          publicKey: 'public-key-2',
          deviceName: 'Phone B',
        );
        expect(secondDevice.status, DeviceStatus.pending);

        final devices = await client.listDevices(
          accessToken: session.accessToken,
        );
        expect(devices, hasLength(2));
      },
    );

    test(
      're-registering an already-known deviceId is a check-in, not a new '
      'pending entry',
      () async {
        final client = FakeApiClient();
        const email = 'checkin@example.com';
        const authKey = 'stretched-auth-key';
        await client.signUp(email: email, authKey: authKey);
        await client.confirmEmail(email: email, confirmationCode: '123456');
        final session = await client.signIn(
          email: email,
          authKey: authKey,
          deviceId: 'signed-in-device',
        );

        await client.registerDevice(
          accessToken: session.accessToken,
          deviceId: 'device-1',
          publicKey: 'public-key-1',
          deviceName: 'Phone A',
        );
        final checkedIn = await client.registerDevice(
          accessToken: session.accessToken,
          deviceId: 'device-1',
          publicKey: 'public-key-1',
          deviceName: 'Phone A',
        );
        expect(checkedIn.status, DeviceStatus.active);

        final devices = await client.listDevices(
          accessToken: session.accessToken,
        );
        expect(devices, hasLength(1));
      },
    );

    test('approveDevice promotes a pending device to active', () async {
      final client = FakeApiClient();
      const email = 'approve@example.com';
      const authKey = 'stretched-auth-key';
      await client.signUp(email: email, authKey: authKey);
      await client.confirmEmail(email: email, confirmationCode: '123456');
      final session = await client.signIn(
        email: email,
        authKey: authKey,
        deviceId: 'signed-in-device',
      );

      await client.registerDevice(
        accessToken: session.accessToken,
        deviceId: 'device-1',
        publicKey: 'public-key-1',
        deviceName: 'Phone A',
      );
      await client.registerDevice(
        accessToken: session.accessToken,
        deviceId: 'device-2',
        publicKey: 'public-key-2',
        deviceName: 'Phone B',
      );

      await client.approveDevice(
        accessToken: session.accessToken,
        deviceId: 'device-2',
      );

      final devices = await client.listDevices(
        accessToken: session.accessToken,
      );
      final approved = devices.firstWhere((d) => d.deviceId == 'device-2');
      expect(approved.status, DeviceStatus.active);
    });

    test('revokeDevice marks a device revoked without deleting its entry', () async {
      final client = FakeApiClient();
      const email = 'revoke@example.com';
      const authKey = 'stretched-auth-key';
      await client.signUp(email: email, authKey: authKey);
      await client.confirmEmail(email: email, confirmationCode: '123456');
      final session = await client.signIn(
        email: email,
        authKey: authKey,
        deviceId: 'signed-in-device',
      );

      await client.registerDevice(
        accessToken: session.accessToken,
        deviceId: 'device-1',
        publicKey: 'public-key-1',
        deviceName: 'Phone A',
      );

      await client.revokeDevice(
        accessToken: session.accessToken,
        deviceId: 'device-1',
      );

      final devices = await client.listDevices(
        accessToken: session.accessToken,
      );
      expect(devices, hasLength(1));
      expect(devices.single.status, DeviceStatus.revoked);
    });

    test(
      'approveDevice refuses to re-activate a revoked device (no revocation '
      'bypass)',
      () async {
        final client = FakeApiClient();
        const email = 'revoke-bypass@example.com';
        const authKey = 'stretched-auth-key';
        await client.signUp(email: email, authKey: authKey);
        await client.confirmEmail(email: email, confirmationCode: '123456');
        final session = await client.signIn(
          email: email,
          authKey: authKey,
          deviceId: 'signed-in-device',
        );

        await client.registerDevice(
          accessToken: session.accessToken,
          deviceId: 'device-1',
          publicKey: 'public-key-1',
          deviceName: 'Phone A',
        );
        await client.registerDevice(
          accessToken: session.accessToken,
          deviceId: 'device-2',
          publicKey: 'public-key-2',
          deviceName: 'Phone B',
        );
        await client.revokeDevice(
          accessToken: session.accessToken,
          deviceId: 'device-2',
        );

        expect(
          () => client.approveDevice(
            accessToken: session.accessToken,
            deviceId: 'device-2',
          ),
          throwsStateError,
        );

        final devices = await client.listDevices(
          accessToken: session.accessToken,
        );
        final revoked = devices.firstWhere((d) => d.deviceId == 'device-2');
        expect(revoked.status, DeviceStatus.revoked);
      },
    );

    test('approveDevice throws for an unknown deviceId', () async {
      final client = FakeApiClient();
      const email = 'unknown-device@example.com';
      const authKey = 'stretched-auth-key';
      await client.signUp(email: email, authKey: authKey);
      await client.confirmEmail(email: email, confirmationCode: '123456');
      final session = await client.signIn(
        email: email,
        authKey: authKey,
        deviceId: 'signed-in-device',
      );

      await client.registerDevice(
        accessToken: session.accessToken,
        deviceId: 'device-1',
        publicKey: 'public-key-1',
        deviceName: 'Phone A',
      );

      expect(
        () => client.approveDevice(
          accessToken: session.accessToken,
          deviceId: 'does-not-exist',
        ),
        throwsStateError,
      );
    });

    // --- Phase 5 core deliverable: token TTL/expiry + device-scoped
    // invalidation (GOALS_v2 §2.7) --------------------------------------

    test(
      'an access token stops working once its TTL has elapsed, using an '
      'injectable clock rather than a real wait',
      () async {
        var now = DateTime(2026, 1, 1);
        final client = FakeApiClient(
          now: () => now,
          accessTokenTtl: const Duration(minutes: 15),
        );
        const email = 'ttl@example.com';
        const authKey = 'stretched-auth-key';
        await client.signUp(email: email, authKey: authKey);
        await client.confirmEmail(email: email, confirmationCode: '123456');
        final session = await client.signIn(
          email: email,
          authKey: authKey,
          deviceId: 'device-1',
        );

        // Still within TTL: the token authorizes calls fine.
        await client.listDevices(accessToken: session.accessToken);

        // Advance the clock past the 15-minute access-token TTL.
        now = now.add(const Duration(minutes: 16));

        expect(
          () => client.listDevices(accessToken: session.accessToken),
          throwsStateError,
        );
      },
    );

    test(
      'revokeDevice immediately invalidates that device\'s outstanding '
      'access token, before its TTL would otherwise have expired',
      () async {
        final client = FakeApiClient();
        const email = 'revoke-token@example.com';
        const authKey = 'stretched-auth-key';
        await client.signUp(email: email, authKey: authKey);
        await client.confirmEmail(email: email, confirmationCode: '123456');
        final session = await client.signIn(
          email: email,
          authKey: authKey,
          deviceId: 'device-1',
        );
        await client.registerDevice(
          accessToken: session.accessToken,
          deviceId: 'device-1',
          publicKey: 'public-key-1',
          deviceName: 'Phone A',
        );

        // Sanity: the token works before revocation.
        await client.listDevices(accessToken: session.accessToken);

        await client.revokeDevice(
          accessToken: session.accessToken,
          deviceId: 'device-1',
        );

        // The very same still-unexpired access token must now be rejected —
        // revocation does not wait for the token's TTL to elapse.
        expect(
          () => client.listDevices(accessToken: session.accessToken),
          throwsStateError,
        );
      },
    );

    test(
      'revokeDevice also invalidates that device\'s outstanding refresh '
      'token, so it cannot be used to mint a fresh access token',
      () async {
        final client = FakeApiClient();
        const email = 'revoke-refresh@example.com';
        const authKey = 'stretched-auth-key';
        await client.signUp(email: email, authKey: authKey);
        await client.confirmEmail(email: email, confirmationCode: '123456');
        final session = await client.signIn(
          email: email,
          authKey: authKey,
          deviceId: 'device-1',
        );
        await client.registerDevice(
          accessToken: session.accessToken,
          deviceId: 'device-1',
          publicKey: 'public-key-1',
          deviceName: 'Phone A',
        );

        await client.revokeDevice(
          accessToken: session.accessToken,
          deviceId: 'device-1',
        );

        expect(
          () => client.refreshSession(refreshToken: session.refreshToken),
          throwsStateError,
        );
      },
    );

    test(
      'signIn refuses a deviceId that has already been revoked for this '
      'account, rather than issuing it a fresh token pair',
      () async {
        final client = FakeApiClient();
        const email = 'signin-revoked@example.com';
        const authKey = 'stretched-auth-key';
        await client.signUp(email: email, authKey: authKey);
        await client.confirmEmail(email: email, confirmationCode: '123456');
        final session = await client.signIn(
          email: email,
          authKey: authKey,
          deviceId: 'device-1',
        );
        await client.registerDevice(
          accessToken: session.accessToken,
          deviceId: 'device-1',
          publicKey: 'public-key-1',
          deviceName: 'Phone A',
        );
        await client.revokeDevice(
          accessToken: session.accessToken,
          deviceId: 'device-1',
        );

        expect(
          () => client.signIn(
            email: email,
            authKey: authKey,
            deviceId: 'device-1',
          ),
          throwsStateError,
        );
      },
    );

    // --- Phase 7: account deletion (GOALS_v2 §1.7) ----------------------

    test(
      'deleteAccount hard-deletes the account: it can no longer sign in, '
      'and the outstanding access token stops working immediately',
      () async {
        final client = FakeApiClient();
        const email = 'delete-me@example.com';
        const authKey = 'stretched-auth-key';
        await client.signUp(email: email, authKey: authKey);
        await client.confirmEmail(email: email, confirmationCode: '123456');
        final session = await client.signIn(
          email: email,
          authKey: authKey,
          deviceId: 'device-1',
        );

        await client.deleteAccount(accessToken: session.accessToken);

        // The account no longer exists: sign-in fails.
        expect(
          () => client.signIn(
            email: email,
            authKey: authKey,
            deviceId: 'device-1',
          ),
          throwsStateError,
        );

        // The previously-issued access token is invalidated immediately,
        // not merely left to expire on its own TTL.
        expect(
          () => client.listDevices(accessToken: session.accessToken),
          throwsStateError,
        );
      },
    );

    test('deleteAccount removes every registered device for the account', () async {
      final client = FakeApiClient();
      const email = 'delete-devices@example.com';
      const authKey = 'stretched-auth-key';
      await client.signUp(email: email, authKey: authKey);
      await client.confirmEmail(email: email, confirmationCode: '123456');
      final session = await client.signIn(
        email: email,
        authKey: authKey,
        deviceId: 'device-1',
      );
      await client.registerDevice(
        accessToken: session.accessToken,
        deviceId: 'device-1',
        publicKey: 'public-key-1',
        deviceName: 'Phone A',
      );

      await client.deleteAccount(accessToken: session.accessToken);

      // Re-creating the account from scratch must not see the old devices
      // (a real backend would 404/401 any lookup by the deleted userId;
      // here we confirm indirectly via a fresh sign-up/sign-in seeing no
      // devices for its brand-new userId).
      await client.signUp(email: email, authKey: authKey);
      await client.confirmEmail(email: email, confirmationCode: '123456');
      final newSession = await client.signIn(
        email: email,
        authKey: authKey,
        deviceId: 'device-1',
      );
      final devices = await client.listDevices(
        accessToken: newSession.accessToken,
      );
      expect(devices, isEmpty);
    });

    test('deleteAccount throws for an invalid/unknown access token', () async {
      final client = FakeApiClient();

      expect(
        () => client.deleteAccount(accessToken: 'not-a-real-token'),
        throwsStateError,
      );
    });
  });
}
