import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:password_manager/data/api/api_client.dart';
import 'package:password_manager/data/biometrics/biometric_authenticator.dart';
import 'package:password_manager/data/crypto/device_identity_service.dart';
import 'package:password_manager/data/storage/device_key_store.dart';
import 'package:password_manager/data/storage/secure_storage_service.dart';
import 'package:password_manager/data/storage/vault_local_store.dart';
import 'package:password_manager/domain/auth/auth_state.dart';
import 'package:password_manager/domain/auth/auth_status.dart';
import 'package:password_manager/domain/auth/recovery_mode.dart';
import 'package:password_manager/domain/crypto/master_key_deriver.dart';
import 'package:password_manager/l10n/generated/app_localizations_en.dart';
import 'package:password_manager/presentation/app/providers.dart';

/// English-only localized strings for error/reason text originating in this
/// controller, which has no [BuildContext] to call `AppLocalizations.of`.
/// Per GOALS_v2 §3.4, only English needs to exist yet — this keeps the
/// strings externalized in the ARB file (so the mechanism is in place for
/// future locales) without threading a context through the auth layer.
final AppLocalizationsEn _l10n = AppLocalizationsEn();

/// Orchestrates the sign-up/sign-in/lock/unlock session lifecycle described
/// in GOALS_v2 §1.3 on top of the pure [MasterKeyDeriver] domain logic and
/// the [ApiClient]/[SecureStorageService]/[BiometricAuthenticator]
/// abstractions.
///
/// This is deliberately a presentation-layer controller (state management),
/// not domain logic — it coordinates side-effecting collaborators, while
/// the actual key derivation math lives in `lib/domain/crypto` where it can
/// be unit tested in isolation.
class AuthController extends Notifier<AuthState> {
  MasterKeyDeriver get _deriver => ref.read(masterKeyDeriverProvider);
  SecureStorageService get _storage => ref.read(secureStorageServiceProvider);
  BiometricAuthenticator get _biometrics =>
      ref.read(biometricAuthenticatorProvider);
  ApiClient get _api => ref.read(apiClientProvider);
  DeviceIdentityService get _deviceIdentity =>
      ref.read(deviceIdentityServiceProvider);
  VaultLocalStore get _vaultLocalStore => ref.read(vaultLocalStoreProvider);
  DeviceKeyStore get _deviceKeyStore => ref.read(deviceKeyStoreProvider);

  // Held only in memory for the brief window between the user entering
  // their credentials at signup and completing the recovery-mode choice.
  // Cleared as soon as the account is created (or the attempt fails).
  String? _pendingEmail;
  String? _pendingAccountPassword;
  String? _pendingMasterSecret;

  @override
  AuthState build() {
    // Restoring from secure storage is async; kick it off after the
    // synchronous initial state (signed-out) is published. If a session is
    // found it flips to signed-in-locked, requiring re-authentication —
    // consistent with "auto-lock on backgrounding" extending to a fresh
    // process launch.
    Future.microtask(_restore);
    return const AuthState.signedOut();
  }

  bool get hasPendingSignUp =>
      _pendingEmail != null &&
      _pendingAccountPassword != null &&
      _pendingMasterSecret != null;

  /// Pending sign-up values, exposed so [SignUpScreen] can prefill its
  /// fields when the user navigates *back* from the recovery-mode step to
  /// revise their choices. In-memory only, same lifetime as the pending
  /// sign-up itself.
  String? get pendingEmail => _pendingEmail;
  String? get pendingAccountPassword => _pendingAccountPassword;
  String? get pendingMasterSecret => _pendingMasterSecret;

  Future<void> _restore() async {
    final stored = await _storage.readSession();
    if (stored == null) return;
    state = state.copyWith(
      status: AuthStatus.signedInLocked,
      email: stored.email,
      userId: stored.userId,
      accessToken: stored.accessToken,
      refreshToken: stored.refreshToken,
      accessTokenExpiresAt: stored.accessTokenExpiresAt,
      recoveryMode: stored.recoveryMode,
      biometricEnabled: stored.biometricEnabled,
    );
  }

  /// Step 1 of sign-up. Does **not** create an account — only stashes
  /// credentials in memory until the recovery-mode choice (GOALS_v2 §1.3)
  /// is made.
  void beginSignUp({
    required String email,
    required String accountPassword,
    required String masterSecret,
  }) {
    _pendingEmail = email;
    _pendingAccountPassword = accountPassword;
    _pendingMasterSecret = masterSecret;
    state = state.copyWith(clearError: true);
  }

  void cancelSignUp() {
    _pendingEmail = null;
    _pendingAccountPassword = null;
    _pendingMasterSecret = null;
  }

