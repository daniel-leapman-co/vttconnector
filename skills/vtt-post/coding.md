# Coding transactions

## Reading `vtt chart`

`vtt chart FILE --format markdown --with-precedent 6` groups accounts by ledger and,
per account, shows: P&L vs balance sheet, how many times it has been used, when it was
last used, its balance, and the **typical prior narratives** coded to it.

The prior narratives are the strongest signal. "This description was coded to this
account before" beats any rule of thumb — a statement line reading `PURE GYM LTD` goes
wherever `PURE GYM` went last time. Work description-first:

1. Look for an account whose prior narratives contain (or closely match) the statement
   line's merchant/reference.
2. Failing an exact precedent, choose by meaning, respecting P&L vs balance sheet — an
   expense belongs on a P&L account, a transfer or settlement on a balance-sheet one.
3. If still unsure, **ask the user.** Don't guess on anything material.
4. If nothing in the chart fits, propose a new account to the user - ledger and name -
   rather than forcing a poor fit. Only on their say-so, create it with
   `vtt add-account` (dry run first) before posting the batch that uses it.

Match on a stable prefix of the narrative (merchants often append varying refs/dates),
and keep distinct merchants distinct even when they share a prefix (e.g. Amazon Prime →
subscriptions vs a generic Amazon order → shopping).

## Control ledgers (suppliers / customers)

Accounts flagged as a control ledger belong to a supplier or customer. Post the
transaction to the **supplier/customer**, not to a P&L account. Coding a supplier
payment straight to an expense double-counts it and leaves the creditor outstanding.
Card settlements are the common case: a payment leaving the bank to a credit-card
provider settles the supplier (`Suppliers|…`), it is not an expense. Flag these for the
user.

## Transfers and dedup

- **Transfers between the entity's own accounts** (current → savings, bank → petty
  cash) are posted **once**, as `TRF`. Don't post both legs from both statements.
- **Card settlements** appear on both the bank statement (payment out) and the card
  statement (payment in). Post the settlement from **one** side only; code the card's
  individual purchases from the card statement.
- **Reconciliation is the dedup.** There is no hash guard. If the same line is posted
  twice, the account's book value will overshoot the statement's closing balance and
  the step-5 tie-out fails. That is the intended safety net — trust it, and when a tie
  fails, look for a duplicated or doubled line first.

## Transaction types

| Type | Use for |
| --- | --- |
| `PAY` | money out of a bank/card account |
| `REC` | money in |
| `TRF` | transfer between the entity's own accounts |
| `JRN` | revaluations, interest capitalised, true journals |

Using `PAY`/`REC` (not `JRN`) for cash movements keeps VT's cashbook and bank
reconciliation working.

## Investment / savings revaluations

A single `JRN` to move an asset to its stated period-end value: debit (increase) the
holding, credit the gains/interest P&L account the file already uses for that holding
(follow the account's prior narratives — capital movement vs interest are usually
different accounts). Interest paid direct from the bank shows in a statement as a
purchase-in / fee-out wash and must be excluded from a revaluation.
