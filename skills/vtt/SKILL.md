---
name: vtt
description: General knowledge about VT Transaction+ (VTT+) and reference for the vttconnector `vtt` CLI. Covers how VT stores data (ledgers, accounts, transactions, entries, year ends, lock dates), how VAT works in VT and why a hand-built VAT line silently breaks boxes 6 and 7, the details/entry details narrative convention, the three supported ways to get data into a .vtr file and why the binary format must never be hand-written, the full `vtt` command reference and its WSL/COM environment, and the VTA COM API traps. Use when asked how VT or the vtt connector works, when reading data out of a .vtr, when choosing between the posting routes, when diagnosing a VT or `vtt` error, or when extending vttconnector itself. For the step-by-step posting workflow use vtt-post; for preparing a Universal Input Sheet use vtt-import.
---

# VT Transaction+ and the vtt connector

VT Transaction+ (VTT+) is the firm's bookkeeping ledger. One client entity is one
`.vtr` file — a proprietary binary store holding the whole chart of accounts,
every transaction, and VT's own indexes and cached balances.

This skill is the **knowledge base**: what is true about VT, and what `vtt` can do.
The two workflow skills sit on top of it:

- **`vtt-post`** — the step-by-step loop for posting a statement into a client's
  `.vtr` through the connector.
- **`vtt-import`** — preparing a Universal Input Sheet to paste into VT's own import.

## Reference files

- [connector.md](connector.md) — the `vtt` CLI: every command, the posting input
  forms, the safety model, and the WSL/32-bit COM environment it needs.
- [data-model.md](data-model.md) — ledgers, accounts, transactions, entries,
  transaction types, control ledgers, the details/entry details convention, lock
  dates and year ends.
- [vat.md](vat.md) — how VT builds a VAT entry, why you must never write one
  yourself, and the three VAT states.
- [internals.md](internals.md) — the `.vtr` binary format, why it must not be
  hand-written, and the VTA COM API traps. Read when extending vttconnector.

## The three ways data gets into a .vtr

| Route | What it is | When |
| --- | --- | --- |
| **The VT GUI** | Typing into VT | Anything interactive; the reference behaviour |
| **Universal Input Sheet** | VT's own spreadsheet import | The client file is not to hand, or a human wants to eyeball the sheet before importing. See `vtt-import` |
| **VTA COM API** | VT Accounting Objects, driven by `vtt` | Programmatic posting. The default when the `.vtr` is reachable. See `vtt-post` |

There is no fourth route. **Writing the `.vtr` binary directly is not an option** —
see [internals.md](internals.md) for the evidence. Reading it directly is fine and
is what `vtt check` uses as an independent cross-check.

Every write through `vtt` goes through VT itself, so VT maintains its indexes,
denormalised balances and year-end postings exactly as it does for the GUI.

## Cheat sheet

`vtt` is on PATH; source in `~/tools/vttconnector` (full docs in its `README.md`).
Quote the `.vtr` path — client filenames contain spaces.

```
vtt info     "FILE.vtr"                                   # company, VAT no, year end, lock date, type codes
vtt chart    "FILE.vtr" --format markdown --with-precedent 6   # accounts + coding context
vtt accounts "FILE.vtr" --search rent                     # find an exact account name
vtt tb       "FILE.vtr" --date 2026-06-30                 # trial balance
vtt balance  "FILE.vtr" --account "Bank|Current account"  # one account's book value
vtt entries  "FILE.vtr" --account lloyds --tail 5         # entries as CSV
vtt post     "FILE.vtr" --csv batch.csv                   # DRY RUN
vtt post     "FILE.vtr" --csv batch.csv --commit          # writes; backup + Verify()
vtt check    "FILE.vtr" --against tb.txt                  # VTA vs parser vs a VT report
vtt show     "FILE.vtr" --type PAY --ref 1676             # a posted tran, lines numbered
vtt edit     "FILE.vtr" --id 2049 --account "Subsistence" # recode (DRY RUN)
vtt edit     "FILE.vtr" --id 2073 --vat 20% --commit       # re-split gross into net+VAT
vtt edit     "FILE.vtr" --id 2073 --split "Travel=1.20:taxi"  # carve an amount off a line
vtt add-account "FILE.vtr" --ledger Expenses --name "Cleaning"   # new account (DRY RUN)
```

Add `--json` to any command for machine-readable output.

## The things that bite

- **Posting is a dry run unless `--commit` is given.** A dry run is not a
  simulation — it really posts inside a rollback, so it raises the same errors.
- **A dry run does change the file's bytes**, though not one figure of accounting
  data. Never use a checksum to prove a dry run was safe; diff `vtt tb` or
  `vtt entries` instead. See [connector.md](connector.md).
- **The file must be closed in VT**, or any post — dry run included — fails with
  *"Write access denied."*
- **Never write a VAT line yourself.** It posts, it balances, `Verify()` passes,
  boxes 1–5 come out right, and boxes 6 and 7 are silently understated by the
  whole net. See [vat.md](vat.md).
- **Check the lock date before posting** (`vtt info`) — VT rejects any transaction
  dated on or before it.
- **Editing posted transactions: VT does NOT enforce the lock date through COM.**
  `vtt edit` soft-blocks it (`--force` to override). VT itself blocks VAT/date
  changes on a transaction in a posted VAT return but allows recoding it. VT does
  not stop edits to the bank line or VAT entry; `vtt edit` refuses those. See
  [connector.md](connector.md) "Editing posted transactions".
- **Back-dating past a year end restates the year end.** Intended, not a bug, but
  it moves prior-period figures. See [data-model.md](data-model.md).
- **In the Universal Input Sheet, a split's continuation rows look blank and must
  not be tidied away** — deleting one forces the whole net onto a single account
  with no error. Detail in `vtt-import`.

## Client work

This workspace has a standing estratos rule: on client files, `retrieve` the
client scope before starting and record durable coding decisions as you go. Skip
it for personal or test files.
