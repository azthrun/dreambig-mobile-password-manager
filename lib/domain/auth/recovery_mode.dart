/// The account recovery mode a user chooses **up front, at signup, before**
/// the account/vault is created (GOALS_v2 §1.3, decision #3).
///
/// This is intentionally a binary, explicit choice — never a hidden default
/// — because it has irreversible data-loss implications the user must
/// understand before committing.
enum RecoveryMode {
  /// Master secret and vault key exist only on-device. No recovery is
  /// possible: losing the device *or* forgetting the master secret means
  /// permanent, total data loss. The vault cannot sync to another device
  /// and is lost on app uninstall or device wipe.
  localOnly,

  /// An encrypted copy of the vault is stored server-side (still
  /// zero-knowledge — the server holds ciphertext only). This protects
  /// against device loss *only if the master secret is remembered*: the
  /// server holds no plaintext and cannot recover a forgotten master
  /// secret either. A copy of the vault does leave the device, as
  /// ciphertext.
  remoteBackup,
}
