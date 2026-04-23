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

echo "Build fertig. Deploy mit: firebase deploy --only hosting:app"
