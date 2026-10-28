# Chart of Accounts — default, fallback only

> **This is VT's default chart, not any particular client's.** Where the client's
> `.vtr` file is available, read the real chart from it instead:
>
> ```bash
> vtt chart "/mnt/c/.../Client.vtr" --format markdown --with-precedent 6
> ```
>
> Charts get edited — accounts renamed, added, or deleted — and an account name
> that is not in the file is rejected on import. The live chart also carries
> usage counts and prior narratives, which is what lets a line be coded from the
> client's own precedent. Use this file only when the `.vtr` cannot be reached,
> and say so, because that coding needs checking against the file before import.
>
> `vtt chart` prints `Ledger|Account`; the UIS wants `Ledger: Account`.

Accounts are referenced in the format `Ledger: Account`.

The "Within VAT scope?" column indicates whether transactions posted to that account can carry a non-zero VAT amount.

---

## Income

| Account | VAT scope |
|---------|-----------|
| Income: Fees | yes |
| Income: Interest receivable | |
| Income: Investment income | |
| Income: Other operating income | yes |
| Income: Sales | yes |

## Cost of sales

| Account | VAT scope |
|---------|-----------|
| Cost of sales: Carriage | yes |
| Cost of sales: Commissions payable | yes |
| Cost of sales: Decrease/(increase) in stocks | yes |
| Cost of sales: Direct labour | |
| Cost of sales: Discounts allowed | yes |
| Cost of sales: Other | yes |
| Cost of sales: Purchases | yes |
| Cost of sales: Subcontractor costs | yes |

## Expenses

| Account | VAT scope |
|---------|-----------|
| Expenses: Accountancy fees | yes |
| Expenses: Advertising and PR | yes |
| Expenses: Amortisation of goodwill | yes |
| Expenses: Audit fees | yes |
| Expenses: Awards, Marketing | yes |
| Expenses: Bad debts | yes |
| Expenses: Bank charges | yes |
| Expenses: Bonuses | |
| Expenses: Bookkeeping expenses | yes |
| Expenses: Charitable donations | yes |
| Expenses: Cleaning | yes |
| Expenses: Consultancy fees | yes |
| Expenses: Courier services | yes |
| Expenses: Depreciation | yes |
| Expenses: Directors salaries | |
| Expenses: Employers NI | |
| Expenses: Entertaining | yes |
| Expenses: Equipment expensed | yes |
| Expenses: Equipment hire | yes |
| Expenses: Exchange differences & charges | yes |
| Expenses: Gain/loss on disposal | yes |
| Expenses: Gain/loss on revaluation of current asset investments - listed | |
| Expenses: Gain/loss on revaluation of current asset investments - unlisted | |
| Expenses: Gain/loss on revaluation of fixed asset investments | |
| Expenses: Information and publications | yes |
| Expenses: Insurance | yes |
| Expenses: Interest - bank | |
| Expenses: Interest - leases & HP | |
| Expenses: Interest - other | |
| Expenses: Legal & professional | yes |
| Expenses: Light and heat | yes |
| Expenses: Management fees | yes |
| Expenses: Motor expenses | yes |
| Expenses: Non-equity dividends | |
| Expenses: Other legal and prof | yes |
| Expenses: Other legal and professional | yes |
| Expenses: P/L on disposal of investments | |
| Expenses: P/L on disposal of land and buildings | yes |
| Expenses: P/L on disposal of plant and machinery | yes |
| Expenses: Pensions | yes |
| Expenses: Postage | yes |
| Expenses: Practice expenses | yes |
| Expenses: Rates | |
| Expenses: Rent | yes |
| Expenses: Repairs and maintenance | yes |
| Expenses: Service charges | yes |
| Expenses: Software | yes |
| Expenses: Solicitors fees | yes |
| Expenses: Staff training & welfare | yes |
| Expenses: Stationery and printing | yes |
| Expenses: Subscriptions | yes |
| Expenses: Sundry | yes |
| Expenses: SUSPENSE | yes |
| Expenses: Telephone and fax | yes |
| Expenses: Temps and recruitment | yes |
| Expenses: Travel and subsistence | yes |
| Expenses: Use of home | yes |
| Expenses: Wages and salaries | |
| Expenses: Write backs/discounts | yes |
| Expenses: Write offs/discounts | yes |

