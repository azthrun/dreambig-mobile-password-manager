import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:password_manager/l10n/generated/app_localizations.dart';
import 'package:password_manager/presentation/app/providers.dart';
import 'package:password_manager/presentation/auth/auth_controller.dart';

/// CSV export screen (GOALS_v2 §3.3).
///
/// The plaintext-on-disk warning is shown up front, always visible — never
/// buried behind a secondary dialog. Re-authentication (master-secret
/// re-entry, verified immediately before the export happens) is required
/// exactly like account deletion's re-auth gate. Only active (non-trashed)
/// vault items are exported — see `encodeVaultItemsAsCsv`'s doc comment.
class ExportCsvScreen extends ConsumerStatefulWidget {
  const ExportCsvScreen({super.key});

  @override
  ConsumerState<ExportCsvScreen> createState() => _ExportCsvScreenState();
}

class _ExportCsvScreenState extends ConsumerState<ExportCsvScreen> {
  final _masterSecretController = TextEditingController();
  bool _submitting = false;
  String? _error;
  String? _resultPath;

  @override
  void initState() {
    super.initState();
    _masterSecretController.addListener(_refresh);
  }

  @override
  void dispose() {
    _masterSecretController.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  bool get _canSubmit =>
      !_submitting && _masterSecretController.text.isNotEmpty;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _submitting = true;
      _error = null;
      _resultPath = null;
    });
    final l10n = AppLocalizations.of(context);
    final authController = ref.read(authControllerProvider.notifier);
    try {
      // Re-authentication immediately before export (GOALS_v2 §3.3) — this
      // is a plaintext-secrets operation by nature, so being reachable from
      // an already-unlocked session is not enough on its own.
      final verified = await authController.verifyMasterSecret(
        _masterSecretController.text,
      );
      if (!verified) {
        if (!mounted) return;
        setState(() {
          _submitting = false;
          _error = l10n.exportCsvReauthError;
        });
        return;
      }
      final repo = ref.read(vaultRepositoryProvider);
      if (repo == null) {
        throw StateError(l10n.noUnlockedVaultError);
      }
      // Only active (non-trashed) items — `encodeVaultItemsAsCsv` also
      // defensively filters, but `listActive()` is the primary guard.
      final items = await repo.listActive();
      final path = await ref
          .read(vaultCsvExporterProvider)
          .exportActiveItems(items);
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _resultPath = path;
      });
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
      appBar: AppBar(title: Text(l10n.exportCsvTitle)),
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
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        l10n.exportCsvWarning,
                        key: const Key('exportCsvWarningText'),
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(l10n.exportCsvReauthInstructions),
                  const SizedBox(height: 8),
                  TextField(
                    key: const Key('exportCsvMasterSecretField'),
                    controller: _masterSecretController,
                    obscureText: true,
                    enabled: !_submitting,
                    decoration: InputDecoration(
                      labelText: l10n.authMasterSecretLabel,
                    ),
                  ),
                  if (_error != null) ...<Widget>[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      key: const Key('exportCsvErrorText'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  if (_resultPath != null) ...<Widget>[
                    const SizedBox(height: 12),
                    Text(
                      l10n.exportCsvSuccessMessage(_resultPath!),
                      key: const Key('exportCsvSuccessText'),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    key: const Key('exportCsvSubmitButton'),
                    onPressed: _canSubmit ? _submit : null,
                    child: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.exportCsvSubmitButton),
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
