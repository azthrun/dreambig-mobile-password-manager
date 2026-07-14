import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:password_manager/data/vault/vault_repository.dart';
import 'package:password_manager/domain/models/vault_item.dart';
import 'package:password_manager/presentation/app/providers.dart';

/// Drives the vault home (list) screen: loads the current session's active
/// items via [vaultRepositoryProvider] and re-runs whenever that provider's
/// underlying session changes (sign-in/out, lock/unlock) since it's a
/// `Provider` dependency, not a one-shot read.
class VaultListController extends AsyncNotifier<List<VaultItem>> {
  @override
  Future<List<VaultItem>> build() async {
    final repo = ref.watch(vaultRepositoryProvider);
    if (repo == null) return const <VaultItem>[];
    return repo.listActive();
  }

  VaultRepository? get _repo => ref.read(vaultRepositoryProvider);

  Future<void> refresh() async {
    final repo = _repo;
    if (repo == null) {
      state = const AsyncValue<List<VaultItem>>.data(<VaultItem>[]);
      return;
    }
    state = await AsyncValue.guard(repo.listActive);
  }

  Future<void> deleteItem(String id) async {
    final repo = _repo;
    if (repo == null) return;
    await repo.softDelete(id);
    await refresh();
  }
}

final AsyncNotifierProvider<VaultListController, List<VaultItem>>
vaultListControllerProvider =
    AsyncNotifierProvider<VaultListController, List<VaultItem>>(
      VaultListController.new,
    );
