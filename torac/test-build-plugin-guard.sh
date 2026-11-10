#!/usr/bin/env bash
# Prüft die Schutzprüfung für OUT_DIR in torac/build-plugin.sh: Das Skript darf den
# Ausgabeordner nie löschen, wenn er das Repo, $HOME, "/" oder ein Elternordner
# davon ist (auch über "/", ".", "..", Symlinks), und sonst nur, wenn er leer ist
# oder die Markierungsdatei enthält.
#
# Aufruf:  torac/test-build-plugin-guard.sh
#
# Das Skript arbeitet in einem temporären Ordner (mktemp), in den es das
# build-plugin.sh kopiert, und räumt ihn am Ende auf. Es startet keinen Build:
# build-plugin.sh steigt über BUILD_PLUGIN_STOP_AFTER direkt nach der Pfadprüfung
# ("check") oder nach dem Neuanlegen des Ordners ("prepare") aus. Für "/" und das
# echte $HOME läuft nur der Modus "check", der nie etwas löscht. Alle anderen Fälle
# laufen zusätzlich ohne Ausstiegsmodus (mit einem Pfad, den nur der Test kennt, und
# einem Platzhalter-$HOME im Temp-Ordner); bräche dort die Prüfung nicht ab, würde
# höchstens der Temp-Ordner gelöscht, und eine Datei im Checkout würde fehlen.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/build-plugin.sh"
[ -f "$SRC" ] || { echo "build-plugin.sh nicht gefunden: $SRC" >&2; exit 1; }
REAL_HOME="${HOME:-}"

T="$(mktemp -d "${TMPDIR:-/tmp}/build-plugin-guard.XXXXXX")"
T="$(cd "$T" && pwd -P)"
case "$(basename "$T")" in build-plugin-guard.*) ;; *) echo "unerwarteter Temp-Ordner: $T" >&2; exit 1 ;; esac
cleanup() { [ -n "${T:-}" ] && case "$(basename "$T")" in build-plugin-guard.*) rm -rf "$T" ;; esac; }
trap cleanup EXIT

R="$T/repo"                  # temporärer "Checkout"
FAKE_HOME="$T/home"
mkdir -p "$R/torac" "$R/sub" "$FAKE_HOME"
cp "$SRC" "$R/torac/build-plugin.sh"
echo "wichtig" > "$R/canary.txt"
echo "wichtig" > "$R/sub/canary.txt"
echo "wichtig" > "$T/outside-canary.txt"
echo "wichtig" > "$FAKE_HOME/home-canary.txt"
ln -s "$R" "$T/link-to-repo"
ln -s "$T" "$T/link-to-parent"

FAILS=0
PASSES=0
pass() { PASSES=$((PASSES + 1)); echo "ok     $1"; }
fail() { FAILS=$((FAILS + 1)); echo "FEHLER $1" >&2; }

# run_guard <HOME> <Modus|-> <cwd> <OUT_DIR>: schreibt Ausgabe nach $OUT und setzt $RC
run_guard() {
  local home="$1" mode="$2" cwd="$3" out_dir="$4"
  RC=0
  OUT="$(cd "$cwd" && env HOME="$home" OUT_DIR="$out_dir" \
    JAMEICA_DIR="$T/nicht-vorhanden" HIBISCUS_DIR="$T/nicht-vorhanden" \
    PAGES_BASE_URL=https://example.invalid/test BUILD_NUMBER=1 \
    BUILD_PLUGIN_STOP_AFTER="$([ "$mode" = - ] && echo '' || echo "$mode")" \
    bash "$R/torac/build-plugin.sh" 2>&1)" || RC=$?
}

canaries_ok() {
  [ -f "$R/canary.txt" ] && [ -f "$R/sub/canary.txt" ] && [ -f "$R/torac/build-plugin.sh" ] \
    && [ -f "$T/outside-canary.txt" ] && [ -f "$FAKE_HOME/home-canary.txt" ]
}

# expect_abort <Name> <HOME> <Modus|-> <cwd> <OUT_DIR>
expect_abort() {
  local name="$1"
  run_guard "$2" "$3" "$4" "$5"
  if [ "$RC" -eq 0 ] || grep -Eq 'OUT_DIR (geprüft|angelegt)' <<<"$OUT"; then
    fail "$name: sollte abbrechen, lief aber durch (rc=$RC)"
  elif ! canaries_ok; then
    fail "$name: Dateien im Checkout fehlen nach dem Lauf"
  elif ! grep -q 'build-plugin.sh:' <<<"$OUT"; then
    fail "$name: Abbruch ohne Meldung des Skripts: $OUT"
  else
    pass "$name"
  fi
}

# expect_ok <Name> <HOME> <Modus> <cwd> <OUT_DIR>
expect_ok() {
  local name="$1"
  run_guard "$2" "$3" "$4" "$5"
  if [ "$RC" -ne 0 ]; then
    fail "$name: sollte akzeptiert werden, brach aber ab (rc=$RC): $OUT"
  elif ! canaries_ok; then
    fail "$name: Dateien im Checkout fehlen nach dem Lauf"
  else
    pass "$name"
  fi
}

