# Aktenwerk Design Guideline v1.0

> Handoff-Paket für Claude Code (VS Code) — Farben, Typografie, Komponenten, Logo-Austausch.
> **Ziel:** Alle bestehenden Seiten sauber auf das neue System umbauen und das neue Logo überall einsetzen.

---

## 1. Inhalt dieses Pakets

```
handoff/
├── README.md                          ← diese Datei
├── DIALOGS.md                         ← Modals, Side-Sheets, Toasts
├── CLAUDE_CODE_PROMPT.md              ← fertiger Prompt zum Kopieren in VS Code
├── tokens.css                         ← Design-Tokens als CSS Custom Properties
├── tokens.ts                          ← gleiche Tokens für TS/JS
├── logo/
│   ├── aktenwerk-mark.svg             ← Haupt-Symbol (dunkel, mit orangem Layer)
│   ├── aktenwerk-mark-light.svg       ← Variante auf hellem Hintergrund
│   ├── aktenwerk-mark-mono.svg        ← einfarbige Variante (dunkel)
│   └── aktenwerk-lockup.svg           ← Symbol + Wortmarke + Subline, horizontal
└── components/
    ├── Logo.tsx                       ← React-Komponente
    ├── Sidebar.tsx                    ← App-Sidebar (Referenz)
    ├── PageHeader.tsx                 ← Page-Header-Muster (Referenz)
    └── Modal.tsx                      ← Modal + FormGrid + Field + Input
```

---

## 2. Farben (Kernpalette)

| Rolle           | Token                | Hex / Wert                 | Verwendung                                         |
|-----------------|----------------------|----------------------------|----------------------------------------------------|
| Primary         | `--aw-orange`        | `#F25C1F`                  | Primary Button, Akzent, Progress, IDs, aktiver Nav |
| Primary Hover   | `--aw-orange-deep`   | `#D94810`                  | Button Hover                                        |
| Primary Soft    | `--aw-orange-soft`   | `rgba(242,92,31,0.10)`     | Active Nav BG, Badge BG                             |
| Ink (Text)      | `--aw-ink`           | `#0B1220`                  | Primärtext, dunkle Flächen (Assistenz-Karte)        |
| Paper           | `--aw-paper`         | `#FAFAF7`                  | App-Hintergrund, Tabellen-Header                    |
| White           | `--aw-white`         | `#FFFFFF`                  | Cards, Sidebar                                      |
| Mute            | `--aw-mute`          | `rgba(11,18,32,0.55)`      | Sekundärtext                                        |
| Line            | `--aw-line`          | `rgba(11,18,32,0.08)`      | Borders, Dividers                                   |

**Status-Farben:** green `#16794A` · amber `#B45309` · red `#B42318` · blue `#1E4ED8` (alle je mit `-soft` Variante bei 10 % Deckkraft).

**Regel:** Orange ist Akzent, nie Fläche. Nur Primary-Button, Badge-BG, Progress-Fill, 2.5px Accent-Bar, oranges Logo-Layer. Niemals als Hintergrund ganzer Panels.

---

## 3. Typografie

- **Sans:** `Geist` (Google Fonts). Fallback: `-apple-system, system-ui, sans-serif`.
- **Mono:** `Geist Mono` — für IDs wenn monospaced gewünscht (optional).

```
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Geist:wght@400;500;600;700&family=Geist+Mono:wght@400;500&display=swap" rel="stylesheet">
```

**Skala (px):**

| Klasse       | Größe | Weight | Tracking  | Verwendung                        |
|--------------|-------|--------|-----------|-----------------------------------|
| `aw-h1`      | 24    | 600    | -0.025em  | Seiten-Titel                      |
| `aw-h2`      | 20    | 600    | -0.025em  | Große Metrik-Zahlen               |
| `aw-h3`      | 14    | 600    | -0.01em   | Card-Titel                        |
| body         | 12.5  | 400    | —         | Standard                          |
| small / mute | 11.5  | 400    | —         | Sekundär, Sublabels               |
| `aw-eyebrow` | 11    | 500    | 0.05em up | Über Titeln, Card-Labels          |
| micro        | 10    | 600    | 0.12em up | Nav-Gruppen, Tabellen-Header      |

