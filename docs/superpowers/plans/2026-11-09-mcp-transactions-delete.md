# MCP Transactions Delete Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expose transaction IDs over MCP and add an opt-in, Hibiscus-confirmed `hibiscus_transactions_delete` tool.

**Architecture:** `McpJsonRpcHandler` gets an injected `TransactionDeleter` (lookup, confirm, delete) and a `BooleanSupplier deleteEnabled`, mirroring how `SepaTransferDraftWriter` and `writeEnabled` are injected today. All per-ID logic lives in the handler and is unit-tested with a fake; the Hibiscus implementation (DB access + SWT confirmation dialog) is thin and tested manually. A new `McpSettings` flag with a checkbox in `McpSettingsDialog` controls visibility.

**Tech Stack:** Java 17, Jameica/Hibiscus plugin API, SWT, Jackson. Tests are plain classes with a static `run()` registered in `test/de/open4me/hibiscus/reports/CoreTests.java`, using `check(...)`/`checkEquals(...)` helpers.

**Spec:** `docs/superpowers/specs/2026-11-09-mcp-transactions-delete-design.md`

**Running tests:** `$RUN_TESTS <fully.qualified.TestClass> ...` compiles `src` + `test` and calls each class's static `run()`; it prints `PASS <class>` per class and exits non-zero on failure. The executor is given the concrete runner path for this machine. With Apache Ant and Jameica/Hibiscus checkouts at `../jameica` / `../hibiscus`, `ant -f build/build.xml test` runs the whole suite; note it currently stops early in `DynamicReportTests` because `reports/Umsatzkategorien.html` is not in the repo (pre-existing, unrelated). Baseline: `McpJsonRpcHandlerTests`, `McpSettingsActionTests`, `DuplicateDetectorTests` pass.

## Global Constraints

- Repository is public: tests, docs, examples, commit messages use invented values only ("Rechnung 4711", "Beispiel GmbH", IBAN `DE02120300000000202051` as already used in tests). Never real account data.
- Tool names/titles/descriptions in the existing German ASCII-transliterated style ("Umsaetze loeschen"); README/ChangeLog in normal German with umlauts, as today.
- Deletion is local only; nothing is sent to the bank.
- Delete setting defaults to `false`.
- Only an explicit "Loeschen" click in the Hibiscus dialog deletes; decline, close, timeout, headless mode, or any confirm failure deletes nothing.
- One confirmation dialog per call, all-or-nothing for that call.
- IDs are strings in input and output; malformed IDs count as `unknown`.
- When the setting is off, `hibiscus_transactions_delete` is absent from `tools/list` and a call is refused with an error containing "Umsaetze loeschen".
- Statuses exactly: `wouldDelete`, `deleted`, `unknown`, `notConfirmed`, `error`.
- Confirmation timeout: 2 minutes (Claude's call within the spec's "a few minutes"; short enough that most MCP clients are still waiting for the answer).

## Review Focus

- **Confirm step throws** (Jameica in server mode without GUI, SWT error): every found ID becomes `notConfirmed`, result carries `confirmError`, nothing is deleted. → test `deleteConfirmFailureDeletesNothing` in Task 2.
- **IDs sent as JSON numbers** (`"ids":[4711]`) instead of strings: accepted as `"4711"`. → test `deleteAcceptsNumericIds` in Task 2.
- **Setting toggled while the server runs:** `tools/list` and `tools/call` read the supplier on every request, no restart. → test `deleteToolFollowsSettingWithoutRestart` in Task 2.
- **Large batches** (dozens of duplicates in one call): the dialog lists every transaction and stays usable (scrollable, fixed size). → test `confirmationTextListsEveryTransaction` in Task 3 with 60 entries.
- **Lookup itself fails for one ID** (DB error, not "not found"): that ID gets `error`, the rest continue. → test `deleteLookupFailureOnlyAffectsThatId` in Task 2.

---

### Task 1: `id` in `hibiscus_transactions_list`

**Files:**
- Modify: `src/de/open4me/hibiscus/reports/mcp/McpJsonRpcHandler.java` (`transaction(ReportTransaction)` ~line 598; `hibiscus_transactions_list` tool description ~line 186)
- Test: `test/de/open4me/hibiscus/reports/mcp/McpJsonRpcHandlerTests.java`
- Modify: `README_MCP.md` (section "Umsätze laden")

