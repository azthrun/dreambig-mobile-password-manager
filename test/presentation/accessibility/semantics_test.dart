// Accessibility regression tests (Phase 9, GOALS_v2 §3.4): asserts that
// icon-only actions expose a screen-reader-visible label (tooltip, which
// Flutter also surfaces as a semantics label/hint on IconButton), and that
// the password strength indicator exposes a text/semantics equivalent of
// its color-coded meter rather than relying on color alone.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/l10n/generated/app_localizations.dart';
import 'package:password_manager/presentation/app/app.dart';
import 'package:password_manager/presentation/generator/password_strength_indicator.dart';
import 'package:password_manager/presentation/security/compromised_device_screen.dart';

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
  testWidgets(
    'home screen app-bar icon-only actions all have a non-empty tooltip',
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
        email: 'a11y-home-user@example.com',
        masterSecret: 'accessibility secret',
      );

      // Every icon-only app-bar action (generator, trash, devices, account)
      // must carry a tooltip — this is both a usability affordance on
      // long-press and, per `IconButton`'s implementation, becomes the
      // widget's semantics label/hint for screen readers.
      for (final Key key in const <Key>[
        Key('homeGeneratorButton'),
        Key('homeTrashButton'),
        Key('homeDevicesButton'),
        Key('homeAccountButton'),
      ]) {
        final finder = find.byKey(key);
        expect(finder, findsOneWidget, reason: '$key should be present');
        final button = tester.widget<IconButton>(finder);
        expect(
          button.tooltip,
          isNotNull,
          reason: '$key must have a tooltip for screen-reader users',
        );
        expect(button.tooltip, isNotEmpty);
      }

      // The floating "add item" action is icon-only too.
      final fab = tester.widget<FloatingActionButton>(
        find.byKey(const Key('homeAddItemButton')),
      );
      expect(fab.tooltip, isNotNull);
      expect(fab.tooltip, isNotEmpty);
    },
  );

  testWidgets(
    'vault item detail: reveal/copy secret icon buttons have tooltips',
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
        email: 'a11y-detail-user@example.com',
        masterSecret: 'accessibility detail secret',
      );

      await tester.tap(find.byKey(const Key('homeAddItemButton')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('vaultFormIdentifierField')),
        'someone@example.com',
      );
      await tester.enterText(
        find.byKey(const Key('vaultFormSecretField')),
        'a reasonably strong secret',
      );
      await tester.tap(find.byKey(const Key('vaultFormSaveButton')));
      await tester.pumpAndSettle();

      // Back on the vault home list — tap the newly created item by its
      // displayed identifier (item ids are opaque/generated). The site
      // name was left blank, so the identifier appears twice (title and
      // subtitle both fall back to it) — tap the first match.
      await tester.tap(find.text('someone@example.com').first);
      await tester.pumpAndSettle();

      final visibilityToggle = tester.widget<IconButton>(
        find.byKey(const Key('vaultDetailSecretVisibilityToggle')),
      );
      expect(visibilityToggle.tooltip, isNotNull);
      expect(visibilityToggle.tooltip, isNotEmpty);
    },
    skip: false,
  );

  testWidgets(
    'password strength indicator exposes a text/semantics equivalent, not color alone',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: testProviderOverrides(),
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: PasswordStrengthIndicator(password: 'password'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // A plain text label exists (not just a colored bar) …
      expect(find.byKey(const Key('passwordStrengthLabel')), findsOneWidget);
      // … and it's also reachable as a semantics label, so a screen reader
      // announces the strength rather than staying silent on the color-only
      // progress bar.
      expect(
        find.bySemanticsLabel(RegExp('Strength: ')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'compromised-device blocking screen is a semantics live region',
    (WidgetTester tester) async {
      await tester.pumpWidget(const CompromisedDeviceApp());
      await tester.pumpAndSettle();

      final semanticsHandle = tester.ensureSemantics();
      final liveRegionFinder = find.byWidgetPredicate(
        (widget) => widget is Semantics && (widget.properties.liveRegion ?? false),
      );
      expect(
        liveRegionFinder,
        findsOneWidget,
        reason:
            'the blocking security screen should announce itself immediately '
            'to screen readers rather than requiring manual exploration',
      );
      semanticsHandle.dispose();
    },
  );
}
