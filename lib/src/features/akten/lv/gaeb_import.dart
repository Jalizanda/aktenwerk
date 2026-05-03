import 'dart:typed_data';

import 'package:xml/xml.dart';

/// Eine geparste GAEB-Position aus einem importierten LV.
class GaebPosition {
  final String? oz;
  final String art; // 'titel' | 'normal' | 'bedarf' | 'eventual' | 'stundenlohn' | 'grundtext'
  final String kurztext;
  final String? langtext;
  final String? einheit;
  final double? menge;
  final double? einzelpreis;
  final String? gaebUuid;
  final int parentIdx; // Index in der Liste, -1 = Top-Level

  const GaebPosition({
    required this.art,
    required this.kurztext,
    required this.parentIdx,
    this.oz,
    this.langtext,
    this.einheit,
    this.menge,
    this.einzelpreis,
    this.gaebUuid,
  });
}

class GaebImportResult {
  final String? projektName;
  final String? phaseCode; // '81' / '83' / '84'
  final List<GaebPosition> positionen;

  const GaebImportResult({
    required this.positionen,
    this.projektName,
    this.phaseCode,
  });
}

/// Parst GAEB DA XML 3.2 (Phasen X81 / X83 / X84). Liefert eine flache
/// Liste mit `parentIdx`-Verweis auf das übergeordnete Titel-Element.
/// Bewusst tolerant — unvollständige LVs werden bestmöglich geladen.
GaebImportResult parseGaebXml(Uint8List bytes) {
  final doc = XmlDocument.parse(String.fromCharCodes(bytes));
  final positionen = <GaebPosition>[];

  // Projekt-Info
  final prjName = doc
      .findAllElements('NamePrj')
      .firstOrNull
      ?.innerText
      .trim();

  // Phase aus <DP Cat="83">
  String? phase;
  final dp = doc.findAllElements('DP').firstOrNull;
  if (dp != null) {
    phase = dp.getAttribute('Cat');
  }

  void traverse(XmlElement parent, int parentIdx) {
    for (final child in parent.children.whereType<XmlElement>()) {
      switch (child.localName) {
        case 'BoQCtgy':
          // Titel/Strukturzeile
          final oz = child.getAttribute('RNoPart');
          final label = _findText(child, 'LblTx') ??
              _findText(child, 'OutlTxt') ??
              '(Titel)';
          positionen.add(GaebPosition(
            oz: oz,
            art: 'titel',
            kurztext: label,
            parentIdx: parentIdx,
          ));
          final myIdx = positionen.length - 1;
          // Kinder rekursiv (kann verschachtelte Titel und Items enthalten).
          final body = child.findElements('BoQBody').firstOrNull;
          if (body != null) {
            traverse(body, myIdx);
          } else {
            traverse(child, myIdx);
          }
        case 'Item':
          final oz = child.getAttribute('RNoPart');
          final uuid = child.getAttribute('ID');
          final itemType = _findText(child, 'ItemType') ?? 'BoQItem';
          final art = _mapGaebArt(itemType);
          final kurztext =
              _findDeepText(child, ['OutlTxt', 'TextOutlTxt']) ??
                  _findText(child, 'OutlTxt') ??
                  '(ohne Kurztext)';
          final langtext =
              _findDeepText(child, ['TextComplTxt']);
          final qu = _findText(child, 'QU');
          final qty = _parseDouble(_findText(child, 'Qty'));
          final up = _parseDouble(_findText(child, 'UP'));
          positionen.add(GaebPosition(
            oz: oz,
            art: art,
            kurztext: kurztext,
            langtext: langtext,
            einheit: qu,
            menge: qty,
            einzelpreis: up,
            gaebUuid: uuid,
            parentIdx: parentIdx,
          ));
        default:
          // Container — weiter absteigen.
          traverse(child, parentIdx);
      }
    }
  }

  final boqBody = doc.findAllElements('BoQBody').firstOrNull;
  if (boqBody != null) {
    traverse(boqBody, -1);
  }

  return GaebImportResult(
    projektName: prjName,
    phaseCode: phase,
    positionen: positionen,
  );
}

String _mapGaebArt(String itemType) {
  switch (itemType) {
    case 'BeP':
      return 'bedarf';
    case 'AltP':
      return 'eventual';
    case 'StdP':
      return 'stundenlohn';
    default:
      return 'normal';
  }
}

String? _findText(XmlElement parent, String localName) {
  final el = parent.findAllElements(localName).firstOrNull;
  if (el == null) return null;
  final txt = _flattenText(el);
  return txt.isEmpty ? null : txt;
}

/// Sucht nach erstem passenden Element auf einem beliebigen Pfad,
/// liefert dessen kompletten Textinhalt.
String? _findDeepText(XmlElement parent, List<String> path) {
  XmlElement? current = parent;
  for (final name in path) {
    current = current?.findAllElements(name).firstOrNull;
    if (current == null) return null;
  }
  if (current == null) return null;
  final txt = _flattenText(current);
  return txt.isEmpty ? null : txt;
}

/// Verkettet alle Textknoten eines Elements zu einem String — nützlich,
/// weil GAEB den Kurztext oft in `<p><span>...</span></p>` einpackt.
String _flattenText(XmlElement el) {
  final parts = <String>[];
  for (final node in el.descendants) {
    if (node is XmlText) {
      final s = node.value.trim();
      if (s.isNotEmpty) parts.add(s);
    }
  }
  return parts.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}

double? _parseDouble(String? s) {
  if (s == null || s.trim().isEmpty) return null;
  return double.tryParse(s.replaceAll(',', '.').trim());
}