**Interfaces:**
- Produces: every transaction object in `hibiscus_transactions_list` output has `"id": "<string>"` taken from `ReportTransaction.getId()`.

- [ ] **Step 1: Write the failing test** `listsTransactionIds`, registered in `run()` after `listsTransactionsWithCategoryFilter()`. The existing `FakeTransactionProvider` returns transactions with IDs `"13"`, `"14"`, `"20"` in that order; call `hibiscus_transactions_list` without filters and assert, reaching the array the same way `listsTransactionsWithFilters` does:

```java
check(transactions.get(0).path("id").isTextual(), "transaction id is string");
checkEquals("13", transactions.get(0).path("id").asText(), "transaction id");
checkEquals("20", transactions.get(2).path("id").asText(), "last transaction id");
```

- [ ] **Step 2: Run** `$RUN_TESTS de.open4me.hibiscus.reports.mcp.McpJsonRpcHandlerTests` → FAIL on "transaction id".
- [ ] **Step 3: Implement:** `node.put("id", transaction.getId())` as the first field in `transaction(...)`. Extend the tool description to: `"Listet Umsaetze mit Zeitraum-, Konto- und Limit-Filtern. Das Feld id ist die Hibiscus-Umsatz-ID."`
- [ ] **Step 4: Run** the same command → `PASS ...McpJsonRpcHandlerTests`.
- [ ] **Step 5: README:** in "Umsätze laden" add one sentence: each transaction carries `id`, the Hibiscus transaction ID, which `hibiscus_transactions_delete` takes (if enabled).
- [ ] **Step 6: Commit** `MCP: Umsatz-ID in hibiscus_transactions_list ausgeben (#4)`.

---

### Task 2: `TransactionDeleter` contract and the delete tool in the handler

**Files:**
- Create: `src/de/open4me/hibiscus/reports/mcp/TransactionDeleter.java`
- Modify: `src/de/open4me/hibiscus/reports/mcp/McpJsonRpcHandler.java` (fields, constructors, `toolsList()`, `toolsCall()`, new `deleteTransactions(JsonNode)`, new `transactionsDeleteSchema()`)
- Test: `test/de/open4me/hibiscus/reports/mcp/McpJsonRpcHandlerTests.java`

**Interfaces:**
- Produces (exact):

```java
package de.open4me.hibiscus.reports.mcp;

public interface TransactionDeleter
{
    /** Empty if the ID is malformed or no such transaction exists. Throws only on real lookup failures. */
    java.util.Optional<Candidate> find(String id) throws Exception;

    /** Blocks until the user answers. true only on explicit confirmation. */
    boolean confirm(java.util.List<Candidate> candidates, int unknownCount) throws Exception;

    void delete(String id) throws Exception;

    record Candidate(String id, String accountId, String accountName, java.time.LocalDate date, double amount,
                     String counterpartyName, String purpose, java.util.List<String> links)
    {
    }
}
```

- Produces: new package-private constructor
  `McpJsonRpcHandler(ReportTemplateContextFactory, ReportTransactionProvider, ReportCategoryProvider, SepaTransferDraftWriter, McpAccountSynchronizer, BooleanSupplier writeEnabled, TransactionDeleter transactionDeleter, BooleanSupplier deleteEnabled)`.
  The existing 5- and 6-argument constructors delegate to it with `null, () -> false`. The public 3-argument constructor is rewired in Task 4, not here.
- Tool: name `hibiscus_transactions_delete`, title `Umsaetze loeschen`, description `"Loescht Umsaetze anhand ihrer IDs aus der lokalen Hibiscus-Datenbank. Bei der Bank aendert sich nichts. Nicht umkehrbar. Zuerst mit dryRun=true pruefen; jede echte Loeschung muss der Benutzer in Hibiscus bestaetigen."`
- Schema: `ids` array of string, `minItems: 1`, title `Umsatz-IDs`, description `"IDs aus hibiscus_transactions_list (Feld id)."`; `dryRun` boolean, title `Probelauf`, description `"Wenn true, wird nur aufgelistet, was geloescht wuerde. Kein Dialog, keine Aenderung."`; `required: ["ids"]`. Use the existing `property`/`arrayProperty` helpers.
- Output shape (structuredContent):
  - `dryRun` (boolean)
  - `confirmed` (boolean): only when `dryRun` is false and at least one ID was found
  - `confirmError` (string): only when `confirm` threw
  - `results`: one entry per distinct input ID, in input order. Each entry has `id` and `status`. Found transactions add `transaction` `{kontoId, kontoName, datum, betrag, gegenkontoName, zweck}` and `links` (array of strings). An `error` entry adds `message`.
  - `counts`: `{wouldDelete, deleted, unknown, notConfirmed, error}`, all five keys always present.
