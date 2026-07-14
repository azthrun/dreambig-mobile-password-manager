import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:password_manager/l10n/generated/app_localizations.dart';
import 'package:password_manager/presentation/auth/auth_controller.dart';
import 'package:password_manager/presentation/routing/app_router.dart';

/// Step 1 of sign-up: collect email + master secret.
///
/// Deliberately does **not** create the account. It only stashes the
/// credentials in the controller and moves to [RecoveryModeScreen], which
/// must be shown before account/vault creation per GOALS_v2 §1.3.
class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _masterSecretController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _masterSecretController.dispose();
    super.dispose();
  }

  void _continue() {
    if (!_formKey.currentState!.validate()) return;
    ref
        .read(authControllerProvider.notifier)
        .beginSignUp(
          email: _emailController.text.trim(),
          masterSecret: _masterSecretController.text,
        );
    context.go(AppRoutes.recoveryMode);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.signUpTitle)),
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
                      key: const Key('signUpEmailField'),
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
                      controller: _masterSecretController,
                      key: const Key('signUpMasterSecretField'),
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: l10n.authMasterSecretLabel,
                      ),
                      validator: (value) => (value == null || value.length < 8)
                          ? l10n.authMasterSecretLabel
                          : null,
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      key: const Key('signUpContinueButton'),
                      onPressed: _continue,
                      child: Text(l10n.signUpContinueButton),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => context.go(AppRoutes.signIn),
                      child: Text(l10n.signUpHaveAccountLink),
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
