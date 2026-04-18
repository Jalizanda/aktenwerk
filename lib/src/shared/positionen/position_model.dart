import 'dart:convert';

/// Einzelposition einer Rechnung / eines Angebots.
class Position {
  final String bezeichnung;
  final double menge;
  final String einheit;
  final double einzelpreis;
  final double ustSatz;

  const Position({
    this.bezeichnung = '',
    this.menge = 1,
    this.einheit = '',
    this.einzelpreis = 0,
    this.ustSatz = 19,
  });

  double get nettoBetrag => menge * einzelpreis;
  double get ustBetrag => nettoBetrag * (ustSatz / 100);
  double get bruttoBetrag => nettoBetrag + ustBetrag;

  Position copyWith({
    String? bezeichnung,
    double? menge,
    String? einheit,
    double? einzelpreis,
    double? ustSatz,
  }) =>
      Position(
        bezeichnung: bezeichnung ?? this.bezeichnung,
        menge: menge ?? this.menge,
        einheit: einheit ?? this.einheit,
        einzelpreis: einzelpreis ?? this.einzelpreis,
        ustSatz: ustSatz ?? this.ustSatz,
      );

  Map<String, dynamic> toJson() => {
        'bezeichnung': bezeichnung,
        'menge': menge,
        'einheit': einheit,
        'einzelpreis': einzelpreis,
        'ustSatz': ustSatz,
      };

  factory Position.fromJson(Map<String, dynamic> j) => Position(
        bezeichnung: (j['bezeichnung'] as String?) ?? '',
        menge: (j['menge'] as num?)?.toDouble() ?? 1,
        einheit: (j['einheit'] as String?) ?? '',
        einzelpreis: (j['einzelpreis'] as num?)?.toDouble() ?? 0,
        ustSatz: (j['ustSatz'] as num?)?.toDouble() ?? 19,
      );
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

  static PositionsTotals fromList(List<Position> list) {
    double n = 0;
    double u = 0;
    for (final p in list) {
      n += p.nettoBetrag;
      u += p.ustBetrag;
    }
    return PositionsTotals(netto: n, ust: u, brutto: n + u);
  }
}
