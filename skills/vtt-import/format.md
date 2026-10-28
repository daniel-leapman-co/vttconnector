# Universal Input Sheet — Column Reference

## Column order

| # | Column | Required | Notes |
|---|--------|----------|-------|
| 1 | Type | Yes | Transaction type code; only on first row of a transaction |
| 2 | Ref No | No | Auto-assigned by VTT+; leave blank |
| 3 | Date | Yes | DD/MM/YYYY; only on first row of a transaction |
| 4 | Primary Account | Yes | Account name only (no ledger prefix); only on first row |
| 5 | Details | Yes | Transaction description; only on first row |
| 6 | Total | Yes | Gross amount; only on first row; blank for JRN/RJN |
| 7 | VAT | No | VAT amount; leave blank if none; only on first row; blank for JRN/RJN |
| 8 | Analysis | Yes | Net amount for this line; negative for credit entries in journals |
| 9 | Analysis account | Yes | `Ledger: Account` — the nominal account for this line |
| 10 | Entry details | No | Line-level description |
| 11 | Notes | No | Free-text; not posted to ledger |

**Split and journal transactions** use multiple rows. Only the first row carries Type, Ref No, Date, Primary Account, Details, Total, and VAT. Subsequent rows contain only Analysis, Analysis account, and Entry details.

> **Never tidy away a continuation row.** With most columns deliberately blank they read as empty or zero-value rows, but deleting one does not raise an error: VT keeps the header row's Total and VAT, finds a single surviving analysis line that no longer ties, and forces the **whole** net onto it. The trial balance still balances and every total is still right — only the analysis is wrong, which is what review does not catch. Filling the Notes column on continuation rows makes them obviously deliberate. After any import, check the analysis accounts with `vtt entries FILE --from … --to …`, not just the totals.

---

## Column details

### Type
Transaction type code that determines how VTT+ posts the entry.

| Code | Description |
|------|-------------|
| PAY | Payment |
| CHQ | Cheque |
| REC | Receipt |
| SIN | Sales Invoice |
| SCR | Sales Credit Note |
| PIN | Purchase Invoice |
| PCR | Purchase Credit Note |
| PCV | Petty Cash Voucher |
| CCV | Credit Card Voucher |
| JRN | Journal |
| RJN | Reversing Journal — auto-reverses on the first day of the following period |

**Notes:**
- CHQ and PAY are functionally similar; use CHQ when the payment instrument is a physical cheque.
- JRN and RJN: no Primary Account, Total, or VAT. Analysis amounts use positive (debit) and negative (credit) values. Debits and credits must balance. Journals are rarely entered via the UIS.

### Ref No
Auto-assigned by VTT+. Leave blank.

### Date
Format: `DD/MM/YYYY`

### Primary Account
The account name only — no ledger prefix. VTT+ infers the ledger from the transaction type.

| Transaction type | Primary Account |
|-----------------|----------------|
| SIN, SCR | Customer name (e.g. `Springsteen Ltd.`) |
| PIN, PCR | Supplier name (e.g. `Widgets Ltd.`) |
| PAY, CHQ, REC | Bank account name (e.g. `Current account`) |
| PCV | `Petty cash` |
| CCV | Credit card account name |
| JRN, RJN | Leave blank |

**Note on control accounts:** VT maintains `Debtors: Trade debtors` and `Creditors: Trade creditors` automatically as the sum of all customer and supplier account balances. These are never used as Primary Accounts in transaction entry.

### Details
The main transaction description — a title for the whole transaction: who it was with and what for. It is what appears in the transaction list and on the Primary Account's statement.

### Total
Gross (VAT-inclusive) amount. Positive value. Leave blank for JRN/RJN.

### VAT
The VAT monetary amount (e.g. `40.00`). Not a code or rate.

Leave blank when there is no VAT — do not enter `0`. Leave blank for JRN/RJN.

### Analysis
The net amount for this analysis line.
- Routine transactions: positive value; Analysis = Total − VAT for single-line entries
- Journals: positive for debits, negative for credits; all rows must net to zero

### Analysis account
Format: `Ledger: Account` (both strings).

See [chart-of-accounts.md](chart-of-accounts.md) for all valid accounts.

For PAY, CHQ, and REC the Analysis account determines the accounting treatment:

| Analysis account | Treatment |
|-----------------|-----------|
| `Suppliers: [name]` | Settling a creditor (accruals) |
| `Customers: [name]` | Settling a debtor (accruals) |
| `Expenses: [account]` | Direct expense (cash basis) |
| `Income: [account]` | Direct income (cash basis) |

See [accounting-basis.md](accounting-basis.md) for full patterns.

### Entry details
What shows against this line when you open the **analysis account's** ledger — where the rest of the transaction is not on screen. Treat it as an extension of Details, not a separate field.

**Single-line transactions (PAY, CHQ, REC, SIN, SCR, PIN, PCR, PCV, CCV): Entry details = Details, verbatim.** There is only one analysis line, so there is nothing to distinguish; anything shorter just loses information when the line is read on its own.

**Split transactions:** keep the high-level identity from Details — supplier and invoice number, or customer and job — then qualify it with what that line is:

