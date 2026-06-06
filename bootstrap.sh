#!/usr/bin/env bash
# linux-bootstrap — make a fresh box comfortable.
#
# Idempotent: safe to re-run any time (after a `git pull`, say).
# Supports: Arch/CachyOS (pacman) and Ubuntu/Debian/Raspberry Pi OS (apt).
#
# Usage:
#   ./bootstrap.sh                      # from a clone
#   curl -fsSL <raw-url> | bash        # from nothing (installs git, clones itself)
set -euo pipefail

REPO_URL="https://github.com/will-davis/linux-bootstrap.git"
CLONE_DIR="$HOME/linux-bootstrap"
NVIM_MIN="0.10"   # lazy.nvim ecosystem effectively requires >= 0.10 now

info() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m==> WARNING:\033[0m %s\n' "$*"; }

# ── locate ourselves / self-clone ───────────────────────────────────────────
# When piped from curl, BASH_SOURCE is unset (we're reading stdin), so there's
# no repo on disk yet: install git, clone, and re-exec from the clone.
if [[ -f "${BASH_SOURCE[0]:-}" ]]; then
    REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
    info "running from a pipe — cloning to $CLONE_DIR"
    if ! command -v git >/dev/null; then
        if command -v pacman >/dev/null; then sudo pacman -S --needed --noconfirm git
        else sudo apt-get update -qq && sudo apt-get install -y git; fi
    fi
    if [[ -d "$CLONE_DIR/.git" ]]; then
        git -C "$CLONE_DIR" pull --ff-only
    else
        git clone "$REPO_URL" "$CLONE_DIR"
    fi
    exec bash "$CLONE_DIR/bootstrap.sh"
fi

# ── packages ────────────────────────────────────────────────────────────────
if command -v pacman >/dev/null; then
    PM=pacman
    # -Syu, not -Sy: installing from a stale db after a partial refresh
    # ("partial upgrade") is how Arch boxes break. A fresh/remote Arch box
    # should be fully synced before adding packages anyway.
    info "pacman: syncing and installing packages"
    sudo pacman -Syu --needed --noconfirm \
        fish fzf zoxide fd ripgrep btop neovim git curl
elif command -v apt-get >/dev/null; then
    PM=apt
    info "apt: updating and installing packages"
    sudo apt-get update -qq
    # fd is packaged as fd-find (binary: fdfind) — Debian had a prior `fd` claim.
    # neovim deliberately NOT from apt: 24.04 ships 0.9.x, too old for lazy.nvim.
    sudo apt-get install -y \
        fish fzf zoxide fd-find ripgrep btop git curl ca-certificates
else
    echo "No supported package manager (pacman/apt) found." >&2
    exit 1
fi

# ── neovim (apt systems: GitHub release tarball) ────────────────────────────
nvim_recent_enough() {
    command -v nvim >/dev/null || return 1
    local v
    v="$(nvim --version | head -1 | sed 's/^NVIM v//')"
    # sort -V: if NVIM_MIN sorts first (or equal), installed version is >= min
    [[ "$(printf '%s\n' "$NVIM_MIN" "$v" | sort -V | head -1)" == "$NVIM_MIN" ]]
}

if [[ $PM == apt ]]; then
    if nvim_recent_enough; then
        info "nvim $(nvim --version | head -1) already present — skipping"
    else
        case "$(uname -m)" in
            x86_64)  NVIM_ARCH=x86_64 ;;
            aarch64) NVIM_ARCH=arm64 ;;
            *)       NVIM_ARCH="" ;;
        esac
        if [[ -n $NVIM_ARCH ]]; then
            info "installing neovim (latest release tarball, $NVIM_ARCH) to /opt"
            # Release tarballs are self-contained (bin/ + share/runtime).
            # /opt/<dir> + a symlink on PATH keeps removal trivial.
            sudo rm -rf "/opt/nvim-linux-$NVIM_ARCH"
            curl -fsSL "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-${NVIM_ARCH}.tar.gz" \
                | sudo tar -xz -C /opt
            sudo ln -sf "/opt/nvim-linux-$NVIM_ARCH/bin/nvim" /usr/local/bin/nvim
        else
            warn "unsupported arch $(uname -m) — falling back to apt neovim (may be too old for lazy.nvim)"
            sudo apt-get install -y neovim
        fi
    fi

    # fdfind -> fd shim (config.fish puts ~/.local/bin on PATH)
    mkdir -p "$HOME/.local/bin"
    ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
fi

# ── default shell ───────────────────────────────────────────────────────────
FISH_PATH="$(command -v fish)"
# chsh refuses shells not whitelisted in /etc/shells (packages add this, but belt+braces)
grep -qx "$FISH_PATH" /etc/shells || echo "$FISH_PATH" | sudo tee -a /etc/shells >/dev/null

CURRENT_SHELL="$(getent passwd "$USER" | cut -d: -f7)"
if [[ $CURRENT_SHELL != "$FISH_PATH" ]]; then
    info "setting default shell to fish"
    # sudo chsh: root may change any user's shell without the password
    # re-prompt plain `chsh` does — and sudo creds are already cached.
    sudo chsh -s "$FISH_PATH" "$USER"
else
    info "default shell already fish — skipping"
fi

# ── configs (symlink, don't copy) ───────────────────────────────────────────
# Symlinks mean edits made on this machine land in the repo working tree,
# so they can be committed and pushed back instead of drifting per-machine.
link_config() {
    local name=$1
    local target="$REPO_DIR/config/$name" dest="$HOME/.config/$name"
    mkdir -p "$HOME/.config"
    if [[ -L $dest ]]; then
        [[ "$(readlink -f "$dest")" == "$(readlink -f "$target")" ]] && return
        rm "$dest"
    elif [[ -e $dest ]]; then
        local bak="$dest.bak.$(date +%Y%m%d-%H%M%S)"
        warn "existing $dest moved to $bak"
        mv "$dest" "$bak"
    fi
    ln -s "$target" "$dest"
    info "linked ~/.config/$name -> $target"
}

link_config fish
link_config nvim

info "done. log out/in (or 'exec fish') to pick up the new shell."
