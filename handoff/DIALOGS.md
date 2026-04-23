# Dialogs & Modals — Aktenwerk Design Guideline

Ergänzung zu `README.md`. Regelt alle Popup-Fenster: Bearbeiten-Dialoge, Bestätigungen, Side-Sheets, Toasts.

---

## 1. Taxonomie

| Typ              | Breite     | Einsatz                                                  | Overlay |
|------------------|------------|----------------------------------------------------------|---------|
| **Modal S**      | 420 px     | Bestätigungen, einfache Formulare (1–3 Felder)           | ja      |
| **Modal M**      | 640 px     | Standard-Formulare (bis ~10 Felder)                      | ja      |
| **Modal L**      | 880 px     | Editor-Dialoge wie „Anschreiben bearbeiten" (Screenshot) | ja      |
| **Modal XL**     | 1120 px    | Mehrspaltige Editoren, Dokument-Preview + Form           | ja      |
| **Side-Sheet R** | 520 px     | Schnell-Inspector, Notizen, Filter-Detail                | ja      |
| **Drawer**       | 100 % unten, 420 px hoch | Mobile-nah, Quick-Actions                    | ja      |
| **Popover**      | auto, max 320 px | Kontext-Menü, Feld-Hilfe, Datum-Picker              | nein    |
| **Toast**        | 360 px     | Bestätigung nach Aktion                                   | nein    |

---

## 2. Modal-Anatomie (L — wie im Screenshot)

```
┌─────────────────────────────────────────────────────────┐
│ ⚠ icon  Anschreiben bearbeiten                     ✕  │  ← Header (52px)
├─────────────────────────────────────────────────────────┤
│ Datum*          Status*           Empfänger*            │
│ [08.04.2026 📅] [Versendet ▾]    [zu suchen… 🔍]      │  ← Form-Grid (3-col)
│                                                         │
│ Art Nr.*                          Betreff*              │
│ [ANS 0001 - Sonnenfelder    ✕]   [Anschrei... ▾][…]   │
│                                                         │
│ Briefnummer                       Geschäftszeichen      │
│ [OP1-28/25 NJ 7Z24 56213]        [NY 5754/52941-18/2]  │
│                                                         │
│ Brief                                      ✎ 10/12/2025 │  ← Editor-Toolbar
│ A▾  11▾  B I U … ≡ ≡ ≡ ↷ ↶                            │
│ ┌───────────────────────────────────────────────────┐   │
│ │                                                   │   │  ← Editor-Body
│ │ Hiermit bestätige ich Ihnen den Eingang …         │   │     (scroll)
│ │                                                   │   │
│ └───────────────────────────────────────────────────┘   │
├─────────────────────────────────────────────────────────┤
│ 🗑  📎 Vorlage auf Signatur …     [Abbrechen] [Speichern]│  ← Footer (64px)
└─────────────────────────────────────────────────────────┘
```

---

## 3. Visual Specs

### Overlay
- `position: fixed; inset: 0;`
- BG: `rgba(11, 18, 32, 0.38)` (Ink 38 %)
- `backdrop-filter: blur(2px)` — optional, nur Desktop.
- Fade-in 120 ms, cubic-bezier(0.4, 0, 0.2, 1).

### Container
- BG: `--aw-white`
- Border: `1px solid --aw-line`
- Radius: **14 px** (bewusst größer als Cards = 10 px, signalisiert Ebene)
- Shadow: `--aw-shadow-lg` (`0 12px 32px rgba(11,18,32,0.10)`)
- Max-Height: `calc(100vh - 64px)` — Body scrollt, Header + Footer sticky.
- Entry: opacity 0→1 + translateY(8px)→0, 160 ms.

### Header (52 px)
- Padding: `14px 20px`
- Border-Bottom: `1px solid --aw-line`
- Links: **Status-Dot 8 px** (kontextabhängige Farbe) + **Titel** (15 px, 600, Ink, tracking `-0.015em`).
- Rechts: **Close-Button** 28×28, Icon X 14 px, hover BG `--aw-paper`.
- Optional: Eyebrow-Label über dem Titel (10 px uppercase mute) — z. B. „AUFTRAG AW-0046".

### Body
- Padding: `18px 20px 20px`
- Gap zwischen Feld-Reihen: 14 px.
- Section-Divider wenn mehrere Blöcke: `hr` mit Margin 18 px, Farbe `--aw-line`.

### Form-Grid
- Default: `grid-template-columns: repeat(3, 1fr); gap: 14px 16px` für Modal L.
- Modal M: `repeat(2, 1fr)`, Modal S: 1 Spalte.
- Feld-Label (oberhalb Input): 11 px, 500, `--aw-mute`, margin-bottom 4.
- Pflichtfeld-Stern: Orange 500, klein (9 px), margin-left 2.
- Volle Breite: `grid-column: 1 / -1`.