- Errors (whole call fails, deleter untouched):
  - setting off: `IllegalStateException("Umsaetze loeschen ist deaktiviert.")`
  - `ids` missing, not an array, or empty: `IllegalArgumentException("ids: mindestens eine Umsatz-ID angeben.")`
  - deleter is `null` while the setting is on: `IllegalStateException("Kein Loeschdienst fuer Umsaetze verfuegbar.")`

**Processing order** (this is the algorithm the tests pin):
1. Collect the IDs with `asText().trim()` into a `LinkedHashSet`, so duplicates collapse and numbers become strings.
2. Call `find` for each ID. Empty → `unknown`. Exception → `error` with the exception message. Otherwise it's a candidate.
3. If `dryRun` is true, candidates become `wouldDelete`. No `confirm` call.
4. Otherwise, if there are candidates, call `confirm(candidates, unknownCount)` exactly once.
   - `false` → all candidates become `notConfirmed`.
   - Exception → all candidates become `notConfirmed`, and `confirmError` holds the message.
   - `true` → call `delete(id)` per candidate. Success → `deleted`. Exception → `error` with the message, and the loop continues.

- [ ] **Step 1: Write the fake and the helper** in the test file:
  - `FakeTransactionDeleter implements TransactionDeleter` with
    - `Map<String, Candidate> existing`
    - `Set<String> failingLookups`, `Set<String> failingDeletes`
    - `Boolean answer` (`null` means `confirm` throws `IllegalStateException("kein GUI")`)
    - recorded `List<List<Candidate>> confirmCalls`, `List<Integer> unknownCounts`, `List<String> deleted`
  - Helper `handler(ReportTransactionProvider, TransactionDeleter, BooleanSupplier deleteEnabled)` calling the new 8-argument constructor with `new FakeTransferDraftWriter()`, the same account synchronizer the existing 6-argument helper uses, and `() -> false` for writes.
  - Candidates use invented data: account `"7"` / `"Beispielkonto"`, `LocalDate.of(2025, 1, 14)`, `-42.0`, `"Beispiel GmbH"`, `"Rechnung 4711"`. Links: `["kategorie: Versicherung"]` for ID `"1"`, empty for the others.

- [ ] **Step 2: Write the failing tests** and register them in `run()`:
  - `hidesDeleteToolWhenDisabled`: `tools/list` with the setting off does not contain `hibiscus_transactions_delete`.
  - `listsDeleteToolWhenEnabled`: it does contain it, `schemaProperties(tools, "hibiscus_transactions_delete").path("ids").path("type")` is `"array"`, and the `dryRun` type is `"boolean"`.
  - `deleteToolFollowsSettingWithoutRestart`: one handler with an `AtomicBoolean`-backed supplier. Off → absent from the list, and a call is an error. Set it on → present in the list, and the call succeeds.
  - `rejectsDeleteWhenDisabled`: `response.has("error")`, `error.data` contains `"Umsaetze loeschen"`, and the fake recorded no calls.
  - `rejectsDeleteWithoutIds`: both `{}` and `{"ids":[]}` produce an error whose data contains `"mindestens eine Umsatz-ID"`, with no fake calls.
  - `deleteDryRunReportsWithoutConfirmOrDelete`: existing `1` and `2`, ids `["1","2","x"]`, `dryRun: true`.
    - statuses: `wouldDelete`, `wouldDelete`, `unknown`
    - `confirmCalls` is empty and `deleted` is empty
    - `confirmed` is absent
    - `counts.wouldDelete == 2` and `counts.unknown == 1`
    - entry `1` has `links[0] == "kategorie: Versicherung"` and `transaction.gegenkontoName == "Beispiel GmbH"`
  - `deletesConfirmedTransactionsPerId`: existing `1` and `2`, `failingDeletes = {"2"}`, `answer = true`, ids `["1","2","1","x"]`.
    - `results` has 3 entries in order `1`, `2`, `x`
    - statuses: `deleted`, `error` (with `message`), `unknown`
    - `confirmCalls.size() == 1` with 2 candidates, and `unknownCounts.get(0) == 1`
    - `deleted == ["1"]`, and `confirmed` is true
    - counts: `deleted 1`, `error 1`, `unknown 1`, `notConfirmed 0`, `wouldDelete 0`
  - `declinedDeleteDeletesNothing`: `answer = false` → found IDs are `notConfirmed`, unknown IDs stay `unknown`, `deleted` is empty, and `confirmed` is false.
  - `deleteConfirmFailureDeletesNothing`: `answer = null` → found IDs are `notConfirmed`, `confirmError` contains `"kein GUI"`, and `deleted` is empty.
  - `deleteWithOnlyUnknownIdsSkipsConfirmation`: ids `["x","y"]` → both `unknown`, `confirmCalls` is empty, and `confirmed` is absent.
  - `deleteLookupFailureOnlyAffectsThatId`: `failingLookups = {"3"}`, existing `1`, `answer = true`, ids `["3","1"]` → `3` is `error`, `1` is `deleted`.
  - `deleteAcceptsNumericIds`: `"ids":[1]` with existing `"1"` → `results[0].id == "1"` and the status is `deleted`.