  /// Step 2 of sign-up: the user has now seen and chosen between the
  /// local-only and remote-backup consequence statements. Only now do we
  /// derive keys and actually create the account.
  Future<void> completeSignUp(RecoveryMode recoveryMode) async {
    final email = _pendingEmail;
    final accountPassword = _pendingAccountPassword;
    final masterSecret = _pendingMasterSecret;
    if (email == null || accountPassword == null || masterSecret == null) {
      throw StateError(_l10n.noPendingAccountError);
    }
    try {
      final derived = await _deriver.deriveKeys(
        email: email,
        accountPassword: accountPassword,
        masterSecret: masterSecret,
      );
      final authKey = _deriver.encodeAuthKeyForTransport(derived.authKey);
      final session = await _api.signUp(email: email, authKey: authKey);
      await _storage.writeSession(
        email: email,
        userId: session.userId,
        accessToken: session.accessToken,
        refreshToken: session.refreshToken,
        accessTokenExpiresAt: session.expiresAt,
        vaultKey: derived.vaultKey,
        recoveryMode: recoveryMode,
      );
      state = AuthState(
        status: AuthStatus.signedOut, // not usable until email is confirmed
        email: email,
        userId: session.userId,
        accessToken: session.accessToken,
        refreshToken: session.refreshToken,
        accessTokenExpiresAt: session.expiresAt,
        recoveryMode: recoveryMode,
        needsEmailConfirmation: true,
      );
    } catch (e) {
      state = state.copyWith(errorMessage: _l10n.authGenericError);
      rethrow;
    } finally {
      _pendingEmail = null;
      _pendingAccountPassword = null;
      _pendingMasterSecret = null;
    }
  }

  Future<void> confirmEmail(String confirmationCode) async {
    final email = state.email;
    if (email == null) {
      throw StateError(_l10n.noPendingAccountError);
    }
    try {
      await _api.confirmEmail(email: email, confirmationCode: confirmationCode);
      // A freshly-confirmed signup lands unlocked rather than forcing an
      // immediate re-entry of the master secret the user just typed.
      final stored = await _storage.readSession();
      state = state.copyWith(
        status: AuthStatus.signedInUnlocked,
        needsEmailConfirmation: false,
        vaultKey: stored?.vaultKey,
        accessTokenExpiresAt: stored?.accessTokenExpiresAt,
        clearError: true,
      );
      final token = state.accessToken;
      if (token != null) await _registerCurrentDevice(token);
    } catch (e) {
      state = state.copyWith(errorMessage: _l10n.authGenericError);
      rethrow;
    }
  }

  Future<void> signIn({
    required String email,
    required String accountPassword,
    required String masterSecret,
  }) async {
    try {
      final derived = await _deriver.deriveKeys(
        email: email,
        accountPassword: accountPassword,
        masterSecret: masterSecret,
      );
      final authKey = _deriver.encodeAuthKeyForTransport(derived.authKey);
      // Session tokens are device-scoped from the moment they're issued
      // (GOALS_v2 §2.7) so a revoked device's tokens can be invalidated
      // immediately — see `ApiClient.signIn`'s doc comment. The device
      // identity is generated/persisted entirely on-device and safe to load
      // before the network call.
      final identity = await _deviceIdentity.loadOrCreateIdentity();
      final session = await _api.signIn(
        email: email,
        authKey: authKey,
        deviceId: identity.deviceId,
      );
      final previouslyStored = await _storage.readSession();
      final recoveryMode =
          previouslyStored?.recoveryMode ?? RecoveryMode.localOnly;
      await _storage.writeSession(
        email: email,
        userId: session.userId,
        accessToken: session.accessToken,
        refreshToken: session.refreshToken,
        accessTokenExpiresAt: session.expiresAt,
        vaultKey: derived.vaultKey,
        recoveryMode: recoveryMode,
      );
      state = AuthState(
        status: AuthStatus.signedInUnlocked,
        email: email,
        userId: session.userId,
        accessToken: session.accessToken,
        refreshToken: session.refreshToken,
        accessTokenExpiresAt: session.expiresAt,
        vaultKey: derived.vaultKey,
        recoveryMode: recoveryMode,
        biometricEnabled: previouslyStored?.biometricEnabled ?? false,
      );
      await _registerCurrentDevice(session.accessToken);
    } catch (e) {
      state = state.copyWith(errorMessage: _l10n.authGenericError);
      rethrow;
    }
  }

  /// Called on inactivity timeout or app backgrounding (GOALS_v2 §1.3 /
  /// §2.3). Drops the vault key from memory; it stays in secure storage,
  /// but re-authentication is required to load it back into memory.
  void lock() {
    if (state.status != AuthStatus.signedInUnlocked) return;
    state = state.copyWith(
      status: AuthStatus.signedInLocked,
      clearVaultKey: true,
    );
  }

