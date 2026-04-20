#!/usr/bin/env node
// Führt die seedDemo()-Funktion aus der SV-Software gegen ein
// In-Memory-IndexedDB-Mock aus und schreibt das Ergebnis als JSON.
//
// Usage:
//   node extract_demo_seed.js > assets/data/demo_seed.json
//
// Die Pfade können via SV_SOFTWARE_HTML überschrieben werden.

const fs = require('fs');

const ORIGINAL = process.env.SV_SOFTWARE_HTML
    || '/Users/ahoepken/Documents/CoWork/SV-Software/index.html';

// --------------- Mock der SV-Software-Umgebung ---------------
const data = {};
const nextId = {};

const idb = {
  add: async (store, obj) => {
    nextId[store] = (nextId[store] || 0) + 1;
    const id = nextId[store];
    const row = Object.assign({}, obj, { id });
    (data[store] = data[store] || []).push(row);
    return id;
  },
  put: async (store, obj) => {
    const arr = data[store] = data[store] || [];
    if (obj.id != null) {
      const i = arr.findIndex(r => r.id === obj.id);
      if (i >= 0) arr[i] = Object.assign({}, arr[i], obj);
      else arr.push(Object.assign({}, obj));
    } else {
      return idb.add(store, obj);
    }
    return obj.id;
  },
  all: async (store) => (data[store] || []).slice(),
  getAll: async (store) => (data[store] || []).slice(),
  get: async (store, id) => (data[store] || []).find(r => r.id === id) || null,
  del: async (store, id) => {
    data[store] = (data[store] || []).filter(r => r.id !== id);
  },
};

const maybeBackup = () => {};

// -------- Helper, die im Original außerhalb von seedDemo leben --------

function makeSvgFoto(title, bg, fg) {
  return `demo-svg:${title}|${bg}|${fg}`;
}

const fmtDate = (d) =>
  d ? new Date(d).toLocaleDateString('de-DE') : '–';
const fmtDateTime = (d) =>
  d ? new Date(d).toLocaleString('de-DE',
        { dateStyle: 'short', timeStyle: 'short' }) : '–';

const STAMMDATEN_HOEPKEN = {
  name: 'Alexander Höpken',
  titel: 'Dipl.-Ing. (FH), M. Eng.',
  bestellung1: 'Beratender Ingenieur\nund Sachverständiger',
  bestellung2:
      'ift-Fachingenieur Fenster & Fassade\nEnergieberater\n' +
      'Energieeffizienz-Experte\n(Beraternummer EB463265)',
  bestellung:
      'Beratender Ingenieur und Sachverständiger\n' +
      'ift Fachingenieur für Fenster & Fassade\n' +
      'Energieberater · Energieeffizienz-Experte (Beraternummer EB463265)',
  anschrift: 'Auf dem Stemmingholt 21\n46499 Hamminkeln',
  telefon: '+49 152 519 75042',
  email: 'buero@bauelemente-experte.de',
  website: 'www.bauelemente-experte.de',
  ustid: 'DE240376766',
  steuernr: '130/5051/2997',
  kontoinhaber: 'Alexander Höpken',
  bank: 'Volksbank Rhein-Lippe',
  iban: 'DE54 3566 0599 1201 3270 20',
  bic: 'GENODED1RLW',
  stundensatzPrivat: 140,
  stundensatzJveg: 130,
  mwstSatz: 19,
  kleinunternehmer: 'nein',
  jvegKmSatz: 0.42,
  jvegSchreibsatz: 1.80,
  jvegKopieSw: 0.50,
  jvegKopieFarbe: 1.00,
  jvegLichtbildErstes: 2.00,
  jvegLichtbildWeitere: 1.00,
  zahlungszielTage: 14,
  rechnungSchlusstext:
      'Bitte überweisen Sie den Rechnungsbetrag innerhalb des ' +
      'Zahlungsziels auf das unten genannte Konto. Vielen Dank ' +
      'für Ihren Auftrag.',
  nummernkreise: {
    auftrag: { muster: '{YYYY}-{NNN}', naechste: 1, reset: 'jahr' },
    angebot: { muster: 'A{YYYY}-{NNN}', naechste: 1, reset: 'jahr' },
    rechnung: { muster: 'R{YYYY}-{NNN}', naechste: 1, reset: 'jahr' },
    gutachten: { muster: '{aktenzeichen}-G{N}', naechste: 1, reset: 'nie' },
    fortbildung: { muster: 'FB{YYYY}-{NN}', naechste: 1, reset: 'jahr' },
  },
};

