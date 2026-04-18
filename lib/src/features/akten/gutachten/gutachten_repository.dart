import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';

/// Standard-Abschnitte nach Zöller (13 Stück).
const gutachtenAbschnitte = <String>[
  'Sachlage und Auftrag',
  'Beteiligte',
  'Befund / Ortstermin',
  'Tatsächliche Feststellungen',
  'Ursachenermittlung',
  'Schadensbeschreibung',
  'Bewertung',
  'Kostenermittlung',
  'Zumutbarkeit / Verhältnismäßigkeit',
  'Gutachterliche Beurteilung',
  'Zusammenfassung',
  'Anlagen',
  'Schlusswort',
];

class GutachtenWithAuftrag {
  final GutachtenData gutachten;
  final AuftraegeData? auftrag;
  const GutachtenWithAuftrag(this.gutachten, this.auftrag);
}

class GutachtenRepository {
  GutachtenRepository(this._db);
  final AppDatabase _db;

  Stream<List<GutachtenWithAuftrag>> watchAll({String query = ''}) {
    final q = _db.select(_db.gutachten).join([
      leftOuterJoin(_db.auftraege,
          _db.auftraege.id.equalsExp(_db.gutachten.auftragId)),
    ]);
    if (query.trim().isNotEmpty) {
      final like = '%${query.trim().toLowerCase()}%';
      q.where(_db.gutachten.titel.lower().like(like) |
          _db.auftraege.aktenzeichen.lower().like(like));
    }
    q.orderBy([
      OrderingTerm(
          expression: _db.gutachten.updatedAt, mode: OrderingMode.desc),
    ]);
    return q.watch().map((rows) => rows
        .map((r) => GutachtenWithAuftrag(
            r.readTable(_db.gutachten), r.readTableOrNull(_db.auftraege)))
        .toList());
  }

  Future<GutachtenData?> byId(int id) =>
      (_db.select(_db.gutachten)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  Future<int> upsert(GutachtenCompanion entry) async {
    if (entry.id.present) {
      await (_db.update(_db.gutachten)
            ..where((t) => t.id.equals(entry.id.value)))
          .write(entry.copyWith(updatedAt: Value(DateTime.now())));
      return entry.id.value;
    }
    return _db.into(_db.gutachten).insert(entry);
  }

  Future<int> delete(int id) =>
      (_db.delete(_db.gutachten)..where((t) => t.id.equals(id))).go();
}

final gutachtenRepositoryProvider = Provider<GutachtenRepository>((ref) {
  return GutachtenRepository(ref.watch(appDatabaseProvider));
});

final gutachtenQueryProvider = StateProvider<String>((ref) => '');

final gutachtenListProvider =
    StreamProvider<List<GutachtenWithAuftrag>>((ref) {
  final q = ref.watch(gutachtenQueryProvider);
  return ref.watch(gutachtenRepositoryProvider).watchAll(query: q);
});

/// Helper: Abschnitts-Map ↔ JSON.
Map<String, String> abschnitteFromJson(String? json) {
  if (json == null || json.isEmpty) return {};
  final decoded = jsonDecode(json) as Map<String, dynamic>;
  return decoded.map((k, v) => MapEntry(k, v?.toString() ?? ''));
}

String abschnitteToJson(Map<String, String> map) => jsonEncode(map);
