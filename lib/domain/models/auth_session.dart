/// Represents an authenticated session returned by the backend after
/// sign-up, sign-in, or token refresh.
///
/// Only the *authentication* key material ever crosses this boundary; the
/// vault encryption key is derived and kept on-device only (see GOALS_v2
/// §1.3) and therefore never appears on this model.
class AuthSession {
  const AuthSession({
    required this.userId,
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  final String userId;
  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;

  /// Defense-in-depth against token leakage into logs/crash reports
  /// (GOALS_v2 §2.8) — redacts both tokens explicitly rather than relying
  /// on the default `Object.toString()`.
  @override
  String toString() =>
      'AuthSession(userId: $userId, accessToken: <redacted>, '
      'refreshToken: <redacted>, expiresAt: $expiresAt)';
}
