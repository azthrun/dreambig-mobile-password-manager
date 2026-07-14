/// Which generation mode the generator screen is in — character-based
/// (GOALS_v2 §1.2 item 1) or Diceware-style passphrase (item 2).
enum GeneratorMode {
  characters,
  passphrase;

  String toJson() => name;

  static GeneratorMode fromJson(String? value) {
    return GeneratorMode.values.firstWhere(
      (m) => m.name == value,
      orElse: () => GeneratorMode.characters,
    );
  }
}