- [ ] **Step 3: Run** `$RUN_TESTS de.open4me.hibiscus.reports.mcp.McpJsonRpcHandlerTests`. It must fail to compile, because `TransactionDeleter` and the constructor are missing.
- [ ] **Step 4: Implement:** create `TransactionDeleter` as above. In `McpJsonRpcHandler`, add the fields, the 8-argument constructor and the constructor delegation. In `toolsList()`, add the tool only when `deleteEnabled.getAsBoolean()`, placed after `hibiscus_transactions_list`. Add the `toolsCall` case `"hibiscus_transactions_delete" -> toolResult(deleteTransactions(arguments), "Umsaetze verarbeitet.")`. Write `deleteTransactions` following the processing order above.
- [ ] **Step 5: Run** the same command and confirm `PASS ...McpJsonRpcHandlerTests`, with all old tests still passing.
- [ ] **Step 6: Commit** with the message `MCP: Tool hibiscus_transactions_delete (#4)`.

---

### Task 3: Hibiscus implementation and confirmation dialog

**Files:**
- Create: `src/de/open4me/hibiscus/reports/mcp/TransactionDeleteConfirmation.java` (pure text, no SWT)
- Create: `src/de/open4me/hibiscus/reports/mcp/McpTransactionDeleteDialog.java` (SWT)
- Create: `src/de/open4me/hibiscus/reports/mcp/HibiscusTransactionDeleter.java`
- Test: `test/de/open4me/hibiscus/reports/mcp/TransactionDeleteConfirmationTests.java`; register it in `CoreTests` after `McpJsonRpcHandlerTests.run()`.

**Interfaces:**
- Consumes: `TransactionDeleter`, `TransactionDeleter.Candidate` (Task 2).
- Produces:
  - `final class TransactionDeleteConfirmation { static String text(List<TransactionDeleter.Candidate> candidates, int unknownCount) }`
  - `final class McpTransactionDeleteDialog extends AbstractDialog<Boolean>`, with `static boolean confirm(String text, java.time.Duration timeout) throws Exception`
  - `public final class HibiscusTransactionDeleter implements TransactionDeleter`, with a public no-argument constructor that must not touch Hibiscus or SWT (`McpOAuthHttpTests` constructs handlers without Hibiscus), and `static final java.time.Duration CONFIRM_TIMEOUT = java.time.Duration.ofMinutes(2)`

**Text content.** Fixed copy, German, with umlauts allowed, because this is UI and not a tool name:
- First line: `"Ein MCP-Client möchte {n} Umsatz/Umsätze löschen:"`, singular for 1.
- One line per candidate: `dd.MM.yyyy  <betrag with German formatting, 2 decimals> EUR  <gegenkontoName>  –  <purpose's first line>  (<accountName>)`. Append `  [<links joined by ", ">]` when links are not empty.
- If `unknownCount > 0`: `"{k} unbekannte ID(s) werden übersprungen."`
- Last line: `"Die Umsätze werden nur lokal in Hibiscus gelöscht, bei der Bank ändert sich nichts. Das Löschen kann nicht rückgängig gemacht werden."`

