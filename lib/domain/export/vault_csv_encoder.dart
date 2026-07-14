import 'package:password_manager/domain/models/vault_item.dart';

/// Column order for the CSV export (GOALS_v2 §3.3). Kept as a constant so
/// the header row and each data row are built from the exact same list.
const List<String> kVaultCsvColumns = <String>[
  'identifier',
  'secret',
  'siteName',
  'url',
  'notes',
  'tags',
];

/// Pure CSV-building logic for the plaintext vault export (GOALS_v2 §3.3),
/// deliberately separated from any file I/O (`VaultCsvExporter`) so it can
/// be unit tested without touching `path_provider`/the filesystem, mirroring
/// how `PasswordGenerator`'s pure logic is split from its UI.
///
/// **Only active, non-trashed items are included** — soft-deleted (trashed)
/// items are excluded even if the caller's list contains them, so this
/// function is safe to call with either `VaultRepository.listActive()`'s
/// result or an unfiltered list.
///
/// This is a plaintext-secrets operation by nature (the whole point of CSV
/// export is a human-readable file containing real passwords) — callers
/// must gate calling this behind re-authentication and an explicit
/// on-disk-plaintext warning (see `ExportCsvScreen`), and must never log or
/// print the returned string.
String encodeVaultItemsAsCsv(List<VaultItem> items) {
  final buffer = StringBuffer();
  buffer.write(_csvRow(kVaultCsvColumns));
  buffer.write('\r\n');
  for (final item in items) {
    if (item.isTrashed) continue;
    buffer.write(
      _csvRow(<String>[
        item.data.identifier,
        item.data.secret,
        item.data.siteName,
        item.data.url,
        item.data.notes,
        item.data.tags.join(';'),
      ]),
    );
    buffer.write('\r\n');
  }
  return buffer.toString();
}

String _csvRow(List<String> fields) => fields.map(_csvField).join(',');

/// RFC 4180-style escaping: any field containing a comma, double quote, or
/// line break is wrapped in double quotes, with internal double quotes
/// doubled.
String _csvField(String value) {
  final needsQuoting =
      value.contains(',') ||
      value.contains('"') ||
      value.contains('\n') ||
      value.contains('\r');
  if (!needsQuoting) return value;
  final escaped = value.replaceAll('"', '""');
  return '"$escaped"';
}
