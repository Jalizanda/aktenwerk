import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'einstellungen_repository.dart';

/// Typ des Nummernkreises.
enum NummernkreisTyp {
  akte,
  rechnung,
  akonto,
  angebot,
  auftragsbestaetigung,
  gutachten,
  fortbildung,
}

class _NkKeys {
  final String muster;
  final String naechste;
  final String reset;
  final String lastYear;
  const _NkKeys(this.muster, this.naechste, this.reset, this.lastYear);
}

_NkKeys _keysFor(NummernkreisTyp t) {
  switch (t) {
    case NummernkreisTyp.akte:
      return const _NkKeys(
        SettingsKeys.nummernkreisAktenzeichen,
        SettingsKeys.nummernkreisAktenzeichenNaechste,
        SettingsKeys.nummernkreisAktenzeichenReset,
        'nummernkreis.aktenzeichen.lastYear',
      );
    case NummernkreisTyp.rechnung:
      return const _NkKeys(
        SettingsKeys.nummernkreisRechnung,
        SettingsKeys.nummernkreisRechnungNaechste,
        SettingsKeys.nummernkreisRechnungReset,
        'nummernkreis.rechnung.lastYear',
      );
    case NummernkreisTyp.akonto:
      return const _NkKeys(
        SettingsKeys.nummernkreisAkonto,
        SettingsKeys.nummernkreisAkontoNaechste,
        SettingsKeys.nummernkreisAkontoReset,
        'nummernkreis.akonto.lastYear',
      );
    case NummernkreisTyp.angebot:
      return const _NkKeys(
        SettingsKeys.nummernkreisAngebot,
        SettingsKeys.nummernkreisAngebotNaechste,
        SettingsKeys.nummernkreisAngebotReset,
        'nummernkreis.angebot.lastYear',
      );
    case NummernkreisTyp.auftragsbestaetigung:
      return const _NkKeys(
        SettingsKeys.nummernkreisAuftragsbestaetigung,
        SettingsKeys.nummernkreisAuftragsbestaetigungNaechste,
        SettingsKeys.nummernkreisAuftragsbestaetigungReset,
        'nummernkreis.auftragsbestaetigung.lastYear',
      );
    case NummernkreisTyp.gutachten:
      return const _NkKeys(
        SettingsKeys.nummernkreisGutachten,
        SettingsKeys.nummernkreisGutachtenNaechste,
        SettingsKeys.nummernkreisGutachtenReset,
        'nummernkreis.gutachten.lastYear',
      );
    case NummernkreisTyp.fortbildung:
      return const _NkKeys(
        SettingsKeys.nummernkreisFortbildung,
        SettingsKeys.nummernkreisFortbildungNaechste,
        SettingsKeys.nummernkreisFortbildungReset,
        'nummernkreis.fortbildung.lastYear',
      );
  }
}

String _defaultPattern(NummernkreisTyp t) => switch (t) {
      NummernkreisTyp.akte => 'AW-{NNNN}',
      NummernkreisTyp.angebot => 'AN{YYYY}-{NNN}',
      NummernkreisTyp.auftragsbestaetigung => 'AB{YYYY}-{NNN}',
      NummernkreisTyp.rechnung => 'RE{YYYY}-{NNN}',
      NummernkreisTyp.akonto => 'AZ{YYYY}-{NNN}',
      NummernkreisTyp.gutachten => '{aktenzeichen}-G{N}',
      NummernkreisTyp.fortbildung => 'FB{YYYY}-{NN}',
    };

String _defaultReset(NummernkreisTyp t) => switch (t) {
      // Alle Kreise laufen per Default manuell — fortlaufend über Jahre
      // hinweg. Damit bleiben GoBD-konforme, lückenlose Nummerierungen
      // erhalten. Nutzer kann in den Einstellungen auf "jahr" umstellen.
      _ => 'nie',
    };

