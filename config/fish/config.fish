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

# ── ENV VARIABLES ───────────────────────────────────────────────────────────
set -gx GIT_DISCOVERY_ACROSS_FILESYSTEM 1 # github discovery across FS boundaries

# ── OTHER --------───────────────────────────────────────────────────────────
alias ls='ls -1 --color=auto'

abbr -a y 'yazi'
abbr -a pngnumber 'set a 1; for i in *; mv -- "$i" "$a.png"; set a (math $a + 1); end'

# ── desktop-only ────────────────────────────────────────────────────────────
if test (hostname) = will-desktop
    abbr -a comv 'source ~/comfyui-venv/ComfyUI/.venv/bin/activate.fish && uv run ~/comfyui-venv/ComfyUI/main.py --enable-manager'
    abbr -a ppllama '~/Documents/sys-prompts/llama-server-cpp.fish'
    abbr -a png '~/.local/bin/organize_pngs.sh'
    abbr -a qc 'cd ~/gemini/claude && claude'

    function hey
        /home/will/.local/bin/hey_claude.py $argv
    end
end