- [ ] **Step 1: Write the failing tests** in `TransactionDeleteConfirmationTests`:
  - `confirmationTextShowsTransaction`: one candidate (invented data from Task 2) with links `["kategorie: Versicherung"]`. The text contains each of:
    - `"Ein MCP-Client möchte 1 Umsatz löschen"`
    - `"14.01.2025"`
    - `"-42,00 EUR"`
    - `"Beispiel GmbH"`
    - `"Rechnung 4711"`
    - `"Beispielkonto"`
    - `"[kategorie: Versicherung]"`
    - `"bei der Bank ändert sich nichts"`
  - `confirmationTextMentionsUnknownIds`: `unknownCount = 2` → contains `"2 unbekannte ID(s)"`. With `0`, it contains no `"unbekannte"`.
  - `confirmationTextListsEveryTransaction`: 60 candidates with distinct purposes `"Rechnung 1"`…`"Rechnung 60"` → all 60 purposes appear, and the header says `"60 Umsätze"`.
- [ ] **Step 2: Run** `$RUN_TESTS de.open4me.hibiscus.reports.mcp.TransactionDeleteConfirmationTests` and confirm it fails to compile.
- [ ] **Step 3: Implement `TransactionDeleteConfirmation.text`.** Use a fixed `Locale.GERMANY` `DecimalFormat("#,##0.00")` for the amount.
- [ ] **Step 4: Run** the same command and confirm `PASS`.
- [ ] **Step 5: Implement `McpTransactionDeleteDialog`.**
  - Title: `"Umsätze löschen (MCP)"`.
  - Body: a read-only, multi-line, scrollable `Text` with the confirmation text, fixed size of roughly 700×400.
  - Buttons: "Löschen" (sets the result to true, then closes) and "Abbrechen", which is the default button.
  - `onEscape` cancels.
  - `confirm(text, timeout)`:
    - If `Application.inServerMode()`, throw `IllegalStateException("Hibiscus läuft ohne Oberfläche; Löschen kann nicht bestätigt werden.")`.
    - Otherwise run on `GUI.getDisplay().syncExec`: create the dialog, call `display.timerExec((int) timeout.toMillis(), dialog::close)`, then `open()`.
    - Return true only when `open()` returned `Boolean.TRUE`. Return false when it was closed by the timer, by the window X, or on `OperationCanceledException`.
  - Manual check only: no SWT in unit tests.
- [ ] **Step 6: Implement `HibiscusTransactionDeleter`.**
  - `find(id)`: if `id` doesn't match `\d+`, return empty. Otherwise call `Settings.getDBService().createObject(Umsatz.class, id)`; `de.willuhn.datasource.rmi.ObjectNotFoundException` → empty. Build the `Candidate`:
    - account: `getKonto().getID()`, plus the name, using the same name fallback as `DuplicateTransactionRepository.accountName`
    - date: `getDatum()` → `LocalDate`
    - `getBetrag()`, `getGegenkontoName()`, and `getZweck()` as the purpose
    - links: `"kategorie: " + getUmsatzTyp().getName()` if set, `"kommentar"` if `getKommentar()` is not blank, `"geprueft"` if `hasFlag(Umsatz.FLAG_CHECKED)`
  - `confirm`: `McpTransactionDeleteDialog.confirm(TransactionDeleteConfirmation.text(candidates, unknownCount), CONFIRM_TIMEOUT)`.
  - `delete(id)`: `Settings.getDBService().createObject(Umsatz.class, id).delete()`. This is the same call the GUI duplicate view makes via `DuplicateTransactionRepository.loadTransaction(id).delete()`. Don't extract shared code.
  - This version of Hibiscus has no split bookings (`Umsatz` has no parent/child API), so there's nothing to handle there.
- [ ] **Step 7: Run** `$RUN_TESTS de.open4me.hibiscus.reports.mcp.TransactionDeleteConfirmationTests de.open4me.hibiscus.reports.mcp.McpJsonRpcHandlerTests de.open4me.hibiscus.reports.mcp.McpOAuthHttpTests` and confirm all three `PASS`. This also verifies that everything compiles.
- [ ] **Step 8: Commit** with the message `MCP: Hibiscus-Löschdienst mit Bestätigungsdialog (#4)`.

---

### Task 4: Setting, wiring, docs

