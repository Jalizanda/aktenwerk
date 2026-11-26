import 'dart:convert';
import 'dart:typed_data';

import 'package:aktenwerk/src/core/jveg/jveg_tabelle.dart';
import 'package:aktenwerk/src/shared/docx/word_vorlagen_engine.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _docx(String body) {
  const ct = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
      '</Types>';
  const rels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
      '</Relationships>';
  final doc = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
      '<w:body>$body<w:sectPr/></w:body></w:document>';
  final a = Archive();
  for (final (n, s) in [('[Content_Types].xml', ct), ('_rels/.rels', rels), ('word/document.xml', doc)]) {
    final b = utf8.encode(s);
    a.addFile(ArchiveFile(n, b.length, b));
  }
  return Uint8List.fromList(ZipEncoder().encode(a));
}

String _text(Uint8List docx) {
  final a = ZipDecoder().decodeBytes(docx);
  final f = a.files.firstWhere((f) => f.name == 'word/document.xml');
  final xml = utf8.decode(f.content as List<int>);
  return RegExp(r'<w:t(?: [^>]*)?>([^<]*)</w:t>')
      .allMatches(xml)
      .map((m) => m.group(1))
      .join('|');
}

void main() {
  group('JVEG 2025', () {
    test('Sachgebiete Bau haben die Sätze aus Anlage 1 Teil 1', () {
      expect(jvegGesetzlicherSatz('SG 4.1'), 114);
      expect(jvegGesetzlicherSatz('SG 4.2'), 104);
      expect(jvegGesetzlicherSatz('SG 4.6'), 109);
      expect(jvegGesetzlicherSatz('M1'), 87);
      expect(jvegGesetzlicherSatz('M3'), 131);
    });

    test('§ 8 Abs. 2 S. 2: letzte begonnene Stunde auf Gesamtzeit', () {
      expect(jvegAbrechenbareStunden(0), 0);
      expect(jvegAbrechenbareStunden(60), 1);
      expect(jvegAbrechenbareStunden(61), 1.5);
      expect(jvegAbrechenbareStunden(90), 1.5);
      expect(jvegAbrechenbareStunden(91), 2);
      // 3 Tätigkeiten à 20 Min = 60 Min → 1 h (nicht 3 × 0,5 h)
      expect(jvegAbrechenbareStunden(20 + 20 + 20), 1);
    });
  });

  group('Word-Vorlagen-Engine', () {
    test(r'ersetzt $Platzhalter auch über mehrere Runs', () {
      final vorlage = _docx('<w:p><w:r><w:t>Az.: \$Ger</w:t></w:r>'
          '<w:r><w:t>ichtsAZ, Sache</w:t></w:r></w:p>');
      final out = erzeugeWordDokument(
        vorlage: vorlage,
        resolver: (t) => t == r'$GerichtsAZ' ? '5 O 123/25' : null,
      );
      expect(_text(out).replaceAll('|', ''), contains('Az.: 5 O 123/25, Sache'));
    });

    test('Serienbrief erzeugt einen Abschnitt je Empfänger', () {
      final vorlage = _docx('<w:p><w:r><w:t>«Name»</w:t></w:r></w:p>');
      final out = erzeugeWordDokument(
        vorlage: vorlage,
        resolver: (_) => null,
        empfaenger: [
          (t) => t == '«Name»' ? 'Müller' : null,
          (t) => t == '«Name»' ? 'Schmidt' : null,
        ],
      );
      final txt = _text(out);
      expect(txt, contains('Müller'));
      expect(txt, contains('Schmidt'));
    });
  });
}
