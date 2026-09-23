# Shared bootstrap functions. Sourcing this file has no side effects.
info() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m==> WARNING:\033[0m %s\n' "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
NVIM_MIN=0.11.3

detect_platform() {
    local system_root=${1:-/} model=''
    CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
    DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
    ARCH=$(uname -m)
    # A 64-bit kernel may run a 32-bit Raspberry Pi OS userland.
    if command -v dpkg >/dev/null; then
        case "$(dpkg --print-architecture)" in
            armhf) ARCH=armv7l ;; arm64) ARCH=aarch64 ;; amd64) ARCH=x86_64 ;;
        esac
    fi
    IS_PI=0
    if [[ -r $system_root/proc/device-tree/model ]]; then model=$(tr -d '\0' < "$system_root/proc/device-tree/model"); fi
    if [[ $model == *'Raspberry Pi'* || -f $system_root/etc/rpi-issue ]]; then IS_PI=1; fi
    if [[ $PROFILE == auto ]]; then
        if [[ :${XDG_CURRENT_DESKTOP:-}: == *:KDE:* ]] || command -v startplasma-wayland >/dev/null || command -v startplasma-x11 >/dev/null; then PROFILE=kde
        else PROFILE=headless; fi
    fi
    if [[ $NVIM_MODE == auto ]]; then
        NVIM_MODE=full
        if ((IS_PI)) || [[ ! $ARCH =~ ^(x86_64|aarch64)$ ]]; then NVIM_MODE=minimal; fi
    fi
    if command -v pacman >/dev/null; then PM=pacman
    elif command -v apt-get >/dev/null; then PM=apt
    else die 'No supported package manager (pacman/apt).'; fi
}

