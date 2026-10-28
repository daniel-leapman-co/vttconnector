# Accounting Basis

VTT+ supports both cash basis and full accruals accounting. The basis determines which transaction types are used and how bank receipts and payments are analysed.

---

## Primary and Analysis accounts for bank transactions

For PAY, CHQ, and REC the Primary Account is **always the bank account name** (e.g. `Current account`). What changes between cash basis and accruals is the **Analysis account**:

| Scenario | Type | Primary Account | Analysis account |
|----------|------|----------------|-----------------|
| Cash basis payment (direct to expense) | PAY / CHQ | `Current account` | `Expenses: [account]` |
| Accruals payment (settling a supplier) | PAY / CHQ | `Current account` | `Suppliers: [Supplier name]` |
| Cash basis receipt (direct to income) | REC | `Current account` | `Income: [account]` |
| Accruals receipt (settling a customer) | REC | `Current account` | `Customers: [Customer name]` |

---

## Cash basis

Income and expenditure are recognised when cash is received or paid. Bank receipts and payments are analysed directly to P&L accounts. No debtor or creditor balances are maintained.

### Transaction types used
- **REC** — cash received
- **PAY / CHQ** — cash paid
- **PCV** — petty cash payment
- **CCV** — credit card payment
- **JRN / RJN** — journals where needed

SIN and PIN are not used under cash basis.

### Examples

**Receipt with VAT** — £240 received from A Jones (£200 net + £40 VAT):

| Type | Ref No | Date | Primary Account | Details | Total | VAT | Analysis | Analysis account | Entry details |
|------|--------|------|-----------------|---------|-------|-----|----------|------------------|---------------|
| REC | | 27/04/21 | Current account | A Jones | 240.00 | 40.00 | 200.00 | Income: Sales | A Jones |

**Payment with VAT** — £72 to The Paper Shop (£60 net + £12 VAT):

| Type | Ref No | Date | Primary Account | Details | Total | VAT | Analysis | Analysis account | Entry details |
|------|--------|------|-----------------|---------|-------|-----|----------|------------------|---------------|
| PAY | | 23/04/21 | Current account | The Paper Shop | 72.00 | 12.00 | 60.00 | Expenses: Stationery and printing | The Paper Shop |

**Payment, no VAT** — £500 wages:

| Type | Ref No | Date | Primary Account | Details | Total | VAT | Analysis | Analysis account | Entry details |
|------|--------|------|-----------------|---------|-------|-----|----------|------------------|---------------|
| PAY | | 05/04/2026 | Current account | Wages April | 500.00 | | 500.00 | Expenses: Wages and salaries | |

---

## Full accruals

Income and expenditure are recognised when invoices are raised or received. Debtor and creditor balances are maintained via the Customers and Suppliers ledgers.

### Invoice entry

Invoices are raised first via SIN or PIN, analysed to the relevant P&L account. No bank account is involved at this stage.

**Sales invoice (SIN)** — £600 to Springsteen Ltd. (£500 net + £100 VAT):

| Type | Ref No | Date | Primary Account | Details | Total | VAT | Analysis | Analysis account | Entry details |
|------|--------|------|-----------------|---------|-------|-----|----------|------------------|---------------|
| SIN | | 18/04/21 | Springsteen Ltd. | IT services - inv 4567 | 600.00 | 100.00 | 500.00 | Income: Sales | IT services - inv 4567 |

**Purchase invoice (PIN)** — £120 from Widgets Ltd. (£100 net + £20 VAT):

| Type | Ref No | Date | Primary Account | Details | Total | VAT | Analysis | Analysis account | Entry details |
|------|--------|------|-----------------|---------|-------|-----|----------|------------------|---------------|
| PIN | | 18/04/21 | Widgets Ltd. | Inv ref: 12345 | 120.00 | 20.00 | 100.00 | Expenses: Repairs and maintenance | Inv ref: 12345 |

### Payment/receipt entry (accruals)

When cash moves, the bank account name is the Primary Account. The Analysis account is the customer or supplier being settled. VAT is left blank — it was accounted for on the invoice.

**Receipt settling a customer (REC)**:

| Type | Ref No | Date | Primary Account | Details | Total | VAT | Analysis | Analysis account | Entry details |
|------|--------|------|-----------------|---------|-------|-----|----------|------------------|---------------|
| REC | | 23/04/21 | Current account | Rec'd payment of inv 4567 | 600.00 | | 600.00 | Customers: Springsteen Ltd. | Rec'd payment of inv 4567 |

**Payment settling a supplier (PAY)**:

| Type | Ref No | Date | Primary Account | Details | Total | VAT | Analysis | Analysis account | Entry details |
|------|--------|------|-----------------|---------|-------|-----|----------|------------------|---------------|
| PAY | | 21/04/21 | Current account | Payment of inv 12345 | 120.00 | | 120.00 | Suppliers: Widgets Ltd. | Payment of inv 12345 |

---

## Key differences at a glance

| | Cash basis | Accruals |
|-|------------|----------|
| Invoice types used | No | Yes (SIN, PIN, SCR, PCR) |
| Analysis account for receipts | P&L income account | `Customers: [name]` |
| Analysis account for payments | P&L expense account | `Suppliers: [name]` |
| VAT on receipts/payments | Possible | Blank (VAT on invoice only) |
| Debtor/creditor balances | None | Maintained via Customers/Suppliers |
