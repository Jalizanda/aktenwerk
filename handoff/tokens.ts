/**
 * Aktenwerk Design Tokens (JS/TS)
 * Mirrors tokens.css for use in styled-components, Tailwind config, or inline styles.
 */

export const colors = {
  orange:       '#F25C1F',
  orangeDeep:   '#D94810',
  orangeSoft:   'rgba(242, 92, 31, 0.10)',
  orangeBorder: 'rgba(242, 92, 31, 0.28)',

  ink:          '#0B1220',
  ink2:         '#1A2235',

  paper:        '#FAFAF7',
  white:        '#FFFFFF',
  mute:         'rgba(11, 18, 32, 0.55)',
  muteSoft:     'rgba(11, 18, 32, 0.35)',
  line:         'rgba(11, 18, 32, 0.08)',
  lineStrong:   'rgba(11, 18, 32, 0.14)',

  green:        '#16794A',
  greenSoft:    'rgba(22, 121, 74, 0.10)',
  amber:        '#B45309',
  amberSoft:    'rgba(180, 83, 9, 0.10)',
  red:          '#B42318',
  redSoft:      'rgba(180, 35, 24, 0.10)',
  blue:         '#1E4ED8',
  blueSoft:     'rgba(30, 78, 216, 0.08)',
} as const;

export const typography = {
  sans: "'Geist', -apple-system, BlinkMacSystemFont, 'Segoe UI', system-ui, sans-serif",
  mono: "'Geist Mono', ui-monospace, SFMono-Regular, Menlo, monospace",
  tracking: {
    tight:   '-0.025em',
    body:    '-0.01em',
    eyebrow: '0.05em',
    micro:   '0.12em',
  },
};

export const radius = { xs: 4, sm: 6, md: 8, lg: 10, xl: 14 } as const;

export const statusMap = {
  'In Bearbeitung': { className: 'aw-badge aw-badge--in-progress' },
  'Zu prüfen':      { className: 'aw-badge aw-badge--todo' },
  'Abgeschlossen':  { className: 'aw-badge aw-badge--done' },
  'Überfällig':     { className: 'aw-badge aw-badge--overdue' },
  'Entwurf':        { className: 'aw-badge aw-badge--draft' },
  'Ortstermin':     { className: 'aw-badge aw-badge--info' },
  'Bezahlt':        { className: 'aw-badge aw-badge--done' },
  'Offen':          { className: 'aw-badge aw-badge--info' },
  'Mahnung 1':      { className: 'aw-badge aw-badge--overdue' },
  'Mahnung 2':      { className: 'aw-badge aw-badge--overdue' },
} as const;
