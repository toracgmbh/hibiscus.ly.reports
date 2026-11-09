# MCP: Delete transactions (and expose transaction IDs)

Issue: #4

## Intent

When a re-sync fetches a period that is already in the database, Hibiscus
recognises known transactions but can import a second copy when the bank
delivers a field such as the counterparty name in a different format (e.g.
"Beispiel GmbH" vs. "BEISPIEL GMBH NIEDERLASSUNG"). Such copies are
otherwise identical.

The user works with Hibiscus through Claude sessions over MCP. A session can
already find such pairs by reading `hibiscus_transactions_list`, but it can
neither tell two identical entries apart (the output has no ID) nor remove
one. This feature closes that gap, with deletion strictly opt-in and
confirmed in Hibiscus itself.

## Goals

1. `hibiscus_transactions_list` returns each transaction's Hibiscus ID.
2. A new tool `hibiscus_transactions_delete` deletes transactions by ID from
   the local Hibiscus database.
3. Deleting is off by default and controlled by a new checkbox in the MCP
   settings dialog. When it is off, the tool is not advertised at all.
4. Every real (non-dry-run) delete is confirmed by the user in a Hibiscus
   dialog.

## Non-goals

- No duplicate-detection tool over MCP. Deciding what is a duplicate is
  left to the model reading the list output. (Item 3 of the issue is
  dropped.)
- No change to the existing GUI duplicate detection (Tools / Duplikate
  suchen), including its scoring.
- No change to how `hibiscus_sepa_transfer_create` is gated (it stays
  advertised and is refused at call time when "Ueberweisungen anlegen" is
  off).
- Nothing is sent to the bank. Deletion is local only.

## Anti-goals (would make this a failure even if it works)

- A transaction is deleted without the user having clicked "yes" in
  Hibiscus for that call.
- A client can discover or use deletion while the setting is off.
- A single bad ID makes the whole call fail without telling which IDs were
  and were not processed.

## Behaviour

### 1. ID in `hibiscus_transactions_list`

- Each transaction object gets an `id` field with the Hibiscus `Umsatz` ID,
  as a string (matching how account and category IDs are already returned).
  `ReportTransaction` already carries the ID; it is just not serialised in
  `McpJsonRpcHandler.transaction(...)`.
- Always present, independent of any setting.
- Tool description and `README_MCP.md` mention that this ID is what
  `hibiscus_transactions_delete` takes.

### 2. Setting "Umsaetze loeschen"

- New boolean in `McpSettings`, e.g. `deleteEnabled`, default `false`,
  following the existing `writeEnabled` pattern.
- New checkbox "Umsaetze loeschen" in `McpSettingsDialog`, next to
  "Ueberweisungen anlegen".
- When off:
  - `tools/list` does not contain `hibiscus_transactions_delete`.
  - A `tools/call` for it is refused with an error (defence in depth), the
    same way an unknown tool is refused or the SEPA tool is refused when
    disabled.
- When on: the tool is listed and works as below.
- The server has no server-to-client channel (plain HTTP, no SSE), so
  `notifications/tools/list_changed` cannot be pushed. After toggling the
  setting, clients see the change on their next `tools/list`, typically
  after reconnecting. `README_MCP.md` says so.

### 3. Tool `hibiscus_transactions_delete`

Input:

| Field    | Type            | Required | Meaning |
|----------|-----------------|----------|---------|
| `ids`    | array of string | yes      | Hibiscus transaction IDs, at least one. Duplicates in the list are collapsed. |
| `dryRun` | boolean         | no       | Default `false`. When `true`, only report what would be deleted. |

Processing:

1. Validate the input. An empty or missing `ids` is an argument error
   (whole call fails, nothing happens).
2. Load each ID. Unknown IDs are marked `unknown` and take no further part.
3. For each found transaction, collect a short description (account, date,
   amount, counterparty name, purpose) and a list of attached links (see
   below).
4. If `dryRun`: return the per-ID result with status `wouldDelete` /
   `unknown`. No dialog, no change.
5. Otherwise, if at least one transaction was found: show **one**
   confirmation dialog in Hibiscus listing all found transactions of this
   call (and noting how many IDs were unknown). It is all-or-nothing for
   the call.
   - "No", closing the dialog, or no answer (see "Dialog" below): every
     found transaction gets status `notConfirmed`; nothing is deleted.
   - "Yes": delete each found transaction individually. Success →
     `deleted`; an exception → `error` with the message. A failure on one ID
     does not stop the others.
