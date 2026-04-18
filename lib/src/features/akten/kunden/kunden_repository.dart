import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';

/// Mögliche Kundentypen (entspricht typ-Feld in der DB).
enum KundenTyp { privat, firma, anwalt, gericht, versicherung, behoerde }

extension KundenTypX on KundenTyp {
  String get dbValue => name;

  String get label => switch (this) {
        KundenTyp.privat => 'Privat',
        KundenTyp.firma => 'Firma',
        KundenTyp.anwalt => 'Anwalt',
        KundenTyp.gericht => 'Gericht',
        KundenTyp.versicherung => 'Versicherung',
        KundenTyp.behoerde => 'Behörde',
      };

  static KundenTyp fromDb(String? s) {
    return KundenTyp.values.firstWhere(
      (t) => t.name == s,
      orElse: () => KundenTyp.privat,
    );
  }
}

/// Hübsch formatierter Anzeigename aus Vor-/Nach-/Firmenname.
String kundeAnzeigename(KundenData k) {
  final name = [k.vorname, k.nachname].whereType<String>().join(' ').trim();
  final firma = k.firma?.trim();
  if ((firma ?? '').isNotEmpty && name.isNotEmpty) return '$firma – $name';
  if ((firma ?? '').isNotEmpty) return firma!;
  if (name.isNotEmpty) return name;
  return '(ohne Namen)';
}

class KundenRepository {
  KundenRepository(this._db);
  final AppDatabase _db;

  Stream<List<KundenData>> watchAll({
    String query = '',
    KundenTyp? typ,
  }) {
    final q = _db.select(_db.kunden);
    if (typ != null) {
      q.where((t) => t.typ.equals(typ.dbValue));
    }
    if (query.trim().isNotEmpty) {
      final like = '%${query.trim().toLowerCase()}%';
      q.where((t) =>
          t.firma.lower().like(like) |
          t.nachname.lower().like(like) |
          t.vorname.lower().like(like) |
          t.ort.lower().like(like) |
          t.plz.like(like) |
          t.email.lower().like(like));
    }
    q.orderBy([
      (t) => OrderingTerm(expression: t.nachname),
      (t) => OrderingTerm(expression: t.firma),
    ]);
    return q.watch();
  }

  Future<KundenData?> byId(int id) =>
      (_db.select(_db.kunden)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  Future<int> upsert(KundenCompanion entry) async {
    if (entry.id.present) {
      await (_db.update(_db.kunden)
            ..where((t) => t.id.equals(entry.id.value)))
          .write(entry.copyWith(updatedAt: Value(DateTime.now())));
      return entry.id.value;
    }
    return _db.into(_db.kunden).insert(entry);
  }

  Future<int> delete(int id) =>
      (_db.delete(_db.kunden)..where((t) => t.id.equals(id))).go();
}

final kundenRepositoryProvider = Provider<KundenRepository>((ref) {
  return KundenRepository(ref.watch(appDatabaseProvider));
});

/// Suchfilter-State: Freitext + optional Typ.
class KundenFilter {
  final String query;
  final KundenTyp? typ;
  const KundenFilter({this.query = '', this.typ});

  KundenFilter copyWith({String? query, KundenTyp? typ, bool clearTyp = false}) {
    return KundenFilter(
      query: query ?? this.query,
      typ: clearTyp ? null : (typ ?? this.typ),
    );
  }
}

final kundenFilterProvider =
    StateProvider<KundenFilter>((ref) => const KundenFilter());

final kundenListProvider = StreamProvider<List<KundenData>>((ref) {
  final f = ref.watch(kundenFilterProvider);
  return ref.watch(kundenRepositoryProvider).watchAll(
        query: f.query,
        typ: f.typ,
      );
});
