#!/usr/bin/env bash
# Baut das Web-Release für Aktenwerk ohne Flutter-Service-Worker und
# legt einen Tombstone-SW anstelle der leeren `flutter_service_worker.js`
# ab. Damit ersetzt jeder Deploy den alten SW durch einen Pass-Through,
# der alle Caches löscht, offene Tabs neu lädt und sich selbst abmeldet.
#
# Nutzung: ./scripts/build_web.sh
set -euo pipefail

cd "$(dirname "$0")/.."

flutter build web --release --pwa-strategy=none

# Tombstone-Inhalt in flutter_service_worker.js kopieren, damit der
# Browser alte Flutter-SWs automatisch durch den Pass-Through ersetzt.
cp web/tombstone-sw.js build/web/flutter_service_worker.js

# Optional: PNG-Favicons aus dem aktuellen SVG-Mark regenerieren.
# Braucht rsvg-convert oder inkscape — wenn nicht da, überspringen.
if command -v rsvg-convert >/dev/null 2>&1; then
  rsvg-convert -w 32 -h 32 web/icon.svg -o web/favicon.png
  rsvg-convert -w 192 -h 192 web/icon.svg -o web/icons/Icon-192.png
  rsvg-convert -w 512 -h 512 web/icon.svg -o web/icons/Icon-512.png
  rsvg-convert -w 192 -h 192 web/icon.svg -o web/icons/Icon-maskable-192.png
  rsvg-convert -w 512 -h 512 web/icon.svg -o web/icons/Icon-maskable-512.png
  echo "Favicons neu generiert."
elif command -v inkscape >/dev/null 2>&1; then
  inkscape --export-type=png -w 32 -h 32 web/icon.svg -o web/favicon.png
  inkscape --export-type=png -w 192 -h 192 web/icon.svg -o web/icons/Icon-192.png
  inkscape --export-type=png -w 512 -h 512 web/icon.svg -o web/icons/Icon-512.png
  echo "Favicons neu generiert (via Inkscape)."
else
  echo "(Hinweis: rsvg-convert/inkscape nicht installiert — PNG-Favicons"
  echo " bleiben wie sie sind. SVG-Favicon (web/icon.svg) ist aktuell.)"
fi

echo "Build fertig. Deploy mit: firebase deploy --only hosting:app"
