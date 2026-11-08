#!/usr/bin/env bash
# Baut hibiscus.ly.reports ohne Apache Ant und legt das Ergebnis im Layout des
# Jameica-Repositories ab (ohne Signatur, die erledigt der Workflow).
#
# Aufruf:  torac/build-plugin.sh
#
# Eingaben (Umgebungsvariablen):
#   JAMEICA_DIR       entpacktes Jameica-Release (Ordner mit jameica.jar)
#   HIBISCUS_DIR      entpacktes Hibiscus-Release (Ordner mit hibiscus.jar)
#   PAGES_BASE_URL    Wurzel des Repositories, z. B. https://toracgmbh.github.io/hibiscus.ly.reports
#   BUILD_NUMBER      laufende Build-Nummer (github.run_number), 1..9999
#   OUT_DIR           Ausgabeordner (wird neu angelegt), Standard: build-output/torac
#
# Ergebnis in OUT_DIR:
#   classes/                                   kompilierte Klassen
#   dist/hibiscus.ly.reports/                  Inhalt der ZIP (Jar, plugin.xml, LICENSE, README.md, ChangeLog.txt, lib/)
#   site/hibiscus.ly.reports/plugin.xml        veröffentlichte plugin.xml
#   site/hibiscus.ly.reports/hibiscus.ly.reports.zip
#   version.txt                                veröffentlichte Version
set -euo pipefail

: "${JAMEICA_DIR:?JAMEICA_DIR fehlt}"
: "${HIBISCUS_DIR:?HIBISCUS_DIR fehlt}"
: "${PAGES_BASE_URL:?PAGES_BASE_URL fehlt}"
: "${BUILD_NUMBER:?BUILD_NUMBER fehlt}"

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${OUT_DIR:-$REPO_DIR/build-output/torac}"
PLUGIN=hibiscus.ly.reports
PAGES_BASE_URL="${PAGES_BASE_URL%/}"

cd "$REPO_DIR"

# --- Version -----------------------------------------------------------------
# Jameicas Version-Klasse liest nur major.minor.patch (weitere Teile und der
# Suffix nach "-" zählen im Vergleich nicht). Die laufende Nummer steckt darum
# im Patch-Teil:  <major>.<minor>.<patch * 10000 + Build-Nummer>.
# Beispiel: Upstream 1.3.2, Build 7  ->  1.3.20007
UPSTREAM_VERSION="$(sed -n 's/.*name="'"$PLUGIN"'"[[:space:]]*version="\([^"]*\)".*/\1/p' plugin.xml | head -n1)"
if ! [[ "$UPSTREAM_VERSION" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  echo "Upstream-Version '$UPSTREAM_VERSION' in plugin.xml ist nicht von der Form X.Y.Z" >&2
  exit 1
fi
MAJOR="${BASH_REMATCH[1]}"; MINOR="${BASH_REMATCH[2]}"; PATCH="${BASH_REMATCH[3]}"
if ! [[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || [ "$BUILD_NUMBER" -lt 1 ] || [ "$BUILD_NUMBER" -ge 10000 ]; then
  echo "BUILD_NUMBER '$BUILD_NUMBER' muss zwischen 1 und 9999 liegen" >&2
  exit 1
fi
VERSION="$MAJOR.$MINOR.$((PATCH * 10000 + BUILD_NUMBER))"
PLUGIN_URL="$PAGES_BASE_URL/$PLUGIN/$PLUGIN.zip"
echo "Upstream-Version: $UPSTREAM_VERSION, veröffentlichte Version: $VERSION"
echo "Download-URL    : $PLUGIN_URL"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR/classes" "$OUT_DIR/dist/$PLUGIN" "$OUT_DIR/site/$PLUGIN"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"

# --- Kompilieren -------------------------------------------------------------
# Wie compile.path in build/build.xml. Ein "javascript"-Ordner existiert in
# Jameica 2.12 nicht mehr und wird daher nicht angegeben.
CP="$JAMEICA_DIR/jameica.jar:$HIBISCUS_DIR/hibiscus.jar"
while IFS= read -r jar; do CP="$CP:$jar"; done < <(
  { find "$JAMEICA_DIR/lib/swt" "$JAMEICA_DIR/lib/de_willuhn_ds" "$JAMEICA_DIR/lib/de_willuhn_util" \
         "$HIBISCUS_DIR/lib" lib -name '*.jar' -type f; } | sort)
echo "$CP" > "$OUT_DIR/classpath.txt"

find src -name '*.java' | sort > "$OUT_DIR/sources.txt"
javac --release 17 -encoding UTF-8 -g -nowarn -cp "$CP" -d "$OUT_DIR/classes" @"$OUT_DIR/sources.txt"
mkdir -p "$OUT_DIR/classes/help"
cp -R src/help/. "$OUT_DIR/classes/help/"

# --- Jar ---------------------------------------------------------------------
cat > "$OUT_DIR/manifest.txt" <<EOF
Implementation-Title: $PLUGIN
Implementation-Version: $VERSION
Implementation-Buildnumber: $BUILD_NUMBER
Upstream-Version: $UPSTREAM_VERSION
EOF
jar cfm "$OUT_DIR/dist/$PLUGIN/$PLUGIN.jar" "$OUT_DIR/manifest.txt" -C "$OUT_DIR/classes" .

# --- plugin.xml für die Veröffentlichung -------------------------------------
# Nur Version (am Plugin-Element, nicht bei <import>) und <url> ändern; die
# Quelldatei im Repo bleibt unverändert.
sed -e 's|\(name="'"$PLUGIN"'"[[:space:]]*version="\)[^"]*\(".*\)|\1'"$VERSION"'\2|' \
    -e 's|<url>[^<]*</url>|<url>'"$PLUGIN_URL"'</url>|' \
    plugin.xml > "$OUT_DIR/dist/$PLUGIN/plugin.xml"
grep -q "name=\"$PLUGIN\" version=\"$VERSION\"" "$OUT_DIR/dist/$PLUGIN/plugin.xml" \
  || { echo "Version in plugin.xml wurde nicht ersetzt" >&2; exit 1; }
grep -q "<url>$PLUGIN_URL</url>" "$OUT_DIR/dist/$PLUGIN/plugin.xml" \
  || { echo "<url> in plugin.xml wurde nicht ersetzt" >&2; exit 1; }

# --- Weitere Dateien und Bibliotheken ----------------------------------------
cp LICENSE README.md ChangeLog.txt "$OUT_DIR/dist/$PLUGIN/"
mkdir -p "$OUT_DIR/dist/$PLUGIN/lib/javascript"   # wie im Original-ZIP
while IFS= read -r jar; do
  rel="${jar#lib/}"
  mkdir -p "$OUT_DIR/dist/$PLUGIN/lib/$(dirname "$rel")"
  cp "$jar" "$OUT_DIR/dist/$PLUGIN/lib/$rel"
done < <(find lib -name '*.jar' -type f | sort)

# --- ZIP ---------------------------------------------------------------------
(cd "$OUT_DIR/dist" && zip -X -q -r "$OUT_DIR/site/$PLUGIN/$PLUGIN.zip" "$PLUGIN")
cp "$OUT_DIR/dist/$PLUGIN/plugin.xml" "$OUT_DIR/site/$PLUGIN/plugin.xml"
printf '%s\n' "$VERSION" > "$OUT_DIR/version.txt"
echo "Fertig: $OUT_DIR/site/$PLUGIN/$PLUGIN.zip"
