import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:password_manager/l10n/generated/app_localizations.dart';
import 'package:password_manager/presentation/auth/auth_controller.dart';
import 'package:password_manager/presentation/routing/app_router.dart';
import 'package:password_manager/presentation/vault/vault_item_form_screen.dart';
import 'package:password_manager/presentation/vault/vault_list_controller.dart';

/// Vault home screen: the signed-in-unlocked landing screen, now showing
/// the account's active vault items (GOALS_v2 §1.1) rather than just
/// proving the Phase 1 auth/session wiring.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final biometricEnabled = ref.watch(
      authControllerProvider.select((s) => s.biometricEnabled),
    );
    final itemsAsync = ref.watch(vaultListControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appTitle),
        actions: <Widget>[
          IconButton(
            key: const Key('homeGeneratorButton'),
            icon: const Icon(Icons.password),
            tooltip: l10n.generatorTitle,
            onPressed: () => context.pushNamed(AppRoutes.generator),
          ),
          IconButton(
            key: const Key('homeTrashButton'),
            icon: const Icon(Icons.delete_outline),
            tooltip: l10n.vaultTrashButton,
            onPressed: () => context.pushNamed(AppRoutes.trash),
          ),
          IconButton(
            key: const Key('homeDevicesButton'),
            icon: const Icon(Icons.devices),
            tooltip: l10n.deviceManagementButton,
            onPressed: () => context.pushNamed(AppRoutes.devices),
          ),
          IconButton(
            key: const Key('homeAccountButton'),
            icon: const Icon(Icons.account_circle_outlined),
            tooltip: l10n.accountButton,
            onPressed: () => context.pushNamed(AppRoutes.account),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('homeAddItemButton'),
        tooltip: l10n.vaultAddItemButton,
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const VaultItemFormScreen(),
          ),
        ),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  l10n.homeWelcomeMessage,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    FilledButton(
                      key: const Key('homeLockButton'),
                      onPressed: () =>
                          ref.read(authControllerProvider.notifier).lock(),
                      child: Text(l10n.homeLockButton),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton(
                      key: const Key('homeSignOutButton'),
                      onPressed: () =>
                          ref.read(authControllerProvider.notifier).signOut(),
                      child: Text(l10n.homeSignOutButton),
                    ),
                  ],
                ),
                if (!biometricEnabled) ...<Widget>[
                  const SizedBox(height: 12),
                  TextButton(
                    key: const Key('homeEnableBiometricButton'),
                    onPressed: () => ref
                        .read(authControllerProvider.notifier)
                        .enableBiometricUnlock(),
                    child: Text(l10n.biometricEnableButton),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: itemsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) =>
                  Center(child: Text(l10n.genericErrorLabel)),
              data: (items) {
                if (items.isEmpty) {
                  return Center(child: Text(l10n.vaultEmptyState));
                }
                return ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return ListTile(
                      key: Key('vaultListItem-${item.id}'),
                      title: Text(
                        item.data.siteName.isNotEmpty
                            ? item.data.siteName
                            : item.data.identifier,
                      ),
                      subtitle: Text(item.data.identifier),
                      onTap: () =>
                          context.pushNamed(AppRoutes.vaultItemDetail, pathParameters: {'id': item.id}),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
