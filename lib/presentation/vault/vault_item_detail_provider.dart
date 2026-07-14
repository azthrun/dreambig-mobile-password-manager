import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:password_manager/domain/models/vault_item.dart';
import 'package:password_manager/presentation/app/providers.dart';

/// Fetches a single vault item by id for the detail screen. `autoDispose`
/// so stale data isn't held once the screen is popped, and re-runs if the
/// underlying [vaultRepositoryProvider] session changes.
final AutoDisposeFutureProviderFamily<VaultItem?, String>
vaultItemDetailProvider = FutureProvider.autoDispose.family<VaultItem?, String>((
  ref,
  id,
) async {
  final repo = ref.watch(vaultRepositoryProvider);
  if (repo == null) return null;
  return repo.getById(id);
});
