# Plan — agent-assisted bank posting into VT Transaction+

> **Superseded (Jul 2026).** After running a full bookkeeping session by hand, the
> `vtt bank …` rules pipeline below (extract → tie-out → rules → code → review →
> learn) was replaced by a lighter, skill-driven loop: an agent codes directly
> from `vtt chart` + prior narratives, reconciles to the statement's own balances,
> and posts a batch. What shipped instead:
> - read/coding primitives — `vtt entries --account/--tail`, `vtt balance`, and
>   `vtt post` reading a batch from stdin (`-`);
> - the `vtt-post` Claude skill (`~/.claude/skills/vtt-post/`) that drives the loop.
>
> Dropped, and why: **`srcId` idempotency** — reconciliation to the account book
> value is the anchor instead (a duplicate post overshoots the statement and is
> caught by the tie-out), so a per-row hash was redundant. **VAT computation** —
> the skill targets non-VAT-registered clients first; VAT clients keep a manual,
> human-reviewed path. **Rules engine / `extract` / `learn`** — the agent codes
> from the chart directly, no curated `rules.csv`. The design below is kept for its
> reasoning on the amount path, the review model, and the control-ledger risk,
> which the skill still follows.

Status: **phase 1 (`vtt chart`) built; the `vtt bank …` pipeline is still design only.**
Phases and open questions at the end.

Two deliverables:

* **A.** `vtt chart` — the chart of accounts in a form a Claude agent can code against. **Built.**
* **B.** `vtt bank …` — a pipeline that turns a bank statement into postings, with an
  agent doing only the part that needs judgement.

Both build on the existing connector (`vtt`, `vtaconnect.py`, `vta.ps1`), so every
write still goes through VT's own COM API.

---

## Governing principle

**The model proposes, deterministic code disposes.**

The agent's only job is mapping *description → account*. It never sees, produces,
or adjusts an amount. Amounts flow from the extracted statement to the posting
untouched, and are never round-tripped through a prompt. Everything the agent
returns is validated against the real chart before it can reach the ledger.

This survives the relaxed review model below, and for a reason worth stating: a
**wrong account is obvious on review** — "Rent" sitting under Motor expenses jumps
out of a nominal listing. A **wrong amount is invisible** — £1,240.00 where the
statement said £1,204.00 looks entirely plausible and will only surface when the
bank fails to reconcile, if then. So the amount path stays sealed even though the
coding path is open.

---

## The review model

**Posting is reversible; VT makes recoding cheap.** Changing an account, amount or
date on a posted transaction is a few keystrokes in the GUI, so an AI mis-coding is
a correction, not an incident. The design therefore does **not** try to gatekeep AI
output before it reaches the ledger.

What this buys and what it costs:

