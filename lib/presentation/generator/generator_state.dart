import 'package:password_manager/domain/generator/generator_preferences.dart';

/// UI state for the generator screen/sheet.
class GeneratorState {
  const GeneratorState({
    required this.preferences,
    required this.generatedValue,
    this.error,
  });

  final GeneratorPreferences preferences;
  final String generatedValue;

  /// Set when the current [preferences] combination can't produce a value
  /// (e.g. every character set toggled off) — surfaced in the UI instead of
  /// silently keeping a stale value.
  final String? error;

  GeneratorState copyWith({
    GeneratorPreferences? preferences,
    String? generatedValue,
    String? error,
    bool clearError = false,
  }) {
    return GeneratorState(
      preferences: preferences ?? this.preferences,
      generatedValue: generatedValue ?? this.generatedValue,
      error: clearError ? null : (error ?? this.error),
    );
  }
}
