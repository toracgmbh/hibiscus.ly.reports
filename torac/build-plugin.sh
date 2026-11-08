#!/usr/bin/env bash
# Baut hibiscus.ly.reports ohne Apache Ant und legt die UNSIGNIERTE ZIP samt
# plugin.xml ab. Signieren und Veröffentlichen erledigt der Workflow in
# eigenen Jobs (siehe torac/README.md).
#
# Aufruf:  torac/build-plugin.sh
#
# Eingaben (Umgebungsvariablen):
#   JAMEICA_DIR       entpacktes Jameica-Release (Ordner mit jameica.jar)
#   HIBISCUS_DIR      entpacktes Hibiscus-Release (Ordner mit hibiscus.jar)
#   PAGES_BASE_URL    Wurzel des Repositories, z. B. https://toracgmbh.github.io/hibiscus.ly.reports
#   BUILD_NUMBER      laufende Build-Nummer (github.run_number), 1..9999
#   OUT_DIR           Ausgabeordner (wird neu angelegt), Standard: build-output/torac.
#                     Relative Pfade gelten ab dem aktuellen Ordner des Aufrufs. Der Pfad wird
#                     aufgelöst (Symlinks, ".", ".."), bevor etwas gelöscht wird. Der Ordner
#                     wird nur gelöscht, wenn er nicht existiert, leer ist oder die Markierungs-
#                     datei .build-plugin-out enthält (die das Skript selbst anlegt), und nie,
#                     wenn er das Repo, $HOME, "/" oder ein Elternordner davon ist.
#   BUILD_PLUGIN_STOP_AFTER   nur für torac/test-build-plugin-guard.sh:
#                     "check" beendet das Skript nach der Pfadprüfung, "prepare" nach dem
#                     Neuanlegen des Ausgabeordners (jeweils ohne Build).
#
# Ergebnis in OUT_DIR:
#   classpath.txt                  Classpath (wie compile.path in build/build.xml), auch für die Tests
#   classes/                       kompilierte Klassen
#   dist/hibiscus.ly.reports/      Inhalt der ZIP (Jar, plugin.xml, LICENSE, README.md, ChangeLog.txt, lib/)
#   unsigned/hibiscus.ly.reports.zip   unsignierte ZIP
#   unsigned/plugin.xml            veröffentlichte plugin.xml (gleich der in der ZIP)
#   unsigned/version.txt           veröffentlichte Version
#   repository.xml                 aus der Vorlage erzeugt (nur zur Prüfung, wird nicht veröffentlicht)
set -euo pipefail

die() { echo "build-plugin.sh: $*" >&2; exit 1; }

