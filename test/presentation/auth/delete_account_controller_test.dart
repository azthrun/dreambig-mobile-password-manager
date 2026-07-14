// Controller-level tests for AuthController.verifyMasterSecret and
// AuthController.deleteAccount (GOALS_v2 §1.7): re-authentication succeeds
// only for the correct master secret, deletion calls ApiClient.deleteAccount,
// wipes local secure storage / the local vault store / this install's
// device identity, and forces the session back to signed-out.
//
// Driven via a bare ProviderContainer (no widget tree needed) — the same
// approach recovery_mode_screen_test.dart uses to stage AuthController
// state directly.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/data/storage/device_key_store.dart';
import 'package:password_manager/data/storage/vault_local_store.dart';
import 'package:password_manager/domain/auth/auth_status.dart';
import 'package:password_manager/domain/auth/recovery_mode.dart';
import 'package:password_manager/domain/models/credential_data.dart';
import 'package:password_manager/presentation/app/providers.dart';
import 'package:password_manager/presentation/auth/auth_controller.dart';

import '../../support/test_providers.dart';

void main() {
  test(
    'verifyMasterSecret returns true for the correct secret and false for '
    'a wrong one, without changing session status',
    () async {
      final vaultLocalStore = InMemoryVaultLocalStore();
      final deviceKeyStore = InMemoryDeviceKeyStore();
      final container = ProviderContainer(
        overrides: testProviderOverrides(
          vaultLocalStore: vaultLocalStore,
          deviceKeyStore: deviceKeyStore,
        ),
      );
      addTearDown(container.dispose);

      final controller = container.read(authControllerProvider.notifier);
      controller.beginSignUp(
        email: 'verify@example.com',
        masterSecret: 'correct horse battery staple',
      );
      await controller.completeSignUp(
        RecoveryMode.localOnly,
      );
      await controller.confirmEmail('123456');

      expect(
        container.read(authControllerProvider).status,
        AuthStatus.signedInUnlocked,
      );

      final wrong = await controller.verifyMasterSecret('totally wrong');
      expect(wrong, isFalse);
      // A failed re-auth attempt must not lock/sign the session out.
      expect(
        container.read(authControllerProvider).status,
        AuthStatus.signedInUnlocked,
      );

      final correct = await controller.verifyMasterSecret(
        'correct horse battery staple',
      );
      expect(correct, isTrue);
      expect(
        container.read(authControllerProvider).status,
        AuthStatus.signedInUnlocked,
      );
    },
  );

  test(
    'deleteAccount wipes secure storage, the local vault store, this '
    "install's device identity, and forces sign-out",
    () async {
      final vaultLocalStore = InMemoryVaultLocalStore();
      final deviceKeyStore = InMemoryDeviceKeyStore();
      final container = ProviderContainer(
        overrides: testProviderOverrides(
          vaultLocalStore: vaultLocalStore,
          deviceKeyStore: deviceKeyStore,
        ),
      );
      addTearDown(container.dispose);

      final controller = container.read(authControllerProvider.notifier);
      controller.beginSignUp(
        email: 'delete-controller@example.com',
        masterSecret: 'correct horse battery staple',
      );
      await controller.completeSignUp(RecoveryMode.localOnly);
      await controller.confirmEmail('123456');

      final userId = container.read(authControllerProvider).userId;
      expect(userId, isNotNull);

      // Give this device an identity, and put something in the vault, so
      // there's something real to assert got wiped.
      final repo = container.read(vaultRepositoryProvider);
      expect(repo, isNotNull);
      await repo!.createCredential(
        const CredentialData(identifier: 'id', secret: 'secret'),
      );
      expect(await vaultLocalStore.loadAll(userId!), isNotEmpty);
      expect(await deviceKeyStore.readIdentity(), isNotNull);

      await controller.deleteAccount();

      final state = container.read(authControllerProvider);
      expect(state.status, AuthStatus.signedOut);
      expect(state.accessToken, isNull);
      expect(state.vaultKey, isNull);

      expect(await vaultLocalStore.loadAll(userId), isEmpty);
      expect(await deviceKeyStore.readIdentity(), isNull);
    },
  );

  test('deleteAccount throws if there is no active session', () async {
    final container = ProviderContainer(overrides: testProviderOverrides());
    addTearDown(container.dispose);

    final controller = container.read(authControllerProvider.notifier);

    expect(() => controller.deleteAccount(), throwsStateError);
  });
}
