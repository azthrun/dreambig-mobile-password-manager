// Smoke test proving the app boots: DI container, router, theming, and
// localization all wire together. Phase 1 gates the app behind
// authentication, so the very first screen a signed-out user sees is now
// Sign In rather than the vault home screen.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/presentation/app/app.dart';

import 'support/test_providers.dart';

void main() {
  testWidgets('App boots and shows the sign-in screen when signed out', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: testProviderOverrides(),
        child: const PasswordManagerApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsWidgets);
    expect(find.byKey(const Key('signInEmailField')), findsOneWidget);
  });
}
