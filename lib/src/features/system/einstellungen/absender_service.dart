import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../benutzer/benutzer_repository.dart';
import 'einstellungen_repository.dart';

/// Liest Absender-Daten aus den Einstellungen + fällt auf den aktiven
/// Benutzer zurück, wenn ein Feld dort nicht gesetzt ist.
///
/// Wird vom PDF-Generator verwendet, damit Einstellungen (Logo, Bank,
/// Bestellungstext, Fußzeile) in Rechnungs-/Angebots-PDFs erscheinen.
Future<BenutzerData> absenderFromSettings(WidgetRef ref) async {
  final einstellungen = ref.read(einstellungenProvider).valueOrNull ??
      <String, String>{};
  final benutzer = await ref.read(benutzerRepositoryProvider).getActive();

  String? v(String k) {
    final s = einstellungen[k];
    return (s == null || s.isEmpty) ? null : s;
  }

  // Logo als data:-URI zusammenbauen.
  String? logoDataUri;
  final logoBase64 = v(SettingsKeys.firmaLogoBase64);
  final logoMime = v(SettingsKeys.firmaLogoMime) ?? 'image/png';
  if (logoBase64 != null && logoBase64.isNotEmpty) {
    logoDataUri = 'data:$logoMime;base64,$logoBase64';
  }

  final nameFull = v(SettingsKeys.firmaName) ?? '';
  final parts = nameFull.split(RegExp(r'\s+'));
  final vorname =
      parts.length > 1 ? parts.take(parts.length - 1).join(' ') : null;
  final nachname = parts.isNotEmpty ? parts.last : null;

  // Bestellungstext als Kombination der zwei Spalten.
  final bestellung1 = v(SettingsKeys.firmaBestellung1) ?? '';
  final bestellung2 = v(SettingsKeys.firmaBestellung2) ?? '';
  final bestellung = [bestellung1, bestellung2]
      .where((s) => s.isNotEmpty)
      .join('\n\n');

  // Anschrift aus Einstellungen parsen (Straße / PLZ-Ort).
  final anschrift = v(SettingsKeys.firmaAnschrift) ?? '';
  final anschriftLines = anschrift
      .split(RegExp(r'\r?\n'))
      .where((s) => s.trim().isNotEmpty)
      .toList();
  final strasseSet = anschriftLines.isNotEmpty ? anschriftLines.first : null;
  String? plzSet;
  String? ortSet;
  if (anschriftLines.length >= 2) {
    // Zeile 2: "46499 Hamminkeln" → PLZ + Ort
    final m = RegExp(r'^(\d{4,5})\s+(.+)').firstMatch(anschriftLines[1]);
    if (m != null) {
      plzSet = m.group(1);
      ortSet = m.group(2);
    } else {
      ortSet = anschriftLines[1];
    }
  }

  // Baue neue BenutzerData auf, indem wir das bestehende Benutzer-Profil
  // als Basis nehmen und Einstellungs-Werte überlagern.
  final base = benutzer ??
      BenutzerData(
        id: 0,
        aktiv: true,
        rolle: 'admin',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
  return base.copyWith(
    firma: Value(v(SettingsKeys.firmaName) ?? base.firma),
    titel: Value(v(SettingsKeys.firmaTitel) ?? base.titel),
    vorname: Value(vorname ?? base.vorname),
    nachname: Value(nachname ?? base.nachname),
    strasse: Value(strasseSet ?? base.strasse),
    plz: Value(plzSet ?? base.plz),
    ort: Value(ortSet ?? base.ort),
    telefon: Value(v(SettingsKeys.firmaTelefon) ?? base.telefon),
    email: Value(v(SettingsKeys.firmaEmail) ?? base.email),
    website: Value(v(SettingsKeys.firmaWebsite) ?? base.website),
    steuerNr: Value(v(SettingsKeys.steuerNr) ?? base.steuerNr),
    ustId: Value(v(SettingsKeys.steuerUstId) ?? base.ustId),
    iban: Value(v(SettingsKeys.bankIban) ?? base.iban),
    bic: Value(v(SettingsKeys.bankBic) ?? base.bic),
    bank: Value(v(SettingsKeys.bankName) ?? base.bank),
    bestellungsText:
        Value(bestellung.isNotEmpty ? bestellung : base.bestellungsText),
    logoPfad: Value(logoDataUri ?? base.logoPfad),
    standardStundensatz: Value(
        double.tryParse(
                (v(SettingsKeys.standardStundensatz) ?? '').replaceAll(',', '.')) ??
            base.standardStundensatz),
  );
}
