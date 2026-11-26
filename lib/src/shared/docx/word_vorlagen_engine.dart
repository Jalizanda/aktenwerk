// Word-Vorlagen-Engine (.docx) – füllt Word-Vorlagen mit Aktendaten.
//
// Unterstützte Platzhalter (kompatibel zu Gutachten-Manager-Vorlagen und
// zur Aktenwerk-Syntax):
//   $Platzhalter        – Textersetzung, auch wenn Word den Text in mehrere
//                          „Runs“ zerlegt hat
//   {{platzhalter}}     – Aktenwerk-Syntax
//   «Seriendruckfeld»   – MERGEFIELD-Felder, inkl. «TableStart:X» …
//                          «TableEnd:X» für wiederholte Tabellenzeilen
//   PHPlatzhalter       – Platzhalter aus E-Mail-Vorlagen
//   #Name               – ganzer Absatz wird durch einen Textblock ersetzt
//   $BeteiligtePersonen – eine Tabellenzeile je Beteiligtem
// Zusätzlich: Serienbrief (ein Brief je Empfänger, Seitenzählung je Brief)
// und Übernahme von Kopf-/Fußzeilen aus einer separaten Briefkopf-Datei.

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Liefert den Ersatzwert zu einem Token (`$Sache`, `«Name»`, `{{sache}}` …)
/// oder `null`, wenn das Token unbekannt ist (es bleibt dann stehen).
typedef WordResolver = String? Function(String token);

final RegExp _tokenRe = RegExp(
    r'\$[A-Za-zÄÖÜäöüß][A-Za-zÄÖÜäöüß0-9_]*|«[^«»]+»|\bPH[A-Z][A-Za-z0-9]*|\{\{[A-Za-z0-9_.]+\}\}');

const _relHeader =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships/header';
const _relFooter =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer';
const _ctHeader =
    'application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml';
const _ctFooter =
    'application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml';

// ---------------------------------------------------------------------------
// XML-Helfer
// ---------------------------------------------------------------------------

Iterable<XmlElement> _desc(XmlNode n, String name) => n.descendants
    .whereType<XmlElement>()
    .where((e) => e.name.qualified == name);

Iterable<XmlElement> _kids(XmlNode n, [String? name]) => n.children
    .whereType<XmlElement>()
    .where((e) => name == null || e.name.qualified == name);

XmlElement? _ancestor(XmlNode n, String name, [XmlNode? stop]) {
  XmlNode? p = n.parent;
  while (p != null && p != stop) {
    if (p is XmlElement && p.name.qualified == name) return p;
    p = p.parent;
  }
  return null;
}

XmlElement _el(String name,
        {Map<String, String> attrs = const {},
        List<XmlNode> kinder = const []}) =>
    XmlElement(
      XmlName.fromString(name),
      [for (final e in attrs.entries) XmlAttribute(XmlName.fromString(e.key), e.value)],
      kinder,
    );

XmlElement _t(String text) =>
    _el('w:t', attrs: {'xml:space': 'preserve'}, kinder: [XmlText(text)]);

void _remove(XmlNode n) {
  if (n.parent != null) n.remove();
}

void _insertBefore(XmlNode neu, XmlNode ref) {
  final parent = ref.parent!;
  parent.children.insert(parent.children.indexOf(ref), neu);
}

List<XmlElement> _textNodesOf(XmlElement p) =>
    _desc(p, 'w:t').where((t) => _ancestor(t, 'w:p') == p).toList();

String paragraphText(XmlElement p) =>
    _textNodesOf(p).map((t) => t.innerText).join();

bool _hasGraphic(XmlElement p) => ['w:drawing', 'w:pict', 'w:object']
    .any((n) => _desc(p, n).isNotEmpty);

void _ohneLesezeichen(XmlNode n) {
  for (final b in [..._desc(n, 'w:bookmarkStart'), ..._desc(n, 'w:bookmarkEnd')]) {
    _remove(b);
  }
}

// ---------------------------------------------------------------------------
// Felder (MERGEFIELD, SEQ) in Text-Tokens «Name» umwandeln
// ---------------------------------------------------------------------------

