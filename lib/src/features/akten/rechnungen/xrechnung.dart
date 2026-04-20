import 'dart:convert';
import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

import '../../../data/database/app_database.dart';
import '../../../shared/positionen/position_model.dart';

/// Profil-Kennung für UN/CEFACT Cross Industry Invoice (CII).
/// - `xrechnung` liefert die **XRechnung 3.0** (national DE, Pflicht an Behörden)
/// - `zugferd_basic` liefert **ZUGFeRD 2.3 / Factur-X BASIC** (EU-weit)
enum ERechnungProfil { xrechnung, zugferdBasic }

extension ERechnungProfilX on ERechnungProfil {
  String get guideline => switch (this) {
        ERechnungProfil.xrechnung =>
          'urn:cen.eu:en16931:2017#compliant#urn:xoev-de:kosit:standard:xrechnung_3.0',
        ERechnungProfil.zugferdBasic =>
          'urn:cen.eu:en16931:2017#compliant#urn:factur-x.eu:1p0:basic',
      };
  String get dateiname => switch (this) {
        ERechnungProfil.xrechnung => 'xrechnung',
        ERechnungProfil.zugferdBasic => 'zugferd_factur-x',
      };
}

/// Erzeugt das UN/CEFACT Cross Industry Invoice XML.
///
/// Sehr kompakte, EN16931-konforme Version — deckt den Hauptteil der
/// Pflichtfelder ab (BT-1 bis BT-144). Für echte Behörden-Tests ggf. durch
/// den XRechnung-Validator jagen.
String buildCiiXml({
  required ERechnungProfil profil,
  required RechnungenData rechnung,
  required List<Position> positionen,
  required KundenData? empfaenger,
  required BenutzerData absender,
  String? leitwegId,
  String? bankName,
  String? bankIban,
  String? bankBic,
}) {
  final buf = StringBuffer();
  final datum = rechnung.rechnungsdatum ?? DateTime.now();
  final faellig = rechnung.faelligAm ??
      datum.add(Duration(days: rechnung.zahlungszielTage));
  final netto = rechnung.netto;
  final ust = rechnung.ustBetrag;
  final brutto = rechnung.brutto;
  final ustSatz = rechnung.ustSatz;
  final ustKategorie = _ustKategorieFor(
      ustSatz, rechnung.kleinunternehmerHinweis);
  final rnr = rechnung.rechnungsnummer ?? '';

  String esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  String d2(double v) => v.toStringAsFixed(2);
  String dt(DateTime v) =>
      '${v.year.toString().padLeft(4, '0')}'
      '${v.month.toString().padLeft(2, '0')}'
      '${v.day.toString().padLeft(2, '0')}';

  buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
  buf.writeln(
      '<rsm:CrossIndustryInvoice xmlns:rsm="urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100" '
      'xmlns:ram="urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100" '
      'xmlns:udt="urn:un:unece:uncefact:data:standard:UnqualifiedDataType:100">');

  // 1. ExchangedDocumentContext
  buf.writeln('<rsm:ExchangedDocumentContext>');
  buf.writeln('  <ram:GuidelineSpecifiedDocumentContextParameter>');
  buf.writeln('    <ram:ID>${esc(profil.guideline)}</ram:ID>');
  buf.writeln('  </ram:GuidelineSpecifiedDocumentContextParameter>');
  buf.writeln('</rsm:ExchangedDocumentContext>');

  // 2. ExchangedDocument
  buf.writeln('<rsm:ExchangedDocument>');
  buf.writeln('  <ram:ID>${esc(rnr)}</ram:ID>');
  buf.writeln('  <ram:TypeCode>380</ram:TypeCode>'); // 380 = Handelsrechnung
  buf.writeln('  <ram:IssueDateTime>');
  buf.writeln(
      '    <udt:DateTimeString format="102">${dt(datum)}</udt:DateTimeString>');
  buf.writeln('  </ram:IssueDateTime>');
  if ((rechnung.notiz ?? '').isNotEmpty) {
    buf.writeln('  <ram:IncludedNote>');
    buf.writeln('    <ram:Content>${esc(rechnung.notiz!)}</ram:Content>');
    buf.writeln('  </ram:IncludedNote>');
  }
  buf.writeln('</rsm:ExchangedDocument>');

  // 3. Transaction
  buf.writeln('<rsm:SupplyChainTradeTransaction>');

  // 3.1 Positionen
  for (var i = 0; i < positionen.length; i++) {
    final p = positionen[i];
    buf.writeln('  <ram:IncludedSupplyChainTradeLineItem>');
    buf.writeln('    <ram:AssociatedDocumentLineDocument>');
    buf.writeln('      <ram:LineID>${i + 1}</ram:LineID>');
    buf.writeln('    </ram:AssociatedDocumentLineDocument>');
    buf.writeln('    <ram:SpecifiedTradeProduct>');
    buf.writeln(
        '      <ram:Name>${esc(p.bezeichnung.isEmpty ? "(ohne)" : p.bezeichnung)}</ram:Name>');
    buf.writeln('    </ram:SpecifiedTradeProduct>');
    buf.writeln('    <ram:SpecifiedLineTradeAgreement>');
    buf.writeln('      <ram:NetPriceProductTradePrice>');
    buf.writeln(
        '        <ram:ChargeAmount>${d2(p.einzelpreis)}</ram:ChargeAmount>');
    buf.writeln('      </ram:NetPriceProductTradePrice>');
    buf.writeln('    </ram:SpecifiedLineTradeAgreement>');
    buf.writeln('    <ram:SpecifiedLineTradeDelivery>');
    buf.writeln(
        '      <ram:BilledQuantity unitCode="${_unitFor(p.einheit)}">${p.menge.toStringAsFixed(3)}</ram:BilledQuantity>');
    buf.writeln('    </ram:SpecifiedLineTradeDelivery>');
    buf.writeln('    <ram:SpecifiedLineTradeSettlement>');
    buf.writeln('      <ram:ApplicableTradeTax>');
    buf.writeln('        <ram:TypeCode>VAT</ram:TypeCode>');
    buf.writeln(
        '        <ram:CategoryCode>$ustKategorie</ram:CategoryCode>');
    buf.writeln(
        '        <ram:RateApplicablePercent>${d2(ustSatz)}</ram:RateApplicablePercent>');
    buf.writeln('      </ram:ApplicableTradeTax>');
    buf.writeln(
        '      <ram:SpecifiedTradeSettlementLineMonetarySummation>');
    buf.writeln(
        '        <ram:LineTotalAmount>${d2(p.nettoBetrag)}</ram:LineTotalAmount>');
    buf.writeln(
        '      </ram:SpecifiedTradeSettlementLineMonetarySummation>');
    buf.writeln('    </ram:SpecifiedLineTradeSettlement>');
    buf.writeln('  </ram:IncludedSupplyChainTradeLineItem>');
  }

  // 3.2 Parteien
  buf.writeln('  <ram:ApplicableHeaderTradeAgreement>');
  if (leitwegId != null && leitwegId.trim().isNotEmpty) {
    buf.writeln(
        '    <ram:BuyerReference>${esc(leitwegId.trim())}</ram:BuyerReference>');
  }
  // Seller
  buf.writeln('    <ram:SellerTradeParty>');
  buf.writeln('      <ram:Name>${esc(absender.firma ?? "")}</ram:Name>');
  buf.writeln('      <ram:PostalTradeAddress>');
  buf.writeln(
      '        <ram:PostcodeCode>${esc(absender.plz ?? "")}</ram:PostcodeCode>');
  buf.writeln(
      '        <ram:LineOne>${esc(absender.strasse ?? "")}</ram:LineOne>');
  buf.writeln(
      '        <ram:CityName>${esc(absender.ort ?? "")}</ram:CityName>');
  buf.writeln(
      '        <ram:CountryID>DE</ram:CountryID>');
  buf.writeln('      </ram:PostalTradeAddress>');
  if ((absender.email ?? '').isNotEmpty) {
    buf.writeln('      <ram:URIUniversalCommunication>');
    buf.writeln(
        '        <ram:URIID schemeID="EM">${esc(absender.email!)}</ram:URIID>');
    buf.writeln('      </ram:URIUniversalCommunication>');
  }
  if ((absender.ustId ?? '').isNotEmpty) {
    buf.writeln('      <ram:SpecifiedTaxRegistration>');
    buf.writeln(
        '        <ram:ID schemeID="VA">${esc(absender.ustId!)}</ram:ID>');
    buf.writeln('      </ram:SpecifiedTaxRegistration>');
  }
  buf.writeln('    </ram:SellerTradeParty>');
  // Buyer
  buf.writeln('    <ram:BuyerTradeParty>');
  buf.writeln(
      '      <ram:Name>${esc(_empfaengerName(empfaenger))}</ram:Name>');
  buf.writeln('      <ram:PostalTradeAddress>');
  buf.writeln(
      '        <ram:PostcodeCode>${esc(empfaenger?.plz ?? "")}</ram:PostcodeCode>');
  buf.writeln(
      '        <ram:LineOne>${esc(empfaenger?.strasse ?? "")}</ram:LineOne>');
  buf.writeln(
      '        <ram:CityName>${esc(empfaenger?.ort ?? "")}</ram:CityName>');
  buf.writeln(
      '        <ram:CountryID>DE</ram:CountryID>');
  buf.writeln('      </ram:PostalTradeAddress>');
  if ((empfaenger?.ustId ?? '').isNotEmpty) {
    buf.writeln('      <ram:SpecifiedTaxRegistration>');
    buf.writeln(
        '        <ram:ID schemeID="VA">${esc(empfaenger!.ustId!)}</ram:ID>');
    buf.writeln('      </ram:SpecifiedTaxRegistration>');
  }
  buf.writeln('    </ram:BuyerTradeParty>');
  buf.writeln('  </ram:ApplicableHeaderTradeAgreement>');

  buf.writeln('  <ram:ApplicableHeaderTradeDelivery/>');

  // 3.3 Settlement
  buf.writeln('  <ram:ApplicableHeaderTradeSettlement>');
  buf.writeln(
      '    <ram:InvoiceCurrencyCode>EUR</ram:InvoiceCurrencyCode>');
  if ((bankIban ?? '').isNotEmpty) {
    buf.writeln('    <ram:SpecifiedTradeSettlementPaymentMeans>');
    buf.writeln('      <ram:TypeCode>58</ram:TypeCode>'); // SEPA credit transfer
    buf.writeln(
        '      <ram:PayeePartyCreditorFinancialAccount>');
    buf.writeln(
        '        <ram:IBANID>${esc(bankIban!.replaceAll(" ", ""))}</ram:IBANID>');
    buf.writeln('      </ram:PayeePartyCreditorFinancialAccount>');
    if ((bankBic ?? '').isNotEmpty) {
      buf.writeln(
          '      <ram:PayeeSpecifiedCreditorFinancialInstitution>');
      buf.writeln('        <ram:BICID>${esc(bankBic!)}</ram:BICID>');
      buf.writeln(
          '      </ram:PayeeSpecifiedCreditorFinancialInstitution>');
    }
    buf.writeln('    </ram:SpecifiedTradeSettlementPaymentMeans>');
  }
  buf.writeln('    <ram:ApplicableTradeTax>');
  buf.writeln(
      '      <ram:CalculatedAmount>${d2(ust)}</ram:CalculatedAmount>');
  buf.writeln('      <ram:TypeCode>VAT</ram:TypeCode>');
  buf.writeln(
      '      <ram:BasisAmount>${d2(netto)}</ram:BasisAmount>');
  buf.writeln(
      '      <ram:CategoryCode>$ustKategorie</ram:CategoryCode>');
  buf.writeln(
      '      <ram:RateApplicablePercent>${d2(ustSatz)}</ram:RateApplicablePercent>');
  buf.writeln('    </ram:ApplicableTradeTax>');
  buf.writeln('    <ram:SpecifiedTradePaymentTerms>');
  buf.writeln(
      '      <ram:Description>Zahlung bis ${dt(faellig)} ohne Abzug.</ram:Description>');
  buf.writeln('      <ram:DueDateDateTime>');
  buf.writeln(
      '        <udt:DateTimeString format="102">${dt(faellig)}</udt:DateTimeString>');
  buf.writeln('      </ram:DueDateDateTime>');
  buf.writeln('    </ram:SpecifiedTradePaymentTerms>');
  buf.writeln(
      '    <ram:SpecifiedTradeSettlementHeaderMonetarySummation>');
  buf.writeln(
      '      <ram:LineTotalAmount>${d2(netto)}</ram:LineTotalAmount>');
  buf.writeln(
      '      <ram:TaxBasisTotalAmount>${d2(netto)}</ram:TaxBasisTotalAmount>');
  buf.writeln(
      '      <ram:TaxTotalAmount currencyID="EUR">${d2(ust)}</ram:TaxTotalAmount>');
  buf.writeln(
      '      <ram:GrandTotalAmount>${d2(brutto)}</ram:GrandTotalAmount>');
  buf.writeln(
      '      <ram:DuePayableAmount>${d2(brutto - rechnung.bezahlt)}</ram:DuePayableAmount>');
  buf.writeln(
      '    </ram:SpecifiedTradeSettlementHeaderMonetarySummation>');
  buf.writeln('  </ram:ApplicableHeaderTradeSettlement>');

  buf.writeln('</rsm:SupplyChainTradeTransaction>');
  buf.writeln('</rsm:CrossIndustryInvoice>');
  return buf.toString();
}

