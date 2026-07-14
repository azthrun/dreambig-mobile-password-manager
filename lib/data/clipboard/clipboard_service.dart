import 'dart:async';

import 'package:flutter/services.dart';

/// Default clipboard auto-clear timeout (GOALS_v2 §2.4: "auto-clear copied
/// passwords after a short timeout (e.g., 30-60s)"). 45s sits in the middle
/// of that suggested range.
const Duration kDefaultClipboardClearTimeout = Duration(seconds: 45);

/// Thin seam over the actual clipboard read/write, so [ClipboardService]'s
/// auto-clear/don't-clobber logic can be unit- and widget-tested without
/// touching the real OS pasteboard — mirrors this codebase's existing
/// pattern of an abstraction + real/in-memory implementations (see
/// `SecureStorageService`, `BiometricAuthenticator`).
abstract class ClipboardAdapter {
  Future<void> setText(String text);
  Future<String?> getText();
}

/// Real implementation backed by `package:flutter/services.dart`'s
/// [Clipboard].
class FlutterClipboardAdapter implements ClipboardAdapter {
  const FlutterClipboardAdapter();

  @override
  Future<void> setText(String text) => Clipboard.setData(ClipboardData(text: text));

  @override
  Future<String?> getText() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    return data?.text;
  }
}

/// In-memory fake for tests — avoids the real clipboard platform channel,
/// which in some test/CI sandboxes never responds (it forwards to the host
/// OS pasteboard) and would otherwise hang widget tests indefinitely.
class InMemoryClipboardAdapter implements ClipboardAdapter {
  String? _value;

  @override
  Future<void> setText(String text) async {
    _value = text;
  }

  @override
  Future<String?> getText() async => _value;
}

/// Copies secrets to the clipboard and auto-clears them after a short
/// timeout, per GOALS_v2 §2.4.
///
/// This is the single place that touches the clipboard for secret values
/// so every copy-to-clipboard entry point (vault item detail, the
/// generator screen) gets the same hygiene guarantees rather than each
/// screen having to remember to wire up its own timer.
///
/// **Guard against clobbering**: the timeout callback only clears the
/// clipboard if it still contains exactly the value this service copied —
/// if the user copied something else in the meantime, that value is left
/// alone. This is checked by reading the clipboard back before clearing,
/// not by any assumption that nothing else touched it.
class ClipboardService {
  ClipboardService({
    ClipboardAdapter adapter = const FlutterClipboardAdapter(),
    Duration clearAfter = kDefaultClipboardClearTimeout,
  }) : _adapter = adapter,
       _clearAfter = clearAfter;

  final ClipboardAdapter _adapter;
  final Duration _clearAfter;

  Timer? _clearTimer;
  String? _lastCopiedValue;

  /// Copies [value] to the clipboard and schedules it to be cleared after
  /// the configured timeout, unless the clipboard has changed by then.
  Future<void> copySecret(String value) async {
    _clearTimer?.cancel();
    await _adapter.setText(value);
    _lastCopiedValue = value;
    _clearTimer = Timer(_clearAfter, () {
      unawaited(_clearIfUnchanged());
    });
  }

  /// Proactively clears the clipboard right now if it still holds the last
  /// value this service copied, without waiting for the timeout. Intended
  /// to be tied to the auto-lock event (GOALS_v2 §2.3 + §2.4 hardening) so
  /// locking the app doesn't leave a copied secret sitting in the clipboard
  /// for the rest of the timeout window.
  Future<void> clearNowIfHoldingSecret() async {
    _clearTimer?.cancel();
    _clearTimer = null;
    await _clearIfUnchanged();
  }

  Future<void> _clearIfUnchanged() async {
    final expected = _lastCopiedValue;
    if (expected == null) return;
    final current = await _adapter.getText();
    if (current == expected) {
      await _adapter.setText('');
    }
    _lastCopiedValue = null;
  }

  void dispose() {
    _clearTimer?.cancel();
  }
}
