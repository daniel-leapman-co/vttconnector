# Batch posting format

Write the batch as a CSV **file** in the scratchpad (it is the record of what you
posted), then post it. A path of `-` reads from stdin if you'd rather pipe.

## Columns

```
date,type,ref,text,account,amount,vat,line_text
```

| Column | Notes |
| --- | --- |
| `date` | `YYYY-MM-DD` |
| `type` | `PAY` / `REC` / `CCP` / `TRF` / `JRN`. Blank defaults to `JRN`. |
| `ref` | Blank → VT allocates the next reference for that type. |
| `text` | **Details** — the transaction narrative. |
| `account` | `Ledger|Account` (pipe). Use the full `Ledger|Account` form where a name is not unique. Must match the chart exactly. |
| `amount` | The **net**. **Positive = debit, negative = credit.** |
| `vat` | VAT on that net line, signed the same way. Blank = outside the scope of VAT. Omit the column entirely on a non-VAT file. |
| `line_text` | **Entry details** — a qualifier appended to `text`. Blank on ordinary one-sided transactions. |

## Rules

- **Each transaction must sum to zero, counting VAT.** VAT is posted as an entry of
  its own even though it is not a row of its own, so a £120 payment is `-120.00` on
  the bank and `100.00` net with `20.00` vat. The CLI checks this before calling VT,
  and VT checks again.
- **Consecutive rows sharing `date`/`type`/`ref`/`text` are one transaction.** A change
  in any of those four starts a new transaction. So the file below posts two
  transactions.
- **Put the bank or control account first.** The first line of a transaction becomes
  VT's primary entry, and VT will not accept a VAT flag until it exists.
- **Never write a line to the VAT account.** VT owns that entry; only the entry VT
  creates carries the net figure boxes 6 and 7 are analysed from. `vtt` refuses it.
- Quote any field containing a comma.

## Details vs entry details

`text` titles the whole transaction. `line_text` is what shows against a line when you
open that one account's ledger, with the rest of the transaction off screen — so it is
an *extension* of `text`, not a replacement, and `vtt` appends it:

| `text` | `line_text` | Posted entry details |
| --- | --- | --- |
| `Acme Property Ltd inv 2401 (July)` | *(blank)* | `Acme Property Ltd inv 2401 (July)` |
| `Acme Property Ltd inv 2401 (July)` | `fixed rent` | `Acme Property Ltd inv 2401 (July) - fixed rent` |

Leave `line_text` blank on an ordinary payment or receipt — with one analysis line
there is nothing to distinguish. Use it when a transaction splits across accounts.

## Worked example

A card payment leaving the bank, and a savings-interest journal:

```csv
date,type,ref,text,account,amount,vat,line_text
2026-07-17,PAY,,American Express settlement,Suppliers|American Express,1859.27,,
2026-07-17,PAY,,American Express settlement,Bank|Lloyds,-1859.27,,
2026-07-18,JRN,,Marcus interest,Bank|Marcus,45.10,,
2026-07-18,JRN,,Marcus interest,Investment gains/losses|Interest,-45.10,,
```

And a VAT-registered file — a split supplier invoice and a zero-rated card payment:

```csv
date,type,ref,text,account,amount,vat,line_text
2026-07-20,PAY,,Acme Property Ltd inv 2401 (July),Cash book|Current account,-3360.00,,
2026-07-20,PAY,,Acme Property Ltd inv 2401 (July),Expenses|Other business expenses,2000.00,400.00,service charge
2026-07-20,PAY,,Acme Property Ltd inv 2401 (July),"Expenses|Rent, power and insurance costs",800.00,160.00,fixed rent
2026-07-21,CCP,,IAP TRAINLINE LONDON,Suppliers|HSBC credit card,-38.00,,
2026-07-21,CCP,,IAP TRAINLINE LONDON,"Expenses|Car, van and travel expenses",38.00,0.00,
```

A `vat` of `0.00` is a zero-rated or exempt supply that still belongs in box 7; a
**blank** `vat` is outside the scope of VAT and stays off the return entirely. The
difference is invisible on the balance sheet and wrong on the return, so decide it
deliberately per line.

## Posting

```
vtt post "<file.vtr>" --csv batch.csv            # dry run — file untouched
vtt post "<file.vtr>" --csv batch.csv --commit   # writes; timestamped backup + Verify()
```

A dry run builds and posts each transaction through VT inside a rollback, so it reports
the exact errors a real post would — a bad account name, an unbalanced transaction, a
date on/before the lock date — while leaving every entry and balance untouched. Always
dry-run first, confirm the reconciliation ties, then `--commit`.

A dry run does still rewrite some of the file's internal housekeeping, so the `.vtr`
will look modified to OneDrive and its hash will change. That is expected; check `vtt
tb` or `vtt entries` rather than a checksum to confirm nothing moved.
