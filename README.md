# linux-bootstrap

One entrypoint for personal KDE desktops, SSH-only Ubuntu/Debian VMs, and
Raspberry Pi OS. Arch/CachyOS uses pacman; Debian-family systems use apt.
Run as your normal user: the script uses sudo only where required.

## Usage

```fish
git clone https://github.com/will-davis/linux-bootstrap.git
./linux-bootstrap/bootstrap.sh
```

Or, on a fresh machine with curl installed:

```fish
curl -fsSL https://raw.githubusercontent.com/will-davis/linux-bootstrap/main/bootstrap.sh | bash
```

The pipe entrypoint clones to `~/linux-bootstrap`, or fast-forward pulls that
clone, then executes the script from it. Local-only commits are not available
through this URL until explicitly pushed.

```fish
./bootstrap.sh --dry-run                         # inspect decisions; no writes/downloads
./bootstrap.sh --profile headless                # force terminal-only setup
./bootstrap.sh --profile kde                     # provision an existing KDE installation over SSH
./bootstrap.sh --nvim minimal                    # plugin-free Neovim on any machine
./bootstrap.sh --config-only                     # apply user settings; no package/service/chsh changes
```

Flags also work through the pipe: append `| bash -s -- --profile headless`.
The script may ask for sudo authentication, AUR review, or confirmation of a
conflicting Sublime package replacement. It does not install Plasma itself.

If an installation stops after installing packages, the configuration stage may
not have run yet. Fix the reported error and rerun the checkout's `bootstrap.sh`;
it retains installed packages and backs up existing configuration before linking.
When all applications are already installed, `--config-only` can finish the user
settings without sudo. It does not enable the Input-remapper system service;
that requires `sudo systemctl enable --now input-remapper.service`.

## Selection rules

There are no hostname checks. KDE is selected when `XDG_CURRENT_DESKTOP` includes
KDE **or** a Plasma startup executable is installed. The latter works over SSH
to a desktop. Otherwise the profile is headless. `--profile` overrides detection.

Raspberry Pi hardware (`/proc/device-tree/model`) or Raspberry Pi OS
(`/etc/rpi-issue`) selects **minimal Neovim**. Other x86-64/ARM64 machines select
full Neovim. Other architectures default to minimal. This choice is stored in
`~/.config/linux-bootstrap/nvim-mode`, outside the shared configuration.
A 32-bit Debian userland is detected even under a 64-bit kernel.

## What it does

| Feature | All machines | KDE profile additions |
|---|---|---|
| Shell/tools | Fish, fzf, zoxide, fd, ripgrep, btop, git, curl, file, jq, Atuin, Yazi; eza when available | kitty, preserving `kitten ssh` and terminal remote control |
| Neovim | Full or minimal configuration, selected separately from desktop profile | Native clipboard tools |
| Full Neovim dependencies | C compiler/make, unzip, Node/npm; Node >=20 for current fish-lsp | Same full configuration |
| Editors/browser | Terminal editor only | Official Sublime Text stable repository, Firefox Developer Edition |
| Config directories | Symlink Fish, Neovim, fd, Atuin to this checkout | Also kitty and Input-remapper |
| KDE shortcuts | Skipped | Custom window shortcuts plus Super+F/S/T application launchers |
| Dolphin | Skipped | Toolbar order/icons, view/context-menu preferences, kitty terminal selection |
| Input-remapper | Skipped | Install, enable service, import selected ProtoArc preset; load at next login |
| Existing settings | Back up before replacing directories or changing managed files | Preserve unrelated KDE entries and other input-device presets |

`XDG_CONFIG_HOME` and `XDG_DATA_HOME` are honored; paths below show their defaults.
The repository is live configuration: edits to linked directories take effect
when the corresponding application reloads them.

### Packages and downloads

- **Arch/CachyOS:** core packages come from pacman, using `-Syu`, never `-Sy`.
  This deliberately includes a full system upgrade. Input-remapper uses the
  distro package if available, otherwise the upstream-recommended AUR
  `input-remapper-git` via paru/yay, or a normal-user `makepkg` build.
- **Ubuntu/Debian:** core tools use apt when available. Missing Atuin/Yazi/eza
  binaries on x86-64/ARM64 come from official GitHub releases. Full Neovim uses
  the installed version if >=0.11.3, otherwise an official release. If Node is
  older than 20, the full profile adds the current official Node LTS distribution.
- Release downloads are checked against upstream SHA-256 metadata, extracted
  into a staging directory, and executed with `--version` before PATH changes.
  Neovim also gets a clean headless launch. Installations live under
  `~/.local/share/linux-bootstrap/releases/`, with links in `~/.local/bin`.
  Existing installations/PATH entries are retained or backed up. A failed
  download or incompatible binary leaves the previous installation usable.
