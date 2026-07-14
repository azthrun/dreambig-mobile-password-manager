// Widget tests for the recovery-mode choice screen (GOALS_v2 §1.3, decision
// #3): both options' consequence statements must be present and visible
// side-by-side (or equivalent comparative layout), shown up front before
// account/vault creation.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/l10n/generated/app_localizations.dart';
import 'package:password_manager/presentation/auth/auth_controller.dart';
import 'package:password_manager/presentation/auth/recovery_mode_screen.dart';

import '../../support/test_providers.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );
  }

  testWidgets(
    'shows both recovery-mode options with their full consequence text',
    (WidgetTester tester) async {
      final container = ProviderContainer(overrides: testProviderOverrides());
      addTearDown(container.dispose);

      // A recovery-mode choice only makes sense mid-signup; stage a pending
      // sign-up the way SignUpScreen would before navigating here.
      container
          .read(authControllerProvider.notifier)
          .beginSignUp(
            email: 'user@example.com',
            masterSecret: 'correct horse battery staple',
          );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: wrap(const RecoveryModeScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Local-only option and its exact consequence statement.
      expect(find.text('Local-only'), findsOneWidget);
      expect(
        find.textContaining('permanent, total data loss'),
        findsOneWidget,
      );
      expect(
        find.textContaining('cannot sync to another device'),
        findsOneWidget,
      );
      expect(
        find.textContaining('lost if you uninstall the app or wipe the device'),
        findsOneWidget,
      );

      // Remote-backup option and its exact consequence statement.
      expect(find.text('Remote backup'), findsOneWidget);
      expect(
        find.textContaining('zero-knowledge'),
        findsOneWidget,
      );
      expect(
        find.textContaining('cannot recover a forgotten master secret'),
        findsOneWidget,
      );
      expect(
        find.textContaining('does leave this device, as ciphertext'),
        findsOneWidget,
      );

      // Both option cards are simultaneously visible (comparative layout),
      // not one disclaimer read in isolation.
      expect(find.byKey(const Key('recoveryModeLocalCard')), findsOneWidget);
      expect(find.byKey(const Key('recoveryModeRemoteCard')), findsOneWidget);
    },
  );

  testWidgets(
    'choosing local-only completes sign-up and requires email confirmation',
    (WidgetTester tester) async {
      final container = ProviderContainer(overrides: testProviderOverrides());
      addTearDown(container.dispose);

      container
          .read(authControllerProvider.notifier)
          .beginSignUp(
            email: 'user@example.com',
            masterSecret: 'correct horse battery staple',
          );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: wrap(const RecoveryModeScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('recoveryModeChooseLocalButton')),
      );
      // Argon2id derivation + fake sign-up round trip.
      await tester.pumpAndSettle(const Duration(seconds: 2));

      final state = container.read(authControllerProvider);
      expect(state.needsEmailConfirmation, isTrue);
      expect(state.email, 'user@example.com');
    },
  );
}