# Fälle, die abbrechen müssen: einmal mit Ausstiegsmodus, einmal im echten Modus
# (ohne Ausstieg, mit Platzhalter-$HOME), ein Fehler träfe nur den Temp-Ordner.
neg() { # <Name> <cwd> <OUT_DIR>
  expect_abort "$1 [check]" "$FAKE_HOME" check "$2" "$3"
  expect_abort "$1 [echt]"  "$FAKE_HOME" -     "$2" "$3"
}

neg 'Repo mit Schrägstrich am Ende' "$T" "$R/"
neg 'Repo mit /.'                   "$T" "$R/."
neg 'Repo über sub/..'              "$T" "$R/sub/.."
neg 'Repo mit doppeltem Schrägstrich' "$T" "$R//"
neg 'Symlink auf das Repo'          "$T" "$T/link-to-repo"
neg 'Symlink auf das Repo mit /.'   "$T" "$T/link-to-repo/."
neg 'Elternordner des Repos'        "$R" "$T"
neg 'Elternordner über ..'          "$R" ".."
neg 'Elternordner über ../sub/../..' "$R/sub" "../.."
neg 'Symlink auf den Elternordner'  "$T" "$T/link-to-parent"
neg 'relativer Pfad .'              "$R" "."
neg 'relativer Pfad ./'             "$R" "./"
neg 'relativer Pfad .. aus sub'     "$R/sub" ".."
neg 'Platzhalter-HOME'              "$T" "$FAKE_HOME"
neg 'Platzhalter-HOME mit /.'       "$T" "$FAKE_HOME/."
neg 'nicht leerer Ordner ohne Markierung' "$T" "$R/sub"
mkdir -p "$T/fremd"; echo x > "$T/fremd/.versteckt"
neg 'fremder Ordner mit versteckter Datei' "$T" "$T/fremd"
neg 'normale Datei statt Ordner'    "$T" "$T/outside-canary.txt"

# Nur Modus "check" (löscht nie etwas): "/" und das echte $HOME.
expect_abort 'Wurzel / [check]' "$FAKE_HOME" check "$T" "/"
expect_abort 'Wurzel // [check]' "$FAKE_HOME" check "$T" "//"
expect_abort 'Wurzel /. [check]' "$FAKE_HOME" check "$T" "/."
if [ -n "$REAL_HOME" ] && [ "$REAL_HOME" != / ]; then
  expect_abort 'echtes HOME [check]'        "$REAL_HOME" check "$T" "$REAL_HOME"
  expect_abort 'echtes HOME mit /. [check]' "$REAL_HOME" check "$T" "$REAL_HOME/."
  expect_abort 'Elternordner des echten HOME [check]' "$REAL_HOME" check "$T" "$(dirname "$REAL_HOME")"
fi

# Positive Fälle (Modus check: es wird nichts gelöscht).
expect_ok 'neuer Ordner [check]'       "$FAKE_HOME" check "$T" "$T/neu/tief/ausgabe"
mkdir -p "$T/leer"
expect_ok 'leerer Ordner [check]'      "$FAKE_HOME" check "$T" "$T/leer"
mkdir -p "$T/markiert/classes"; echo x > "$T/markiert/classes/A.class"; : > "$T/markiert/.build-plugin-out"
expect_ok 'Ordner mit Markierung [check]' "$FAKE_HOME" check "$T" "$T/markiert"
expect_ok 'Ordner im Repo (build-output/torac) [check]' "$FAKE_HOME" check "$R" "build-output/torac"

# Positive Fälle mit Anlegen (Modus prepare, nur im Temp-Ordner).
expect_ok 'neuer Ordner [prepare]' "$FAKE_HOME" prepare "$T" "$T/neu2/ausgabe"
if [ -f "$T/neu2/ausgabe/.build-plugin-out" ] && [ -d "$T/neu2/ausgabe/classes" ]; then pass 'neuer Ordner: Markierung und Unterordner angelegt'; else fail 'neuer Ordner: Markierung oder Unterordner fehlt'; fi
expect_ok 'Ordner mit Markierung [prepare]' "$FAKE_HOME" prepare "$T" "$T/markiert"
if [ ! -e "$T/markiert/classes/A.class" ] && [ -f "$T/markiert/.build-plugin-out" ]; then pass 'markierter Ordner: alter Inhalt entfernt, Markierung neu angelegt'; else fail 'markierter Ordner: alter Inhalt noch da oder Markierung fehlt'; fi
expect_ok 'leerer Ordner [prepare]' "$FAKE_HOME" prepare "$T" "$T/leer"
if [ -f "$T/leer/.build-plugin-out" ]; then pass 'leerer Ordner: Markierung angelegt'; else fail 'leerer Ordner: Markierung fehlt'; fi
# Zweiter Lauf auf demselben Ordner: jetzt mit Markierung, wird akzeptiert.
expect_ok 'zweiter Lauf auf demselben Ordner [prepare]' "$FAKE_HOME" prepare "$T" "$T/leer"

echo "$PASSES bestanden, $FAILS fehlgeschlagen"
[ "$FAILS" -eq 0 ]
