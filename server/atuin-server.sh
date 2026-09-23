#!/usr/bin/env bash
# Optional PostgreSQL-backed sync server for an apt/systemd machine.
# Not called by bootstrap. Run as a normal user, with sudo available.
set -euo pipefail
[[ $EUID != 0 ]] || { echo 'Run as your normal user, not root.' >&2; exit 1; }
command -v apt-get >/dev/null || { echo 'This optional server helper currently supports apt systems.' >&2; exit 1; }
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_DIR/lib/bootstrap.sh"
PROFILE=headless NVIM_MODE=minimal
detect_platform
SVC=/etc/systemd/system/atuin.service
ENV_FILE=/etc/atuin/bootstrap.env
DBNAME=atuin DBUSER=atuin
sudo -v
sudo apt-get update
sudo apt-get install -y postgresql openssl curl ca-certificates python3
sudo systemctl enable --now postgresql
export PATH="$HOME/.local/bin:$PATH"
# New releases split the server into its own binary; older builds expose a
# `server` subcommand. Support both and record the actual absolute executable.
if command -v atuin-server >/dev/null; then
    SERVER_COMMAND="$(command -v atuin-server) start"
elif command -v atuin >/dev/null && atuin server --help >/dev/null 2>&1; then
    SERVER_COMMAND="$(command -v atuin) server start"
else
    release_install atuin-server
    SERVER_COMMAND="$(command -v atuin-server) start"
fi

read_saved() {
    local key=$1 value=''
    if sudo test -f "$ENV_FILE"; then
        value=$(sudo sed -n "s/^${key}=//p" "$ENV_FILE")
    elif sudo test -f "$SVC"; then
        value=$(sudo sed -n "s/^Environment=${key}=//p" "$SVC")
    fi
    printf '%s' "$value"
}
# Keep existing registration/listening policy. Fresh servers bind loopback and
# registration starts closed; explicitly opt in for the first account.
HOST=${ATUIN_HOST:-$(read_saved ATUIN_HOST)}
HOST=${HOST:-127.0.0.1}
PORT=${ATUIN_PORT:-$(read_saved ATUIN_PORT)}
PORT=${PORT:-8888}
OPEN_REGISTRATION=${ATUIN_OPEN_REGISTRATION:-$(read_saved ATUIN_OPEN_REGISTRATION)}
OPEN_REGISTRATION=${OPEN_REGISTRATION:-false}
[[ $PORT =~ ^[0-9]+$ && $OPEN_REGISTRATION =~ ^(true|false)$ && $HOST =~ ^[a-zA-Z0-9.:-]+$ ]] || die 'Invalid host, port, or registration setting.'
DB_URI=$(read_saved ATUIN_DB_URI)
if sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$DBUSER'" | grep -qx 1; then
    [[ -n $DB_URI ]] || die "Database role exists but no saved DB URI in $ENV_FILE or $SVC; preserve/recover credentials before provisioning."
else
    DBPASS=$(openssl rand -hex 24)
    sudo -u postgres psql -v ON_ERROR_STOP=1 -c "CREATE USER $DBUSER WITH ENCRYPTED PASSWORD '$DBPASS';" >/dev/null
    DB_URI="postgres://$DBUSER:$DBPASS@localhost/$DBNAME"
fi
if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='$DBNAME'" | grep -qx 1; then
    sudo -u postgres psql -v ON_ERROR_STOP=1 -c "CREATE DATABASE $DBNAME OWNER $DBUSER;"
fi
sudo -u postgres psql -v ON_ERROR_STOP=1 -d "$DBNAME" -c "GRANT ALL ON SCHEMA public TO $DBUSER;"
umask 077
stage=$(mktemp -d)
trap 'rm -rf -- "$stage"' EXIT
cat > "$stage/env" <<ENV
ATUIN_HOST=$HOST
ATUIN_PORT=$PORT
ATUIN_OPEN_REGISTRATION=$OPEN_REGISTRATION
ATUIN_DB_URI=$DB_URI
ENV
cat > "$stage/service" <<UNIT
[Unit]
Description=Atuin sync server
After=network.target postgresql.service
Requires=postgresql.service

[Service]
User=$(id -un)
EnvironmentFile=$ENV_FILE
ExecStart=$SERVER_COMMAND
Restart=on-failure

[Install]
WantedBy=multi-user.target
UNIT
sudo install -d -m 0700 /etc/atuin
changed=0
if ! sudo cmp -s "$stage/env" "$ENV_FILE"; then
    sudo install -m 0600 "$stage/env" "$ENV_FILE"
    changed=1
fi
if ! sudo cmp -s "$stage/service" "$SVC"; then
    sudo install -m 0644 "$stage/service" "$SVC"
    changed=1
fi
sudo systemctl daemon-reload
sudo systemctl enable --now atuin
if ((changed)); then sudo systemctl restart atuin; fi
sudo systemctl is-active --quiet atuin || die 'Atuin failed to start; inspect journalctl -u atuin.'
info "Atuin is running at $HOST:$PORT; registration=$OPEN_REGISTRATION."
info "Policy and DB credentials are in $ENV_FILE (root-only). Re-runs preserve them."
info 'No firewall rules were changed. Use an SSH tunnel or configure your own trusted-network access.'
info 'For initial registration: rerun with ATUIN_OPEN_REGISTRATION=true, create the account, then rerun with false.'