**Files:**
- Modify: `src/de/open4me/hibiscus/reports/mcp/McpSettings.java`
- Modify: `src/de/open4me/hibiscus/reports/ui/McpSettingsDialog.java` (checkbox, `Result` record, local tab text)
- Modify: `src/de/open4me/hibiscus/reports/ui/McpSettingsAction.java` (save + restore)
- Modify: `src/de/open4me/hibiscus/reports/mcp/McpJsonRpcHandler.java` (public 3-arg constructor wiring)
- Modify: `test/de/open4me/hibiscus/reports/ui/McpSettingsActionTests.java` only if it constructs `McpSettingsDialog.Result`. Today it does not; check.
- Modify: `README_MCP.md`, `ChangeLog.txt`

**Interfaces:**
- Consumes: `HibiscusTransactionDeleter` (Task 3), 8-arg constructor (Task 2).
- Produces: `McpSettings.isDeleteEnabled()` / `setDeleteEnabled(boolean)`, key `"deleteEnabled"`, default `false`. `McpSettingsDialog.Result` gains `boolean deleteEnabled` directly after `writeEnabled`.

- [ ] **Step 1: Settings.** Add `isDeleteEnabled`/`setDeleteEnabled` next to `isWriteEnabled`, using the same pattern.
- [ ] **Step 2: Dialog.**
  - Add a `CheckboxInput deleteEnabled` named `"Umsaetze loeschen"`, initialised from `McpSettings.isDeleteEnabled()`. Put it in the local tab directly after `writeEnabled`, and pass it into `Result`.
  - Extend the local-tab explanatory text with: `"Die Option für Umsätze erlaubt Clients, Umsätze lokal zu löschen; jede Löschung muss hier in Hibiscus bestätigt werden. Nach dem Umschalten müssen sich Clients neu verbinden, um das Tool zu sehen."`
- [ ] **Step 3: Action.**
  - Save `result.deleteEnabled()` right after `setWriteEnabled`.
  - Capture `previousDeleteEnabled`, and restore it in `restorePreviousSettings`, adding a parameter after `writeEnabled`.
- [ ] **Step 4: Wiring.** Make the public 3-argument constructor call the 8-argument one with:
  - `new HibiscusSepaTransferDraftWriter()`
  - `new HibiscusMcpAccountSynchronizer()`
  - `McpSettings::isWriteEnabled`
  - `new HibiscusTransactionDeleter()`
  - `McpSettings::isDeleteEnabled`

  `McpServerManager` needs no change.
- [ ] **Step 5: Run** `$RUN_TESTS de.open4me.hibiscus.reports.mcp.McpJsonRpcHandlerTests de.open4me.hibiscus.reports.mcp.TransactionDeleteConfirmationTests de.open4me.hibiscus.reports.mcp.McpOAuthHttpTests de.open4me.hibiscus.reports.ui.McpSettingsActionTests` and confirm all four `PASS`.
- [ ] **Step 6: Docs.**
  - In `README_MCP.md`:
    - In the local-share setup list, after "Überweisungen anlegen", add the option **Umsätze löschen** (off by default; it shows the tool, and every deletion is confirmed in Hibiscus; clients need to reconnect after toggling it).
    - Add a row to the "Verfügbare Tools" table: `hibiscus_transactions_delete` | Umsätze lokal löschen (nur wenn aktiviert).
    - Add a new section "## Umsätze löschen" after "Umsätze laden". It covers the input (`ids`, `dryRun`), the dialog with its 2-minute timeout, the statuses, the `links` hint, that nothing happens at the bank, and that remote use without someone at the machine deletes nothing. Example values must be invented.
  - In `ChangeLog.txt`, add a new top block with no version number:
    - `\t[Feature] MCP: Umsatz-ID in hibiscus_transactions_list`
    - `\t[Feature] MCP: Umsätze löschen (optional, mit Bestätigung in Hibiscus)`
- [ ] **Step 7: Manual check in Jameica** (by the user; record the outcome in the PR):
  1. With the setting off, `tools/list` has no delete tool.
  2. Switch it on and reconnect; the tool is listed.
  3. A `dryRun` call shows no dialog.
  4. A real call shows a dialog. "Abbrechen" → `notConfirmed`.
  5. Waiting 2 minutes closes the dialog → `notConfirmed`.
  6. "Löschen" → the transaction is gone from the Hibiscus list.
- [ ] **Step 8: Commit** with the message `MCP: Einstellung "Umsaetze loeschen", Doku (#4)`.