describe_plan() {
    info 'Core: Fish, fzf, zoxide, fd, ripgrep, btop, git, curl, Atuin, Yazi, file, jq, Neovim; eza when available.'
    if [[ $NVIM_MODE == full ]]; then info 'Full Neovim: >=0.11.3, make/C compiler, Node/npm, unzip, GLSL analyzer via Mason.'
    else info 'Minimal Neovim: distro package; no Lazy/Mason/plugins/build dependencies.'; fi
    if [[ $PROFILE == kde ]]; then
        info 'KDE: kitty, Firefox Developer Edition, official Sublime Text, Dolphin, clipboard tools, Input-remapper.'
        info 'KDE config: managed shortcuts, Dolphin toolbar/preferences/icons, trackball preset.'
    else info 'Headless: no GUI packages, KDE settings, or input service.'; fi
}
backup_path() { printf '%s.bak.%s.%s' "$1" "$(date +%Y%m%d-%H%M%S)" "$$"; }
link_config() {
    local target="$REPO_DIR/config/$1" dest="$CONFIG_HOME/$1" bak
    mkdir -p "$CONFIG_HOME"
    if [[ -L $dest && $(readlink -f "$dest") == "$(readlink -f "$target")" ]]; then return; fi
    if [[ -e $dest || -L $dest ]]; then
        bak=$(backup_path "$dest"); mv -- "$dest" "$bak"; info "Backed up $dest to $bak"
    fi
    ln -s -- "$target" "$dest"
    info "Linked $dest"
}
version_at_least() { [[ $(printf '%s\n' "$1" "$2" | sort -V | sed -n '1p') == "$2" ]]; }
nvim_recent_enough() {
    command -v nvim >/dev/null || return 1
    local version
    version=$(nvim --version | sed -n '1s/^NVIM v//p')
    [[ -n $version ]] && version_at_least "$version" "$NVIM_MIN"
}
apt_has() {
    local candidate
    candidate=$(apt-cache policy "$1" | sed -n 's/^[[:space:]]*Candidate: //p')
    [[ -n $candidate && $candidate != '(none)' ]]
}
release_install() { python3 "$REPO_DIR/scripts/releases.py" install "$1" --arch "$ARCH"; }
remapper_recent_enough() {
    command -v input-remapper-control >/dev/null || return 1
    local version
    version=$(input-remapper-control --version 2>/dev/null | sed -n '1s/^input-remapper \([0-9][0-9.]*\).*/\1/p') || return 1
    [[ -n $version ]] && version_at_least "$version" 2.2.1
}
install_core() {
    local extras=() tool
    export PATH="$HOME/.local/bin:$PATH"
    if [[ $PM == pacman ]]; then
        [[ $NVIM_MODE != full ]] || extras+=(base-devel nodejs npm)
        sudo pacman -Syu --needed --noconfirm fish fzf zoxide fd ripgrep btop git curl \
            ca-certificates python unzip file jq neovim eza atuin yazi "${extras[@]}"
    else
        [[ $NVIM_MODE != full ]] || extras+=(build-essential nodejs npm)
        [[ $NVIM_MODE != minimal ]] || extras+=(neovim)
        sudo apt-get update
        sudo apt-get install -y fish fzf zoxide fd-find ripgrep btop git curl \
            ca-certificates python3 unzip file jq xz-utils "${extras[@]}"
        mkdir -p "$HOME/.local/bin"
        ln -sfn "$(command -v fdfind)" "$HOME/.local/bin/fd"
        for tool in atuin yazi eza; do
            if command -v "$tool" >/dev/null && "$tool" --version >/dev/null 2>&1; then continue; fi
            if apt_has "$tool"; then sudo apt-get install -y "$tool"
            elif [[ $ARCH =~ ^(x86_64|aarch64)$ ]]; then release_install "$tool"
            else warn "$tool: no distro package or supported upstream binary for $ARCH; skipped (no automatic source build)."; fi
        done
        if [[ $NVIM_MODE == full ]] && ! nvim_recent_enough; then release_install nvim; fi
    fi
    if [[ $NVIM_MODE == full ]] && ! nvim_recent_enough; then die "Full Neovim needs >=$NVIM_MIN; use --nvim minimal for an older installation."; fi
    # Ubuntu 24.04's Node 18 cannot run current fish-lsp (requires >=20).
    if [[ $NVIM_MODE == full ]] && ! node -e 'process.exit(Number(process.versions.node.split(".")[0]) >= 20 ? 0 : 1)'; then
        release_install node
    fi
}
fetch_key() {
    local url=$1 fingerprint=$2 output=$3 actual
    curl -fsSL --retry 3 "$url" -o "$output"
    actual=$(gpg --batch --show-keys --with-colons "$output" | awk -F: '$1 == "fpr" {print $10; exit}')
    [[ $actual == "$fingerprint" ]] || die "Unexpected repository key fingerprint for $url"
}
install_desktop() (
    set -euo pipefail
    [[ $ARCH =~ ^(x86_64|aarch64)$ ]] || die 'KDE application profile supports x86_64/aarch64; use --profile headless on 32-bit systems.'
    local_tmp=$(mktemp -d)
    trap 'rm -rf -- "$local_tmp"' EXIT
    if [[ $PM == pacman ]]; then sudo pacman -S --needed --noconfirm gnupg
    else sudo apt-get install -y gnupg; fi
    fetch_key https://download.sublimetext.com/sublimehq-pub.gpg \
        1EDDE2CDFC025D17F6DA9EC0ADAE6AD28A8F901A "$local_tmp/sublime.asc"
    if [[ $PM == pacman ]]; then
        sudo pacman-key --add "$local_tmp/sublime.asc"
        sudo pacman-key --lsign-key 1EDDE2CDFC025D17F6DA9EC0ADAE6AD28A8F901A
        if ! pacman-conf --repo sublime-text Server >/dev/null 2>&1; then
            printf '\n[sublime-text]\nServer = https://download.sublimetext.com/arch/stable/%s\n' "$ARCH" | sudo tee -a /etc/pacman.conf >/dev/null
        elif [[ $(pacman-conf --repo sublime-text Server) != "https://download.sublimetext.com/arch/stable/$ARCH" ]]; then
            die 'Existing sublime-text repository uses a different channel/URL; review /etc/pacman.conf.'
        fi
        # Resolve the conflicting AUR provider within a single transaction.
        if pacman -Q sublime-text-4 >/dev/null 2>&1; then
            info 'Replacing sublime-text-4 with the vendor package (answer pacman conflict prompt).'
            sudo pacman -Syu --needed sublime-text </dev/tty
        fi
        sudo pacman -Syu --needed --noconfirm sublime-text firefox-developer-edition kitty \
            dolphin wl-clipboard xclip ttf-jetbrains-mono-nerd
        if ! remapper_recent_enough; then
            if pacman -Si input-remapper >/dev/null 2>&1; then sudo pacman -S --needed --noconfirm input-remapper
            elif command -v paru >/dev/null; then paru -S --needed input-remapper-git </dev/tty
            elif command -v yay >/dev/null; then yay -S --needed input-remapper-git </dev/tty
            else
                sudo pacman -S --needed --noconfirm base-devel
                git clone https://aur.archlinux.org/input-remapper-git.git "$local_tmp/input-remapper"
                (cd "$local_tmp/input-remapper" && makepkg -si --needed </dev/tty)
            fi
        fi
    else
        sudo install -d -m 0755 /etc/apt/keyrings
        sudo install -m 0644 "$local_tmp/sublime.asc" /etc/apt/keyrings/sublimehq-pub.asc
        printf 'Types: deb\nURIs: https://download.sublimetext.com/\nSuites: apt/stable/\nSigned-By: /etc/apt/keyrings/sublimehq-pub.asc\n' | sudo tee /etc/apt/sources.list.d/sublime-text.sources >/dev/null
        fetch_key https://packages.mozilla.org/apt/repo-signing-key.gpg \
            35BAA0B33E9EB396F59CA838C0BA5CE6DC6315A3 "$local_tmp/mozilla.asc"
        sudo install -m 0644 "$local_tmp/mozilla.asc" /etc/apt/keyrings/packages.mozilla.org.asc
        printf 'Types: deb\nURIs: https://packages.mozilla.org/apt\nSuites: mozilla\nComponents: main\nSigned-By: /etc/apt/keyrings/packages.mozilla.org.asc\n' | sudo tee /etc/apt/sources.list.d/linux-bootstrap-mozilla.sources >/dev/null
        sudo apt-get update
        sudo apt-get install -y sublime-text firefox-devedition kitty dolphin wl-clipboard xclip
        candidate=$(apt-cache policy input-remapper | sed -n 's/^[[:space:]]*Candidate: //p')
        installed=$(dpkg-query -W -f='${Version}' input-remapper 2>/dev/null || true)
        if [[ -n $candidate && $candidate != '(none)' ]] && dpkg --compare-versions "$candidate" ge 2.2.1; then
            sudo apt-get install -y input-remapper
        elif ! dpkg --compare-versions "${installed:-0}" ge 2.2.1; then
            deb=$(python3 "$REPO_DIR/scripts/releases.py" download sezanzeb/input-remapper --pattern '^input-remapper-.*\.deb$' --directory "$local_tmp")
            chmod 0755 "$local_tmp"
            chmod 0644 "$deb"
            sudo apt-get install -y "$deb"
        fi
    fi
    remapper_recent_enough || die 'Input-remapper >=2.2.1 is required for the shared preset.'
)
