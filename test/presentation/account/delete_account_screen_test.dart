// Widget tests for the account-deletion screen (GOALS_v2 §1.7), driven
// through the real app/router the same way
// test/presentation/devices/device_management_screen_test.dart drives the
// device management screen.
//
// Covers: the irreversibility warning is shown up front, the submit button
// stays disabled until acknowledgement + re-auth + type-to-confirm are all
// satisfied, a wrong master secret is rejected without deleting anything,
// and a fully-correct submission signs the user out back to sign-in.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/presentation/app/app.dart';

import '../../support/test_providers.dart';

const String _kEmail = 'delete-ui@example.com';
const String _kMasterSecret = 'a very strong secret';

Future<void> _signUpAndReachHome(WidgetTester tester) async {
  await tester.tap(find.text('Need an account? Create one'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('signUpEmailField')), _kEmail);
  await tester.enterText(
    find.byKey(const Key('signUpMasterSecretField')),
    _kMasterSecret,
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

Future<void> _openDeleteAccountScreen(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('homeAccountButton')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('accountDeleteAccountButton')));
  await tester.pumpAndSettle();
}

/// Taps [key] after scrolling it into view, since this form is tall enough
/// to overflow the default (800x600) test viewport.
Future<void> _tapVisible(WidgetTester tester, Key key) async {
  final finder = find.byKey(key);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
}

void main() {
  testWidgets(
    'shows the irreversibility warning up front, before any input is given',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: testProviderOverrides(),
          child: const PasswordManagerApp(),
        ),
      );
      await tester.pumpAndSettle();

      await _signUpAndReachHome(tester);
      await _openDeleteAccountScreen(tester);

      expect(find.byKey(const Key('deleteAccountWarningText')), findsOneWidget);
      expect(
        find.textContaining('permanent and cannot be undone'),
        findsWidgets,
      );
    },
  );

  testWidgets(
    'the submit button stays disabled until acknowledgement + master '
    'secret + exact type-to-confirm text are all provided',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: testProviderOverrides(),
          child: const PasswordManagerApp(),
        ),
      );
      await tester.pumpAndSettle();

      await _signUpAndReachHome(tester);
      await _openDeleteAccountScreen(tester);

      FilledButton submitButton() => tester.widget<FilledButton>(
        find.byKey(const Key('deleteAccountSubmitButton')),
      );

      // Nothing filled in yet: disabled.
      expect(submitButton().onPressed, isNull);

      // Only the checkbox: still disabled.
      await _tapVisible(tester, const Key('deleteAccountAcknowledgeCheckbox'));
      await tester.pump();
      expect(submitButton().onPressed, isNull);

      // + master secret: still disabled (no type-to-confirm yet).
      await tester.enterText(
        find.byKey(const Key('deleteAccountMasterSecretField')),
        _kMasterSecret,
      );
      await tester.pump();
      expect(submitButton().onPressed, isNull);

      // Wrong confirmation text: still disabled.
      await tester.enterText(
        find.byKey(const Key('deleteAccountConfirmTextField')),
        'delete',
      );
      await tester.pump();
      expect(submitButton().onPressed, isNull);

      // The exact literal "DELETE": now enabled.
      await tester.enterText(
        find.byKey(const Key('deleteAccountConfirmTextField')),
        'DELETE',
      );
      await tester.pump();
      expect(submitButton().onPressed, isNotNull);
    },
  );

  testWidgets(
    'a wrong master secret is rejected and the account is not deleted',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: testProviderOverrides(),
          child: const PasswordManagerApp(),
        ),
      );
      await tester.pumpAndSettle();

      await _signUpAndReachHome(tester);
      await _openDeleteAccountScreen(tester);

      await _tapVisible(
        tester,
        const Key('deleteAccountAcknowledgeCheckbox'),
      );
      await tester.enterText(
        find.byKey(const Key('deleteAccountMasterSecretField')),
        'the wrong secret entirely',
      );
      await tester.enterText(
        find.byKey(const Key('deleteAccountConfirmTextField')),
        'DELETE',
      );
      await tester.pump();

      await _tapVisible(tester, const Key('deleteAccountSubmitButton'));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.byKey(const Key('deleteAccountErrorText')), findsOneWidget);
      // Still on the delete-account screen, not bounced to sign-in.
      expect(find.byKey(const Key('deleteAccountSubmitButton')), findsOneWidget);
    },
  );

  testWidgets(
    'a fully-correct submission deletes the account and forces sign-out '
    'to the sign-in screen',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: testProviderOverrides(),
          child: const PasswordManagerApp(),
        ),
      );
      await tester.pumpAndSettle();

      await _signUpAndReachHome(tester);
      await _openDeleteAccountScreen(tester);

      await _tapVisible(
        tester,
        const Key('deleteAccountAcknowledgeCheckbox'),
      );
      await tester.enterText(
        find.byKey(const Key('deleteAccountMasterSecretField')),
        _kMasterSecret,
      );
      await tester.enterText(
        find.byKey(const Key('deleteAccountConfirmTextField')),
        'DELETE',
      );
      await tester.pump();

      await _tapVisible(tester, const Key('deleteAccountSubmitButton'));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Router redirect bounced us all the way back to sign-in.
      expect(find.byKey(const Key('signInSubmitButton')), findsOneWidget);
    },
  );
}
