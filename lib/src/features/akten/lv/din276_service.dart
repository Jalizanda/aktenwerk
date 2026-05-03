import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Eine DIN-276-Kostengruppe (1./2./3. Ebene) mit Kurzbeschreibung.
class Din276Eintrag {
  final String nr;
  final String name;
  final String beschreibung;
  final int ebene;
  const Din276Eintrag({
    required this.nr,
    required this.name,
    required this.beschreibung,
    required this.ebene,
  });

  factory Din276Eintrag.fromJson(Map<String, dynamic> j) => Din276Eintrag(
        nr: j['nr']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        beschreibung: j['beschreibung']?.toString() ?? '',
        ebene: (j['ebene'] as num?)?.toInt() ?? 1,
      );

  String get label => '$nr · $name';
}

/// Lädt die DIN-276-Liste aus dem Asset-JSON. Wird einmalig pro Session
/// geladen und im Provider gecacht.
class Din276Service {
  Din276Service();

  List<Din276Eintrag>? _cache;

  Future<List<Din276Eintrag>> load() async {
    if (_cache != null) return _cache!;
    final raw = await rootBundle
        .loadString('assets/data/din276_kostengruppen.json');
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final list = (json['kostengruppen'] as List)
        .whereType<Map<String, dynamic>>()
        .map(Din276Eintrag.fromJson)
        .toList();
    _cache = list;
    return list;
  }

  Din276Eintrag? findeByNr(String? nr) {
    if (nr == null || nr.trim().isEmpty) return null;
    return _cache?.where((e) => e.nr == nr.trim()).firstOrNull;
  }
}

final din276ServiceProvider =
    Provider<Din276Service>((_) => Din276Service());

final din276ListProvider = FutureProvider<List<Din276Eintrag>>(
    (ref) => ref.watch(din276ServiceProvider).load());
