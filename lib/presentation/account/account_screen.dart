import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:password_manager/l10n/generated/app_localizations.dart';
import 'package:password_manager/presentation/routing/app_router.dart';

/// Simple entry-point screen (GOALS_v2 §1.7, §3.3) housing the two Phase 7
/// features: CSV export and account deletion. Neither action is reachable
/// via a single tap from here — both push to their own dedicated screen
/// with its own warning/re-auth/confirmation gates.
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.accountScreenTitle)),
      body: SafeArea(
        child: ListView(
          children: <Widget>[
            ListTile(
              key: const Key('accountExportCsvButton'),
              leading: const Icon(Icons.file_download_outlined),
              title: Text(l10n.accountExportCsvButton),
              onTap: () => context.pushNamed(AppRoutes.exportCsv),
            ),
            const Divider(height: 1),
            ListTile(
              key: const Key('accountDeleteAccountButton'),
              leading: Icon(
                Icons.delete_forever_outlined,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                l10n.accountDeleteAccountButton,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () => context.pushNamed(AppRoutes.deleteAccount),
            ),
          ],
        ),
      ),
    );
  }
}
