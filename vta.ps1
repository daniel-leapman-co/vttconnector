<#
    VT Accounting Objects (VTA) connector.

    Must be run under 32-bit PowerShell — VTA.dll is a 32-bit in-process COM
    server. vtaconnect.py handles that; if invoking by hand, use
    C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe

    Actions
      accounts  list every account as JSON
      tb        trial balance at -Date as JSON
      entries   all entries as JSON
      post      post transactions described by -Json; rolls back unless -Commit
      show      find posted transactions described by -Json (read only)
      edit      edit posted transactions described by -Json; rolls back unless -Commit

    All writes run inside BeginTrans/CommitTrans. Without -Commit the work is
    rolled back, which leaves every entry and balance untouched — that is the
    dry run. The file's bytes still change: opening a company for write makes VT
    rewrite internal housekeeping whatever the rollback does. After a commit the
    company is re-verified and a non-zero VtaVerifyResult is reported as a
    failure.
#>
param(
    [Parameter(Mandatory=$true)][ValidateSet('info','accounts','tb','entries','post','show','edit')][string]$Action,
    [Parameter(Mandatory=$true)][string]$File,
    [string]$Date,
    [string]$Json,
    [switch]$Commit
)

$ErrorActionPreference = 'Stop'

# Redirected stdout defaults to the OEM code page, which mangles accented
# narratives and non-ASCII company names. Force UTF-8 both ways.
[Console]::OutputEncoding = New-Object Text.UTF8Encoding $false
$OutputEncoding = [Console]::OutputEncoding

if ([Environment]::Is64BitProcess) {
    throw "Must run under 32-bit PowerShell (VTA.dll is 32-bit). Use SysWOW64\WindowsPowerShell\v1.0\powershell.exe"
}

function Format-VtDate($v) {
    # Unset VT dates come back as 0 / empty rather than a DateTime.
    if ($null -eq $v) { return $null }
    try { $d = [datetime]$v } catch { return $null }
    if ($d.Year -le 1900) { return $null }
    $d.ToString('yyyy-MM-dd')
}

function Get-AccountMap($company) {
    $map = @{}
    foreach ($a in $company.AllAccounts) {
        # Account names are unique per ledger, so key on both.
        $map["$($a.Parent.Name)|$($a.Name)"] = $a
        if (-not $map.ContainsKey($a.Name)) { $map[$a.Name] = $a }
    }
    $map
}

function Resolve-Account($map, $spec) {
    if ($map.ContainsKey($spec)) { return $map[$spec] }
    throw "Account not found: '$spec' (use 'Name' or 'Ledger|Name')"
}

function Get-VATAccountKeys($company) {
    # The input and output VAT accounts VT maintains itself. On a transaction
    # type that carries VAT these are written by VT, never by us — see the
    # 'post' action for why posting to them directly produces a dead entry.
    $keys = @{}
    foreach ($task in 4, 5) {   # vtaDTInputVATAccount, vtaDTOutputVATAccount
        try {
            $a = $company.DefinedAccounts($task)
            if ($a) { $keys["$($a.Parent.Name)|$($a.Name)"] = $true }
        } catch { }
    }
    $keys
}

# ------------------------------------------------------------------ editing
#
# Entry.TypeID on a posted transaction: 2 = primary (the bank or control side
# on a PAY/REC/SIN..., simply the first line on a JRN), 3 = the VAT entry VT
# owns, 5 = an analysis line. Everything below is built on what was proven
# against VTA before this was written:
#   * Entry.Account (putref) recodes a posted line in place.
#   * A posted entry's value is read only; ChangeValue(NewValue, BalancingEntry)
#     moves the difference onto another entry of the same transaction, so a
#     transaction can never be left out of balance.
#   * On the VAT entry, ChangeValue(vat, netLine) re-splits a gross into net and
#     VAT; VT recomputes the VAT entry's net (VATTurnoverValue) itself.
#   * VT refuses VAT changes and moving the date past the return on a
#     transaction in a posted VAT return, but DOES allow recoding it.
#   * VT does NOT enforce the lock date through COM. That check is ours.
#   * VT does not stop edits to the primary or VAT entry, nor ChangeValue
#     balanced against the VAT entry. Those guards are ours as well.

