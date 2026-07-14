import 'dart:typed_data';

import 'package:password_manager/domain/auth/auth_status.dart';
import 'package:password_manager/domain/auth/recovery_mode.dart';

/// Full session state exposed by the auth controller.
///
/// [status] drives router redirects (signed-out/signed-in-locked/
/// signed-in-unlocked, per Phase 1 scope). [needsEmailConfirmation] is a
/// narrower, orthogonal flag: a brand-new account is neither fully signed
/// out nor usable until its email is confirmed (GOALS_v2 §1.3), so it gets
/// its own route rather than overloading [AuthStatus].
class AuthState {
  const AuthState({
    required this.status,
    this.email,
    this.userId,
    this.accessToken,
    this.refreshToken,
    this.accessTokenExpiresAt,
    this.vaultKey,
    this.recoveryMode,
    this.needsEmailConfirmation = false,
    this.biometricEnabled = false,
    this.errorMessage,
  });

  const AuthState.signedOut() : this(status: AuthStatus.signedOut);

  final AuthStatus status;
  final String? email;
  final String? userId;
  final String? accessToken;
  final String? refreshToken;

  /// When [accessToken] stops being valid (GOALS_v2 §2.7). Drives
  /// `AuthController.ensureValidSession`'s proactive-refresh check.
  final DateTime? accessTokenExpiresAt;

  /// Only ever populated while [status] is [AuthStatus.signedInUnlocked].
  /// Never persisted anywhere outside secure storage, never transmitted.
  final Uint8List? vaultKey;

  final RecoveryMode? recoveryMode;
  final bool needsEmailConfirmation;
  final bool biometricEnabled;
  final String? errorMessage;

  bool get isUnlocked => status == AuthStatus.signedInUnlocked;

  AuthState copyWith({
    AuthStatus? status,
    String? email,
    String? userId,
    String? accessToken,
    String? refreshToken,
    DateTime? accessTokenExpiresAt,
    Uint8List? vaultKey,
    bool clearVaultKey = false,
    RecoveryMode? recoveryMode,
    bool? needsEmailConfirmation,
    bool? biometricEnabled,
    String? errorMessage,
    bool clearError = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      email: email ?? this.email,
      userId: userId ?? this.userId,
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      accessTokenExpiresAt: accessTokenExpiresAt ?? this.accessTokenExpiresAt,
      vaultKey: clearVaultKey ? null : (vaultKey ?? this.vaultKey),
      recoveryMode: recoveryMode ?? this.recoveryMode,
      needsEmailConfirmation:
          needsEmailConfirmation ?? this.needsEmailConfirmation,
      biometricEnabled: biometricEnabled ?? this.biometricEnabled,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  /// Defense-in-depth against secret leakage into logs/crash reports
  /// (GOALS_v2 §2.8): [vaultKey], [accessToken], and [refreshToken] are all
  /// explicitly redacted rather than relying on the default
  /// `Object.toString()`, in case this state object is ever interpolated
  /// into an error message or log line.
  @override
  String toString() =>
      'AuthState(status: $status, email: $email, userId: $userId, '
      'accessToken: ${accessToken == null ? null : '<redacted>'}, '
      'refreshToken: ${refreshToken == null ? null : '<redacted>'}, '
      'accessTokenExpiresAt: $accessTokenExpiresAt, '
      'vaultKey: ${vaultKey == null ? null : '<redacted>'}, '
      'recoveryMode: $recoveryMode, '
      'needsEmailConfirmation: $needsEmailConfirmation, '
      'biometricEnabled: $biometricEnabled, '
      'errorMessage: $errorMessage)';
}