/// UStG §4: EN-16931 UNTDID 5305 Kategorie-Codes.
String _ustKategorieFor(double satz, bool kleinunternehmer) {
  if (kleinunternehmer) return 'E'; // Exempt / §19 UStG
  if (satz == 0) return 'Z'; // Zero rated
  return 'S'; // Standard rate
}

/// Einheitskürzel nach UNECE Rec 20 (Auszug).
String _unitFor(String? einheit) {
  final e = (einheit ?? '').toLowerCase();
  return switch (e) {
    'h' || 'std' || 'stunde' || 'stunden' => 'HUR',
    'stk' || 'stück' || 'st' => 'H87',
    'km' => 'KMT',
    'm' => 'MTR',
    'm²' || 'm2' => 'MTK',
    'm³' || 'm3' => 'MTQ',
    'kg' => 'KGM',
    't' => 'TNE',
    'l' => 'LTR',
    'pauschal' || 'psch' => 'LS',
    _ => 'C62', // one (general)
  };
}

String _empfaengerName(KundenData? k) {
  if (k == null) return 'Empfänger';
  if ((k.firma ?? '').isNotEmpty) return k.firma!;
  return '${k.vorname ?? ''} ${k.nachname ?? ''}'.trim();
}

/// Teilt das XML über share_plus als Datei.
Future<void> shareCiiXml(String xml, {required String nummer,
    ERechnungProfil profil = ERechnungProfil.xrechnung}) async {
  final bytes = Uint8List.fromList(utf8.encode(xml));
  final filename = '${profil.dateiname}_$nummer.xml';
  await Share.shareXFiles(
    [
      XFile.fromData(
        bytes,
        name: filename,
        mimeType: 'application/xml',
      ),
    ],
    subject: 'E-Rechnung $nummer',
    text: 'E-Rechnung (${profil.name}) – $nummer',
  );
}
