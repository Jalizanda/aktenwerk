import 'dart:convert';

import 'package:drift/drift.dart' show Value, OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../auftraege/auftrag_gm_extras.dart';
import '../auftraege/auftraege_repository.dart';

/// Ein Beteiligter in einer Akte — zusätzlich zum Auftraggeber.
class Beteiligter {
  String rolle;
  String anrede;
  String name;
  String briefanrede;
  String ihrZeichen;
  String vertritt;
  String strasse;
  String plz;
  String ort;
  String telefon;
  String email;
  bool zumOrtsterminLaden;
  String versandart;

  Beteiligter({
    this.rolle = 'Antragsteller',
    this.anrede = '',
    this.name = '',
    this.briefanrede = '',
    this.ihrZeichen = '',
    this.vertritt = '',
    this.strasse = '',
    this.plz = '',
    this.ort = '',
    this.telefon = '',
    this.email = '',
    this.zumOrtsterminLaden = true,
    this.versandart = 'Brief',
  });

  /// Komplette Anschrift als ein String — für Anschreiben-Empfänger.
  String get anschrift {
    final z2 = '${plz.trim()} ${ort.trim()}'.trim();
    return [strasse.trim(), z2]
        .where((s) => s.isNotEmpty)
        .join(', ');
  }

  /// Baut die effektive Briefanrede (nutzt `briefanrede`, falls gesetzt,
  /// sonst automatisch aus `anrede`, `name` und `rolle`).
  String get effectiveBriefanrede {
    if (briefanrede.trim().isNotEmpty) return briefanrede.trim();
    final n = name.trim();
    if (n.isEmpty) return 'Sehr geehrte Damen und Herren,';
    final teile = n.split(RegExp(r'\s+'));
    final nachname = teile.isNotEmpty ? teile.last : n;
    final lower = n.toLowerCase();
    final anr = anrede.trim().toLowerCase();
    final istAnwalt = rolle.toLowerCase().contains('anwalt');
    if (anr == 'frau' ||
        lower.contains(' frau ') ||
        lower.startsWith('frau ')) {
      return istAnwalt
          ? 'Sehr geehrte Frau Rechtsanwältin $nachname,'
          : 'Sehr geehrte Frau $nachname,';
    }
    if (anr == 'herr' ||
        lower.contains(' herr ') ||
        lower.startsWith('herr ')) {
      return istAnwalt
          ? 'Sehr geehrter Herr Rechtsanwalt $nachname,'
          : 'Sehr geehrter Herr $nachname,';
    }
    return 'Sehr geehrte Damen und Herren,';
  }

  Map<String, dynamic> toJson() => {
        'rolle': rolle,
        'anrede': anrede,
        'name': name,
        'briefanrede': briefanrede,
        'ihrZeichen': ihrZeichen,
        'vertritt': vertritt,
        'strasse': strasse,
        'plz': plz,
        'ort': ort,
        // Für Abwärtskompatibilität: ältere Stellen lesen `anschrift`.
        'anschrift': anschrift,
        'telefon': telefon,
        'email': email,
        'zumOrtsterminLaden': zumOrtsterminLaden,
        'versandart': versandart,
      };

  static Beteiligter fromJson(Map<String, dynamic> m) {
    // Neue Felder bevorzugt; sonst aus altem `anschrift`-String parsen.
    final str = m['strasse']?.toString();
    final plz = m['plz']?.toString();
    final ort = m['ort']?.toString();
    final ladenRaw = m['zumOrtsterminLaden'];
    final laden = ladenRaw is bool ? ladenRaw : true;
    final versand = m['versandart']?.toString().trim();

    if (str == null && plz == null && ort == null) {
      // Legacy-Daten: ein Anschrift-String — heuristisch zerlegen.
      final raw = (m['anschrift']?.toString() ?? '').trim();
      var lStrasse = '';
      var lPlz = '';
      var lOrt = '';
      if (raw.isNotEmpty) {
        // Komma-getrennt: „Strasse 1, 12345 Stadt"
        final teile = raw.split(',').map((e) => e.trim()).toList();
        if (teile.length >= 2) {
          lStrasse = teile[0];
          final rest = teile.sublist(1).join(', ').trim();
          final m2 = RegExp(r'^(\d{4,5})\s+(.+)$').firstMatch(rest);
          if (m2 != null) {
            lPlz = m2.group(1)!;
            lOrt = m2.group(2)!;
          } else {
            lOrt = rest;
          }
        } else {
          lStrasse = raw;
        }
      }
      return Beteiligter(
        rolle: m['rolle']?.toString() ?? 'Antragsteller',
        anrede: m['anrede']?.toString() ?? '',
        name: m['name']?.toString() ?? '',
        briefanrede: m['briefanrede']?.toString() ?? '',
        ihrZeichen: m['ihrZeichen']?.toString() ?? '',
        vertritt: m['vertritt']?.toString() ?? '',
        strasse: lStrasse,
        plz: lPlz,
        ort: lOrt,
        telefon: m['telefon']?.toString() ?? '',
        email: m['email']?.toString() ?? '',
        zumOrtsterminLaden: laden,
        versandart: (versand == null || versand.isEmpty) ? 'Brief' : versand,
      );
    }
    return Beteiligter(
      rolle: m['rolle']?.toString() ?? 'Antragsteller',
      anrede: m['anrede']?.toString() ?? '',
      name: m['name']?.toString() ?? '',
      briefanrede: m['briefanrede']?.toString() ?? '',
      ihrZeichen: m['ihrZeichen']?.toString() ?? '',
      vertritt: m['vertritt']?.toString() ?? '',
      strasse: str ?? '',
      plz: plz ?? '',
      ort: ort ?? '',
      telefon: m['telefon']?.toString() ?? '',
      email: m['email']?.toString() ?? '',
      zumOrtsterminLaden: laden,
      versandart: (versand == null || versand.isEmpty) ? 'Brief' : versand,
    );
  }
}

const beteiligtenRollen = <String>[
  'Antragsteller',
  'Antragsgegner',
  'Kläger',
  'Beklagter',
  'Streitverkündete:r',
  'Mieter',
  'Vermieter',
  'Eigentümer',
  'WEG / Verwalter',
  'Anwalt Kläger',
  'Anwalt Beklagter',
  'Anwalt Streitverkündeter',
  'Versicherungsnehmer',
  'Anspruchsteller',
  'Regulierer / Versicherung',
  'Bauherr',
  'Bauträger',
  'Architekt',
  'Sonstiger',
];

