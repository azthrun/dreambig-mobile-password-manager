/// Discriminator for the kind of data a [VaultItem] holds.
///
/// GOALS_v2 §1.1: Phase 1 is credentials-only, but the schema must support
/// adding other item types (secure notes, cards, identities) later without
/// a breaking migration. Carrying this discriminator from day one — plus
/// keeping the payload for each type in its own typed shape — is how that's
/// achieved: a future type is a new enum value and a new payload class, not
/// a change to existing stored data.
enum VaultItemType {
  credential;

  static VaultItemType fromName(String name) {
    return VaultItemType.values.firstWhere(
      (value) => value.name == name,
      orElse: () => throw FormatException('Unknown VaultItemType: $name'),
    );
  }
}
