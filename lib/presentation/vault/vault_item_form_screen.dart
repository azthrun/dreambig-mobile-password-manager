import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:password_manager/domain/models/credential_data.dart';
import 'package:password_manager/domain/models/vault_item.dart';
import 'package:password_manager/l10n/generated/app_localizations.dart';
import 'package:password_manager/presentation/app/providers.dart';
import 'package:password_manager/presentation/generator/generator_screen.dart';
import 'package:password_manager/presentation/generator/password_strength_indicator.dart';
import 'package:password_manager/presentation/vault/vault_item_detail_provider.dart';
import 'package:password_manager/presentation/vault/vault_list_controller.dart';

/// Create/edit form for a credential vault item (GOALS_v2 §1.1).
///
/// The secret field wires into the Phase 3 password generator
/// ([GeneratorScreen]) via its "Generate" button, and shows a live
/// [PasswordStrengthIndicator] as the user types — GOALS_v2 §1.2 requires
/// the strength estimate be shown "at generation and entry time".
class VaultItemFormScreen extends ConsumerStatefulWidget {
  const VaultItemFormScreen({super.key, this.editing});

  /// Null for create; the item being edited otherwise.
  final VaultItem? editing;

  @override
  ConsumerState<VaultItemFormScreen> createState() =>
      _VaultItemFormScreenState();
}

class _VaultItemFormScreenState extends ConsumerState<VaultItemFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _identifierController;
  late final TextEditingController _secretController;
  late final TextEditingController _siteNameController;
  late final TextEditingController _urlController;
  late final TextEditingController _notesController;
  late final TextEditingController _tagsController;

  bool _secretVisible = false;
  bool _saving = false;

  bool get _isEditing => widget.editing != null;

  @override
  void initState() {
    super.initState();
    final data = widget.editing?.data;
    _identifierController = TextEditingController(text: data?.identifier ?? '');
    _secretController = TextEditingController(text: data?.secret ?? '');
    _siteNameController = TextEditingController(text: data?.siteName ?? '');
    _urlController = TextEditingController(text: data?.url ?? '');
    _notesController = TextEditingController(text: data?.notes ?? '');
    _tagsController = TextEditingController(
      text: data?.tags.join(', ') ?? '',
    );
  }

  @override
  void dispose() {
    _identifierController.dispose();
    _secretController.dispose();
    _siteNameController.dispose();
    _urlController.dispose();
    _notesController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _openGenerator() async {
    final generated = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => const GeneratorScreen()),
    );
    if (generated == null || !mounted) return;
    setState(() {
      _secretController.text = generated;
      _secretVisible = true;
    });
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final repo = ref.read(vaultRepositoryProvider);
    if (repo == null) return;

    setState(() => _saving = true);
    final tags = _tagsController.text
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    final data = CredentialData(
      identifier: _identifierController.text.trim(),
      secret: _secretController.text,
      siteName: _siteNameController.text.trim(),
      url: _urlController.text.trim(),
      notes: _notesController.text.trim(),
      tags: tags,
    );

    final editing = widget.editing;
    if (editing != null) {
      await repo.updateCredential(editing.id, data);
      ref.invalidate(vaultItemDetailProvider(editing.id));
    } else {
      await repo.createCredential(data);
    }
    await ref.read(vaultListControllerProvider.notifier).refresh();

    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? l10n.vaultItemEditTitle : l10n.vaultItemCreateTitle),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            TextFormField(
              key: const Key('vaultFormIdentifierField'),
              controller: _identifierController,
              decoration: InputDecoration(labelText: l10n.vaultFieldIdentifier),
              validator: (value) =>
                  (value == null || value.trim().isEmpty)
                      ? l10n.vaultFieldRequiredError
                      : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('vaultFormSecretField'),
              controller: _secretController,
              obscureText: !_secretVisible,
              decoration: InputDecoration(
                labelText: l10n.vaultFieldSecret,
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    IconButton(
                      key: const Key('vaultFormGenerateButton'),
                      icon: const Icon(Icons.autorenew),
                      tooltip: l10n.vaultGenerateSecretButton,
                      onPressed: _openGenerator,
                    ),
                    IconButton(
                      key: const Key('vaultFormSecretVisibilityToggle'),
                      icon: Icon(
                        _secretVisible
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      tooltip: _secretVisible
                          ? l10n.vaultHideSecretTooltip
                          : l10n.vaultRevealSecretTooltip,
                      onPressed: () =>
                          setState(() => _secretVisible = !_secretVisible),
                    ),
                  ],
                ),
              ),
              validator: (value) =>
                  (value == null || value.isEmpty)
                      ? l10n.vaultFieldRequiredError
                      : null,
              // Live strength estimate as the user types (GOALS_v2 §1.2:
              // "shown at generation and entry time").
              onChanged: (_) => setState(() {}),
            ),
            PasswordStrengthIndicator(password: _secretController.text),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('vaultFormSiteNameField'),
              controller: _siteNameController,
              decoration: InputDecoration(labelText: l10n.vaultFieldSiteName),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('vaultFormUrlField'),
              controller: _urlController,
              decoration: InputDecoration(labelText: l10n.vaultFieldUrl),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('vaultFormNotesField'),
              controller: _notesController,
              decoration: InputDecoration(labelText: l10n.vaultFieldNotes),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('vaultFormTagsField'),
              controller: _tagsController,
              decoration: InputDecoration(labelText: l10n.vaultFieldTags),
            ),
            const SizedBox(height: 24),
            FilledButton(
              key: const Key('vaultFormSaveButton'),
              onPressed: _saving ? null : _save,
              child: Text(l10n.vaultItemSaveButton),
            ),
          ],
        ),
      ),
    );
  }
}
