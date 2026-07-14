import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:password_manager/l10n/generated/app_localizations.dart';
import 'package:password_manager/presentation/auth/auth_controller.dart';

/// The literal string the user must type to confirm account deletion
/// (GOALS_v2 §1.7: "explicit type-to-confirm").
const String kDeleteAccountConfirmationText = 'DELETE';

/// Account-deletion screen (GOALS_v2 §1.7).
///
/// Models the "make the stakes visible before commit" pattern from the
/// Phase 1 recovery-mode screen: the irreversibility warning is the first
/// thing on screen, always visible, not hidden behind a dialog. Deletion is
/// only reachable once *all* of the following are true simultaneously — no
/// single tap can ever complete it:
///   1. The user has explicitly checked the "I understand" acknowledgement.
///   2. The user has re-entered (and the app has re-verified) their master
///      secret, immediately before the action.
///   3. The user has typed the literal string "DELETE" into a confirmation
///      field.
/// Only then does the submit button become enabled at all.
class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() =>
      _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final _masterSecretController = TextEditingController();
  final _confirmTextController = TextEditingController();
  bool _acknowledged = false;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _masterSecretController.addListener(_refresh);
    _confirmTextController.addListener(_refresh);
  }

  @override
  void dispose() {
    _masterSecretController.dispose();
    _confirmTextController.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  bool get _confirmTextMatches =>
      _confirmTextController.text == kDeleteAccountConfirmationText;

  bool get _canSubmit =>
      !_submitting &&
      _acknowledged &&
      _masterSecretController.text.isNotEmpty &&
      _confirmTextMatches;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(authControllerProvider.notifier);
    try {
      // Re-authentication immediately before the irreversible action
      // (GOALS_v2 §1.7) — never trust that the account screen having been
      // reachable at all is proof enough.
      final verified = await controller.verifyMasterSecret(
        _masterSecretController.text,
      );
      if (!verified) {
        if (!mounted) return;
        setState(() {
          _submitting = false;
          _error = l10n.deleteAccountReauthError;
        });
        return;
      }
      await controller.deleteAccount();
      // Router redirect takes it from here once state flips to signedOut.
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = l10n.authGenericError;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.deleteAccountTitle)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Card(
                    color: Theme.of(
                      context,
                    ).colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        l10n.deleteAccountWarning,
                        key: const Key('deleteAccountWarningText'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  CheckboxListTile(
                    key: const Key('deleteAccountAcknowledgeCheckbox'),
                    value: _acknowledged,
                    onChanged: _submitting
                        ? null
                        : (value) =>
                              setState(() => _acknowledged = value ?? false),
                    title: Text(l10n.deleteAccountAcknowledgeCheckbox),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  const SizedBox(height: 16),
                  Text(l10n.deleteAccountReauthInstructions),
                  const SizedBox(height: 8),
                  TextField(
                    key: const Key('deleteAccountMasterSecretField'),
                    controller: _masterSecretController,
                    obscureText: true,
                    enabled: !_submitting,
                    decoration: InputDecoration(
                      labelText: l10n.authMasterSecretLabel,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    key: const Key('deleteAccountConfirmTextField'),
                    controller: _confirmTextController,
                    enabled: !_submitting,
                    decoration: InputDecoration(
                      labelText: l10n.deleteAccountConfirmTextLabel,
                      errorText:
                          _confirmTextController.text.isNotEmpty &&
                              !_confirmTextMatches
                          ? l10n.deleteAccountConfirmTextMismatch
                          : null,
                    ),
                  ),
                  if (_error != null) ...<Widget>[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      key: const Key('deleteAccountErrorText'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    key: const Key('deleteAccountSubmitButton'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                    ),
                    onPressed: _canSubmit ? _submit : null,
                    child: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.deleteAccountSubmitButton),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
