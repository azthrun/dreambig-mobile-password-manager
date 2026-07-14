import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:password_manager/domain/generator/generator_mode.dart';
import 'package:password_manager/domain/generator/generator_preferences.dart';
import 'package:password_manager/domain/generator/passphrase_generator.dart';
import 'package:password_manager/domain/generator/passphrase_generator_options.dart';
import 'package:password_manager/domain/generator/password_generator.dart';
import 'package:password_manager/domain/generator/password_generator_options.dart';
import 'package:password_manager/presentation/app/providers.dart';
import 'package:password_manager/presentation/generator/generator_state.dart';

/// Drives the generator screen/sheet: loads persisted
/// `GeneratorPreferences` (GOALS_v2 §1.2, item 5), produces the initial
/// value, and regenerates/persists on every option change.
///
/// Deliberately independent of any vault item — the generator is usable
/// standalone (item 4 of the requirement), not only when opened from the
/// item form.
class GeneratorController extends AsyncNotifier<GeneratorState> {
  @override
  Future<GeneratorState> build() async {
    final store = ref.watch(generatorPreferencesStoreProvider);
    final preferences = await store.read() ?? const GeneratorPreferences();
    // Preload the diceware wordlist during the initial build regardless of
    // starting mode, so `dicewareWordlistProvider.future` is already
    // resolved and cached by the time a later mode switch (triggered from
    // a UI event handler, e.g. `setMode`) needs it in `_generate`.
    await ref.watch(dicewareWordlistProvider.future);
    final value = await _generate(preferences);
    return GeneratorState(preferences: preferences, generatedValue: value);
  }

  Future<String> _generate(GeneratorPreferences preferences) async {
    switch (preferences.mode) {
      case GeneratorMode.characters:
        return PasswordGenerator().generate(preferences.passwordOptions);
      case GeneratorMode.passphrase:
        final wordlist = await ref.read(dicewareWordlistProvider.future);
        return PassphraseGenerator(
          wordlist: wordlist,
        ).generate(preferences.passphraseOptions);
    }
  }

  /// Regenerates a new value using the current preferences (e.g. the user
  /// tapped a "regenerate" / refresh action without changing any option).
  Future<void> regenerate() async {
    final current = state.value;
    if (current == null) return;
    await _applyAndPersist(current.preferences);
  }

  Future<void> setMode(GeneratorMode mode) async {
    final current = state.value;
    if (current == null) return;
    await _applyAndPersist(current.preferences.copyWith(mode: mode));
  }

  Future<void> updatePasswordOptions(
    PasswordGeneratorOptions Function(PasswordGeneratorOptions) update,
  ) async {
    final current = state.value;
    if (current == null) return;
    await _applyAndPersist(
      current.preferences.copyWith(
        passwordOptions: update(current.preferences.passwordOptions),
      ),
    );
  }

  Future<void> updatePassphraseOptions(
    PassphraseGeneratorOptions Function(PassphraseGeneratorOptions) update,
  ) async {
    final current = state.value;
    if (current == null) return;
    await _applyAndPersist(
      current.preferences.copyWith(
        passphraseOptions: update(current.preferences.passphraseOptions),
      ),
    );
  }

  Future<void> _applyAndPersist(GeneratorPreferences preferences) async {
    await ref.read(generatorPreferencesStoreProvider).write(preferences);
    final current = state.value;
    try {
      final value = await _generate(preferences);
      state = AsyncValue<GeneratorState>.data(
        GeneratorState(preferences: preferences, generatedValue: value),
      );
    } catch (e) {
      // Keep the previous generated value on screen (e.g. all charsets
      // toggled off) rather than clearing it, surfacing the error instead.
      state = AsyncValue<GeneratorState>.data(
        GeneratorState(
          preferences: preferences,
          generatedValue: current?.generatedValue ?? '',
          error: e.toString(),
        ),
      );
    }
  }
}

final AsyncNotifierProvider<GeneratorController, GeneratorState>
generatorControllerProvider =
    AsyncNotifierProvider<GeneratorController, GeneratorState>(
      GeneratorController.new,
    );