# Types VT generates for its own bookkeeping; edit these in the GUI or not at all.
$script:NoEditTypes = @('YET','VAT','DVT','CLR','PGS','CRV','PCV','CCV','WOF','WBK')

function Get-ProtectedAccountKeys($company) {
    # Accounts nothing should be recoded TO: VT's VAT accounts, the net VAT due
    # account the return posts to, EC VAT and the deferred VAT accounts.
    $keys = @{}
    foreach ($task in 4, 5, 6, 14, 17, 18) {
        try {
            $a = $company.DefinedAccounts($task)
            if ($a) { $keys["$($a.Parent.Name)|$($a.Name)"] = $true }
        } catch { }
    }
    $keys
}

function Find-Account($map, $all, $spec) {
    # Exact 'Ledger|Name' or 'Name' first; then a case-insensitive fragment
    # that matches exactly one account. Recoding to a guessed account is worse
    # than an error, so an ambiguous fragment lists the candidates and stops.
    if ($map.ContainsKey($spec)) { return $map[$spec] }
    $needle = $spec.ToLower()
    $hits = @($all | Where-Object { "$($_.Parent.Name)|$($_.Name)".ToLower().Contains($needle) })
    if ($hits.Count -eq 1) { return $hits[0] }
    if ($hits.Count -eq 0) { throw "Account not found: '$spec'" }
    $names = ($hits | Select-Object -First 8 | ForEach-Object { "$($_.Parent.Name)|$($_.Name)" }) -join '; '
    throw "Account '$spec' is ambiguous ($($hits.Count) matches): $names"
}

function Get-Role($e) {
    switch ([int]$e.TypeID) { 2 { 'primary' } 3 { 'vat' } default { 'line' } }
}

function Snapshot-Transaction($t, $lockDate) {
    $inRet = $false; try { $inRet = [bool]$t.IsInVATReturn } catch { }
    $lines = @(); $pos = 0
    foreach ($e in $t.Entries) {
        $pos++
        $role = Get-Role $e
        $vatNet = $null
        if ($role -eq 'vat') { try { $vatNet = [double]$e.VATTurnoverValue } catch { } }
        $inScope = $false; try { $inScope = [bool]$e.WithinVATScope } catch { }
        $lines += [pscustomobject]@{
            n = $pos; role = $role
            ledger = $e.Account.Parent.Name; account = $e.Account.Name
            amount = [double][math]::Round([decimal]$e.BaseValue, 2)
            inScope = $inScope; vatNet = $vatNet; text = $e.Text
        }
    }
    $d = $t.DateNumber
    [pscustomobject]@{
        id = $t.Identifier; type = $t.Parent.Name; ref = $t.RefNumber
        date = $d.ToString('yyyy-MM-dd'); text = $t.Text; notes = $t.Notes
        inVATReturn = $inRet
        locked = ($lockDate -and $d -le $lockDate)
        lines = $lines
    }
}

function Find-Transactions($c, $sel) {
    # One of: id; type + ref; date (+ optional text fragment, amount).
    if ($sel.id) {
        $t = $c.AllTransactions.ID([int]$sel.id)
        if (-not $t) { throw "No transaction with id $($sel.id)" }
        return ,@($t)
    }
    $out = @()
    $from = $null; $to = $null
    if ($sel.date) { $from = [datetime]::Parse($sel.date, [Globalization.CultureInfo]::InvariantCulture); $to = $from }
    if ($sel.from) { $from = [datetime]::Parse($sel.from, [Globalization.CultureInfo]::InvariantCulture) }
    if ($sel.to)   { $to   = [datetime]::Parse($sel.to,   [Globalization.CultureInfo]::InvariantCulture) }
    if (-not ($sel.ref -or $from -or $to -or $sel.text)) { throw "Give an id, a type and ref, or a date/text to find the transaction" }
    $needle = if ($sel.text) { ([string]$sel.text).ToLower() } else { $null }
    foreach ($t in $c.AllTransactions) {
        if ($sel.type -and $t.Parent.Name -ne $sel.type) { continue }
        if ($sel.ref -and $t.RefNumber -ne [int]$sel.ref) { continue }
        if ($from -and $t.DateNumber -lt $from) { continue }
        if ($to -and $t.DateNumber -gt $to) { continue }
        if ($needle -and -not ([string]$t.Text).ToLower().Contains($needle)) { continue }
        if ($null -ne $sel.amount) {
            $pe = $t.PrimaryEntry
            if (-not $pe -or [math]::Abs([math]::Abs([double]$pe.BaseValue) - [math]::Abs([double]$sel.amount)) -gt 0.005) { continue }
        }
        $out += $t
    }
    ,$out
}

