# Claude Code — Integration Prompt

> Kopiere den folgenden Block komplett in Claude Code (VS Code). Lege vorher den Ordner `handoff/` in dein Projekt (oder den Pfad anpassen).

---

## Prompt

````
Du bekommst ein Design-System-Paket unter `./handoff/`. Lies zuerst:
1. `handoff/README.md` (komplette Guideline)
2. `handoff/DIALOGS.md` (Modal-/Popup-Spezifikation)
3. `handoff/tokens.css` (Design-Tokens)
4. `handoff/tokens.ts` (TS-Tokens)
5. Die SVGs in `handoff/logo/`
6. `handoff/components/Modal.tsx` (Referenz-Implementierung)

Dann führe die folgenden Aufgaben in dieser Reihenfolge aus. Stoppe nach jeder Phase und zeige mir das Diff, bevor du weitermachst.

────────────────────────────────────────────────
PHASE 1 — Tokens & Fonts einbinden
────────────────────────────────────────────────
- Kopiere `handoff/tokens.css` nach `src/styles/tokens.css` (oder dem äquivalenten Ort).
- Importiere die Datei als erstes im globalen Stylesheet / in `main.tsx` / `layout.tsx`.
- Füge die Geist + Geist Mono Google-Font-Links in `index.html` / Root-Layout ein:

    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Geist:wght@400;500;600;700&family=Geist+Mono:wght@400;500&display=swap" rel="stylesheet">

- Falls Tailwind verwendet wird: erweitere `tailwind.config` mit den Farben aus `tokens.ts` unter einem `aw`-Namespace.

────────────────────────────────────────────────
PHASE 2 — Logo ersetzen
────────────────────────────────────────────────
- Kopiere alle SVGs aus `handoff/logo/` nach `src/assets/logo/`.
- Ersetze das alte Favicon durch `aktenwerk-mark.svg` (als SVG-Favicon + 32/16 PNG-Export).
- Suche im Codebase nach dem alten Logo (z. B. „logo", „Aktenwerk-icon", alter Pfad) und ersetze JEDE Stelle durch eine `<Logo>`-Komponente. Erstelle dafür:

    // src/components/Logo.tsx
    import mark from '@/assets/logo/aktenwerk-mark.svg';
    import lockup from '@/assets/logo/aktenwerk-lockup.svg';
    export function Logo({ size = 32, variant = 'mark' }: { size?: number; variant?: 'mark' | 'lockup' }) {
      const src = variant === 'lockup' ? lockup : mark;
      return <img src={src} alt="Aktenwerk" height={size} style={{ display: 'block' }} />;
    }

- Ersetze überall:
    * Sidebar-Header        → <Logo size={32} /> + daneben Wortmarke „Akten<span class='text-aw-orange'>werk</span>"
    * Login / Splash        → <Logo size={72} variant="lockup" />
    * Print-Templates       → Lockup SVG oben links
    * Email-Templates       → PNG-Export des Lockups @ 2×

────────────────────────────────────────────────
PHASE 3 — Seiten auf das neue System umbauen
────────────────────────────────────────────────
Führe für jede bestehende Seite durch — in dieser Priorität:
  1. Dashboard
  2. Aufträge-Liste
  3. Gutachten-Detail
  4. Normen-Katalog
  5. Rechnungen
  6. Kalender
  7. restliche Screens (Auftraggeber, Objekte, Einstellungen)

Pro Seite:

A) Struktur
   - App-Shell verwenden: Sidebar 232 px + Topbar 56 px + Main (padding 22px 28px).
   - Page-Header-Muster: eyebrow → h1 → subtitle → Actions rechts, darunter optional Tabs.

B) Komponenten austauschen
   - Alle Buttons: `.aw-btn-primary` (CTA) oder `.aw-btn-ghost` (Sekundär).
   - Alle Filter/Dropdowns oberhalb von Tabellen: `.aw-chip`.
   - Alle Status-Anzeigen: `.aw-badge` mit passendem Modifier (Mapping in tokens.ts → statusMap).
   - Alle Tabellen: `.aw-table` (siehe tokens.css).
   - IDs (AW-0046, RE-0231) in Orange 500 + class="aw-tabular".

