import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:password_manager/domain/models/vault_item.dart';
import 'package:password_manager/domain/models/vault_item_revision.dart';
import 'package:password_manager/l10n/generated/app_localizations.dart';
import 'package:password_manager/presentation/app/providers.dart';
import 'package:password_manager/presentation/common/copy_to_clipboard_button.dart';
import 'package:password_manager/presentation/vault/vault_item_detail_provider.dart';
import 'package:password_manager/presentation/vault/vault_item_form_screen.dart';
import 'package:password_manager/presentation/vault/vault_list_controller.dart';

/// Detail view for a single vault item: fields, edit/delete actions, and a
/// basic revision-history "restore this version" affordance
/// (GOALS_v2 §1.1).
class VaultItemDetailScreen extends ConsumerStatefulWidget {
  const VaultItemDetailScreen({super.key, required this.itemId});

  final String itemId;

  @override
  ConsumerState<VaultItemDetailScreen> createState() =>
      _VaultItemDetailScreenState();
}

class _VaultItemDetailScreenState
    extends ConsumerState<VaultItemDetailScreen> {
  bool _secretVisible = false;

  Future<void> _delete(VaultItem item) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.vaultDeleteConfirmTitle),
        content: Text(l10n.vaultDeleteConfirmMessage),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.vaultCancelButton),
          ),
          TextButton(
            key: const Key('vaultDetailConfirmDeleteButton'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.vaultItemDeleteButton),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(vaultListControllerProvider.notifier).deleteItem(item.id);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _restoreRevision(VaultItemRevision revision) async {
    final repo = ref.read(vaultRepositoryProvider);
    if (repo == null) return;
    await repo.restoreRevision(widget.itemId, revision.eTag);
    ref.invalidate(vaultItemDetailProvider(widget.itemId));
    await ref.read(vaultListControllerProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final itemAsync = ref.watch(vaultItemDetailProvider(widget.itemId));

    return Scaffold(
      appBar: AppBar(
        title: itemAsync.maybeWhen(
          data: (item) =>
              Text(item != null && item.data.siteName.isNotEmpty
                  ? item.data.siteName
                  : (item?.data.identifier ?? l10n.appTitle)),
          orElse: () => Text(l10n.appTitle),
        ),
        actions: <Widget>[
          itemAsync.maybeWhen(
            data: (item) => item == null
                ? const SizedBox.shrink()
                : IconButton(
                    key: const Key('vaultDetailEditButton'),
                    icon: const Icon(Icons.edit),
                    tooltip: l10n.vaultItemEditButton,
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => VaultItemFormScreen(editing: item),
                        ),
                      );
                      ref.invalidate(vaultItemDetailProvider(widget.itemId));
                    },
                  ),
            orElse: () => const SizedBox.shrink(),
          ),
          itemAsync.maybeWhen(
            data: (item) => item == null
                ? const SizedBox.shrink()
                : IconButton(
                    key: const Key('vaultDetailDeleteButton'),
                    icon: const Icon(Icons.delete_outline),
                    tooltip: l10n.vaultItemDeleteButton,
                    onPressed: () => _delete(item),
                  ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: itemAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            Center(child: Text(l10n.genericErrorLabel)),
        data: (item) {
          if (item == null) {
            return Center(child: Text(l10n.vaultEmptyState));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              _DetailRow(label: l10n.vaultFieldIdentifier, value: item.data.identifier),
              _DetailRow(
                label: l10n.vaultFieldSecret,
                value: _secretVisible ? item.data.secret : '••••••••',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    IconButton(
                      key: const Key('vaultDetailSecretVisibilityToggle'),
                      icon: Icon(
                        _secretVisible
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      tooltip: _secretVisible
                          ? l10n.vaultHideSecretTooltip
                          : l10n.vaultRevealSecretTooltip,
                      onPressed: () =>
                          setState(() => _secretVisible = !_secretVisible),
                    ),
                    CopyToClipboardButton(
                      key: const Key('vaultDetailCopySecretButton'),
                      value: item.data.secret,
                      tooltip: l10n.vaultCopySecretTooltip,
                      copiedMessage: l10n.vaultSecretCopiedMessage,
                    ),
                  ],
                ),
              ),
              if (item.data.siteName.isNotEmpty)
                _DetailRow(label: l10n.vaultFieldSiteName, value: item.data.siteName),
              if (item.data.url.isNotEmpty)
                _DetailRow(label: l10n.vaultFieldUrl, value: item.data.url),
              if (item.data.notes.isNotEmpty)
                _DetailRow(label: l10n.vaultFieldNotes, value: item.data.notes),
              if (item.data.tags.isNotEmpty)
                _DetailRow(
                  label: l10n.vaultFieldTags,
                  value: item.data.tags.join(', '),
                ),
              const SizedBox(height: 24),
              Text(
                l10n.vaultRevisionHistoryTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              if (item.revisions.isEmpty)
                Text(l10n.vaultRevisionEmptyState)
              else
                ...item.revisions.map(
                  (revision) => Card(
                    key: Key('vaultRevisionCard-${revision.eTag}'),
                    child: ListTile(
                      title: Text(revision.data.identifier),
                      subtitle: Text(
                        l10n.vaultRevisionSavedAt(
                          revision.savedAt.toLocal().toString(),
                        ),
                      ),
                      trailing: TextButton(
                        onPressed: () => _restoreRevision(revision),
                        child: Text(l10n.vaultRevisionRestoreButton),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value, this.trailing});

  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(label, style: Theme.of(context).textTheme.labelSmall),
                Text(value, style: Theme.of(context).textTheme.bodyLarge),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
