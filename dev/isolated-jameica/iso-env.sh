# Einstellungen der isolierten Test-Instanz. Wird per "source" eingebunden.
# Alle Werte sind Testwerte; keiner gehoert zu einer echten Installation.
ISO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_DIR="${ISO_RUN_DIR:-$ISO_DIR/run}"     # Laufzeitdaten (Arbeitsverzeichnis, Home, Logs); in .gitignore
ISO_PORT="${ISO_PORT:-37691}"              # eigener MCP-Port, damit eine laufende echte Instanz unberuehrt bleibt
ISO_TOKEN="isolated-test-token-4711"       # MCP-Passwort der Test-Instanz
ISO_MASTER_PW="isolated-master-4711"       # Jameica-Masterpasswort der Test-Instanz
ISO_URL="http://127.0.0.1:$ISO_PORT/mcp"
