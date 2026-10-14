import 'dart:convert';

import '../../../data/database/app_database.dart';

/// Ein Band / Hefter der Gerichts- oder Beiakte (mit Eingangs- und Rückgabedatum).
class GerichtsaktenBand {
  String bandNr;
  String bezeichnung;
  int? seitenVon;
  int? seitenBis;
  DateTime? eingangAm;
  DateTime? rueckgabeAm;

  GerichtsaktenBand({
    this.bandNr = 'Bd. I',
    this.bezeichnung = 'Hauptakte',
    this.seitenVon,
    this.seitenBis,
    this.eingangAm,
    this.rueckgabeAm,
  });

  Map<String, dynamic> toJson() => {
        'bandNr': bandNr,
        'bezeichnung': bezeichnung,
        'seitenVon': seitenVon,
        'seitenBis': seitenBis,
        'eingangAm': eingangAm?.toIso8601String(),
        'rueckgabeAm': rueckgabeAm?.toIso8601String(),
      };

  static GerichtsaktenBand fromJson(Map<String, dynamic> m) =>
      GerichtsaktenBand(
        bandNr: m['bandNr']?.toString() ?? 'Bd. I',
        bezeichnung: m['bezeichnung']?.toString() ?? 'Hauptakte',
        seitenVon: (m['seitenVon'] as num?)?.toInt(),
        seitenBis: (m['seitenBis'] as num?)?.toInt(),
        eingangAm: m['eingangAm'] == null
            ? null
            : DateTime.tryParse(m['eingangAm'].toString()),
        rueckgabeAm: m['rueckgabeAm'] == null
            ? null
            : DateTime.tryParse(m['rueckgabeAm'].toString()),
      );
}

/// Erweiterte Akten-Stammdaten nach Vorbild des Gutachten Manager Enterprise.
///
/// Wird verlustfrei im `extras`-JSON-Feld von [Auftraege] gespeichert, sodass
/// bestehende Zusatzdaten (z. B. `kostenschaetzung`) erhalten bleiben und
/// der Firestore-Sync ohne Schema-Bruch funktioniert.
class AuftragGmExtras {
  // --- Versicherungsgutachten ---
  String schadensnummer;
  String versicherungsscheinNr;
  DateTime? schadenstag;
  String schadensursache;
  String versicherungsnehmer;
  String anspruchsteller;

  // --- Schiedsgutachten ---
  DateTime? schiedsvertragVom;
  String obmann;
  String parteiA;
  String parteiB;

  // --- Ortstermin-Zeiten & Umladungs-Tracking ---
  String ortsterminUhrzeitVon;
  String ortsterminUhrzeitBis;
  DateTime? ortsterminAltAm;
  String ortsterminAltUhrzeit;
  String ortsterminVerlegtGrund;

  // --- Gerichtssache: Streitwert & Aktenbände ---
  double? streitwert;
  List<GerichtsaktenBand> gerichtsaktenBaende;

  List<GerichtsaktenBand> get aktenbaende => gerichtsaktenBaende;

  AuftragGmExtras({
    this.schadensnummer = '',
    this.versicherungsscheinNr = '',
    this.schadenstag,
    this.schadensursache = '',
    this.versicherungsnehmer = '',
    this.anspruchsteller = '',
    this.schiedsvertragVom,
    this.obmann = '',
    this.parteiA = '',
    this.parteiB = '',
    this.ortsterminUhrzeitVon = '',
    this.ortsterminUhrzeitBis = '',
    this.ortsterminAltAm,
    this.ortsterminAltUhrzeit = '',
    this.ortsterminVerlegtGrund = '',
    this.streitwert,
    List<GerichtsaktenBand>? gerichtsaktenBaende,
    List<GerichtsaktenBand>? aktenbaende,
  }) : gerichtsaktenBaende = gerichtsaktenBaende ?? aktenbaende ?? [];

  /// Kurzform der Sache („Kläger ./. Beklagter" bzw. „Partei A ./. Partei B").
  String sacheFor(AuftraegeData a) {
    final k = (a.klaeger ?? '').trim();
    final b = (a.beklagter ?? '').trim();
    if (k.isNotEmpty || b.isNotEmpty) {
      return '${k.isEmpty ? "…" : k} ./. ${b.isEmpty ? "…" : b}';
    }
    if (parteiA.trim().isNotEmpty || parteiB.trim().isNotEmpty) {
      return '${parteiA.trim().isEmpty ? "…" : parteiA.trim()} ./. '
          '${parteiB.trim().isEmpty ? "…" : parteiB.trim()}';
    }
    if (versicherungsnehmer.trim().isNotEmpty) {
      return 'Schadenssache ${versicherungsnehmer.trim()}'
          '${schadensnummer.trim().isNotEmpty ? " (Schaden-Nr. ${schadensnummer.trim()})" : ""}';
    }
    return a.betreff ?? a.bezeichnung ?? a.aktenzeichen ?? '';
  }

