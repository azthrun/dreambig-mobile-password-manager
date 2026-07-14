import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/domain/generator/passphrase_generator.dart';
import 'package:password_manager/domain/generator/passphrase_generator_options.dart';

void main() {
  final wordlist = <String>['apple', 'banana', 'cherry', 'date', 'elderberry'];

  group('PassphraseGenerator', () {
    test('produces the requested word count', () {
      final generator = PassphraseGenerator(wordlist: wordlist);
      for (final count in <int>[1, 3, 5, 8]) {
        final phrase = generator.generate(
          PassphraseGeneratorOptions(wordCount: count),
        );
        // Default separator is '-'.
        expect(phrase.split('-').length, count);
      }
    });

    test('every word in the result comes from the supplied wordlist', () {
      final generator = PassphraseGenerator(wordlist: wordlist);
      final phrase = generator.generate(
        const PassphraseGeneratorOptions(wordCount: 6),
      );
      for (final word in phrase.split('-')) {
        expect(wordlist, contains(word));
      }
    });

    test('uses the configured separator', () {
      final generator = PassphraseGenerator(wordlist: wordlist);
      final phrase = generator.generate(
        const PassphraseGeneratorOptions(wordCount: 3, separator: '_'),
      );
      expect(phrase.split('_').length, 3);
      expect(phrase.contains('-'), isFalse);
    });

    test('capitalizeWords capitalizes each word', () {
      final generator = PassphraseGenerator(wordlist: wordlist);
      final phrase = generator.generate(
        const PassphraseGeneratorOptions(
          wordCount: 4,
          capitalizeWords: true,
        ),
      );
      for (final word in phrase.split('-')) {
        expect(word[0], word[0].toUpperCase());
      }
    });

    test('appendNumber adds exactly one trailing digit segment', () {
      final generator = PassphraseGenerator(wordlist: wordlist);
      final phrase = generator.generate(
        const PassphraseGeneratorOptions(wordCount: 3, appendNumber: true),
      );
      final parts = phrase.split('-');
      expect(parts.length, 4);
      expect(RegExp(r'^[0-9]$').hasMatch(parts.last), isTrue);
    });

    test('throws for an empty wordlist', () {
      final generator = PassphraseGenerator(wordlist: const <String>[]);
      expect(
        () => generator.generate(const PassphraseGeneratorOptions()),
        throwsA(isA<PassphraseGeneratorException>()),
      );
    });

    test('throws for non-positive word count', () {
      final generator = PassphraseGenerator(wordlist: wordlist);
      expect(
        () => generator.generate(
          const PassphraseGeneratorOptions(wordCount: 0),
        ),
        throwsA(isA<PassphraseGeneratorException>()),
      );
    });

    test('statistical sanity: repeated calls are not identical', () {
      // Use a larger wordlist so collisions across 30 draws of 6 words are
      // implausible unless the RNG is broken.
      final bigWordlist = List<String>.generate(200, (i) => 'word$i');
      final generator = PassphraseGenerator(wordlist: bigWordlist);
      final results = List<String>.generate(
        30,
        (_) => generator.generate(const PassphraseGeneratorOptions(wordCount: 6)),
      );
      expect(results.toSet().length, results.length);
    });
  });
}