async function setStammdatenHoepken(_ = true) {
  await idb.add('einstellungen', { key: 'stammdaten', wert: STAMMDATEN_HOEPKEN });
}

const AUFGABEN_DEFAULT = [
  'Auftragseingang bestätigt',
  'Befangenheits-Prüfung durchgeführt (keine Beziehungen zu Beteiligten)',
  'Beweisbeschluss / Auftrag gelesen, Beweisfragen geklärt',
  'Kostenrahmen geprüft, ggf. Mehrkostenanzeige nach § 8a Abs. 4 JVEG',
  'Akteneinsicht / Vorkorrespondenz gesichtet',
  'Ortstermin abgestimmt (alle Beteiligten geladen)',
  'Ortstermin durchgeführt + protokolliert',
  'Messungen / Bauteilöffnungen dokumentiert',
  'Lichtbilder gesichtet und Lichtbildanlage erstellt',
  'Befund / Feststellungen erfasst',
  'Sachverständige Würdigung formuliert',
  'Variantenvergleich Maßnahmen erstellt',
  'Kostenschätzung erstellt (DIN 276 Stufe 2)',
  'Verantwortlichkeit (übliche Maßstäbe) formuliert',
  'Beweisfragen vollständig beantwortet',
  'Sprach-/Floskel-Check durchgeführt',
  'Gutachten-Entwurf fertig (intern geprüft)',
  'Gutachten in geforderter Anzahl ausgefertigt',
  'Gutachten versendet',
  'Rechnung nach JVEG / Privatabrechnung gestellt',
  'Zahlung eingegangen / verbucht',
];

const SKR_KATEGORIEN = [
  { key: 'kfz', label: 'Kfz-Kosten', skr03: '4530', skr04: '6500', ustSatz: 19 },
  { key: 'kfz_versich', label: 'Kfz-Versicherung', skr03: '4520', skr04: '6520', ustSatz: 0 },
  { key: 'reise', label: 'Reisekosten', skr03: '4670', skr04: '6673', ustSatz: 7 },
  { key: 'bewirtung', label: 'Bewirtung', skr03: '4650', skr04: '6640', ustSatz: 19 },
  { key: 'buero', label: 'Bürobedarf', skr03: '4930', skr04: '6815', ustSatz: 19 },
  { key: 'porto', label: 'Porto', skr03: '4910', skr04: '6800', ustSatz: 0 },
  { key: 'tel', label: 'Telefon / Internet', skr03: '4920', skr04: '6805', ustSatz: 19 },
  { key: 'edv', label: 'EDV / Software', skr03: '4940', skr04: '6810', ustSatz: 19 },
  { key: 'fortbildung', label: 'Fortbildung', skr03: '4948', skr04: '6840', ustSatz: 7 },
  { key: 'versicherung', label: 'Betriebsversicherung', skr03: '4360', skr04: '6400', ustSatz: 0 },
  { key: 'beitraege', label: 'Beiträge', skr03: '4380', skr04: '6420', ustSatz: 0 },
  { key: 'rechtberatung', label: 'Rechtsberatung', skr03: '4950', skr04: '6825', ustSatz: 19 },
  { key: 'steuerberatung', label: 'Steuerberatung', skr03: '4957', skr04: '6827', ustSatz: 19 },
  { key: 'werkzeug', label: 'Werkzeuge / Messgeräte', skr03: '4985', skr04: '6850', ustSatz: 19 },
  { key: 'gwg', label: 'GWG', skr03: '0480', skr04: '0670', ustSatz: 19 },
  { key: 'afa', label: 'AfA', skr03: '4830', skr04: '6220', ustSatz: 0 },
  { key: 'miete', label: 'Miete', skr03: '4210', skr04: '6310', ustSatz: 0 },
  { key: 'energie', label: 'Energie', skr03: '4240', skr04: '6325', ustSatz: 19 },
  { key: 'fremdleistung', label: 'Fremdleistung', skr03: '3100', skr04: '5900', ustSatz: 19 },
  { key: 'werbung', label: 'Werbung', skr03: '4600', skr04: '6600', ustSatz: 19 },
  { key: 'webhosting', label: 'Webhosting', skr03: '4920', skr04: '6805', ustSatz: 19 },
  { key: 'bankgebuehr', label: 'Bankgebühren', skr03: '4970', skr04: '6855', ustSatz: 0 },
  { key: 'zinsen', label: 'Zinsen', skr03: '2100', skr04: '7300', ustSatz: 0 },
  { key: 'sonstiges', label: 'Sonstiges', skr03: '4980', skr04: '6855', ustSatz: 19 },
];

