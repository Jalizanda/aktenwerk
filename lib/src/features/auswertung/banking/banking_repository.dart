import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';

class BankingRepository {
  BankingRepository(this._db);
  final AppDatabase _db;

  Stream<List<BankBewegungenData>> watchAll({String? konto}) {
    final q = _db.select(_db.bankBewegungen)
      ..orderBy([
        (t) =>
            OrderingTerm(expression: t.buchungsdatum, mode: OrderingMode.desc),
        (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
      ]);
    if (konto != null && konto.isNotEmpty) {
      q.where((t) => t.konto.equals(konto));
    }
    return q.watch();
  }

  Future<List<String>> distinctKonten() async {
    final rows = await (_db.selectOnly(_db.bankBewegungen, distinct: true)
          ..addColumns([_db.bankBewegungen.konto]))
        .get();
    return rows
        .map((r) => r.read(_db.bankBewegungen.konto) ?? '')
        .where((s) => s.isNotEmpty)
        .toList()
      ..sort();
  }

  Future<int> upsert(BankBewegungenCompanion entry) async {
    if (!entry.id.present) {
      return _db.into(_db.bankBewegungen).insert(
            entry.copyWith(updatedAt: Value(DateTime.now())),
          );
    }
    await (_db.update(_db.bankBewegungen)
          ..where((t) => t.id.equals(entry.id.value)))
        .write(entry.copyWith(updatedAt: Value(DateTime.now())));
    return entry.id.value;
  }

  Future<void> delete(int id) async {
    await (_db.delete(_db.bankBewegungen)
          ..where((t) => t.id.equals(id)))
        .go();
  }

  /// Importiert eine Liste von Bewegungen (z. B. aus CSV) und überspringt
  /// Duplikate anhand (Konto, Buchungsdatum, Betrag, Verwendungszweck).
  Future<int> importMany(List<BankBewegungenCompanion> bewegungen) async {
    var insertedCount = 0;
    for (final b in bewegungen) {
      final exists = await (_db.select(_db.bankBewegungen)
            ..where((t) =>
                t.konto.equalsNullable(b.konto.value) &
                t.buchungsdatum.equals(b.buchungsdatum.value) &
                t.betrag.equals(b.betrag.value) &
                t.verwendungszweck
                    .equalsNullable(b.verwendungszweck.value)))
          .get();
      if (exists.isNotEmpty) continue;
      await _db.into(_db.bankBewegungen).insert(b);
      insertedCount++;
    }
    return insertedCount;
  }
}

final bankingRepositoryProvider = Provider<BankingRepository>((ref) {
  return BankingRepository(ref.watch(appDatabaseProvider));
});

final bankBewegungenProvider =
    StreamProvider.family<List<BankBewegungenData>, String?>((ref, konto) {
  return ref.watch(bankingRepositoryProvider).watchAll(konto: konto);
});
