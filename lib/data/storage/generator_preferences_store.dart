import 'dart:io';

import 'package:password_manager/domain/generator/generator_preferences.dart';
import 'package:path_provider/path_provider.dart';

/// Persists [GeneratorPreferences] locally (GOALS_v2 §1.2, item 5).
///
/// These are non-secret UI preferences (generator length/charset toggles,
/// last-used mode) — not vault secrets — so there's no requirement to route
/// them through `flutter_secure_storage`. Implemented as a small JSON file
/// in the app's private documents directory (the same
/// `path_provider`-resolved location and pattern `FileVaultLocalStore`
/// already uses for vault items) rather than adding a new
/// `shared_preferences` dependency for a single small value — one plugin
/// less to vet/maintain for the same effective guarantee (app-private,
/// not shared storage).
abstract class GeneratorPreferencesStore {
  Future<GeneratorPreferences?> read();
  Future<void> write(GeneratorPreferences preferences);
}

class FileGeneratorPreferencesStore implements GeneratorPreferencesStore {
  FileGeneratorPreferencesStore({Directory? directory})
    : _directoryOverride = directory;

  final Directory? _directoryOverride;

  Future<File> _file() async {
    final dir = _directoryOverride ?? await getApplicationDocumentsDirectory();
    return File('${dir.path}/generator_preferences.json');
  }

  @override
  Future<GeneratorPreferences?> read() async {
    final file = await _file();
    if (!await file.exists()) return null;
    final raw = await file.readAsString();
    if (raw.trim().isEmpty) return null;
    try {
      return GeneratorPreferences.decode(raw);
    } on FormatException {
      // Corrupt/old-shape preferences shouldn't block the generator screen
      // from opening — fall back to defaults.
      return null;
    }
  }

  @override
  Future<void> write(GeneratorPreferences preferences) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(preferences.encode());
  }
}

/// In-memory fake for tests, mirroring `InMemoryVaultLocalStore`.
class InMemoryGeneratorPreferencesStore implements GeneratorPreferencesStore {
  GeneratorPreferences? _stored;

  @override
  Future<GeneratorPreferences?> read() async => _stored;

  @override
  Future<void> write(GeneratorPreferences preferences) async {
    _stored = preferences;
  }
}