6. Return the result.

Output (structured content):

```json
{
  "dryRun": false,
  "confirmed": true,
  "results": [
    {
      "id": "4711",
      "status": "deleted",
      "transaction": {
        "kontoId": "12", "datum": "2025-01-14", "betrag": -42.00,
        "gegenkontoName": "Example GmbH", "zweck": "Invoice 4711"
      },
      "links": ["kategorie: Versicherung"]
    },
    { "id": "9999", "status": "unknown" }
  ],
  "counts": { "deleted": 1, "unknown": 1, "notConfirmed": 0, "error": 0 }
}
```

Statuses: `wouldDelete` (dry run only), `deleted`, `unknown`,
`notConfirmed`, `error` (with `message`). Field names in the
`transaction` summary follow the existing German names of the list output.
`confirmed` is absent for dry runs and when no ID was found.

The tool description tells the client that deletion is irreversible, local
only, that a dry run is recommended first, and that the user has to confirm
in Hibiscus.

#### Links ("Verknuepfungen")

The result names links attached to a transaction so the client can tell the
user what is lost. At minimum: an assigned category and a non-empty
comment. Split bookings (parent/child transactions) must not be silently
broken: the builder checks how Hibiscus' own `Umsatz.delete()` treats them
and either relies on that or reports/refuses accordingly. Links are
reported, they do not block deletion.

#### Dialog

- Shown on the SWT display thread; content lists every transaction of the
  call in readable form (date, amount, counterparty, purpose, account),
  plus "this cannot be undone; nothing is changed at the bank".
- Only an explicit "yes" deletes.
- If the user is not at the machine (e.g. remote use through ngrok), the
  call must not delete anything. The existing confirm helper
  (`Application.getCallback().askUser`, used in `AutomationDialogs`) blocks
  without a timeout; the builder decides whether to add a timeout (preferred:
  a few minutes, then `notConfirmed` and the dialog closes) or accept
  blocking. Either way, a late "yes" after the HTTP request has already
  timed out on the client side must not be possible without the user
  knowing; a timeout that closes the dialog avoids this.
- Should respect the existing dialog gate (`AutomationDialogGate`) if that
  is what keeps dialogs from colliding with other modal work, at the
  builder's discretion.

## Constraints

- Plugin is Java on Jameica/Hibiscus; follow the existing structure in
  `de.open4me.hibiscus.reports.mcp`: the handler gets the deleter injected
  (like `SepaTransferDraftWriter` / `McpAccountSynchronizer`) so tests can
  use a fake, plus a `BooleanSupplier` for the setting.
- The repository is public. Tests, docs, examples and commit messages use
  invented values only (e.g. "Invoice 4711", "Example GmbH"), never real
  account data.
- Tool names, titles and descriptions follow the existing German,
  ASCII-transliterated style ("Umsaetze loeschen").

## Testing

- `McpJsonRpcHandlerTests`:
  - list output contains `id`;
  - `tools/list` without / with the setting;
  - call refused when the setting is off;
  - dry run: statuses, no dialog, no deletion;
  - confirmed: mixed known/unknown/failing IDs → per-ID statuses, others
    still deleted;
  - declined / timed out → all `notConfirmed`, nothing deleted;
  - empty `ids` → argument error.
- Dialog and real Hibiscus deletion are behind an interface and tested
  manually in Jameica.

## Documentation

- `README_MCP.md`: new setting, new tool, `id` in list output, reconnect
  after toggling.
- `ChangeLog.txt` entry.

## Left to the builder

- Exact class names and where the deleter lives.
- Dialog implementation (Jameica `askUser` vs. custom dialog), timeout
  length, and whether it goes through `AutomationDialogGate`.
- How to detect and report links beyond category and comment, and how to
  handle split bookings.
- Exact error message texts.

## Decisions marked as Claude's call

- One dialog per call, all-or-nothing.
- `id` as string.
- Status names and output shape above.
- No `list_changed` notification (no push channel); reconnect documented
  instead.
- SEPA tool gating left unchanged.
- Refusal when the setting is off: thrown from the tool call like
  `createSepaTransferDraft`, so the client gets a regular error.
- Malformed or non-numeric IDs count as `unknown`, not as an argument
  error.
- Deletion reuses the existing path of the GUI duplicate view:
  `DuplicateTransactionRepository.loadTransaction(id).delete()` (or the same
  calls moved to a shared place).
