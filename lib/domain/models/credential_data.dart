/// The Phase 1 (credentials-only) payload shape for a [VaultItemType.credential]
/// vault item, per GOALS_v2 §1.1: identifier (username/email), secret
/// (password), site/app name, URL, notes, and tags/folder.
///
/// Kept as its own class (rather than inline fields on `VaultItem`) so that
/// adding a sibling payload type later (e.g. `SecureNoteData`, `CardData`)
/// is additive, not a change to this type or its serialization.
class CredentialData {
  const CredentialData({
    required this.identifier,
    required this.secret,
    this.siteName = '',
    this.url = '',
    this.notes = '',
    this.tags = const <String>[],
  });

  /// Username or email used to sign in to the site/app.
  final String identifier;

  /// The password itself. Plaintext in memory only — always encrypted
  /// before touching disk (see `VaultItemCipher`).
  final String secret;

  final String siteName;
  final String url;
  final String notes;
  final List<String> tags;

  CredentialData copyWith({
    String? identifier,
    String? secret,
    String? siteName,
    String? url,
    String? notes,
    List<String>? tags,
  }) {
    return CredentialData(
      identifier: identifier ?? this.identifier,
      secret: secret ?? this.secret,
      siteName: siteName ?? this.siteName,
      url: url ?? this.url,
      notes: notes ?? this.notes,
      tags: tags ?? this.tags,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'identifier': identifier,
    'secret': secret,
    'siteName': siteName,
    'url': url,
    'notes': notes,
    'tags': tags,
  };

  factory CredentialData.fromJson(Map<String, dynamic> json) {
    return CredentialData(
      identifier: json['identifier'] as String? ?? '',
      secret: json['secret'] as String? ?? '',
      siteName: json['siteName'] as String? ?? '',
      url: json['url'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
      tags:
          (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList() ??
          const <String>[],
    );
  }

  /// Defense-in-depth against secret leakage into logs/crash reports
  /// (GOALS_v2 §2.8): explicitly redacts [secret] (and [notes], which can
  /// also hold sensitive free text) rather than relying on the default
  /// `Object.toString()`, in case this ever gets interpolated into an
  /// error message or log line by a future change.
  @override
  String toString() =>
      'CredentialData(identifier: $identifier, secret: <redacted>, '
      'siteName: $siteName, url: $url, notes: <redacted>, tags: $tags)';
}
