import 'dart:io';

import 'package:password_manager/domain/export/vault_csv_encoder.dart';
import 'package:password_manager/domain/models/vault_item.dart';
import 'package:path_provider/path_provider.dart';

/// Writes the plaintext vault CSV export (GOALS_v2 §3.3) to disk.
///
/// Kept as its own abstraction (mirroring `VaultLocalStore`/
/// `GeneratorPreferencesStore`'s pattern) so widget/unit tests can substitute
/// [InMemoryVaultCsvExporter] instead of touching `path_provider`'s platform
/// channel or the real filesystem.
///
/// **Security note**: the returned path points at a file containing
/// unencrypted secrets. Nothing in this class logs/prints the CSV content —
/// only the resulting file path is ever returned to a caller, and the
/// caller (`ExportCsvScreen`) is responsible for showing the user the
/// required "delete this file after use" warning.
abstract class VaultCsvExporter {
  /// Encodes [items] (active items only — see `encodeVaultItemsAsCsv`) and
  /// writes them to a new file, returning its path.
  Future<String> exportActiveItems(List<VaultItem> items);
}

/// Real implementation: one timestamped file per export, in the app's
/// private documents directory (not shared/public storage) — matching
/// `FileVaultLocalStore`/`FileGeneratorPreferencesStore`'s existing pattern
/// rather than adding a new package for a single file write.
class FileVaultCsvExporter implements VaultCsvExporter {
  FileVaultCsvExporter({Directory? directory, DateTime Function()? now})
    : _directoryOverride = directory,
      _now = now ?? DateTime.now;

  final Directory? _directoryOverride;
  final DateTime Function() _now;

  Future<File> _newFile() async {
    final dir = _directoryOverride ?? await getApplicationDocumentsDirectory();
    final stamp = _now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    return File('${dir.path}/vault_export_$stamp.csv');
  }

  @override
  Future<String> exportActiveItems(List<VaultItem> items) async {
    final csv = encodeVaultItemsAsCsv(items);
    final file = await _newFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(csv);
    return file.path;
  }
}

/// In-memory fake for tests, mirroring `InMemoryVaultLocalStore`. Records
/// the encoded CSV content against a fake path so tests can assert on it
/// directly without touching the filesystem.
class InMemoryVaultCsvExporter implements VaultCsvExporter {
  final Map<String, String> writtenFiles = <String, String>{};
  int _counter = 0;

  @override
  Future<String> exportActiveItems(List<VaultItem> items) async {
    final csv = encodeVaultItemsAsCsv(items);
    final path = 'memory://vault_export_${_counter++}.csv';
    writtenFiles[path] = csv;
    return path;
  }
}
