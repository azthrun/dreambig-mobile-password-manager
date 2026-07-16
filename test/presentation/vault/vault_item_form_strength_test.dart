// Widget test for the live strength indicator on the vault item form's
// secret field (GOALS_v2 §1.2, item 3: "shown at generation and entry
// time" — this covers the manual-entry half of that requirement; the
// generator half is covered by test/presentation/generator/generator_screen_test.dart).

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
    find.byKey(const Key('signUpAccountPasswordField')),
    'test account password',
  );
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
  testWidgets('typing a manual secret shows a live strength indicator', (
    WidgetTester tester,
  ) async {
    // The strength indicator adds height under the secret field once it's
    // non-empty, which can push content below the fold of the default
    // 800x600 test surface — use a taller surface so everything fits.
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: testProviderOverrides(),
        child: const PasswordManagerApp(),
      ),
    );
    await tester.pumpAndSettle();

    await _signUpAndReachHome(
      tester,
      email: 'strength-form-user@example.com',
      masterSecret: 'strength form secret',
    );

    await tester.tap(find.byKey(const Key('homeAddItemButton')));
    await tester.pumpAndSettle();

    // No secret yet — no strength indicator.
    expect(find.byKey(const Key('passwordStrengthLabel')), findsNothing);

    // A known-weak password.
    await tester.enterText(
      find.byKey(const Key('vaultFormSecretField')),
      'password',
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('passwordStrengthLabel')), findsOneWidget);
    expect(find.text('Strength: Very weak'), findsOneWidget);
    expect(find.byKey(const Key('passwordStrengthCommonWarning')), findsOneWidget);

    // A long, varied password should score meaningfully higher.
    await tester.enterText(
      find.byKey(const Key('vaultFormSecretField')),
      r'xQ7$mZ2#vT9@pL4!kR8^',
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('passwordStrengthCommonWarning')), findsNothing);
    expect(find.text('Strength: Very weak'), findsNothing);
  });
}
