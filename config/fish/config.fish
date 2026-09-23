set -g fish_greeting
if test -f /usr/share/cachyos-fish-config/cachyos-config.fish
    source /usr/share/cachyos-fish-config/cachyos-config.fish
end
fish_add_path -g ~/.local/bin ~/.cargo/bin

# Per-machine overrides stay outside the symlinked tree. This is useful for
# ATUIN_SYNC_ADDRESS, RAYGLOW_HOST, or optional workstation integrations.
set -l bootstrap_config ~/.config/linux-bootstrap
if set -q XDG_CONFIG_HOME
    set bootstrap_config "$XDG_CONFIG_HOME/linux-bootstrap"
end
if test -f "$bootstrap_config/local.fish"
    source "$bootstrap_config/local.fish"
end

# Preserve kitty's SSH terminfo transport and remote-side safety net.
if test "$TERM" = xterm-kitty; and not infocmp xterm-kitty >/dev/null 2>&1
    set -gx TERM xterm-256color
end
command -q kitten; and alias ssh='kitten ssh'
set -gx EDITOR nvim
set -gx VISUAL nvim
set -gx GIT_DISCOVERY_ACROSS_FILESYSTEM 1

# Hidden and Git-ignored files are useful; .fdignore and the global junk list
# still apply. fd does NOT follow symlinks into Wine prefixes/mounted storage.
if command -q fd
    set -gx FZF_DEFAULT_COMMAND 'fd -t f --hidden --no-ignore-vcs --exclude .git'
    set -gx FZF_CTRL_T_COMMAND $FZF_DEFAULT_COMMAND
    # Alt+C is the directory picker: visible directories, normal ignore rules.
    set -gx FZF_ALT_C_COMMAND 'fd -t d --exclude .git'
end

if status is-interactive
    fish_vi_key_bindings
    command -q zoxide; and zoxide init fish | source
    # Prefer the packaged integration: also works with Ubuntu's pre-0.48 fzf.
    if functions -q fzf_key_bindings
        fzf_key_bindings
    else if test -f /usr/share/doc/fzf/examples/key-bindings.fish
        source /usr/share/doc/fzf/examples/key-bindings.fish
    else if test -f /usr/share/fzf/key-bindings.fish
        source /usr/share/fzf/key-bindings.fish
    else if command -q fzf
        fzf --fish 2>/dev/null | source
    end
    # Last binding wins: Atuin owns Ctrl+R; native up-arrow remains available.
    command -q atuin; and atuin init fish --disable-up-arrow | source
end

# Yazi changes the parent shell's cwd through a temporary file.
function y
    set -l tmp (mktemp -t yazi-cwd.XXXXXX)
    command yazi $argv --cwd-file="$tmp"
    set -l result $status
    set -l cwd (cat -- "$tmp")
    if test -n "$cwd"; and test "$cwd" != "$PWD"
        builtin cd -- "$cwd"
    end
    rm -f -- "$tmp"
    return $result
end
command -q yazi; and alias yazi='y'
if command -q eza
    abbr -a ls eza
    abbr -a l eza
end
abbr -a pngnumber 'set a 1; for i in *; mv -- "$i" "$a.png"; set a (math $a + 1); end'

# Project tools follow their dependencies, not the machine's hostname.
if test -f ~/comfyui-venv/ComfyUI/.venv/bin/activate.fish; and command -q uv
    abbr -a comv 'source ~/comfyui-venv/ComfyUI/.venv/bin/activate.fish && uv run ~/comfyui-venv/ComfyUI/main.py --enable-manager'
end
if test -x ~/.local/bin/organize_pngs.sh
    abbr -a png '~/.local/bin/organize_pngs.sh'
end
if test -f ~/Projects/rayglow/tools/rayglow_ctl.py; and command -q python3
    abbr -a rgc 'python3 ~/Projects/rayglow/tools/rayglow_ctl.py'
end
if test -f ~/Projects/rayglow/sender/sender.py; and command -q uv
    abbr -a soundbr 'cd ~/Projects/rayglow/sender/ && uv run sender.py'
end
if test -f ~/Projects/rayglow-agent/package.json; and command -q npm
    abbr -a rg-agent 'cd ~/Projects/rayglow-agent/ && npm run tui -- --preview-fps 120'
end
if test -d ~/Projects/rayglow-terminal-control; and command -q uv
    abbr -a rg-tui 'cd ~/Projects/rayglow-terminal-control/ && uv run rayglow-tui'
end
if test -x ~/.local/bin/hey_llamacpp.py
    function hey
        ~/.local/bin/hey_llamacpp.py $argv
    end
end
if test -x ~/.local/bin/hey_claude.py
    function heyclaude
        ~/.local/bin/hey_claude.py $argv
    end
end
