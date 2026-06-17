# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A personal dotfiles bootstrapper: one script (`bootstrap.sh`) that makes a fresh
Linux box comfortable, plus the `config/` tree it symlinks into `~/.config`.
There is no build, no test suite, no app. "Running" it means executing the
bootstrap script; "developing" it means editing files under `config/` and
committing. There are two consumers — Arch/CachyOS (pacman) desktops and
apt-based boxes (Ubuntu server, Raspberry Pi OS) — and almost every design
decision in here is about making one tree work correctly on both.

## Commands

```fish
./bootstrap.sh          # apply everything; idempotent, safe to re-run after a git pull
exec fish               # reload shell config after editing config/fish/
:Lazy sync              # (inside nvim) reconcile plugins against lazy-lock.json
```

There is no lint or test. To "verify" a change, re-run `bootstrap.sh` (it should
no-op the unchanged steps) or open `nvim`/`fish` and observe.

## Architecture

**Symlinks, not copies.** `bootstrap.sh::link_config` points `~/.config/fish`
and `~/.config/nvim` *at* this repo's working tree. So edits made on any machine
land in the repo and can be committed back — the repo is the live config, not a
snapshot of it. Backups of pre-existing dirs are made (`.bak.<timestamp>`), never
deleted. This is why `config/fish/fish_variables` is gitignored: the symlink
drags fish's machine-local runtime state into the tree, and it must not be tracked.

**Dual-distro is the core constraint.** `bootstrap.sh` branches on
`command -v pacman` vs `apt-get`. The non-obvious apt-side workarounds, each
load-bearing:
- **neovim is installed from the GitHub release tarball on apt, not the package** — Ubuntu 24.04 ships 0.9.x, too old for the lazy.nvim ecosystem (`NVIM_MIN=0.10`). Tarball goes to `/opt/nvim-linux-<arch>` + a symlink on PATH; arch-gated to x86_64/aarch64.
- **`fd` shim** — apt packages it as `fd-find` with binary `fdfind`; bootstrap symlinks `~/.local/bin/fd` to restore the real name (and `config.fish` puts `~/.local/bin` on PATH).
- pacman uses `-Syu` (full sync), deliberately not `-Sy`, to avoid partial-upgrade breakage.

**One config tree, host-conditioned.** Files must source/run cleanly on every
box, so divergence is fenced at runtime rather than forked:
- `config.fish` guards the CachyOS default-config `source` behind a file-exists test, and fences desktop-only abbrs/functions behind `if test (hostname) = will-desktop`. New machine-specific shell bits follow that pattern.
- `init.lua` enables the OSC 52 clipboard provider only under `SSH_TTY` (+ nvim-0.10), so local boxes keep their native `wl-clipboard`. lazy.nvim self-bootstraps on first launch; plugins are pinned by `lazy-lock.json` (commit lock changes alongside plugin edits).

**kitty TERM strategy (two layers, both in `config.fish`).** On hosts with kitty,
`alias ssh='kitten ssh'` ships the `xterm-kitty` terminfo to remotes. As a
remote-side safety net, if `TERM=xterm-kitty` but the local terminfo db lacks the
entry, it falls back to `xterm-256color` so ncurses apps don't misbehave.

**Self-clone path.** Run via `curl … | bash`, `BASH_SOURCE` is unset, so the
script installs git, clones itself to `~/linux-bootstrap`, and re-execs. From a
clone it just locates its own dir and proceeds.

## Conventions

- Edits are expected to be made *in place* (via the symlink) on whatever box, then committed here — there is no separate "install" step to re-run for config changes, only `exec fish` / reopening nvim.
- Keep both distros working. Before adding a package or path, consider whether the binary name / availability differs on pacman vs apt and guard accordingly.
- `bootstrap.sh` is `set -euo pipefail` and idempotent by contract — every step checks "already done?" and skips. Preserve that when adding steps.
- The README's "What it does" table is user-facing documentation; update it when behavior changes.