  /// Resume from locked using a re-entered master secret. Verifies against
  /// a locally-stored hash of the vault key rather than a network call, so
  /// unlocking works offline.
  Future<bool> unlockWithMasterSecret(String masterSecret) async {
    final email = state.email;
    if (email == null) return false;
    final stored = await _storage.readSession();
    if (stored == null) return false;
    final vaultKey = await _deriver.deriveVaultKey(
      email: email,
      masterSecret: masterSecret,
    );
    final verifier = await vaultKeyVerifierOf(vaultKey);
    if (!_bytesEqual(verifier, stored.vaultKeyVerifier)) {
      state = state.copyWith(errorMessage: _l10n.incorrectMasterSecretError);
      return false;
    }
    state = state.copyWith(
      status: AuthStatus.signedInUnlocked,
      vaultKey: vaultKey,
      accessToken: stored.accessToken,
      refreshToken: stored.refreshToken,
      accessTokenExpiresAt: stored.accessTokenExpiresAt,
      clearError: true,
    );
    await _registerCurrentDevice(stored.accessToken);
    return true;
  }

  /// Re-verifies the currently signed-in user's master secret **without**
  /// changing session/lock state, for the "re-authentication immediately
  /// before this action" gate required by both account deletion
  /// (GOALS_v2 §1.7) and CSV export (GOALS_v2 §3.3).
  ///
  /// Deliberately kept separate from [unlockWithMasterSecret] (which *does*
  /// transition the session to unlocked) — deletion/export can be triggered
  /// from an already-unlocked session, and re-entering the master secret
  /// there must re-prove the user's identity right before the destructive
  /// action, not just check a stale in-memory flag. Uses the same
  /// on-device vault-key-verifier check as unlock, so no network round trip
  /// is required.
  Future<bool> verifyMasterSecret(String masterSecret) async {
    final email = state.email;
    if (email == null) return false;
    final stored = await _storage.readSession();
    if (stored == null) return false;
    final vaultKey = await _deriver.deriveVaultKey(
      email: email,
      masterSecret: masterSecret,
    );
    final verifier = await vaultKeyVerifierOf(vaultKey);
    return _bytesEqual(verifier, stored.vaultKeyVerifier);
  }

  /// Permanently deletes the signed-in account (GOALS_v2 §1.7).
  ///
  /// Callers (`DeleteAccountScreen`) must have already re-verified the
  /// master secret via [verifyMasterSecret] and obtained explicit
  /// type-to-confirm input immediately before calling this — those are
  /// UI-level gates this method itself does not repeat, keeping "prove it's
  /// really the user and they really mean it" separate from "perform the
  /// irreversible action".
  ///
  /// Unconditional hard delete, per the decisions log (no retention):
  /// calls `ApiClient.deleteAccount`, then wipes every piece of local state
  /// tied to this install/account — secure storage (session/tokens/vault
  /// key), the local vault store, and this install's device identity
  /// keypair — before forcing sign-out to the sign-in screen.
  ///
  /// Device identity is deliberately wiped here, unlike [signOut] (which
  /// preserves it, see `DeviceKeyStore`'s doc comment): account deletion is
  /// a stronger, irreversible action with no data-retention exception, so
  /// nothing tied to this account should remain recoverable on the device
  /// afterward.
  Future<void> deleteAccount() async {
    final token = state.accessToken;
    if (token == null) {
      throw StateError(_l10n.noActiveSessionError);
    }
    final userId = state.userId;
    await _api.deleteAccount(accessToken: token);
    if (userId != null) {
      await _vaultLocalStore.clear(userId);
    }
    await _deviceKeyStore.clear();
    await _storage.clear();
    _pendingEmail = null;
    _pendingAccountPassword = null;
    _pendingMasterSecret = null;
    state = const AuthState.signedOut();
  }

  /// Resume from locked via biometrics. Per GOALS_v2 §1.3 this must never
  /// derive the vault key differently — it only gates access to the vault
  /// key that's already sitting in secure storage.
  Future<bool> unlockWithBiometric() async {
    if (!state.biometricEnabled) return false;
    final ok = await _biometrics.authenticate(
      reason: _l10n.biometricUnlockReason,
    );
    if (!ok) return false;
    final stored = await _storage.readSession();
    if (stored == null) return false;
    state = state.copyWith(
      status: AuthStatus.signedInUnlocked,
      vaultKey: stored.vaultKey,
      accessToken: stored.accessToken,
      refreshToken: stored.refreshToken,
      accessTokenExpiresAt: stored.accessTokenExpiresAt,
      clearError: true,
    );
    await _registerCurrentDevice(stored.accessToken);
    return true;
  }

