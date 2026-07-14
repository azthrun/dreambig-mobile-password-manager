import 'package:password_manager/domain/models/credential_data.dart';
import 'package:password_manager/domain/models/vault_item_revision.dart';
import 'package:password_manager/domain/models/vault_item_type.dart';

/// How long a soft-deleted item remains recoverable from trash
/// (GOALS_v2 §1.1: "soft delete with a recovery window (e.g., 30-day
/// trash)").
const Duration kVaultItemTrashRetention = Duration(days: 30);

/// The full local representation of a vault item — everything
/// [VaultItemSummary] deliberately omits (actual decrypted content,
/// revision history), scoped to a single owning account.
///
/// [type] is the forward-compat discriminator described in GOALS_v2 §1.1;
/// only [VaultItemType.credential] is populated in Phase 1, but the shape
/// already supports adding sibling types without breaking this class or
/// its persisted form. [eTag] mirrors `VaultItemSummary.eTag` so the local
/// full item also carries the version token multi-device sync will need
/// later (GOALS_v2 §3.1).
class VaultItem {
  const VaultItem({
    required this.id,
    required this.userId,
    required this.type,
    required this.eTag,
    required this.createdAt,
    required this.updatedAt,
    required this.data,
    this.deletedAt,
    this.revisions = const <VaultItemRevision>[],
  });

  final String id;

  /// The signed-in account that owns this item. Enforced structurally, not
  /// just by convention: `LocalVaultRepository` is constructed per-session
  /// with a fixed `userId` and the local store keys/partitions records by
  /// it, so a repository instance can never read another account's items
  /// (see `lib/data/storage/vault_local_store.dart`).
  final String userId;

  final VaultItemType type;
  final String eTag;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Non-null while the item is soft-deleted. Within
  /// [kVaultItemTrashRetention] of this timestamp it's recoverable via
  /// trash; the item is out-of-scope for restore once older than that.
  final DateTime? deletedAt;

  /// Current payload. Phase 1 only ever populates [CredentialData]; a later
  /// phase adding item types would add sibling fields here rather than
  /// changing this one.
  final CredentialData data;

  /// Prior versions, most-recent-first, excluding the current [data].
  final List<VaultItemRevision> revisions;

  bool get isTrashed => deletedAt != null;

  /// Whether this item has aged out of the recovery window and should no
  /// longer be offered for restore (permanent purge itself is out of scope
  /// for Phase 2, per IMPLEMENTATION_PLAN.md).
  bool isPurgeable(DateTime now) {
    final deleted = deletedAt;
    if (deleted == null) return false;
    return now.difference(deleted) > kVaultItemTrashRetention;
  }

  VaultItem copyWith({
    String? eTag,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
    CredentialData? data,
    List<VaultItemRevision>? revisions,
  }) {
    return VaultItem(
      id: id,
      userId: userId,
      type: type,
      eTag: eTag ?? this.eTag,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
      data: data ?? this.data,
      revisions: revisions ?? this.revisions,
    );
  }

  /// Serializes everything except [id]/[userId]/[eTag]/timestamps, which
  /// the local store keeps as plaintext columns/fields for indexing —
  /// this is the part that gets encrypted (see `VaultItemCipher`).
  Map<String, dynamic> toEncryptablePayload() => <String, dynamic>{
    'type': type.name,
    'data': data.toJson(),
    'revisions': revisions.map((r) => r.toJson()).toList(),
  };

  static ({VaultItemType type, CredentialData data, List<VaultItemRevision> revisions})
  payloadFromJson(Map<String, dynamic> json) {
    return (
      type: VaultItemType.fromName(json['type'] as String),
      data: CredentialData.fromJson(json['data'] as Map<String, dynamic>),
      revisions: (json['revisions'] as List<dynamic>? ?? <dynamic>[])
          .map((e) => VaultItemRevision.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Defense-in-depth against secret leakage into logs/crash reports
  /// (GOALS_v2 §2.8). The default `Object.toString()` wouldn't have printed
  /// [data]'s fields anyway, but this makes the redaction explicit and
  /// future-proof against someone later adding a "real" toString here —
  /// [data]'s own `toString()` already redacts the secret.
  @override
  String toString() =>
      'VaultItem(id: $id, userId: $userId, type: $type, eTag: $eTag, '
      'data: $data, revisions: ${revisions.length} revision(s))';
}
