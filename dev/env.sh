# Gemeinsame Einstellungen fuer die Skripte unter dev/. Wird per "source" eingebunden.
#
# Pflicht:
#   JAMEICA_DIR   Jameica-Installation. Ohne JAMEICA_CP wird das Layout des Nix-Pakets erwartet
#                 (share/java/jameica.jar und share/jameica-*/<jars>).
#   HIBISCUS_DIR  Hibiscus-Plugin-Ordner (enthaelt hibiscus.jar und lib/), z. B. aus dem
#                 Jameica-Arbeitsverzeichnis. Wird nur gelesen.
# Optional:
#   JAVA_HOME     JDK (17 oder neuer); sonst java/javac/jar aus PATH.
#   JAMEICA_CP    Classpath von Jameica, falls nicht im Nix-Layout.
#   JAMEICA_CWD   Arbeitsverzeichnis beim Start von Jameica (Nix: share/java).

DEV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$DEV_DIR/.." && pwd)"

: "${JAMEICA_DIR:?JAMEICA_DIR setzen (Jameica-Installation)}"
: "${HIBISCUS_DIR:?HIBISCUS_DIR setzen (Hibiscus-Plugin-Ordner mit hibiscus.jar)}"
[ -f "$HIBISCUS_DIR/hibiscus.jar" ] || { echo "Kein hibiscus.jar in $HIBISCUS_DIR" >&2; exit 1; }

BIN="${JAVA_HOME:+$JAVA_HOME/bin/}"
JAVA="${BIN}java"
JAVAC="${BIN}javac"
JAR="${BIN}jar"

if [ -z "${JAMEICA_CP:-}" ]; then
  [ -f "$JAMEICA_DIR/share/java/jameica.jar" ] || {
    echo "JAMEICA_DIR ist kein Nix-Layout; JAMEICA_CP und JAMEICA_CWD setzen" >&2; exit 1; }
  JAMEICA_CP="$JAMEICA_DIR/share/java/jameica.jar"
  for jar in $(LC_ALL=C ls "$JAMEICA_DIR"/share/jameica-*/*.jar); do JAMEICA_CP="$JAMEICA_CP:$jar"; done
  : "${JAMEICA_CWD:=$JAMEICA_DIR/share/java}"
fi
: "${JAMEICA_CWD:?JAMEICA_CWD setzen}"

# Classpath zum Uebersetzen von Plugin und Tests: Jameica, Hibiscus, Jars aus lib/ von Hibiscus und Repo.
compile_cp() {
  local cp="$JAMEICA_CP:$HIBISCUS_DIR/hibiscus.jar" jar
  for jar in $(find "$HIBISCUS_DIR/lib" "$REPO_DIR/lib" -name '*.jar' | LC_ALL=C sort); do cp="$cp:$jar"; done
  echo "$cp"
}
