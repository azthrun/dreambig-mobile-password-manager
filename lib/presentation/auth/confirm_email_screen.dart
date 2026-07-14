import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:password_manager/l10n/generated/app_localizations.dart';
import 'package:password_manager/presentation/auth/auth_controller.dart';

/// Step 3 of sign-up: the fake email confirmation code/link step.
///
/// GOALS_v2 §1.3 requires new accounts to confirm email before the account
/// is usable; the fake `ApiClient` accepts any non-empty code, simulating a
/// confirmation link/code flow without a real mail backend.
class ConfirmEmailScreen extends ConsumerStatefulWidget {
  const ConfirmEmailScreen({super.key});

  @override
  ConsumerState<ConfirmEmailScreen> createState() =>
      _ConfirmEmailScreenState();
}

class _ConfirmEmailScreenState extends ConsumerState<ConfirmEmailScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (!_formKey.currentState!.validate() || _submitting) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .confirmEmail(_codeController.text.trim());
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
    final email = ref.watch(authControllerProvider).email ?? '';
    return Scaffold(
      appBar: AppBar(title: Text(l10n.confirmEmailTitle)),
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
                    Text(l10n.confirmEmailInstructions(email)),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _codeController,
                      key: const Key('confirmEmailCodeField'),
                      decoration: InputDecoration(
                        labelText: l10n.confirmEmailCodeLabel,
                      ),
                      validator: (value) => (value == null || value.isEmpty)
                          ? l10n.confirmEmailCodeLabel
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
                      key: const Key('confirmEmailSubmitButton'),
                      onPressed: _submitting ? null : _confirm,
                      child: _submitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(l10n.confirmEmailSubmitButton),
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
