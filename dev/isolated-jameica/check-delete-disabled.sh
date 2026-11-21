#!/bin/bash
# Prueft hibiscus_transactions_delete bei ausgeschalteter Option "Umsaetze loeschen": Tool nicht
# angeboten, Aufruf abgelehnt. Vorher die Option in der Test-Instanz abschalten (GUI) oder vor dem Start
# deleteEnabled=false in run/work/cfg/de.open4me.hibiscus.reports.mcp.McpSettings.properties setzen.
BASE="$(cd "$(dirname "$0")" && pwd)"
source "$BASE/iso-env.sh"
for i in $(seq 1 40); do
  curl -s --max-time 2 -o /dev/null "$ISO_URL" && break
  sleep 2
done
ok() { if [ "$1" = "true" ]; then echo "PASS $2"; else echo "FAIL $2"; echo "     got: $3" | cut -c1-600; fi; }
TOOLS=$(bash "$BASE/mcp.sh" '{"jsonrpc":"2.0","id":1,"method":"tools/list"}')
ok "$(jq '([.result.tools[].name] | index("hibiscus_transactions_delete")) == null and ([.result.tools[].name] | index("hibiscus_transactions_list")) != null' <<<"$TOOLS")" "setting off: delete tool not listed" "$TOOLS"
CALL=$(bash "$BASE/mcp.sh" '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"hibiscus_transactions_delete","arguments":{"ids":["1"],"dryRun":true}}}')
ok "$(jq '.error.data | contains("Umsaetze loeschen ist deaktiviert")' <<<"$CALL")" "setting off: call refused" "$CALL"
