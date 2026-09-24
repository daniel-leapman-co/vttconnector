# vttconnector

Command line access to VT Transaction+ (`.vtr`) ledger files — read the data out,
post transactions in.

Writes go through VT's own COM API (**VTA — VT Accounting Objects**), so VT
maintains its indexes, cached balances and year-end postings exactly as it does
when you type into the GUI. There is also an independent read-only parser of the
`.vtr` binary format, used to cross-check what VTA reports.

```
./vtt tb      Client.vtr --date 2026-06-30
./vtt post    Client.vtr --date 2026-06-30 --text "June rent" \
              --line "Expenses|Rent=1200.00" --line "Bank|Current account=-1200.00" --commit
```

---

Claude Code skills that drive this tool — `vtt`, `vtt-post` and `vtt-import` —
live in a separate repository, [claude-skills][skills], cloned to
`~/.claude/skills`.

[skills]: https://github.com/daniel-leapman-co/claude-skills

---

## Requirements

* WSL on a machine with VT Transaction+ installed.
* `VTA.dll` registered on the Windows host. It already is if VT Transaction+ is
  installed — check with `reg.exe query "HKCR\VTA.Company"`.
* Nothing to install on the Linux side; standard library only.

VTA is a **32-bit** in-process COM server, so the connector drives it through
`C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe`. That is handled for
you.

COM cannot open files on the Linux side of WSL. Files under `/mnt/...` are used
in place; anything else is staged to `C:\Temp\vtaconnect`, and copied back **only
when a post is committed**.

---

## Commands

Add `--json` to any command for machine-readable output.

### `vtt info FILE`

Company name, VAT number, current year end, **lock date**, counts, and the
transaction type codes available for `--type`.

The lock date matters before posting: VT rejects transactions dated on or before
it.

### `vtt accounts FILE [--search TEXT]`

Lists every account with its ledger. Use this to find the exact account names
`post` expects.

### `vtt chart FILE [--format markdown|json] [--min-usage N] [--with-precedent N]`

The chart of accounts with enough context to *choose between* accounts: whether each
is P&L or balance sheet, how often it has been used, when it was last used, its
balance, and the narratives that have been coded to it before.

By default it shows only accounts that have actually been used — VT ships around 170
standard accounts and most files use a few dozen. `--min-usage 0` shows everything.

Prior narratives are the strongest coding signal, so they are drawn from real
transactions (payments, receipts) in preference to journals, whose text tends to be
bookkeeping shorthand like "TB 2022" rather than anything about the transaction.

Year-end entries are excluded from the counts entirely; they are VT's own
bookkeeping, not a precedent.

Accounts in a customer or supplier control ledger are marked `*`. Post to the
customer or supplier, not to the account.

```
./vtt chart Client.vtr --format markdown --with-precedent 6 > chart.md
```

`--format markdown` is designed to be pasted into a prompt; `--format json` for
programmatic use.

### `vtt tb FILE [--date YYYY-MM-DD]`

Trial balance, as a debit/credit table with totals. Warns if it does not sum to
zero.

### `vtt balance FILE --account TEXT [--date YYYY-MM-DD]`

The book value of one account (or a few) at a date — a single figure to diff
against a statement, before and after posting. `--account` is a case-insensitive
fragment of `Ledger|Account`, so `--account "Bank|Current"` or `--account lloyds`
both work; if the fragment matches several accounts they are listed with a total.

The balance comes from the same VTA trial balance the GUI shows, so it already
excludes the closing year end. `--json` returns the matched accounts and the total.

```
$ ./vtt balance Client.vtr --account "Bank|Current account" --date 2026-06-30
Bank|Current account                       12,345.67
```

### `vtt entries FILE [--account TEXT] [--from DATE] [--to DATE] [--tail N]`

Every entry as CSV on stdout:
`date,type,ref,ledger,account,text,amount,vat_net,in_scope`.

