import 'dart:math';

import 'package:password_manager/domain/generator/passphrase_generator_options.dart';

/// Thrown when [PassphraseGenerator.generate] can't build a passphrase
/// (empty word list, or non-positive word count).
class PassphraseGeneratorException implements Exception {
  const PassphraseGeneratorException(this.message);
  final String message;

  @override
  String toString() => 'PassphraseGeneratorException: $message';
}

/// Diceware-style passphrase generator (GOALS_v2 §1.2, item 2).
///
/// Picks [PassphraseGeneratorOptions.wordCount] words independently and
/// uniformly at random from [wordlist] using a cryptographically secure
/// RNG ([Random.secure] by default — same rationale as
/// `PasswordGenerator`), joins them with the configured separator, and
/// optionally capitalizes each word and/or appends a random digit.
class PassphraseGenerator {
  PassphraseGenerator({required this.wordlist, Random? random})
    : _random = random ?? Random.secure();

  /// The word pool to draw from — see `WordlistAssets.dicewareWordlist`
  /// for the production source (the EFF long wordlist).
  final List<String> wordlist;

  final Random _random;

  String generate(PassphraseGeneratorOptions options) {
    if (options.wordCount <= 0) {
      throw const PassphraseGeneratorException(
        'Word count must be positive.',
      );
    }
    if (wordlist.isEmpty) {
      throw const PassphraseGeneratorException('Word list is empty.');
    }

    final words = List<String>.generate(options.wordCount, (_) {
      final word = wordlist[_random.nextInt(wordlist.length)];
      return options.capitalizeWords ? _capitalize(word) : word;
    });

    if (options.appendNumber) {
      words.add(_random.nextInt(10).toString());
    }

    return words.join(options.separator);
  }

  String _capitalize(String word) {
    if (word.isEmpty) return word;
    return word[0].toUpperCase() + word.substring(1);
  }
}