**Wichtig:** `font-variant-numeric: tabular-nums` auf allen IDs, Geldbeträgen, Datumsangaben, Prozenten (Klasse `.aw-tabular`).

---

## 4. Logo

### Symbol (64 × 64)
Zwei versetzte, abgerundete Rechtecke auf dunklem Container — hinteres als Outline, vorderes in Orange gefüllt. Metapher: Schichten / übereinanderliegende Register.

- `logo/aktenwerk-mark.svg` — Standard (dunkler Container)
- `logo/aktenwerk-mark-light.svg` — für dunkle Hintergründe nicht nötig; dies ist die Version für helle Flächen mit sichtbarem Rahmen
- `logo/aktenwerk-mark-mono.svg` — einfarbig (wenn Orange nicht möglich, z. B. Fax/Stempel)
- `logo/aktenwerk-lockup.svg` — Symbol + „Akten**werk**" + Subline SACHVERSTÄNDIGEN-SUITE

### Wortmarke
„Akten**werk**" — Geist 600, Tracking `-0.025em`. „Akten" in Ink (`#0B1220`), „werk" in Orange (`#F25C1F`). Subline optional darunter: `SACHVERSTÄNDIGEN-SUITE` in 9px, letter-spacing `0.16em`, uppercase, mute.

### Schutzraum & Mindestgröße
- Mindestens halbe Höhe des Symbols als Abstand rundum.
- Mindestgröße Symbol: **20 × 20 px** (Favicon 16 × 16 ist OK).
- Im App-Sidebar: **32 × 32 px**, mit Wortmarke daneben.

### Was zu ersetzen ist (Old → New)
1. `favicon.ico` / `favicon.svg` → neues Symbol exportieren (32/16)
2. Sidebar-Header-Logo → `<Logo size={32} withWordmark />`
3. Login / Auth-Screens → `aktenwerk-lockup.svg` zentriert
4. Print-Header auf PDF-Anschreiben / Rechnungen → Lockup oben links, ca. 120 px breit
5. Email-Signatur-Template → Lockup als PNG @ 2× Export

---

## 5. Layout-System

### App-Shell
```
┌────────────────────────────────────────────────────────┐
│ Sidebar 232px │ Topbar 56px                            │
│               ├────────────────────────────────────────┤
│               │ Main: padding 22px 28px, gap 18–20px   │
└────────────────────────────────────────────────────────┘
```

- **Sidebar:** 232 px breit, `--aw-white` BG, `--aw-line` rechter Rand. Logo oben (18px padding), Workspace-Switcher, drei Nav-Gruppen (Übersicht / Arbeit / System), User-Zeile unten.
- **Nav-Item aktiv:** BG `--aw-orange-soft`, Text `--aw-ink` 500, Icon `--aw-orange`, plus 2.5 px × Höhe Orange-Bar links außen (bei `left: -10px`).
- **Topbar:** 56 px hoch, weiß, `--aw-line` unten. Links: globale Suche (`⌘K`). Rechts: „KI-Frage stellen", „PDF-Import", Bell mit Dot, Primary „Neuer Auftrag".

### Page-Header
```
eyebrow (uppercase 11px mute)
H1 (24px 600 -0.025em)
subtitle (13px mute)
[ghost btns] [primary btn]
—
tabs (optional) — active tab hat Orange underline (2px)
```

### Card
- BG `--aw-white`, Border `1px --aw-line`, `border-radius: 10px`.
- Interne Padding: 14–18 px.
- Card-Header: `aw-h3` + optional Subline + Actions rechts.

### Grid
- Dashboard-Body: `grid-template-columns: 1.6fr 1fr` (Haupt/Seitenspalte).
- KPI-Reihen: `repeat(4, 1fr)` mit 10–12 px Gap.
- Bei Screens > 1440 px: Max-Width 1400 px, zentriert.

---

## 6. Komponenten-Katalog

