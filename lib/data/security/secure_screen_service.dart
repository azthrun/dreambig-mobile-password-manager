import 'package:flutter/services.dart';

/// Thin seam over the actual `FLAG_SECURE` platform call, so
/// [SecureScreenService] can be exercised in widget tests without touching
/// a real platform channel — this codebase's test sandbox has no Android
/// host to answer platform-channel calls, and (like the real OS clipboard,
/// see `ClipboardAdapter`'s doc comment) an unanswered channel call hangs
/// the test indefinitely rather than failing fast. Mirrors the existing
/// abstraction + real/fake pattern used for `SecureStorageService` and
/// `BiometricAuthenticator`.
abstract class SecureScreenChannel {
  Future<void> setSecure(bool enabled);
}

/// Real implementation: a minimal, dedicated `MethodChannel` handled
/// directly in `MainActivity.kt`.
///
/// **Implementation choice**: there is no Flutter-level API for
/// `FLAG_SECURE`, and pulling in a third-party plugin (e.g.
/// `flutter_windowmanager`, `secure_application`) for what is a two-line
/// native call is more dependency surface than the feature justifies
/// (AGENTS.md: "avoid adding dependencies unless clearly justified").
/// Instead this is a dedicated platform channel that just calls
/// `Window.setFlags(FLAG_SECURE, FLAG_SECURE)` /
/// `Window.clearFlags(FLAG_SECURE)` on the Android side.
class FlutterSecureScreenChannel implements SecureScreenChannel {
  const FlutterSecureScreenChannel();

  static const MethodChannel _channel = MethodChannel(
    SecureScreenService.channelName,
  );

  @override
  Future<void> setSecure(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setSecure', <String, bool>{
        'enabled': enabled,
      });
    } on MissingPluginException {
      // No native implementation registered (e.g. running on a platform
      // other than Android, or in a host that hasn't wired the channel).
    } on PlatformException {
      // Best-effort hardening; never block the app on this.
    }
  }
}

/// In-memory fake for tests: records the most recent call instead of
/// touching a real platform channel.
class FakeSecureScreenChannel implements SecureScreenChannel {
  bool? lastSecureValue;
  final List<bool> calls = <bool>[];

  @override
  Future<void> setSecure(bool enabled) async {
    lastSecureValue = enabled;
    calls.add(enabled);
  }
}

/// Toggles Android's `FLAG_SECURE` window flag, which blocks screenshots
/// and screen recording/casting of the app's content (GOALS_v2 §2.5).
///
/// **Granularity choice**: rather than threading this through every
/// individual screen's lifecycle, it is toggled once, app-wide, based on
/// whether the session is signed-in-unlocked (see `AutoLockWrapper`, which
/// already owns the single `ref.listen(authControllerProvider, ...)` this
/// hooks into). In this app almost every unlocked screen is vault-adjacent
/// (list, detail, generator, even the device list which is
/// security-sensitive), while every *locked*/signed-out screen (sign-in,
/// lock screen, recovery-mode choice) never displays plaintext secrets. So
/// "secure while unlocked, not secure while locked/signed-out" gets the
/// actual protection GOALS_v2 §2.5 asks for without a fragile per-route
/// toggle that a future new screen could easily forget to opt into.
class SecureScreenService {
  SecureScreenService({SecureScreenChannel? channel})
    : _channel = channel ?? const FlutterSecureScreenChannel();

  static const String channelName = 'password_manager/secure_screen';

  final SecureScreenChannel _channel;

  /// Enables (`true`) or disables (`false`) `FLAG_SECURE` on the current
  /// window.
  Future<void> setSecure(bool enabled) => _channel.setSecure(enabled);
}
