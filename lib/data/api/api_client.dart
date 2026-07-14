import 'package:password_manager/data/api/encrypted_envelope.dart';
import 'package:password_manager/domain/models/auth_session.dart';
import 'package:password_manager/domain/models/registered_device.dart';
import 'package:password_manager/domain/models/vault_item_summary.dart';

/// Abstraction over the future backend surface.
///
/// No real backend exists yet (see IMPLEMENTATION_PLAN.md). This interface
/// defines the shape later phases will implement against; for now only a
/// [FakeApiClient] backs it so the app is runnable and testable end-to-end.
/// See `HttpApiClient` for the documented (unimplemented) seam a real
/// HTTPS-backed implementation would fill in later.
///
/// Every method takes/returns already-encrypted or opaque values only — the
/// server is zero-knowledge (GOALS_v2 §2.1) and this interface must never be
/// widened to accept plaintext secrets. Vault payloads specifically must
/// cross this boundary only as an [EncryptedEnvelope] (GOALS_v2 §1.5's
/// application-layer encryption on top of transport encryption) — see that
/// class's doc comment for why a raw `String`/plaintext payload can't be
/// constructed into one.
///
/// Real transport (out of scope for this repo, see IMPLEMENTATION_PLAN.md):
/// all traffic over this interface's future `HttpApiClient` implementation
/// must run over HTTPS/TLS with certificate pinning (see
/// `CertificatePinningConfig`). Backend rate-limiting/lockout on repeated
/// failed sign-in attempts (GOALS_v2 §1.5) is a hard dependency of this
/// client's security model but is entirely a backend concern — there is
/// nothing to build client-side for it.
abstract class ApiClient {
  // --- Authentication -------------------------------------------------

  /// Registers a new account. [authKey] must already be a stretched,
  /// domain-separated authentication key derived from the master secret —
  /// never the master secret itself (GOALS_v2 §1.3).
  Future<AuthSession> signUp({
    required String email,
    required String authKey,
  });

  /// Confirms a newly created account using the code/link sent to [email].
  Future<void> confirmEmail({
    required String email,
    required String confirmationCode,
  });

  /// [deviceId] ties the issued tokens to this install (GOALS_v2 §1.4/§2.7):
  /// a revoked device's tokens must stop working immediately, which requires
  /// the server (here, [FakeApiClient]) to know which device a token belongs
  /// to. Sign-in must fail if [deviceId] has already been revoked for this
  /// account.
  Future<AuthSession> signIn({
    required String email,
    required String authKey,
    required String deviceId,
  });

  Future<void> signOut({required String accessToken});

  /// Exchanges a still-valid, non-blacklisted refresh token for a new
  /// short-lived access token (and rotated refresh token). Must fail if the
  /// refresh token has expired, has been blacklisted (e.g. by
  /// [revokeDevice]), or belongs to a device that is no longer active
  /// (GOALS_v2 §2.7).
  Future<AuthSession> refreshSession({required String refreshToken});

  // --- Device registration --------------------------------------------

  /// Registers (or re-checks-in) this device's public key for
  /// asymmetric-encryption based device authorization (GOALS_v2 §1.4).
  ///
  /// [deviceId] and [publicKey] are generated/persisted entirely on-device
  /// by `DeviceIdentityService` — the private key never crosses this
  /// method's boundary, only the public key does (public keys are not
  /// secret; safe to send in clear over this fake transport). Calling this
  /// again with a [deviceId] that's already registered is a no-op check-in
  /// (updates the device's last-seen time) rather than a new registration,
  /// so callers can invoke it idempotently on every sign-in/unlock.
  ///
  /// The very first device registered for an account is auto-[
  /// DeviceStatus.active] (nothing exists yet to authorize it against);
  /// every subsequent device lands [DeviceStatus.pending] until an
  /// already-active device calls [approveDevice] for it — this is the
  /// "new-device authorization by an already-trusted device" flow from
  /// GOALS_v2 §1.4.
  Future<RegisteredDevice> registerDevice({
    required String accessToken,
    required String deviceId,
    required String publicKey,
    required String deviceName,
  });

  /// Lists every device (any status) registered to the signed-in account,
  /// for the device management screen.
  Future<List<RegisteredDevice>> listDevices({required String accessToken});

  /// Promotes a [DeviceStatus.pending] device to [DeviceStatus.active].
  /// Modeled as callable only from an already-signed-in (i.e.
  /// already-trusted) session's [accessToken], per GOALS_v2 §1.4's
  /// "authorization by an already-trusted device".
  ///
  /// Must reject (throw) if the target device is not currently
  /// [DeviceStatus.pending] — in particular, approving a
  /// [DeviceStatus.revoked] device must never re-activate it. This is not
  /// an idempotent/no-op call.
  Future<void> approveDevice({
    required String accessToken,
    required String deviceId,
  });

  /// Revokes a lost/stolen device, invalidating its tokens server-side.
  /// The device's history entry is kept (marked [DeviceStatus.revoked])
  /// rather than deleted, so the device management screen can still show
  /// that it was revoked.
  ///
  /// Per GOALS_v2 §2.7 this must take effect **immediately**: every
  /// outstanding access/refresh token previously issued to [deviceId] is
  /// blacklisted as part of this call, not merely left to expire on its own
  /// TTL. A subsequent authenticated call using one of those tokens must
  /// fail right away.
  Future<void> revokeDevice({
    required String accessToken,
    required String deviceId,
  });

  // --- Vault sync -------------------------------------------------------

  /// Lists item summaries (ciphertext + metadata only) for the signed-in
  /// account, for future sync reconciliation.
  Future<List<VaultItemSummary>> fetchVaultItemSummaries({
    required String accessToken,
  });

  /// Pushes an encrypted vault item payload. [eTag] enables optimistic
  /// concurrency once multi-device sync lands (GOALS_v2 §3.1).
  ///
  /// [payload] must be an [EncryptedEnvelope] — see that class's doc comment
  /// for why a bare `String cipherText` parameter here would be a structural
  /// gap (nothing would stop a future caller from accidentally passing
  /// plaintext).
  Future<VaultItemSummary> pushVaultItem({
    required String accessToken,
    required String itemId,
    required EncryptedEnvelope payload,
    required String? expectedETag,
  });

  // --- Account deletion --------------------------------------------------

  /// Permanently, unconditionally hard-deletes the signed-in account and
  /// every piece of backend data associated with it (GOALS_v2 §1.7): the
  /// account record, all registered devices, and all remotely-synced vault
  /// data. There is no retention/soft-delete/grace-period for this call —
  /// per the decisions log, deletion is unconditional in exchange for clear
  /// upfront communication and an accidental-trigger-proof confirmation UI,
  /// both of which are the caller's (not this method's) responsibility.
  ///
  /// Callers must have already re-authenticated the user (re-verified the
  /// master secret) immediately before invoking this — this method itself
  /// performs no additional re-auth check, it only requires a currently
  /// valid [accessToken].
  ///
  /// Implementations must also invalidate every outstanding access/refresh
  /// token for this account as part of the same call, mirroring
  /// [revokeDevice]'s "takes effect immediately" contract.
  Future<void> deleteAccount({required String accessToken});
}