### Footer (64 px)
- Padding: `14px 20px`
- Border-Top: `1px solid --aw-line`
- Hintergrund: `--aw-paper` (warmes Grau — trennt Footer visuell ohne Linie-Konflikt)
- Layout: `display:flex; justify-content: space-between; align-items:center;`
- **Links:** Destruktive/Tertiäre Actions (🗑 Löschen, 📎 Vorlage) — `.aw-btn-ghost`, Icon 16 px.
- **Rechts:** Sekundär → Primär Reihenfolge, 8 px Gap.
    - `Abbrechen` — `.aw-btn-ghost`
    - `Speichern` — `.aw-btn-primary`

---

## 4. Felder in Dialogen

### Input (Text / Nummer / Datum)
```css
height: 34px;
padding: 0 10px;
background: var(--aw-white);
border: 1px solid var(--aw-line-strong);
border-radius: 8px;
font: 500 12.5px/1 var(--aw-font-sans);
color: var(--aw-ink);
```
- Fokus: Border `--aw-orange`, `box-shadow: 0 0 0 3px var(--aw-orange-soft)`.
- Error: Border `--aw-red`, Helper-Text rot 11 px darunter.
- Trailing-Icon (📅, 🔍, ▾): 14 px, `--aw-mute`, 8 px vom rechten Rand.

### Select
- Gleiche Box. Caret-Icon ▾ rechts, 11 px, `--aw-mute`.
- Dropdown-Panel: gleicher Radius (8), weiße BG, `--aw-shadow-md`, Items 32 px hoch, Hover `--aw-paper`, Selected `--aw-orange-soft` + Ink 500.

### Search-Feld mit Chip-Wert (wie „Art Nr." im Screenshot)
- Chip links in der Input-Box: `--aw-orange-soft` BG, Text Orange-Deep 500, Icon-X 10 px rechts im Chip.
- Rest des Inputs ist Suchfläche.

### Multi-Line / Editor
- Toolbar separater Streifen darüber: 40 px Höhe, `--aw-paper` BG, `--aw-line` bottom, Icon-Buttons 28×28, stroke 1.5.
- Editor-Body: mindestens 200 px, max `calc(100vh - 320px)`, Padding 14 px, Ink Text, 13 px line-height 1.6.

---

## 5. Bestätigungs-Modal (Modal S, 420 px)

```
┌────────────────────────────────────┐
│  ⚠  Auftrag löschen?           ✕  │
├────────────────────────────────────┤
│  Auftrag AW-0046 wird unwider-     │
│  ruflich entfernt. Alle Anhänge    │
│  bleiben 30 Tage im Papierkorb.    │
├────────────────────────────────────┤
│              [Abbrechen]  [Löschen]│
└────────────────────────────────────┘
```

- Icon-Badge links im Header: 28 × 28, Kreis, `--aw-red-soft` BG, Icon `--aw-red`.
- Destruktiver Primary: BG `--aw-red`, Text weiß. Gleiche Form wie `.aw-btn-primary`.
- Titel max 40 Zeichen, Body max 3 Zeilen.

---

## 6. Side-Sheet (520 px, rechts)

- `position: fixed; top:0; right:0; height: 100vh; width: 520px;`
- Entry: translateX(24px) → 0, 200 ms.
- Header wie Modal (52 px). Footer **sticky unten**, nicht immer nötig.
- Einsatz: Gutachten-Quick-View, Kontakt-Inspector, Filter-Detail in Listen.

---

## 7. Toast (360 px, unten rechts)

- Position: `bottom: 20px; right: 20px;`
- Container: `--aw-ink` BG, weißer Text 12.5 px, Radius 8, Padding 10 × 14, Shadow lg.
- Icon 16 px links (✓ grün / ⚠ amber / ✕ rot).
- Action-Link optional rechts: Orange 500, underline on hover.
- Auto-Dismiss: 4 s (Success), 6 s (Error, mit Retry-Link).
- Max 3 gleichzeitig gestapelt, Gap 8.

---

## 8. Verhalten

- **Fokus-Falle:** Tab-Order bleibt im Modal, `Esc` schließt (außer bei ungespeicherten Änderungen → Discard-Confirm).
- **Autofocus** auf das erste editierbare Feld nach Öffnen.
- **Ungespeichert-Schutz:** Bei dirty Form → Confirm-Modal S auf Abbrechen/Close.
- **Scroll-Lock** auf `body` solange offen.
- **Nur 1 Modal gleichzeitig.** Confirm über Modal = Stack bis max 2 Ebenen (zweite Ebene 90 % Scale + mehr Overlay).
- **URL-State:** Modals, die Ressourcen zeigen (Anschreiben, Gutachten-Preview), sollten den Zustand in der URL halten (`?modal=anschreiben&id=ANS-0001`) — Reload-sicher, teilbar.
- **ESC / Click-outside:** schließt Modal S/M, Side-Sheet, Popover. **Nicht** Modal L/XL mit Form-Dirty-State.

