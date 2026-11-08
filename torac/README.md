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

Jameica installiert aus einem Repository nur Plugins, deren ZIP signiert ist
(`hibiscus.ly.reports.zip.sha1`, RSA-Signatur über die ZIP, `SHA1withRSA`).
Es prüft die Signatur gegen das Zertifikat, das `repository.xml` angibt, und
bricht sonst mit "Installation abgebrochen" ab.

- Zertifikat (öffentlich): `torac/signing-cert.pem` im Repo, veröffentlicht
  als `signing-cert.pem` im Pages-Wurzelverzeichnis.
- Aussteller und Inhaber: `CN=torac GmbH hibiscus.ly.reports, O=torac GmbH, C=DE`
  (selbstsigniert, RSA 4096, gültig bis 05.11.2036).
- SHA-256-Fingerabdruck:
  `3D:9B:64:3C:F4:84:89:FA:D1:7C:98:99:A1:F1:87:9D:EB:AA:1E:3E:1B:B4:1A:DD:26:FB:74:BF:4D:51:F5:80`
  (der Workflow prüft bei jedem Lauf, dass er mit dem Zertifikat im Repo
  übereinstimmt).
- Der private Schlüssel liegt nur als Secret `PLUGIN_SIGNING_KEY` der
  Environment `release` (Settings, Environments, release). Er steht nicht im
  Repo und nicht als Repo-Secret. Die Environment erlaubt nur den Branch `main`
  (benutzerdefinierte Branch-Richtlinie); nur der Job `sign` nutzt sie. Pull-Requests
  und andere Branches kommen nicht an den Schlüssel heran, auch nicht über eine
  geänderte Workflow-Datei: GitHub verweigert der Environment dann den Zugriff.
- Nachprüfen auf der Kommandozeile:

      openssl x509 -noout -fingerprint -sha256 -in signing-cert.pem
      openssl x509 -in signing-cert.pem -pubkey -noout > pub.pem
      openssl dgst -sha1 -verify pub.pem -signature hibiscus.ly.reports.zip.sha1 hibiscus.ly.reports.zip

**Schlüsselverlust oder Verdacht auf Missbrauch:** Neues Schlüsselpaar und
neues Zertifikat erzeugen (RSA 4096, selbstsigniert, zum Beispiel mit
`openssl req -x509 -newkey rsa:4096 -nodes -days 3650 -sha256 -addext basicConstraints=critical,CA:TRUE -subj "/C=DE/O=torac GmbH/CN=torac GmbH hibiscus.ly.reports"`),
den neuen Schlüssel als Secret `PLUGIN_SIGNING_KEY` in der Environment `release`
setzen (`gh secret set PLUGIN_SIGNING_KEY --env release < key.pem`),
`torac/signing-cert.pem` ersetzen, den Fingerabdruck in dieser Datei anpassen und
den Workflow auf `main` laufen lassen. Die Schlüsseldatei danach löschen. Die
Nutzer müssen dem neuen Zertifikat in Jameica erneut zustimmen.

## Wie ein Release entsteht

Der Workflow `.github/workflows/publish-plugin-repository.yml` läuft bei jedem
Push auf `main`, bei Pull-Requests und lässt sich über **Actions, Run workflow**
von Hand starten. Er besteht aus drei Jobs mit je minimalen Rechten:

1. **`build`** (alle Auslöser, keine Secrets, keine Environment):
   Jameica und Hibiscus werden aus den offiziellen Release-ZIPs von willuhn.de
   geladen (Version und SHA-256 stehen im Kopf des Workflows, die Prüfsumme wird
   bei jedem Lauf geprüft, auch bei einem Treffer im Cache; der Cache-Schlüssel ist
   die SHA-256). Mit Java 17 wird das Plugin übersetzt (`torac/build-plugin.sh`,
   statt Apache Ant) und getestet. Der Classpath entspricht `compile.path` in
   `build/build.xml` und ist für Übersetzen und Tests derselbe: Jars aus `lib/` des
   Repos, dazu von Jameica `swt`, `de_willuhn_ds`, `de_willuhn_util` und von
   Hibiscus nur `swtchart` und `obantoo-bin-*.jar`, sortiert mit `LC_ALL=C`. Es
   wird also gegen dieselben Bibliotheken getestet, die in der ZIP liegen. Jar und
   **unsignierte** ZIP entstehen im Layout des Originals. In der `plugin.xml`
   (auch in der ZIP) werden Version und `<url>` per Python XML-sicher ersetzt
   (`torac/patch-plugin-xml.py`); die `plugin.xml` im Repo bleibt unverändert.
   Ein Selbsttest signiert die ZIP mit einem Wegwerf-Schlüssel, der im Job entsteht,
   und prüft die Signatur mit `openssl dgst -sha1 -verify` (inklusive Gegenprobe
   mit veränderter ZIP). Der Produktionsschlüssel kommt dabei nicht vor, nichts
   davon wird veröffentlicht. Zum Schluss legt der Job die ZIP als Artefakt ab.
