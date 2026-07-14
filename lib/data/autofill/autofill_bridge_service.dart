import 'package:flutter/services.dart';
import 'package:password_manager/domain/autofill/autofill_matcher.dart';
import 'package:password_manager/domain/models/vault_item.dart';

/// Dart-side half of the Android Autofill bridge (GOALS_v2 §1.8).
///
/// ## Realistic scope of this bridge (read before changing the design)
/// The native `PasswordManagerAutofillService`
/// (`android/app/src/main/kotlin/com/dreambig/password_manager/PasswordManagerAutofillService.kt`)
/// can be instantiated by Android in a fresh process at any time — e.g.
/// while filling a form in some other app the user has open, with this
/// app never launched this boot. There is no vault key and therefore no
/// decrypted vault data available in that case: the vault key only ever
/// exists in this Dart isolate's memory while there is a signed-in-unlocked
/// session (see `AuthState.vaultKey`'s doc comment), and it is
/// deliberately never persisted anywhere a keyless native service could
/// read it independently — doing that just to make autofill simpler would
/// weaken the exact security model Phases 1–2 built.
///
/// So this channel only ever answers a native `getSuggestions` call when:
///  1. a `FlutterEngine` happens to already be running (the app is open or
///     backgrounded-but-not-killed) — the native side looks this up via
///     `FlutterEngineCache`, see `AutofillBridge.kt`, and
///  2. [register] has been called on it, which only happens while there is
///     a signed-in-unlocked session (see `autofillBridgeServiceProvider`
///     usage in `AutoLockWrapper`).
///
/// Whenever either condition fails, the native call gets no handler / a
/// timeout, and `PasswordManagerAutofillService` falls back to a single
/// generic "Unlock to autofill" suggestion that opens the app instead.
/// That fallback is the actual Phase 1 baseline; a live match is a bonus
/// when the app happens to already be running unlocked. A dedicated
/// always-warm background `FlutterEngine`/isolate for autofill (so matches
/// work even when the visible app isn't running) is a materially larger
/// undertaking and is deferred, not attempted here.
class AutofillBridgeService {
  AutofillBridgeService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  /// Must match `AutofillBridge.channelName` on the Kotlin side.
  static const String channelName = 'password_manager/autofill';

  final MethodChannel _channel;

  /// Starts answering native `getSuggestions` calls using [matcher], which
  /// is expected to be scoped to the current signed-in-unlocked session's
  /// `VaultRepository` (see `AutofillMatcher`'s own-items-only doc
  /// comment). Safe to call repeatedly — each call simply replaces the
  /// previous handler, e.g. when the session's vault repository changes.
  void register(AutofillMatcher matcher) {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'getSuggestions':
          final args = (call.arguments as Map?)?.cast<String, dynamic>();
          final matches = await matcher.findMatches(
            packageName: args?['packageName'] as String?,
            webDomain: args?['webDomain'] as String?,
          );
          return matches.map(_toSuggestionMap).toList();
        default:
          throw MissingPluginException(
            'AutofillBridgeService: unknown method ${call.method}',
          );
      }
    });
  }

  /// Detaches the handler (called on lock/sign-out) so a native call made
  /// outside an unlocked session gets no answer and correctly falls back
  /// to the unlock suggestion, rather than being served by a stale matcher
  /// bound to a session that's no longer current.
  void unregister() {
    _channel.setMethodCallHandler(null);
  }

  /// The wire shape returned to native code for each match. [identifier]
  /// and [secret] are only ever sent across this channel while the app's
  /// own process already holds them decrypted in memory for an unlocked
  /// session — this is not a new exposure surface beyond what the rest of
  /// the running app already has (GOALS_v2 §2.8: never logged, per
  /// `CredentialData.toString()`'s redaction — this map is a deliberate,
  /// narrow exception built for exactly this purpose, not a log line).
  static Map<String, Object?> _toSuggestionMap(VaultItem item) {
    return <String, Object?>{
      'id': item.id,
      'identifier': item.data.identifier,
      'secret': item.data.secret,
      'siteName': item.data.siteName,
      'url': item.data.url,
    };
  }
}