- These user-installed release binaries are installed when missing/too old;
  bootstrap is not a general updater for them. Re-run `scripts/releases.py
  install TOOL --arch x86_64` with Python to explicitly refresh one.
- **32-bit ARM:** minimal Neovim comes from apt. Atuin/Yazi are installed if the
  distro supplies them; current upstream releases have no 32-bit ARM assets.
  Unavailable tools are explicitly reported and skipped, without starting a
  Rust build. Use 64-bit Raspberry Pi OS for the complete core toolset.
- Yazi's required `file` utility is included. Large optional video/PDF/image
  preview stacks are not installed on headless VMs.

Sublime is installed from the vendor's signed stable repository. The current
AUR `sublime-text-4` provider is replaced within a pacman transaction, not removed
first. That conflict confirmation is intentionally interactive. On apt, Firefox
Developer Edition comes from Mozilla's signed repository. Repository signing-key
fingerprints are checked before import. Input-remapper on apt requires >=2.2.1;
older distro versions use the upstream release `.deb` with dependency resolution.

Sources: [Sublime repositories](https://www.sublimetext.com/docs/linux_repositories.html),
[Mozilla Linux packages](https://support.mozilla.org/en-US/kb/install-firefox-linux),
[Input-remapper installation](https://github.com/sezanzeb/input-remapper#installation),
[Yazi installation](https://yazi-rs.github.io/docs/installation/),
[Node distributions](https://nodejs.org/en/download).

## Fish, searching, and SSH

| Shortcut | Behavior |
|---|---|
| Ctrl+T | Files, including hidden and Git-ignored files |
| Alt+C | Visible directories, respecting normal ignore rules |
| Ctrl+R | Atuin history |
| Up arrow | Fish's normal prefix history |

Ctrl+T uses `fd --hidden --no-ignore-vcs`, so ignored shader directories remain
searchable while `.fdignore` and the global `config/fd/ignore` continue excluding
virtual environments, node_modules, caches, and Wine/Proton junk. Neither picker
follows directory symlinks. No Ctrl+F binding is added. Packaged fzf integrations
are used on older apt releases that do not support `fzf --fish`.

On machines with kitten, `ssh` is an alias for `kitten ssh`, which carries kitty
terminfo to the destination. The remote side falls back from `xterm-kitty` to
`xterm-256color` only if the terminfo entry is missing. Kitty's remote-control
settings are retained. Twilio Sans Mono remains the preferred font; kitty will
fall back if it is unavailable. Arch installs JetBrains Mono Nerd Font for the
existing symbol map; apt users may install their preferred Nerd Font separately.

`y` and `yazi` preserve the selected working directory on exit. Project-specific
abbreviations appear only when their project files and required commands exist.

## Neovim modes

**Full:** Neovim >=0.11.3, Lazy with the committed `lazy-lock.json`, Telescope,
completion, Mason/LSP, bufferline, GLSL highlighting, and the existing UI choices.
Mason installs pyright, bash-language-server, fish-lsp, lua-language-server, and
glsl_analyzer. First launch needs network access to install plugins/tools.
Use `:Lazy restore` to reproduce pinned plugin revisions. `:Lazy sync` updates
plugins; review and commit its lockfile changes deliberately.

**Minimal:** no Lazy, Mason, plugin downloads, or native plugin builds. Keeps
line numbers, four-space indentation, normal folds, and clipboard behavior. The
config automatically falls back to this mode on Neovim below 0.11.3 even if the
machine-local mode file was not created yet.

Over SSH, Neovim >=0.10 uses its OSC 52 provider. Older Neovim supports OSC 52
**copy**, with the last yank cached locally for `p`; paste external clipboard
text using kitty's terminal paste shortcut. It does not install an old plugin
stack to emulate newer Neovim.

RayGLow auto-push is enabled only with `RAYGLOW_HOST`, the helper checkout, and
Python available. Saving GLSL auto-pushes only inside `RAYGLOW_SHADER_ROOT`
(default `~/Projects/rayglow`). Manual RayGLow commands remain available when the
integration is enabled. Avante can be disabled with `LINUX_BOOTSTRAP_AI=0`;
`LLAMA_CPP_ENDPOINT` and `LLAMA_CPP_MODEL` override its local server defaults.

## KDE, Dolphin, and Input-remapper

| Shortcut | Action |
|---|---|
| Super+F | Firefox Developer Edition, new window |
| Super+S | Sublime Text, new file |
| Super+T / Alt+Shift+T | kitty |

Bootstrap creates its own small `.desktop` launchers with stable IDs so Arch and
apt application naming differences do not break the shortcuts. Conflicting
existing assignments to managed shortcuts are cleared while unrelated shortcuts
are retained. `config/kde/shortcuts.json` contains the customized portable KDE
bindings, not a whole-machine snapshot with activity UUIDs and app instances.

Dolphin's toolbar lives in `~/.local/share/kxmlgui5/dolphin/dolphinui.rc`, including
on this Plasma 6 desktop. The captured toolbar and action properties retain its
layout; the custom icon assets are installed into the user's data directory.
Dolphin preferences are merged into `dolphinrc`, preserving existing home paths
and window geometry. Only the terminal-selection entries of `kdeglobals` are
managed. Plugin-provided actions/previews still require the corresponding plugin
on the target machine. Directory-specific `.directory` files and Places/bookmarks
are not transferred.

Input-remapper's directory is symlinked to `config/input-remapper-2` after backing
up the old directory. The shared default selects:

`ProtoArc EM05NL` → `will-260903`

The preset is copied exactly. Its origin hash is derived from device name and
capabilities, so moving the same device/configuration between machines is
supported by Input-remapper. A different Bluetooth/receiver identity may still
need reassociation. Other existing device presets and autoload choices are
preserved as ignored local files. `defaults.json` is shared; runtime `config.json`
is ignored. This keeps other keyboards out of the shared autoload policy.

Close/reopen Dolphin after applying settings and log out/in to load shortcuts and
remapper autoload. Bootstrap does not stop an active input injector mid-keystroke.
KDE applications can rewrite their settings; close Dolphin before capturing or
applying its configuration if you have just edited its toolbar.

Capture later GUI changes back into the repository:

```fish
python3 scripts/desktop.py capture
git diff
```

Capture covers the portable KDE window bindings, Dolphin preferences/toolbar,
and the active ProtoArc preset. The three application launch shortcuts are the
fixed defaults above. Other application shortcuts remain local. If you rename
the shared preset again, review `.gitignore` and explicitly track the new preset.
Backups and empty old presets are not added automatically.

## Machine-local settings and Atuin

Put optional overrides in `~/.config/linux-bootstrap/local.fish`; this file is
sourced before tool initialization and is never copied into the repo. For example:

```fish
set -gx ATUIN_SYNC_ADDRESS https://your-sync-server.example
set -gx RAYGLOW_HOST your-renderer
set -gx RAYGLOW_SHADER_ROOT ~/Projects/your-shaders
set -gx LINUX_BOOTSTRAP_AI 0
```

`display-hdr` and `display-light` use mode IDs for a particular S90D/Denon pair.
They require an explicit local `BOOTSTRAP_DISPLAY_PROFILE=s90d-denon` setting and
kscreen-doctor. KDE alone is insufficient to identify those monitors.

Atuin's existing private sync target is retained; machines outside that network
can override `ATUIN_SYNC_ADDRESS`, or use `ATUIN_AUTO_SYNC=false` for local-only
history. History starts working without logging in. Bootstrap never copies the
history database, login credentials, or encryption key. Import old shell history
once with `atuin import auto`; authenticate other machines with `atuin login`
and your encryption key, then `atuin sync`.

`server/atuin-server.sh` is an **optional** apt/systemd PostgreSQL server helper;
it is never run by bootstrap. It supports both a standalone `atuin-server` and
older `atuin server` builds, records the actual executable path, and preserves
existing listen/registration policy. Credentials migrate out of the systemd unit
into a root-only environment file. New servers bind loopback with registration
closed; no firewall rules are added. Explicitly set `ATUIN_HOST`, `ATUIN_PORT`, or
`ATUIN_OPEN_REGISTRATION` when provisioning if needed, then close registration
after creating your account. Re-runs do not reopen registration.

## Validation and current limits

The offline regression checks use temporary homes and stub package-manager
calls, with no sudo or external services:

```fish
uv run --no-project python -m unittest discover -s tests -v
```

The development validation includes syntax checks, repeat config application
from both fresh and existing settings, Input-remapper's stderr version output,
KDE merge/conflict and local-device preservation, fd behavior, staged-download
failure handling, and a real minimal Neovim launch. Full Neovim startup is checked
separately against copies of the pinned plugins. Official x86-64 release binaries
are downloaded and executed in a temporary home during release validation.

A CachyOS installation on `will-lab` confirmed the package set and configuration
links, Fish bindings, KDE launcher entries, and the running trackball preset.
Full Neovim also passed a fresh plugin/native-library installation and completed
all five Mason language-server installations there. Final GUI/physical mouse
behavior, a complete apt/ARM package installation, and PostgreSQL provisioning
still need target-machine verification. These are not implied by the offline
checks. There is no Docker/VM test requirement.
