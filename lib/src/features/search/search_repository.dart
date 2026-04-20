import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../data/database/database_provider.dart';

enum SearchEntity {
  kunde,
  auftrag,
  rechnung,
  angebot,
  gutachten,
  anschreiben,
  artikel,
  norm,
  textbaustein,
  lieferant,
  eingangsrechnung,
}

extension SearchEntityX on SearchEntity {
  String get label => switch (this) {
        SearchEntity.kunde => 'Auftraggeber',
        SearchEntity.auftrag => 'Auftrag',
        SearchEntity.rechnung => 'Rechnung',
        SearchEntity.angebot => 'Angebot',
        SearchEntity.gutachten => 'Gutachten',
        SearchEntity.anschreiben => 'Anschreiben',
        SearchEntity.artikel => 'Artikel',
        SearchEntity.norm => 'Norm',
        SearchEntity.textbaustein => 'Textbaustein',
        SearchEntity.lieferant => 'Lieferant',
        SearchEntity.eingangsrechnung => 'Eingangsrechnung',
      };

  String get route => switch (this) {
        SearchEntity.kunde => '/kunden',
        SearchEntity.auftrag => '/auftraege',
        SearchEntity.rechnung => '/rechnungen',
        SearchEntity.angebot => '/angebote',
        SearchEntity.gutachten => '/gutachten',
        SearchEntity.anschreiben => '/anschreiben',
        SearchEntity.artikel => '/artikel',
        SearchEntity.norm => '/normen',
        SearchEntity.textbaustein => '/textbausteine',
        SearchEntity.lieferant => '/lieferanten',
        SearchEntity.eingangsrechnung => '/eingangsrechnungen',
      };
}

class SearchHit {
  final SearchEntity entity;
  final int id;
  final String title;
  final String? subtitle;
  const SearchHit(this.entity, this.id, this.title, this.subtitle);
}

class SearchRepository {
  SearchRepository(this._db);
  final AppDatabase _db;

  Future<List<SearchHit>> search(String query, {int perBucket = 5}) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    final like = '%${q.toLowerCase()}%';
    final hits = <SearchHit>[];

    // Kunden
    final kList = await (_db.select(_db.kunden)
          ..where((t) =>
              t.firma.lower().like(like) |
              t.nachname.lower().like(like) |
              t.vorname.lower().like(like) |
              t.ort.lower().like(like) |
              t.email.lower().like(like))
          ..limit(perBucket))
        .get();
    for (final k in kList) {
      final name =
          [k.vorname, k.nachname].whereType<String>().join(' ').trim();
      final title = (k.firma ?? '').isNotEmpty
          ? k.firma!
          : (name.isNotEmpty ? name : '(ohne Namen)');
      hits.add(SearchHit(SearchEntity.kunde, k.id, title,
          [k.plz, k.ort].whereType<String>().join(' ').trim()));
    }

    // Aufträge
    final aList = await (_db.select(_db.auftraege)
          ..where((t) =>
              t.aktenzeichen.lower().like(like) |
              t.bezeichnung.lower().like(like) |
              t.objektOrt.lower().like(like) |
              t.gerichtsAktenzeichen.lower().like(like))
          ..limit(perBucket))
        .get();
    for (final a in aList) {
      hits.add(SearchHit(
        SearchEntity.auftrag,
        a.id,
        a.aktenzeichen ?? '(o. A.)',
        a.bezeichnung,
      ));
    }

    // Rechnungen
    final rList = await (_db.select(_db.rechnungen)
          ..where((t) => t.rechnungsnummer.lower().like(like))
          ..limit(perBucket))
        .get();
    for (final r in rList) {
      hits.add(SearchHit(
        SearchEntity.rechnung,
        r.id,
        'Rechnung ${r.rechnungsnummer ?? ''}',
        'netto ${r.netto.toStringAsFixed(2)} €',
      ));
    }

    // Angebote
    final angList = await (_db.select(_db.angebote)
          ..where((t) =>
              t.angebotsnummer.lower().like(like) |
              t.betreff.lower().like(like))
          ..limit(perBucket))
        .get();
    for (final a in angList) {
      hits.add(SearchHit(SearchEntity.angebot, a.id,
          'Angebot ${a.angebotsnummer ?? ''}', a.betreff));
    }

    // Gutachten
    final gList = await (_db.select(_db.gutachten)
          ..where((t) => t.titel.lower().like(like))
          ..limit(perBucket))
        .get();
    for (final g in gList) {
      hits.add(SearchHit(
          SearchEntity.gutachten, g.id, g.titel ?? '(ohne Titel)', null));
    }

    // Anschreiben
    final anList = await (_db.select(_db.anschreiben)
          ..where((t) => t.betreff.lower().like(like))
          ..limit(perBucket))
        .get();
    for (final a in anList) {
      hits.add(SearchHit(SearchEntity.anschreiben, a.id,
          a.betreff ?? '(ohne Betreff)', null));
    }

    // Artikel
    final artList = await (_db.select(_db.artikel)
          ..where((t) =>
              t.bezeichnung.lower().like(like) |
              t.nummer.lower().like(like) |
              t.kategorie.lower().like(like))
          ..limit(perBucket))
        .get();
    for (final a in artList) {
      hits.add(SearchHit(SearchEntity.artikel, a.id, a.bezeichnung,
          '${a.einzelpreis.toStringAsFixed(2)} €'));
    }

    // Normen
    final nList = await (_db.select(_db.normen)
          ..where((t) =>
              t.nummer.lower().like(like) | t.titel.lower().like(like))
          ..limit(perBucket))
        .get();
    for (final n in nList) {
      hits.add(SearchHit(SearchEntity.norm, n.id, n.nummer, n.titel));
    }

    // Textbausteine
    final tList = await (_db.select(_db.textbausteine)
          ..where((t) =>
              t.titel.lower().like(like) | t.inhalt.lower().like(like))
          ..limit(perBucket))
        .get();
    for (final t in tList) {
      hits.add(SearchHit(SearchEntity.textbaustein, t.id, t.titel,
          t.kategorie));
    }

    // Lieferanten
    final lList = await (_db.select(_db.lieferanten)
          ..where((t) =>
              t.firma.lower().like(like) |
              t.ort.lower().like(like) |
              t.email.lower().like(like))
          ..limit(perBucket))
        .get();
    for (final l in lList) {
      hits.add(SearchHit(SearchEntity.lieferant, l.id, l.firma,
          [l.plz, l.ort].whereType<String>().join(' ').trim()));
    }

    // Eingangsrechnungen
    final eList = await (_db.select(_db.eingangsrechnungen)
          ..where((t) =>
              t.rechnungsnummer.lower().like(like) |
              t.beschreibung.lower().like(like) |
              t.kategorie.lower().like(like))
          ..limit(perBucket))
        .get();
    for (final e in eList) {
      hits.add(SearchHit(
        SearchEntity.eingangsrechnung,
        e.id,
        'ER ${e.rechnungsnummer ?? ''}',
        '${e.brutto.toStringAsFixed(2)} €',
      ));
    }

    return hits;
  }
}

final searchRepositoryProvider = Provider<SearchRepository>((ref) {
  return SearchRepository(ref.watch(appDatabaseProvider));
});