### Buttons
- **Primary** (`.aw-btn-primary`): Orange BG, weißer Text, 8×14 px, Radius 8.
- **Ghost** (`.aw-btn-ghost`): transparenter BG, `--aw-line` Border, Ink Text, 8×12 px.
- **Segmented Toggle:** Gruppe in weißer Box mit `--aw-line` Border; aktives Segment: Ink BG, weißer Text.

### Filter-Chips
Pill, 6×10 px, weißer BG, `--aw-line` Border, 16 px Radius, Chevron-down Icon 11 px nach Label.

### Status-Badges
Pill mit 5 px Dot vorne. Siehe `.aw-badge--*` Klassen.
| Status           | Klasse                    |
|------------------|---------------------------|
| In Bearbeitung   | `aw-badge--in-progress`   |
| Zu prüfen        | `aw-badge--todo`          |
| Abgeschlossen    | `aw-badge--done`          |
| Überfällig       | `aw-badge--overdue`       |
| Entwurf          | `aw-badge--draft`         |
| Ortstermin       | `aw-badge--info`          |

### Tabellen
- Header: Paper-BG, 10.5 px uppercase 600 mute, `--aw-line` unten.
- Zellen: 11×14 px Padding, 12.5 px Body, `--aw-line` Zeilen-Divider.
- IDs (AW-0046, RE-0231): Orange, weight 500, `tabular-nums`.
- Geld & Fristen: rechts ausgerichtet optional, immer `tabular-nums`.
- Überfällig-Frist: Text in `--aw-red`, weight 500.

### Progress-Balken
5 px Höhe, `--aw-paper` Track, Radius 3, Fill `--aw-orange` (bei 100 % → `--aw-green`).

### Metrik-Karte
`aw-card`, 14×16 px Padding, gap 10. Struktur:
- eyebrow Label + Delta-Chip rechts
- 28 px Zahl + Einheit (13 px mute)
- optional Sparkline SVG (28 px Höhe) mit Orange Line + 10 % Fill

### Assistenz-Karte (KI)
Dunkle Variante: `--aw-ink` BG, weißer Text. Eyebrow `ASSISTENZ` in rgba(255,255,255,0.7), Body in rgba(255,255,255,0.9). Sparkle-Icon in Orange.

### Icons
16 × 16 px stroke-basiert, 1.75 px stroke, round caps. Keine Emoji. Set ist in `dashboard.jsx` → `Icon`-Komponente zu finden. Empfohlen: **Lucide** als Library (API-kompatibel).

---

## 7. Seiten-Muster (Referenz)

1. **Dashboard** — Greeting → 4 KPI-Karten → Main (Auftrags-Tabelle + Wochen-Kalender) + Seite (Fristen + Aktivität + Assistenz).
2. **Aufträge-Liste** — Header mit Tabs + Actions → Filter-Chip-Leiste → Tabelle mit Fortschritt → Paginierung.
3. **Gutachten-Detail** — Breadcrumbs → Kopf mit Status-Badge + ID + Actions → 10-Tab-Nav → Hauptspalte (Stepper, Kennzahlen, Objekt+Karte, Bewertungsverfahren) + Seitenspalte (Auftraggeber, Termine, Normen, Assistenz).
4. **Normen-Katalog** — Header → 2-Spalten: Kategorien-Rail links (220px) + Tabelle rechts.
5. **Rechnungen** — 4 KPI-Kacheln → 12-Monats-Balkendiagramm → Tabelle mit Mahnstufen.
6. **Kalender** — Monatsansicht 7×5 mit Event-Pills → Seitenspalte mit Heute-Agenda & Filter-Legend.

---

## 8. Do & Don't

**Do**
- Orange als Akzent, nie als großflächiger Hintergrund.
- Alle IDs in Orange 500 + `tabular-nums`.
- Weißraum großzügig: 18–24 px zwischen Sektionen.
- Status immer über Badge + Dot kommunizieren, nicht nur Text.

**Don't**
- Keine Gradienten, keine Schatten größer als `--aw-shadow-md`.
- Keine Emoji in UI-Texten.
- Keine rounded-corner + left-border-accent Container.
- Keine gemischten Font-Familien (nur Geist / Geist Mono).
- Kein Orange auf Body-Text.