| Details | Entry details |
|---------|---------------|
| `Acme Property Ltd inv 2401 (July)` | `Acme Property Ltd inv 2401 (July) - service charge` |
| `Acme Property Ltd inv 2401 (July)` | `Acme Property Ltd inv 2401 (July) - fixed rent` |

A bare `fixed rent` against the rent account tells you nothing about whose rent or which invoice, which is exactly what you need when reviewing that account. Never leave a continuation row's Entry details blank.

**Journals** are the exception: the analysis lines are usually different enough that a descriptive Entry details per line stands on its own (`Depreciation of buildings`, `Depreciation of equipment`).

### Notes
Free-text. Not posted to any ledger.

---

## Examples

All examples sourced from VTT+ UIS screenshots.

### Purchase invoice (accruals)

£120 from Widgets Ltd. (£100 net + £20 VAT):

| Type | Ref No | Date | Primary Account | Details | Total | VAT | Analysis | Analysis account | Entry details |
|------|--------|------|-----------------|---------|-------|-----|----------|------------------|---------------|
| PIN | | 18/04/21 | Widgets Ltd. | Inv ref: 12345 | 120.00 | 20.00 | 100.00 | Expenses: Repairs and maintenance | Inv ref: 12345 |

### Sales invoice (accruals)

£600 to Springsteen Ltd. (£500 net + £100 VAT):

| Type | Ref No | Date | Primary Account | Details | Total | VAT | Analysis | Analysis account | Entry details |
|------|--------|------|-----------------|---------|-------|-----|----------|------------------|---------------|
| SIN | | 18/04/21 | Springsteen Ltd. | IT services - inv 4567 | 600.00 | 100.00 | 500.00 | Income: Sales | IT services - inv 4567 |

### Payment settling a supplier (accruals)

Settling the PIN above — no VAT:

| Type | Ref No | Date | Primary Account | Details | Total | VAT | Analysis | Analysis account | Entry details |
|------|--------|------|-----------------|---------|-------|-----|----------|------------------|---------------|
| PAY | | 21/04/21 | Current account | Payment of inv 12345 | 120.00 | | 120.00 | Suppliers: Widgets Ltd. | Payment of inv 12345 |

### Cash basis payment (direct to expense)

£72 to The Paper Shop (£60 net + £12 VAT), no invoice:

| Type | Ref No | Date | Primary Account | Details | Total | VAT | Analysis | Analysis account | Entry details |
|------|--------|------|-----------------|---------|-------|-----|----------|------------------|---------------|
| PAY | | 23/04/21 | Current account | The Paper Shop | 72.00 | 12.00 | 60.00 | Expenses: Stationery and printing | The Paper Shop |

### Receipt settling a customer (accruals)

Collecting payment for the SIN above — no VAT:

| Type | Ref No | Date | Primary Account | Details | Total | VAT | Analysis | Analysis account | Entry details |
|------|--------|------|-----------------|---------|-------|-----|----------|------------------|---------------|
| REC | | 23/04/21 | Current account | Rec'd payment of inv 4567 | 600.00 | | 600.00 | Customers: Springsteen Ltd. | Rec'd payment of inv 4567 |

### Cash basis receipt (direct to income)

£240 received from A Jones (£200 net + £40 VAT), no invoice:

| Type | Ref No | Date | Primary Account | Details | Total | VAT | Analysis | Analysis account | Entry details |
|------|--------|------|-----------------|---------|-------|-----|----------|------------------|---------------|
| REC | | 27/04/21 | Current account | A Jones | 240.00 | 40.00 | 200.00 | Income: Sales | A Jones |

### Split purchase invoice

£1,200 from A Supplier (£1,000 net + £200 VAT) split across two expense accounts. Subsequent rows carry only Analysis, Analysis account, and Entry details. Each Entry details keeps the job number and adds what that line covers:

| Type | Ref No | Date | Primary Account | Details | Total | VAT | Analysis | Analysis account | Entry details |
|------|--------|------|-----------------|---------|-------|-----|----------|------------------|---------------|
| PIN | | 28/04/21 | A Supplier | Job no. 784: 27/04/21 | 1,200.00 | 200.00 | 700.00 | Expenses: Repairs and maintenance | Job no. 784: 27/04/21 - repairs |
| | | | | | | | 300.00 | Expenses: Equipment hire | Job no. 784: 27/04/21 - equipment hire |

### Journal (depreciation)

Two depreciation entries (buildings and equipment). Debits positive, credits negative. No Primary Account, Total, or VAT. Only the first row carries Type, Date, and Details:

| Type | Ref No | Date | Primary Account | Details | Total | VAT | Analysis | Analysis account | Entry details |
|------|--------|------|-----------------|---------|-------|-----|----------|------------------|---------------|
| JRN | | 30/04/21 | | Depreciation - April 2021 | | | 20,000.00 | Expenses: Depreciation | Depreciation of buildings |
| | | | | | | | -20,000.00 | FA - land and buildings: Depn - charge | Depreciation of buildings |
| | | | | | | | 333.33 | Expenses: Depreciation | Depreciation of equipment |
| | | | | | | | -333.33 | FA - equipment, fixtures & fittings: Depn - charge | Depreciation of equipment |
