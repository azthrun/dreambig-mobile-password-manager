import 'package:flutter/services.dart' show rootBundle;

/// Loads newline-delimited wordlist assets bundled with the app.
///
/// Kept as a tiny seam (rather than calling `rootBundle` directly from
/// generator code) so tests can supply an in-memory word list instead of
/// exercising the asset bundle.
abstract class WordlistLoader {
  Future<List<String>> load(String assetPath);
}

class AssetWordlistLoader implements WordlistLoader {
  const AssetWordlistLoader();

  @override
  Future<List<String>> load(String assetPath) async {
    final raw = await rootBundle.loadString(assetPath);
    return raw
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
  }
}

/// In-memory fake for tests, mirroring `InMemorySecureStorageService` /
/// `InMemoryVaultLocalStore`.
///
/// Widget tests deliberately avoid exercising [AssetWordlistLoader]'s real
/// `rootBundle.loadString` call: asset-channel I/O triggered from a
/// non-widget-build context (e.g. an `AsyncNotifier.build()` reached via a
/// button tap/route push, as `GeneratorController` is) does not reliably
/// resolve within `flutter_test`'s fake-async pump loop — the same reason
/// every other real I/O dependency in this app (`SecureStorageService`,
/// `VaultLocalStore`, `BiometricAuthenticator`) is faked in tests rather
/// than exercised for real.
class FakeWordlistLoader implements WordlistLoader {
  const FakeWordlistLoader();

  static const List<String> _diceware = <String>[
    'apple', 'banana', 'cherry', 'date', 'elderberry', 'fig', 'grape',
    'honeydew', 'kiwi', 'lemon', 'mango', 'nectarine', 'orange', 'papaya',
    'quince', 'raspberry', 'strawberry', 'tangerine', 'ugli', 'vanilla',
    'walnut', 'yam', 'zucchini', 'apricot', 'blueberry', 'coconut', 'dragon',
    'eggplant', 'feather', 'garnet', 't-shirt', 'yo-yo',
  ];

  static const List<String> _commonPasswords = <String>[
    'password', '123456', 'qwerty', 'letmein', '111111', 'abc123', 'iloveyou',
    'admin', 'welcome', 'monkey',
  ];

  @override
  Future<List<String>> load(String assetPath) async {
    if (assetPath == WordlistAssets.dicewareWordlist) return _diceware;
    if (assetPath == WordlistAssets.commonPasswords) return _commonPasswords;
    return const <String>[];
  }
}

/// Asset paths for the wordlists bundled under `assets/wordlists/` (see
/// `pubspec.yaml`).
abstract final class WordlistAssets {
  /// The full EFF long wordlist (7,776 words — a 6-dice-roll Diceware
  /// list), used for passphrase generation. Chosen over a smaller curated
  /// list because it's a well-reviewed, publicly documented word list
  /// specifically designed for this purpose (each word maps to a unique
  /// 5-digit dice roll, minimum word-length/edit-distance criteria to
  /// reduce transcription errors) and is small enough (~70KB as plain
  /// text) to bundle directly as an asset — see
  /// `assets/wordlists/eff_diceware_wordlist.txt`.
  static const String dicewareWordlist =
      'assets/wordlists/eff_diceware_wordlist.txt';

  /// A curated list of ~500 of the most common leaked/weak passwords,
  /// used by [PasswordStrengthEstimator] as a fast "is this a well-known
  /// weak password" check. See
  /// `assets/wordlists/common_passwords.txt`.
  static const String commonPasswords =
      'assets/wordlists/common_passwords.txt';
}
