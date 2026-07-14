// Widget test for the device management screen (GOALS_v2 §1.4), driven
// through the real app/router the same way
// test/presentation/vault/vault_crud_flow_test.dart drives vault screens,
// since the device management screen is gated behind signed-in-unlocked.
//
// Covers: this device is auto-registered and listed as trusted after
// sign-up, the "simulate new device" affordance lands a device pending
// approval, approving it promotes it to trusted, and revoking a device
// marks it revoked rather than removing it from the list.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
    'this device auto-registers as trusted and is shown on the device '
    'management screen',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: testProviderOverrides(),
          child: const PasswordManagerApp(),
        ),
      );
      await tester.pumpAndSettle();

      await _signUpAndReachHome(
        tester,
        email: 'device-user@example.com',
        masterSecret: 'a very strong secret',
      );

      await tester.tap(find.byKey(const Key('homeDevicesButton')));
      await tester.pumpAndSettle();

      expect(find.text('Registered devices'), findsOneWidget);
      // The signed-up device is the first for the account, so it's
      // auto-trusted rather than pending.
      expect(find.textContaining('Trusted'), findsOneWidget);
      expect(find.text('No devices registered yet.'), findsNothing);
    },
  );

  testWidgets(
    'simulating a new device shows it pending, and approving it promotes '
    'it to trusted',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: testProviderOverrides(),
          child: const PasswordManagerApp(),
        ),
      );
      await tester.pumpAndSettle();

      await _signUpAndReachHome(
        tester,
        email: 'approve-user@example.com',
        masterSecret: 'another strong secret',
      );

      await tester.tap(find.byKey(const Key('homeDevicesButton')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('deviceSimulateNewDeviceButton')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Pending approval'), findsOneWidget);
      expect(find.text('Simulated new device'), findsOneWidget);

      final approveButton = find.byWidgetPredicate(
        (widget) =>
            widget is TextButton &&
            widget.key.toString().contains('deviceApproveButton'),
      );
      expect(approveButton, findsOneWidget);

      await tester.tap(approveButton);
      await tester.pumpAndSettle();

      expect(find.textContaining('Pending approval'), findsNothing);
      // Two devices now, both trusted: this device + the approved one.
      expect(find.textContaining('Trusted'), findsNWidgets(2));
    },
  );

  testWidgets('revoking a device marks it revoked rather than removing it', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: testProviderOverrides(),
        child: const PasswordManagerApp(),
      ),
    );
    await tester.pumpAndSettle();

    await _signUpAndReachHome(
      tester,
      email: 'revoke-user@example.com',
      masterSecret: 'yet another secret',
    );

    await tester.tap(find.byKey(const Key('homeDevicesButton')));
    await tester.pumpAndSettle();

    final revokeButton = find.byWidgetPredicate(
      (widget) =>
          widget is TextButton &&
          widget.key.toString().contains('deviceRevokeButton'),
    );
    expect(revokeButton, findsOneWidget);

    await tester.tap(revokeButton);
    await tester.pumpAndSettle();

    expect(find.textContaining('Revoked'), findsOneWidget);
    // The device entry is still shown (not deleted), and no longer offers
    // a revoke action.
    expect(revokeButton, findsNothing);
  });
}