: "${JAMEICA_DIR:?JAMEICA_DIR fehlt}"
: "${HIBISCUS_DIR:?HIBISCUS_DIR fehlt}"
: "${PAGES_BASE_URL:?PAGES_BASE_URL fehlt}"
: "${BUILD_NUMBER:?BUILD_NUMBER fehlt}"

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
PLUGIN=hibiscus.ly.reports
PAGES_BASE_URL="${PAGES_BASE_URL%/}"
[[ "$PAGES_BASE_URL" =~ ^https://[A-Za-z0-9.-]+(/[A-Za-z0-9._-]+)*$ ]] \
  || die "PAGES_BASE_URL '$PAGES_BASE_URL' hat nicht die erwartete Form https://host/pfad"

# --- Ausgabeordner prüfen und neu anlegen ------------------------------------
# Der Pfad wird vor dem Löschen aufgelöst, auch wenn der Ordner noch nicht
# existiert (existierender Teil: Symlinks aufgelöst, Rest normalisiert).
OUT_MARKER=.build-plugin-out
real_path() { python3 -I -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$1"; }
# is_within <Ordner> <Pfad>: wahr, wenn <Pfad> gleich <Ordner> ist oder darunter liegt
is_within() { [ "$1" = "/" ] || [ "$2" = "$1" ] || [[ "$2" == "$1"/* ]]; }

OUT_DIR="$(real_path "${OUT_DIR:-$REPO_DIR/build-output/torac}")"
HOME_REAL=""
if [ -n "${HOME:-}" ]; then HOME_REAL="$(real_path "$HOME")"; fi
for protected in "$REPO_DIR" "$HOME_REAL"; do
  if [ -n "$protected" ] && is_within "$OUT_DIR" "$protected"; then
    die "OUT_DIR '$OUT_DIR' ist (oder enthält) '$protected' und wird nicht gelöscht. Bitte einen eigenen Ausgabeordner angeben."
  fi
done
if [ -e "$OUT_DIR" ]; then
  [ -d "$OUT_DIR" ] || die "OUT_DIR '$OUT_DIR' existiert und ist kein Ordner"
  if [ -n "$(ls -A "$OUT_DIR")" ] && [ ! -f "$OUT_DIR/$OUT_MARKER" ]; then
    die "OUT_DIR '$OUT_DIR' ist nicht leer und enthält keine Markierung $OUT_MARKER (kein Ausgabeordner dieses Skripts). Er wird nicht gelöscht; bitte leeren oder einen anderen Ordner angeben."
  fi
fi
if [ "${BUILD_PLUGIN_STOP_AFTER:-}" = check ]; then echo "OUT_DIR geprüft: $OUT_DIR"; exit 0; fi

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR/classes" "$OUT_DIR/dist/$PLUGIN" "$OUT_DIR/unsigned"
: > "$OUT_DIR/$OUT_MARKER"
if [ "${BUILD_PLUGIN_STOP_AFTER:-}" = prepare ]; then echo "OUT_DIR angelegt: $OUT_DIR"; exit 0; fi

cd "$REPO_DIR"

# --- Version -----------------------------------------------------------------
# Jameicas Version-Klasse liest nur major.minor.patch (weitere Teile und der
# Suffix nach "-" zählen im Vergleich nicht). Die laufende Nummer steckt darum
# im Patch-Teil:  <major>.<minor>.<patch * 10000 + Build-Nummer>.
# Beispiel: Upstream 1.3.2, Build 7  ->  1.3.20007
UPSTREAM_VERSION="$(python3 -I -c 'import sys, xml.etree.ElementTree as ET; print(ET.parse(sys.argv[1]).getroot().get("version") or "")' plugin.xml)"
if ! [[ "$UPSTREAM_VERSION" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  die "Upstream-Version '$UPSTREAM_VERSION' in plugin.xml ist nicht von der Form X.Y.Z"
fi
MAJOR="${BASH_REMATCH[1]}"; MINOR="${BASH_REMATCH[2]}"; PATCH="${BASH_REMATCH[3]}"
if ! [[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || [ "$BUILD_NUMBER" -lt 1 ] || [ "$BUILD_NUMBER" -ge 10000 ]; then
  die "BUILD_NUMBER '$BUILD_NUMBER' muss zwischen 1 und 9999 liegen"
fi
VERSION="$MAJOR.$MINOR.$((PATCH * 10000 + BUILD_NUMBER))"
PLUGIN_URL="$PAGES_BASE_URL/$PLUGIN/$PLUGIN.zip"
echo "Upstream-Version: $UPSTREAM_VERSION, veröffentlichte Version: $VERSION"
echo "Download-URL    : $PLUGIN_URL"


# --- Classpath ---------------------------------------------------------------
# Genau wie compile.path in build/build.xml, in derselben Reihenfolge:
#   Jameica- und Hibiscus-Klassen, dann lib/**/*.jar aus dem Repo, dann von
#   Jameica swt/**, de_willuhn_ds/*, de_willuhn_util/*, javascript/* und von
#   Hibiscus nur swtchart/* und obantoo-bin-*.jar. Alle anderen Bibliotheken
#   von Hibiscus gehören nicht dazu: Das Plugin bringt seine eigenen mit
#   (lib/ in der ZIP), und gegen genau diese wird übersetzt und getestet.
# Innerhalb einer Gruppe sortiert "LC_ALL=C sort" unabhängig von der Locale.
[ -f "$JAMEICA_DIR/jameica.jar" ]   || die "$JAMEICA_DIR/jameica.jar fehlt"
[ -f "$HIBISCUS_DIR/hibiscus.jar" ] || die "$HIBISCUS_DIR/hibiscus.jar fehlt"
CP="$JAMEICA_DIR/jameica.jar:$HIBISCUS_DIR/hibiscus.jar"

# add_jars <required|optional> <Ordner> <find-Argumente...>
add_jars() {
  local need="$1" dir="$2" jar found=0
  shift 2
  if [ -d "$dir" ]; then
    while IFS= read -r jar; do CP="$CP:$jar"; found=1; done < <(find "$dir" "$@" -type f | LC_ALL=C sort)
  fi
  if [ "$found" = 0 ] && [ "$need" = required ]; then
    die "keine Jars gefunden in $dir ($*), der Aufbau von Jameica/Hibiscus hat sich geändert?"
  fi
}
add_jars required lib                                  -name '*.jar'
add_jars required "$JAMEICA_DIR/lib/swt"               -name '*.jar'
add_jars required "$JAMEICA_DIR/lib/de_willuhn_ds"     -maxdepth 1 -name '*.jar'
add_jars required "$JAMEICA_DIR/lib/de_willuhn_util"   -maxdepth 1 -name '*.jar'
add_jars optional "$JAMEICA_DIR/lib/javascript"        -maxdepth 1 -name '*.jar'   # in Jameica 2.12 nicht mehr vorhanden
add_jars required "$HIBISCUS_DIR/lib/swtchart"         -maxdepth 1 -name '*.jar'
add_jars required "$HIBISCUS_DIR/lib"                  -maxdepth 1 -name 'obantoo-bin-*.jar'
printf '%s\n' "$CP" > "$OUT_DIR/classpath.txt"

# --- Kompilieren -------------------------------------------------------------
find src -name '*.java' | LC_ALL=C sort > "$OUT_DIR/sources.txt"
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
# Nur Version (am Wurzelelement) und <url> ändern, XML-sicher und mit Prüfung;
# die Quelldatei im Repo bleibt unverändert.
python3 -I torac/patch-plugin-xml.py plugin.xml "$OUT_DIR/dist/$PLUGIN/plugin.xml" "$PLUGIN" "$VERSION" "$PLUGIN_URL"

# --- Weitere Dateien und Bibliotheken ----------------------------------------
cp LICENSE README.md ChangeLog.txt "$OUT_DIR/dist/$PLUGIN/"
mkdir -p "$OUT_DIR/dist/$PLUGIN/lib/javascript"   # wie im Original-ZIP
while IFS= read -r jar; do
  rel="${jar#lib/}"
  mkdir -p "$OUT_DIR/dist/$PLUGIN/lib/$(dirname "$rel")"
  cp "$jar" "$OUT_DIR/dist/$PLUGIN/lib/$rel"
done < <(find lib -name '*.jar' -type f | LC_ALL=C sort)

# --- ZIP (unsigniert) --------------------------------------------------------
(cd "$OUT_DIR/dist" && zip -X -q -r "$OUT_DIR/unsigned/$PLUGIN.zip" "$PLUGIN")
cp "$OUT_DIR/dist/$PLUGIN/plugin.xml" "$OUT_DIR/unsigned/plugin.xml"
printf '%s\n' "$VERSION" > "$OUT_DIR/unsigned/version.txt"

# --- repository.xml aus der Vorlage (nur Prüfung) ----------------------------
sed "s|@PAGES_BASE_URL@|$PAGES_BASE_URL|g" torac/repository.xml > "$OUT_DIR/repository.xml"
python3 -I -c 'import sys, xml.etree.ElementTree as ET; ET.parse(sys.argv[1])' "$OUT_DIR/repository.xml" \
  || die "repository.xml ist nach dem Einsetzen der URL kein wohlgeformtes XML"
! grep -q '@PAGES_BASE_URL@' "$OUT_DIR/repository.xml" || die "Platzhalter in repository.xml nicht ersetzt"

echo "Fertig: $OUT_DIR/unsigned/$PLUGIN.zip"
