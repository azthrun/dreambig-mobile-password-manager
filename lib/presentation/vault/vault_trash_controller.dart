import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:password_manager/data/vault/vault_repository.dart';
import 'package:password_manager/domain/models/vault_item.dart';
import 'package:password_manager/presentation/app/providers.dart';
import 'package:password_manager/presentation/vault/vault_list_controller.dart';

/// Drives the trash screen (soft-deleted items within the recovery window,
/// GOALS_v2 §1.1).
class VaultTrashController extends AsyncNotifier<List<VaultItem>> {
  @override
  Future<List<VaultItem>> build() async {
    final repo = ref.watch(vaultRepositoryProvider);
    if (repo == null) return const <VaultItem>[];
    return repo.listTrash();
  }

  VaultRepository? get _repo => ref.read(vaultRepositoryProvider);

  Future<void> refresh() async {
    final repo = _repo;
    if (repo == null) {
      state = const AsyncValue<List<VaultItem>>.data(<VaultItem>[]);
      return;
    }
    state = await AsyncValue.guard(repo.listTrash);
  }

  Future<void> restoreItem(String id) async {
    final repo = _repo;
    if (repo == null) return;
    await repo.restore(id);
    await refresh();
    // The item reappearing in the active list is driven by the same
    // repository, so refresh that side too rather than waiting for an
    // unrelated rebuild to notice.
    await ref.read(vaultListControllerProvider.notifier).refresh();
  }
}

final AsyncNotifierProvider<VaultTrashController, List<VaultItem>>
vaultTrashControllerProvider =
    AsyncNotifierProvider<VaultTrashController, List<VaultItem>>(
      VaultTrashController.new,
    );