function Resolve-Line($t, $spec, $what) {
    # A line is picked by its position (as `show` numbers them) or by an account
    # fragment. With no spec, the transaction's only analysis line is meant.
    $entries = @(foreach ($e in $t.Entries) { $e })
    if ($null -eq $spec -or "$spec" -eq '') {
        $cands = @($entries | Where-Object { [int]$_.TypeID -eq 5 })
        if ($cands.Count -eq 1) { return $cands[0] }
        throw "This transaction has $($cands.Count) coded lines; say which one to $what with --line N (see 'vtt show')"
    }
    $n = 0
    if ([int]::TryParse("$spec", [ref]$n)) {
        if ($n -lt 1 -or $n -gt $entries.Count) { throw "Line $n does not exist (transaction has $($entries.Count) lines)" }
        return $entries[$n - 1]
    }
    $needle = "$spec".ToLower()
    $hits = @($entries | Where-Object { [int]$_.TypeID -ne 3 -and "$($_.Account.Parent.Name)|$($_.Account.Name)".ToLower().Contains($needle) })
    if ($hits.Count -eq 1) { return $hits[0] }
    if ($hits.Count -eq 0) { throw "No line on this transaction matches '$spec'" }
    throw "'$spec' matches $($hits.Count) lines on this transaction; use --line N"
}

function Assert-EditableLine($t, $e, $what) {
    $role = Get-Role $e
    if ($role -eq 'vat') {
        throw "Refusing to $what the VAT entry: VT owns it. Use --vat to change the VAT on the net line instead."
    }
    if ($role -eq 'primary' -and $t.Parent.Name -notin @('JRN','RJN')) {
        throw ("Refusing to $what the primary entry of a $($t.Parent.Name) ('$($e.Account.Parent.Name)|$($e.Account.Name)'): " +
               "that is the bank or control side, and changing it breaks reconciliation or the sales/purchase ledger. Do it in VT.")
    }
}

function Get-VatEntry($t) { foreach ($e in $t.Entries) { if ([int]$e.TypeID -eq 3) { return $e } }; $null }

function Assert-Invariants($t, $before, $vatChanged, $grossChangeAllowed) {
    # Checked after every edit and before commit. Any failure aborts the whole
    # batch, so a guard we forgot about in the edit code still cannot land.
    $sum = 0.0; $inScopeSum = 0.0; $ve = $null; $prim = $null
    foreach ($e in $t.Entries) {
        $v = [double][math]::Round([decimal]$e.BaseValue, 2)
        $sum += $v
        $ty = [int]$e.TypeID
        if ($ty -eq 3) { $ve = $e }
        elseif ($ty -eq 2) { $prim = $e }
        if ($ty -ne 3) { try { if ($e.WithinVATScope) { $inScopeSum += $v } } catch { } }
    }
    if ([math]::Round($sum, 2) -ne 0) { throw "Internal check failed: transaction $($t.Identifier) no longer balances ($([math]::Round($sum,2)))" }
    $pb = @($before.lines | Where-Object { $_.role -eq 'primary' })
    if (-not $grossChangeAllowed -and $pb.Count -and $prim -and [math]::Round([double]$prim.BaseValue, 2) -ne $pb[0].amount) {
        throw "Internal check failed: the primary entry of transaction $($t.Identifier) changed ($($pb[0].amount) -> $([double]$prim.BaseValue))"
    }
    $vb = @($before.lines | Where-Object { $_.role -eq 'vat' })
    if (-not $vatChanged -and $vb.Count) {
        $now = if ($ve) { [math]::Round([double]$ve.BaseValue, 2) } else { 0 }
        if ($now -ne $vb[0].amount) { throw "Internal check failed: the VAT on transaction $($t.Identifier) changed ($($vb[0].amount) -> $now)" }
    }
    if ($ve) {
        $net = [math]::Round([double]$ve.VATTurnoverValue, 2)
        if ($net -ne [math]::Round($inScopeSum, 2)) {
            throw "Internal check failed: VAT net on transaction $($t.Identifier) is $net but its in-scope lines sum to $([math]::Round($inScopeSum,2))"
        }
    }
}

