import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:password_manager/l10n/generated/app_localizations.dart';
import 'package:password_manager/presentation/auth/auth_controller.dart';
import 'package:password_manager/presentation/routing/app_router.dart';

/// Returning-user sign-in: email + account password + master secret. The
/// auth key is derived on-device from the account password and sent to
/// `ApiClient.signIn`; the master secret is used only to re-derive the
/// vault key locally and never leaves this screen (GOALS_v2 §1.3).
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _accountPasswordController = TextEditingController();
  final _masterSecretController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _accountPasswordController.dispose();
    _masterSecretController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _submitting) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .signIn(
            email: _emailController.text.trim(),
            accountPassword: _accountPasswordController.text,
            masterSecret: _masterSecretController.text,
          );
      // Router redirect takes it from here (status -> signedInUnlocked).
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = l10n.authGenericError);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.signInTitle)),
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
                    TextFormField(
                      controller: _emailController,
                      key: const Key('signInEmailField'),
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const <String>[AutofillHints.email],
                      decoration: InputDecoration(labelText: l10n.authEmailLabel),
                      validator: (value) =>
                          (value == null || !value.contains('@'))
                          ? l10n.authEmailLabel
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _accountPasswordController,
                      key: const Key('signInAccountPasswordField'),
                      obscureText: true,
                      autofillHints: const <String>[AutofillHints.password],
                      decoration: InputDecoration(
                        labelText: l10n.authAccountPasswordLabel,
                      ),
                      validator: (value) => (value == null || value.isEmpty)
                          ? l10n.authAccountPasswordLabel
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _masterSecretController,
                      key: const Key('signInMasterSecretField'),
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
                      key: const Key('signInSubmitButton'),
                      onPressed: _submitting ? null : _submit,
                      child: _submitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(l10n.signInSubmitButton),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => context.go(AppRoutes.signUp),
                      child: Text(l10n.signInNoAccountLink),
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