---

## 9. Accessibility

- `role="dialog"` + `aria-modal="true"` + `aria-labelledby` auf Titel-ID.
- Close-Button mit `aria-label="Schließen"`.
- Nach Schließen: Fokus zurück auf das auslösende Element.
- Kontrast: Header-Text ≥ 7:1, Body ≥ 4.5:1 (gegen weißen BG).

---

## 10. Code-Grundgerüst

```tsx
// src/components/Modal.tsx
import { useEffect, useRef } from 'react';

type Size = 'sm' | 'md' | 'lg' | 'xl';
const WIDTH: Record<Size, number> = { sm: 420, md: 640, lg: 880, xl: 1120 };

export function Modal({
  open, title, eyebrow, size = 'md', onClose,
  statusDot, children, footerLeft, footerRight,
}: {
  open: boolean; title: string; eyebrow?: string; size?: Size;
  onClose: () => void;
  statusDot?: 'orange' | 'green' | 'amber' | 'red';
  children: React.ReactNode;
  footerLeft?: React.ReactNode; footerRight?: React.ReactNode;
}) {
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && onClose();
    window.addEventListener('keydown', onKey);
    document.body.style.overflow = 'hidden';
    return () => { window.removeEventListener('keydown', onKey); document.body.style.overflow = ''; };
  }, [open, onClose]);

  if (!open) return null;
  const dotColor = {
    orange: 'var(--aw-orange)', green: 'var(--aw-green)',
    amber: 'var(--aw-amber)', red: 'var(--aw-red)',
  }[statusDot ?? 'orange'];

  return (
    <div role="dialog" aria-modal="true" aria-labelledby="dlg-title"
      style={{ position:'fixed', inset:0, background:'rgba(11,18,32,0.38)', backdropFilter:'blur(2px)',
               display:'flex', alignItems:'flex-start', justifyContent:'center', paddingTop: 64, zIndex: 1000 }}
      onMouseDown={(e) => e.target === e.currentTarget && onClose()}
    >
      <div ref={ref} style={{
        width: WIDTH[size], maxWidth: 'calc(100vw - 32px)', maxHeight: 'calc(100vh - 96px)',
        background: 'var(--aw-white)', border: '1px solid var(--aw-line)', borderRadius: 14,
        boxShadow: 'var(--aw-shadow-lg)', display: 'flex', flexDirection: 'column', overflow: 'hidden',
      }}>
        <div style={{ display:'flex', alignItems:'center', gap: 10, padding: '14px 20px',
                       borderBottom: '1px solid var(--aw-line)' }}>
          {statusDot && <span style={{ width:8, height:8, borderRadius:4, background:dotColor }} />}
          <div style={{ flex:1, minWidth:0 }}>
            {eyebrow && <div className="aw-eyebrow" style={{ marginBottom: 2 }}>{eyebrow}</div>}
            <div id="dlg-title" style={{ fontSize:15, fontWeight:600, color:'var(--aw-ink)', letterSpacing:'-0.015em' }}>{title}</div>
          </div>
          <button aria-label="Schließen" onClick={onClose}
            style={{ width:28, height:28, border:'none', background:'transparent', borderRadius:6, cursor:'pointer',
                     display:'inline-flex', alignItems:'center', justifyContent:'center', color:'var(--aw-mute)' }}>✕</button>
        </div>
        <div style={{ padding:'18px 20px', overflow:'auto', flex:1 }}>{children}</div>
        {(footerLeft || footerRight) && (
          <div style={{ display:'flex', justifyContent:'space-between', alignItems:'center',
                         padding:'14px 20px', borderTop:'1px solid var(--aw-line)',
                         background:'var(--aw-paper)', gap: 12 }}>
            <div style={{ display:'flex', gap: 8 }}>{footerLeft}</div>
            <div style={{ display:'flex', gap: 8 }}>{footerRight}</div>
          </div>
        )}
      </div>
    </div>
  );
}
```

---

## 11. Checkliste pro Dialog

- [ ] Richtige Größe gewählt (Inhalt ≠ Container-Größe)
- [ ] Header: Status-Dot + Titel + Close
- [ ] Body scrollt, Header + Footer sticky
- [ ] Form-Grid-Spalten konsistent
- [ ] Primary rechts, Destruktiv links im Footer
- [ ] Autofocus, ESC, Click-outside, Dirty-Schutz
- [ ] `role="dialog"` + `aria-modal` + `aria-labelledby`
- [ ] URL-State (wenn Ressource)
- [ ] Scroll-Lock auf body
