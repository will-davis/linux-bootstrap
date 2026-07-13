set -g fish_greeting
# ── distro hooks ────────────────────────────────────────────────────────────
# CachyOS ships a default config; this file only exists on the desktops.
# An unguarded `source` of a missing file errors on every shell startup.
if test -f /usr/share/cachyos-fish-config/cachyos-config.fish
    source /usr/share/cachyos-fish-config/cachyos-config.fish
end

# ~/.local/bin holds user-installed tools (and the fd shim on Ubuntu).
# -g = this session's $PATH only; the universal-variable default pollutes
# fish_variables, which this repo deliberately doesn't track.
fish_add_path -g ~/.local/bin
# ~/.cargo/bin: rustup-managed cargo + `cargo install` binaries (probe-rs, etc.).
fish_add_path -g ~/.cargo/bin

# ── kitty / TERM handling ───────────────────────────────────────────────────
# kitty sets TERM=xterm-kitty. If this host's terminfo db has no entry for it,
# ncurses apps (btop, nvim) misbehave. The real fix is `kitten ssh`, which
# copies the terminfo over on first connect; this is the remote-side safety net.
if test "$TERM" = xterm-kitty; and not infocmp xterm-kitty >/dev/null 2>&1
    set -gx TERM xterm-256color
end

# On machines that have kitty, make plain `ssh` carry terminfo along.
command -q kitten; and alias ssh='kitten ssh'

# ── tool init ───────────────────────────────────────────────────────────────
command -q zoxide; and zoxide init fish | source
# fzf >= 0.48 grew a native fish integration: ctrl-r history, ctrl-t files,
# alt-c cd. Older fzf (Ubuntu 24.04 ships 0.44) errors on --fish, hence 2>/dev/null.
command -q fzf; and fzf --fish 2>/dev/null | source

# fzf backend: fd, not fzf's built-in walker. With no FZF_DEFAULT_COMMAND, fzf
# walks in follow+hidden mode — it CHASES symlinks, so a Wine prefix's
# `dosdevices/w: -> /mnt` or Steam's Proton `drive_c -> /mnt/data/...` drags it
# onto the cold-storage platters and re-crawls duplicated DLL trees. fd fixes
# this structurally: it does NOT follow symlinks, and it honors ~/.config/fd/ignore
# (the blacklist) plus every git repo's own .gitignore.
#   --hidden            still descend into dotdirs like ~/.config (fd skips them by default)
#   -t f / -t d         files for the finder; dirs for alt-c's cd
#   --strip-cwd-prefix  drop the leading "./" from results
if command -q fd
    set -gx FZF_DEFAULT_COMMAND 'fd -t f --hidden --strip-cwd-prefix'
    set -gx FZF_CTRL_T_COMMAND $FZF_DEFAULT_COMMAND
    set -gx FZF_ALT_C_COMMAND 'fd -t d --hidden --strip-cwd-prefix'
end

# atuin: SQLite-backed shell history with fuzzy Ctrl-R + cross-machine sync.
# Sourced AFTER fzf on purpose — last bind wins in fish, so atuin takes Ctrl-R
# (its history TUI beats fzf's for this) while fzf keeps Ctrl-T / Alt-C untouched.
# --disable-up-arrow leaves fish's native up-arrow (prefix search) alone.
command -q atuin; and atuin init fish --disable-up-arrow | source

# ── ENV VARIABLES ───────────────────────────────────────────────────────────
set -gx GIT_DISCOVERY_ACROSS_FILESYSTEM 1 # github discovery across FS boundaries

# ── OTHER --------───────────────────────────────────────────────────────────

# Hotwire muscle-memory `ls` -> eza. Guarded: on a box without eza (fresh, or
# unsupported arch) these don't fire and `ls` stays real coreutils ls instead
# of erroring "command not found: eza". abbrs are interactive + command-position
# only, so scripts, functions, and `sudo ls` still get coreutils ls regardless.
if command -q eza
    abbr -a ls 'eza'
    abbr -a l 'eza'
end
abbr -a y 'yazi'
abbr -a pngnumber 'set a 1; for i in *; mv -- "$i" "$a.png"; set a (math $a + 1); end'

# ── desktop-only ────────────────────────────────────────────────────────────
if test (hostname) = will-desktop
    abbr -a comv 'source ~/comfyui-venv/ComfyUI/.venv/bin/activate.fish && uv run ~/comfyui-venv/ComfyUI/main.py --enable-manager'
    abbr -a png '~/.local/bin/organize_pngs.sh'

    function hey
        /home/will/.local/bin/hey_llamacpp.py $argv
    end
    function heyclaude
        /home/will/.local/bin/hey_claude.py $argv
    end
end

