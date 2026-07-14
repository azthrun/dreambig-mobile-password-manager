import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:password_manager/l10n/generated/app_localizations.dart';
import 'package:password_manager/presentation/auth/auth_controller.dart';

/// Shown whenever the session is [AuthStatus.signedInLocked] — after
/// auto-lock (inactivity timeout or app backgrounding, GOALS_v2 §1.3/§2.3)
/// or on a fresh process launch that restores an existing session.
///
/// Re-authentication resumes the session either via master-secret re-entry
/// or, if enabled, biometrics. Biometrics never re-derive the vault key
/// differently — they only gate access to the key already sitting in
/// secure storage (GOALS_v2 §1.3).
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  final _formKey = GlobalKey<FormState>();
  final _masterSecretController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _masterSecretController.dispose();
    super.dispose();
  }

  Future<void> _unlockWithMasterSecret() async {
    if (!_formKey.currentState!.validate() || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final ok = await ref
        .read(authControllerProvider.notifier)
        .unlockWithMasterSecret(_masterSecretController.text);
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _error = ok ? null : ref.read(authControllerProvider).errorMessage;
    });
  }

  Future<void> _unlockWithBiometric() async {
    if (_submitting) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _submitting = true;
      _error = null;
    });
    final ok = await ref
        .read(authControllerProvider.notifier)
        .unlockWithBiometric();
    if (!mounted) return;
    setState(() {
      _submitting = false;
      if (!ok) _error = l10n.biometricUnlockFailedError;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final biometricEnabled = ref.watch(
      authControllerProvider.select((s) => s.biometricEnabled),
    );
    return Scaffold(
      appBar: AppBar(title: Text(l10n.lockTitle)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(l10n.lockInstructions),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _masterSecretController,
                      key: const Key('lockMasterSecretField'),
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: l10n.authMasterSecretLabel,
                      ),
                      validator: (value) => (value == null || value.isEmpty)
                          ? l10n.authMasterSecretLabel
                          : null,
                    ),
                    if (_error != null) ...<Widget>[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      key: const Key('lockUnlockButton'),
                      onPressed: _submitting ? null : _unlockWithMasterSecret,
                      child: Text(l10n.lockUnlockButton),
                    ),
                    if (biometricEnabled) ...<Widget>[
                      const SizedBox(height: 12),
                      OutlinedButton(
                        key: const Key('lockBiometricButton'),
                        onPressed: _submitting ? null : _unlockWithBiometric,
                        child: Text(l10n.lockBiometricButton),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextButton(
                      key: const Key('lockSignOutButton'),
                      onPressed: _submitting
                          ? null
                          : () => ref
                                .read(authControllerProvider.notifier)
                                .signOut(),
                      child: Text(l10n.lockSignOutButton),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
