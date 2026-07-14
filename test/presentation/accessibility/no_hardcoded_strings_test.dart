// Regression guard for the "no hardcoded strings" convention (AGENTS.md,
// GOALS_v2 §3.4). This is deliberately a lightweight, targeted source scan
// over a curated set of representative widget files — not a general lint —
// per the Phase 9 brief: a full automated hardcoded-string linter is out of
// scope, but a couple of representative files should stay clean so a future
// change can't silently reintroduce a `Text('Some literal')` that bypasses
// `AppLocalizations`.
//
// The heuristic: within `Text(` / `tooltip:` / `labelText:` call sites, a
// string literal that starts with an uppercase letter (i.e. looks like
// English UI copy, not a `'$variable'` interpolation, a key string, or an
// empty string) is almost certainly hardcoded copy that should have come
// from `l10n.*` instead.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final RegExp _suspectLiteral = RegExp(
  r"""(?:Text|tooltip|labelText|semanticLabel)\s*:?\s*\(?\s*'[A-Z][a-zA-Z ,.!?]{2,}'""",
);

void main() {
  test('representative screens contain no hardcoded English UI copy', () {
    // A cross-section of screens touched across multiple phases (auth,
    // vault, generator, devices, security) — enough to catch a regression
    // without this test becoming a full-repo linter.
    const files = <String>[
      'lib/presentation/auth/lock_screen.dart',
      'lib/presentation/auth/sign_in_screen.dart',
      'lib/presentation/auth/recovery_mode_screen.dart',
      'lib/presentation/vault/vault_item_detail_screen.dart',
      'lib/presentation/vault/vault_trash_screen.dart',
      'lib/presentation/generator/password_strength_indicator.dart',
      'lib/presentation/devices/device_management_screen.dart',
      'lib/presentation/security/compromised_device_screen.dart',
      'lib/presentation/account/delete_account_screen.dart',
    ];

    for (final path in files) {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: '$path should exist');
      final contents = file.readAsStringSync();
      final matches = _suspectLiteral.allMatches(contents).map((m) => m.group(0)).toList();
      expect(
        matches,
        isEmpty,
        reason:
            'Found what looks like hardcoded English UI copy in $path: '
            '$matches — route it through AppLocalizations (lib/l10n/app_en.arb) instead.',
      );
    }
  });
}
