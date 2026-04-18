import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';

/// Zentrale Schlüssel für typisierte Einstellungen.
/// Andere Module sollten diese Konstanten nutzen statt hard-coded Strings.
class SettingsKeys {
  SettingsKeys._();

  static const nummernkreisAktenzeichen = 'nummernkreis.aktenzeichen';
  static const nummernkreisRechnung = 'nummernkreis.rechnung';
  static const nummernkreisAngebot = 'nummernkreis.angebot';

  static const standardStundensatz = 'standard.stundensatz';
  static const standardUstSatz = 'standard.ust_satz';

  static const theme = 'ui.theme'; // 'system' | 'light' | 'dark'

  static const rechnungFusstext = 'rechnung.fusstext';
  static const angebotFusstext = 'angebot.fusstext';
}

class EinstellungenRepository {
  EinstellungenRepository(this._db);
  final AppDatabase _db;

  Future<String?> get(String key) async {
    final row = await (_db.select(_db.einstellungen)
          ..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.wert;
  }

  Future<String> getOr(String key, String fallback) async =>
      (await get(key)) ?? fallback;

  Future<double?> getDouble(String key) async {
    final v = await get(key);
    if (v == null) return null;
    return double.tryParse(v.replaceAll(',', '.'));
  }

  Future<void> set(String key, String? value) async {
    final now = DateTime.now();
    if (value == null || value.isEmpty) {
      await (_db.delete(_db.einstellungen)
            ..where((t) => t.key.equals(key)))
          .go();
      return;
    }
    await _db.into(_db.einstellungen).insertOnConflictUpdate(
          EinstellungenCompanion.insert(
            key: key,
            wert: Value(value),
            updatedAt: Value(now),
          ),
        );
  }

  Stream<Map<String, String>> watchAll() {
    return _db.select(_db.einstellungen).watch().map((rows) => {
          for (final r in rows) r.key: r.wert ?? '',
        });
  }
}

final einstellungenRepositoryProvider =
    Provider<EinstellungenRepository>((ref) {
  return EinstellungenRepository(ref.watch(appDatabaseProvider));
});

final einstellungenProvider = StreamProvider<Map<String, String>>((ref) {
  return ref.watch(einstellungenRepositoryProvider).watchAll();
});