const beteiligtenAnreden = <String>[
  '',
  'Herr',
  'Frau',
  'Firma',
  'Kanzlei',
  'Eheleute',
];

const beteiligtenVersandarten = <String>[
  'Brief',
  'Einwurf-Einschreiben',
  'Einschreiben/Rückschein',
  'E-Mail',
  'beA / EGVP',
];

List<Beteiligter> decodeBeteiligte(String? raw) {
  if (raw == null || raw.trim().isEmpty) return [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(Beteiligter.fromJson)
          .toList();
    }
  } catch (_) {}
  return [];
}

String encodeBeteiligte(List<Beteiligter> list) =>
    jsonEncode(list.map((b) => b.toJson()).toList());

String _plainTextToQuillDelta(String text) {
  final zeilen = text.split('\n');
  final ops = <Map<String, dynamic>>[];
  for (final z in zeilen) {
    if (z.isNotEmpty) ops.add({'insert': z});
    ops.add({'insert': '\n'});
  }
  if (ops.isEmpty) ops.add({'insert': '\n'});
  return jsonEncode(ops);
}

/// Baut die Kurzbezeichnung der Sache (z. B. „Müller ./. Schmidt" oder Objekt).
String buildSacheKurzbezeichnung(AuftraegeData auftrag) {
  final kl = (auftrag.klaeger ?? '').trim();
  final bk = (auftrag.beklagter ?? '').trim();
  if (kl.isNotEmpty && bk.isNotEmpty) return '$kl ./. $bk';
  final gm = AuftragGmExtras.fromAuftragExtras(auftrag.extras);
  final pa = gm.parteiA.trim();
  final pb = gm.parteiB.trim();
  if (pa.isNotEmpty && pb.isNotEmpty) return '$pa ./. $pb';
  final vn = gm.versicherungsnehmer.trim();
  if (vn.isNotEmpty) {
    final snr = gm.schadensnummer.trim();
    return snr.isNotEmpty ? 'Schadensache $vn (Schaden-Nr. $snr)' : 'Schadensache $vn';
  }
  final betr = (auftrag.betreff ?? '').trim();
  if (betr.isNotEmpty) return betr;
  return [auftrag.objektStrasse, auftrag.objektOrt]
      .whereType<String>()
      .where((s) => s.trim().isNotEmpty)
      .join(', ');
}

class BeteiligteTab extends ConsumerStatefulWidget {
  const BeteiligteTab({super.key, required this.auftrag});
  final AuftraegeData auftrag;
  @override
  ConsumerState<BeteiligteTab> createState() => _BeteiligteTabState();
}

