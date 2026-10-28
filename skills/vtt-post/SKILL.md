---
name: vtt-post
description: Connect to a VT Transaction+ .vtr ledger and post transactions into it through the vttconnector CLI (VT's COM API) — the live-posting route, not the Universal Input Sheet. Use when the user wants to process/import/post a bank, card, or savings statement into a .vtr file, code transactions against the chart of accounts, reconcile an account to a statement balance, or query existing entries on an account. Client files are the primary case. For preparing a spreadsheet to paste into VT's Universal Input Sheet instead, use vtt-import.
---

# Posting into VT Transaction+ (vttconnector)

Drives the `vtt` CLI (installed on PATH; source in `~/tools/vttconnector`), which reads
and writes `.vtr` files through VT's own COM API. Every write goes through VT, so its
indexes, cached balances and year-end postings stay correct.

The loop: **connect → chart → request existing entries → code from precedent →
reconcile to the statement → post a batch.** The model proposes *accounts*; it never
invents or round-trips an *amount* — amounts come straight from the statement.

## Reference files

- [coding.md](coding.md) — reading `vtt chart`, picking an account from prior
  narratives, control ledgers, transfers, and why reconciliation is the dedup.
- [batch-format.md](batch-format.md) — the posting CSV format and a worked example.
- The **`vtt` skill** — general VT knowledge and the full `vtt` command reference:
  the data model, VAT, lock dates and year ends, the COM environment, and the API
  traps. Load it when something here needs explaining rather than following.

## Ground rules (read first)

- **`vtt` is on PATH** (source in `~/tools/vttconnector`) — run it from any directory,
  e.g. the client's folder. Give the `.vtr` path absolute and quoted; these files have
  spaces.
- **The file must be closed in VT.** Posts (even dry runs) fail with *"Write access
  denied. File may be read-only or already open."* if VT has it open. If you hit that,
  ask the user to close VT, then retry.
- **VAT needs the user's say-so.** `vtt` can now post VAT correctly: the net goes on
  the expense or income line with its VAT in that line's `vat` column, and VT builds
  the VAT entry itself carrying the net that boxes 6 and 7 are analysed from. Never
  write a line to the VAT account yourself — `vtt` refuses it. But a VAT error that
  reaches a filed return is an amendment, not a recoding, so on a VAT-registered file
  (`vtt info` shows `vatRegistered`) say so and get the user's agreement to the VAT
  treatment before committing. See the VAT section of the tool's `README.md`.
- **Ask when unsure.** On any transaction you can't confidently code from precedent,
  ask the user rather than guessing.
- **Client memory (client files only).** This workspace has a standing estratos rule:
  before starting client work, `retrieve` the client scope for prior coding decisions;
  record durable decisions and watch-points as you go. Skip for a personal file.

## The loop

### 1. Connect & orient
```
vtt info    "<file.vtr>"
```
Note the **lock date** (VT rejects postings dated on or before it) and the current
year end (posting into a closed period restates the year end — intended, but it moves
prior-period figures; re-check with `vtt tb` if it matters).

### 2. Get the chart of accounts
```
vtt chart   "<file.vtr>" --format markdown --with-precedent 6
```
This is what you code against — see [coding.md](coding.md). Control ledgers
(supplier/customer) are flagged; post to the supplier/customer, not the account.

### 3. Request the existing entries you need
Establish precedent and the pre-posting book value:
```
vtt entries "<file.vtr>" --account "<name>" --tail 5      # last 5 on an account
vtt entries "<file.vtr>" --from 2026-04-01 --to 2026-07-31   # a period, all accounts
vtt balance "<file.vtr>" --account "<name>"                 # book value now (anchor)
```
Get the **book value of the account being posted to** before you post — it is the
reconciliation anchor for step 5.

### 4. Code the statement into a batch
Map each statement line to an account using the chart's prior narratives (see
[coding.md](coding.md)). Amounts come verbatim from the statement. Write the batch as
a **CSV file in the scratchpad** — it is the durable record of what you posted — in the
format in [batch-format.md](batch-format.md). Flag control-ledger codings and anything
ambiguous for the user before posting.

### 5. Reconcile, then post
The safety gate is reconciliation, not a hash: **opening book value (step 3) + sum of
the batch must equal the statement's stated closing balance, to the penny.** If it
doesn't tie, do not post — find the miscode or missing/duplicated line first (a
double-post overshoots the statement).

```
vtt post "<file.vtr>" --csv batch.csv                 # dry run — file untouched
vtt post "<file.vtr>" --csv batch.csv --commit        # writes; auto-backup + Verify()
```
Use `PAY` for money out and `REC` for money in (not `JRN`) so VT's cashbook and bank
reconciliation keep working; `TRF` for transfers between the entity's own accounts;
`JRN` for revaluations and true journals.

After committing, confirm `Verify()` returned 0, then re-check the anchor:
```
vtt balance "<file.vtr>" --account "<name>"           # must equal statement closing
```
Report the before/after balance and the reconciled figure to the user.

### 6. Correct miscodings in place
Recode, fix VAT or split a posted line with `vtt edit` rather than reversing and
reposting — the bank line and gross never move, so the reconciliation from step 5
still holds:
```
vtt show "<file.vtr>" --type PAY --ref 1676                          # find it, see line numbers
vtt edit "<file.vtr>" --type PAY --ref 1676 --account "Subsistence"  # dry run
vtt edit "<file.vtr>" --type PAY --ref 1676 --vat 20% --commit
```
Full flags and what it refuses: the `vtt` skill's connector.md. It soft-blocks
anything on or before the lock date (`--force`); treat that as a question for the
user, not a flag to add.