  /// Registers (or checks in) this install's device identity against the
  /// account now signed in — see `ApiClient.registerDevice`'s doc comment
  /// (GOALS_v2 §1.4). Called on every sign-in/sign-up/unlock transition so
  /// a device only needs a *successful* registration once, but a lapsed one
  /// (e.g. the very first call failed offline) gets retried on the next
  /// unlock without any extra user action.
  ///
  /// Best-effort: registration failures must never block sign-in/unlock
  /// itself. Only [publicKeyBase64] (never the private key) is sent to
  /// [ApiClient].
  Future<void> _registerCurrentDevice(String accessToken) async {
    try {
      final identity = await _deviceIdentity.loadOrCreateIdentity();
      await _api.registerDevice(
        accessToken: accessToken,
        deviceId: identity.deviceId,
        publicKey: identity.publicKeyBase64,
        deviceName: _currentDeviceName(),
      );
    } catch (_) {
      // The device management screen offers a manual retry via its own
      // registration call, so a failure here is not fatal.
    }
  }

  String _currentDeviceName() => '${defaultTargetPlatform.name} device';

  Future<bool> enableBiometricUnlock() async {
    final available = await _biometrics.isAvailable();
    if (!available) return false;
    await _storage.setBiometricEnabled(true);
    state = state.copyWith(biometricEnabled: true);
    return true;
  }

  Future<void> disableBiometricUnlock() async {
    await _storage.setBiometricEnabled(false);
    state = state.copyWith(biometricEnabled: false);
  }

  /// Ensures the current session's access token is still (or will remain)
  /// valid, refreshing it proactively if it's at or near expiry
  /// (GOALS_v2 §2.7). Callers that are about to make an authenticated
  /// `ApiClient` call should invoke this first.
  ///
  /// Returns `true` if the session is (now) usable. Returns `false` and
  /// forces the session into signed-out if refresh fails — in particular,
  /// this is what makes a device revocation take effect on this device: once
  /// the access token expires, the next refresh attempt is rejected by
  /// `ApiClient.refreshSession` (device revoked), so the app can no longer
  /// silently keep working on stale credentials.
  Future<bool> ensureValidSession() async {
    if (state.status != AuthStatus.signedInUnlocked &&
        state.status != AuthStatus.signedInLocked) {
      return false;
    }
    final refreshToken = state.refreshToken;
    final expiresAt = state.accessTokenExpiresAt;
    if (refreshToken == null) return state.accessToken != null;
    // Nothing to do yet if the token still has healthy headroom left.
    if (expiresAt != null &&
        DateTime.now().isBefore(
          expiresAt.subtract(const Duration(seconds: 30)),
        )) {
      return true;
    }
    try {
      final refreshed = await _api.refreshSession(refreshToken: refreshToken);
      await _storage.updateTokens(
        accessToken: refreshed.accessToken,
        refreshToken: refreshed.refreshToken,
        accessTokenExpiresAt: refreshed.expiresAt,
      );
      state = state.copyWith(
        accessToken: refreshed.accessToken,
        refreshToken: refreshed.refreshToken,
        accessTokenExpiresAt: refreshed.expiresAt,
        clearError: true,
      );
      return true;
    } catch (_) {
      // Refresh failed — most notably because the device was revoked
      // (GOALS_v2 §2.7) or the refresh token itself expired. Either way the
      // session can no longer be trusted locally, so force it closed rather
      // than leaving the UI in a state that looks signed-in but can't
      // actually reach the (fake) backend.
      await _forceSignOutAfterInvalidSession();
      return false;
    }
  }

  Future<void> _forceSignOutAfterInvalidSession() async {
    await _storage.clear();
    _pendingEmail = null;
    _pendingAccountPassword = null;
    _pendingMasterSecret = null;
    state = const AuthState.signedOut().copyWith(
      errorMessage: _l10n.sessionInvalidError,
    );
  }

  Future<void> signOut() async {
    final token = state.accessToken;
    if (token != null) {
      try {
        await _api.signOut(accessToken: token);
      } catch (_) {
        // Best-effort: still clear local state even if the network call
        // fails, so the device never gets stuck signed-in locally.
      }
    }
    await _storage.clear();
    _pendingEmail = null;
    _pendingAccountPassword = null;
    _pendingMasterSecret = null;
    state = const AuthState.signedOut();
  }
}

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var result = 0;
  for (var i = 0; i < a.length; i++) {
    result |= a[i] ^ b[i];
  }
  return result == 0;
}

final NotifierProvider<AuthController, AuthState> authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);
