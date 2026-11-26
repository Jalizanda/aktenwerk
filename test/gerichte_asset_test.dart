import 'dart:convert';
import 'dart:io';

import 'package:aktenwerk/src/data/seed/gerichte.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Gerichtsverzeichnis: vollständig, eindeutig, mit Anschrift', () {
    final liste = (jsonDecode(File('assets/data/gerichte.json').readAsStringSync()) as List)
        .map((e) => Gericht.fromJson(e as Map<String, dynamic>))
        .toList();
    expect(liste.length, greaterThan(1000));
    expect(liste.map((g) => g.name).toSet().length, liste.length);
    expect(liste.where((g) => g.strasse.isEmpty || g.plz.isEmpty || g.ort.isEmpty), isEmpty);
    expect(liste.where((g) => g.typ.isEmpty), isEmpty);
    expect(liste.where((g) => g.land == 'AT').length, greaterThan(150));
    final berlin = liste.firstWhere((g) => g.name == 'Landgericht Berlin II');
    expect(berlin.strasse, 'Tegeler Weg 17-21');
  });
}