2. **`sign`** (nur `push` oder `workflow_dispatch` auf `main`, Environment `release`):
   nimmt die ZIP aus `build` (kein neuer Build, keine Ausführung von Repo-Code),
   prüft Prüfsumme und Inhalt, signiert sie in einem einzigen Schritt mit dem
   Schlüssel (Datei im Runner-Temp mit Rechten nur für den Besitzer, danach
   gelöscht), prüft die Signatur gegen `torac/signing-cert.pem` und stellt
   `repository.xml`, Zertifikat und Plugin-Ordner für Pages zusammen. Schlägt
   etwas fehl, bricht der Lauf ab. Der Job bricht auch ab, wenn es nicht der erste
   Versuch eines Laufs ist (`github.run_attempt != 1`): Ein Re-run baut eine andere
   ZIP mit derselben Versionsnummer. Dann einen neuen Lauf über
   **Run workflow** auf `main` starten.
3. **`deploy`** (nur `main`, Environment `github-pages`): `actions/deploy-pages`.

**Läufe nacheinander (Concurrency):** Der Gruppenschlüssel gilt für den ganzen
Workflow-Lauf, nicht je Job. Läufe auf `main` (Push und `workflow_dispatch`)
liegen in der gemeinsamen Gruppe `plugin-repository-publish` und laufen strikt
nacheinander in der Reihenfolge ihres Starts. Ein laufender Lauf wird nie
abgebrochen. Wartet schon ein Lauf, ersetzt ihn ein neuerer (der neueste Stand
gewinnt, der ersetzte Lauf erscheint als abgebrochen). Damit signiert und
veröffentlicht kein älterer Lauf nach einem neueren. Pull-Requests und andere
Branches haben je Ref eine eigene Gruppe; ein neuer Push oder Lauf bricht den
laufenden ab, und sie blockieren `main` nicht.

**Schutz vor Rückschritten:** Vor dem Signieren holt `sign` die aktuell
veröffentlichte `hibiscus.ly.reports/plugin.xml` von Pages (404 heißt: noch nichts
veröffentlicht) und bricht ab, wenn deren Version gleich oder größer ist als die
des Laufs (numerischer Vergleich je Komponente von `major.minor.patch`). Dann einen
neuen Lauf über **Run workflow** auf `main` starten.

**Pull-Requests und andere Branches** laufen nur durch `build`; `sign` und
`deploy` werden übersprungen. Das Ergebnis liegt 7 Tage als Artefakt
`plugin-zip-unsigned-<PR-Nummer>` (bei `workflow_dispatch` heißt es
`plugin-zip-unsigned`) vor: `hibiscus.ly.reports.zip`, `plugin.xml`, `version.txt`.
Die ZIP ist **unsigniert** und lässt sich nicht über ein Repository installieren
(Jameica verlangt dafür Signatur und Zertifikat). Sie dient zum manuellen Testen:

- In Jameica den Dialog **Plugin installieren** ("ZIP-Datei mit dem zu
  installierenden Plugin auswählen") mit der ZIP benutzen. Er liest nur das
  Manifest und prüft keine Signatur, lehnt aber ein schon installiertes Plugin ab
  ("Das Plugin ist bereits installiert.").
- Für ein Update auf einem bestehenden Stand stattdessen das Jar
  (`hibiscus.ly.reports.jar`) im Plugin-Ordner ersetzen und Jameica neu starten,
  oder das Plugin vorher deinstallieren.

**Versionsnummer:** Jameica wertet nur `major.minor.patch` aus. Zusätzliche
Teile und ein Suffix nach `-` zählen beim Vergleich nicht. Deshalb steckt die
laufende Build-Nummer (`github.run_number`) im Patch-Teil:
`<major>.<minor>.<patch * 10000 + Nummer>`. Aus Upstream 1.3.2 im 7. Lauf wird
`1.3.20007`. Das ist neuer als 1.3.2, und nach einem Upstream-Merge auf 1.3.3
entsteht `1.3.30008` und höher, also wieder etwas Neueres.

Weil der Patch-Teil so groß ist, wirkt die torac-Version in Jameica immer neuer
als Upstream-Versionen mit gleichem `major.minor` (zum Beispiel 1.3.3 von
open4me.de). Wer beide Repositories eingetragen hat, bekommt daher die
torac-Version angeboten; besser ist es, nur eines der beiden einzutragen.

**Neue Upstream-Version einspielen:** `upstream/main` nach `main` mergen und
pushen. Die Version in `plugin.xml` kommt dann von Upstream, die Build-Nummer
kommt vom Workflow.

**Neue Jameica- oder Hibiscus-Version:** Die willuhn.de-URLs `releases/current`
zeigen immer auf die neueste Version, ältere Versionen sind dort nicht abrufbar
(und werden hier auch nicht archiviert). Sobald eine neue erscheint, scheitert die
Prüfsumme im Workflow, solange der Cache nicht greift. Dann URL und SHA-256 im
Kopf des Workflows anpassen (die Prüfsumme steht neben dem Download auf
willuhn.de als `.SHA-256`-Datei).
