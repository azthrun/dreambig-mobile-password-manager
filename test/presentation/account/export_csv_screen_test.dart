// Widget tests for the CSV export screen (GOALS_v2 §3.3), driven through the
// real app/router, mirroring delete_account_screen_test.dart's approach.
//
// Covers: the plaintext-on-disk warning is shown up front, re-auth is
// required (wrong master secret is rejected and nothing is exported), and a
// correct submission exports only active (non-trashed) items with the right
// CSV content.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/data/export/vault_csv_exporter.dart';
import 'package:password_manager/domain/models/credential_data.dart';
import 'package:password_manager/presentation/app/app.dart';
import 'package:password_manager/presentation/app/providers.dart';

import '../../support/test_providers.dart';

const String _kEmail = 'export-ui@example.com';
const String _kMasterSecret = 'a very strong secret';

Future<void> _signUpAndReachHome(WidgetTester tester) async {
  await tester.tap(find.text('Need an account? Create one'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('signUpEmailField')), _kEmail);
  await tester.enterText(
    find.byKey(const Key('signUpAccountPasswordField')),
    'test account password',
  );
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

Future<void> _openExportScreen(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('homeAccountButton')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('accountExportCsvButton')));
  await tester.pumpAndSettle();
}

/// Taps [key] after scrolling it into view, since some of these forms are
/// tall enough to overflow the default (800x600) test viewport.
Future<void> _tapVisible(WidgetTester tester, Key key) async {
  final finder = find.byKey(key);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
}

void main() {
  testWidgets('shows the plaintext-on-disk warning up front', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: testProviderOverrides(),
        child: const PasswordManagerApp(),
      ),
    );
    await tester.pumpAndSettle();

    await _signUpAndReachHome(tester);
    await _openExportScreen(tester);

    expect(find.byKey(const Key('exportCsvWarningText')), findsOneWidget);
    expect(find.textContaining('unencrypted'), findsOneWidget);
  });

  testWidgets(
    'a wrong master secret is rejected and nothing is exported',
    (WidgetTester tester) async {
      final exporter = InMemoryVaultCsvExporter();
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            ...testProviderOverrides(),
            vaultCsvExporterProvider.overrideWithValue(exporter),
          ],
          child: const PasswordManagerApp(),
        ),
      );
      await tester.pumpAndSettle();

      await _signUpAndReachHome(tester);
      await _openExportScreen(tester);

      await tester.enterText(
        find.byKey(const Key('exportCsvMasterSecretField')),
        'the wrong secret entirely',
      );
      await tester.pump();
      await _tapVisible(tester, const Key('exportCsvSubmitButton'));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.byKey(const Key('exportCsvErrorText')), findsOneWidget);
      expect(find.byKey(const Key('exportCsvSuccessText')), findsNothing);
      expect(exporter.writtenFiles, isEmpty);
    },
  );

  testWidgets(
    'a correct submission exports only active items with the right CSV '
    'content, and shows the success message with the file path',
    (WidgetTester tester) async {
      final exporter = InMemoryVaultCsvExporter();
      final container = ProviderContainer(
        overrides: <Override>[
          ...testProviderOverrides(),
          vaultCsvExporterProvider.overrideWithValue(exporter),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const PasswordManagerApp(),
        ),
      );
      await tester.pumpAndSettle();

      await _signUpAndReachHome(tester);

      // Seed the vault directly through the repository (rather than
      // driving the create-item form twice through the UI) so this test
      // stays focused on the export screen's own behavior: re-auth, then
      // "only active items, correct content" end to end.
      final repo = container.read(vaultRepositoryProvider);
      expect(repo, isNotNull);
      await repo!.createCredential(
        const CredentialData(
          identifier: 'kept@example.com',
          secret: 'keep-me-secret',
        ),
      );
      final trashed = await repo.createCredential(
        const CredentialData(
          identifier: 'trashed@example.com',
          secret: 'trash-me-secret',
        ),
      );
      await repo.softDelete(trashed.id);

      await _openExportScreen(tester);

      await tester.enterText(
        find.byKey(const Key('exportCsvMasterSecretField')),
        _kMasterSecret,
      );
      await tester.pump();
      await _tapVisible(tester, const Key('exportCsvSubmitButton'));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.byKey(const Key('exportCsvSuccessText')), findsOneWidget);
      expect(exporter.writtenFiles, hasLength(1));
      final content = exporter.writtenFiles.values.single;
      expect(content, contains('kept@example.com,keep-me-secret'));
      expect(content, isNot(contains('trashed@example.com')));
    },
  );
}
