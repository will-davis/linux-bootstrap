#!/usr/bin/env bash
# atuin-server.sh — provision the atuin sync server on ubuntu-server (Ubuntu 24.04).
#
# One-shot, fail-fast, re-run-safe. NOT invoked by bootstrap.sh (only ubuntu-server
# should run a sync server), hence it lives under server/ rather than in the
# link_config flow. Run it in a REAL terminal because it needs a sudo password:
#
#     bash ~/Projects/linux-bootstrap/server/atuin-server.sh
#
# Nothing secret is committed: the Postgres password is generated at runtime and
# written only into the root-owned systemd unit on this host. atuin sync is
# end-to-end encrypted, so the DB never holds plaintext history anyway.
set -euo pipefail

PORT=8888
DBNAME=atuin
DBUSER=atuin
SVC=/etc/systemd/system/atuin.service

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

# 1. atuin binary — client and server are the same binary. Skip if already present.
if ! command -v atuin >/dev/null 2>&1; then
    log "fetching latest atuin release binary"
    url=$(curl -fsSL https://api.github.com/repos/atuinsh/atuin/releases/latest \
          | grep -oE 'https://[^"]+x86_64-unknown-linux-[a-z]+\.tar\.gz' | head -1)
    [ -n "$url" ] || { echo "no linux x86_64 asset found; install atuin manually"; exit 1; }
    log "  $url"
    tmp=$(mktemp -d)
    curl -fL "$url" -o "$tmp/atuin.tgz"
    tar -xzf "$tmp/atuin.tgz" -C "$tmp"
    sudo install "$(find "$tmp" -name atuin -type f -perm -u+x | head -1)" /usr/local/bin/atuin
    rm -rf "$tmp"
fi
atuin --version
atuin server --help >/dev/null || { echo "this atuin build lacks 'server'"; exit 1; }

# 2. PostgreSQL (24.04 ships PG 16)
log "installing postgresql"
sudo apt-get update -qq
sudo apt-get install -y postgresql openssl

# Create role + db only if absent; on a re-run, reuse the password already baked
# into the systemd unit so the DB URI keeps matching.
if sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$DBUSER'" | grep -q 1; then
    log "role '$DBUSER' exists — reusing the password from $SVC"
    DBPASS=$(sudo grep -oP "postgres://$DBUSER:\K[^@]+" "$SVC" 2>/dev/null || true)
    [ -n "${DBPASS:-}" ] || { echo "role exists but no password in $SVC; fix ATUIN_DB_URI by hand"; exit 1; }
else
    DBPASS=$(openssl rand -hex 24)
    log "creating role '$DBUSER'"
    sudo -u postgres psql -v ON_ERROR_STOP=1 -c "CREATE USER $DBUSER WITH ENCRYPTED PASSWORD '$DBPASS';"
fi
if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='$DBNAME'" | grep -q 1; then
    log "creating database '$DBNAME'"
    sudo -u postgres psql -v ON_ERROR_STOP=1 -c "CREATE DATABASE $DBNAME OWNER $DBUSER;"
fi
# PG 15+ locks down the public schema; atuin's migrations need it.
sudo -u postgres psql -d "$DBNAME" -v ON_ERROR_STOP=1 -c "GRANT ALL ON SCHEMA public TO $DBUSER;"

# 3. systemd unit. OPEN_REGISTRATION starts true so you can create your account;
#    the script's closing notes tell you to flip it off afterward.
log "writing $SVC"
sudo tee "$SVC" >/dev/null <<UNIT
[Unit]
Description=atuin sync server
After=network.target postgresql.service
Requires=postgresql.service

[Service]
User=$USER
Environment=ATUIN_HOST=0.0.0.0
Environment=ATUIN_PORT=$PORT
Environment=ATUIN_OPEN_REGISTRATION=true
Environment=ATUIN_DB_URI=postgres://$DBUSER:$DBPASS@localhost/$DBNAME
ExecStart=/usr/local/bin/atuin server start
Restart=on-failure

[Install]
WantedBy=multi-user.target
UNIT
sudo systemctl daemon-reload
sudo systemctl enable --now atuin
sleep 1
sudo systemctl --no-pager --full status atuin | head -12 || true

# 4. firewall — only touch it if ufw is actually active (often it isn't on a VM).
if sudo ufw status 2>/dev/null | grep -q '^Status: active'; then
    log "ufw active — allowing $PORT from LAN + Tailscale CGNAT range"
    sudo ufw allow from 192.168.0.0/16 to any port "$PORT" proto tcp
    sudo ufw allow from 100.64.0.0/10 to any port "$PORT" proto tcp
fi

# 5. sanity: is it listening?
if ss -tlnp 2>/dev/null | grep -q ":$PORT "; then
    log "atuin server is listening on :$PORT"
else
    log "not listening yet — check: journalctl -u atuin -e"
fi

cat <<NEXT

── next steps ──────────────────────────────────────────────────────────────
On your FIRST client (desktop) — its config.toml already points here:
    atuin register -u will -e blargens@gmail.com
    atuin import auto            # slurp existing fish history (once)
    atuin sync
    atuin key                    # SAVE this mnemonic — other machines need it to decrypt

On every other machine (laptop, and this server as a client):
    git -C ~/Projects/linux-bootstrap pull && ~/Projects/linux-bootstrap/bootstrap.sh
    atuin login -u will          # password, THEN the key printed above
    atuin sync

Then lock registration so nobody else can create an account on your instance:
    sudo sed -i 's/OPEN_REGISTRATION=true/OPEN_REGISTRATION=false/' $SVC
    sudo systemctl daemon-reload && sudo systemctl restart atuin
─────────────────────────────────────────────────────────────────────────────
NEXT
