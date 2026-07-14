import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:password_manager/l10n/generated/app_localizations.dart';
import 'package:password_manager/presentation/vault/vault_trash_controller.dart';

/// Trash screen: soft-deleted items still within the 30-day recovery
/// window (GOALS_v2 §1.1). Permanent purge is out of scope for Phase 2
/// (IMPLEMENTATION_PLAN.md) — this screen only offers restore.
class VaultTrashScreen extends ConsumerWidget {
  const VaultTrashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final trashAsync = ref.watch(vaultTrashControllerProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.vaultTrashTitle)),
      body: trashAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            Center(child: Text(l10n.genericErrorLabel)),
        data: (items) {
          if (items.isEmpty) {
            return Center(child: Text(l10n.vaultTrashEmptyState));
          }
          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return ListTile(
                key: Key('vaultTrashItem-${item.id}'),
                title: Text(
                  item.data.siteName.isNotEmpty
                      ? item.data.siteName
                      : item.data.identifier,
                ),
                subtitle: Text(
                  l10n.vaultTrashDeletedOn(
                    item.deletedAt!.toLocal().toString(),
                  ),
                ),
                trailing: TextButton(
                  key: Key('vaultTrashRestoreButton-${item.id}'),
                  onPressed: () => ref
                      .read(vaultTrashControllerProvider.notifier)
                      .restoreItem(item.id),
                  child: Text(l10n.vaultTrashRestoreButton),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
