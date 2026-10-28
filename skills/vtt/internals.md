# Internals: the `.vtr` format and the VTA COM API

For maintaining or extending vttconnector. Not needed for ordinary posting work.

## Do not hand-write `.vtr` files

Reading the binary format directly is safe and verified — `vtr.py` does it, and
`vtt check` uses it as an independent cross-check of what VTA reports. **Writing it
is not. Do not build a direct writer.**

The evidence: one two-line journal entered through the VT GUI changed **2,216 bytes
across 28 pages and 20 distinct structures**, several of them never touched by
reading:

- new transaction and entry records, plus high-water counts on 5 directory nodes
- **seven sorted indexes** rebuilt by bulk memmove (Entries/Account, AccountOpen,
  AccountOutstanding, DateNumber; Transactions/Text, Identifier, and a
  per-transaction-type DateNumber/LongRefNumber pair)
- **denormalised cached balances** on both the account and the ledger records, plus
  last-transaction and last-entry pointers per account
- Ledgers and Accounts YearEndArrays
- the phrase book (autocomplete) chunk stream and its MRU index
- Company Properties and VTTranProperties counters

**The worst trap:** posting into a period on or before an existing year end causes
VT to **silently rewrite the year-end transaction's own entries** (observed: a net
profit entry moving from -5,940.60 to -4,940.60). A writer that only appends records
leaves the file internally inconsistent with no error — VT would then display
figures that disagree with its own ledger.

Use a supported write path: VT's Universal Input Sheet (`vtt-import`), or the VTA
COM DLL, which is the documented API and is referenced inside the files themselves.

## The `.vtr` binary format

Notes for maintaining `vtr.py`, which is read-only by design:

- Header `VT Data Storage`, then a tree of 4096-byte pages.
- Directory pages hold 16 node descriptors of 256 bytes: a 128-byte padded name and
  32 uint32 fields. Field `[1]` is the node type, `[3]` the page table, `[4]` the
  first data page, `[7]` a record high-water mark, `[8]` the record size.
- Records live in a flat virtual byte stream mapped onto those pages, so **a record
  can straddle a page boundary**.
- Record numbers and string ids are **1-based**: record *n* starts at virtual offset
  `(n-1) * size`.
- Stream page tables start `0x400` into the table page; record page tables start at
  offset 0.
- Amounts are signed int64 in **ten-thousandths**. Dates are day counts from
  1899-12-30 (the spreadsheet epoch).
- Built-in account names are GlobalStrings ids. User-created accounts carry a
  **negative** name id, resolved through the first phrase book chunk stream.

## VTA COM API traps

Dump the real signature of anything in the object model rather than probing with
`Get-Member`:

```bash
/mnt/c/Windows/SysWOW64/WindowsPowerShell/v1.0/powershell.exe \
  -ExecutionPolicy Bypass -File dumptlb.ps1 -Types _Transaction,_Entries
```

- `Transaction.Entry(account)` is a **finder** and returns null. `Entries.Add(account)`
  is the creator.
- `Entry.Value` is a parameterised property — use `Entry.BaseValue`.
- `Company.NewTransaction` takes a `VtaTranTypeTask` enum that does **not** match
  transaction type indexes (task 9 is Reversing Journal, not Journal). Go via
  `TranType.NewTransaction` instead.
- `Account.Parent.Name` gives the ledger.
- `Ledger.IsPL` classifies P&L versus balance sheet. Do not infer it from year-end
  entries — VT's year end also moves fixed-asset cost and disposals.
- `Ledger.ListType` is set only on customer/supplier control ledgers, so its presence
  is the reliable test for one. (`Ledger.CreditTerm` is related.)
- The second argument to `Account.Value` is `IncludeClosingYearEnd`. `vtt` passes
  false, which is why a trial balance at the year-end date shows the year's P&L
  rather than the position after the sweep to reserves.
- `Company.Verify()` requires the file to be open for writing.
- `OpenCompany` with `readOnly = false` rewrites housekeeping even under a rollback —
  see the dry-run section of [connector.md](connector.md).

VAT has its own set of traps and its own file: [vat.md](vat.md).