`vat_net` is filled on a VAT entry and is the net amount behind that VAT — what
boxes 6 and 7 of the return are analysed from. `in_scope` marks the net lines it
was derived from. A VAT entry with an empty `vat_net` is the defect described
under [VAT](#vat) and will be missing from boxes 6/7.

`--account` filters to a `Ledger|Account` name fragment (same matching as
`balance`). `--tail N` keeps only the last N rows after sorting — so
`--account lloyds --tail 5` is "the last five things on the Lloyds account".

### `vtt post FILE ...`

See [Posting](#posting) below.

### `vtt check FILE [--date DATE] [--against REPORT.txt]`

Reconciles the trial balance from VTA against the independent binary parser, and
optionally against a VT trial balance report saved as tab separated text. Exits
non-zero on any mismatch, so it works as a sanity gate in a script.

```
$ ./vtt check Client.vtr --date 2026-06-30 --against tb.txt
...
17/17 lines agree across VTA, parser, report
```

---

## Posting

**Posting is a dry run unless you pass `--commit`.**

A dry run is not a simulation — it builds the transaction and calls VT's `Post()`
inside a `BeginTrans`/`RollbackTrans` pair, then rolls back. You get the same
errors a real post would give, and no accounting data is changed: the trial
balance and every entry are identical afterwards.

The **file bytes are not identical**, though. Opening a company for write makes
VT rewrite some internal housekeeping regardless of the rollback — repeated
identical dry runs flip the file between two states — so a dry run will show up
as a modification to OneDrive, a backup tool, or a checksum. Compare `vtt tb` or
`vtt entries` output, not hashes, to confirm nothing moved.

Amounts are signed: **positive debit, negative credit**. Each transaction must
sum to zero — counting any VAT, which is posted as an entry of its own; the CLI
checks this before calling VT, and VT checks it again. See [VAT](#vat).

The **first line of a transaction becomes its primary entry**, so on a `PAY`,
`REC` or `CCP` put the bank or control account first. VT will not accept a VAT
flag on a transaction that has no primary entry yet.

Accounts are named `Account` or, where the name appears in more than one ledger,
`Ledger|Account`. Account names are only unique per ledger, so prefer the second
form.

`--type` takes a transaction type code (`JRN`, `PAY`, `REC`, `SIN`, …) and
defaults to `JRN`. `vtt info` lists the codes.

If you omit `--ref`, VT allocates the next reference for that type.

### Three input forms

**Inline**, for a single transaction:

```bash
./vtt post Client.vtr --date 2026-06-30 --type JRN --text "June rent" \
  --line "Expenses|Rent=1200.00:rent for June" \
  --line "Bank|Current account=-1200.00" \
  --commit
```

`--line` is `ACCOUNT=AMOUNT[@VAT][:NARRATIVE]`, repeated once per line.

**CSV**, for batches:

```csv
date,type,ref,text,account,amount,vat,line_text
2026-06-30,JRN,,Payroll June,Expenses|Directors salaries,5000.00,,gross pay
2026-06-30,JRN,,Payroll June,Creditors|PAYE and NI,-1200.00,,paye
2026-06-30,JRN,,Payroll June,Bank|Current account,-3800.00,,net pay
2026-06-30,JRN,,Bank interest,Bank|Deposit account,15.40,,
2026-06-30,JRN,,Bank interest,Income|Interest receivable,-15.40,,
```

Consecutive rows sharing `date`/`type`/`ref`/`text` form **one** transaction, so
the file above posts two journals. `type`, `ref`, `vat` and `line_text` may be
blank. The `vat` column may be omitted entirely on a file with no VAT.

```bash
./vtt post Client.vtr --csv batch.csv          # dry run
./vtt post Client.vtr --csv batch.csv --commit
```

A path of `-` for `--csv` or `--json-file` reads the batch from stdin, for
piping. The file form is preferred where you want the batch kept as an artefact
of what was posted:

```bash
cat batch.csv        | ./vtt post Client.vtr --csv -       --commit
some-generator-json  | ./vtt post Client.vtr --json-file - --commit
```

**JSON**, for programmatic use:

```json
[{ "type": "JRN", "date": "2026-06-30", "text": "June rent",
   "lines": [{ "account": "Expenses|Rent", "amount": 1200.00, "text": "rent for June" },
             { "account": "Bank|Current account", "amount": -1200.00 }] }]
```

```bash
./vtt post Client.vtr --json-file journal.json --commit
```

### Details and entry details

VT keeps two narratives, and they are read in different places:

* **Details** (`text` on the transaction) titles the whole transaction — who it
  was with and what for. It is what you see in the transaction list.
* **Entry details** (`line_text` on a line) is what appears against that line
  when you open a single account's ledger, where the rest of the transaction is
  not on screen.

Because an entry detail is read on its own, it has to carry the transaction's
details and then qualify them — "insurance" against the rent account tells you
nothing about whose insurance or which invoice. So `line_text` is treated as a
**qualifier, not a replacement**: it is appended to the transaction details,
unless it already contains them.

```csv
date,type,ref,text,account,amount,vat,line_text
2026-07-20,PAY,,14 GIS Ltd inv 2401 (July),Cash book|Current account,-3420.52,,
2026-07-20,PAY,,14 GIS Ltd inv 2401 (July),Expenses|Other business expenses,2000.00,400.00,variable contributions 14%
2026-07-20,PAY,,14 GIS Ltd inv 2401 (July),"Expenses|Rent, power and insurance costs",850.43,170.09,fixed rent
```

posts entry details of `14 GIS Ltd inv 2401 (July) - variable contributions 14%`
and `14 GIS Ltd inv 2401 (July) - fixed rent`.

**Leave `line_text` blank on an ordinary payment, receipt or invoice.** With one
analysis line there is nothing to distinguish, so the entry details should simply
be the details; VT copies them down itself. Reach for `line_text` when a
transaction splits across more than one account and the lines need telling apart.

### VAT

**Never write the VAT as a line of its own.** Put the net on the expense or
income line and its VAT in that line's `vat` field:

```csv
date,type,ref,text,account,amount,vat,line_text
2026-07-15,PAY,,Chambers account inv 2323,Cash book|Current account,-1200.00,,
2026-07-15,PAY,,Chambers account inv 2323,Expenses|Other business expenses,1000.00,200.00,
2026-07-17,CCP,,IAP TRAINLINE LONDON,Suppliers|HSBC credit card,-38.00,,
2026-07-17,CCP,,IAP TRAINLINE LONDON,"Expenses|Car, van and travel expenses",38.00,0.00,
```

The `amount` is always the **net**; the `vat` is signed the same way as the net
it belongs to (both debits on a purchase, both credits on a sale), and a
transaction balances on **net plus VAT**. Splits work: give each net line its own
`vat` and VT posts a single VAT entry for their total.

Three states, and the difference between the last two is not cosmetic:

| `vat` | Meaning | On the return |
| --- | --- | --- |
| `20.00` | standard-rated | boxes 1/4 **and** 6/7 |
| `0.00` | zero-rated or exempt, still a VAT supply | boxes 6/7 only |
| *(blank)* | outside the scope of VAT | not on the return |

**Why it has to be done this way.** VT owns the VAT entry. Flagging a net line as
within VAT scope is what makes VT create it, and only VT can populate that
entry's `VATTurnoverValue` — the net figure boxes 6 and 7 are analysed from,
which is not assignable through the API. A VAT line written by hand posts to the
right account and balances, and boxes 1 to 5 come out right, so nothing looks
wrong; but it carries no net, and boxes 6 and 7 are quietly understated by the
whole of it. Posting directly to the input or output VAT account on a
VAT-bearing transaction type is therefore refused.

`JRN` and the other types where `HasVATEntries` is false cannot carry VAT at
all — a `vat` on one of those is an error, not a silent omission. Use `PAY`,
`REC` or `CCP`.

### Safety

* Dry run by default; `--commit` is required to write.
* A timestamped backup (`NAME.YYYYmmdd-HHMMSS.bak.vtr`) is taken next to the file
  before every commit, unless you pass `--no-backup`.
* Everything runs inside one VT transaction. If any line of any transaction
  fails, the whole batch is rolled back.
* After committing, `Company.Verify()` is run; a non-zero result is reported and
  the CLI exits non-zero.
* These backups accumulate fast during any multi-step posting session (batch
  testing, bisection, etc.) and are easy to mistake for the live file since they
  still end in `.vtr`. Once a posting session is done and the result has been
  verified (`vtt tb`, `vtt check`, a reconciliation against source statements),
  move the backups out of the working folder into their own subfolder and rename
  the extension from `NAME.<timestamp>.bak.vtr` to `NAME.<timestamp>.vtr.bak` —
  swapping the order so the file's actual extension is `.bak`. That stops Windows/VT
  from associating the file with the VT app (no accidental double-click-to-open),
  while `vtr` stays visible in the name for identification. Restoring one is just
  stripping the trailing `.bak` and copying it back over the live file.

### Year ends

Posting into a period on or before an existing year end causes VT to restate the
year-end transaction, exactly as it does in the GUI. This is intended behaviour —
it is why the year end can be re-run freely — but it means a back-dated posting
changes prior-period figures. Run `vtt tb` for the affected dates afterwards if
that matters.

---

## Editing posted transactions

```
vtt show FILE (--id N | --type PAY --ref N | --date D [--text T] [--amount G])
vtt edit FILE <same selector> [changes] [--force] [--commit]
```

`show` lists a transaction's lines numbered as `edit --line` expects, with
`prim` (bank or control side), `VAT` (VT's own VAT entry) and flags for
`IN VAT RETURN` and `LOCKED`. `edit` is a dry run unless `--commit`, and prints
before/after with changed lines starred. A selector must match exactly one
transaction; if several match, they are listed.

| Change | Flag | Notes |
| --- | --- | --- |
| Recode a line | `--account A` | Account name or unique fragment; ambiguous fragments list candidates |
| Change VAT | `--vat 20%` / `5%` / `0` / `1.00` / `none` | Re-splits the line's gross into net + VAT. Gross and bank line unchanged |
| Split a line | `--split "A=2.50[:text]"` (repeatable) | Moves the amount onto a new line; inherits VAT scope |
| Text / notes / date | `--set-text`, `--line-text`, `--notes`, `--set-date` | |
| Which line | `--line N` or `--line fragment` | Default: the only coded line |
| Batch | `--json-file F` | List of `vtaconnect.edit` specs, one VT transaction, all or nothing |

**Refused:** the primary (bank/control) line of a PAY/REC/invoice; VT's VAT
entry; recoding *to* the VAT/net-VAT-due accounts; VT-generated types (YET,
VAT, CLR …); VAT changes or splits on a transaction in a posted VAT return (VT
also refuses these); `--vat` when another line is also within VAT scope.

**Soft-blocked:** anything dated — or moved to — on or before the lock date.
VT does **not** enforce the lock date through COM, so `vtt` does; `--force`
overrides it and records a warning.

**Allowed on a VAT-return transaction:** recoding and text edits. The return's
figures are unaffected (checked: return total identical after a recode).

After every edit, before commit, the transaction is re-checked: it balances,
the primary entry is unchanged, the VAT is unchanged unless `--vat` was given,
and the VAT entry's net equals the sum of in-scope lines. Any failure rolls back
the whole batch. `--commit` also runs `Verify()` and takes a backup as `post`
does. Year-end postings re-derive themselves, as with a back-dated post.

---

## Adding accounts

```
vtt add-account FILE --ledger L --name N [--code C] [--vat-scope yes|no] [--notes T] [--commit]
vtt add-account FILE --json-file accounts.json [--commit]
```

Creates the account through VT (`Ledger.Accounts.Add`). Dry run unless
`--commit`, which backs up the file and runs `Verify()`. A JSON batch is a list
of `{"ledger", "name", "code"?, "vatScope"?, "notes"?}` and is all or nothing.

* `--ledger` is an exact ledger name or a fragment matching exactly one;
  otherwise the candidates (or all ledgers) are listed.
* **Refused:** a name already in that ledger (VT compares names ignoring case),
  an empty name, a name containing `|` (it would break `Ledger|Account`), and an
  account code already in use anywhere in the file.
* A name that exists in a *different* ledger is allowed, with a warning to refer
  to the new one as `Ledger|Account`.
* **VAT scope default.** VT creates accounts with "new entries within VAT scope"
  off, whereas most P&L accounts on a VAT-registered file have it on. Unless
  `--vat-scope` is given, the new account follows the majority of its ledger.
  This only affects entry typed in the VT GUI; `vtt post` sets scope per line.

---

## Files

| File | What it is |
| --- | --- |
| `vtt` | The CLI. Start here. |
| `vtaconnect.py` | Python wrapper: WSL↔Windows interop, path staging, JSON. Importable as a library (`info`, `accounts`, `entries`, `trial_balance`, `post`, `show`, `edit`, `add_account`). |
| `vta.ps1` | The COM layer. Runs under 32-bit PowerShell; not called directly. |
| `vtr.py` | Independent read-only parser of the `.vtr` binary format. No Windows needed. Used by `vtt check`. |
| `dumptlb.ps1` | Dumps VTA interface signatures from the type library. Useful when extending `vta.ps1`. |
| `PLAN.md` | Design for the agent-assisted bank posting pipeline. `vtt chart` is built; the `vtt bank …` stages are not. |

### Extending `vta.ps1`

To find the real signature of anything in the VTA object model:

```bash
/mnt/c/Windows/SysWOW64/WindowsPowerShell/v1.0/powershell.exe \
  -ExecutionPolicy Bypass -File dumptlb.ps1 -Types _Transaction,_Entries
```

Some API traps worth knowing:

* `Transaction.Entry(account)` is a *finder* and returns null. `Entries.Add(account)`
  is the creator.
* `Entry.Value` is a parameterised property; use `Entry.BaseValue`.
* `Company.NewTransaction` takes a `VtaTranTypeTask` enum that does **not** match
  transaction type indexes (task 9 is Reversing Journal, not Journal). Go via
  `TranType.NewTransaction` instead.
* `Account.Parent.Name` gives the ledger.
* `Ledger.IsPL` classifies P&L versus balance sheet. Do not infer it from year-end
  entries — VT's year end also moves fixed asset cost and disposals.
* `Ledger.ListType` is set only on customer/supplier control ledgers, so its presence
  is the reliable test for one.
* The second argument to `Account.Value` is `IncludeClosingYearEnd`. We pass false,
  which is why a trial balance at the year-end date shows the year's P&L rather than
  the position after the year end has been swept to reserves.
* `Company.Verify()` requires the file to be open for writing.

---

## The `.vtr` format

`vtr.py` reads the format directly, with no VT software. Notes for anyone
maintaining it:

* Header `VT Data Storage`, then a tree of 4096-byte pages.
* Directory pages hold 16 node descriptors of 256 bytes: a 128-byte padded name
  and 32 uint32 fields. Field `[1]` is the node type, `[3]` the page table, `[4]`
  the first data page, `[7]` a record high-water mark, `[8]` the record size.
* Records live in a flat virtual byte stream mapped onto those pages, so **a
  record can straddle a page boundary**.
* Record numbers and string ids are **1-based**: record *n* starts at virtual
  offset `(n-1) * size`.
* Stream page tables start `0x400` into the table page; record page tables start
  at offset 0.
* Amounts are signed int64 in **ten-thousandths**. Dates are day counts from
  1899-12-30 (the spreadsheet epoch).
* Built-in account names are GlobalStrings ids. User-created accounts carry a
  **negative** name id, resolved through the first phrase book chunk stream.

The parser is read-only by design. Do not extend it to write: a single two-line
journal entered through the GUI changed 2,216 bytes across 28 pages and 20
structures, including seven sorted indexes, denormalised balances cached on both
account and ledger records, and a silent restatement of the year-end
transaction's own entries. Use VTA for writes.
