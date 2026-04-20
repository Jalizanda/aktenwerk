import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';

/// Vereinte Terminansicht aus mehreren Quellen:
/// - Erläuterungen (Gericht)
/// - Wiedervorlagen (faelligAm)
/// - Auftrag-Ortstermine (auftrag.ortsterminAm)
/// - Auftrag-Fristen (auftrag.fristAm)
class TerminEintrag {
  final DateTime zeitpunkt;
  final DateTime? ende;
  final String titel;
  final String typ;
  final String? ort;
  final String? telefon;
  final int? auftragId;
  final String? aktenzeichen;
  final int? quellId;

  const TerminEintrag({
    required this.zeitpunkt,
    required this.titel,
    required this.typ,
    this.ende,
    this.ort,
    this.telefon,
    this.auftragId,
    this.aktenzeichen,
    this.quellId,
  });

  DateTime get tag => DateTime(zeitpunkt.year, zeitpunkt.month, zeitpunkt.day);

  /// Wahr wenn ein Ortstermin-Eintrag (für Tel./Maps/Route).
  bool get istOrtstermin => typ == 'Ortstermin';
}

class TermineRepository {
  TermineRepository(this._db);
  final AppDatabase _db;

  Stream<List<TerminEintrag>> watchAll({DateTime? from, DateTime? to}) {
    final fromDate = from ?? DateTime.now().subtract(const Duration(days: 60));
    final toDate = to ?? DateTime.now().add(const Duration(days: 365));

    final erlStream = _db.select(_db.erlaeuterungen).join([
      leftOuterJoin(_db.auftraege,
          _db.auftraege.id.equalsExp(_db.erlaeuterungen.auftragId)),
    ]).watch();

    final wvStream = _db.select(_db.wiedervorlagen).join([
      leftOuterJoin(_db.auftraege,
          _db.auftraege.id.equalsExp(_db.wiedervorlagen.auftragId)),
    ]).watch();

    final auftragStream = _db.select(_db.auftraege).watch();

    return _combineLatest3(erlStream, wvStream, auftragStream).map((triple) {
      final out = <TerminEintrag>[];
      for (final r in triple.$1) {
        final e = r.readTable(_db.erlaeuterungen);
        final a = r.readTableOrNull(_db.auftraege);
        if (e.terminAm == null) continue;
        out.add(TerminEintrag(
          zeitpunkt: e.terminAm!,
          titel: 'Erläuterungstermin',
          typ: 'Erläuterung',
          ort: [e.gericht, e.ort]
              .whereType<String>()
              .where((s) => s.isNotEmpty)
              .join(' · '),
          auftragId: e.auftragId,
          aktenzeichen: a?.aktenzeichen,
          quellId: e.id,
        ));
      }
      for (final r in triple.$2) {
        final w = r.readTable(_db.wiedervorlagen);
        final a = r.readTableOrNull(_db.auftraege);
        out.add(TerminEintrag(
          zeitpunkt: w.faelligAm,
          ende: w.endeAm,
          titel: w.titel,
          typ: 'Wiedervorlage',
          ort: w.anlass,
          auftragId: w.auftragId,
          aktenzeichen: a?.aktenzeichen,
          quellId: w.id,
        ));
      }
      for (final a in triple.$3) {
        if (a.ortsterminAm != null) {
          out.add(TerminEintrag(
            zeitpunkt: a.ortsterminAm!,
            titel: a.betreff ?? a.bezeichnung ?? 'Ortstermin',
            typ: 'Ortstermin',
            ort: [a.objektStrasse, a.objektPlz, a.objektOrt]
                .whereType<String>()
                .where((s) => s.isNotEmpty)
                .join(', '),
            auftragId: a.id,
            aktenzeichen: a.aktenzeichen,
            quellId: a.id,
          ));
        }
        if (a.fristAm != null) {
          out.add(TerminEintrag(
            zeitpunkt: a.fristAm!,
            titel:
                'Frist: ${a.betreff ?? a.bezeichnung ?? a.aktenzeichen ?? ''}',
            typ: 'Frist',
            auftragId: a.id,
            aktenzeichen: a.aktenzeichen,
            quellId: a.id,
          ));
        }
      }
      final filtered = out
          .where((t) =>
              t.zeitpunkt.isAfter(fromDate) && t.zeitpunkt.isBefore(toDate))
          .toList()
        ..sort((x, y) => x.zeitpunkt.compareTo(y.zeitpunkt));
      return filtered;
    });
  }
}

/// Einfache combineLatest3-Implementation ohne rxdart.
Stream<(A, B, C)> _combineLatest3<A, B, C>(
    Stream<A> a, Stream<B> b, Stream<C> c) {
  late StreamController<(A, B, C)> controller;
  A? lastA;
  B? lastB;
  C? lastC;
  var hasA = false, hasB = false, hasC = false;
  final subs = <StreamSubscription>[];

  void emit() {
    if (hasA && hasB && hasC && !controller.isClosed) {
      controller.add((lastA as A, lastB as B, lastC as C));
    }
  }

  controller = StreamController<(A, B, C)>(
    onListen: () {
      subs.add(a.listen((v) {
        lastA = v;
        hasA = true;
        emit();
      }, onError: controller.addError));
      subs.add(b.listen((v) {
        lastB = v;
        hasB = true;
        emit();
      }, onError: controller.addError));
      subs.add(c.listen((v) {
        lastC = v;
        hasC = true;
        emit();
      }, onError: controller.addError));
    },
    onCancel: () async {
      for (final s in subs) {
        await s.cancel();
      }
    },
  );
  return controller.stream;
}

final termineRepositoryProvider = Provider<TermineRepository>((ref) {
  return TermineRepository(ref.watch(appDatabaseProvider));
});

final termineListProvider = StreamProvider<List<TerminEintrag>>((ref) {
  return ref.watch(termineRepositoryProvider).watchAll();
});