function getSkrKategorie(key) {
  return SKR_KATEGORIEN.find(k => k.key === key)
      || { key: 'sonstiges', label: 'Sonstiges', skr03: '4980', skr04: '6855', ustSatz: 19 };
}

// btoa: überschreiben, damit Unicode (—, ä etc.) nicht "Invalid character" wirft.
global.btoa = (s) => Buffer.from(String(s), 'utf8').toString('base64');

// Alle console-Ausgaben des seedDemo-Scripts auf stderr umleiten,
// damit sie die JSON-Ausgabe auf stdout nicht verfälschen.
console.log = (...a) => process.stderr.write(a.map(String).join(' ') + '\n');
console.warn = (...a) => process.stderr.write(a.map(String).join(' ') + '\n');

async function hashPasswort(pw) {
  const { createHash } = require('crypto');
  return createHash('sha256').update(String(pw)).digest('hex');
}

// ------------------ seedDemo aus dem Original parsen ------------------

const html = fs.readFileSync(ORIGINAL, 'utf8');
const lines = html.split('\n');

function extractSeedDemo() {
  const startIdx = lines.findIndex(l =>
      /^async function seedDemo\s*\(/.test(l));
  if (startIdx < 0) throw new Error('seedDemo() nicht gefunden');
  let depth = 0;
  let opened = false;
  for (let i = startIdx; i < lines.length; i++) {
    for (const ch of lines[i]) {
      if (ch === '{') { depth++; opened = true; }
      else if (ch === '}') { depth--; if (opened && depth === 0) {
        return lines.slice(startIdx, i + 1).join('\n');
      } }
    }
  }
  throw new Error('Ende von seedDemo() nicht gefunden');
}

const seedDemoSource = extractSeedDemo();

// ------------------ Ausführen ------------------

async function run() {
  const runner = new Function(
    'idb', 'maybeBackup', 'makeSvgFoto',
    'fmtDate', 'fmtDateTime',
    'STAMMDATEN_HOEPKEN', 'setStammdatenHoepken',
    'AUFGABEN_DEFAULT',
    'SKR_KATEGORIEN', 'getSkrKategorie',
    'hashPasswort',
    seedDemoSource + '\nreturn seedDemo();'
  );
  try {
    await runner(
      idb, maybeBackup, makeSvgFoto,
      fmtDate, fmtDateTime,
      STAMMDATEN_HOEPKEN, setStammdatenHoepken,
      AUFGABEN_DEFAULT,
      SKR_KATEGORIEN, getSkrKategorie,
      hashPasswort,
    );
  } catch (e) {
    console.error('[warn] seedDemo meldete Fehler:', e.message);
  }
  const stats = Object.fromEntries(
    Object.entries(data).map(([k, v]) => [k, v.length]));
  console.error('[info] Einträge je Store:', stats);
  return data;
}

run().then((result) => {
  process.stdout.write(JSON.stringify(result, null, 2));
}).catch((e) => {
  console.error(e);
  process.exit(1);
});
