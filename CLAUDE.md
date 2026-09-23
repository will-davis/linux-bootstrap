# Project guidance

Personal Linux bootstrapper for Arch/CachyOS KDE desktops, Ubuntu/Debian SSH VMs,
and Raspberry Pi OS. Keep one entrypoint (`bootstrap.sh`) with small helpers in
`lib/` and `scripts/`; do not grow a dotfile management framework.

## Commands

```fish
./bootstrap.sh --dry-run
./bootstrap.sh --profile headless --nvim minimal --config-only
uv run --no-project python -m unittest discover -s tests -v
exec fish
# Inside nvim: :Lazy restore reproduces the lock; :Lazy sync updates it.
```

Full bootstrap installs packages and may perform a complete Arch system upgrade.
Use temporary homes/config-only runs for development, not the live machine's full
bootstrap as a routine test. No push/publishing without explicit permission.

## Contracts

- No hostname guards. Detect KDE via session or installed Plasma startup tools;
  support `--profile` for SSH provisioning. Detect Pi hardware/OS separately.
- Headless profiles never install GUI applications or apply KDE/input settings.
- Raspberry Pi defaults to distro Neovim with `minimal.lua`, no plugin stack.
  Full config needs Neovim >=0.11.3 and Node >=20 for fish-lsp.
- Keep apt/pacman package names and architecture differences explicit. Pacman
  uses full `-Syu` upgrades, never partial `-Sy` upgrades.
- Directory symlinks make this checkout live configuration. Back up existing
  paths, including symlinks. Preserve unrelated local changes.
- KDE files are selectively merged/copied because they mix shared preferences
  and machine state. `scripts/desktop.py capture` exports the portable subset.
  Do not claim all KConfig writers destroy file symlinks; local tests disproved it.
- Input-remapper shares defaults.json and the selected ProtoArc preset. Preserve
  other device presets/autoload state as ignored local data in the linked dir.
- Release binaries are verified and executed in staging before changing PATH.
  Keep prior installations usable on failure; do not start source builds on Pi.
- Fish is the user's shell. User-facing commands must be Fish-compatible.
  Keep kitten SSH/terminfo, OSC52, and kitty remote-control workflows intact.
- Guard project integrations by dependencies, with overrides in the untracked
  ~/.config/linux-bootstrap/local.fish. Hardware-specific display modes need an
  explicit local display profile. RayGLow auto-save is limited to a shader root.
- Atuin history/credentials/keys and Fish universal variables are machine-local.
  Never commit them. The optional server helper must preserve registration policy.
- Update README's behavior table and honest validation limits when changing behavior.
