#!/usr/bin/env bash
# Copy repro-ssh.ps1 (and an MSI, if given) to a Windows host and run it from
# an SSH session there. E.g.:
#   windows-msi-test/run-on-host.sh glass.lan 22 ajeetdsouza.zoxide zoxide.exe path/to/zoxide.msi
set -euo pipefail
host=${1:?usage: run-on-host.sh <host> <port> <winget-id> <exe> [msi]}
port=${2:?}; id=${3:?}; exe=${4:?}; msi=${5:-}
here=$(cd "$(dirname "$0")" && pwd)
remote_rel='AppData/Local/Temp/repro-ssh'
remote_win='$env:TEMP\repro-ssh'
ssh -o BatchMode=yes -p "$port" "$host" "New-Item -ItemType Directory -Force $remote_win | Out-Null" </dev/null
scp -o BatchMode=yes -q -P "$port" "$here/repro-ssh.ps1" ${msi:+"$msi"} "$host:$remote_rel/"
msi_arg=${msi:+-Msi $remote_win\\$(basename "$msi")}
mkdir -p "$here/logs"
log=$here/logs/repro-ssh-$host-$(date -u +%Y%m%dT%H%M%SZ).log
status=0
ssh -o BatchMode=yes -p "$port" "$host" \
  "pwsh -NoProfile -NonInteractive -File $remote_win\\repro-ssh.ps1 -WingetId $id -Exe $exe $msi_arg; Remove-Item -Recurse -Force $remote_win" </dev/null 2>&1 | tee "$log" || status=$?
echo "log: $log"
exit "$status"
