# How VT stores accounting data

## Ledgers and accounts

Every account belongs to a **ledger**, and account names are **only unique within a
ledger**. So an account is properly identified as `Ledger|Account`.

The separator differs by tool, same accounts either way:

| Context | Form |
| --- | --- |
| `vtt chart`, `vtt entries`, `vtt post` | `Expenses\|Rent, power and insurance costs` (pipe) |
| Universal Input Sheet, Analysis account column | `Expenses: Rent, power and insurance costs` (colon-space) |
| UIS Primary Account column | `Current account` — bare name, no ledger prefix |

A fresh VT file ships around 170 standard accounts; most client files use a few
dozen and have renamed or added some. **Never code against the default chart when
the client's `.vtr` is reachable** — an account name that is not in the file is
rejected on import, and a plausible-sounding empty account is usually the wrong one.

`Ledger.IsPL` is what classifies P&L versus balance sheet. Do **not** infer it from
year-end entries: VT's year end also moves fixed-asset cost and disposals between
accounts, which misclassifies them.

### Control ledgers

Customer and supplier ledgers are **control ledgers** — each account in one *is* a
customer or supplier. `vtt chart` flags them with `*`. `Ledger.ListType` is set only
on these, so its presence is the reliable test.

Post to the supplier or customer, never to a P&L account. Coding a supplier payment
straight to an expense double-counts it and leaves the creditor outstanding. The
common case is a credit-card settlement: money leaving the bank to the card provider
settles `Suppliers|…`; the card's individual purchases are the expenses, and they
come off the card statement.

## Transactions and entries

A **transaction** is the header — type, date, reference, and Details. It holds two
or more **entries**, each hitting one account, signed **positive debit / negative
credit** and summing to zero.

- The **first entry added becomes the primary entry** (`TypeID` 2). On a bank or
  card transaction, that is the bank or control account. Order matters: VT refuses a
  VAT scope flag until a primary entry exists, and flagging the primary itself fails.
- Analysis entries are `TypeID` 5; a real VAT entry is `TypeID` 3 with `IsAutoVAT`
  true. See [vat.md](vat.md).

### Transaction types

`vtt info` lists the codes valid for a given file.

| Type | Use for |
| --- | --- |
| `PAY` | money out of a bank or card account |
| `REC` | money in |
| `CCP` | credit card purchase |
| `TRF` | transfer between the entity's **own** accounts |
| `JRN` | revaluations, interest capitalised, true journals |
| `SIN` | sales invoice |

The codes available vary by file — `vtt info` is the authority, not this table.

Use `PAY`/`REC` rather than `JRN` for cash movements — it is what keeps VT's
cashbook and bank reconciliation working.

`TranType.HasVATEntries` decides whether a type can carry VAT: true for `PAY`,
`REC`, `CCP`; false for `JRN`. A `vat` value on a `JRN` is an error, not a silent
omission.

**Transfers between the entity's own accounts are posted once**, as `TRF` — don't
post both legs from both statements. Likewise a card settlement appears on the bank
statement and the card statement; post it from one side only.

## Details and entry details

VT keeps two narratives and they are read in different places, so they are written
differently.

- **Details** (`Transaction.Text`; `text` in a `vtt` batch; the Details column in
  the UIS) titles the whole transaction — who it was with and what for. It is what
  you see in the transaction list.
- **Entry details** (`Entry.Text`; `line_text`; the Entry details column) is what
  shows against a line when you open **one account's** ledger, with the rest of the
  transaction off screen.

**The rule: entry details is an *extension* of details, never a replacement and
never a bare fragment.**

- **Ordinary one-sided transactions** (payments, receipts, invoices): entry details
  = details, verbatim. There is one analysis line, so there is nothing to
  distinguish. Leave the field blank and VT copies the details down itself.
- **Split transactions:** keep the high-level identity from Details — supplier and
  invoice number, or customer and job — then qualify it.
  `Acme Property Ltd inv 2401 (July) - fixed rent`, not `fixed rent`. A bare qualifier
  against the rent account tells you nothing about whose rent or which invoice,
  which is exactly what you need when reviewing that account.
- **Journals are the exception:** their lines are usually distinct enough to stand
  alone (`Depreciation of buildings`).

`vtt` implements this — it treats `line_text` as a qualifier and appends it to the
transaction text, skipping when the text already contains it. VT accepts long text;
133 characters has posted without truncation.

## Dates: lock date and year end

**Lock date.** `vtt info` reports it. VT rejects any transaction dated **on or
before** it. Check it before building a batch, not after.

**Year end.** Posting into a period on or before an existing year end causes VT to
**restate the year-end transaction**, exactly as it does in the GUI.

This is intended and valued — it is why a year end can be re-run freely — but it
means a back-dated posting changes prior-period figures. Re-check with `vtt tb` for
the affected dates if that matters. Do not "guard" against the cascade.

It is also the single strongest reason writes must go through VTA: a hand-written
appender would leave the year-end transaction stale and the file internally
inconsistent, with no error. See [internals.md](internals.md).

The second argument to `Account.Value` is `IncludeClosingYearEnd`, and `vtt` passes
false — which is why a trial balance *at* the year-end date shows the year's P&L
rather than the position after the year end has been swept to reserves.

## Coding from precedent

The strongest coding signal is what the client's own bookkeeping did before.
`vtt chart --with-precedent 6` surfaces it. Work description-first: find an account
whose prior narratives contain the statement line's merchant or reference; failing
that choose by meaning, respecting P&L vs balance sheet; failing that **ask**.

Match on a stable prefix — merchants append varying refs and dates — and keep
distinct merchants distinct even when they share one (Amazon Prime → subscriptions
vs a generic Amazon order → shopping). The full workflow is in `vtt-post`'s
`coding.md`.
