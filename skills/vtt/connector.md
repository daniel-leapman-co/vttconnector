# The `vtt` connector

Command line access to `.vtr` files. Reads through both VT's COM API (VTA) and an
independent binary parser; writes only through VTA.

- **Binary:** `vtt`, on PATH. Source and full docs in `~/tools/vttconnector`
  (`README.md`), which is authoritative if it disagrees with this file.
- Run it from anywhere — the client's folder is fine. Give the `.vtr` path
  absolute and **quoted**; these filenames have spaces.
- `--json` on any command gives machine-readable output.

## Environment

The connector runs on Linux under WSL but VTA runs on the Windows host, so a few
constraints leak through:

- **`VTA.dll` is already registered** by the VT Transaction+ installer at
  `C:\Windows\SysWow64\VTA.dll`. No `regsvr32`. Check with
  `reg.exe query "HKCR\VTA.Company"`.
- **VTA is 32-bit**, so it must be driven from
  `C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe`. Handled for you.
- **COM cannot open files on the Linux side of WSL.** Files already under
  `/mnt/...` are used in place — so a client file on OneDrive is read directly —
  and anything else is staged to `C:\Temp\vtaconnect` and copied back **only on
  commit**.
- **Encoding.** Redirected PowerShell stdout defaults to the OEM code page and
  used to throw `UnicodeDecodeError` on accented narratives. `vta.ps1` now forces
  UTF-8 and `vtaconnect.py` decodes with a cp1252/cp850 fallback. If a new client
  file suddenly fails to export, suspect this.
- **The file must be closed in VT.** Any post, dry run included, opens the company
  for write and fails with *"Write access denied. File may be read-only or already
  open."* Ask the user to close VT and retry.

Nothing is installed on the Linux side; standard library only.

## Reading

### `vtt info FILE`
Company name, VAT number and registration status, current year end, **lock date**,
record counts, and the transaction type codes valid for `--type`.

Run this first. The lock date and the year end are what constrain the dates you
can post.

### `vtt accounts FILE [--search TEXT]`
Every account with its ledger. Use it to find the exact name `post` expects.

### `vtt chart FILE [--format markdown|json] [--min-usage N] [--with-precedent N]`
The chart of accounts *with enough context to choose between accounts*: P&L vs
balance sheet, usage count, last used, balance, and the narratives previously
coded to each account.

- Shows only accounts that have actually been used by default. VT ships ~170
  standard accounts and most files use a few dozen. `--min-usage 0` shows all.
- Prior narratives are drawn from real transactions in preference to journals —
  journal text is bookkeeping shorthand ("TB 2022", "From the sheet") and useless
  for deciding where a bank payment belongs.
- Year-end entries are excluded from the counts; they are VT's own bookkeeping,
  not precedent.
- Control-ledger accounts are marked `*`. Post to the supplier or customer, not to
  a P&L account.
- `--format markdown` is designed to be pasted into a prompt.

### `vtt tb FILE [--date YYYY-MM-DD]`
Trial balance as a debit/credit table with totals; warns if it does not sum to zero.

### `vtt balance FILE --account TEXT [--date YYYY-MM-DD]`
Book value of one account (or a few) at a date — the single figure to diff against
a statement before and after posting. `--account` is a case-insensitive fragment of
`Ledger|Account`, so `"Bank|Current"` and `lloyds` both work; several matches are
listed with a total.

Comes from the same VTA trial balance the GUI shows, so it already excludes the
closing year end.

### `vtt entries FILE [--account TEXT] [--from DATE] [--to DATE] [--tail N]`
Every entry as CSV on stdout:
`date,type,ref,ledger,account,text,amount,vat_net,in_scope`.

`vat_net` is filled on a VAT entry and is the net behind that VAT — what boxes 6
and 7 are analysed from. `in_scope` marks the net lines it was derived from. **A
VAT entry with an empty `vat_net` is the defect in [vat.md](vat.md)** and will be
missing from boxes 6/7.

`--tail N` keeps the last N rows after sorting, so `--account lloyds --tail 5` is
"the last five things on the Lloyds account".

