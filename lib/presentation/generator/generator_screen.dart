import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:password_manager/domain/generator/generator_mode.dart';
import 'package:password_manager/domain/generator/passphrase_generator_options.dart';
import 'package:password_manager/domain/generator/password_generator_options.dart';
import 'package:password_manager/l10n/generated/app_localizations.dart';
import 'package:password_manager/presentation/common/copy_to_clipboard_button.dart';
import 'package:password_manager/presentation/generator/generator_controller.dart';
import 'package:password_manager/presentation/generator/password_strength_indicator.dart';

/// Password generator screen (GOALS_v2 §1.2).
///
/// Usable two ways, both backed by the same [generatorControllerProvider]:
///  - **Standalone**: pushed from the home screen with nothing to return —
///    a user just wants to generate/copy a value without saving an item
///    yet (requirement item 4).
///  - **From the vault item form**: pushed with `Navigator.push<String>`,
///    and the "use this password" button pops the generated value back to
///    the caller, which fills the form's secret field.
///
/// Which mode applies is inferred from `Navigator.canPop` — if there's
/// somewhere to pop back to with a result, the "use this password" action
/// is shown.
class GeneratorScreen extends ConsumerWidget {
  const GeneratorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final stateAsync = ref.watch(generatorControllerProvider);
    final canReturnValue = Navigator.of(context).canPop();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.generatorTitle)),
      body: stateAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            Center(child: Text(l10n.genericErrorLabel)),
        data: (state) {
          final preferences = state.preferences;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              SegmentedButton<GeneratorMode>(
                key: const Key('generatorModeSelector'),
                segments: <ButtonSegment<GeneratorMode>>[
                  ButtonSegment<GeneratorMode>(
                    value: GeneratorMode.characters,
                    label: Text(l10n.generatorModeCharacters),
                  ),
                  ButtonSegment<GeneratorMode>(
                    value: GeneratorMode.passphrase,
                    label: Text(l10n.generatorModePassphrase),
                  ),
                ],
                selected: <GeneratorMode>{preferences.mode},
                onSelectionChanged: (selection) => ref
                    .read(generatorControllerProvider.notifier)
                    .setMode(selection.first),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: SelectableText(
                              state.generatedValue,
                              key: const Key('generatorGeneratedValue'),
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontFamily: 'monospace'),
                            ),
                          ),
                          CopyToClipboardButton(
                            key: const Key('generatorCopyButton'),
                            value: state.generatedValue,
                            tooltip: l10n.generatorCopyButton,
                            copiedMessage: l10n.generatorValueCopiedMessage,
                          ),
                        ],
                      ),
                      if (state.error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            l10n.generatorErrorNoCharacterSet,
                            key: const Key('generatorErrorText'),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      PasswordStrengthIndicator(password: state.generatedValue),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('generatorRegenerateButton'),
                onPressed: () =>
                    ref.read(generatorControllerProvider.notifier).regenerate(),
                icon: const Icon(Icons.refresh),
                label: Text(l10n.generatorRegenerateButton),
              ),
              const SizedBox(height: 24),
              if (preferences.mode == GeneratorMode.characters)
                _CharacterOptions(options: preferences.passwordOptions)
              else
                _PassphraseOptions(options: preferences.passphraseOptions),
              const SizedBox(height: 24),
              if (canReturnValue)
                FilledButton(
                  key: const Key('generatorUseThisPasswordButton'),
                  onPressed: () =>
                      Navigator.of(context).pop(state.generatedValue),
                  child: Text(l10n.generatorUseThisPasswordButton),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _CharacterOptions extends ConsumerWidget {
  const _CharacterOptions({required this.options});

  final PasswordGeneratorOptions options;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final notifier = ref.read(generatorControllerProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(l10n.generatorLengthLabel(options.length)),
        Slider(
          key: const Key('generatorLengthSlider'),
          value: options.length.toDouble(),
          min: 4,
          max: 64,
          divisions: 60,
          label: '${options.length}',
          onChanged: (value) => notifier.updatePasswordOptions(
            (o) => o.copyWith(length: value.round()),
          ),
        ),
        CheckboxListTile(
          key: const Key('generatorUppercaseCheckbox'),
          title: Text(l10n.generatorUppercaseLabel),
          value: options.useUppercase,
          onChanged: (value) => notifier.updatePasswordOptions(
            (o) => o.copyWith(useUppercase: value ?? o.useUppercase),
          ),
        ),
        CheckboxListTile(
          key: const Key('generatorLowercaseCheckbox'),
          title: Text(l10n.generatorLowercaseLabel),
          value: options.useLowercase,
          onChanged: (value) => notifier.updatePasswordOptions(
            (o) => o.copyWith(useLowercase: value ?? o.useLowercase),
          ),
        ),
        CheckboxListTile(
          key: const Key('generatorDigitsCheckbox'),
          title: Text(l10n.generatorDigitsLabel),
          value: options.useDigits,
          onChanged: (value) => notifier.updatePasswordOptions(
            (o) => o.copyWith(useDigits: value ?? o.useDigits),
          ),
        ),
        CheckboxListTile(
          key: const Key('generatorSymbolsCheckbox'),
          title: Text(l10n.generatorSymbolsLabel),
          value: options.useSymbols,
          onChanged: (value) => notifier.updatePasswordOptions(
            (o) => o.copyWith(useSymbols: value ?? o.useSymbols),
          ),
        ),
        CheckboxListTile(
          key: const Key('generatorExcludeAmbiguousCheckbox'),
          title: Text(l10n.generatorExcludeAmbiguousLabel),
          value: options.excludeAmbiguous,
          onChanged: (value) => notifier.updatePasswordOptions(
            (o) =>
                o.copyWith(excludeAmbiguous: value ?? o.excludeAmbiguous),
          ),
        ),
      ],
    );
  }
}

class _PassphraseOptions extends ConsumerWidget {
  const _PassphraseOptions({required this.options});

  final PassphraseGeneratorOptions options;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final notifier = ref.read(generatorControllerProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(l10n.generatorWordCountLabel(options.wordCount)),
        Slider(
          key: const Key('generatorWordCountSlider'),
          value: options.wordCount.toDouble(),
          min: 3,
          max: 10,
          divisions: 7,
          label: '${options.wordCount}',
          onChanged: (value) => notifier.updatePassphraseOptions(
            (o) => o.copyWith(wordCount: value.round()),
          ),
        ),
        TextFormField(
          key: const Key('generatorSeparatorField'),
          initialValue: options.separator,
          decoration: InputDecoration(labelText: l10n.generatorSeparatorLabel),
          inputFormatters: <TextInputFormatter>[
            LengthLimitingTextInputFormatter(3),
          ],
          onChanged: (value) => notifier.updatePassphraseOptions(
            (o) => o.copyWith(separator: value),
          ),
        ),
        CheckboxListTile(
          key: const Key('generatorCapitalizeCheckbox'),
          title: Text(l10n.generatorCapitalizeLabel),
          value: options.capitalizeWords,
          onChanged: (value) => notifier.updatePassphraseOptions(
            (o) => o.copyWith(capitalizeWords: value ?? o.capitalizeWords),
          ),
        ),
        CheckboxListTile(
          key: const Key('generatorAppendNumberCheckbox'),
          title: Text(l10n.generatorAppendNumberLabel),
          value: options.appendNumber,
          onChanged: (value) => notifier.updatePassphraseOptions(
            (o) => o.copyWith(appendNumber: value ?? o.appendNumber),
          ),
        ),
      ],
    );
  }
}
