import 'package:flutter/material.dart';

import '../../../shared/widgets/module_scaffold.dart';

/// Datenschutzerklärung gem. Art. 13 / 14 DSGVO. Wird über `/datenschutz`
/// erreicht und ist im Footer des Login-Screens sowie aus den
/// Einstellungen heraus verlinkt.
///
/// Hinweis: Dies ist eine technisch korrekte Vorlage, basierend auf den
/// tatsächlich verwendeten Datenflüssen (Firebase, Vertex AI/Gemini,
/// Google APIs). Eine rechtliche Endprüfung durch einen Anwalt sollte
/// vor Live-Verkauf erfolgen.
class DatenschutzScreen extends StatelessWidget {
  const DatenschutzScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ModuleHeader(
          icon: Icons.privacy_tip_outlined,
          title: 'Datenschutzerklärung',
          subtitle:
              'Information gem. Art. 13 / 14 DSGVO — Stand: 02.05.2026',
        ),
        const Divider(height: 1),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 880),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: SelectionArea(
                  child: DefaultTextStyle(
                    style: Theme.of(context).textTheme.bodyMedium!,
                    child: const _DatenschutzInhalt(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DatenschutzInhalt extends StatelessWidget {
  const _DatenschutzInhalt();

  @override
  Widget build(BuildContext context) {
    final h1 = Theme.of(context).textTheme.headlineSmall;
    final h2 = Theme.of(context).textTheme.titleMedium;
    final dim = TextStyle(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontStyle: FontStyle.italic);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Datenschutzerklärung Aktenwerk', style: h1),
        const SizedBox(height: 4),
        Text(
            'Diese Erklärung informiert Sie über Art, Umfang und Zweck der '
            'Verarbeitung personenbezogener Daten innerhalb unserer SaaS-Anwendung '
            '„Aktenwerk – Sachverständigen-Suite" (im Folgenden „Aktenwerk").',
            style: dim),
        const SizedBox(height: 18),

        // 1. Verantwortlicher
        Text('1. Verantwortlicher', style: h2),
        const SizedBox(height: 6),
        const Text(
            'Verantwortlich für die Datenverarbeitung im Sinne der DSGVO ist:'),
        const SizedBox(height: 4),
        const Text(
            'Alexander Höpken\n'
            'Beratender Ingenieur und Sachverständiger\n'
            'Bauelemente-Experte\n'
            'Auf dem Stemmingholt 21\n'
            '46499 Hamminkeln\n'
            'E-Mail: buero@bauelemente-experte.de\n'
            'Telefon: +49 152 519 75042'),
        const SizedBox(height: 18),

        // 2. Verarbeitete Daten
        Text('2. Welche Daten wir verarbeiten', style: h2),
        const SizedBox(height: 6),
        const Text(
            'Aktenwerk verarbeitet folgende Kategorien personenbezogener Daten:'),
        const SizedBox(height: 6),
        const _Bullet(
            'Anmelde- und Kontodaten (Name, E-Mail-Adresse, Profilbild, Anmelde-Zeitstempel) '
            '– zur Authentifizierung über Google, Apple oder E-Mail/Passwort.'),
        const _Bullet(
            'Inhaltsdaten der von Ihnen erfassten Akten (Aktenzeichen, Beteiligte, '
            'Schriftverkehr, Gutachten, Rechnungen, Stunden, Auslagen, Fotos, '
            'Beweisbeschluss-Inhalte, gerichtliche Aktenzeichen).'),
        const _Bullet(
            'Stammdaten der von Ihnen erfassten Kontakte und Beteiligten '
            '(Name, Anschrift, Telefon, E-Mail, Anwalts-/Richter-Bezeichnung).'),
        const _Bullet(
            'Nutzungsdaten zur Stabilisierung der App (Fehler-Logs, Sync-Status). '
            'Keine Werbe-Tracker, keine Analytics-Cookies.'),
        const _Bullet(
            'Bei aktivierter Gmail-Integration: Mail-Inhalt, Empfänger und Anhänge '
            'der von Ihnen aus Aktenwerk versandten Schreiben (siehe Abschnitt 6).'),
        const _Bullet(
            'Bei aktivierter Google-Kalender-Integration: Termin-Titel, '
            'Beschreibung, Datum und Beteiligte (siehe Abschnitt 6).'),
        const SizedBox(height: 18),

        // 3. Zwecke und Rechtsgrundlagen
        Text('3. Zwecke und Rechtsgrundlagen der Verarbeitung', style: h2),
        const SizedBox(height: 6),
        const Text(
            'Die Verarbeitung erfolgt zu folgenden Zwecken auf Grundlage von '
            'Art. 6 Abs. 1 DSGVO:'),
        const SizedBox(height: 6),
        const _Bullet(
            'Bereitstellung der vertraglich vereinbarten Software-Funktionen '
            '(Akten-, Gutachten-, Rechnungs- und Dokumentenverwaltung) – '
            'Art. 6 Abs. 1 lit. b DSGVO (Vertragserfüllung).'),
        const _Bullet(
            'Authentifizierung und Multi-Tenant-Trennung – Art. 6 Abs. 1 lit. b '
            'und lit. f DSGVO (berechtigtes Interesse an Datensicherheit und '
            'Mandantentrennung).'),
        const _Bullet(
            'Versand von Anschreiben über Ihre verbundenen Mail-Konten (Gmail) – '
            'Art. 6 Abs. 1 lit. a DSGVO (Einwilligung beim ersten Verbinden).'),
        const _Bullet(
            'Erfüllung gesetzlicher Aufbewahrungspflichten gem. § 147 AO und § 257 HGB '
            '– Art. 6 Abs. 1 lit. c DSGVO (rechtliche Verpflichtung).'),
        const _Bullet(
            'KI-gestützte Funktionen (Korrekturen, Umformulierungen, Normen-Chat) – '
            'Art. 6 Abs. 1 lit. f DSGVO bzw. lit. a DSGVO (Einwilligung beim Aufruf).'),
        const SizedBox(height: 18),

        // 4. Speicherort
        Text('4. Speicherort und Auftragsverarbeiter', style: h2),
        const SizedBox(height: 6),
        const Text(
            'Aktenwerk speichert Inhalts- und Stammdaten in der Cloud-Infrastruktur '
            'von Google Firebase (Region europe-west3, Frankfurt am Main). Mit Google '
            'haben wir einen Auftragsverarbeitungsvertrag (Standardvertragsklauseln) '
            'gem. Art. 28 DSGVO geschlossen.'),
        const SizedBox(height: 6),
        const Text('Eingesetzte Auftragsverarbeiter:'),
        const SizedBox(height: 6),
        const _Bullet(
            'Google Cloud / Firebase (Authentication, Firestore, Cloud Storage, '
            'Cloud Functions, Hosting) — Google Ireland Limited, Dublin, '
            'EU-Standardvertragsklauseln.'),
        const _Bullet(
            'Google Cloud Vertex AI / Gemini-API (für die KI-Funktionen wie '
            'Rechtschreibkorrektur, Normen-Chat, Eingangsrechnungs-Erfassung) — '
            'Google Ireland Limited, Dublin. Die KI-Anfragen werden ohne dauerhafte '
            'Speicherung der Eingaben verarbeitet (siehe Google Vertex AI Data Policy).'),
        const _Bullet(
            'Bei aktivierter Gmail-/Calendar-Integration: Google LLC bzw. Google Ireland '
            'als Mail-/Kalender-Anbieter Ihres eigenen Kontos.'),
        const SizedBox(height: 18),

        // 5. Aufbewahrungsdauer
        Text('5. Aufbewahrungsdauer', style: h2),
        const SizedBox(height: 6),
        const Text(
            'Personenbezogene Daten werden gespeichert, solange Ihr Aktenwerk-'
            'Konto aktiv ist. Nach Kündigung werden Ihre Daten innerhalb von 30 Tagen '
            'gelöscht, sofern keine gesetzlichen Aufbewahrungspflichten (z. B. '
            'steuerrechtliche 10-Jahres-Frist gem. § 147 AO für Rechnungen und '
            'Buchungsbelege) entgegenstehen. Während der laufenden Frist werden '
            'die betroffenen Daten gesperrt und nur noch zu Erfüllungszwecken '
            'aufbewahrt.'),
        const SizedBox(height: 18),

        // 6. Google-Integrationen
        Text('6. Google-Integrationen (Gmail, Kalender)', style: h2),
        const SizedBox(height: 6),
        const Text(
            'Aktenwerk bietet optionale Integrationen in Ihr eigenes Google-Konto an. '
            'Diese werden ausschließlich nach Ihrer ausdrücklichen Einwilligung über '
            'den OAuth-Standard-Dialog von Google aktiviert. Sie können die Verbindung '
            'jederzeit in den Aktenwerk-Einstellungen oder unter '
            'myaccount.google.com/permissions widerrufen.'),
        const SizedBox(height: 8),
        const Text(
            'Gmail-Integration (Scope `gmail.send`):'),
        const SizedBox(height: 4),
        const _Bullet(
            'Aktenwerk versendet auf Ihren ausdrücklichen Klick hin Mails über Ihr '
            'Gmail-Konto. Die Mails erscheinen in Ihrem „Gesendet"-Ordner.'),
        const _Bullet(
            'Aktenwerk speichert dabei das von Google ausgegebene OAuth-Access-Token '
            'ausschließlich lokal in Ihrem Browser (LocalStorage). Es wird nicht an '
            'Aktenwerk-Server übertragen.'),
        const _Bullet(
            'Aktenwerk liest in Phase 1 keine Mails aus Ihrem Postfach. Wenn Sie '
            'künftig (Phase 2) den Auto-Import aktivieren, wird zusätzlich der Scope '
            '`gmail.readonly` angefragt — auch diese Anfrage erfolgt erst nach '
            'erneuter ausdrücklicher Einwilligung.'),
        const SizedBox(height: 8),
        const Text(
            'Google-Kalender-Integration (Scopes `calendar.events`, `calendar.readonly`):'),
        const SizedBox(height: 4),
        const _Bullet(
            'Aktenwerk legt von Ihnen ausgewählte Termine (Ortstermine, Erläuterungs-'
            'termine, Wiedervorlagen) in einen von Ihnen bestimmten Google-Kalender. '
            'Es werden ausschließlich Termine gelesen, die mit dem privateExtendedProperty '
            '`aktenwerk=1` markiert sind.'),
        const SizedBox(height: 18),

        // 7. KI-Funktionen
        Text('7. KI-Funktionen', style: h2),
        const SizedBox(height: 6),
        const Text(
            'Die KI-gestützten Funktionen (Rechtschreibkorrektur, Umformulierung, '
            'Normen-Chat, Eingangsrechnungs-Erfassung) verarbeiten Ihre Eingaben '
            'über die Google Vertex AI (Gemini-Modelle). Die übermittelten Texte '
            'werden gemäß Google-Vertex-AI-Datenschutzbestimmungen nicht zum '
            'Trainieren der Modelle verwendet und nicht dauerhaft gespeichert.'),
        const SizedBox(height: 6),
        const Text(
            'Sie sollten dennoch keine Mandantengeheimnisse oder besonders '
            'schützenswerte Daten ohne Pseudonymisierung in die KI-Eingabefelder '
            'übernehmen, wenn ein konkretes Erfordernis dagegenspricht. '
            'Aktenwerk filtert derartige Daten nicht aktiv.'),
        const SizedBox(height: 18),

        // 8. Ihre Rechte
        Text('8. Ihre Rechte als betroffene Person', style: h2),
        const SizedBox(height: 6),
        const Text('Sie haben jederzeit das Recht auf:'),
        const SizedBox(height: 6),
        const _Bullet('Auskunft über Ihre verarbeiteten Daten (Art. 15 DSGVO)'),
        const _Bullet('Berichtigung unrichtiger Daten (Art. 16 DSGVO)'),
        const _Bullet('Löschung („Recht auf Vergessenwerden", Art. 17 DSGVO) — '
            'soweit keine gesetzlichen Aufbewahrungspflichten entgegenstehen'),
        const _Bullet('Einschränkung der Verarbeitung (Art. 18 DSGVO)'),
        const _Bullet('Datenübertragbarkeit (Art. 20 DSGVO) — Sie können Ihre Daten '
            'jederzeit als JSON-Backup über Einstellungen → Backup & Wiederherstellung exportieren'),
        const _Bullet('Widerspruch gegen die Verarbeitung (Art. 21 DSGVO)'),
        const _Bullet('Widerruf erteilter Einwilligungen (Art. 7 Abs. 3 DSGVO)'),
        const SizedBox(height: 6),
        const Text(
            'Zur Ausübung dieser Rechte wenden Sie sich an die in Abschnitt 1 '
            'genannten Kontaktdaten. Sie haben darüber hinaus das Recht, sich '
            'bei einer Aufsichtsbehörde zu beschweren — zuständig ist die '
            'Landesbeauftragte für Datenschutz und Informationsfreiheit '
            'Nordrhein-Westfalen (LDI NRW).'),
        const SizedBox(height: 18),

        // 9. Lokale Speicherung
        Text('9. Lokale Speicherung im Browser', style: h2),
        const SizedBox(height: 6),
        const Text(
            'Aktenwerk arbeitet als Offline-fähige Web-App. Inhalte werden zur '
            'Performance-Optimierung in IndexedDB lokal in Ihrem Browser zwischen-'
            'gespeichert; Authentifizierungs- und Integrationstokens liegen in '
            'LocalStorage. Beim Abmelden und beim Wechsel des Mandanten werden diese '
            'Daten getrennt vorgehalten. Sie können den lokalen Speicher jederzeit '
            'über die Browser-Einstellungen löschen.'),
        const SizedBox(height: 18),

        // 10. Cookies
        Text('10. Cookies', style: h2),
        const SizedBox(height: 6),
        const Text(
            'Aktenwerk verwendet ausschließlich technisch notwendige Cookies bzw. '
            'LocalStorage-Einträge zur Sitzungsverwaltung. Es werden keine Tracking-, '
            'Analyse- oder Werbe-Cookies eingesetzt.'),
        const SizedBox(height: 18),

        // 11. Änderungen
        Text('11. Änderungen dieser Erklärung', style: h2),
        const SizedBox(height: 6),
        const Text(
            'Wir passen diese Datenschutzerklärung an, wenn sich die Datenverarbeitung '
            'ändert (z. B. neue Auftragsverarbeiter oder Funktionen). Nutzer werden '
            'beim ersten Login nach einer wesentlichen Änderung über die Anpassung '
            'informiert.'),
        const SizedBox(height: 30),
        Text(
            'Stand: 02.05.2026 — Diese Erklärung ist eine technische Beschreibung '
            'der tatsächlichen Datenflüsse und sollte vor öffentlichem Verkauf der '
            'App durch einen Anwalt rechtlich geprüft werden.',
            style: dim),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('•  '),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
