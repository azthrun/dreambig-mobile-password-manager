/// Configuration for character-based password generation
/// (GOALS_v2 §1.2, item 1).
class PasswordGeneratorOptions {
  const PasswordGeneratorOptions({
    this.length = 16,
    this.useUppercase = true,
    this.useLowercase = true,
    this.useDigits = true,
    this.useSymbols = true,
    this.excludeAmbiguous = false,
  });

  /// Total number of characters to generate. Must be >= 1.
  final int length;

  final bool useUppercase;
  final bool useLowercase;
  final bool useDigits;
  final bool useSymbols;

  /// Excludes visually ambiguous characters (`0/O`, `1/l/I`) from the
  /// generated password, per GOALS_v2 §1.2.
  final bool excludeAmbiguous;

  bool get hasAnyCharacterSet =>
      useUppercase || useLowercase || useDigits || useSymbols;

  PasswordGeneratorOptions copyWith({
    int? length,
    bool? useUppercase,
    bool? useLowercase,
    bool? useDigits,
    bool? useSymbols,
    bool? excludeAmbiguous,
  }) {
    return PasswordGeneratorOptions(
      length: length ?? this.length,
      useUppercase: useUppercase ?? this.useUppercase,
      useLowercase: useLowercase ?? this.useLowercase,
      useDigits: useDigits ?? this.useDigits,
      useSymbols: useSymbols ?? this.useSymbols,
      excludeAmbiguous: excludeAmbiguous ?? this.excludeAmbiguous,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'length': length,
    'useUppercase': useUppercase,
    'useLowercase': useLowercase,
    'useDigits': useDigits,
    'useSymbols': useSymbols,
    'excludeAmbiguous': excludeAmbiguous,
  };

  factory PasswordGeneratorOptions.fromJson(Map<String, dynamic> json) {
    const defaults = PasswordGeneratorOptions();
    return PasswordGeneratorOptions(
      length: json['length'] as int? ?? defaults.length,
      useUppercase: json['useUppercase'] as bool? ?? defaults.useUppercase,
      useLowercase: json['useLowercase'] as bool? ?? defaults.useLowercase,
      useDigits: json['useDigits'] as bool? ?? defaults.useDigits,
      useSymbols: json['useSymbols'] as bool? ?? defaults.useSymbols,
      excludeAmbiguous:
          json['excludeAmbiguous'] as bool? ?? defaults.excludeAmbiguous,
    );
  }
}
