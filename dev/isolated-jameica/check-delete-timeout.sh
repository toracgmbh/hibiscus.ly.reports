#!/bin/bash
# Nur mit der GUI-Instanz (start.sh gui), ohne Klicks: Ein zweiter Loeschaufruf bei offenem Dialog muss
# sofort mit confirmError zurueckkommen; der offene Dialog muss sich nach etwa 50 s selbst schliessen und
# "nein" melden. Den Dialog dabei NICHT bestaetigen. Umsaetze 4 und 5 muessen danach noch da sein.
BASE="$(cd "$(dirname "$0")" && pwd)"
source "$BASE/iso-env.sh"
OUT="$RUN_DIR/out"; mkdir -p "$OUT"
t0=$(date +%s)
bash "$BASE/delete.sh" 4 > "$OUT/first.json" 2>&1 &
FIRST=$!
sleep 4
t1=$(date +%s)
bash "$BASE/delete.sh" 5 > "$OUT/second.json" 2>&1
t2=$(date +%s)
echo "second call returned after $((t2 - t1)) s:"
jq -c '{confirmed, confirmError, status: [.results[].status], counts}' "$OUT/second.json"
wait $FIRST
t3=$(date +%s)
echo "first call returned after $((t3 - t0)) s:"
jq -c '{confirmed, confirmError, status: [.results[].status], counts}' "$OUT/first.json"
echo "ids 4 and 5 still present:"
bash "$BASE/ids.sh" | awk -F'\t' '$1==4 || $1==5 {print "  " $1 " " $5}'