class _BeteiligteTabState extends ConsumerState<BeteiligteTab> {
  late List<Beteiligter> _liste;
  bool _dirty = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _liste = decodeBeteiligte(widget.auftrag.beteiligteJson);
  }

  @override
  void didUpdateWidget(covariant BeteiligteTab old) {
    super.didUpdateWidget(old);
    if (old.auftrag.id != widget.auftrag.id ||
        old.auftrag.beteiligteJson != widget.auftrag.beteiligteJson) {
      setState(() {
        _liste = decodeBeteiligte(widget.auftrag.beteiligteJson);
        _dirty = false;
      });
    }
  }

  Future<void> _save({bool silent = false}) async {
    setState(() => _saving = true);
    try {
      await ref.read(auftraegeRepositoryProvider).upsert(
            AuftraegeCompanion(
              id: Value(widget.auftrag.id),
              beteiligteJson: Value(encodeBeteiligte(_liste)),
              updatedAt: Value(DateTime.now()),
            ),
          );
      if (mounted) {
        setState(() {
          _saving = false;
          _dirty = false;
        });
        if (!silent) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Beteiligte gespeichert.')),
          );
        }
      }
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Weitere Beteiligte (zusätzlich zum Auftraggeber)',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_liste.isNotEmpty) ...[
                    OutlinedButton.icon(
                      icon: const Icon(Icons.event_outlined, size: 16),
                      label: const Text('Ortstermin-Einladung (Serienbrief)'),
                      onPressed: () => _massenEinladung(context, istUmladung: false),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.update_outlined, size: 16),
                      label: const Text('Umladung / Terminverlegung'),
                      onPressed: () => _massenEinladung(context, istUmladung: true),
                    ),
                    const SizedBox(width: 8),
                  ],
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Beteiligten hinzufügen'),
                    onPressed: () => setState(() {
                      _liste.add(Beteiligter());
                      _dirty = true;
                    }),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    icon: _saving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save_outlined, size: 16),
                    label: Text(_saving ? 'Speichern…' : 'Speichern'),
                    onPressed: _saving || !_dirty ? null : () => _save(),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _liste.isEmpty
                ? const EmptyListState(
                    icon: Icons.groups_2_outlined,
                    title: 'Keine zusätzlichen Beteiligten erfasst',
                    hint:
                        'Auftraggeber steht in den Stammdaten — hier kannst du Kläger, Beklagte, Prozessbevollmächtigte (inkl. eigenem AZ „Ihr Zeichen"), Versicherungsnehmer usw. ergänzen.')
                : ListView.separated(
                    itemCount: _liste.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _BeteiligterRow(
                      key: ValueKey(_liste[i]),
                      b: _liste[i],
                      onChanged: () => setState(() => _dirty = true),
                      onRemove: () => setState(() {
                        _liste.removeAt(i);
                        _dirty = true;
                      }),
                      onBrief: () => _einzelEinladung(_liste[i], viaMail: false),
                      onMail: () => _einzelEinladung(_liste[i], viaMail: true),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  String _baueTerminString(DateTime? datum, String? von, String? bis) {
    if (datum == null) return 'wird gesondert mitgeteilt';
    final d = DateFormat('EEEE, dd.MM.yyyy', 'de').format(datum);
    final v = (von ?? '').trim();
    final b = (bis ?? '').trim();
    if (v.isNotEmpty && b.isNotEmpty) {
      return '$d, $v bis ca. $b Uhr';
    }
    if (v.isNotEmpty) {
      return '$d um $v Uhr';
    }
    if (datum.hour != 0 || datum.minute != 0) {
      return DateFormat("EEEE, dd.MM.yyyy 'um' HH:mm 'Uhr'", 'de').format(datum);
    }
    return d;
  }

  String _baueGeladeneListe(List<Beteiligter> alleGeladenen, {Beteiligter? ausser}) {
    final andere = alleGeladenen
        .where((x) => x != ausser && x.name.trim().isNotEmpty)
        .toList();
    if (andere.isEmpty) return '';
    final buf = StringBuffer('Zu diesem Termin wurden außerdem geladen:\n');
    for (final a in andere) {
      final vert = a.vertritt.trim().isNotEmpty ? ' (für ${a.vertritt.trim()})' : '';
      final ortStr = [a.plz.trim(), a.ort.trim()].where((s) => s.isNotEmpty).join(' ');
      final zusatz = ortStr.isNotEmpty ? ', $ortStr' : '';
      buf.writeln('• ${a.rolle}$vert: ${a.name.trim()}$zusatz');
    }
    return buf.toString().trimRight();
  }

  /// Einzel-Einladung an genau einen Beteiligten — verzweigt direkt in
  /// den Anschreiben-Dialog (Brief) oder Mail-Compose-Flow.
  Future<void> _einzelEinladung(Beteiligter b, {required bool viaMail}) async {
    if (b.name.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bitte erst Name eintragen.')));
      return;
    }
    if (_dirty) {
      await _save(silent: true);
    }
    final gm = AuftragGmExtras.fromAuftragExtras(widget.auftrag.extras);
    final terminStr = _baueTerminString(
      widget.auftrag.ortsterminAm,
      gm.ortsterminUhrzeitVon,
      gm.ortsterminUhrzeitBis,
    );
    final ortStr = [
      widget.auftrag.objektStrasse,
      '${widget.auftrag.objektPlz ?? ''} ${widget.auftrag.objektOrt ?? ''}'.trim(),
    ].whereType<String>().where((s) => s.trim().isNotEmpty).join(', ');
    final sache = buildSacheKurzbezeichnung(widget.auftrag);
    final geladeneBlock = _baueGeladeneListe(
      _liste.where((x) => x.zumOrtsterminLaden).toList(),
      ausser: b,
    );

    final bodyBuf = StringBuffer();
    if (b.ihrZeichen.trim().isNotEmpty) {
      bodyBuf.writeln('Ihr Zeichen: ${b.ihrZeichen.trim()}');
    }
    if ((widget.auftrag.gerichtsAktenzeichen ?? '').trim().isNotEmpty) {
      bodyBuf.writeln(
          'Gerichts-AZ: ${widget.auftrag.gerichtsAktenzeichen!.trim()}');
    }
    if (sache.isNotEmpty) {
      bodyBuf.writeln('In Sachen: $sache');
    }
    if (bodyBuf.isNotEmpty) bodyBuf.writeln();
    bodyBuf.writeln(
        'in oben genannter Angelegenheit wurde ich mit der Erstellung eines Sachverständigengutachtens beauftragt. Zur Durchführung der Ortsbesichtigung lade ich Sie herzlich ein:');
    bodyBuf.writeln();
    bodyBuf.writeln('Termin: $terminStr');
    bodyBuf.writeln('Treffpunkt / Objekt: ${ortStr.isEmpty ? "—" : ortStr}');
    bodyBuf.writeln('Versandart: ${b.versandart}');
    bodyBuf.writeln();
    if (geladeneBlock.isNotEmpty) {
      bodyBuf.writeln(geladeneBlock);
      bodyBuf.writeln();
    }
    bodyBuf.write(
        'Bitte teilen Sie mir kurzfristig mit, falls Sie den Termin nicht wahrnehmen können.');

    final briefText = bodyBuf.toString();

    if (viaMail) {
      if (b.email.trim().isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Keine E-Mail-Adresse hinterlegt — bitte ergänzen.')));
        return;
      }
      final url = Uri(
        scheme: 'mailto',
        path: b.email,
        queryParameters: {
          'subject':
              'Einladung zum Ortstermin — ${widget.auftrag.aktenzeichen ?? sache}',
          'body': '${b.effectiveBriefanrede}\n\n$briefText\n\nMit freundlichen Grüßen',
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Mail-Vorbereitung: $url')));
      }
      return;
    }

    final db = ref.read(appDatabaseProvider);
    final extras = jsonEncode({
      'beteiligterRolle': b.rolle,
      'beteiligterAnrede': b.anrede,
      'beteiligterName': b.name,
      'beteiligterStrasse': b.strasse,
      'beteiligterPlz': b.plz,
      'beteiligterOrt': b.ort,
      'beteiligterAnschrift': b.anschrift,
      'beteiligterEmail': b.email,
      'beteiligterIhrZeichen': b.ihrZeichen,
      'beteiligterVersandart': b.versandart,
      'einladungBestaetigt': null,
    });
    final betreff = b.ihrZeichen.trim().isNotEmpty
        ? 'Einladung zum Ortstermin — Ihr Zeichen: ${b.ihrZeichen.trim()}'
        : 'Einladung zum Ortstermin';
    await db.into(db.anschreiben).insert(AnschreibenCompanion.insert(
          auftragId: Value(widget.auftrag.id),
          betreff: Value(betreff),
          datum: Value(DateTime.now()),
          anrede: Value(b.effectiveBriefanrede),
          briefText: Value(briefText),
          inhaltJson: Value(_plainTextToQuillDelta(briefText)),
          gruss: const Value('Mit freundlichen Grüßen'),
          status: const Value('entwurf'),
          extras: Value(extras),
        ));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Brief-Entwurf für ${b.name} angelegt — im Tab „Anschreiben" finalisieren.')));
  }

  /// Öffnet den Termin-Einladung- bzw. Umladung-Dialog.
  Future<void> _massenEinladung(BuildContext context,
      {required bool istUmladung}) async {
    if (_dirty) {
      await _save(silent: true);
    }
    if (!context.mounted) return;
    final aktiveBeteiligte =
        _liste.where((b) => b.name.trim().isNotEmpty).toList(growable: false);
    if (aktiveBeteiligte.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Erst Beteiligte erfassen, dann Einladungen verschicken.')));
      return;
    }
    final result = await showDialog<_EinladungResult>(
      context: context,
      useRootNavigator: true,
      builder: (_) => _TerminEinladungDialog(
        auftrag: widget.auftrag,
        beteiligte: aktiveBeteiligte,
        istUmladung: istUmladung,
      ),
    );
    if (result == null || !context.mounted) return;

    final db = ref.read(appDatabaseProvider);

    // 1. Optional: Termin & Uhrzeit & Umladungsdaten direkt in der Akte speichern.
    if (result.inAkteSpeichern && result.termin != null) {
      final gmAlt = AuftragGmExtras.fromAuftragExtras(widget.auftrag.extras);
      final gmNeu = AuftragGmExtras(
        schadensnummer: gmAlt.schadensnummer,
        versicherungsscheinNr: gmAlt.versicherungsscheinNr,
        schadenstag: gmAlt.schadenstag,
        schadensursache: gmAlt.schadensursache,
        versicherungsnehmer: gmAlt.versicherungsnehmer,
        anspruchsteller: gmAlt.anspruchsteller,
        schiedsvertragVom: gmAlt.schiedsvertragVom,
        obmann: gmAlt.obmann,
        parteiA: gmAlt.parteiA,
        parteiB: gmAlt.parteiB,
        streitwert: gmAlt.streitwert,
        aktenbaende: gmAlt.aktenbaende,
        ortsterminUhrzeitVon: result.uhrzeitVon,
        ortsterminUhrzeitBis: result.uhrzeitBis,
        ortsterminAltAm: istUmladung
            ? (result.terminAlt ?? widget.auftrag.ortsterminAm ?? gmAlt.ortsterminAltAm)
            : gmAlt.ortsterminAltAm,
        ortsterminVerlegtGrund: istUmladung
            ? result.verlegtGrund
            : gmAlt.ortsterminVerlegtGrund,
      );
      await ref.read(auftraegeRepositoryProvider).upsert(
            AuftraegeCompanion(
              id: Value(widget.auftrag.id),
              ortsterminAm: Value(result.termin),
              extras: Value(gmNeu.mergeIntoAuftragExtras(widget.auftrag.extras)),
              updatedAt: Value(DateTime.now()),
            ),
          );
    }

    var erstellt = 0;
    final terminText = _baueTerminString(
      result.termin,
      result.uhrzeitVon,
      result.uhrzeitBis,
    );
    final altTerminText = result.terminAlt == null
        ? 'den ursprünglich angesetzten Termin'
        : DateFormat('dd.MM.yyyy', 'de').format(result.terminAlt!);
    final sache = buildSacheKurzbezeichnung(widget.auftrag);

    String? letzterBrieftext;

    for (final b in result.empfaenger) {
      final anrede = b.effectiveBriefanrede;
      final brief = StringBuffer();
      if (b.ihrZeichen.trim().isNotEmpty) {
        brief.writeln('Ihr Zeichen: ${b.ihrZeichen.trim()}');
      }
      if ((widget.auftrag.gerichtsAktenzeichen ?? '').trim().isNotEmpty) {
        brief.writeln(
            'Gerichts-AZ: ${widget.auftrag.gerichtsAktenzeichen!.trim()}');
      }
      if (sache.isNotEmpty) {
        brief.writeln('In Sachen: $sache');
      }
      if (brief.isNotEmpty) brief.writeln();

      if (istUmladung) {
        brief.writeln(
            'in oben genannter Angelegenheit muss der ursprünglich für $altTerminText anberaumte Ortstermin${result.verlegtGrund.isNotEmpty ? " (${result.verlegtGrund})" : ""} leider verlegt werden.');
        brief.writeln();
        brief.writeln('Neuer Termin zur Ortsbesichtigung:');
        brief.writeln('Termin: $terminText');
        brief.writeln('Treffpunkt / Objekt: ${result.ort.isEmpty ? "—" : result.ort}');
        brief.writeln('Versandart: ${b.versandart}');
        brief.writeln();
      } else {
        brief.writeln(
            'in oben genannter Angelegenheit wurde ich mit der Erstellung eines Sachverständigengutachtens beauftragt. Zur Durchführung der Ortsbesichtigung lade ich Sie hiermit ein:');
        brief.writeln();
        brief.writeln('Termin: $terminText');
        brief.writeln('Treffpunkt / Objekt: ${result.ort.isEmpty ? "—" : result.ort}');
        brief.writeln('Versandart: ${b.versandart}');
        brief.writeln();
      }

      if (result.geladeneAuffuehren) {
        final geladeneBlock = _baueGeladeneListe(result.empfaenger, ausser: b);
        if (geladeneBlock.isNotEmpty) {
          brief.writeln(geladeneBlock);
          brief.writeln();
        }
      }

      if (result.hinweis.isNotEmpty) {
        brief.writeln(result.hinweis);
      }

      final textOut = brief.toString().trimRight();
      letzterBrieftext = textOut;

      final extras = jsonEncode({
        'beteiligterRolle': b.rolle,
        'beteiligterAnrede': b.anrede,
        'beteiligterName': b.name,
        'beteiligterStrasse': b.strasse,
        'beteiligterPlz': b.plz,
        'beteiligterOrt': b.ort,
        'beteiligterAnschrift': b.anschrift,
        'beteiligterEmail': b.email,
        'beteiligterIhrZeichen': b.ihrZeichen,
        'beteiligterVersandart': b.versandart,
        'terminText': terminText,
        'ortText': result.ort,
        'istUmladung': istUmladung,
        'einladungBestaetigt': null,
      });

      final indivBetreff = b.ihrZeichen.trim().isNotEmpty
          ? '${result.betreff} (Ihr Zeichen: ${b.ihrZeichen.trim()})'
          : result.betreff;

      await db.into(db.anschreiben).insert(AnschreibenCompanion.insert(
            auftragId: Value(widget.auftrag.id),
            betreff: Value(indivBetreff),
            datum: Value(DateTime.now()),
            anrede: Value(anrede),
            briefText: Value(textOut),
            inhaltJson: Value(_plainTextToQuillDelta(textOut)),
            gruss: const Value('Mit freundlichen Grüßen'),
            status: const Value('entwurf'),
            extras: Value(extras),
          ));
      erstellt++;
    }

    // Optional: Gericht / Auftraggeber automatisch über den Ortstermin / die Umladung benachrichtigen.
    if (result.gerichtInformieren && widget.auftrag.kundeId != null) {
      final gerichtText = StringBuffer();
      if ((widget.auftrag.gerichtsAktenzeichen ?? '').trim().isNotEmpty) {
        gerichtText.writeln(
            'Geschäftszeichen: ${widget.auftrag.gerichtsAktenzeichen!.trim()}');
      }
      if (sache.isNotEmpty) {
        gerichtText.writeln('In Sachen: $sache');
      }
      if (gerichtText.isNotEmpty) gerichtText.writeln();
      if (istUmladung) {
        gerichtText.writeln(
            'in dem oben genannten Verfahren teile ich höflich mit, dass der ursprünglich für $altTerminText anberaumte Ortstermin${result.verlegtGrund.isNotEmpty ? " (${result.verlegtGrund})" : ""} auf folgenden neuen Termin verlegt wurde:');
      } else {
        gerichtText.writeln(
            'in dem oben genannten Verfahren teile ich höflich mit, dass der Ortstermin wie folgt anberaumt wurde:');
      }
      gerichtText.writeln();
      gerichtText.writeln('Termin: $terminText');
      gerichtText.writeln('Ort: ${result.ort.isEmpty ? "—" : result.ort}');
      gerichtText.writeln();
      final geladeneAlle = _baueGeladeneListe(result.empfaenger);
      if (geladeneAlle.isNotEmpty) {
        gerichtText.writeln(geladeneAlle);
        gerichtText.writeln();
      }
      gerichtText.write('Die Parteien bzw. ihre Prozessbevollmächtigten wurden gesondert benachrichtigt.');
      final gOut = gerichtText.toString();

      await db.into(db.anschreiben).insert(AnschreibenCompanion.insert(
            auftragId: Value(widget.auftrag.id),
            kundeId: Value(widget.auftrag.kundeId),
            betreff: Value(istUmladung
                ? 'Nachricht über Terminverlegung (Ortstermin)'
                : 'Nachricht über Anberaumung des Ortstermins'),
            datum: Value(DateTime.now()),
            anrede: const Value('Sehr geehrte Damen und Herren,'),
            briefText: Value(gOut),
            inhaltJson: Value(_plainTextToQuillDelta(gOut)),
            gruss: const Value('Mit freundlichen Grüßen'),
            status: const Value('entwurf'),
          ));
      erstellt++;
    }

    // Serienbrief-Historie mitschreiben.
    if (letzterBrieftext != null) {
      await db.into(db.serienbriefe).insert(SerienbriefeCompanion.insert(
            datum: Value(DateTime.now()),
            betreff: Value(result.betreff),
            anrede: const Value('Individuell je Beteiligtem'),
            gruss: const Value('Mit freundlichen Grüßen'),
            inhaltJson: Value(_plainTextToQuillDelta(letzterBrieftext)),
            versandart: Value(result.kanal == _Kanal.brief ? 'brief' : 'mail'),
            anzahl: Value(erstellt),
          ));
    }

    // Termin im eigenen Kalender (Wiedervorlagen-Tabelle).
    if (result.termin != null && result.inKalender) {
      await db.into(db.wiedervorlagen).insert(WiedervorlagenCompanion.insert(
            auftragId: Value(widget.auftrag.id),
            titel: '${istUmladung ? "Ortstermin (verlegt)" : "Ortstermin"}: ${widget.auftrag.aktenzeichen ?? result.betreff}',
            faelligAm: Value(result.termin!),
            endeAm: Value(result.termin!.add(const Duration(hours: 2))),
            beschreibung: Value(
                '${result.empfaenger.length} Beteiligte eingeladen (${result.uhrzeitVon}–${result.uhrzeitBis} Uhr).\nOrt: ${result.ort}'),
          ));
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
          '$erstellt ${istUmladung ? "Umladungs-Schreiben" : "Einladungs-Schreiben"} '
          'erzeugt${result.inKalender && result.termin != null ? " · Termin im Kalender & Akte hinterlegt" : ""}.'),
    ));
  }
}

