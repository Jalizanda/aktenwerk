import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';

/// Weist neu angelegten Kunden/Lieferanten eine DATEV-Debitor- bzw.
/// Kreditor-Nummer zu.
///
/// Standard-Konvention (konfigurierbar):
/// - **Debitoren** (Kunden): `10000 + id` → 10001, 10002, …
/// - **Kreditoren** (Lieferanten): `70000 + id` → 70001, 70002, …
class DebitorKreditorService {
  DebitorKreditorService(this._db);
  final AppDatabase _db;

  static const int debitorStart = 10000;
  static const int kreditorStart = 70000;

  Future<String> nextDebitornummer() async {
    final rows = await (_db.selectOnly(_db.kunden)
          ..addColumns([_db.kunden.debitornummer])
          ..where(_db.kunden.debitornummer.isNotNull()))
        .get();
    var max = debitorStart;
    for (final r in rows) {
      final v = r.read(_db.kunden.debitornummer);
      final n = int.tryParse(v ?? '');
      if (n != null && n > max) max = n;
    }
    return (max + 1).toString();
  }

  Future<String> nextKreditornummer() async {
    final rows = await (_db.selectOnly(_db.lieferanten)
          ..addColumns([_db.lieferanten.kreditornummer])
          ..where(_db.lieferanten.kreditornummer.isNotNull()))
        .get();
    var max = kreditorStart;
    for (final r in rows) {
      final v = r.read(_db.lieferanten.kreditornummer);
      final n = int.tryParse(v ?? '');
      if (n != null && n > max) max = n;
    }
    return (max + 1).toString();
  }

  /// Belegt Debitornummern nachträglich bei allen Kunden ohne Nummer.
  Future<int> belegeAlleKunden() async {
    final kunden = await (_db.select(_db.kunden)
          ..where((t) => t.debitornummer.isNull()))
        .get();
    var next = int.parse(await nextDebitornummer());
    var i = 0;
    for (final k in kunden) {
      await (_db.update(_db.kunden)..where((t) => t.id.equals(k.id)))
          .write(KundenCompanion(debitornummer: Value(next.toString())));
      next++;
      i++;
    }
    return i;
  }

  Future<int> belegeAlleLieferanten() async {
    final ll = await (_db.select(_db.lieferanten)
          ..where((t) => t.kreditornummer.isNull()))
        .get();
    var next = int.parse(await nextKreditornummer());
    var i = 0;
    for (final l in ll) {
      await (_db.update(_db.lieferanten)..where((t) => t.id.equals(l.id)))
          .write(
              LieferantenCompanion(kreditornummer: Value(next.toString())));
      next++;
      i++;
    }
    return i;
  }
}

final debitorKreditorServiceProvider =
    Provider<DebitorKreditorService>((ref) {
  return DebitorKreditorService(ref.watch(appDatabaseProvider));
});
