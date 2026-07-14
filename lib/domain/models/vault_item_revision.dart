import 'package:password_manager/domain/models/credential_data.dart';

/// A prior version of a [VaultItem]'s payload, captured immediately before
/// an overwrite (GOALS_v2 §1.1: "maintain revision history ... so users can
/// recover after an overwrite").
///
/// Revisions are append-only and immutable once written; a "restore" action
/// creates a *new* current version (and, in turn, a new revision of what
/// was overwritten) rather than mutating history.
class VaultItemRevision {
  const VaultItemRevision({
    required this.eTag,
    required this.savedAt,
    required this.data,
  });

  /// The eTag the item had while this revision was current.
  final String eTag;

  final DateTime savedAt;
  final CredentialData data;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'eTag': eTag,
    'savedAt': savedAt.toIso8601String(),
    'data': data.toJson(),
  };

  factory VaultItemRevision.fromJson(Map<String, dynamic> json) {
    return VaultItemRevision(
      eTag: json['eTag'] as String,
      savedAt: DateTime.parse(json['savedAt'] as String),
      data: CredentialData.fromJson(json['data'] as Map<String, dynamic>),
    );
  }

  /// Defense-in-depth against secret leakage into logs/crash reports
  /// (GOALS_v2 §2.8) — relies on [data]'s own redacted `toString()`.
  @override
  String toString() => 'VaultItemRevision(eTag: $eTag, savedAt: $savedAt, data: $data)';
}