class _Feld {
  _Feld(this.begin);
  final XmlElement begin;
  XmlElement? sep;
  XmlElement? end;
  final StringBuffer instr = StringBuffer();
  final List<XmlElement> resultRuns = [];
}

final _mergeRe = RegExp(r'^\s*MERGEFIELD\s+"?([^\s"\\]+)"?', caseSensitive: false);

void normalizeFields(XmlNode root, {bool seq = false}) {
  for (final fs in _desc(root, 'w:fldSimple').toList()) {
    final m = _mergeRe.firstMatch(fs.getAttribute('w:instr') ?? '');
    if (m == null) continue;
    final run = _el('w:r');
    final first = _kids(fs, 'w:r').firstOrNull;
    final rPr = first == null ? null : _kids(first, 'w:rPr').firstOrNull;
    if (rPr != null) run.children.add(rPr.copy());
    run.children.add(_t('«${m.group(1)}»'));
    _insertBefore(run, fs);
    _remove(fs);
  }

  final stack = <_Feld>[];
  final felder = <_Feld>[];
  for (final r in _desc(root, 'w:r').toList()) {
    for (final c in _kids(r)) {
      final n = c.name.qualified;
      if (n == 'w:fldChar') {
        final typ = c.getAttribute('w:fldCharType');
        if (typ == 'begin') {
          stack.add(_Feld(r));
        } else if (typ == 'separate' && stack.isNotEmpty) {
          stack.last.sep = r;
        } else if (typ == 'end' && stack.isNotEmpty) {
          final f = stack.removeLast()..end = r;
          felder.add(f);
        }
      } else if (n == 'w:instrText' && stack.isNotEmpty) {
        stack.last.instr.write(c.innerText);
      } else if (n == 'w:t' && stack.isNotEmpty && stack.last.sep != null) {
        stack.last.resultRuns.add(r);
      }
    }
  }
  for (final f in felder.reversed) {
    final instr = f.instr.toString();
    String? name = _mergeRe.firstMatch(instr)?.group(1);
    if (name == null && seq && RegExp(r'^\s*SEQ\b', caseSensitive: false).hasMatch(instr)) {
      name = '__SEQ';
    }
    if (name == null) continue;
    final parent = f.begin.parent;
    if (parent == null || f.end == null || parent != f.end!.parent) continue;
    final run = _el('w:r');
    final src = f.resultRuns.firstWhere((r) => r.parent != null, orElse: () => f.begin);
    final rPr = _kids(src, 'w:rPr').firstOrNull;
    if (rPr != null) run.children.add(rPr.copy());
    run.children.add(_t('«$name»'));
    final iB = parent.children.indexOf(f.begin);
    parent.children.insert(iB, run);
    final start = iB + 1;
    final ende = parent.children.indexOf(f.end!);
    if (ende >= start) parent.children.removeRange(start, ende + 1);
  }
}

// ---------------------------------------------------------------------------
// Textersetzung innerhalb eines Absatzes (über Run-Grenzen hinweg)
// ---------------------------------------------------------------------------

