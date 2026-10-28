---
name: vtt-import
description: Prepares accounting data for import into VT Transaction+ (VTT+) using the Universal Input Sheet format. Use when the user needs to format, map, or transform accounting transactions for VTT+ import, or when working with VT Transaction+ data entry, bank analysis, or bookkeeping.
---

# VT Transaction+ Universal Input Sheet

Prepares transaction data for import into VTT+ via the Universal Input Sheet (UIS), outputting CSV ready to copy into the system.

## Reference files

- [format.md](format.md) — full column specifications, accepted values, and examples
- [accounting-basis.md](accounting-basis.md) — cash basis vs accruals transaction patterns
- [chart-of-accounts.md](chart-of-accounts.md) — the **default** VT chart, for when the client's own file is not to hand
- The **`vtt` skill** — general VT knowledge and the full `vtt` command reference: the data model, VAT, lock dates and year ends, and the COM environment

## Get the client's real chart first

Do not code against the default chart when the client's `.vtr` is available.
Every file's chart is edited — accounts renamed, added, or never used — and an
account name that is not in the file is rejected on import.

```bash
vtt chart "/mnt/c/.../Client.vtr" --format markdown --with-precedent 6
```

This gives the accounts that actually exist, plus how often each has been used,
when it was last used, its balance, and the narratives previously coded to it —
so a line can be coded from what the client's own bookkeeping did before rather
than from the account name alone. Prefer an account with precedent over a
plausible-sounding empty one.

Note the ledger separator differs between the two tools: `vtt chart` prints
`Ledger|Account`, the UIS wants `Ledger: Account`. Same accounts, different
punctuation.

Fall back to [chart-of-accounts.md](chart-of-accounts.md) only when the `.vtr`
cannot be reached — no path given, the file is on a drive you cannot see, or
`vtt` is unavailable. Say which one you used, because a fallback coding needs
checking against the file before import.

If the client's file is available and you are posting rather than preparing a
sheet, consider the `vtt-post` skill instead — it writes into the file through
VT's own API and skips the UIS entirely.

## Output format

Always output as CSV using the 11 UIS columns in order:

```
Type,Ref No,Date,Primary Account,Details,Total,VAT,Analysis,Analysis account,Entry details,Notes
```

Rules:
- Leave Ref No blank (VTT+ auto-assigns)
- Leave VAT blank (not 0) when there is no VAT
- For split/journal continuation rows, leave Type, Ref No, Date, Primary Account, Details, Total, and VAT blank
- Journal Analysis amounts: positive = debit, negative = credit
- Wrap any field containing a comma in double quotes
- Dates: DD/MM/YYYY
- Numbers: decimal point, no thousands separator, 2 decimal places

## Workflow

1. Pull the client's real chart with `vtt chart` (see above); fall back to [chart-of-accounts.md](chart-of-accounts.md) only if the file is unreachable
2. Identify the accounting basis — cash or accruals (see [accounting-basis.md](accounting-basis.md))
3. Identify transaction types for each row
4. Map Primary Account (account name only — no ledger prefix)
5. Map Analysis account (`Ledger: Account` format)
6. Calculate VAT amounts where applicable
7. Write Details, then Entry details as an extension of it (see [format.md](format.md))
8. Output CSV

## Key rules

- Primary Account: account name only, no ledger prefix (e.g. `Current account`, `Widgets Ltd.`)
- Analysis account: always `Ledger: Account` format (e.g. `Expenses: Repairs and maintenance`)
- VAT on payments/receipts settling an invoice: leave blank
- All amounts positive except journal credit entries (negative)
- Entry details is never blank and never a bare fragment: it repeats Details, qualified where a transaction splits (e.g. `Acme Property Ltd inv 2401 - fixed rent`)
