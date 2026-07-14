import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:password_manager/data/api/api_client.dart';
import 'package:password_manager/data/api/fake_api_client.dart';
import 'package:password_manager/data/autofill/autofill_bridge_service.dart';
import 'package:password_manager/data/biometrics/biometric_authenticator.dart';
import 'package:password_manager/data/clipboard/clipboard_service.dart';
import 'package:password_manager/data/crypto/device_identity_service.dart';
import 'package:password_manager/data/export/vault_csv_exporter.dart';
import 'package:password_manager/data/security/secure_screen_service.dart';
import 'package:password_manager/data/storage/device_key_store.dart';
import 'package:password_manager/data/storage/generator_preferences_store.dart';
import 'package:password_manager/data/storage/secure_storage_service.dart';
import 'package:password_manager/data/storage/vault_local_store.dart';
import 'package:password_manager/data/vault/vault_repository.dart';
import 'package:password_manager/domain/auth/auth_status.dart';
import 'package:password_manager/domain/crypto/master_key_deriver.dart';
import 'package:password_manager/domain/crypto/vault_item_cipher.dart';
import 'package:password_manager/domain/generator/password_strength_estimator.dart';
import 'package:password_manager/domain/generator/wordlist_loader.dart';
import 'package:password_manager/presentation/auth/auth_controller.dart';

/// Composition root for dependency injection.
///
/// Riverpod is used consistently across the app for both DI and state
/// management. Widgets/controllers should depend on the [ApiClient]
/// abstraction via [apiClientProvider] rather than constructing
/// implementations directly, so a real backend can be swapped in later
/// without touching call sites.
final Provider<ApiClient> apiClientProvider = Provider<ApiClient>((ref) {
  return FakeApiClient();
});

/// Secure, platform-backed storage for the vault key and session tokens
/// (GOALS_v2 §1.4) — never SharedPreferences/plain files. Overridden with
/// [InMemorySecureStorageService] in tests to avoid touching platform
/// channels.
final Provider<SecureStorageService> secureStorageServiceProvider =
    Provider<SecureStorageService>((ref) {
      return FlutterSecureStorageService();
    });

/// Local biometric convenience-unlock (GOALS_v2 §1.3). Overridden with
/// [FakeBiometricAuthenticator] in tests.
final Provider<BiometricAuthenticator> biometricAuthenticatorProvider =
    Provider<BiometricAuthenticator>((ref) {
      return LocalAuthBiometricAuthenticator();
    });

/// Pure two-key derivation logic (GOALS_v2 §1.3); see
/// `lib/domain/crypto/master_key_deriver.dart`.
final Provider<MasterKeyDeriver> masterKeyDeriverProvider =
    Provider<MasterKeyDeriver>((ref) {
      return MasterKeyDeriver();
    });

/// Local encrypted persistence for vault items (GOALS_v2 §1.1). Overridden
/// with [InMemoryVaultLocalStore] in tests to avoid touching the
/// filesystem.
final Provider<VaultLocalStore> vaultLocalStoreProvider =
    Provider<VaultLocalStore>((ref) {
      return FileVaultLocalStore();
    });

/// Per-item AES-GCM encryption using the vault key from `AuthState`.
final Provider<VaultItemCipher> vaultItemCipherProvider =
    Provider<VaultItemCipher>((ref) {
      return VaultItemCipher();
    });

/// The vault repository for the current session, or `null` when there is no
/// signed-in-unlocked session (no `userId`/`vaultKey` to scope it to).
///
/// Scoped per-user by construction (see `LocalVaultRepository`) so vault
/// screens can never accidentally query another account's items — this is
/// also what Phase 8's autofill service will depend on for the same
/// guarantee (GOALS_v2 §1.8).
final Provider<VaultRepository?> vaultRepositoryProvider =
    Provider<VaultRepository?>((ref) {
      final auth = ref.watch(authControllerProvider);
      final userId = auth.userId;
      final vaultKey = auth.vaultKey;
      if (auth.status != AuthStatus.signedInUnlocked ||
          userId == null ||
          vaultKey == null) {
        return null;
      }
      return LocalVaultRepository(
        userId: userId,
        vaultKey: vaultKey,
        store: ref.watch(vaultLocalStoreProvider),
        cipher: ref.watch(vaultItemCipherProvider),
      );
    });

/// Loads the newline-delimited wordlist assets bundled under
/// `assets/wordlists/` (Phase 3 — GOALS_v2 §1.2). Overridden with a fake in
/// tests that don't want to exercise the real asset bundle.
final Provider<WordlistLoader> wordlistLoaderProvider =
    Provider<WordlistLoader>((ref) => const AssetWordlistLoader());

/// The EFF long Diceware wordlist (7,776 words), used by
/// `PassphraseGenerator` — see `WordlistAssets.dicewareWordlist` for
/// sourcing rationale.
final FutureProvider<List<String>> dicewareWordlistProvider =
    FutureProvider<List<String>>((ref) {
      return ref
          .watch(wordlistLoaderProvider)
          .load(WordlistAssets.dicewareWordlist);
    });