## Other expenses

| Account | VAT scope |
|---------|-----------|
| Other expenses: EOT Payments | yes |

## Taxation

| Account | VAT scope |
|---------|-----------|
| Taxation: Corporation tax | |
| Taxation: Corporation tax - deferred tax | |
| Taxation: Corporation tax - prior year adjustment | |

## Fixed assets — intangible

| Account | VAT scope |
|---------|-----------|
| FA - intangible: Amortisation - b/fwd | |
| FA - intangible: Amortisation - charge | |
| FA - intangible: Amortisation - disposals | |
| FA - intangible: Cost - b/fwd | |
| FA - intangible: Cost - additions | yes |
| FA - intangible: Cost - disposals | yes |

## Fixed assets — land and buildings

| Account | VAT scope |
|---------|-----------|
| FA - land and buildings: Cost - b/fwd | |
| FA - land and buildings: Cost - additions | yes |
| FA - land and buildings: Cost - disposals | yes |
| FA - land and buildings: Cost - revaluation | |
| FA - land and buildings: Depn - b/fwd | |
| FA - land and buildings: Depn - charge | |
| FA - land and buildings: Depn - disposals | yes |
| FA - land and buildings: Depn - revaluation | |

## Fixed assets — plant and machinery

| Account | VAT scope |
|---------|-----------|
| FA - plant and machinery: Cost - b/fwd | |
| FA - plant and machinery: Cost - additions | yes |
| FA - plant and machinery: Cost - disposals | yes |
| FA - plant and machinery: Depn - b/fwd | |
| FA - plant and machinery: Depn - charge | |
| FA - plant and machinery: Depn - disposals | yes |

## Fixed assets — equipment, fixtures & fittings

| Account | VAT scope |
|---------|-----------|
| FA - equipment, fixtures & fittings: Cost - b/fwd | |
| FA - equipment, fixtures & fittings: Cost - additions | yes |
| FA - equipment, fixtures & fittings: Cost - disposals | yes |
| FA - equipment, fixtures & fittings: Depn - b/fwd | |
| FA - equipment, fixtures & fittings: Depn - charge | |
| FA - equipment, fixtures & fittings: Depn - disposals | yes |

## Fixed assets — vehicles

| Account | VAT scope |
|---------|-----------|
| FA - vehicles: Cost - b/fwd | |
| FA - vehicles: Cost - additions | yes |
| FA - vehicles: Cost - disposals | yes |
| FA - vehicles: Depn - b/fwd | |
| FA - vehicles: Depn - charge | |
| FA - vehicles: Depn - disposals | yes |

## Investments — fixed

| Account | VAT scope |
|---------|-----------|
| Investments - fixed: Listed - b/fwd | |
| Investments - fixed: Listed - additions | |
| Investments - fixed: Listed - disposals | |
| Investments - fixed: Listed - revaluation | |
| Investments - fixed: Subsidiaries - b/fwd | |
| Investments - fixed: Subsidiaries - additions | |
| Investments - fixed: Subsidiaries - disposals | |
| Investments - fixed: Subsidiaries - revaluation | |
| Investments - fixed: Unlisted - b/fwd | |
| Investments - fixed: Unlisted - additions | |
| Investments - fixed: Unlisted - disposals | |
| Investments - fixed: Unlisted - revaluation | |

## Investments — current

| Account | VAT scope |
|---------|-----------|
| Investments - current: Listed | |
| Investments - current: Unlisted | |

## Stocks