### `vtt check FILE [--date DATE] [--against REPORT.txt]`
Reconciles the VTA trial balance against the independent binary parser, and
optionally against a VT trial balance report saved as tab-separated text. Exits
non-zero on any mismatch, so it works as a gate in a script.

## Posting

**A dry run unless `--commit` is passed.**

Amounts are signed: **positive debit, negative credit**, and each transaction must
sum to zero *counting VAT*, which VT posts as an entry of its own. The CLI checks
this before calling VT and VT checks it again.

The **first line of a transaction becomes its primary entry**, so on a `PAY`, `REC`
or `CCP` put the bank or control account first — VT will not accept a VAT flag on a
transaction with no primary entry yet.

Accounts are named `Account`, or `Ledger|Account` where the name appears in more
than one ledger. Names are only unique per ledger, so prefer the second form.
`--type` defaults to `JRN`; omitting `--ref` lets VT allocate the next reference.

### Three input forms

**Inline**, one transaction — `--line` is `ACCOUNT=AMOUNT[@VAT][:NARRATIVE]`:

```bash
vtt post "Client.vtr" --date 2026-06-30 --type JRN --text "June rent" \
  --line "Expenses|Rent=1200.00:rent for June" \
  --line "Bank|Current account=-1200.00" --commit
```

**CSV**, for batches — `date,type,ref,text,account,amount,vat,line_text`.
Consecutive rows sharing `date`/`type`/`ref`/`text` form **one** transaction.
`type`, `ref`, `vat` and `line_text` may be blank, and the `vat` column may be
omitted entirely on a non-VAT file. Full column reference and worked examples live
in `vtt-post`'s `batch-format.md`.

**JSON**, for programmatic use:

```json
[{ "type": "JRN", "date": "2026-06-30", "text": "June rent",
   "lines": [{ "account": "Expenses|Rent", "amount": 1200.00, "text": "rent for June" },
             { "account": "Bank|Current account", "amount": -1200.00 }] }]
```

A path of `-` for `--csv` or `--json-file` reads from stdin. Prefer a real file
where the batch should survive as the record of what was posted.

## Editing posted transactions

```
vtt show "FILE.vtr" (--id N | --type PAY --ref N | --date D [--text T] [--amount G])
vtt edit "FILE.vtr" <same selector> [changes] [--force] [--commit]
```

