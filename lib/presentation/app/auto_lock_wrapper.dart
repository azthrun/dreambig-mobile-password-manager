import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:password_manager/domain/autofill/autofill_matcher.dart';
import 'package:password_manager/presentation/app/providers.dart';
import 'package:password_manager/presentation/auth/auth_controller.dart';

/// Configurable inactivity timeout before auto-lock (GOALS_v2 §1.3 / §2.3).
/// Kept as a provider so a future settings screen can override it.
final Provider<Duration> autoLockTimeoutProvider = Provider<Duration>((ref) {
  return const Duration(minutes: 5);
});

/// How often to check whether the access token needs a proactive refresh
/// (GOALS_v2 §2.7). Kept short relative to the token TTL so a revoked
/// device's session is torn down promptly rather than sitting stale until
/// the user happens to trigger a network call.
final Provider<Duration> sessionRefreshCheckIntervalProvider =
    Provider<Duration>((ref) {
      return const Duration(minutes: 1);
    });

/// Enforces auto-lock: locks the session after [autoLockTimeoutProvider] of
/// inactivity, and immediately on app backgrounding, per GOALS_v2 §1.3.
///
/// Wraps the whole app so any pointer activity anywhere resets the
/// inactivity clock, and observes app lifecycle via [WidgetsBindingObserver]
/// to lock on backgrounding regardless of the inactivity timer.
class AutoLockWrapper extends ConsumerStatefulWidget {
  const AutoLockWrapper({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AutoLockWrapper> createState() => _AutoLockWrapperState();
}

class _AutoLockWrapperState extends ConsumerState<AutoLockWrapper>
    with WidgetsBindingObserver {
  Timer? _inactivityTimer;
  Timer? _sessionRefreshTimer;

  /// Tracked so [_syncSecureFlag] can tell backgrounding apart from
  /// foreground locking — see that method's doc comment for why the
  /// distinction matters for `FLAG_SECURE`.
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _inactivityTimer?.cancel();
    _sessionRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      ref.read(authControllerProvider.notifier).lock();
      // Backgrounding alone must never clear `FLAG_SECURE` — see
      // _syncSecureFlag's doc comment.
    } else if (state == AppLifecycleState.resumed) {
      // Coming back to the foreground is the one point where it's safe to
      // drop `FLAG_SECURE` if we're locked: the Recents/Overview snapshot
      // that could have exposed vault content was already taken (and
      // protected) while backgrounded, and whatever's about to render now
      // is the lock/sign-in screen, which never shows secrets.
      _syncSecureFlag();
    }
  }

  /// Applies the current `FLAG_SECURE` state from (auth status, lifecycle
  /// state), rather than clearing it as a direct, synchronous side effect
  /// of every lock transition.
  ///
  /// **Why this indirection matters**: `didChangeAppLifecycleState` fires
  /// on `paused` around the same time Android tears down the visible
  /// window and (separately, on the native side) captures a task snapshot
  /// for the Recents/Overview UI. If locking-due-to-backgrounding cleared
  /// `FLAG_SECURE` immediately, that clear is an async platform-channel
  /// round trip racing that snapshot capture — if the flag gets cleared
  /// before the OS takes the snapshot, the *last unlocked frame* (showing
  /// plaintext vault content) could be captured and shown later in the
  /// task switcher, defeating the whole point of GOALS_v2 §2.5.
  ///
  /// So the rule is: `FLAG_SECURE` turns on the moment the session
  /// unlocks (unchanged), but it only turns *off* once the app is both
  /// locked *and* back in the foreground (or fully signed out) — i.e.
  /// once we're certain we're actually showing the (secret-free) lock/
  /// sign-in screen rather than mid-transition to background. While
  /// backgrounded-and-locked, `FLAG_SECURE` is deliberately left on.
  void _syncSecureFlag() {
    final unlocked = ref.read(authControllerProvider).isUnlocked;
    if (unlocked) {
      unawaited(ref.read(secureScreenServiceProvider).setSecure(true));
    } else if (_lifecycleState == AppLifecycleState.resumed) {
      unawaited(ref.read(secureScreenServiceProvider).setSecure(false));
    }
  }

  /// Registers/unregisters the native-facing autofill handler
  /// (GOALS_v2 §1.8) in lockstep with the session, mirroring
  /// [_syncSecureFlag]'s "driven off (auth status)" shape: a matcher is
  /// only ever wired up while there's both an unlocked session *and* a
  /// [vaultRepositoryProvider] to scope it to, and is torn down the moment
  /// either stops being true, so a native `getSuggestions` call can never
  /// be answered by a matcher left over from a previous/different session.
  void _syncAutofillBridge(bool unlocked) {
    final bridge = ref.read(autofillBridgeServiceProvider);
    final repository = unlocked ? ref.read(vaultRepositoryProvider) : null;
    if (repository != null) {
      bridge.register(AutofillMatcher(repository));
    } else {
      bridge.unregister();
    }
  }

  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    if (!ref.read(authControllerProvider).isUnlocked) return;
    final timeout = ref.read(autoLockTimeoutProvider);
    _inactivityTimer = Timer(timeout, () {
      ref.read(authControllerProvider.notifier).lock();
    });
  }

  void _onUserActivity([PointerEvent? _]) => _resetInactivityTimer();

  /// Periodically calls `AuthController.ensureValidSession` so a
  /// short-lived access token gets refreshed proactively (GOALS_v2 §2.7)
  /// instead of only ever being checked reactively before some future API
  /// call. This is also how a device revocation while the app is sitting
  /// open eventually surfaces: once the access token expires, the refresh
  /// attempt is rejected and `AuthController` forces the session closed.
  void _startSessionRefreshTimer() {
    _sessionRefreshTimer?.cancel();
    final interval = ref.read(sessionRefreshCheckIntervalProvider);
    _sessionRefreshTimer = Timer.periodic(interval, (_) {
      ref.read(authControllerProvider.notifier).ensureValidSession();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Whenever the session transitions to unlocked, (re)start both the
    // inactivity clock and the periodic session-refresh check; whenever it
    // leaves unlocked, stop both.
    //
    // This is also the single hook for two Phase 6 hardening measures tied
    // to the same lock/unlock transition (GOALS_v2 §2.4, §2.5), rather than
    // duplicating lifecycle plumbing elsewhere:
    //  - Clipboard hygiene: locking proactively clears the clipboard if it
    //    still holds a copied secret, instead of only ever relying on the
    //    auto-clear timeout to eventually catch up.
    //  - `FLAG_SECURE`: turned on the moment the session unlocks (any
    //    screen reachable then is vault-adjacent); turning it back off is
    //    routed through `_syncSecureFlag` rather than done unconditionally
    //    here, so a backgrounding-triggered lock doesn't race the OS's
    //    Recents/Overview snapshot capture — see that method's doc comment.
    ref.listen(authControllerProvider, (previous, next) {
      if (next.isUnlocked) {
        _resetInactivityTimer();
        _startSessionRefreshTimer();
      } else {
        _inactivityTimer?.cancel();
        _sessionRefreshTimer?.cancel();
        unawaited(
          ref.read(clipboardServiceProvider).clearNowIfHoldingSecret(),
        );
      }
      _syncSecureFlag();
      _syncAutofillBridge(next.isUnlocked);
    });

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onUserActivity,
      onPointerMove: _onUserActivity,
      onPointerUp: _onUserActivity,
      child: widget.child,
    );
  }
}
