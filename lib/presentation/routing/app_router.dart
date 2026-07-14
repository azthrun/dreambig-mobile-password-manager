import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:password_manager/domain/auth/auth_state.dart';
import 'package:password_manager/domain/auth/auth_status.dart';
import 'package:password_manager/presentation/account/account_screen.dart';
import 'package:password_manager/presentation/account/delete_account_screen.dart';
import 'package:password_manager/presentation/account/export_csv_screen.dart';
import 'package:password_manager/presentation/auth/auth_controller.dart';
import 'package:password_manager/presentation/auth/confirm_email_screen.dart';
import 'package:password_manager/presentation/auth/lock_screen.dart';
import 'package:password_manager/presentation/auth/recovery_mode_screen.dart';
import 'package:password_manager/presentation/auth/sign_in_screen.dart';
import 'package:password_manager/presentation/auth/sign_up_screen.dart';
import 'package:password_manager/presentation/devices/device_management_screen.dart';
import 'package:password_manager/presentation/generator/generator_screen.dart';
import 'package:password_manager/presentation/home/home_screen.dart';
import 'package:password_manager/presentation/vault/vault_item_detail_screen.dart';
import 'package:password_manager/presentation/vault/vault_trash_screen.dart';

/// Route path/name constants, kept centralized so screens never hardcode
/// paths or names.
abstract final class AppRoutes {
  static const String home = '/';
  static const String signIn = '/sign-in';
  static const String signUp = '/sign-up';
  static const String recoveryMode = '/sign-up/recovery-mode';
  static const String confirmEmail = '/confirm-email';
  static const String lock = '/lock';

  /// Route *name* (not path) for the trash screen; navigated to via
  /// `context.pushNamed`.
  static const String trash = 'trash';
  static const String trashPath = '/trash';

  /// Route *name* for the item detail screen, parameterized by `id`.
  static const String vaultItemDetail = 'vault-item-detail';
  static const String vaultItemDetailPath = '/vault/:id';

  /// Standalone entry point for the password generator (GOALS_v2 §1.2,
  /// item 4) — reachable without creating/editing a vault item. The form
  /// screen instead pushes [GeneratorScreen] directly via
  /// `Navigator.push<String>` so it can receive the generated value back.
  static const String generator = 'generator';
  static const String generatorPath = '/generator';

  /// Route *name* for the device management screen (GOALS_v2 §1.4).
  static const String devices = 'devices';
  static const String devicesPath = '/devices';

  /// Route *name* for the account screen (GOALS_v2 §1.7, §3.3) — houses the
  /// CSV export and account deletion entry points.
  static const String account = 'account';
  static const String accountPath = '/account';

  /// Route *name* for the CSV export flow.
  static const String exportCsv = 'export-csv';
  static const String exportCsvPath = '/account/export-csv';

  /// Route *name* for the account-deletion flow.
  static const String deleteAccount = 'delete-account';
  static const String deleteAccountPath = '/account/delete';
}

/// Routes reachable while [AuthStatus.signedOut] (the whole sign-up/sign-in
/// funnel).
const Set<String> _signedOutRoutes = <String>{
  AppRoutes.signIn,
  AppRoutes.signUp,
  AppRoutes.recoveryMode,
};

/// App-wide router, exposed via Riverpod so it can be overridden in tests.
/// Auth-gated redirects live entirely in [GoRouter.redirect] below, driven
/// by [authControllerProvider] so signed-out/locked/unlocked transitions
/// (including auto-lock) immediately push the user to the right screen.
final Provider<GoRouter> appRouterProvider = Provider<GoRouter>((ref) {
  final refreshListenable = _AuthRefreshListenable(ref);
  ref.onDispose(refreshListenable.dispose);

  return GoRouter(
    initialLocation: AppRoutes.signIn,
    refreshListenable: refreshListenable,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final location = state.matchedLocation;

      if (auth.needsEmailConfirmation) {
        return location == AppRoutes.confirmEmail
            ? null
            : AppRoutes.confirmEmail;
      }

      switch (auth.status) {
        case AuthStatus.signedOut:
          return _signedOutRoutes.contains(location)
              ? null
              : AppRoutes.signIn;
        case AuthStatus.signedInLocked:
          return location == AppRoutes.lock ? null : AppRoutes.lock;
        case AuthStatus.signedInUnlocked:
          return _signedOutRoutes.contains(location) ||
                  location == AppRoutes.lock ||
                  location == AppRoutes.confirmEmail
              ? AppRoutes.home
              : null;
      }
    },
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.signIn,
        builder: (context, state) => const SignInScreen(),
      ),
      GoRoute(
        path: AppRoutes.signUp,
        builder: (context, state) => const SignUpScreen(),
      ),
      GoRoute(
        path: AppRoutes.recoveryMode,
        builder: (context, state) => const RecoveryModeScreen(),
      ),
      GoRoute(
        path: AppRoutes.confirmEmail,
        builder: (context, state) => const ConfirmEmailScreen(),
      ),
      GoRoute(
        path: AppRoutes.lock,
        builder: (context, state) => const LockScreen(),
      ),
      GoRoute(
        path: AppRoutes.trashPath,
        name: AppRoutes.trash,
        builder: (context, state) => const VaultTrashScreen(),
      ),
      GoRoute(
        path: AppRoutes.vaultItemDetailPath,
        name: AppRoutes.vaultItemDetail,
        builder: (context, state) => VaultItemDetailScreen(
          itemId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: AppRoutes.generatorPath,
        name: AppRoutes.generator,
        builder: (context, state) => const GeneratorScreen(),
      ),
      GoRoute(
        path: AppRoutes.devicesPath,
        name: AppRoutes.devices,
        builder: (context, state) => const DeviceManagementScreen(),
      ),
      GoRoute(
        path: AppRoutes.accountPath,
        name: AppRoutes.account,
        builder: (context, state) => const AccountScreen(),
      ),
      GoRoute(
        path: AppRoutes.exportCsvPath,
        name: AppRoutes.exportCsv,
        builder: (context, state) => const ExportCsvScreen(),
      ),
      GoRoute(
        path: AppRoutes.deleteAccountPath,
        name: AppRoutes.deleteAccount,
        builder: (context, state) => const DeleteAccountScreen(),
      ),
    ],
  );
});

/// Bridges Riverpod's [authControllerProvider] changes to go_router's
/// [Listenable]-based `refreshListenable`, so a lock/unlock/sign-out
/// triggers an immediate re-evaluation of [GoRouter.redirect] without
/// rebuilding the router itself (which would otherwise reset navigation
/// state on every auth change).
class _AuthRefreshListenable extends ChangeNotifier {
  _AuthRefreshListenable(this._ref) {
    _subscription = _ref.listen(authControllerProvider, (previous, next) {
      notifyListeners();
    });
  }

  final Ref _ref;
  late final ProviderSubscription<AuthState> _subscription;

  @override
  void dispose() {
    _subscription.close();
    super.dispose();
  }
}
