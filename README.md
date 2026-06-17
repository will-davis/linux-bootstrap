# linux-bootstrap

Make a fresh Linux box comfortable in one shot. Supports Arch/CachyOS (pacman)
and Ubuntu/Debian/Raspberry Pi OS (apt). Idempotent — re-run after any `git pull`.

## Usage

From a clone:

```fish
git clone https://github.com/will-davis/linux-bootstrap.git
./linux-bootstrap/bootstrap.sh
```

From a box with nothing on it (requires the repo to be public; the script
installs git, clones itself to `~/linux-bootstrap`, and re-execs):

```fish
curl -fsSL https://raw.githubusercontent.com/will-davis/linux-bootstrap/main/bootstrap.sh | bash
```

## What it does

| Step | Detail |
|------|--------|
| Packages | fish, fzf, zoxide, fd, ripgrep, btop, git, curl |
| neovim | pacman: distro package (current). apt: GitHub release tarball → `/opt`, symlinked to `/usr/local/bin/nvim` (apt's 0.9.x is too old for lazy.nvim). x86_64 + aarch64. |
| eza | pacman: distro package. apt: GitHub release binary → `~/.local/bin/eza` (not in Ubuntu 24.04 / Debian bookworm repos). x86_64 + aarch64. The `ls`/`l` abbrs map to it, but only fire when eza is present. |
| fd shim | Ubuntu packages fd as `fd-find` with binary `fdfind`; a `~/.local/bin/fd` symlink restores the real name |
| Default shell | `sudo chsh -s (command -v fish)`, skipped if already set |
| Configs | Symlinks `~/.config/fish` and `~/.config/nvim` into this repo (existing dirs are backed up, not deleted). Edits on any machine can be committed back. |

## kitty TERM strategy

Two layers, both in `config/fish/config.fish`:

1. On machines with kitty installed: `alias ssh='kitten ssh'` — copies the
   `xterm-kitty` terminfo entry to the remote on first connect, so remotes
   understand kitty natively.
2. On remotes reached some other way: if `TERM=xterm-kitty` but the host's
   terminfo db has no entry for it, fall back to `TERM=xterm-256color`.

## Notes

- Desktop-only abbrs/functions in `config.fish` are fenced behind
  `if test (hostname) = will-desktop`.
- `config/fish/fish_variables` is gitignored: it's machine-local runtime state.
- nvim plugins are pinned by `config/nvim/lazy-lock.json`; lazy.nvim bootstraps
  itself on first `nvim` launch (needs git + network).
- fzf's fish keybindings (ctrl-r history, ctrl-t files, alt-c cd) need
  fzf ≥ 0.48; on older fzf (Ubuntu 24.04) the init line no-ops silently.
