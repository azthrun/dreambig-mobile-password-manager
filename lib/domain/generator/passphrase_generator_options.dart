/// Configuration for Diceware-style passphrase generation
/// (GOALS_v2 §1.2, item 2).
class PassphraseGeneratorOptions {
  const PassphraseGeneratorOptions({
    this.wordCount = 5,
    this.separator = '-',
    this.capitalizeWords = false,
    this.appendNumber = false,
  });

  /// Number of words in the passphrase. Must be >= 1.
  final int wordCount;

  /// Character(s) placed between words (common Diceware UX allows an empty
  /// separator too).
  final String separator;

  /// Capitalizes the first letter of each word.
  final bool capitalizeWords;

  /// Appends a random single digit (0-9) to the end of the passphrase,
  /// separated the same way as the words — a common Diceware convention
  /// for satisfying "must contain a digit" site policies.
  final bool appendNumber;

  PassphraseGeneratorOptions copyWith({
    int? wordCount,
    String? separator,
    bool? capitalizeWords,
    bool? appendNumber,
  }) {
    return PassphraseGeneratorOptions(
      wordCount: wordCount ?? this.wordCount,
      separator: separator ?? this.separator,
      capitalizeWords: capitalizeWords ?? this.capitalizeWords,
      appendNumber: appendNumber ?? this.appendNumber,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'wordCount': wordCount,
    'separator': separator,
    'capitalizeWords': capitalizeWords,
    'appendNumber': appendNumber,
  };

  factory PassphraseGeneratorOptions.fromJson(Map<String, dynamic> json) {
    const defaults = PassphraseGeneratorOptions();
    return PassphraseGeneratorOptions(
      wordCount: json['wordCount'] as int? ?? defaults.wordCount,
      separator: json['separator'] as String? ?? defaults.separator,
      capitalizeWords:
          json['capitalizeWords'] as bool? ?? defaults.capitalizeWords,
      appendNumber: json['appendNumber'] as bool? ?? defaults.appendNumber,
    );
  }
}
