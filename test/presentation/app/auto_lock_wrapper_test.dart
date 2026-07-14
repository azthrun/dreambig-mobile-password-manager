// Widget tests for the Phase 6 hardening tied to `AutoLockWrapper`'s
// existing lock/unlock lifecycle hook (GOALS_v2 §2.4, §2.5):
//  - `FLAG_SECURE` (via `SecureScreenService`) is enabled while the vault is
//    unlocked and disabled once it locks.
//  - Locking proactively clears the clipboard if it still holds a secret
//    this session copied, instead of only relying on the auto-clear timer.
//
// Driven through the real app/router the same way
// test/presentation/vault/vault_crud_flow_test.dart drives the vault flow,
// since both behaviors are only observable through a real sign-in ->
// unlocked -> lock transition.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/data/clipboard/clipboard_service.dart';
import 'package:password_manager/data/security/secure_screen_service.dart';
import 'package:password_manager/presentation/app/app.dart';

import '../../support/test_providers.dart';

Future<void> _signUpAndReachHome(
  WidgetTester tester, {
  required String email,
  required String masterSecret,
}) async {
  await tester.tap(find.text('Need an account? Create one'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('signUpEmailField')), email);
  await tester.enterText(
    find.byKey(const Key('signUpMasterSecretField')),
    masterSecret,
  );
  await tester.tap(find.byKey(const Key('signUpContinueButton')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('recoveryModeChooseLocalButton')));
  await tester.pumpAndSettle(const Duration(seconds: 2));
  await tester.enterText(
    find.byKey(const Key('confirmEmailCodeField')),
    '123456',
  );
  await tester.tap(find.byKey(const Key('confirmEmailSubmitButton')));
  await tester.pumpAndSettle();
  expect(find.text('Welcome to your vault'), findsOneWidget);
}

void main() {
  testWidgets(
    'FLAG_SECURE is enabled on unlock and disabled on lock',
    (tester) async {
      final secureChannel = FakeSecureScreenChannel();

      await tester.pumpWidget(
        ProviderScope(
          overrides: testProviderOverrides(
            secureScreenService: SecureScreenService(channel: secureChannel),
          ),
          child: const PasswordManagerApp(),
        ),
      );
      await tester.pumpAndSettle();

      // Signed-out (sign-in screen): never toggled on yet.
      expect(secureChannel.calls, isEmpty);

      await _signUpAndReachHome(
        tester,
        email: 'secure-screen-user@example.com',
        masterSecret: 'a very strong secret',
      );

      // Unlocking turned FLAG_SECURE on.
      expect(secureChannel.lastSecureValue, true);

      await tester.tap(find.byKey(const Key('homeLockButton')));
      await tester.pumpAndSettle();

      // Locking turned it back off.
      expect(secureChannel.lastSecureValue, false);
      expect(secureChannel.calls, containsAllInOrder(<bool>[true, false]));
    },
  );

  testWidgets(
    'FLAG_SECURE stays on while backgrounded-and-locked, and only clears '
    'once resumed (regression test for the Recents-snapshot race)',
    (tester) async {
      final secureChannel = FakeSecureScreenChannel();

      await tester.pumpWidget(
        ProviderScope(
          overrides: testProviderOverrides(
            secureScreenService: SecureScreenService(channel: secureChannel),
          ),
          child: const PasswordManagerApp(),
        ),
      );
      await tester.pumpAndSettle();

      await _signUpAndReachHome(
        tester,
        email: 'background-race-user@example.com',
        masterSecret: 'a very strong secret',
      );

      // Unlocked and foregrounded: FLAG_SECURE is on.
      expect(secureChannel.lastSecureValue, true);
      secureChannel.calls.clear();

      // Simulate the app being backgrounded (e.g. app-switcher/Recents),
      // which locks the session via AutoLockWrapper's lifecycle observer.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();

      // Backgrounding-triggered lock must NOT clear FLAG_SECURE while still
      // backgrounded — otherwise the last unlocked frame could be captured
      // in the OS's task snapshot before FLAG_SECURE is reasserted.
      expect(
        secureChannel.calls,
        isNot(contains(false)),
        reason:
            'FLAG_SECURE must stay enabled while the app is locked and '
            'backgrounded, to protect the Recents/Overview snapshot.',
      );
      expect(secureChannel.lastSecureValue, true);

      // Now simulate returning to the foreground while still locked (the
      // lock screen, which never shows secrets, is what's about to render).
      tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      );
      await tester.pumpAndSettle();

      // Only now is it safe to drop FLAG_SECURE.
      expect(secureChannel.lastSecureValue, false);
    },
  );

  testWidgets(
    'locking the app clears a copied secret out of the clipboard',
    (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final clipboardAdapter = InMemoryClipboardAdapter();
      final clipboardService = ClipboardService(
        adapter: clipboardAdapter,
        // Long enough that the timeout itself never fires during this
        // test — only the explicit lock-triggered clear should run.
        clearAfter: const Duration(minutes: 5),
      );
      addTearDown(clipboardService.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: testProviderOverrides(clipboardService: clipboardService),
          child: const PasswordManagerApp(),
        ),
      );
      await tester.pumpAndSettle();

      await _signUpAndReachHome(
        tester,
        email: 'clipboard-lock-user@example.com',
        masterSecret: 'another strong secret',
      );

      await tester.tap(find.byKey(const Key('homeAddItemButton')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('vaultFormIdentifierField')),
        'alice@example.com',
      );
      await tester.enterText(
        find.byKey(const Key('vaultFormSecretField')),
        'copy-me-secret',
      );
      await tester.enterText(
        find.byKey(const Key('vaultFormSiteNameField')),
        'Clipboard Site',
      );
      await tester.tap(find.byKey(const Key('vaultFormSaveButton')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Clipboard Site'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('vaultDetailCopySecretButton')));
      await tester.pumpAndSettle();

      expect(await clipboardAdapter.getText(), 'copy-me-secret');

      // Navigate back to home to reach the lock button, then lock.
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('homeLockButton')));
      await tester.pumpAndSettle();

      // Locking should have proactively cleared the clipboard rather than
      // leaving the secret sitting there for the rest of the (long) timeout.
      expect(await clipboardAdapter.getText(), '');
    },
  );
}