C) Farb-Hygiene
   - Entferne jede Verwendung von Orange auf großen Flächen.
   - Entferne Gradients.
   - Setze Card-Backgrounds auf `--aw-white`, App-BG auf `--aw-paper`, Borders auf `--aw-line`.

D) Typografie-Hygiene
   - Alle Texte auf Geist umstellen (über tokens.css automatisch).
   - H1 = `.aw-h1`, Card-Titel = `.aw-h3`.
   - Zahlen/Geld/Daten überall `class="aw-tabular"`.

E) Icons
   - Alle Emoji entfernen.
   - Lucide-React installieren und verwenden, 16 px stroke 1.75.

────────────────────────────────────────────────
PHASE 3.5 — Modals / Popups vereinheitlichen
────────────────────────────────────────────────
- Kopiere `handoff/components/Modal.tsx` nach `src/components/Modal.tsx`.
- Ersetze ALLE bestehenden Modal-/Dialog-/Popup-Implementierungen durch `<Modal>`.
  Suche nach: "dialog", "modal", "popup", "overlay", "sheet", custom ReactPortal.
- Regeln pro Dialog (siehe handoff/DIALOGS.md):
    * Size: sm (420) / md (640) / lg (880) / xl (1120)
    * Header: optional eyebrow + Titel + statusDot + Close-X
    * Body: Form-Grid mit <FormGrid columns> und <Field label required span>
    * Footer: links destruktiv/tertiär (Ghost), rechts Abbrechen → Speichern (Primary)
    * Scroll-Lock, ESC, click-outside (außer L/XL mit Dirty-State), Autofocus
    * role="dialog" + aria-modal + aria-labelledby
- Insbesondere für „Anschreiben bearbeiten", „Auftrag anlegen", „Norm hinzufügen",
  „Rechnung erstellen", „Kontakt bearbeiten": Modal L (880 px).
- Bestätigungs-Prompts (Löschen, Discard, Versenden): Modal S (420 px) mit rotem
  Icon-Badge und destruktivem Primary.
- Quick-Inspector (Klick auf Zeile → Detail): Side-Sheet rechts 520 px.

────────────────────────────────────────────────
PHASE 4 — Emails & PDFs
────────────────────────────────────────────────
- Anschreiben-PDF-Template: Logo-Lockup oben links (120 px breit), Absender-Block rechts, Geist-Schriftart eingebettet.
- Rechnungs-PDF: gleiches Layout, Zahlenblock tabular-nums.
- Email-Signaturen: Lockup als PNG 200 px breit.

────────────────────────────────────────────────
PHASE 5 — QA-Checkliste
────────────────────────────────────────────────
Prüfe jede Seite gegen diese Liste:
[ ] Orange ausschließlich auf: Primary-Button, Badge-BG, Progress-Fill, Active-Nav-Bar, Logo-Accent, IDs
[ ] Kein Emoji mehr im UI
[ ] Alle Borders sind `--aw-line`, nicht harte Grautöne
[ ] Kein Font außer Geist / Geist Mono
[ ] Kein Gradient
[ ] Favicon zeigt neues Logo
[ ] Sidebar-Header zeigt neues Logo
[ ] PDFs zeigen neues Lockup

Zeige mir am Ende ein Before/After-Screenshot-Paar pro Seite, damit ich abnehmen kann.
````

---

## Tipps zur Verwendung in VS Code

1. Commit dein aktuelles Branch, dann lege einen neuen an (`redesign/aktenwerk-v1`).
2. Ziehe den `handoff/`-Ordner in dein Projekt-Root.
3. Öffne Claude Code in VS Code, paste den Prompt-Block oben.
4. Arbeite Phase für Phase — nach jeder Phase Diff reviewen + committen.
5. Beim Logo-Replace: Claude Code nutzt `grep`/`ripgrep` um alle Vorkommen zu finden. Prüfe, dass auch PDF-/Email-Templates erfasst sind.
