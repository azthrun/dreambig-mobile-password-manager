// End-to-end widget tests for the basic sign-up and sign-in flows against
// the app's real router (redirect-driven, GOALS_v2 §1.3): entering
// credentials, picking a recovery mode, confirming email, landing on the
// vault home screen, then locking and signing back in.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/presentation/app/app.dart';

import '../../support/test_providers.dart';

void main() {
  testWidgets('full sign-up flow: credentials -> recovery mode -> confirm -> home', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: testProviderOverrides(),
        child: const PasswordManagerApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Starts on Sign In; navigate to Sign Up.
    await tester.tap(find.text('Need an account? Create one'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('signUpEmailField')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('signUpEmailField')),
      'new-user@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('signUpAccountPasswordField')),
      'test account password',
    );
    await tester.enterText(
      find.byKey(const Key('signUpMasterSecretField')),
      'correct horse battery staple',
    );
    await tester.tap(find.byKey(const Key('signUpContinueButton')));
    await tester.pumpAndSettle();

    // Recovery-mode choice must appear before the account exists.
    expect(find.text('Choose your recovery mode'), findsOneWidget);
    expect(find.text('Local-only'), findsOneWidget);
    expect(find.text('Remote backup'), findsOneWidget);

    await tester.tap(find.byKey(const Key('recoveryModeChooseLocalButton')));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Email confirmation gate.
    expect(find.byKey(const Key('confirmEmailCodeField')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('confirmEmailCodeField')),
      '123456',
    );
    await tester.tap(find.byKey(const Key('confirmEmailSubmitButton')));
    await tester.pumpAndSettle();

    // Lands on the vault home screen, unlocked.
    expect(find.text('Welcome to your vault'), findsOneWidget);
  });

  testWidgets(
    'recovery-mode step can go back to sign-up with values prefilled, and '
    'sign-up rejects a master secret equal to the account password',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: testProviderOverrides(),
          child: const PasswordManagerApp(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Need an account? Create one'));
      await tester.pumpAndSettle();

      // Master secret identical to the account password is rejected.
      await tester.enterText(
        find.byKey(const Key('signUpEmailField')),
        'second-thoughts@example.com',
      );
      await tester.enterText(
        find.byKey(const Key('signUpAccountPasswordField')),
        'test account password',
      );
      await tester.enterText(
        find.byKey(const Key('signUpMasterSecretField')),
        'test account password',
      );
      await tester.tap(find.byKey(const Key('signUpContinueButton')));
      await tester.pumpAndSettle();
      expect(
        find.text('Master secret must be different from your account password'),
        findsOneWidget,
      );

      // Fix the master secret and continue to the recovery-mode step.
      await tester.enterText(
        find.byKey(const Key('signUpMasterSecretField')),
        'correct horse battery staple',
      );
      await tester.tap(find.byKey(const Key('signUpContinueButton')));
      await tester.pumpAndSettle();
      expect(find.text('Choose your recovery mode'), findsOneWidget);

      // Change of heart before confirming: back returns to sign-up with
      // everything still filled in.
      await tester.tap(find.byKey(const Key('recoveryModeBackButton')));
      await tester.pumpAndSettle();
      expect(find.text('second-thoughts@example.com'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const Key('signUpMasterSecretField')),
            )
            .controller
            ?.text,
        'correct horse battery staple',
      );
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const Key('signUpAccountPasswordField')),
            )
            .controller
            ?.text,
        'test account password',
      );
    },
  );

  testWidgets('sign-in flow: valid credentials reach the home screen', (
    WidgetTester tester,
  ) async {
    // First create+confirm an account via the app itself, then sign out and
    // sign back in with the same credentials to prove sign-in derives a
    // matching auth key independently.
    await tester.pumpWidget(
      ProviderScope(
        overrides: testProviderOverrides(),
        child: const PasswordManagerApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Need an account? Create one'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('signUpEmailField')),
      'returning-user@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('signUpAccountPasswordField')),
      'test account password',
    );
    await tester.enterText(
      find.byKey(const Key('signUpMasterSecretField')),
      'another master secret',
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

    // Sign out, then sign back in.
    await tester.tap(find.byKey(const Key('homeSignOutButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('signInEmailField')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('signInEmailField')),
      'returning-user@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('signInAccountPasswordField')),
      'test account password',
    );
    await tester.enterText(
      find.byKey(const Key('signInMasterSecretField')),
      'another master secret',
    );
    await tester.tap(find.byKey(const Key('signInSubmitButton')));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.text('Welcome to your vault'), findsOneWidget);
  });
}