bool replaceInParagraph(
  XmlElement p,
  WordResolver resolver, {
  RegExp? regex,
  bool leereZeilenEntfernen = true,
}) {
  final tns = _textNodesOf(p);
  if (tns.isEmpty) return false;
  final texts = tns.map((t) => t.innerText).toList();
  final full = texts.join();
  final re = regex ?? _tokenRe;
  final matches = re.allMatches(full).toList();
  if (matches.isEmpty) return false;

  var nurSeriendruck = true;
  var alleLeer = true;
  final ersetzungen = <(int, int, String)>[];
  for (final m in matches) {
    final tok = m.group(0)!;
    if (!tok.startsWith('«')) nurSeriendruck = false;
    final v = resolver(tok);
    if (v == null) {
      alleLeer = false;
      continue;
    }
    if (v.trim().isNotEmpty) alleLeer = false;
    ersetzungen.add((m.start, m.end, v));
  }
  if (ersetzungen.isEmpty) return false;

  final starts = <int>[];
  var pos = 0;
  for (final t in texts) {
    starts.add(pos);
    pos += t.length;
  }
  int locate(int i) {
    for (var k = texts.length - 1; k >= 0; k--) {
      if (i >= starts[k]) return k;
    }
    return 0;
  }

  for (final (s, e, v) in ersetzungen.reversed) {
    final a = locate(s);
    final b = locate(e - 1);
    if (a == b) {
      final t = texts[a];
      texts[a] = t.substring(0, s - starts[a]) + v + t.substring(e - starts[a]);
    } else {
      texts[a] = texts[a].substring(0, s - starts[a]) + v;
      for (var k = a + 1; k < b; k++) {
        texts[k] = '';
      }
      texts[b] = texts[b].substring(e - starts[b]);
    }
  }
  for (var i = 0; i < tns.length; i++) {
    if (tns[i].innerText != texts[i]) {
      tns[i].innerText = texts[i];
      tns[i].setAttribute('xml:space', 'preserve');
    }
  }

  // Adresszeilen, die nur aus leeren Seriendruckfeldern bestanden, entfernen.
  if (leereZeilenEntfernen && nurSeriendruck && alleLeer && !_hasGraphic(p)) {
    final rest = full.replaceAll(re, '').trim();
    final tc = _ancestor(p, 'w:tc');
    final geschwister = tc == null ? 2 : _kids(tc, 'w:p').length;
    if (rest.isEmpty && geschwister > 1 && _desc(p, 'w:br').isEmpty) _remove(p);
  }
  return true;
}

/// Zeilenumbrüche (\n) in Werten in echte Word-Zeilenumbrüche umwandeln.
void expandSpecials(XmlNode root) {
  for (final t in _desc(root, 'w:t').toList()) {
    final s = t.innerText;
    if (!s.contains('\n')) continue;
    final teile = s.replaceAll('\r', '').split('\n');
    for (var i = 0; i < teile.length; i++) {
      if (i > 0) _insertBefore(_el('w:br'), t);
      if (teile[i].isNotEmpty) _insertBefore(_t(teile[i]), t);
    }
    _remove(t);
  }
}

// ---------------------------------------------------------------------------
// Tabellenbereiche «TableStart:X» … «TableEnd:X»
// ---------------------------------------------------------------------------

void expandTables(
  XmlNode root,
  Map<String, List<Map<String, String>>> tabellen,
  WordResolver? global,
) {
  for (var guard = 0; guard < 200; guard++) {
    XmlElement? startP;
    String? name;
    for (final p in _desc(root, 'w:p')) {
      final m = RegExp(r'«TableStart:([^»]+)»').firstMatch(paragraphText(p));
      if (m != null) {
        startP = p;
        name = m.group(1);
        break;
      }
    }
    if (startP == null || name == null) return;
    final key = tabellen.keys.firstWhere(
        (k) => k.toLowerCase() == name!.toLowerCase(),
        orElse: () => '');
    final recs = key.isEmpty ? const <Map<String, String>>[] : tabellen[key]!;
    final endTok = '«TableEnd:$name»';
    final startRow = _ancestor(startP, 'w:tr', root);
    final block = <XmlElement>[];
    if (startRow != null) {
      final parent = startRow.parent!;
      var i = parent.children.indexOf(startRow);
      for (; i < parent.children.length; i++) {
        final n = parent.children[i];
        if (n is! XmlElement || n.name.qualified != 'w:tr') continue;
        block.add(n);
        if (_desc(n, 'w:p').any((p) => paragraphText(p).contains(endTok))) break;
      }
    } else {
      final parent = startP.parent!;
      var i = parent.children.indexOf(startP);
      for (; i < parent.children.length; i++) {
        final n = parent.children[i];
        if (n is! XmlElement) continue;
        block.add(n);
        final hit = n.name.qualified == 'w:p'
            ? paragraphText(n).contains(endTok)
            : _desc(n, 'w:p').any((p) => paragraphText(p).contains(endTok));
        if (hit) break;
      }
    }
    final anchor = block.first;
    for (var r = 0; r < recs.length; r++) {
      final rec = recs[r];
      String? recRes(String tok) {
        if (tok.startsWith('«TableStart:') || tok.startsWith('«TableEnd:')) return '';
        if (tok.startsWith('«')) {
          final k = tok.substring(1, tok.length - 1).replaceFirst('Image:', '');
          if (k == '__SEQ') return '${r + 1}';
          for (final e in rec.entries) {
            if (e.key.toLowerCase() == k.toLowerCase()) return e.value;
          }
        }
        return global?.call(tok);
      }

      for (final b in block) {
        final c = b.copy();
        _ohneLesezeichen(c);
        _insertBefore(c, anchor);
        normalizeFields(c, seq: true);
        if (c.name.qualified == 'w:p') {
          replaceInParagraph(c, recRes);
        } else {
          for (final p in _desc(c, 'w:p').toList()) {
            replaceInParagraph(p, recRes);
          }
        }
      }
    }
    final tbl = startRow == null ? null : _ancestor(startRow, 'w:tbl');
    for (final b in block) {
      _remove(b);
    }
    if (tbl != null && _kids(tbl, 'w:tr').isEmpty) _remove(tbl);
  }
}

