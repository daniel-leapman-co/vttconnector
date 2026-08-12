"""Drive the VTA COM connector from WSL.

VTA.dll is a 32-bit Windows COM server, so the work happens in 32-bit
PowerShell on the Windows host. This module handles the interop details:
locating that interpreter, converting paths, and staging files that live on
the Linux side of WSL (COM cannot open them in place).

    python3 vtaconnect.py tb       <file.vtr> 2026-06-30
    python3 vtaconnect.py accounts <file.vtr>
    python3 vtaconnect.py entries  <file.vtr>
    python3 vtaconnect.py post     <file.vtr> journal.json [--commit]

Without --commit a post is rolled back, which leaves the file unchanged.
"""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

PS32 = Path("/mnt/c/Windows/SysWOW64/WindowsPowerShell/v1.0/powershell.exe")
SCRIPT = Path(__file__).with_name("vta.ps1")
STAGE = Path("/mnt/c/Temp/vtaconnect")


class VtaError(RuntimeError):
    pass


def _decode(b: bytes) -> str:
    """PowerShell may hand back UTF-8 or the Windows OEM code page. Try both."""
    for enc in ("utf-8", "cp1252", "cp850"):
        try:
            return b.decode(enc)
        except UnicodeDecodeError:
            continue
    return b.decode("utf-8", errors="replace")


def _win_path(p: Path) -> str:
    out = subprocess.run(["wslpath", "-w", str(p)], capture_output=True, text=True)
    if out.returncode:
        raise VtaError(f"cannot map {p} to a Windows path")
    return out.stdout.strip()


def _run(action: str, vtr: Path, *, date=None, spec=None, commit=False):
    """Run one action. Files outside /mnt are staged onto the Windows side."""
    if not PS32.exists():
        raise VtaError(f"32-bit PowerShell not found at {PS32}")
    vtr = vtr.resolve()
    if not vtr.exists():
        raise VtaError(f"no such file: {vtr}")

    STAGE.mkdir(parents=True, exist_ok=True)
    staged = not str(vtr).startswith("/mnt/")
    work = STAGE / vtr.name if staged else vtr
    if staged:
        shutil.copy2(vtr, work)

    # The .ps1 is always staged: 32-bit PowerShell will not run scripts over UNC.
    # Stage it with a BOM: Windows PowerShell 5 reads a BOM-less script in the
    # legacy ANSI code page, which mangles any non-ASCII character in the source
    # and turns one inside a string literal into a parse error.
    script = STAGE / SCRIPT.name
    script.write_text(SCRIPT.read_text(encoding="utf-8"), encoding="utf-8-sig")

    cmd = [str(PS32), "-NoProfile", "-ExecutionPolicy", "Bypass",
           "-File", _win_path(script), "-Action", action, "-File", _win_path(work)]
    tmp_spec = None
    if date:
        cmd += ["-Date", date]
    if spec is not None:
        tmp_spec = STAGE / "posting.json"
        tmp_spec.write_text(json.dumps(spec), encoding="utf-8")
        cmd += ["-Json", _win_path(tmp_spec)]
    if commit:
        cmd += ["-Commit"]

    # Capture bytes, not text: older PowerShell hosts still emit the OEM code
    # page for some streams, and one accented narrative should not kill a run.
    proc = subprocess.run(cmd, capture_output=True)
    out = _decode(proc.stdout).replace("\r", "").strip()
    try:
        result = json.loads(out) if out else None
    except json.JSONDecodeError:
        result = None
    if result is None:
        err = _decode(proc.stderr)
        raise VtaError((err or out or "no output").replace("\r", "").strip())
    if isinstance(result, dict) and result.get("error"):
        raise VtaError(result["error"])

    # Only copy back when the file actually changed, so dry runs cannot touch it.
    if staged and commit:
        shutil.copy2(work, vtr)
    if tmp_spec:
        tmp_spec.unlink(missing_ok=True)
    return result


def info(vtr): return _run("info", Path(vtr))
def accounts(vtr): return _run("accounts", Path(vtr))
def entries(vtr): return _run("entries", Path(vtr))
def trial_balance(vtr, date): return _run("tb", Path(vtr), date=date)


def post(vtr, spec, commit=False):
    """Post transactions. `spec` is a dict or list of dicts:

        {"type": "PAY", "date": "2026-06-30", "text": "...",
         "lines": [{"account": "Bank|Current account", "amount": -120.0},
                   {"account": "Travel", "amount": 100.0, "vat": 20.0}]}

    Amounts are signed: positive debit, negative credit, and each transaction
    must sum to zero. Accounts are "Name" or "Ledger|Name" where ambiguous.

    A line's optional "vat" is the VAT on that net amount, signed the same way.
    Never add a line for the VAT account itself: VT owns that entry, and only
    the entry VT creates carries the net figure (VATTurnoverValue) the return
    analyses into box 6/7. Omitting "vat" leaves the line outside VAT scope;
    a "vat" of 0 keeps it on the return at a nil rate. The first line of a
    transaction becomes its primary entry, so on a PAY/REC/CCP put the bank or
    control account first — VT will not accept a VAT flag before that exists.
    """
    return _run("post", Path(vtr), spec=spec, commit=commit)


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    action, path = argv[1], argv[2]
    try:
        if action == "accounts":
            r = accounts(path)
        elif action == "entries":
            r = entries(path)
        elif action == "tb":
            r = trial_balance(path, argv[3])
        elif action == "post":
            spec = json.loads(Path(argv[3]).read_text())
            r = post(path, spec, commit="--commit" in argv)
            if not r.get("ok"):
                print(json.dumps(r, indent=2))
                print(f"\nVERIFY FAILED (VtaVerifyResult={r.get('verify')})", file=sys.stderr)
                return 1
        else:
            print(__doc__)
            return 2
    except VtaError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1
    print(json.dumps(r, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
