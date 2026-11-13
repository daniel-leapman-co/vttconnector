# PowerShell entry point for vtt. PowerShell strips the quotes from arguments
# without spaces when it calls a .cmd file, so cmd.exe would read the | in
# "Ledger|Account" as a pipe. Calling Python directly avoids cmd.exe entirely.
$py = if ($env:VTT_PYTHON) { $env:VTT_PYTHON } else { "python" }
& $py (Join-Path $PSScriptRoot "vtt") @args
exit $LASTEXITCODE
