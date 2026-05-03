import 'dart:convert';
import 'dart:typed_data';

import '../../../data/database/app_database.dart';

/// GAEB-Phase. D83 = Angebotsaufforderung (Ausschreibung an Handwerker).
/// D81 = LV-Übergabe. D84 = Angebot des Bieters.
enum GaebPhase { d81, d83, d84 }

/// Erzeugt eine GAEB DA XML 3.2-Datei (vereinfacht) aus einem LV.
/// Nicht der vollständige Standard, aber genug, um von ORCA AVA, California
/// und nextbau eingelesen zu werden.
///
/// Spezifikation: https://www.gaeb.de
Uint8List buildGaebX83({
  required LvKopfData kopf,
  required List<LvPositionenData> positionen,
  GaebPhase phase = GaebPhase.d83,
  String waehrung = 'EUR',
  String? auftragsnehmer,
  String? auftraggeber,
}) {
  final phaseCode = switch (phase) {
    GaebPhase.d81 => '81',
    GaebPhase.d83 => '83',
    GaebPhase.d84 => '84',
  };
  final tsString =
      DateTime.now().toIso8601String().replaceAll(RegExp(r'\.\d+'), '');

  final buf = StringBuffer();
  buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
  buf.writeln(
      '<GAEB xmlns="http://www.gaeb.de/GAEB_DA_XML/200407" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">');

  // GAEB-Info
  buf.writeln('  <GAEBInfo>');
  buf.writeln('    <Version>3.2</Version>');
  buf.writeln('    <VersDate>$tsString</VersDate>');
  buf.writeln(
      '    <Date>${DateTime.now().toIso8601String().substring(0, 10)}</Date>');
  buf.writeln(
      '    <Time>${DateTime.now().toIso8601String().substring(11, 19)}</Time>');
  buf.writeln('    <ProgSystem>Aktenwerk</ProgSystem>');
  buf.writeln('  </GAEBInfo>');

  // PrjInfo
  buf.writeln('  <PrjInfo>');
  buf.writeln('    <NamePrj>${_xml(kopf.bezeichnung)}</NamePrj>');
  if ((kopf.untertitel ?? '').isNotEmpty) {
    buf.writeln(
        '    <LblPrj>${_xml(kopf.untertitel!)}</LblPrj>');
  }
  if (auftraggeber != null) {
    buf.writeln('    <Cl>');
    buf.writeln('      <Name>${_xml(auftraggeber)}</Name>');
    buf.writeln('    </Cl>');
  }
  if (auftragsnehmer != null) {
    buf.writeln('    <Cntr>');
    buf.writeln('      <Name>${_xml(auftragsnehmer)}</Name>');
    buf.writeln('    </Cntr>');
  }
  buf.writeln('    <Cur>${_xml(waehrung)}</Cur>');
  buf.writeln('  </PrjInfo>');

  // Award (Phase-Container)
  buf.writeln('  <Award>');
  buf.writeln(
      '    <DP version="3.2" Cat="${phaseCode}" status="00">');
  buf.writeln('      <CatalogAwardCondition/>');
  buf.writeln('      <BoQ>');
  buf.writeln(
      '        <BoQInfo><Name>${_xml(kopf.bezeichnung)}</Name></BoQInfo>');
  buf.writeln('        <BoQBody>');

  // Positionen — flache Hierarchie für simple Implementierung.
  // GAEB unterstützt verschachtelte BoQCtgy, hier vereinfacht ohne
  // tiefe Struktur.
  for (final p in positionen) {
    if (p.art == 'titel') {
      buf.writeln('          <BoQCtgy RNoPart="${_xml(p.oz ?? "")}">');
      buf.writeln(
          '            <LblTx><p><span>${_xml(p.kurztext)}</span></p></LblTx>');
      buf.writeln('          </BoQCtgy>');
      continue;
    }
    final isMengenpos = p.art == 'normal' ||
        p.art == 'bedarf' ||
        p.art == 'eventual' ||
        p.art == 'stundenlohn';
    final itemType = switch (p.art) {
      'bedarf' => 'BeP',
      'eventual' => 'AltP',
      'stundenlohn' => 'StdP',
      _ => 'BoQItem',
    };

    buf.writeln(
        '          <Item RNoPart="${_xml(p.oz ?? "")}" ID="${p.id}">');
    buf.writeln('            <Description>');
    buf.writeln(
        '              <CompleteText><OutlineText><OutlTxt>'
        '<TextOutlTxt><p><span>${_xml(p.kurztext)}</span></p></TextOutlTxt>'
        '</OutlTxt>'
        '${(p.langtext ?? "").isEmpty ? "" : "<TextComplTxt><p><span>${_xml(p.langtext!)}</span></p></TextComplTxt>"}'
        '</OutlineText></CompleteText>');
    buf.writeln('            </Description>');
    if (isMengenpos) {
      if ((p.einheit ?? '').isNotEmpty) {
        buf.writeln('            <QU>${_xml(p.einheit!)}</QU>');
      }
      buf.writeln('            <Qty>${(p.menge ?? 0).toStringAsFixed(3)}</Qty>');
      // Bei der Ausschreibung (D83) keine Preise mitschicken.
      if (phase == GaebPhase.d81 || phase == GaebPhase.d84) {
        buf.writeln(
            '            <UP>${(p.einzelpreis ?? 0).toStringAsFixed(2)}</UP>');
        buf.writeln(
            '            <IT>${((p.menge ?? 0) * (p.einzelpreis ?? 0)).toStringAsFixed(2)}</IT>');
      }
    }
    buf.writeln('            <ItemType>$itemType</ItemType>');
    buf.writeln('          </Item>');
  }

  buf.writeln('        </BoQBody>');
  buf.writeln('      </BoQ>');
  buf.writeln('    </DP>');
  buf.writeln('  </Award>');
  buf.writeln('</GAEB>');

  return Uint8List.fromList(utf8.encode(buf.toString()));
}

String _xml(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');
