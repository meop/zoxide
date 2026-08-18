# winget WiX/.msi installer — WIP notes

Goal: give zoxide's winget manifest a real per-machine `.msi` installer (via
`cargo-wix`) alongside the existing portable/zip one, matching starship's
setup. Motivation: winget's portable installers land as a symlink in the
WinGet Links folder, and Windows blocks following symlinks over SSH by
default — breaking `zoxide` for anyone using it non-interactively (its own
shell-init hook, `zoxide init <shell>`, runs on every session start). Filed
upstream as a GitHub issue; maintainer agreed to accept a PR.

Reference implementation studied: starship/starship (`cargo wix` +
`install/windows/main.wxs`, see their `.github/workflows/release.yml`).

## What's done (commit 1eb22bb, branch `winget-wix-installer`)
- `install/windows/main.wxs` — new WiX v3 template, fresh `UpgradeCode` GUID
  (`76D6BAFA-6E4E-4057-A10F-5F3287CC51FD`), installs `zoxide.exe` under
  `Program Files\zoxide\bin`, registers that dir on system PATH.
- `.github/workflows/release.yml` — installs `cargo-wix` 0.3.9 on the Windows
  legs, builds `zoxide-<version>-<target>.msi`, uploads it alongside the zip.
- `.github/workflows/winget.yml` — widened `installers-regex` to also match
  `.msi` so `winget-releaser` picks up both installer types.

## Needs verification (none of this ran on a real Windows box)
- [ ] Confirm `cargo wix` actually builds cleanly for both
      `x86_64-pc-windows-msvc` and `aarch64-pc-windows-msvc` (no i686 target
      in zoxide's matrix).
- [ ] Confirm the resulting `.msi` installs correctly and actually lands
      zoxide on PATH — install, open a **new** shell, run `zoxide --version`.
- [ ] Confirm winget prefers the `.msi` over the `.zip` by default once both
      exist in a manifest (expected — winget's `InstallerTypeEnum` in
      winget-cli's `ManifestCommon.h` ranks Wix/Msi above Zip/Portable — but
      worth confirming end-to-end against a real generated manifest, ideally
      by manually testing with `wingetcreate` against these release assets).
- [ ] `Manufacturer` in the .wxs is currently `"zoxide Contributors"` —
      zoxide's `Cargo.toml` only lists one author; confirm this is the value
      the maintainer wants, or switch to the author's name.
- [ ] No icon/banner assets exist in-repo; template omits them cleanly. Fine
      to leave, or add later.

## Not in scope here
Submitting the actual winget-pkgs manifest update — that's a separate PR to
`microsoft/winget-pkgs` once the `.msi` exists as a real release asset and
the maintainer is ready to run `wingetcreate` (or once CI is verified to do
it automatically via the updated `installers-regex`).
