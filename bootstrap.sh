#!/usr/bin/env bash
# Normal-user entrypoint, also works through curl | bash -s -- [options].
set -euo pipefail
usage() {
    cat <<'USAGE'
Usage: bootstrap.sh [--profile auto|kde|headless] [--nvim auto|full|minimal]
                    [--config-only] [--dry-run]
  auto: KDE when Plasma is installed (including over SSH), headless otherwise.
  Raspberry Pi defaults to minimal Neovim; other 64-bit machines use full.
  --config-only: user configuration only; no packages, services, or shell change.
  --dry-run: show selections without changes or downloads (use from a clone).
USAGE
}
PROFILE=auto NVIM_MODE=auto CONFIG_ONLY=0 DRY_RUN=0
ORIGINAL_ARGS=("$@")
while (($#)); do
    case "$1" in
        --profile|--nvim)
            (($# >= 2)) || { usage >&2; exit 2; }
            if [[ $1 == --profile ]]; then PROFILE=$2; else NVIM_MODE=$2; fi
            shift 2 ;;
        --config-only) CONFIG_ONLY=1; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
 done
[[ $PROFILE =~ ^(auto|kde|headless)$ && $NVIM_MODE =~ ^(auto|full|minimal)$ ]] || { usage >&2; exit 2; }
if [[ ! -f ${BASH_SOURCE[0]:-} ]]; then
    ((DRY_RUN == 0)) || { echo 'Use dry-run from a clone to avoid cloning.'; exit 0; }
    [[ $EUID != 0 ]] || { echo 'Run as your normal user, not root.' >&2; exit 1; }
    if ! command -v git >/dev/null; then
        if command -v pacman >/dev/null; then sudo pacman -Syu --needed --noconfirm git
        elif command -v apt-get >/dev/null; then
            sudo apt-get update
            sudo apt-get install -y git ca-certificates
        else echo 'No supported package manager (pacman/apt).' >&2; exit 1; fi
    fi
    clone_dir="$HOME/linux-bootstrap"
    if [[ -d $clone_dir/.git ]]; then git -C "$clone_dir" pull --ff-only
    else git clone https://github.com/will-davis/linux-bootstrap.git "$clone_dir"; fi
    exec bash "$clone_dir/bootstrap.sh" "${ORIGINAL_ARGS[@]}"
fi
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/bootstrap.sh
source "$REPO_DIR/lib/bootstrap.sh"
detect_platform
info "profile=$PROFILE; neovim=$NVIM_MODE; packages=$PM; architecture=$ARCH; raspberry-pi=$IS_PI"
if ((DRY_RUN)); then describe_plan; exit 0; fi
[[ $EUID != 0 ]] || die 'Run as your normal user, not root.'
if ((!CONFIG_ONLY)); then
    sudo -v
    install_core
    if [[ $PROFILE == kde ]]; then install_desktop; fi
fi
export PATH="$HOME/.local/bin:$PATH"
mkdir -p "$CONFIG_HOME/linux-bootstrap"
printf '%s\n' "$NVIM_MODE" > "$CONFIG_HOME/linux-bootstrap/nvim-mode"
for name in fish nvim fd atuin; do link_config "$name"; done
if [[ $PROFILE == kde ]]; then
    link_config kitty
    python3 "$REPO_DIR/scripts/desktop.py" apply --repo "$REPO_DIR"
    if ((!CONFIG_ONLY)); then sudo systemctl enable --now input-remapper; fi
    # The packaged login autostart loads user presets. Don't interrupt a held
    # key by stopping/reloading a running injector in the middle of bootstrap.
fi
if ((!CONFIG_ONLY)); then
    fish_path="$(command -v fish)"
    grep -Fxq "$fish_path" /etc/shells || printf '%s\n' "$fish_path" | sudo tee -a /etc/shells >/dev/null
    login_user="$(id -un)"
    if [[ $(getent passwd "$login_user" | cut -d: -f7) != "$fish_path" ]]; then
        sudo chsh -s "$fish_path" "$login_user"
    fi
fi
info 'Done. Start a new Fish shell; log out/in to load changed KDE shortcuts and remaps.'
if [[ $NVIM_MODE == full ]]; then info 'First nvim launch installs locked plugins; :Lazy restore reproduces the lockfile.'; fi
info 'Atuin works locally immediately. Sync login/key import remains a manual step.'