function Invoke-Edit($c, $spec, $map, $all, $protected, $lockDate) {
    $found = Find-Transactions $c $spec   # returns the array itself (unary comma), do not re-wrap
    if ($found.Count -eq 0) { throw "No transaction matches $(($spec | ConvertTo-Json -Compress -Depth 4))" }
    if ($found.Count -gt 1) {
        $list = ($found | Select-Object -First 10 | ForEach-Object { "id $($_.Identifier) $($_.Parent.Name) ref $($_.RefNumber) $($_.DateNumber.ToString('yyyy-MM-dd')) '$($_.Text)'" }) -join '; '
        throw "$($found.Count) transactions match; narrow it down or use --id. First matches: $list"
    }
    $t = $found[0]
    $before = Snapshot-Transaction $t $lockDate
    $warnings = @(); $done = @()
    $force = [bool]$spec.force

    if ($t.Parent.Name -in $script:NoEditTypes) {
        throw "Refusing to edit a $($t.Parent.Name) transaction (id $($t.Identifier)): VT generates these itself. Use the VT GUI."
    }

    # Lock date: VT would let this through, so we block unless forced.
    $newDate = $null
    if ($spec.newDate) { $newDate = [datetime]::Parse($spec.newDate, [Globalization.CultureInfo]::InvariantCulture) }
    if ($lockDate) {
        $hits = @()
        if ($t.DateNumber -le $lockDate) { $hits += "is dated $($t.DateNumber.ToString('yyyy-MM-dd'))" }
        if ($newDate -and $newDate -le $lockDate) { $hits += "would move to $($newDate.ToString('yyyy-MM-dd'))" }
        if ($hits.Count) {
            $msg = "Transaction id $($t.Identifier) $($hits -join ' and '), on or before the lock date $($lockDate.ToString('yyyy-MM-dd'))"
            if (-not $force) { throw "$msg. VT does not enforce the lock date through COM; re-run with --force if this is deliberate." }
            $warnings += "$msg (forced)"
        }
    }

    $inRet = $before.inVATReturn
    $vatOp = ($null -ne $spec.vatRate) -or ($null -ne $spec.vatAmount) -or [bool]$spec.vatNone
    if ($inRet -and ($vatOp -or $spec.splits)) {
        throw "Transaction id $($t.Identifier) is in a posted VAT return; its VAT and amounts can only be changed in the VT GUI (recoding and text edits are allowed)."
    }
    if ($inRet) { $warnings += "Transaction is in a posted VAT return; the return itself is unchanged by this edit." }

    # ---- header edits
    if ($null -ne $spec.newText) { $t.Text = [string]$spec.newText; $done += "text -> '$($spec.newText)'" }
    if ($null -ne $spec.notes)   { $t.Notes = [string]$spec.notes; $done += "notes updated" }
    if ($newDate) {
        $t.DateNumber = $newDate
        $done += "date -> $($newDate.ToString('yyyy-MM-dd'))"
    }

    # ---- line edits
    $needsLine = ($spec.account -or $spec.splits -or $vatOp -or ($null -ne $spec.lineText))
    if ($needsLine) {
        $what = if ($vatOp) { 'change the VAT on' } elseif ($spec.splits) { 'split' } else { 'edit' }
        $e = Resolve-Line $t $spec.line $what
        Assert-EditableLine $t $e $what
        $pos = 0; $i = 0; foreach ($x in $t.Entries) { $i++; if ($x.Identifier -eq $e.Identifier) { $pos = $i } }
        $label = "line $pos"

        if ($spec.account) {
            $to = Find-Account $map $all ([string]$spec.account)
            $key = "$($to.Parent.Name)|$($to.Name)"
            if ($protected.ContainsKey($key)) {
                throw "Refusing to recode to '$key': VT maintains that account. Use --vat to put VAT on a line."
            }
            try { if ($to.Parent.ListType) { $warnings += "'$key' is on a control ledger ($($to.Parent.ListType.Name)); coding straight to it bypasses the sales/purchase ledger." } } catch { }
            $from = "$($e.Account.Parent.Name)|$($e.Account.Name)"
            if ($from -eq $key) { $warnings += "$label is already coded to '$key'" }
            else { $e.Account = $to; $done += "$label recoded '$from' -> '$key'" }
        }

        if ($null -ne $spec.lineText) { $e.Text = [string]$spec.lineText; $done += "$label text -> '$($spec.lineText)'" }

        if ($spec.splits) {
            if ([int]$e.TypeID -ne 5) { throw "Only a coded line can be split, not the primary entry" }
            foreach ($s in $spec.splits) {
                $to = Find-Account $map $all ([string]$s.account)
                $key = "$($to.Parent.Name)|$($to.Name)"
                if ($protected.ContainsKey($key)) { throw "Refusing to split to '$key': VT maintains that account." }
                $cur = [decimal]$e.BaseValue
                $amt = [math]::Abs([decimal]$s.amount)
                if ($amt -le 0 -or $amt -ge [math]::Abs($cur)) {
                    throw "Split of $amt to '$key' must be more than 0 and less than the line's $([math]::Abs($cur))"
                }
                $signed = if ($cur -lt 0) { -$amt } else { $amt }
                $new = $t.Entries.Add($to)
                $new.ChangeValue([decimal]$signed, $e)
                if ($e.WithinVATScope) {
                    if (-not $new.SetWithinVATScopeIfPossible($true)) { throw "VT would not bring the new '$key' line within VAT scope" }
                }
                if ($s.text) { $new.Text = [string]$s.text }
                $done += "split $amt from $label to '$key'"
            }
        }

        if ($vatOp) {
            if (-not $t.Parent.HasVATEntries) { throw "A $($t.Parent.Name) does not carry VAT entries; VAT can only be changed on PAY, REC and invoice types" }
            if ([int]$e.TypeID -ne 5) { throw "VAT goes on a coded line, not the primary entry" }
            $others = @(foreach ($x in $t.Entries) { if ([int]$x.TypeID -eq 5 -and $x.Identifier -ne $e.Identifier -and $x.WithinVATScope) { $x } })
            if ($others.Count) {
                throw ("Another line on this transaction is also within VAT scope, so its VAT cannot be attributed to $label alone. " +
                       "Change VAT in VT, or on a transaction with one VAT'd line.")
            }
            $ve = Get-VatEntry $t
            $oldVat = if ($ve) { [decimal]$ve.BaseValue } else { [decimal]0 }
            $gross = [decimal]$e.BaseValue + $oldVat
            if ($spec.vatNone) {
                if ($ve -and $oldVat -ne 0) { $ve.ChangeValue([decimal]0, $e) }
                if ($e.WithinVATScope) {
                    if (-not $e.SetWithinVATScopeIfPossible($false)) { throw "VT would not take $label out of VAT scope" }
                }
                $done += "$label taken outside the scope of VAT (VAT $oldVat -> 0, net $gross)"
            } else {
                if ($null -ne $spec.vatRate) {
                    $r = [decimal]$spec.vatRate
                    if ($r -lt 0 -or $r -gt 100) { throw "VAT rate $r% is not plausible" }
                    $vat = [math]::Round($gross * $r / (100 + $r), 2, [MidpointRounding]::AwayFromZero)
                    $how = "$r%"
                } else {
                    $vat = [math]::Abs([decimal]$spec.vatAmount)
                    if ($gross -lt 0) { $vat = -$vat }
                    $how = "amount"
                    if ([math]::Abs($vat) -ge [math]::Abs($gross)) { throw "VAT $vat is not less than the gross $gross" }
                    $implied = if ($gross - $vat -ne 0) { [math]::Round($vat / ($gross - $vat) * 100, 1) } else { 0 }
                    if ($implied -notin 0, 5, 20) { $warnings += "VAT of $vat on a gross of $gross is $implied% of the net, not a standard UK rate" }
                }
                if (-not $e.WithinVATScope) {
                    if (-not $e.SetWithinVATScopeIfPossible($true)) { throw "VT would not bring $label within VAT scope" }
                }
                $ve = Get-VatEntry $t
                if (-not $ve) { throw "VT did not create a VAT entry when $label was brought within scope" }
                if ([decimal]$ve.BaseValue -ne $vat) { $ve.ChangeValue([decimal]$vat, $e) }
                $done += "$label VAT $oldVat -> $vat ($how); net $([decimal]$e.BaseValue), gross $gross unchanged"
            }
        }
    }

    if (-not $done.Count) { throw "Nothing to change on transaction id $($t.Identifier)" }
    Assert-Invariants $t $before $vatOp $false
    [pscustomobject]@{
        before = $before; after = (Snapshot-Transaction $t $lockDate)
        changes = @($done); warnings = @($warnings)
    }
}