/// A curated list of ~500 well-known weak/leaked passwords, used by
/// `PasswordStrengthEstimator` for its dictionary check.
final FutureProvider<Set<String>> commonPasswordsProvider =
    FutureProvider<Set<String>>((ref) async {
      final words = await ref
          .watch(wordlistLoaderProvider)
          .load(WordlistAssets.commonPasswords);
      return words.toSet();
    });

/// The heuristic strength estimator (GOALS_v2 §1.2, item 3) — see
/// `PasswordStrengthEstimator`'s doc comment for why this is a documented
/// estimate rather than a zxcvbn port. Async because it depends on the
/// common-password wordlist asset finishing its load.
final FutureProvider<PasswordStrengthEstimator> passwordStrengthEstimatorProvider =
    FutureProvider<PasswordStrengthEstimator>((ref) async {
      final commonPasswords = await ref.watch(commonPasswordsProvider.future);
      return PasswordStrengthEstimator(commonPasswords: commonPasswords);
    });

/// Persists this install's device identity keypair (GOALS_v2 §1.4),
/// independent of the signed-in account's session — see
/// `DeviceKeyStore`'s doc comment for why it's a separate store from
/// [secureStorageServiceProvider]. Overridden with [InMemoryDeviceKeyStore]
/// in tests to avoid touching platform channels.
final Provider<DeviceKeyStore> deviceKeyStoreProvider =
    Provider<DeviceKeyStore>((ref) {
      return FlutterDeviceKeyStore();
    });

/// Generates/loads this install's per-device X25519 keypair (GOALS_v2
/// §1.4); see `DeviceIdentityService`'s doc comment for the algorithm
/// choice rationale.
final Provider<DeviceIdentityService> deviceIdentityServiceProvider =
    Provider<DeviceIdentityService>((ref) {
      return DeviceIdentityService(store: ref.watch(deviceKeyStoreProvider));
    });

/// Persists non-secret generator UI preferences (GOALS_v2 §1.2, item 5).
/// Overridden with [InMemoryGeneratorPreferencesStore] in tests to avoid
/// touching the filesystem via `path_provider`.
final Provider<GeneratorPreferencesStore> generatorPreferencesStoreProvider =
    Provider<GeneratorPreferencesStore>((ref) {
      return FileGeneratorPreferencesStore();
    });

/// How long a copied secret sits in the clipboard before being auto-cleared
/// (GOALS_v2 §2.4). Kept as its own provider, mirroring
/// `autoLockTimeoutProvider`, so tests can override it with a short value
/// instead of waiting out the real default.
final Provider<Duration> clipboardClearTimeoutProvider = Provider<Duration>((
  ref,
) {
  return kDefaultClipboardClearTimeout;
});

/// Clipboard hygiene for copied passwords/secrets (GOALS_v2 §2.4) — see
/// `ClipboardService`'s doc comment. A single instance is shared for the
/// whole app so `AutoLockWrapper` can proactively clear it on lock as well
/// as the vault/generator screens copying into it.
final Provider<ClipboardService> clipboardServiceProvider =
    Provider<ClipboardService>((ref) {
      final service = ClipboardService(
        clearAfter: ref.watch(clipboardClearTimeoutProvider),
      );
      ref.onDispose(service.dispose);
      return service;
    });

/// Toggles Android `FLAG_SECURE` on secret-bearing screens (GOALS_v2 §2.5)
/// — see `SecureScreenService`'s doc comment for the platform-channel and
/// app-wide-while-unlocked rationale. Overridden with a fake in tests to
/// avoid touching a real platform channel.
final Provider<SecureScreenService> secureScreenServiceProvider =
    Provider<SecureScreenService>((ref) {
      return SecureScreenService();
    });

/// Writes the plaintext CSV vault export (GOALS_v2 §3.3) to disk. Overridden
/// with [InMemoryVaultCsvExporter] in tests to avoid touching
/// `path_provider`'s platform channel or the real filesystem.
final Provider<VaultCsvExporter> vaultCsvExporterProvider =
    Provider<VaultCsvExporter>((ref) {
      return FileVaultCsvExporter();
    });

/// The native-facing half of Android autofill (GOALS_v2 §1.8) — see
/// `AutofillBridgeService`'s doc comment for the full "only answers while
/// the engine is alive and a session is unlocked" scope. `AutoLockWrapper`
/// is what actually calls [AutofillBridgeService.register]/`unregister` as
/// the session locks/unlocks, mirroring how it drives
/// [secureScreenServiceProvider]. A single instance is shared for the
/// whole app's lifetime; disposed defensively on provider teardown so a
/// hot-restarted app in tests never leaves a stale handler registered.
final Provider<AutofillBridgeService> autofillBridgeServiceProvider =
    Provider<AutofillBridgeService>((ref) {
      final service = AutofillBridgeService();
      ref.onDispose(service.unregister);
      return service;
    });