`show` numbers a transaction's lines as `edit --line` expects and marks them
`prim` (bank/control side), `VAT` (VT's own VAT entry), `IN VAT RETURN`, `LOCKED`.
`edit` is a dry run unless `--commit`; it prints before/after with changed lines
starred. The selector must match exactly one transaction, or the matches are listed.

| Change | Flag |
| --- | --- |
| Recode a line | `--account A` (exact name or unique fragment) |
| Re-split gross into net + VAT | `--vat 20%` / `5%` / `0` / `1.00` / `none` |
| Carve an amount off a line | `--split "Account=2.50[:text]"` (repeatable; inherits VAT scope) |
| Header / line narrative, date | `--set-text`, `--line-text`, `--notes`, `--set-date` |
| Which line | `--line N` or `--line fragment` (default: the only coded line) |
| Batch, all-or-nothing | `--json-file F` (specs as in `vtaconnect.edit`) |

`--vat` keeps the gross and the bank line fixed: `£6 Telephone` becomes `£5
Telephone + £1 input VAT`. A bare `0`, `5` or `20` is a rate; write `5.00` for an
amount.

**Refused:** the primary line of a PAY/REC/invoice; VT's VAT entry; recoding *to*
the VAT or net-VAT-due accounts; VT-generated types (YET, VAT, CLR ...); VAT changes
or splits on a transaction in a posted VAT return; `--vat` when another line is also
in VAT scope (do that one in the GUI). Changing the gross is not supported.

**Soft-blocked:** anything dated, or moved to, on or before the lock date —
`--force` overrides and records a warning. VT does not enforce the lock date
through COM, so this guard is the only one.

**Allowed on a VAT-return transaction:** recoding and text. The return's figures
do not move.

After each edit, before commit, the transaction is re-checked (balances, primary
unchanged, VAT unchanged unless `--vat`, VAT net = sum of in-scope lines); any
failure rolls back the whole batch. `--commit` backs up and runs `Verify()`.

VTA mechanics, for extending it: a posted entry's value is read only — amounts move
only via `Entry.ChangeValue(newValue, balancingEntry)`, which VT refuses without a
balancing entry; recoding is `Entry.Account = acct`; `CheckEntriesBalance()` only
works on unposted transactions; `ChangeParent` (e.g. PAY→JRN) is refused.

## Adding accounts

```
vtt add-account "FILE.vtr" --ledger L --name N [--code C] [--vat-scope yes|no] [--notes T] [--commit]
vtt add-account "FILE.vtr" --json-file accounts.json [--commit]    # [{"ledger","name",...}], all or nothing
```

Dry run unless `--commit` (backup + `Verify()`). `--ledger` is an exact name or a
unique fragment. Refused: a name already in that ledger (VT is case-insensitive),
an empty name, a name containing `|`, a code already in use. A name that exists in
another ledger is allowed with a warning - refer to it as `Ledger|Account`.

VT creates accounts with "new entries within VAT scope" off; `vtt` instead follows
the majority of the ledger unless `--vat-scope` is given. That flag only affects
GUI entry - `vtt post` sets scope per line.

Before creating one, check `vtt chart` for an existing account that fits: a new
account is a chart-of-accounts decision for the user, not a coding shortcut.

## The safety model

- **Dry run by default.** Not a simulation: it builds the transaction and calls
  VT's `Post()` inside `BeginTrans`/`RollbackTrans`, then rolls back. You get the
  real errors — bad account name, unbalanced transaction, date on or before the
  lock date — and no accounting data changes.
- **A timestamped backup** (`NAME.YYYYmmdd-HHMMSS.bak.vtr`) is written next to the
  file before every commit, unless `--no-backup`.
- **One VT transaction wraps the whole batch.** If any line of any transaction
  fails, everything rolls back.
- **`Company.Verify()` runs after committing.** Non-zero is reported and the CLI
  exits non-zero.
- **There is no duplicate guard.** Reconciliation is the dedup — see `vtt-post`.

### A dry run changes the file's bytes

Earlier notes and the tool's own docs once claimed a dry run leaves the `.vtr`
byte-for-byte identical. **That is wrong**, and both have been corrected.

Opening a company for write — which `post` does even for a dry run — makes VT
rewrite internal housekeeping regardless of the `RollbackTrans`. Repeated
*identical* dry runs flip the file between two byte states rather than accumulating.

The **accounting data genuinely is untouched**: verified by diffing full `vtt tb`
and `vtt entries` output either side of a dry run on a 207-entry file — identical.

In practice:

- A dry run makes the `.vtr` look modified to OneDrive, to a backup tool, and to
  any hash-based change detection. Expect the client file to re-sync.
- **Do not use a checksum to prove a dry run was safe.** Compare `vtt tb` or
  `vtt entries` output.
- The read-only commands (`info`, `accounts`, `chart`, `tb`, `balance`, `entries`)
  do not touch the file at all — the hash is stable across repeated runs.

## The files in ~/tools/vttconnector

| File | What it is |
| --- | --- |
| `vtt` | The CLI. Start here. |
| `vtaconnect.py` | Python wrapper: WSL↔Windows interop, path staging, JSON. Importable as a library (`info`, `accounts`, `entries`, `trial_balance`, `post`). |
| `vta.ps1` | The COM layer. Runs under 32-bit PowerShell; not called directly. |
| `vtr.py` | Independent read-only parser of the `.vtr` binary format. No Windows needed. Used by `vtt check`. |
| `dumptlb.ps1` | Dumps VTA interface signatures from the type library. Use when extending `vta.ps1` — see [internals.md](internals.md). |
| `PLAN.md` | Design for the agent-assisted bank posting pipeline. `vtt chart` is built; the `vtt bank …` stages are not. |