$g = New-Object -ComObject VTA.GlobalMethods
$readOnly = ($Action -notin @('post','edit'))
$c = $g.OpenCompany($File, $readOnly, "", $false)

try {
  # Report failures as JSON too, so the caller never has to parse a PowerShell
  # stack trace to find out what VT actually objected to.
  try {
    switch ($Action) {

        'info' {
            [pscustomobject]@{
                company      = $c.Name
                vatNumber    = $c.VATRegNumber
                vatRegistered= [bool]$c.VATRegistered
                currentYearEnd = Format-VtDate $c.CurrentYearEnd
                lockDate     = Format-VtDate $c.LockDate
                accounts     = $c.AllAccounts.Count
                transactions = $c.AllTransactions.Count
                tranTypes    = @(foreach ($tt in $c.TranTypes) { $tt.Name })
            } | ConvertTo-Json -Depth 4
        }

        'accounts' {
            # IsPL and ListType come off the ledger, not the account. ListType is
            # set only on customer/supplier control ledgers, so its presence is
            # what marks an account as one you should not code to directly.
            $out = foreach ($a in $c.AllAccounts) {
                $led = $a.Parent
                $lt = $null
                try { if ($led.ListType) { $lt = [string]$led.ListType.Name } } catch { }
                [pscustomobject]@{
                    ledger   = $led.Name
                    account  = $a.Name
                    code     = $a.Code
                    isPL     = [bool]$led.IsPL
                    listType = $lt
                }
            }
            $out | ConvertTo-Json -Depth 4
        }

        'tb' {
            if (-not $Date) { throw "-Date is required for tb" }
            $d = [datetime]::Parse($Date, [Globalization.CultureInfo]::InvariantCulture)
            # VTA returns an exact currency type; round at the JSON boundary so
            # double conversion cannot leak 1e-11 noise into the total.
            $rows = foreach ($a in $c.AllAccounts) {
                $v = [math]::Round([decimal]$a.Value($d, $false, 0, $null), 2)
                if ($v -ne 0) {
                    [pscustomobject]@{ ledger = $a.Parent.Name; account = $a.Name; balance = [double]$v }
                }
            }
            [pscustomobject]@{
                company = $c.Name
                date    = $d.ToString('yyyy-MM-dd')
                total   = [double][math]::Round(($rows | Measure-Object -Property balance -Sum).Sum, 2)
                rows    = @($rows)
            } | ConvertTo-Json -Depth 4
        }

        'entries' {
            # isVAT / net: on a VAT entry, VATTurnoverValue is the net amount the VAT
            # return analyses into box 6 or 7. inScope marks the net lines it came from.
            $rows = foreach ($t in $c.AllTransactions) {
                foreach ($e in $t.Entries) {
                    $isVAT = $false; $net = $null; $inScope = $false
                    try { $isVAT = ([int]$e.TypeID -eq 3) } catch { }
                    try { $inScope = [bool]$e.WithinVATScope } catch { }
                    if ($isVAT) { try { $net = [double]$e.VATTurnoverValue } catch { } }
                    [pscustomobject]@{
                        date    = $t.DateNumber.ToString('yyyy-MM-dd')
                        type    = $t.Parent.Name
                        ref     = $t.RefNumber
                        ledger  = $e.Account.Parent.Name
                        account = $e.Account.Name
                        text    = $e.Text
                        amount  = [double]$e.BaseValue
                        isVAT   = $isVAT
                        inScope = $inScope
                        net     = $net
                    }
                }
            }
            $rows | ConvertTo-Json -Depth 4
        }

        'show' {
            if (-not $Json) { throw "-Json is required for show" }
            $sel = Get-Content -Raw -LiteralPath $Json | ConvertFrom-Json
            $lock = $null; try { if ($c.LockDate.Year -gt 1900) { $lock = $c.LockDate } } catch { }
            $found = Find-Transactions $c $sel
            $limit = if ($sel.limit) { [int]$sel.limit } else { 50 }
            [pscustomobject]@{
                ok = $true; lockDate = (Format-VtDate $c.LockDate); matched = $found.Count
                transactions = @($found | Select-Object -First $limit | ForEach-Object { Snapshot-Transaction $_ $lock })
            } | ConvertTo-Json -Depth 6
        }

        'edit' {
            if (-not $Json) { throw "-Json is required for edit" }
            $spec = Get-Content -Raw -LiteralPath $Json | ConvertFrom-Json
            if ($spec -isnot [array]) { $spec = @($spec) }
            $map = Get-AccountMap $c
            $all = @(foreach ($a in $c.AllAccounts) { $a })
            $protected = Get-ProtectedAccountKeys $c
            $lock = $null; try { if ($c.LockDate.Year -gt 1900) { $lock = $c.LockDate } } catch { }
            $results = @()

            $c.BeginTrans()
            try {
                $i = 0
                foreach ($s in $spec) {
                    $i++
                    try { $results += Invoke-Edit $c $s $map $all $protected $lock }
                    catch { throw "edit $i of $($spec.Count): $($_.Exception.Message)" }
                }
                if ($Commit) {
                    $c.CommitTrans()
                    $v = $c.Verify()
                    $c.FlushBuffers()
                    [pscustomobject]@{ committed = $true; verify = [int]$v; ok = ([int]$v -eq 0)
                                       lockDate = (Format-VtDate $c.LockDate); edits = @($results) } | ConvertTo-Json -Depth 7
                } else {
                    $c.RollbackTrans()
                    [pscustomobject]@{ committed = $false; verify = $null; ok = $true
                                       lockDate = (Format-VtDate $c.LockDate); edits = @($results) } | ConvertTo-Json -Depth 7
                }
            } catch {
                $c.RollbackTrans()
                throw
            }
        }

        'post' {
            if (-not $Json) { throw "-Json is required for post" }
            $spec = Get-Content -Raw -LiteralPath $Json | ConvertFrom-Json
            if ($spec -isnot [array]) { $spec = @($spec) }

            $map    = Get-AccountMap $c
            $vatKeys = Get-VATAccountKeys $c
            $types  = @{}
            foreach ($tt in $c.TranTypes) { $types[$tt.Name] = $tt }
            $posted = @()

            $c.BeginTrans()
            try {
                foreach ($tran in $spec) {
                    $typeName = if ($tran.type) { $tran.type } else { 'JRN' }
                    if (-not $types.ContainsKey($typeName)) { throw "Unknown transaction type: $typeName" }
                    $tt = $types[$typeName]
                    $carriesVAT = $false
                    try { $carriesVAT = [bool]$tt.HasVATEntries } catch { }
                    $d = [datetime]::Parse($tran.date, [Globalization.CultureInfo]::InvariantCulture)

                    $t = if ($tran.ref) { $tt.NewTransaction($d, [string]$tran.text, [int]$tran.ref) }
                         else            { $tt.NewTransaction($d, [string]$tran.text) }

                    # Add every line first. The first entry becomes the transaction's
                    # primary entry (the bank or control account on a PAY/REC/CCP), and
                    # VT will not accept a VAT scope flag until a primary exists — hence
                    # two passes rather than flagging as we go.
                    $scoped, $vatTotal = @(), 0.0
                    foreach ($line in $tran.lines) {
                        $acct = Resolve-Account $map $line.account
                        $key  = "$($acct.Parent.Name)|$($acct.Name)"
                        if ($carriesVAT -and $vatKeys.ContainsKey($key)) {
                            throw ("Do not post directly to '$key' on a $typeName. VT owns the VAT " +
                                   "entry on this transaction type: put the VAT on the net line's " +
                                   "'vat' field instead and VT will create it, carrying the net " +
                                   "amount that boxes 6 and 7 are built from.")
                        }
                        $e = $t.Entries.Add($acct)
                        $e.BaseValue = [double]$line.amount
                        if ($line.text) { $e.Text = [string]$line.text }
                        if ($line.PSObject.Properties.Name -contains 'vat' -and $null -ne $line.vat) {
                            $scoped += $e
                            $vatTotal += [double]$line.vat
                        }
                    }

                    # Flagging a net line as within VAT scope is what makes VT create the
                    # automatic VAT entry, and the VAT entry's VATTurnoverValue — the net
                    # figure the VAT return analyses into box 6/7 — is derived by VT from
                    # these flags. It cannot be assigned directly.
                    if ($scoped.Count) {
                        foreach ($e in $scoped) {
                            if ($e.SetWithinVATScopeIfPossible($true)) { continue }
                            $where = "'$($e.Account.Parent.Name)|$($e.Account.Name)'"
                            if (-not $carriesVAT) {
                                throw ("Transaction type $typeName does not carry VAT entries, so " +
                                       "$where cannot be flagged within VAT scope. Use PAY, REC or " +
                                       "CCP, or drop the 'vat' field.")
                            }
                            $isPrimary = $false
                            try { $isPrimary = [bool]$e.IsPrimary } catch { }
                            if ($isPrimary) {
                                throw ("$where carries the VAT but is the first line of the $typeName " +
                                       "dated $($tran.date), which makes it the primary entry — the " +
                                       "bank or control side, which is gross and never within VAT " +
                                       "scope. Put the bank or control account first and the net " +
                                       "lines after it.")
                            }
                            throw "VT refused to bring $where within VAT scope on the $typeName dated $($tran.date)"
                        }
                        $ve = $t.VATEntry
                        if (-not $ve) { throw "VT did not create a VAT entry for the $typeName dated $($tran.date)" }
                        $ve.BaseValue = [double]$vatTotal
                    }

                    $t.CheckEntriesBalance()   # throws if the journal does not balance
                    $t.Post()

                    # Read the VAT figures back off the posted transaction rather than
                    # echoing what we sent, so the caller sees what VT actually stored.
                    $vatValue = $null; $netValue = $null
                    $ve = $null; try { $ve = $t.VATEntry } catch { }
                    if ($ve) {
                        $vatValue = [double]$ve.BaseValue
                        $netValue = [double]$ve.VATTurnoverValue
                    }
                    $posted += [pscustomobject]@{
                        type = $t.Parent.Name; ref = $t.RefNumber
                        date = $t.DateNumber.ToString('yyyy-MM-dd')
                        text = $t.Text; lines = $t.Entries.Count
                        vat = $vatValue; net = $netValue
                    }
                }

                if ($Commit) {
                    $c.CommitTrans()
                    $v = $c.Verify()
                    $c.FlushBuffers()
                    [pscustomobject]@{ committed = $true; verify = [int]$v
                                       ok = ([int]$v -eq 0); posted = @($posted) } | ConvertTo-Json -Depth 4
                } else {
                    $c.RollbackTrans()
                    [pscustomobject]@{ committed = $false; verify = $null
                                       ok = $true; posted = @($posted) } | ConvertTo-Json -Depth 4
                }
            } catch {
                $c.RollbackTrans()
                throw
            }
        }
    }
  } catch {
    [pscustomobject]@{ ok = $false; committed = $false
                       error = $_.Exception.Message } | ConvertTo-Json -Depth 4
    exit 1
  }
}
finally {
    $c.CloseFile()
}
