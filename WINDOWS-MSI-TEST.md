# Testing the zoxide MSI on Windows (fork-only handoff)

Goal: confirm on a real Windows machine (x64 and ARM64 if available) that the
MSI fixes the problem in
[ajeetdsouza/zoxide#1180](https://github.com/ajeetdsouza/zoxide/issues/1180):
winget's portable install puts `zoxide.exe` behind a symlink, and that install
does not work over SSH, while an MSI install does.

GitHub Actions already shows that the MSI installs a real `zoxide.exe` of the
right architecture into `C:\Program Files\zoxide\bin`, adds it to the machine
PATH, runs over SSH, and uninstalls cleanly
(https://github.com/meop/zoxide/actions/runs/37183594306). What CI could not
show is the original failure: a winget-style symlink on the runner also ran
over SSH. So step 1 below, reproducing the failure, is the important one.

## 0. Get the MSI

The artifacts come from the fork's release workflow run on branch
`winget-wix-smoke`; one artifact per target holds the `.msi` and `.zip`.

With the GitHub CLI on the Windows machine:

```powershell
# x64 machine
gh run download 37183594306 -R meop/zoxide -n x86_64-pc-windows-msvc -D zoxide-x64
# ARM64 machine
gh run download 37183594306 -R meop/zoxide -n aarch64-pc-windows-msvc -D zoxide-arm64
```

Or open the run page above in a browser and download the artifact under
"Artifacts". Artifacts expire after 90 days; to rebuild:

```powershell
gh workflow run release.yml -R meop/zoxide --ref winget-wix-smoke
gh run list -R meop/zoxide --workflow release.yml --branch winget-wix-smoke --limit 1
```

## 1. Reproduce the original failure (winget portable)

Use your normal user account, not an administrator shell, and an SSH client on
another machine. OpenSSH Server's default shell on Windows is `cmd.exe` unless
`HKLM\SOFTWARE\OpenSSH\DefaultShell` is set; note which one you use.

```powershell
winget install --exact --id ajeetdsouza.zoxide
# In a NEW local terminal:
zoxide --version
Get-Item "$env:LOCALAPPDATA\Microsoft\WinGet\Links\zoxide.exe" | Format-List LinkType, Target
```

From the other machine:

```sh
ssh <user>@<host> zoxide --version
ssh <user>@<host> "pwsh -NoProfile -Command zoxide --version"
```

Record the exact output and error. If PowerShell is your SSH shell and your
profile runs `zoxide init powershell`, also record what happens at login.

Then remove it: `winget uninstall --exact --id ajeetdsouza.zoxide`.

## 2. MSI install

```powershell
msiexec /i zoxide-x64\zoxide-0.10.0-x86_64-pc-windows-msvc.msi
```

Use the interactive installer once to check the feature tree (Application,
and the "PATH Environment Variable" feature). Then, in a NEW terminal:

```powershell
(Get-Command zoxide).Source      # expect C:\Program Files\zoxide\bin\zoxide.exe
zoxide --version
```

Repeat the SSH commands from step 1 and record the output. With the shell init
hook in your profile, log in over SSH and run `z` once to confirm the hook works.

## 3. Both installed

Install the winget portable package alongside the MSI and record which
`zoxide` wins on PATH in a new local terminal and over SSH
(`where.exe zoxide`). Winget should prefer the MSI once the manifest lists it;
this checks what users who already have the portable install will see.

## 4. Uninstall

Uninstall from Settings > Apps (or `msiexec /x <msi>`). Confirm
`C:\Program Files\zoxide` is gone and `zoxide\bin` is no longer on the machine
PATH (`[Environment]::GetEnvironmentVariable('Path','Machine')`).

## Results

Record each step with the machine (x64 or ARM64, Windows version), the SSH
shell, and the commit this ran against.

| Step | Machine | Result |
| --- | --- | --- |
| 1. Portable over SSH | | |
| 2. MSI over SSH | | |
| 3. Both installed | | |
| 4. Uninstall | | |