  Map<String, dynamic> toMap() => {
        'schadensnummer': schadensnummer,
        'versicherungsscheinNr': versicherungsscheinNr,
        'schadenstag': schadenstag?.toIso8601String(),
        'schadensursache': schadensursache,
        'versicherungsnehmer': versicherungsnehmer,
        'anspruchsteller': anspruchsteller,
        'schiedsvertragVom': schiedsvertragVom?.toIso8601String(),
        'obmann': obmann,
        'parteiA': parteiA,
        'parteiB': parteiB,
        'ortsterminUhrzeitVon': ortsterminUhrzeitVon,
        'ortsterminUhrzeitBis': ortsterminUhrzeitBis,
        'ortsterminAltAm': ortsterminAltAm?.toIso8601String(),
        'ortsterminAltUhrzeit': ortsterminAltUhrzeit,
        'ortsterminVerlegtGrund': ortsterminVerlegtGrund,
        'streitwert': streitwert,
        'gerichtsaktenBaende':
            gerichtsaktenBaende.map((b) => b.toJson()).toList(),
      };

  static AuftragGmExtras fromAuftragExtras(String? rawExtras) =>
      fromExtras(rawExtras);

  static AuftragGmExtras fromExtras(String? rawExtras) {
    if (rawExtras == null || rawExtras.trim().isEmpty) {
      return AuftragGmExtras();
    }
    try {
      final root = jsonDecode(rawExtras);
      if (root is! Map<String, dynamic>) return AuftragGmExtras();
      final m = (root['gm'] is Map<String, dynamic>)
          ? root['gm'] as Map<String, dynamic>
          : root;
      final baendeRaw = m['gerichtsaktenBaende'];
      final baende = <GerichtsaktenBand>[];
      if (baendeRaw is List) {
        for (final item in baendeRaw) {
          if (item is Map<String, dynamic>) {
            baende.add(GerichtsaktenBand.fromJson(item));
          }
        }
      }
      return AuftragGmExtras(
        schadensnummer: m['schadensnummer']?.toString() ?? '',
        versicherungsscheinNr: m['versicherungsscheinNr']?.toString() ?? '',
        schadenstag: m['schadenstag'] == null
            ? null
            : DateTime.tryParse(m['schadenstag'].toString()),
        schadensursache: m['schadensursache']?.toString() ?? '',
        versicherungsnehmer: m['versicherungsnehmer']?.toString() ?? '',
        anspruchsteller: m['anspruchsteller']?.toString() ?? '',
        schiedsvertragVom: m['schiedsvertragVom'] == null
            ? null
            : DateTime.tryParse(m['schiedsvertragVom'].toString()),
        obmann: m['obmann']?.toString() ?? '',
        parteiA: m['parteiA']?.toString() ?? '',
        parteiB: m['parteiB']?.toString() ?? '',
        ortsterminUhrzeitVon: m['ortsterminUhrzeitVon']?.toString() ?? '',
        ortsterminUhrzeitBis: m['ortsterminUhrzeitBis']?.toString() ?? '',
        ortsterminAltAm: m['ortsterminAltAm'] == null
            ? null
            : DateTime.tryParse(m['ortsterminAltAm'].toString()),
        ortsterminAltUhrzeit: m['ortsterminAltUhrzeit']?.toString() ?? '',
        ortsterminVerlegtGrund: m['ortsterminVerlegtGrund']?.toString() ?? '',
        streitwert: (m['streitwert'] as num?)?.toDouble(),
        gerichtsaktenBaende: baende,
      );
    } catch (_) {
      return AuftragGmExtras();
    }
  }

  String mergeIntoAuftragExtras(String? existingExtras) =>
      mergeIntoExtras(existingExtras);

  /// Merged diese `AuftragGmExtras` unter dem Schlüssel `'gm'` in das
  /// bestehende `extras`-JSON der Akte.
  String mergeIntoExtras(String? existingExtras) {
    Map<String, dynamic> root = {};
    if (existingExtras != null && existingExtras.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(existingExtras);
        if (decoded is Map<String, dynamic>) {
          root = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
    }
    root['gm'] = toMap();
    return jsonEncode(root);
  }
}

extension AuftraegeDataGmX on AuftraegeData {
  AuftragGmExtras get gmExtras => AuftragGmExtras.fromExtras(extras);
}
