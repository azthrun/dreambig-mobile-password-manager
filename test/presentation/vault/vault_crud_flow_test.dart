// Widget tests for the vault list + create/edit flow (GOALS_v2 §1.1),
// driven through the real app/router the same way
// test/presentation/auth/sign_up_sign_in_flow_test.dart drives the auth
// flow, since vault screens are gated behind signed-in-unlocked.

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
  await tester.enterText(
    find.byKey(const Key('signUpEmailField')),
    email,
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

Future<void> _tapSaveButton(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('vaultFormSaveButton')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('vault list starts empty, then shows a created item', (
    WidgetTester tester,
  ) async {
    // The Phase 3 strength indicator adds height under the item form's
    // secret field once it's non-empty, which can push the save button
    // below the fold of the default 800x600 test surface — use a taller
    // surface so the whole form fits without needing to scroll mid-test.
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
      email: 'vault-user@example.com',
      masterSecret: 'a very strong secret',
    );

    // No items yet.
    expect(find.text('No items yet. Tap + to add your first password.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('homeAddItemButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('vaultFormIdentifierField')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('vaultFormIdentifierField')),
      'alice@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('vaultFormSecretField')),
      'hunter2',
    );
    await tester.enterText(
      find.byKey(const Key('vaultFormSiteNameField')),
      'Example Site',
    );

    await _tapSaveButton(tester);

    // Back on the vault home screen, the new item shows up.
    expect(find.text('Example Site'), findsOneWidget);
    expect(find.text('alice@example.com'), findsOneWidget);
  });

  testWidgets('editing an item updates the list and keeps revision history', (
    WidgetTester tester,
  ) async {
    // The Phase 3 strength indicator adds height under the item form's
    // secret field once it's non-empty, which can push the save button
    // below the fold of the default 800x600 test surface — use a taller
    // surface so the whole form fits without needing to scroll mid-test.
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
      email: 'edit-user@example.com',
      masterSecret: 'another strong secret',
    );

    await tester.tap(find.byKey(const Key('homeAddItemButton')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('vaultFormIdentifierField')),
      'bob@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('vaultFormSecretField')),
      'first-secret',
    );
    await tester.enterText(
      find.byKey(const Key('vaultFormSiteNameField')),
      'Editable Site',
    );
    await _tapSaveButton(tester);

    expect(find.text('Editable Site'), findsOneWidget);

    // Open the item detail screen.
    await tester.tap(find.text('Editable Site'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('vaultDetailEditButton')), findsOneWidget);
    // No prior revisions yet.
    expect(find.text('No previous versions yet.'), findsOneWidget);

    // Edit it.
    await tester.tap(find.byKey(const Key('vaultDetailEditButton')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('vaultFormSecretField')),
      'second-secret',
    );
    await _tapSaveButton(tester);

    // Back on detail, a revision now exists.
    expect(find.textContaining('Saved '), findsOneWidget);
    expect(find.text('Restore this version'), findsOneWidget);
  });

  testWidgets('deleting an item moves it to trash, where it can be restored', (
    WidgetTester tester,
  ) async {
    // The Phase 3 strength indicator adds height under the item form's
    // secret field once it's non-empty, which can push the save button
    // below the fold of the default 800x600 test surface — use a taller
    // surface so the whole form fits without needing to scroll mid-test.
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
      email: 'trash-user@example.com',
      masterSecret: 'yet another secret',
    );

    await tester.tap(find.byKey(const Key('homeAddItemButton')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('vaultFormIdentifierField')),
      'carol@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('vaultFormSecretField')),
      'secret',
    );
    await tester.enterText(
      find.byKey(const Key('vaultFormSiteNameField')),
      'Trashable Site',
    );
    await _tapSaveButton(tester);

    await tester.tap(find.text('Trashable Site'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('vaultDetailDeleteButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('vaultDetailConfirmDeleteButton')));
    await tester.pumpAndSettle();

    // Back on the vault home screen, the item is gone from the active list.
    expect(find.text('Trashable Site'), findsNothing);
    expect(find.text('No items yet. Tap + to add your first password.'), findsOneWidget);

    // It's in trash.
    await tester.tap(find.byKey(const Key('homeTrashButton')));
    await tester.pumpAndSettle();
    expect(find.text('Trashable Site'), findsOneWidget);
    expect(find.text('Restore'), findsOneWidget);

    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();

    expect(find.text('Trash is empty.'), findsOneWidget);
  });
}