// ---------------------------------------------------------------------------
// $BeteiligtePersonen – eine Tabellenzeile je Beteiligtem
// ---------------------------------------------------------------------------

void setCellText(XmlElement tc, String text) {
  final ps = _kids(tc, 'w:p').toList();
  final XmlElement p;
  if (ps.isNotEmpty) {
    p = ps.first;
  } else {
    p = _el('w:p');
    tc.children.add(p);
  }
  for (final x in ps.skip(1)) {
    _remove(x);
  }
  final firstRun = _kids(p, 'w:r').firstOrNull;
  final rPr = firstRun == null ? null : _kids(firstRun, 'w:rPr').firstOrNull?.copy();
  for (final c in _kids(p).toList()) {
    if (c.name.qualified != 'w:pPr') _remove(c);
  }
  p.children.add(_el('w:r', kinder: [?rPr, _t(text)]));
}

void expandBeteiligte(XmlNode root, List<(String, String)> personen) {
  final re = RegExp(r'\$BeteiligtePersonen\b(?!All)');
  for (final p in _desc(root, 'w:p').toList()) {
    if (p.parent == null || !re.hasMatch(paragraphText(p))) continue;
    final row = _ancestor(p, 'w:tr', root);
    if (row == null) {
      replaceInParagraph(
          p,
          (t) => t == r'$BeteiligtePersonen'
              ? personen.map((x) => '${x.$1}: ${x.$2.replaceAll('\n', ', ')}').join('\n')
              : null);
      continue;
    }
    for (final pers in personen) {
      final c = row.copy();
      _ohneLesezeichen(c);
      _insertBefore(c, row);
      final zellen = _kids(c, 'w:tc').toList();
      final idx = zellen.indexWhere((tc) =>
          _desc(tc, 'w:p').map(paragraphText).join().contains(r'$BeteiligtePersonen'));
      if (idx < 0) continue;
      for (final pp in _desc(zellen[idx], 'w:p').toList()) {
        replaceInParagraph(pp, (t) => t == r'$BeteiligtePersonen' ? pers.$1 : null);
      }
      if (idx + 1 < zellen.length) setCellText(zellen[idx + 1], pers.$2);
    }
    _remove(row);
  }
}

List<XmlElement> textToParagraphs(String text, XmlElement? vorlageP) {
  final pPr = vorlageP == null ? null : _kids(vorlageP, 'w:pPr').firstOrNull;
  final run = vorlageP == null ? null : _kids(vorlageP, 'w:r').firstOrNull;
  final rPr = run == null ? null : _kids(run, 'w:rPr').firstOrNull;
  return text.replaceAll('\r', '').split('\n').map((zeile) {
    return _el('w:p', kinder: [
      if (pPr != null) pPr.copy(),
      _el('w:r', kinder: [if (rPr != null) rPr.copy(), _t(zeile)]),
    ]);
  }).toList();
}

// ---------------------------------------------------------------------------
// Paket (ZIP + Beziehungen + Content-Types)
// ---------------------------------------------------------------------------

class _Paket {
  _Paket(Uint8List bytes) {
    final arch = ZipDecoder().decodeBytes(bytes);
    for (final f in arch.files) {
      if (f.isFile) dateien[f.name] = f.content;
    }
  }