| Account | VAT scope |
|---------|-----------|
| Stocks: Finished goods | yes |
| Stocks: Long term contract balances | yes |
| Stocks: Payments received on account | yes |
| Stocks: Raw materials | yes |
| Stocks: Work in progress | yes |

## Customers

Individual customer accounts live under the Customers ledger.
Format: `Customers: [Customer name]`

Use this as the Primary Account for SIN, SCR, and REC transactions. VT automatically aggregates all Customers balances into `Debtors: Trade debtors` on the trial balance — do not use Trade debtors as a Primary Account.

## Debtors

| Account | VAT scope |
|---------|-----------|
| Debtors: Accrued income | |
| Debtors: Bad debt provision | |
| Debtors: Credit card | |
| Debtors: Director's account | |
| Debtors: Long term contracts | |
| Debtors: Prepayments | |
| Debtors: Staff loans | |
| Debtors: Sundry | |
| Debtors: Trade debtors | |
| Debtors: Translation differences | |
| Debtors: Work in progress | |

## Bank

| Account | VAT scope |
|---------|-----------|
| Bank: Current account | |
| Bank: Deposit account | |
| Bank: Deposit account 2 | |
| Bank: Petty cash | |

## Suppliers

Individual supplier accounts live under the Suppliers ledger.
Format: `Suppliers: [Supplier name]`

Use this as the Primary Account for PIN, PCR, PAY, and CHQ transactions. VT automatically aggregates all Suppliers balances into `Creditors: Trade creditors` on the trial balance — do not use Trade creditors as a Primary Account.

The following is a named account under Suppliers:

| Account | VAT scope |
|---------|-----------|
| Suppliers: Credit card company | |

## Creditors

| Account | VAT scope |
|---------|-----------|
| Creditors: Accruals | |
| Creditors: Accruals - preference dividend | |
| Creditors: ACT payable | |
| Creditors: Bank loans < 1 year | |
| Creditors: Bank loans > 1 year | |
| Creditors: Corporation tax | |
| Creditors: Credit card | |
| Creditors: Deferred income | |
| Creditors: Director's account | |
| Creditors: Leases & HP < 1 year | |
| Creditors: Leases & HP > 1 year | |
| Creditors: Long term contracts | |
| Creditors: Net VAT due | |
| Creditors: Net Wages | |
| Creditors: Non-equity preference shares | |
| Creditors: Opening balances contra | |
| Creditors: PAYE and NI | |
| Creditors: Pension fund | |
| Creditors: Proposed dividends | |
| Creditors: Sundry | |
| Creditors: SUSPENSE | |
| Creditors: Trade creditors | |
| Creditors: VAT - Deferred input | |
| Creditors: VAT - Deferred output | |
| Creditors: VAT - EC acquisitions | |
| Creditors: VAT - Input | |
| Creditors: VAT - Output | |
| Creditors: Wages and Salaries Control | |

## Deferred tax

| Account | VAT scope |
|---------|-----------|
| Deferred tax: Brought forward | |
| Deferred tax: Charged to other comprehensive income | |
| Deferred tax: Charged to profit and loss account | |

## Share capital

| Account | VAT scope |
|---------|-----------|
| Share capital: Brought forward | |
| Share capital: Shares issued | |
| Share capital: Shares redeemed | |

## Share premium

| Account | VAT scope |
|---------|-----------|
| Share premium: Brought forward | |
| Share premium: Expenses of issue | |
| Share premium: On shares issued | |

## Revaluation reserve

| Account | VAT scope |
|---------|-----------|
| Revaluation reserve: Brought forward | |
| Revaluation reserve: Deferred taxation arising on the revaluation of land and buildings | |
| Revaluation reserve: Gain on revaluation of land and buildings | |

## Profit and loss account

| Account | VAT scope |
|---------|-----------|
| Profit and loss account: Brought forward | |
| Profit and loss account: Direct payments to EOT | |
| Profit and loss account: Equity dividends | |
