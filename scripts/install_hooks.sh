#!/bin/bash
# install_hooks.sh
# Installiert den Release Agent als post-commit hook im aktuellen Git-Repository.

HOOK_DIR=".git/hooks"
HOOK_FILE="$HOOK_DIR/post-commit"

if [ ! -d "$HOOK_DIR" ]; then
    echo "❌ Fehler: .git/hooks Verzeichnis nicht gefunden. Bitte führe das Skript im Root-Verzeichnis des Projekts aus."
    exit 1
fi

echo "⚙️ Installiere post-commit hook..."

cat << 'EOF' > "$HOOK_FILE"
#!/bin/bash

# Rufe den Release Agent auf, um den Changelog automatisch zu aktualisieren
dart run tool/release_agent.dart

# Prüfe, ob die CHANGELOG.md durch den Agenten verändert wurde
if git diff --name-only | grep -q "CHANGELOG.md"; then
    echo ""
    echo "🤖 [Agent] Ich habe die CHANGELOG.md aktualisiert!"
    echo "💡 Tipp: Mit 'git commit --amend --no-edit CHANGELOG.md' kannst du die Änderung direkt in deinen letzten Commit übernehmen."
fi
EOF

chmod +x "$HOOK_FILE"

echo "✅ post-commit hook erfolgreich installiert! Der Release Agent läuft nun bei jedem Commit automatisch mit."
