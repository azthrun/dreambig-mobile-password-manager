import 'dart:convert';

import 'package:password_manager/domain/generator/generator_mode.dart';
import 'package:password_manager/domain/generator/passphrase_generator_options.dart';
import 'package:password_manager/domain/generator/password_generator_options.dart';

/// Non-secret UI preferences for the password generator (GOALS_v2 §1.2,
/// item 5) — length/charset toggles, passphrase options, and last-used
/// mode. Persisted locally as a UX convenience (see
/// `GeneratorPreferencesStore`) so the user's settings survive across
/// sessions; contains no vault secrets, so `SharedPreferences` is an
/// appropriate store (unlike vault data, which always goes through
/// `flutter_secure_storage`).
class GeneratorPreferences {
  const GeneratorPreferences({
    this.mode = GeneratorMode.characters,
    this.passwordOptions = const PasswordGeneratorOptions(),
    this.passphraseOptions = const PassphraseGeneratorOptions(),
  });

  final GeneratorMode mode;
  final PasswordGeneratorOptions passwordOptions;
  final PassphraseGeneratorOptions passphraseOptions;

  GeneratorPreferences copyWith({
    GeneratorMode? mode,
    PasswordGeneratorOptions? passwordOptions,
    PassphraseGeneratorOptions? passphraseOptions,
  }) {
    return GeneratorPreferences(
      mode: mode ?? this.mode,
      passwordOptions: passwordOptions ?? this.passwordOptions,
      passphraseOptions: passphraseOptions ?? this.passphraseOptions,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'mode': mode.toJson(),
    'passwordOptions': passwordOptions.toJson(),
    'passphraseOptions': passphraseOptions.toJson(),
  };

  factory GeneratorPreferences.fromJson(Map<String, dynamic> json) {
    return GeneratorPreferences(
      mode: GeneratorMode.fromJson(json['mode'] as String?),
      passwordOptions: PasswordGeneratorOptions.fromJson(
        (json['passwordOptions'] as Map<String, dynamic>?) ??
            const <String, dynamic>{},
      ),
      passphraseOptions: PassphraseGeneratorOptions.fromJson(
        (json['passphraseOptions'] as Map<String, dynamic>?) ??
            const <String, dynamic>{},
      ),
    );
  }

  String encode() => jsonEncode(toJson());

  static GeneratorPreferences decode(String raw) {
    return GeneratorPreferences.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
  }
}
