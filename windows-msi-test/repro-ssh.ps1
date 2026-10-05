# Runs on a Windows host from an elevated SSH session (an administrator's SSH
# session is elevated). Reproduces the winget portable install failing over
# SSH (ajeetdsouza/zoxide#1180), then shows the MSI install working:
#
# 1. winget installs the portable package from a NON-elevated context: a
#    scheduled task in the user's logged-in desktop session at medium
#    integrity, as from a normal terminal. (An S4U task runs at high
#    integrity for an administrator even with RunLevel Limited, so it does
#    not reproduce this.) Needs the user logged in at the console.
# 2. This elevated session runs the tool through that link. Windows refuses
#    to follow links created by less-privileged processes (redirection trust),
#    expected: error 448, "untrusted mount point".
# 3. The MSI installs a real file under Program Files with a machine PATH
#    entry; it runs from the same elevated session.
# 4. Both are removed again.
param(
    [Parameter(Mandatory)] [string] $WingetId,   # e.g. ajeetdsouza.zoxide
    [Parameter(Mandatory)] [string] $Exe,        # e.g. zoxide.exe
    [string] $Msi,                               # MSI to compare with (optional)
    [string[]] $VersionArgs = @('--version')
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$work = Join-Path $env:TEMP "repro-ssh-$($WingetId -replace '[^A-Za-z0-9]', '-')"
New-Item -ItemType Directory -Force $work | Out-Null
$task = "repro-ssh-$($WingetId -replace '[^A-Za-z0-9]', '-')"
$user = (whoami)
$link = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\$Exe"

function Invoke-Limited([string] $name, [string] $script) {
    # Runs $script as this user with a limited (non-elevated) token, waits,
    # and returns its output.
    $ps1 = Join-Path $work "$name.ps1"
    $out = Join-Path $work "$name.log"
    Set-Content -Path $ps1 -Value "& { $script } *> '$out'"
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ps1`""
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask -TaskName $task -Action $action -Principal $principal -Force | Out-Null
    Start-ScheduledTask -TaskName $task
    $deadline = (Get-Date).AddMinutes(10)
    do { Start-Sleep 2 } while ((Get-ScheduledTask -TaskName $task).State -eq 'Running' -and (Get-Date) -lt $deadline)
    Unregister-ScheduledTask -TaskName $task -Confirm:$false
    if (Test-Path $out) { Get-Content $out }
}

function Show-Link {
    $i = Get-Item $link -Force -ErrorAction SilentlyContinue
    if (-not $i) { return "no link at $link" }
    "link: $($i.LinkType) -> $($i.Target)  owner $((Get-Acl $link).Owner)"
}

"user: $user  elevated: $(([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrators'))"
"windows: $([Environment]::OSVersion.Version)  ssh shell: $((Get-ItemProperty 'HKLM:\SOFTWARE\OpenSSH' -ErrorAction SilentlyContinue).DefaultShell)"
if (Test-Path $link) { throw "a portable $Exe is already installed at $link; remove it first" }

if (-not ((quser 2>$null) -match "^\s*>?$($env:USERNAME)\s")) { throw "$env:USERNAME is not logged in at the console; the non-elevated step needs a desktop session" }
try {
    "== 1. winget portable install from a non-elevated context"
    Invoke-Limited 'label' "whoami /groups | Select-String 'Mandatory Label' | ForEach-Object { (`$_ -split '\s{2,}')[0] }" | ForEach-Object { "   integrity: $_" }
    Invoke-Limited 'install' "winget install --exact --id $WingetId --scope user --source winget --accept-package-agreements --accept-source-agreements --disable-interactivity | Select-Object -Last 2" |
        ForEach-Object { "   $_" }
    Show-Link
    "   from the same non-elevated context:"
    Invoke-Limited 'run-limited' "& '$link' $($VersionArgs -join ' '); 'exit=' + `$LASTEXITCODE" | ForEach-Object { "   $_" }

    "== 2. the same link from this elevated SSH session"
    try {
        $out = & $link @VersionArgs 2>&1 | ForEach-Object { "$_" }
        "   exit=$LASTEXITCODE  $($out -join ' / ')"
    } catch {
        "   failed to start: $($_.Exception.InnerException.Message ?? $_.Exception.Message)"
    }
    try { [void][IO.File]::ReadAllBytes($link); "   reading through the link: ok" } catch { "   reading through the link: $($_.Exception.InnerException.Message ?? $_.Exception.Message)" }

    if ($Msi) {
        "== 3. MSI install, run from this elevated SSH session"
        $p = Start-Process msiexec.exe -ArgumentList '/i', "`"$Msi`"", '/qn', '/l*v', "`"$work\msi-install.log`"" -Wait -PassThru
        "   msiexec exit: $($p.ExitCode)"
        $installed = Get-ChildItem "$env:ProgramFiles" -Recurse -Filter $Exe -ErrorAction SilentlyContinue | Select-Object -First 1
        "   installed: $($installed.FullName)  link type: '$($installed.LinkType)'"
        $out = & $installed.FullName @VersionArgs 2>&1 | ForEach-Object { "$_" }
        "   exit=$LASTEXITCODE  $($out -join ' / ')"
        $code = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' | Where-Object { $_.WindowsInstaller -eq 1 -and $_.InstallLocation -and $installed.FullName.StartsWith($_.InstallLocation) } | Select-Object -First 1).PSChildName
        if (-not $code) { $code = "`"$Msi`"" }
        $p = Start-Process msiexec.exe -ArgumentList '/x', $code, '/qn' -Wait -PassThru
        "   msiexec /x exit: $($p.ExitCode)  still installed: $(Test-Path $installed.FullName)"
    }
} finally {
    "== 4. remove the portable install"
    winget uninstall --exact --id $WingetId --source winget --disable-interactivity 2>&1 | Select-Object -Last 1 | ForEach-Object { "   $_" }
    "   link still present: $(Test-Path $link)"
    Remove-Item -Recurse -Force $work
    Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false
}