/// Wendet die Platzhalter an: `{YYYY}`, `{YY}`, `{MM}`, `{N}`/`{NN}`/`{NNN}`/
/// `{NNNN}` und optional `{aktenzeichen}`.
String applyNummernkreisPattern(
  String pattern,
  int counter, {
  DateTime? now,
  String? aktenzeichen,
}) {
  final n = now ?? DateTime.now();
  var out = pattern
      .replaceAll('{YYYY}', n.year.toString())
      .replaceAll('{YY}', n.year.toString().substring(2))
      .replaceAll('{MM}', n.month.toString().padLeft(2, '0'))
      .replaceAll('{DD}', n.day.toString().padLeft(2, '0'));
  // Legacy-Platzhalter (ohne geschweifte Klammern).
  out = out
      .replaceAll('YYYY', n.year.toString())
      .replaceAll('YY', n.year.toString().substring(2));
  // Zähler mit variabler Breite: {N}, {NN}, {NNN}, {NNNN}.
  for (final width in [4, 3, 2, 1]) {
    final token = '{${'N' * width}}';
    if (out.contains(token)) {
      out = out.replaceAll(token, counter.toString().padLeft(width, '0'));
    }
  }
  // Legacy: #### / ### / ##.
  final hashes = RegExp(r'#+').firstMatch(out);
  if (hashes != null) {
    final width = hashes.group(0)!.length;
    out = out.replaceFirst(
        hashes.group(0)!, counter.toString().padLeft(width, '0'));
  }
  if (aktenzeichen != null) {
    out = out.replaceAll('{aktenzeichen}', aktenzeichen);
  }
  return out;
}

class NummernkreisService {
  NummernkreisService(this._repo);
  final EinstellungenRepository _repo;

  /// Gibt die nächste Nummer für den angegebenen Typ zurück und erhöht
  /// den Zähler. Berücksichtigt den jährlichen Reset.
  ///
  /// [aktenzeichen] ist nur für [NummernkreisTyp.gutachten] relevant.
  Future<String> nextNumber(
    NummernkreisTyp typ, {
    String? aktenzeichen,
  }) async {
    final keys = _keysFor(typ);
    final pattern = await _repo.getOr(keys.muster, _defaultPattern(typ));
    final reset = await _repo.getOr(keys.reset, _defaultReset(typ));

    final now = DateTime.now();
    var counter =
        int.tryParse(await _repo.getOr(keys.naechste, '1')) ?? 1;

    if (reset == 'jahr') {
      final lastYear = int.tryParse(await _repo.getOr(keys.lastYear, '0'));
      if (lastYear == null || lastYear != now.year) {
        counter = 1;
      }
    }

    final result = applyNummernkreisPattern(
      pattern,
      counter,
      now: now,
      aktenzeichen: aktenzeichen,
    );

    // Persistieren: Zähler hochzählen und Jahr merken.
    await _repo.set(keys.naechste, (counter + 1).toString());
    if (reset == 'jahr') {
      await _repo.set(keys.lastYear, now.year.toString());
    }

    return result;
  }

  /// Vorschau ohne den Zähler hochzusetzen.
  Future<String> previewNumber(
    NummernkreisTyp typ, {
    String? aktenzeichen,
  }) async {
    final keys = _keysFor(typ);
    final pattern = await _repo.getOr(keys.muster, _defaultPattern(typ));
    final reset = await _repo.getOr(keys.reset, _defaultReset(typ));

    final now = DateTime.now();
    var counter =
        int.tryParse(await _repo.getOr(keys.naechste, '1')) ?? 1;

    if (reset == 'jahr') {
      final lastYear = int.tryParse(await _repo.getOr(keys.lastYear, '0'));
      if (lastYear == null || lastYear != now.year) {
        counter = 1;
      }
    }

    return applyNummernkreisPattern(
      pattern,
      counter,
      now: now,
      aktenzeichen: aktenzeichen,
    );
  }
}

final nummernkreisServiceProvider = Provider<NummernkreisService>(
  (ref) => NummernkreisService(ref.watch(einstellungenRepositoryProvider)),
);
