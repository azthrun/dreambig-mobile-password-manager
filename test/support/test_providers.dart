// Shared Riverpod overrides for widget tests: swap the platform-channel
// backed services (secure storage, biometrics) for in-memory fakes so
// widget tests never touch real platform channels, mirroring how
// `apiClientProvider` is already backed by `FakeApiClient` everywhere.

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:password_manager/data/biometrics/biometric_authenticator.dart';
import 'package:password_manager/data/clipboard/clipboard_service.dart';
import 'package:password_manager/data/security/secure_screen_service.dart';
import 'package:password_manager/data/storage/device_key_store.dart';
import 'package:password_manager/data/storage/generator_preferences_store.dart';
import 'package:password_manager/data/storage/secure_storage_service.dart';
import 'package:password_manager/data/storage/vault_local_store.dart';
import 'package:password_manager/domain/crypto/master_key_deriver.dart';
import 'package:password_manager/domain/generator/wordlist_loader.dart';
import 'package:password_manager/presentation/app/providers.dart';

/// A short clipboard-clear timeout for widget tests that exercise the real
/// auto-clear timer end-to-end, instead of waiting out the real 45s
/// default.
const Duration kTestClipboardClearTimeout = Duration(milliseconds: 50);

/// Cheap Argon2id parameters for widget tests.
///
/// Production Argon2id parameters (`MasterKeyDeriver`'s default: ~19 MiB)
/// make the `cryptography` package's Dart implementation spawn a real
/// background [Isolate] to do the memory-hard work. Flutter widget tests
/// run inside a fake-async zone that doesn't drive real isolate message
/// passing, so awaiting that derivation inside a widget test hangs
/// `pumpAndSettle`. The KDF's actual strength/independence properties are
/// covered directly (with real production parameters) in
/// `test/domain/crypto/master_key_deriver_test.dart`; these tests only
/// need *a* deterministic derivation to drive the auth flow UI.
MasterKeyDeriver testMasterKeyDeriver() {
  return MasterKeyDeriver(
    argon2id: Argon2id(
      parallelism: 1,
      memory: 8,
      iterations: 1,
      hashLength: MasterKeyDeriver.stretchedKeyLength,
    ),
  );
}

List<Override> testProviderOverrides({
  SecureStorageService? secureStorageService,
  BiometricAuthenticator? biometricAuthenticator,
  MasterKeyDeriver? masterKeyDeriver,
  VaultLocalStore? vaultLocalStore,
  GeneratorPreferencesStore? generatorPreferencesStore,
  WordlistLoader? wordlistLoader,
  DeviceKeyStore? deviceKeyStore,
  ClipboardService? clipboardService,
  SecureScreenService? secureScreenService,
}) {
  return <Override>[
    secureStorageServiceProvider.overrideWithValue(
      secureStorageService ?? InMemorySecureStorageService(),
    ),
    biometricAuthenticatorProvider.overrideWithValue(
      biometricAuthenticator ?? FakeBiometricAuthenticator(),
    ),
    masterKeyDeriverProvider.overrideWithValue(
      masterKeyDeriver ?? testMasterKeyDeriver(),
    ),
    // Real `FlutterDeviceKeyStore` touches the same secure-storage platform
    // channel as `secureStorageServiceProvider` — fake it out for the same
    // reason.
    deviceKeyStoreProvider.overrideWithValue(
      deviceKeyStore ?? InMemoryDeviceKeyStore(),
    ),
    // The real `FileVaultLocalStore` touches platform channels
    // (path_provider) that widget tests don't have access to.
    vaultLocalStoreProvider.overrideWithValue(
      vaultLocalStore ?? InMemoryVaultLocalStore(),
    ),
    // Same reasoning as `vaultLocalStoreProvider` above — avoid touching
    // `path_provider`'s platform channel in widget tests.
    generatorPreferencesStoreProvider.overrideWithValue(
      generatorPreferencesStore ?? InMemoryGeneratorPreferencesStore(),
    ),
    // Real asset-channel I/O (`rootBundle.loadString`) doesn't reliably
    // resolve in widget tests when first triggered outside of a widget's
    // own build (see `FakeWordlistLoader`'s doc comment) — fake it out the
    // same way the other real I/O dependencies above are faked.
    wordlistLoaderProvider.overrideWithValue(
      wordlistLoader ?? const FakeWordlistLoader(),
    ),
    // The real `Clipboard` platform channel forwards to the host OS
    // pasteboard and never responds in some test/CI sandboxes, hanging the
    // test indefinitely — use the in-memory adapter with a short timeout so
    // the auto-clear timer can actually be exercised in widget tests.
    clipboardServiceProvider.overrideWithValue(
      clipboardService ??
          ClipboardService(
            adapter: InMemoryClipboardAdapter(),
            clearAfter: kTestClipboardClearTimeout,
          ),
    ),
    // Real `SecureScreenService` touches a native platform channel with no
    // Android host in widget tests, which hangs rather than fails fast (see
    // `SecureScreenChannel`'s doc comment) — default to the recording fake
    // channel so it's both safe and inspectable; tests that care can pass
    // their own `FakeSecureScreenChannel` instance to assert on calls.
    secureScreenServiceProvider.overrideWithValue(
      secureScreenService ??
          SecureScreenService(channel: FakeSecureScreenChannel()),
    ),
  ];
}
