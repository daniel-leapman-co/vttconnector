# VAT in VT

**VT owns the VAT entry. You cannot build one yourself, and the failure is silent.**

This is the single most dangerous thing in the whole toolchain: a hand-built VAT
line posts, balances, passes `Verify()`, and produces correct figures in boxes 1 to
5 — while understating boxes 6 and 7 by the whole of the net behind it.

## How to do it

Put the **net** on the expense or income line and its VAT in that line's VAT field.
Never give VAT a line of its own.

```csv
date,type,ref,text,account,amount,vat,line_text
2026-07-15,PAY,,Supplier account inv 2323,Cash book|Current account,-1200.00,,
2026-07-15,PAY,,Supplier account inv 2323,Expenses|Other business expenses,1000.00,200.00,
```

- `amount` is always the net; `vat` is signed the same way as the net it belongs to
  (both debits on a purchase, both credits on a sale).
- **The transaction balances on net plus VAT** — a £1,200 payment is `-1200.00` on
  the bank against `1000.00` net with `200.00` VAT.
- Splits work: give each net line its own `vat`, and VT posts a **single** VAT entry
  for their total.
- `vtt` **refuses** a line posted directly to an input or output VAT account on a
  VAT-bearing transaction type.

In the Universal Input Sheet the same principle applies through the Total and VAT
columns on the header row — and on a payment or receipt that merely settles an
existing invoice, leave VAT blank; the VAT was accounted for on the invoice.

## The three states

The difference between the last two is invisible on the balance sheet and wrong on
the return, so decide it deliberately, per line.

| `vat` | Meaning | On the return |
| --- | --- | --- |
| `20.00` | standard-rated | boxes 1/4 **and** 6/7 |
| `0.00` | zero-rated or exempt, still a VAT supply | boxes 6/7 only |
| *(blank)* | outside the scope of VAT | not on the return at all |

## The mechanism

On a transaction type where `TranType.HasVATEntries` is true (`PAY`, `REC`, `CCP` —
not `JRN`), calling `Entry.SetWithinVATScopeIfPossible($true)` on a **net** line
makes VT create the VAT entry itself: `TypeID` 3 (`vtaETVAT`), `IsAutoVAT` true, on
the account from `Company.DefinedAccounts(4|5)`. You then set only that entry's
`BaseValue` to the VAT amount.

**`VATTurnoverValue` is the net behind the VAT** — the figure boxes 6 and 7 are
analysed from — **and it cannot be assigned.** Setting it on a real VAT entry throws
*"Automatic VAT entry. VATTurnoverValue cannot be set directly."* VT derives it from
the in-scope net lines, summing them where a transaction splits.

**Order matters.** The first entry added becomes the primary (`TypeID` 2), and VT
refuses a VAT scope flag until a primary exists. Add every line first — bank or
control account first — then apply the flags, then set the VAT entry's value.
Flagging the primary itself fails.

**Cash accounting** needs nothing special for cash transactions. Leave
`DeferredVATStatus` at 0; setting it to 2 breaks the auto VAT entry, because VT then
expects the deferred account.

## Why a hand-built VAT line looks fine and is not

Adding an ordinary entry to `Liabilities|Input VAT` posts, balances, and `Verify()`
returns 0 — but the entry is `TypeID` 5 (analysis), `Transaction.VATEntry` is null,
and its turnover is zero. Boxes 1 to 5 still come out right, because VT sums the VAT
*accounts* for those, so nothing looks wrong. **Boxes 6 and 7 are understated by the
whole net.**

Illustrative figures for a VAT-registered file:

| Box | Hand-built VAT lines | Correct |
| --- | --- | --- |
| 6 | 39,000.00 | 44,000.00 |
| 7 | 8,000.00 | 9,200.00 |

**How to detect it after the fact.** `vtt entries` emits `vat_net` on each VAT entry
and `in_scope` on the net lines it was derived from. A VAT entry with an **empty
`vat_net`** is this defect.

## Practice rule

On a VAT-registered file (`vtt info` shows `vatRegistered`), a VAT error that
reaches a filed return is an amendment, not a recoding. State the VAT treatment and
get the user's agreement before committing.
