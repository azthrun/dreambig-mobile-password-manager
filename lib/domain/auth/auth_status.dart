/// Coarse-grained session status driving router redirects (Phase 1 scope,
/// GOALS_v2 §1.3).
enum AuthStatus {
  /// No active account session on this device.
  signedOut,

  /// A session exists (tokens + vault key are in secure storage) but the
  /// vault key is not currently held in memory — the app is locked pending
  /// re-authentication (master secret re-entry or biometric).
  signedInLocked,

  /// A session exists and the vault key is held in memory; the app is
  /// usable.
  signedInUnlocked,
}
