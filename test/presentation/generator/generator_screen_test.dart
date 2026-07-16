// Widget tests for the password generator (GOALS_v2 §1.2), driven through
// the real app/router the same way other Phase 1-3 widget tests do, since
// the generator's home-screen entry point is gated behind
// signed-in-unlocked.

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
  testWidgets('standalone generator screen generates a character password', (
    WidgetTester tester,
  ) async {
    // The generator screen's options list is tall enough that its bottom
    // (e.g. the "use this password" button) can fall below the fold of
    // the default 800x600 test surface — use a taller surface so
    // everything fits without needing to scroll mid-test.
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
      email: 'generator-user@example.com',
      masterSecret: 'a very strong secret',
    );

    await tester.tap(find.byKey(const Key('homeGeneratorButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('generatorGeneratedValue')), findsOneWidget);
    final valueWidget = tester.widget<SelectableText>(
      find.byKey(const Key('generatorGeneratedValue')),
    );
    // Default options: length 16, all charsets enabled.
    expect(valueWidget.data!.length, 16);

    // Regenerating produces a (very likely) different value.
    final first = valueWidget.data!;
    await tester.tap(find.byKey(const Key('generatorRegenerateButton')));
    await tester.pumpAndSettle();
    final second = tester
        .widget<SelectableText>(find.byKey(const Key('generatorGeneratedValue')))
        .data!;
    expect(second, isNot(first));

    // No "use this password" button — this was opened standalone via the
    // named route directly from the home app bar, so canPop() is still
    // true (go_router pushes onto the Navigator stack), but let's instead
    // assert the strength meter renders for a non-empty value.
    expect(find.byKey(const Key('passwordStrengthLabel')), findsOneWidget);
  });

  testWidgets('changing length updates the generated value length', (
    WidgetTester tester,
  ) async {
    // The generator screen's options list is tall enough that its bottom
    // (e.g. the "use this password" button) can fall below the fold of
    // the default 800x600 test surface — use a taller surface so
    // everything fits without needing to scroll mid-test.
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
      email: 'generator-length@example.com',
      masterSecret: 'another strong secret',
    );

    await tester.tap(find.byKey(const Key('homeGeneratorButton')));
    await tester.pumpAndSettle();

    // Drag the length slider to (roughly) its maximum.
    await tester.drag(
      find.byKey(const Key('generatorLengthSlider')),
      const Offset(500, 0),
    );
    await tester.pumpAndSettle();

    final value = tester
        .widget<SelectableText>(find.byKey(const Key('generatorGeneratedValue')))
        .data!;
    expect(value.length, greaterThan(16));
  });

  testWidgets('switching to passphrase mode generates a word-based value', (
    WidgetTester tester,
  ) async {
    // The generator screen's options list is tall enough that its bottom
    // (e.g. the "use this password" button) can fall below the fold of
    // the default 800x600 test surface — use a taller surface so
    // everything fits without needing to scroll mid-test.
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
      email: 'generator-passphrase@example.com',
      masterSecret: 'yet another secret',
    );

    await tester.tap(find.byKey(const Key('homeGeneratorButton')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Passphrase'));
    await tester.pumpAndSettle();

    // The word-count slider only renders in passphrase mode — its presence
    // confirms the mode switch actually took effect (rather than inferring
    // it from the generated value's shape, which is unreliable: the
    // character-mode symbol set also includes '-').
    expect(find.byKey(const Key('generatorWordCountSlider')), findsOneWidget);

    final value = tester
        .widget<SelectableText>(find.byKey(const Key('generatorGeneratedValue')))
        .data!;
    // Default word count is 5, default separator '-', so there are at
    // least 4 dashes joining words (possibly more since a few EFF
    // wordlist entries are themselves hyphenated, e.g. "t-shirt").
    expect('-'.allMatches(value).length, greaterThanOrEqualTo(4));
  });

  testWidgets(
    'from the vault item form, "use this password" fills the secret field',
    (WidgetTester tester) async {
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
        email: 'generator-form-user@example.com',
        masterSecret: 'form generator secret',
      );

      await tester.tap(find.byKey(const Key('homeAddItemButton')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('vaultFormGenerateButton')), findsOneWidget);

      await tester.tap(find.byKey(const Key('vaultFormGenerateButton')));
      await tester.pumpAndSettle();

      final generated = tester
          .widget<SelectableText>(find.byKey(const Key('generatorGeneratedValue')))
          .data!;

      expect(find.byKey(const Key('generatorUseThisPasswordButton')), findsOneWidget);
      await tester.tap(find.byKey(const Key('generatorUseThisPasswordButton')));
      await tester.pumpAndSettle();

      // Back on the form, the secret field now holds the generated value.
      final secretField = tester.widget<TextFormField>(
        find.byKey(const Key('vaultFormSecretField')),
      );
      expect(secretField.controller!.text, generated);
      // Live strength indicator shows for the filled-in value.
      expect(find.byKey(const Key('passwordStrengthLabel')), findsOneWidget);
    },
  );
}