  final Map<String, Uint8List> dateien = {};
  final Map<String, XmlDocument> _xml = {};
  int _relZaehler = 0;

  XmlDocument? xml(String name) {
    if (_xml.containsKey(name)) return _xml[name];
    final b = dateien[name];
    if (b == null) return null;
    return _xml[name] = XmlDocument.parse(utf8.decode(b, allowMalformed: true));
  }

  String _relsName(String part) {
    final i = part.lastIndexOf('/');
    return '${part.substring(0, i)}/_rels/${part.substring(i + 1)}.rels';
  }

  String addRel(String part, String type, String target) {
    final name = _relsName(part);
    var rels = xml(name);
    if (rels == null) {
      rels = XmlDocument.parse(
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"/>');
      _xml[name] = rels;
    }
    final ids = rels.rootElement.childElements.map((e) => e.getAttribute('Id')).toSet();
    String id;
    do {
      id = 'rIdAW${++_relZaehler}';
    } while (ids.contains(id));
    rels.rootElement.children.add(_el('Relationship',
        attrs: {'Id': id, 'Type': type, 'Target': target}));
    return id;
  }

  void contentTypeDefault(String ext, String mime) {
    final ct = xml('[Content_Types].xml')!;
    final root = ct.rootElement;
    final vorhanden = root.childElements.any((e) =>
        e.name.local == 'Default' &&
        (e.getAttribute('Extension') ?? '').toLowerCase() == ext.toLowerCase());
    if (!vorhanden) {
      root.children.insert(0, _el('Default', attrs: {'Extension': ext, 'ContentType': mime}));
    }
  }

  void contentTypeOverride(String partName, String mime) {
    xml('[Content_Types].xml')!
        .rootElement
        .children
        .add(_el('Override', attrs: {'PartName': partName, 'ContentType': mime}));
  }

  Uint8List schreiben() {
    for (final e in _xml.entries) {
      dateien[e.key] = Uint8List.fromList(utf8.encode(e.value.toXmlString()));
    }
    final arch = Archive();
    for (final e in dateien.entries) {
      arch.addFile(ArchiveFile.bytes(e.key, e.value));
    }
    return Uint8List.fromList(ZipEncoder().encode(arch));
  }
}

// ---------------------------------------------------------------------------
// Briefkopf (Kopf-/Fußzeilen) aus separater .docx übernehmen
// ---------------------------------------------------------------------------

List<String> _briefkopfUebernehmen(_Paket ziel, Uint8List bkBytes) {
  final bk = _Paket(bkBytes);
  final bkDoc = bk.xml('word/document.xml');
  final bkRels = bk.xml('word/_rels/document.xml.rels');
  if (bkDoc == null || bkRels == null) return const [];
  final bkSect = _desc(bkDoc, 'w:sectPr').lastOrNull;
  if (bkSect == null) return const [];
  final doc = ziel.xml('word/document.xml')!;
  final refs = <(String, String, String)>[]; // name, type, rid
  final neueParts = <String>[];

  for (final ref in _kids(bkSect).where((k) =>
      k.name.qualified == 'w:headerReference' || k.name.qualified == 'w:footerReference')) {
    final rel = bkRels.rootElement.childElements
        .where((r) => r.getAttribute('Id') == ref.getAttribute('r:id'))
        .firstOrNull;
    if (rel == null) continue;
    final target = rel.getAttribute('Target')!;
    final isHeader = ref.name.qualified == 'w:headerReference';
    final neuName = 'bk_${target.replaceAll('/', '_')}';
    final inhalt = bk.dateien['word/$target'];
    if (inhalt == null) continue;
    ziel.dateien['word/$neuName'] = inhalt;
    final relDatei = bk.xml('word/_rels/$target.rels');
    if (relDatei != null) {
      final kopie = XmlDocument.parse(relDatei.toXmlString());
      for (final r in kopie.rootElement.childElements) {
        if (r.getAttribute('TargetMode') == 'External') continue;
        final t = r.getAttribute('Target') ?? '';
        final daten = bk.dateien['word/$t'];
        if (daten == null) continue;
        final basis = t.split('/').last;
        final nt = 'media/bk_$basis';
        ziel.dateien['word/$nt'] = daten;
        r.setAttribute('Target', nt);
        final ext = basis.contains('.') ? basis.split('.').last.toLowerCase() : '';
        const mimes = {
          'png': 'image/png', 'jpg': 'image/jpeg', 'jpeg': 'image/jpeg',
          'gif': 'image/gif', 'emf': 'image/x-emf', 'wmf': 'image/x-wmf',
          'svg': 'image/svg+xml',
        };
        if (mimes.containsKey(ext)) ziel.contentTypeDefault(ext, mimes[ext]!);
      }
      ziel.dateien['word/_rels/$neuName.rels'] =
          Uint8List.fromList(utf8.encode(kopie.toXmlString()));
    }
    ziel.contentTypeOverride('/word/$neuName', isHeader ? _ctHeader : _ctFooter);
    final rid = ziel.addRel('word/document.xml', isHeader ? _relHeader : _relFooter, neuName);
    refs.add((ref.name.qualified, ref.getAttribute('w:type') ?? 'default', rid));
    neueParts.add('word/$neuName');
  }

  // fehlende Formatvorlagen übernehmen
  final st = ziel.xml('word/styles.xml');
  final bst = bk.xml('word/styles.xml');
  if (st != null && bst != null) {
    final vorhanden =
        _desc(st, 'w:style').map((s) => s.getAttribute('w:styleId')).toSet();
    for (final s in _desc(bst, 'w:style')) {
      if (!vorhanden.contains(s.getAttribute('w:styleId'))) {
        st.rootElement.children.add(s.copy());
      }
    }
  }

  final bkTitle = _kids(bkSect, 'w:titlePg').isNotEmpty;
  final bkMar = _kids(bkSect, 'w:pgMar').firstOrNull;
  for (final sect in _desc(doc, 'w:sectPr').toList()) {
    for (final k in _kids(sect).toList()) {
      final n = k.name.qualified;
      if (n == 'w:headerReference' || n == 'w:footerReference') _remove(k);
    }
    var i = 0;
    for (final r in refs) {
      sect.children.insert(i++, _el(r.$1, attrs: {'w:type': r.$2, 'r:id': r.$3}));
    }
    final m = _kids(sect, 'w:pgMar').firstOrNull;
    if (bkMar != null && m != null) {
      for (final a in ['w:top', 'w:bottom', 'w:header', 'w:footer']) {
        final v = bkMar.getAttribute(a);
        if (v != null) m.setAttribute(a, v);
      }
    }
    final tp = _kids(sect, 'w:titlePg').firstOrNull;
    if (bkTitle && tp == null) {
      const nach = ['w:textDirection', 'w:bidi', 'w:rtlGutter', 'w:docGrid', 'w:printerSettings', 'w:sectPrChange'];
      final ref = _kids(sect).where((k) => nach.contains(k.name.qualified)).firstOrNull;
      final neu = _el('w:titlePg');
      if (ref != null) {
        _insertBefore(neu, ref);
      } else {
        sect.children.add(neu);
      }
    } else if (!bkTitle && tp != null) {
      _remove(tp);
    }
  }
  return neueParts;
}

void _seitenzaehlungNeu(XmlElement sect) {
  for (final k in _kids(sect, 'w:pgNumType').toList()) {
    _remove(k);
  }
  const nach = ['w:cols', 'w:formProt', 'w:vAlign', 'w:noEndnote', 'w:titlePg',
    'w:textDirection', 'w:bidi', 'w:rtlGutter', 'w:docGrid', 'w:printerSettings', 'w:sectPrChange'];
  final ref = _kids(sect).where((k) => nach.contains(k.name.qualified)).firstOrNull;
  final neu = _el('w:pgNumType', attrs: {'w:start': '1'});
  if (ref != null) {
    _insertBefore(neu, ref);
  } else {
    sect.children.add(neu);
  }
}

// ---------------------------------------------------------------------------
// Hauptfunktion
// ---------------------------------------------------------------------------

/// Erzeugt ein Word-Dokument aus [vorlage].
///
/// * [resolver] – liefert Werte zu `$…`, `{{…}}`, `«…»`, `PH…`.
/// * [tabellen] – Datensätze für «TableStart:X»-Bereiche.
/// * [personen] – (Rolle, Anschrift) für `$BeteiligtePersonen`.
/// * [empfaenger] – Serienbrief: je Empfänger ein Resolver (für «An», «Name» …).
/// * [raute] – Inhalt für Absätze, die nur aus `#Name` bestehen
///   (`null` = unbekannt, Absatz bleibt; `''` = Absatz entfällt).
/// * [briefkopf] – .docx, deren Kopf-/Fußzeilen übernommen werden.
Uint8List erzeugeWordDokument({
  required Uint8List vorlage,
  required WordResolver resolver,
  Map<String, List<Map<String, String>>> tabellen = const {},
  List<(String, String)>? personen,
  List<WordResolver>? empfaenger,
  String? Function(String name)? raute,
  Uint8List? briefkopf,
  bool felderAktualisieren = false,
}) {
  final pkg = _Paket(vorlage);
  final doc = pkg.xml('word/document.xml');
  if (doc == null) {
    throw const FormatException('Die Datei ist keine gültige Word-Vorlage (.docx).');
  }
  final body = _desc(doc, 'w:body').first;
  normalizeFields(body);

  var extraParts = <String>[];
  if (briefkopf != null) extraParts = _briefkopfUebernehmen(pkg, briefkopf);

  // #-Platzhalter (eigener Absatz)
  if (raute != null) {
    final reAbs = RegExp(r'^(#[A-Za-zÄÖÜäöüß][\wÄÖÜäöüß]*\s*)+$');
    for (final p in _desc(body, 'w:p').toList()) {
      final txt = paragraphText(p).trim();
      if (!reAbs.hasMatch(txt)) continue;
      final namen = RegExp(r'#([A-Za-zÄÖÜäöüß][\wÄÖÜäöüß]*)')
          .allMatches(txt)
          .map((m) => m.group(1)!)
          .toList();
      final neu = <XmlElement>[];
      var bekannt = false;
      for (final n in namen) {
        final v = raute(n);
        if (v == null) {
          neu.addAll(textToParagraphs('#$n', p));
          continue;
        }
        bekannt = true;
        if (v.isNotEmpty) neu.addAll(textToParagraphs(v, p));
      }
      if (!bekannt) continue;
      if (_ancestor(p, 'w:tc') != null && neu.isEmpty) neu.add(_el('w:p'));
      for (final n in neu) {
        _insertBefore(n, p);
      }
      _remove(p);
    }
  }

  void verarbeite(XmlNode root, WordResolver res) {
    expandTables(root, tabellen, res);
    if (personen != null) expandBeteiligte(root, personen);
    for (final p in _desc(root, 'w:p').toList()) {
      if (p.parent != null) replaceInParagraph(p, res);
    }
  }

  // leere Absätze / reine Seitenumbrüche am Dokumentende entfernen
  final sectEnde = _kids(body, 'w:sectPr').firstOrNull;
  while (true) {
    final kinder = body.children.whereType<XmlElement>().toList();
    final idx = sectEnde == null ? kinder.length - 1 : kinder.indexOf(sectEnde) - 1;
    if (idx < 1) break;
    final n = kinder[idx];
    final davor = kinder[idx - 1];
    if (n.name.qualified == 'w:p' &&
        davor.name.qualified != 'w:tbl' &&
        paragraphText(n).trim().isEmpty &&
        !_hasGraphic(n) &&
        _desc(n, 'w:sectPr').isEmpty) {
      _remove(n);
    } else {
      break;
    }
  }

  var serienbrief = false;
  final empfFelder = RegExp(r'«(An|Name|Anrede|Strasse|Plz|Stadt|Zusatz|Vorname)»');
  if (empfaenger != null &&
      empfaenger.isNotEmpty &&
      empfFelder.hasMatch(_desc(body, 'w:p').map(paragraphText).join('\n'))) {
    serienbrief = true;
    final sect = _kids(body, 'w:sectPr').firstOrNull;
    final vorlageNodes = body.children.where((n) => n != sect).toList();
    for (final n in vorlageNodes) {
      _remove(n);
    }
    if (sect != null) _seitenzaehlungNeu(sect);
    for (var i = 0; i < empfaenger.length; i++) {
      final tmp = _el('w:body');
      for (final n in vorlageNodes) {
        final c = n.copy();
        if (i > 0) _ohneLesezeichen(c);
        tmp.children.add(c);
      }
      final empf = empfaenger[i];
      verarbeite(tmp, (tok) => empf(tok) ?? resolver(tok));
      final teile = tmp.children.toList();
      for (final n in teile) {
        n.remove();
        if (sect != null) {
          _insertBefore(n, sect);
        } else {
          body.children.add(n);
        }
      }
      if (sect != null && i < empfaenger.length - 1) {
        final p = _el('w:p', kinder: [_el('w:pPr', kinder: [sect.copy()])]);
        _insertBefore(p, sect);
      }
    }
  } else {
    verarbeite(body, resolver);
  }
  expandSpecials(body);

  // Kopf-/Fußzeilen, Fuß-/Endnoten
  final weitere = pkg.dateien.keys
      .where((n) => RegExp(r'^word/(bk_)?(header|footer|footnotes|endnotes)[^/]*\.xml$').hasMatch(n) ||
          RegExp(r'^word/bk_[^/]*\.xml$').hasMatch(n))
      .toSet()
    ..addAll(extraParts);
  for (final name in weitere) {
    final d = pkg.xml(name);
    if (d == null) continue;
    normalizeFields(d.rootElement);
    for (final p in _desc(d.rootElement, 'w:p').toList()) {
      replaceInParagraph(p, resolver, leereZeilenEntfernen: false);
    }
    expandSpecials(d.rootElement);
  }

  if (serienbrief) {
    for (final name in pkg.dateien.keys.where((n) => RegExp(r'^word/[^/]+\.xml$').hasMatch(n)).toList()) {
      final d = pkg.xml(name);
      if (d == null) continue;
      for (final it in _desc(d.rootElement, 'w:instrText')) {
        if (it.innerText.contains('NUMPAGES')) {
          it.innerText = it.innerText.replaceAll('NUMPAGES', 'SECTIONPAGES');
        }
      }
      for (final fs in _desc(d.rootElement, 'w:fldSimple')) {
        final ins = fs.getAttribute('w:instr') ?? '';
        if (ins.contains('NUMPAGES')) {
          fs.setAttribute('w:instr', ins.replaceAll('NUMPAGES', 'SECTIONPAGES'));
        }
      }
    }
  }

  if (felderAktualisieren) {
    final st = pkg.xml('word/settings.xml');
    if (st != null && _desc(st, 'w:updateFields').isEmpty) {
      const nach = ['w:hdrShapeDefaults', 'w:footnotePr', 'w:endnotePr', 'w:compat', 'w:docVars',
        'w:rsids', 'm:mathPr', 'w:attachedSchema', 'w:themeFontLang', 'w:clrSchemeMapping',
        'w:doNotIncludeSubdocsInStats', 'w:doNotAutoCompressPictures', 'w:forceUpgrade',
        'w:captions', 'w:readModeInkLockDown', 'w:smartTagType', 'sl:schemaLibrary',
        'w:shapeDefaults', 'w:doNotEmbedSmartTags', 'w:decimalSymbol', 'w:listSeparator'];
      final ref = st.rootElement.childElements
          .where((e) => nach.contains(e.name.qualified) || e.name.qualified.startsWith('w1'))
          .firstOrNull;
      final neu = _el('w:updateFields', attrs: {'w:val': 'true'});
      if (ref != null) {
        _insertBefore(neu, ref);
      } else {
        st.rootElement.children.add(neu);
      }
    }
  }
  return pkg.schreiben();
}

/// Prüft, ob die Vorlage Serienbrief-Felder («Name», «Strasse» …) enthält.
bool vorlageHatSerienbriefFelder(Uint8List vorlage) {
  try {
    final pkg = _Paket(vorlage);
    final doc = pkg.xml('word/document.xml');
    if (doc == null) return false;
    normalizeFields(doc.rootElement);
    return RegExp(r'«(An|Name|Anrede|Strasse|Plz|Stadt|Zusatz)»')
        .hasMatch(_desc(doc, 'w:p').map(paragraphText).join('\n'));
  } catch (_) {
    return false;
  }
}