class _BeteiligterRow extends StatefulWidget {
  const _BeteiligterRow({
    super.key,
    required this.b,
    required this.onChanged,
    required this.onRemove,
    required this.onBrief,
    required this.onMail,
  });
  final Beteiligter b;
  final VoidCallback onChanged;
  final VoidCallback onRemove;
  final VoidCallback onBrief;
  final VoidCallback onMail;
  @override
  State<_BeteiligterRow> createState() => _BeteiligterRowState();
}

class _BeteiligterRowState extends State<_BeteiligterRow> {
  late final _name = TextEditingController(text: widget.b.name);
  late final _strasse = TextEditingController(text: widget.b.strasse);
  late final _plz = TextEditingController(text: widget.b.plz);
  late final _ort = TextEditingController(text: widget.b.ort);
  late final _telefon = TextEditingController(text: widget.b.telefon);
  late final _email = TextEditingController(text: widget.b.email);
  late final _ihrZeichen = TextEditingController(text: widget.b.ihrZeichen);
  late final _vertritt = TextEditingController(text: widget.b.vertritt);
  late final _briefanrede = TextEditingController(text: widget.b.briefanrede);

  @override
  void dispose() {
    for (final c in [
      _name,
      _strasse,
      _plz,
      _ort,
      _telefon,
      _email,
      _ihrZeichen,
      _vertritt,
      _briefanrede,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration deco(String label, {String? hint}) => InputDecoration(
          labelText: label,
          hintText: hint,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          border: const OutlineInputBorder(),
        );
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        border:
            Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Zeile 1: OT-Häkchen, Rolle, Anrede, Name/Kanzlei, Straße, PLZ, Ort, Aktionen
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Tooltip(
                message: 'Zum Ortstermin einladen',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkbox(
                      visualDensity: VisualDensity.compact,
                      value: widget.b.zumOrtsterminLaden,
                      onChanged: (v) {
                        setState(() => widget.b.zumOrtsterminLaden = v ?? true);
                        widget.onChanged();
                      },
                    ),
                    const Text('OT', style: TextStyle(fontSize: 11)),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 155,
                child: DropdownButtonFormField<String>(
                  initialValue: beteiligtenRollen.contains(widget.b.rolle)
                      ? widget.b.rolle
                      : 'Sonstiger',
                  isDense: true,
                  decoration: deco('Rolle'),
                  items: [
                    for (final r in beteiligtenRollen)
                      DropdownMenuItem(
                        value: r,
                        child: Text(r, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) {
                    widget.b.rolle = v ?? 'Sonstiger';
                    widget.onChanged();
                  },
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 95,
                child: DropdownButtonFormField<String>(
                  initialValue: beteiligtenAnreden.contains(widget.b.anrede)
                      ? widget.b.anrede
                      : '',
                  isDense: true,
                  decoration: deco('Anrede'),
                  items: [
                    for (final a in beteiligtenAnreden)
                      DropdownMenuItem(
                        value: a,
                        child: Text(a.isEmpty ? '—' : a),
                      ),
                  ],
                  onChanged: (v) {
                    widget.b.anrede = v ?? '';
                    widget.onChanged();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _name,
                  decoration: deco('Name / Kanzlei / Firma'),
                  onChanged: (v) {
                    widget.b.name = v;
                    widget.onChanged();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _strasse,
                  decoration: deco('Straße & Hausnr.'),
                  onChanged: (v) {
                    widget.b.strasse = v;
                    widget.onChanged();
                  },
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 80,
                child: TextField(
                  controller: _plz,
                  decoration: deco('PLZ'),
                  onChanged: (v) {
                    widget.b.plz = v;
                    widget.onChanged();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _ort,
                  decoration: deco('Ort'),
                  onChanged: (v) {
                    widget.b.ort = v;
                    widget.onChanged();
                  },
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Einzel-Einladung (Brief) erzeugen',
                icon: const Icon(Icons.mail_outline, size: 18),
                onPressed: widget.onBrief,
              ),
              IconButton(
                tooltip: 'E-Mail direkt verfassen',
                icon: const Icon(Icons.alternate_email, size: 18),
                onPressed: widget.onMail,
              ),
              IconButton(
                tooltip: 'Eintrag löschen',
                icon: const Icon(Icons.close, size: 18),
                color: Theme.of(context).colorScheme.error,
                onPressed: widget.onRemove,
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Zeile 2: Ihr Zeichen (Kanzlei/Schaden-AZ), Vertritt, Versandart, Briefanrede, Telefon, E-Mail
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(width: 48), // Einrückung analog zur OT-Spalte
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _ihrZeichen,
                  decoration: deco('Ihr Zeichen / Geschäfts-AZ',
                      hint: 'z. B. 142/26-M'),
                  onChanged: (v) {
                    widget.b.ihrZeichen = v;
                    widget.onChanged();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _vertritt,
                  decoration: deco('Vertritt / Partei',
                      hint: 'z. B. Kläger / Beklagter'),
                  onChanged: (v) {
                    widget.b.vertritt = v;
                    widget.onChanged();
                  },
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 175,
                child: DropdownButtonFormField<String>(
                  initialValue:
                      beteiligtenVersandarten.contains(widget.b.versandart)
                          ? widget.b.versandart
                          : 'Brief',
                  isDense: true,
                  decoration: deco('Versandart'),
                  items: [
                    for (final va in beteiligtenVersandarten)
                      DropdownMenuItem(
                        value: va,
                        child: Text(va, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) {
                    widget.b.versandart = v ?? 'Brief';
                    widget.onChanged();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _briefanrede,
                  decoration: deco(
                    'Briefanrede (optional)',
                    hint: widget.b.effectiveBriefanrede,
                  ),
                  onChanged: (v) {
                    widget.b.briefanrede = v;
                    widget.onChanged();
                  },
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 135,
                child: TextField(
                  controller: _telefon,
                  decoration: deco('Telefon / Mobil'),
                  onChanged: (v) {
                    widget.b.telefon = v;
                    widget.onChanged();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _email,
                  decoration: deco('E-Mail'),
                  onChanged: (v) {
                    widget.b.email = v;
                    widget.onChanged();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _Kanal { brief, mail }

class _EinladungResult {
  final DateTime? termin;
  final DateTime? terminAlt;
  final String uhrzeitVon;
  final String uhrzeitBis;
  final String verlegtGrund;
  final String ort;
  final String betreff;
  final String hinweis;
  final List<Beteiligter> empfaenger;
  final _Kanal kanal;
  final bool inKalender;
  final bool inAkteSpeichern;
  final bool geladeneAuffuehren;
  final bool gerichtInformieren;

  const _EinladungResult({
    required this.termin,
    required this.terminAlt,
    required this.uhrzeitVon,
    required this.uhrzeitBis,
    required this.verlegtGrund,
    required this.ort,
    required this.betreff,
    required this.hinweis,
    required this.empfaenger,
    required this.kanal,
    required this.inKalender,
    required this.inAkteSpeichern,
    required this.geladeneAuffuehren,
    required this.gerichtInformieren,
  });
}

class _TerminEinladungDialog extends ConsumerStatefulWidget {
  const _TerminEinladungDialog({
    required this.auftrag,
    required this.beteiligte,
    required this.istUmladung,
  });
  final AuftraegeData auftrag;
  final List<Beteiligter> beteiligte;
  final bool istUmladung;
  @override
  ConsumerState<_TerminEinladungDialog> createState() =>
      _TerminEinladungDialogState();
}

class _TerminEinladungDialogState
    extends ConsumerState<_TerminEinladungDialog> {
  late final AuftragGmExtras _gm =
      AuftragGmExtras.fromAuftragExtras(widget.auftrag.extras);

  DateTime? _datum;
  DateTime? _datumAlt;
  TimeOfDay _zeit = const TimeOfDay(hour: 10, minute: 0);
  late final TextEditingController _uhrzeitVon;
  late final TextEditingController _uhrzeitBis;
  late final TextEditingController _verlegtGrund;
  late final TextEditingController _ort;
  late final TextEditingController _betreff;
  late final TextEditingController _hinweis;
  late final Set<int> _ausgewaehlt;
  _Kanal _kanal = _Kanal.brief;
  bool _inKalender = true;
  bool _inAkteSpeichern = true;
  bool _geladeneAuffuehren = true;
  late bool _gerichtInformieren;
  List<WiedervorlagenData> _konflikte = const [];

  @override
  void initState() {
    super.initState();
    _datum = widget.auftrag.ortsterminAm;
    _datumAlt = _gm.ortsterminAltAm ?? widget.auftrag.ortsterminAm;
    if (_datum != null && (_datum!.hour != 0 || _datum!.minute != 0)) {
      _zeit = TimeOfDay(hour: _datum!.hour, minute: _datum!.minute);
    }
    _uhrzeitVon = TextEditingController(
      text: _gm.ortsterminUhrzeitVon.isEmpty
          ? '10:00'
          : _gm.ortsterminUhrzeitVon,
    );
    _uhrzeitBis = TextEditingController(
      text: _gm.ortsterminUhrzeitBis.isEmpty
          ? '12:00'
          : _gm.ortsterminUhrzeitBis,
    );
    _verlegtGrund = TextEditingController(
      text: _gm.ortsterminVerlegtGrund.isEmpty
          ? 'auf Antrag einer Partei / wegen Terminkollision'
          : _gm.ortsterminVerlegtGrund,
    );
    _ort = TextEditingController(
      text: [
        widget.auftrag.objektStrasse,
        '${widget.auftrag.objektPlz ?? ''} ${widget.auftrag.objektOrt ?? ''}'
            .trim(),
      ].whereType<String>().where((s) => s.trim().isNotEmpty).join(', '),
    );
    _betreff = TextEditingController(
      text: widget.istUmladung
          ? 'Terminverlegung / Umladung zum Ortstermin'
          : 'Einladung zum Ortstermin',
    );
    _hinweis = TextEditingController(
      text:
          'Bitte teilen Sie mir kurzfristig mit, falls Sie den Termin nicht wahrnehmen können.',
    );
    _ausgewaehlt = {
      for (var i = 0; i < widget.beteiligte.length; i++)
        if (widget.beteiligte[i].zumOrtsterminLaden) i
    };
    if (_ausgewaehlt.isEmpty) {
      for (var i = 0; i < widget.beteiligte.length; i++) {
        _ausgewaehlt.add(i);
      }
    }
    _gerichtInformieren = widget.auftrag.art == 'gericht' ||
        widget.auftrag.art == 'beweissicherung';
    if (_datum != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _pruefeKonflikte());
    }
  }

  @override
  void dispose() {
    _uhrzeitVon.dispose();
    _uhrzeitBis.dispose();
    _verlegtGrund.dispose();
    _ort.dispose();
    _betreff.dispose();
    _hinweis.dispose();
    super.dispose();
  }

  DateTime? get _terminMoment {
    if (_datum == null) return null;
    final parts = _uhrzeitVon.text.trim().split(':');
    var h = _zeit.hour;
    var m = _zeit.minute;
    if (parts.length >= 2) {
      h = int.tryParse(parts[0]) ?? h;
      m = int.tryParse(parts[1]) ?? m;
    }
    return DateTime(_datum!.year, _datum!.month, _datum!.day, h, m);
  }

  Future<void> _waehleDatum({bool istAlt = false}) async {
    final init = (istAlt ? _datumAlt : _datum) ??
        DateTime.now().add(const Duration(days: 7));
    final picked = await showDatePicker(
      context: context,
      initialDate: init,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
      locale: const Locale('de'),
    );
    if (picked == null) return;
    setState(() {
      if (istAlt) {
        _datumAlt = picked;
      } else {
        _datum = picked;
      }
    });
    if (!istAlt) await _pruefeKonflikte();
  }

  Future<void> _pruefeKonflikte() async {
    if (_datum == null) return;
    final db = ref.read(appDatabaseProvider);
    final tagBeginn = DateTime(_datum!.year, _datum!.month, _datum!.day);
    final tagEnde = tagBeginn.add(const Duration(days: 1));
    final alle = await (db.select(db.wiedervorlagen)
          ..where((t) => t.erledigt.equals(false))
          ..orderBy([(t) => OrderingTerm(expression: t.faelligAm)]))
        .get();
    final rows = alle
        .where((w) =>
            !w.faelligAm.isBefore(tagBeginn) && w.faelligAm.isBefore(tagEnde))
        .toList();
    if (!mounted) return;
    setState(() => _konflikte = rows);
  }

  Future<void> _einfuegeTextbaustein() async {
    final db = ref.read(appDatabaseProvider);
    final liste = await (db.select(db.textbausteine)
          ..where((t) => t.kategorie.equals('anschreiben'))
          ..orderBy([(t) => OrderingTerm(expression: t.titel)]))
        .get();
    if (!mounted) return;
    if (liste.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Keine Anschreiben-Textbausteine hinterlegt — Modul „Textbausteine" nutzen.')));
      return;
    }
    final picked = await showDialog<TextbausteineData>(
      context: context,
      useRootNavigator: true,
      builder: (_) => Dialog(
        child: SizedBox(
          width: 540,
          height: 480,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child:
                    Text('Textbaustein wählen', style: TextStyle(fontSize: 16)),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: liste.length,
                  itemBuilder: (_, i) {
                    final t = liste[i];
                    return ListTile(
                      title: Text(t.titel),
                      subtitle: Text(t.inhalt ?? '',
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      onTap: () =>
                          Navigator.of(context, rootNavigator: true).pop(t),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    final cur = _hinweis.text.trim();
    final neu = picked.inhalt ?? '';
    setState(() {
      _hinweis.text = cur.isEmpty ? neu : '$cur\n\n$neu';
    });
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd.MM.yyyy', 'de');
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: 780,
        height: 820,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
              child: Row(children: [
                Icon(widget.istUmladung
                    ? Icons.update_outlined
                    : Icons.event_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                      widget.istUmladung
                          ? 'Umladung / Terminverlegung an Beteiligte'
                          : 'Ortstermin-Einladung (Serienbrief) an Beteiligte',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () =>
                      Navigator.of(context, rootNavigator: true).pop(),
                ),
              ]),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.istUmladung) ...[
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () => _waehleDatum(istAlt: true),
                              child: InputDecorator(
                                decoration: const InputDecoration(
                                    labelText: 'Bisheriger Termin (wird verlegt)'),
                                child: Row(children: [
                                  const Icon(Icons.history, size: 16),
                                  const SizedBox(width: 8),
                                  Text(_datumAlt == null
                                      ? '— Bisheriges Datum wählen —'
                                      : dateFmt.format(_datumAlt!)),
                                ]),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: _verlegtGrund,
                              decoration: const InputDecoration(
                                labelText: 'Grund der Terminverlegung',
                                hintText:
                                    'z. B. auf Antrag des Klägervertreters',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                    Row(children: [
                      Expanded(
                        flex: 2,
                        child: InkWell(
                          onTap: () => _waehleDatum(istAlt: false),
                          child: InputDecorator(
                            decoration: InputDecoration(
                                labelText: widget.istUmladung
                                    ? 'Neues Datum Ortstermin'
                                    : 'Datum Ortstermin'),
                            child: Row(children: [
                              const Icon(Icons.calendar_today_outlined,
                                  size: 16),
                              const SizedBox(width: 8),
                              Text(_datum == null
                                  ? '— Datum wählen —'
                                  : dateFmt.format(_datum!)),
                            ]),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _uhrzeitVon,
                          decoration: const InputDecoration(
                            labelText: 'Uhrzeit von',
                            hintText: '10:00',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _uhrzeitBis,
                          decoration: const InputDecoration(
                            labelText: 'Uhrzeit bis (ca.)',
                            hintText: '12:00',
                          ),
                        ),
                      ),
                    ]),
                    if (_konflikte.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .errorContainer
                              .withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: Theme.of(context).colorScheme.error,
                              width: 0.5),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                '⚠ ${_konflikte.length} Termin${_konflikte.length == 1 ? '' : 'e'} am '
                                '${dateFmt.format(_datum!)} bereits eingetragen:',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color:
                                        Theme.of(context).colorScheme.error)),
                            const SizedBox(height: 4),
                            for (final k in _konflikte)
                              Text(
                                  '  • ${DateFormat('HH:mm').format(k.faelligAm)} — ${k.titel}',
                                  style: const TextStyle(fontSize: 11)),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: _ort,
                      decoration: const InputDecoration(
                          labelText: 'Treffpunkt / Anschrift Ortstermin'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _betreff,
                      decoration: const InputDecoration(labelText: 'Betreff'),
                    ),
                    const SizedBox(height: 12),
                    Row(children: [
                      const Text('Hinweis / Schlusstext',
                          style: TextStyle(fontSize: 13)),
                      const Spacer(),
                      TextButton.icon(
                        icon: const Icon(Icons.article_outlined, size: 14),
                        label: const Text('Textbaustein'),
                        onPressed: _einfuegeTextbaustein,
                      ),
                    ]),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _hinweis,
                      minLines: 3,
                      maxLines: 6,
                      decoration: const InputDecoration(
                          alignLabelWithHint: true,
                          hintText:
                              'Bitte teilen Sie uns kurz mit, ob Sie den Termin wahrnehmen können …'),
                    ),
                    const SizedBox(height: 12),
                    Text('Zu ladende Beteiligte',
                        style: Theme.of(context).textTheme.titleSmall),
                    for (var i = 0; i < widget.beteiligte.length; i++)
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: _ausgewaehlt.contains(i),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _ausgewaehlt.add(i);
                          } else {
                            _ausgewaehlt.remove(i);
                          }
                        }),
                        title: Text(
                            '${widget.beteiligte[i].rolle} · ${widget.beteiligte[i].name}'
                            '${widget.beteiligte[i].ihrZeichen.trim().isNotEmpty ? " (AZ: ${widget.beteiligte[i].ihrZeichen.trim()})" : ""}'),
                        subtitle: Text(
                          [
                            widget.beteiligte[i].versandart,
                            if (widget.beteiligte[i].vertritt.isNotEmpty)
                              'vertritt: ${widget.beteiligte[i].vertritt}',
                            if (widget.beteiligte[i].email.isNotEmpty)
                              widget.beteiligte[i].email,
                          ].join(' · '),
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    const Divider(height: 16),
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: _geladeneAuffuehren,
                      onChanged: (v) =>
                          setState(() => _geladeneAuffuehren = v ?? true),
                      title: const Text(
                          'Im Schreiben aufführen: „Zu diesem Termin wurden außerdem geladen: …"'),
                    ),
                    if (widget.auftrag.kundeId != null)
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: _gerichtInformieren,
                        onChanged: (v) =>
                            setState(() => _gerichtInformieren = v ?? false),
                        title: const Text(
                            'Zusätzlich Nachricht über Ortstermin an Auftraggeber / Gericht erzeugen'),
                      ),
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: _inAkteSpeichern,
                      onChanged: (v) =>
                          setState(() => _inAkteSpeichern = v ?? true),
                      title: const Text(
                          'Datum, Uhrzeit und ggf. Verlegungsgrund direkt in den Akten-Stammdaten speichern'),
                    ),
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: _inKalender,
                      onChanged: (v) =>
                          setState(() => _inKalender = v ?? true),
                      title: const Text(
                          'Termin in meinem Kalender (Wiedervorlagen) eintragen'),
                    ),
                    const SizedBox(height: 8),
                    Row(children: [
                      const Text('Standard-Ausgabe:',
                          style: TextStyle(fontSize: 13)),
                      const SizedBox(width: 12),
                      SegmentedButton<_Kanal>(
                        segments: const [
                          ButtonSegment(
                              value: _Kanal.brief,
                              icon: Icon(Icons.mail_outline, size: 14),
                              label: Text('Anschreiben (Brief/PDF)')),
                          ButtonSegment(
                              value: _Kanal.mail,
                              icon: Icon(Icons.alternate_email, size: 14),
                              label: Text('E-Mail-Entwurf')),
                        ],
                        selected: {_kanal},
                        onSelectionChanged: (s) =>
                            setState(() => _kanal = s.first),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(children: [
                Text(
                  '${_ausgewaehlt.length + (_gerichtInformieren && widget.auftrag.kundeId != null ? 1 : 0)} Schreiben werden erzeugt.',
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () =>
                      Navigator.of(context, rootNavigator: true).pop(),
                  child: const Text('Abbrechen'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  icon: const Icon(Icons.send_outlined, size: 16),
                  label: Text(widget.istUmladung
                      ? 'Umladung erzeugen'
                      : 'Einladungen erzeugen'),
                  onPressed: _ausgewaehlt.isEmpty
                      ? null
                      : () {
                          final empfaenger = [
                            for (final i in _ausgewaehlt) widget.beteiligte[i]
                          ];
                          Navigator.of(context, rootNavigator: true).pop(
                            _EinladungResult(
                              termin: _terminMoment,
                              terminAlt: _datumAlt,
                              uhrzeitVon: _uhrzeitVon.text.trim(),
                              uhrzeitBis: _uhrzeitBis.text.trim(),
                              verlegtGrund: _verlegtGrund.text.trim(),
                              ort: _ort.text.trim(),
                              betreff: _betreff.text.trim().isEmpty
                                  ? (widget.istUmladung
                                      ? 'Umladung zum Ortstermin'
                                      : 'Einladung zum Ortstermin')
                                  : _betreff.text.trim(),
                              hinweis: _hinweis.text.trim(),
                              empfaenger: empfaenger,
                              kanal: _kanal,
                              inKalender: _inKalender,
                              inAkteSpeichern: _inAkteSpeichern,
                              geladeneAuffuehren: _geladeneAuffuehren,
                              gerichtInformieren: _gerichtInformieren,
                            ),
                          );
                        },
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