* Rule matches and agent codings both post unattended. No approval queue.
* The burden shifts from *blocking* to *finding*. A wrong posting nobody looks at
  is still wrong, so everything the tool posts must be trivially enumerable
  afterwards — see [Traceability](#traceability).

The safeguards that remain are the ones guarding against states that are **not**
cheap to fix, or not noticeable in the first place:

| Kept | Why it is not just caution |
| --- | --- |
| Tie-out (stage 2) | A mis-parsed statement produces wrong *amounts*, which review does not catch. This is the one hard stop. |
| `srcId` idempotency | Duplicate postings are easy to delete but easy to miss, and they distort every report until someone notices. |
| Lock date check | VT refuses these anyway; catching it early avoids a half-posted batch. |
| VAT computed, never model-decided | A VAT error that reaches a filed return stops being a recoding job and becomes an amendment. |

Everything else is advisory.

---

## Decisions taken

| Decision | Choice | Why |
| --- | --- | --- |
| VAT | Per-rule VAT treatment | VAT lives in the rules file, computed deterministically. The model never decides VAT — it is the most likely and most expensive error, and the only one that can escape into a filed return. |
| Review gate | **Post everything that is coded** | VT recoding is cheap, so pre-approval buys little and costs a queue. Superseded the earlier "auto-post rule matches only". |
| Suppliers / customers | **Post, but flag prominently** | Coding a supplier payment straight to P&L bypasses the purchase ledger and leaves the creditor outstanding — a double count. Still fixable, but not self-evident on a nominal listing, so it leads the review report. `--hold-ledger` restores a hard refusal. |

---

## A. `vtt chart`

```
vtt chart FILE [--format json|markdown] [--min-usage N] [--with-precedent N]
```

`vtt accounts` lists names. An agent needs enough to choose *between* accounts:

| Field | Source | Why it matters |
| --- | --- | --- |
| ledger, account | `Account.Parent.Name`, `Account.Name` | names are only unique per ledger |
| P&L vs balance sheet | ledger classification | stops "Rent" landing on a balance sheet account |
| **role** | `Company.DefinedAccounts(task)` | marks bank, VAT input/output, net VAT due, accruals, prepayments, P&L b/fwd as *never code here directly* |
| **is control ledger** | ledger type (see open questions) | drives the `ledger-review` status |
| entry count, last used | entry scan | VT ships ~170 standard accounts; only a fraction are live. Usage separates them. |
| **sample narratives** | prior entry text | by far the strongest coding signal — "this description was coded here before" |
| balance | `Account.Value(date, …)` | sanity context |

`--min-usage 1` prunes the unused standard chart, which is the difference between a
prompt that fits comfortably and one full of noise. `--format markdown` for dropping
into a prompt; `--format json` for programmatic use.

Prior narratives can also be mined from VT's **phrase book**, which is VT's own record
of which narrative went with which account.

---

## B. Bank pipeline

```
statement.csv
  │
  ├─1─ vtt bank extract   → rows.json          deterministic
  ├─2─      (tie-out)     → HARD STOP on failure
  ├─3─ vtt bank code      → proposed.csv       rules + history
  ├─4─      agent         → coding.csv         judgement only
  ├─5─ vtt bank post      → dry run, then --commit
  ├─5a─ vtt bank review   → worklist, recode in VT
  └─6─ vtt bank learn     → rules.csv grows
```

### 1–2. Extract and tie out

```
vtt bank extract statement.csv --account "Bank|Current account" > rows.json
```

Deterministic parsing of CSV/OFX/QIF. **PDF is out of scope** — see Risks.

The tie-out is the safety net for the whole pipeline. It refuses to emit anything
unless:

* the running balance is continuous row to row;
* opening + sum(rows) = closing, against the statement's own stated balances;
* no duplicate `src_id`;
* no row dated on or before the VT file's lock date.

If a statement does not tie, no amount of good coding downstream can save it. This
is what stops an extraction error becoming a posting error.

```json
{
  "source": "statement-2026-06.csv",
  "bank_account": "Bank|Current account",
  "period": { "from": "2026-06-01", "to": "2026-06-30" },
  "opening_balance": 15549.60,
  "closing_balance": 12345.67,
  "rows": [
    { "ordinal": 1, "date": "2026-06-02", "description": "SO/RENT JUNE",
      "amount": -1200.00, "balance": 14349.60, "src_id": "9f2a…" }
  ]
}
```

`src_id` = SHA-256 of `bank_account | date | amount | description | ordinal`. Stable
across re-runs, unique per line, and the basis of idempotency.

### 3. Rule-based coding

```
vtt bank code rows.json --file FILE --rules rules.csv > proposed.csv
```

Two sources of deterministic matches:

1. **`rules.csv`** — the curated rule set.
2. **History** — exact narrative matches mined from the file's own prior entries and
   phrase book. An exact match on a narrative that a human already coded is at least
   as good a signal as a hand-written rule, so these post too; they are recorded as
   `history` rather than `rule` so the review report can distinguish them.

`rules.csv`, plain CSV so it opens in Excel and diffs in git:

```csv
match,pattern,account,type,vat,note
contains,TFL TRAVEL,Expenses|Travel and subsistence,PAY,none,
regex,^SO/RENT,Expenses|Rent,PAY,standard,monthly standing order
exact,BANK INTEREST,Income|Interest receivable,REC,none,
```

`match` is `exact` | `contains` | `regex`. `vat` is `standard` | `zero` | `exempt` |
`none`, defaulting to `none` when absent. First matching rule wins; order is
significant and therefore reviewable.

### 4. The agent step

The CLI does not call an API. The agent is the loop:

* **Given:** `vtt chart` output, and only the rows with `status=needs-coding`
  (date, description, amount — amount for context only).
* **Returns:** `coding.csv` with `src_id,account,note,confidence` — *nothing else*.

Amounts are deliberately absent from the return path. They are re-read from
`rows.json` at posting time, so no agent output can alter a figure.

On merge the tool rejects any row whose account is not in the chart — a hallucinated
account name is the one agent output that cannot be posted at all — and marks
`ledger-review` where the account sits in a customer or supplier control ledger.

`confidence` is carried through to the review report so a human can work the list
worst-first, rather than being used as a posting threshold. A low-confidence coding
that turns out right costs nothing; the same coding held back costs a manual entry.

### 5. Posting

```
vtt bank post proposed.csv --file FILE            # dry run
vtt bank post proposed.csv --file FILE --commit
```

`status` records *how* a row was coded. It drives the review report, not a gate:

| `status` | meaning | behaviour |
| --- | --- | --- |
| `rule` | matched a curated rule | posts |
| `history` | matched a prior entry's narrative exactly | posts |
| `agent` | coded by the model | posts, listed in the review report |
| `ledger-review` | account is in a supplier or customer control ledger | posts, **leads** the review report (`--hold-ledger` to refuse instead) |
| `needs-coding` | nothing matched and the agent declined | cannot post — there is no account to post to |

Only the last is a genuine refusal, and only because the row is incomplete.

Posting reuses the existing machinery: dry run by default, timestamped backup before
commit, whole batch in one VT transaction, `Verify()` afterwards.

**Transaction types** are `REC` for money in and `PAY` for money out — not `JRN` — so
VT's cashbook and bank reconciliation keep working.

**Idempotency.** Each posted transaction is stamped
`CustomProperty("srcId") = src_id`. Before posting, existing transactions in the date
range are read back and matching rows skipped, so re-running a statement is safe and
partial re-runs resume cleanly.

**VAT computation** is deterministic, derived from the rule's treatment and the
company's own rate:

```
net = round(gross / (1 + rate), 2)
vat = gross - net                     # residual, so the transaction always balances
```

A £1,200 standard-rated payment posts as **two** batch lines, not three:

| Account | Amount | VAT |
| --- | --- | --- |
| `Bank\|Current account` | −1,200.00 | |
| `Expenses\|Rent` | +1,000.00 | +200.00 |

The VAT is not a line of its own. VT creates the VAT entry itself once the net
line is flagged within VAT scope, and only the entry VT creates carries the net
amount behind it — the figure boxes 6 and 7 are analysed from. See the VAT
section of `README.md`; this is implemented and no longer an open question.

Taking VAT as the residual rather than rounding both sides independently guarantees
the transaction sums to zero.

Note this file is on **VAT cash accounting**, so bank movements genuinely do carry
VAT — see Risks.

<a name="traceability"></a>

### 5a. Traceability

If nothing is held back before posting, everything must be findable after it. This is
the part of the design that the relaxed review model makes load-bearing.

Every transaction the tool posts is stamped with custom properties:

| Property | Value |
| --- | --- |
| `srcId` | the statement row hash — drives idempotency |
| `codedBy` | `rule` \| `history` \| `agent` |
| `codedRun` | timestamp of the import run, so one batch can be isolated |
| `confidence` | agent confidence, where applicable |

```
vtt bank review FILE --run 2026-07-24T09:15 [--only agent,ledger-review]
```

Reads those properties back and prints a worklist — date, type, **ref**, account,
amount, narrative, why it was coded that way — ordered supplier/customer first, then
agent codings weakest-confidence first, then history, then rules. The ref is what
makes it actionable: it is what you type into VT to pull the transaction up and
recode it.

Two things to confirm during the build (see Open questions): whether VT surfaces
custom properties anywhere in its own UI, and whether it is worth an opt-in `--tag`
that appends a visible marker to the narrative for people who would rather filter
inside VT than work from a printed list.

### 6. Learning

```
vtt bank learn proposed.csv --rules rules.csv
```

Promotes codings into `rules.csv` so next month they match deterministically, without
an agent call. With the approval gate gone this is now a **cost** optimisation rather
than a trust one — the postings would happen either way; rules just make them free
and repeatable.

Promotion is still per-rule and writes a diff, because `rules.csv` is the artefact a
human is most likely to want to read, edit and keep in version control. A rule is a
standing instruction, and standing instructions deserve to be legible even when the
individual postings they produce are cheap to undo.

---

## Risks

Ranked by how hard the damage is to undo, since that is now the organising principle.

1. **Extraction error.** A mis-parsed statement produces plausible-looking wrong
   amounts that survive review and only surface at bank reconciliation. This is the
   one failure the tie-out exists for, and the reason PDF is out of scope. Use CSV or
   OFX from the bank; if PDF is unavoidable, treat it as untrusted input whose only
   defence is stage 2.
2. **VAT, especially under cash accounting.** A direct payment for an expense carries
   VAT; a payment settling a purchase-ledger invoice does not, because VAT was
   accounted on the invoice. A bank narrative alone often cannot distinguish them.
   Recoding is cheap *until the VAT return is filed*, after which it is an amendment.
   Mitigated by per-rule treatment and by flagging control-ledger names, not
   eliminated.
3. **Supplier and customer payments.** The natural agent instinct is to code
   "P WEISS" to an expense account, which double-counts the expense and leaves the
   creditor outstanding. These now post, so the defence is that they lead the review
   report — which depends on correctly identifying control ledgers.
4. **Nobody reads the review report.** The real exposure created by dropping the
   approval gate. Unreviewed AI postings are cheap to fix and therefore easy to leave
   alone. Worth making `vtt bank post` print the worklist immediately on commit
   rather than waiting to be asked for it.
5. **Wrong rule repeating silently.** A rule posts every month thereafter. Rules
   belong in version control and `learn` writes a readable diff.
6. **Lock date.** Currently 2024-06-30 on this file; `vtt info` reports it.
7. **Year-end restatement.** Posting into a closed period restates the year end. This
   is intended VT behaviour and one of the reasons the year end can be re-run freely,
   but a back-dated import will move prior-period figures. Worth running `vtt tb` for
   affected dates afterwards.

---

## Build phases

| Phase | Deliverable | Notes |
| --- | --- | --- |
| 1 | `vtt chart` | **Done.** Shipped 24 Jul 2026. |
| 2 | `vtt bank extract` + tie-out | The safety gate. Worth building before anything that writes. |
| 3 | Rules engine + `vtt bank code` | |
| 4 | `vtt bank post` + `srcId` idempotency | |
| 5 | `vtt bank review` | Ships **with** phase 4, not after it — with no approval gate it is the only thing standing between an AI coding and nobody ever looking at it. |
| 6 | `vtt bank learn` | |

Optionally afterwards: a Claude Code skill wrapping the loop so the agent follows the
same sequence each time. Note the workspace already has a `vtt-import` skill for VT's
Universal Input Sheet — a different, spreadsheet-driven route to the same ledger,
worth keeping distinct from this one.

---

## Open questions, to confirm while building

1. ~~**How VT identifies customer/supplier ledgers.**~~ **Resolved.** `Ledger.ListType`
   is set only on customer/supplier control ledgers, so its presence is the test.
   `Ledger.IsPL` gives the P&L/balance sheet split. Both are now surfaced by
   `vtt chart`.
2. **VAT split mechanics.** Whether to post net + VAT explicitly to the VAT-Input
   account, or drive VT's own auto-VAT (`Entry.IsAutoVAT`). Auto-VAT may handle
   deferred/cash-accounting VAT more correctly than an explicit split.
3. **Idempotency scan cost.** Reading `CustomProperty` across a date range is trivial
   on this 556-transaction file; needs checking on a large one before being relied on.
4. **Whether VT surfaces custom properties in its own UI.** If it does, `codedBy`
   becomes filterable inside VT and the review report is a convenience rather than
   the only route in. If it does not, the report carries the whole weight and the
   optional narrative `--tag` is worth having.
5. **Whether VT flags transactions as VAT-reconciled or bank-reconciled.** These are
   the two states where "just recode it" stops being true. If VTA exposes them, the
   review report should say so per transaction.
