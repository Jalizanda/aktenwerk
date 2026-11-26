#!/bin/bash
# GutachtenManager → Aktenwerk: Datenbank als CSV-Dateien exportieren.
#
# Voraussetzung (einmalig):  brew install mdbtools
# Aufruf:                    ./tool/gm_export.sh /Pfad/zu/GutachterDBV80.mdb [Zielordner]
#
# Danach in Aktenwerk: Einstellungen › „Word-Vorlagen, Gerichte & Datenübernahme“
# › „Gutachten-Manager-Daten importieren“ und alle erzeugten CSV-Dateien auswählen.
# Übernommen werden Auftraggeber, Akten, Beteiligte, Zeiten und Auslagen
# (keine Rechnungen, keine Dokumente).
set -euo pipefail

MDB="${1:-}"
ZIEL="${2:-$HOME/Desktop/GM-Export}"

if [[ -z "$MDB" || ! -f "$MDB" ]]; then
  echo "Bitte Pfad zur GutachtenManager-Datenbank angeben (z. B. GutachterDBV80.mdb)." >&2
  exit 1
fi
if ! command -v mdb-tables >/dev/null 2>&1; then
  echo "mdbtools fehlt. Installation: brew install mdbtools" >&2
  exit 1
fi

mkdir -p "$ZIEL"
anzahl=0
while IFS= read -r tabelle; do
  [[ -z "$tabelle" ]] && continue
  datei="$ZIEL/${tabelle// /_}.csv"
  # Datumsformat ISO, Komma-getrennt, UTF-8
  mdb-export -D '%Y-%m-%d %H:%M:%S' "$MDB" "$tabelle" > "$datei"
  echo "  ✓ $tabelle"
  anzahl=$((anzahl + 1))
done < <(mdb-tables -1 "$MDB")

echo
echo "$anzahl Tabellen nach $ZIEL exportiert."
echo "Kennwortgeschützte Datenbanken müssen vorher in Access ohne Kennwort gespeichert werden."
