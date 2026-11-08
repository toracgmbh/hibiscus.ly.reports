# torac-Repository für Jameica

Dieser Fork (`toracgmbh/hibiscus.ly.reports`) veröffentlicht das Plugin
`hibiscus.ly.reports` mit den eigenen Änderungen der torac GmbH als
Jameica-Plugin-Repository über GitHub Pages. Jameica kann es damit wie das
Original von open4me.de über den Update-Manager installieren und aktualisieren.

Repository-URL (Wurzel der Pages-Seite):

    https://toracgmbh.github.io/hibiscus.ly.reports/

## In Jameica eintragen

Die Beschreibung des Update-Managers steht im Abschnitt "Installation" der
[README des Plugins](../README.md).

1. In Jameica **Datei/Einstellungen** öffnen, Reiter **Updates**.
2. **Neues Repository hinzufügen** wählen und die URL oben eintragen.
3. Beim ersten Zugriff fragt Jameica, ob dem Zertifikat des Repositories
   vertraut werden soll. Den SHA-256-Fingerabdruck mit dem unten angegebenen
   vergleichen und bestätigen.
4. Das Repository öffnen, `hibiscus.ly.reports` auswählen, installieren und
   Jameica neu starten.

Das Repository von open4me.de sollte dabei deaktiviert bleiben oder entfernt
werden, damit nicht beide Quellen dasselbe Plugin anbieten.

## Signatur und Zertifikat

Jameica installiert nur Plugins, deren ZIP signiert ist
(`hibiscus.ly.reports.zip.sha1`, RSA-Signatur über die ZIP, `SHA1withRSA`).
Es prüft sie gegen das Zertifikat, das `repository.xml` angibt.

- Zertifikat (öffentlich): `torac/signing-cert.pem` im Repo, veröffentlicht
  als `signing-cert.pem` im Pages-Wurzelverzeichnis.
- Aussteller und Inhaber: `CN=torac GmbH hibiscus.ly.reports, O=torac GmbH, C=DE`
  (selbstsigniert, RSA 4096, gültig bis 05.11.2036).
- SHA-256-Fingerabdruck:
  `C6:FE:82:23:45:70:B2:81:3C:04:D5:E5:C3:73:29:2D:C4:0D:AF:46:1E:EB:63:02:01:B4:95:51:65:F3:25:0D`
- Der private Schlüssel liegt nur als Repo-Secret `PLUGIN_SIGNING_KEY`
  (Settings, Secrets and variables, Actions). Er steht nicht im Repo und wird
  nur im Signierschritt des Workflows in eine temporäre Datei geschrieben, die
  sofort wieder gelöscht wird. Pull-Requests aus Forks bekommen keine Secrets,
  dort wird nicht signiert und nichts veröffentlicht.
- Nachprüfen auf der Kommandozeile:

      openssl x509 -in signing-cert.pem -pubkey -noout > pub.pem
      openssl dgst -sha1 -verify pub.pem -signature hibiscus.ly.reports.zip.sha1 hibiscus.ly.reports.zip

**Schlüsselverlust oder Verdacht auf Missbrauch:** Neues Schlüsselpaar und
neues Zertifikat erzeugen (RSA 4096, selbstsigniert), den neuen Schlüssel als
Secret `PLUGIN_SIGNING_KEY` setzen, `torac/signing-cert.pem` ersetzen und
den Workflow auf `main` laufen lassen. Die Nutzer müssen dem neuen Zertifikat in
Jameica erneut zustimmen. Der Fingerabdruck in dieser Datei ist dann
anzupassen.

## Wie ein Release entsteht

Der Workflow `.github/workflows/publish-plugin-repository.yml` läuft bei jedem
Push auf `main` und lässt sich über **Actions, Run workflow** von Hand starten.

1. Jameica und Hibiscus werden aus den offiziellen Release-ZIPs von willuhn.de
   geladen (Version und SHA-256 stehen im Kopf des Workflows und werden beim
   Download geprüft). Mit Java 17 wird das Plugin übersetzt (`torac/build-plugin.sh`,
   statt Apache Ant), die MCP-Tests laufen, Jar und ZIP entstehen im Layout des
   Originals.
2. In der veröffentlichten `plugin.xml` (auch in der ZIP) werden Version und
   `<url>` ersetzt. Die `plugin.xml` im Repo bleibt unverändert.
3. Die ZIP wird signiert und die Signatur im Workflow gegen das eingecheckte
   Zertifikat geprüft. Schlägt das fehl, bricht der Lauf ab.
4. `repository.xml`, Zertifikat und Plugin-Ordner werden über GitHub Pages
   veröffentlicht. Der Deploy-Job läuft nur auf `main`.

Pull-Requests und andere Branches bauen nur und legen das Ergebnis als Artefakt
`plugin-repository` zur Kontrolle ab (7 Tage), ohne etwas zu veröffentlichen.

**Versionsnummer:** Jameica wertet nur `major.minor.patch` aus. Zusätzliche
Teile und ein Suffix nach `-` zählen beim Vergleich nicht. Deshalb steckt die
laufende Build-Nummer im Patch-Teil: `<major>.<minor>.<patch * 10000 + Nummer>`.
Aus Upstream 1.3.2 im 7. Lauf wird `1.3.20007`. Das ist neuer als 1.3.2, und
nach einem Upstream-Merge auf 1.3.3 entsteht `1.3.30008` und höher, also wieder
etwas Neueres.

Weil der Patch-Teil so groß ist, wirkt die torac-Version in Jameica immer neuer
als Upstream-Versionen mit gleichem `major.minor` (zum Beispiel 1.3.3 von
open4me.de). Wer beide Repositories eingetragen hat, bekommt daher die
torac-Version angeboten; besser ist es, nur eines der beiden einzutragen.

**Neue Upstream-Version einspielen:** `upstream/main` nach `main` mergen und
pushen. Die Version in `plugin.xml` kommt dann von Upstream, die Build-Nummer
kommt vom Workflow.

**Neue Jameica- oder Hibiscus-Version:** Die willuhn.de-URLs `releases/current`
zeigen immer auf die neueste Version, ältere Versionen sind dort nicht abrufbar.
Sobald eine neue erscheint, scheitert die Prüfsumme im Workflow. Dann URL, Version
und SHA-256 im Kopf des Workflows anpassen (Prüfsumme steht neben dem Download
auf willuhn.de als `.SHA-256`-Datei).
