import 'dart:convert';

/// Eine einzelne Beweisfrage aus dem Beweisbeschluss.
class Beweisfrage {
  final String nr;
  final String frage;
  const Beweisfrage({required this.nr, required this.frage});

  Map<String, dynamic> toJson() => {'nr': nr, 'frage': frage};

  factory Beweisfrage.fromJson(Map<String, dynamic> j) => Beweisfrage(
        nr: j['nr']?.toString() ?? '',
        frage: j['frage']?.toString() ?? '',
      );

  Beweisfrage copyWith({String? nr, String? frage}) =>
      Beweisfrage(nr: nr ?? this.nr, frage: frage ?? this.frage);
}

List<Beweisfrage> decodeBeweisfragen(String? json) {
  if (json == null || json.trim().isEmpty) return const [];
  try {
    final raw = jsonDecode(json);
    if (raw is List) {
      return raw
          .whereType<Map<String, dynamic>>()
          .map(Beweisfrage.fromJson)
          .toList();
    }
  } catch (_) {}
  return const [];
}

String encodeBeweisfragen(List<Beweisfrage> list) =>
    jsonEncode(list.map((e) => e.toJson()).toList());
