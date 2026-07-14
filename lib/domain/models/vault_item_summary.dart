/// Lightweight, sync-oriented view of a vault item.
///
/// Deliberately does not carry any decrypted fields — the server (and this
/// summary) only ever sees ciphertext. The [eTag] exists from Phase 0 so
/// optimistic-concurrency sync can be layered on later without a data model
/// migration (GOALS_v2 §3.1).
class VaultItemSummary {
  const VaultItemSummary({
    required this.itemId,
    required this.eTag,
    required this.updatedAt,
    required this.isDeleted,
  });

  final String itemId;
  final String eTag;
  final DateTime updatedAt;

  /// True while the item is within its soft-delete/trash window.
  final bool isDeleted;
}
