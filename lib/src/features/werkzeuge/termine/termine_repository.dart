import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';

/// Vereinte Terminansicht aus mehreren Quellen.
class TerminEintrag {
  final DateTime zeitpunkt;
  final String titel;
  final String typ;
  final String? ort;
  final int? auftragId;
  final String? aktenzeichen;
  final int? quellId;

  const TerminEintrag({
    required this.zeitpunkt,
    required this.titel,
    required this.typ,
    this.ort,
    this.auftragId,
    this.aktenzeichen,
    this.quellId,
  });
}

class TermineRepository {
  TermineRepository(this._db);
  final AppDatabase _db;

  Stream<List<TerminEintrag>> watchAll({DateTime? from, DateTime? to}) {
    final fromDate = from ?? DateTime.now().subtract(const Duration(days: 30));
    final toDate = to ?? DateTime.now().add(const Duration(days: 365));

    // Alle drei relevanten Streams zusammenführen.
    final erl = _db
        .select(_db.erlaeuterungen)
        .join([
          leftOuterJoin(_db.auftraege,
              _db.auftraege.id.equalsExp(_db.erlaeuterungen.auftragId)),
        ])
        .watch()
        .map((rows) => rows
            .map((r) {
              final e = r.readTable(_db.erlaeuterungen);
              final a = r.readTableOrNull(_db.auftraege);
              if (e.terminAm == null) return null;
              return TerminEintrag(
                zeitpunkt: e.terminAm!,
                titel: 'Erläuterungstermin',
                typ: 'Erläuterung',
                ort: [e.gericht, e.ort].whereType<String>().join(' · '),
                auftragId: e.auftragId,
                aktenzeichen: a?.aktenzeichen,
                quellId: e.id,
              );
            })
            .whereType<TerminEintrag>()
            .toList());

    final wv = _db
        .select(_db.wiedervorlagen)
        .join([
          leftOuterJoin(_db.auftraege,
              _db.auftraege.id.equalsExp(_db.wiedervorlagen.auftragId)),
        ])
        .watch()
        .map((rows) => rows.map((r) {
              final w = r.readTable(_db.wiedervorlagen);
              final a = r.readTableOrNull(_db.auftraege);
              return TerminEintrag(
                zeitpunkt: w.faelligAm,
                titel: w.titel,
                typ: 'Wiedervorlage',
                auftragId: w.auftragId,
                aktenzeichen: a?.aktenzeichen,
                quellId: w.id,
              );
            }).toList());

    // Verknüpft beide Streams zu einem gemeinsamen.
    return erl.asyncMap((erlList) async {
      final wvList = await wv.first;
      final merged = <TerminEintrag>[...erlList, ...wvList]
          .where((t) =>
              t.zeitpunkt.isAfter(fromDate) && t.zeitpunkt.isBefore(toDate))
          .toList()
        ..sort((a, b) => a.zeitpunkt.compareTo(b.zeitpunkt));
      return merged;
    });
  }
}

final termineRepositoryProvider = Provider<TermineRepository>((ref) {
  return TermineRepository(ref.watch(appDatabaseProvider));
});

final termineListProvider = StreamProvider<List<TerminEintrag>>((ref) {
  return ref.watch(termineRepositoryProvider).watchAll();
});
