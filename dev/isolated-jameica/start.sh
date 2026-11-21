#!/bin/bash
# Startet die isolierte Test-Instanz. Aufruf: start.sh server|gui
# Eigenes user.home (die echte ~/.jameica.properties wird weder gelesen noch geschrieben),
# eigenes Arbeitsverzeichnis, Testdaten werden beim ersten Start angelegt.
source "$(dirname "$0")/../env.sh"
source "$(dirname "$0")/iso-env.sh"
MODE="${1:-server}"
[ -d "$RUN_DIR/work" ] || { echo "Erst build.sh ausfuehren." >&2; exit 1; }
ARGS=(-Duser.home="$RUN_DIR/home" -cp "$JAMEICA_CP")
if [ "$MODE" = "server" ]; then
  MAIN_ARGS=(-d -n -f "$RUN_DIR/work" -p "$ISO_MASTER_PW")
else
  [ "$(uname)" = "Darwin" ] && ARGS+=(-XstartOnFirstThread -Xdock:name=Jameica-TEST)
  MAIN_ARGS=(-f "$RUN_DIR/work" -p "$ISO_MASTER_PW")
fi
cd "$JAMEICA_CWD"
exec "$JAVA" "${ARGS[@]}" de.willuhn.jameica.Main "${MAIN_ARGS[@]}" > "$RUN_DIR/jameica-$MODE.log" 2>&1
