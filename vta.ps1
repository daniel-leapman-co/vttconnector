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

    All writes run inside BeginTrans/CommitTrans. Without -Commit the work is
    rolled back, which leaves every entry and balance untouched — that is the
    dry run. The file's bytes still change: opening a company for write makes VT
    rewrite internal housekeeping whatever the rollback does. After a commit the
    company is re-verified and a non-zero VtaVerifyResult is reported as a
    failure.
#>
param(
    [Parameter(Mandatory=$true)][ValidateSet('info','accounts','tb','entries','post')][string]$Action,
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

$g = New-Object -ComObject VTA.GlobalMethods
$readOnly = ($Action -ne 'post')
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
