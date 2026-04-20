import 'dart:convert';

/// Einzelposition einer Rechnung / eines Angebots.
///
/// [bezeichnung] ist der Kurztext (einzeilig). [langtext] ist ein optionaler
/// mehrzeiliger Zusatztext, der im Dokument kleiner und grau unter dem
/// Kurztext ausgegeben wird.
class Position {
  final String bezeichnung;
  final String langtext;
  final double menge;
  final String einheit;
  final double einzelpreis;
  final double ustSatz;

  /// Optionale Positions-Nummer (frei setzbar). Wenn leer, wird im PDF die
  /// fortlaufende Zeilennummer genutzt.
  final String posNr;

  /// Optional-/Alternativ-Position. Beträge werden nicht in die Gesamtsumme
  /// eingerechnet, sondern im PDF in Klammern `(…)` ausgewiesen.
  final bool optional;

  const Position({
    this.bezeichnung = '',
    this.langtext = '',
    this.menge = 1,
    this.einheit = '',
    this.einzelpreis = 0,
    this.ustSatz = 19,
    this.posNr = '',
    this.optional = false,
  });

  double get nettoBetrag => menge * einzelpreis;
  double get ustBetrag => nettoBetrag * (ustSatz / 100);
  double get bruttoBetrag => nettoBetrag + ustBetrag;

  Position copyWith({
    String? bezeichnung,
    String? langtext,
    double? menge,
    String? einheit,
    double? einzelpreis,
    double? ustSatz,
    String? posNr,
    bool? optional,
  }) =>
      Position(
        bezeichnung: bezeichnung ?? this.bezeichnung,
        langtext: langtext ?? this.langtext,
        menge: menge ?? this.menge,
        einheit: einheit ?? this.einheit,
        einzelpreis: einzelpreis ?? this.einzelpreis,
        ustSatz: ustSatz ?? this.ustSatz,
        posNr: posNr ?? this.posNr,
        optional: optional ?? this.optional,
      );

  Map<String, dynamic> toJson() => {
        'bezeichnung': bezeichnung,
        if (langtext.isNotEmpty) 'langtext': langtext,
        'menge': menge,
        'einheit': einheit,
        'einzelpreis': einzelpreis,
        'ustSatz': ustSatz,
        if (posNr.isNotEmpty) 'posNr': posNr,
        if (optional) 'optional': true,
      };

  factory Position.fromJson(Map<String, dynamic> j) {
    // Rückwärts-kompatibel: Falls `bezeichnung` mehrzeilig ist, splitten wir
    // sie — erste Zeile bleibt Kurztext, Rest wird zu Langtext.
    var bez = (j['bezeichnung'] as String?) ?? '';
    var lang = (j['langtext'] as String?) ?? '';
    if (lang.isEmpty && bez.contains('\n')) {
      final parts = bez.split(RegExp(r'\r?\n'));
      bez = parts.first;
      lang = parts.sublist(1).join('\n').trim();
    }
    return Position(
      bezeichnung: bez,
      langtext: lang,
      menge: (j['menge'] as num?)?.toDouble() ?? 1,
      einheit: (j['einheit'] as String?) ?? '',
      einzelpreis: (j['einzelpreis'] as num?)?.toDouble() ?? 0,
      ustSatz: (j['ustSatz'] as num?)?.toDouble() ?? 19,
      posNr: (j['posNr'] as String?) ?? '',
      optional: j['optional'] == true,
    );
  }
}

List<Position> positionsFromJson(String? json) {
  if (json == null || json.isEmpty) return const [];
  final list = jsonDecode(json) as List<dynamic>;
  return list
      .map((e) => Position.fromJson(e as Map<String, dynamic>))
      .toList();
}

String positionsToJson(List<Position> list) =>
    jsonEncode(list.map((p) => p.toJson()).toList());

/// Summen-Totals über alle Positionen.
class PositionsTotals {
  final double netto;
  final double ust;
  final double brutto;
  const PositionsTotals({required this.netto, required this.ust, required this.brutto});

  /// Summen ohne Optional-/Alternativpositionen (für die Rechnungs-/Angebots-
  /// Summe). Optional-Positionen werden im Dokument in Klammern dargestellt
  /// und fließen NICHT in die Gesamtsumme ein.
  static PositionsTotals fromList(List<Position> list) {
    double n = 0;
    double u = 0;
    for (final p in list) {
      if (p.optional) continue;
      n += p.nettoBetrag;
      u += p.ustBetrag;
    }
    return PositionsTotals(netto: n, ust: u, brutto: n + u);
  }
}
