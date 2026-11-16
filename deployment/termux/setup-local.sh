#!/data/data/com.termux/files/usr/bin/bash
#
# MediaFusion — token-less LOCAL addon for Termux (Android), reachable over WiFi/LAN.
#
# What this does:
#   * Installs PostgreSQL + Redis + the Rust toolchain in Termux
#   * Creates the mediafusion database and applies migrations
#   * Builds the Rust backend (mediafusion-api) in offline mode
#   * Runs it bound to 0.0.0.0 so other devices on your WiFi can reach it
#
# After it is up you install, in Stremio on the SAME WiFi:
#
#     http://<this-tablet-LAN-IP>:8000/manifest.json
#
# NOTE: no secret_str / token in the URL -> the backend's PUBLIC routes serve
#       UserData::default(). That is the "without token" mode. It gives public
#       (non-debrid) streams only, and results appear only once the database has
#       been populated by scrapers/indexers.
#
# Run once:   bash deployment/termux/setup-local.sh
# Re-run:     same command; it skips steps already done and just restarts + runs.
#
set -euo pipefail

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
PGDATA="$PREFIX/var/lib/postgresql"
DB_NAME="mediafusion"
DB_USER="mediafusion"
DB_PASS="mediafusion"
PORT="${STREAM_RS_PORT:-8000}"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

# ── 1. LAN IP detection ──────────────────────────────────────────────────────
detect_ip() {
  local ip
  ip="$(ip -4 addr show 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 \
        | grep -E '^(192\.168|10\.|172\.(1[6-9]|2[0-9]|3[0-1]))\.' | head -n1 || true)"
  [ -z "$ip" ] && ip="$(ifconfig 2>/dev/null | awk '/inet /{print $2}' \
        | grep -E '^(192\.168|10\.|172\.)' | head -n1 || true)"
  echo "$ip"
}
LAN_IP="${LAN_IP:-$(detect_ip)}"
if [ -z "$LAN_IP" ]; then
  echo "Could not auto-detect your LAN IP. Set it and re-run, e.g.:"
  echo "   LAN_IP=192.168.1.43 bash deployment/termux/setup-local.sh"
  exit 1
fi
HOST_URL="http://$LAN_IP:$PORT"

# ── 2. Packages ──────────────────────────────────────────────────────────────
log "Installing packages (rust, postgresql, redis, build tools)"
pkg update -y
pkg install -y rust postgresql redis git clang make pkg-config openssl binutils

# ── 3. PostgreSQL ────────────────────────────────────────────────────────────
if [ ! -d "$PGDATA/base" ]; then
  log "Initializing PostgreSQL data dir"
  initdb "$PGDATA"
fi
log "Starting PostgreSQL"
pg_ctl -D "$PGDATA" -l "$PGDATA/pg.log" -o "-k $PREFIX/tmp" start || true
sleep 3

# role + db (idempotent)
export PGHOST="$PREFIX/tmp"
psql -d postgres -tc "SELECT 1 FROM pg_roles WHERE rolname='$DB_USER'" | grep -q 1 || \
  psql -d postgres -c "CREATE ROLE $DB_USER LOGIN PASSWORD '$DB_PASS' SUPERUSER;"
psql -d postgres -tc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" | grep -q 1 || \
  psql -d postgres -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;"

# ── 4. Redis ─────────────────────────────────────────────────────────────────
log "Starting Redis"
if ! redis-cli ping >/dev/null 2>&1; then
  redis-server --daemonize yes --save '' --appendonly no
  sleep 1
fi

# ── 5. Environment ───────────────────────────────────────────────────────────
export SECRET_KEY="${SECRET_KEY:-$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 32)}"
export POSTGRES_URI="postgresql://$DB_USER:$DB_PASS@127.0.0.1:5432/$DB_NAME"
export REDIS_URL="redis://127.0.0.1:6379"
export STREAM_RS_PORT="$PORT"
export HOST_URL="$HOST_URL"
export ADDON_NAME="${ADDON_NAME:-MediaFusion Local}"
export SQLX_OFFLINE=true

# ── 6. Migrations (tracked, idempotent) ──────────────────────────────────────
log "Applying database migrations"
psql "$POSTGRES_URI" -c "CREATE TABLE IF NOT EXISTS _local_migrations (name text PRIMARY KEY, applied_at timestamptz DEFAULT now());"
for up in $(ls "$REPO_ROOT"/backend/migrations/*.up.sql | sort); do
  name="$(basename "$up")"
  already="$(psql "$POSTGRES_URI" -tAc "SELECT 1 FROM _local_migrations WHERE name='$name'")"
  if [ "$already" != "1" ]; then
    echo "  applying $name"
    psql "$POSTGRES_URI" -v ON_ERROR_STOP=1 -f "$up"
    psql "$POSTGRES_URI" -c "INSERT INTO _local_migrations(name) VALUES ('$name');"
  fi
done

# ── 7. Build backend ─────────────────────────────────────────────────────────
log "Building mediafusion-api (release). First build is SLOW on a tablet."
( cd "$REPO_ROOT/backend" && SQLX_OFFLINE=true cargo build --release --bin mediafusion-api )

# ── 8. Run ───────────────────────────────────────────────────────────────────
log "Starting MediaFusion addon"
cat <<EOF

  Addon is starting on:   $HOST_URL/manifest.json

  In Stremio on the SAME WiFi, add this addon URL:

      $HOST_URL/manifest.json

  (No token in the URL = public / token-less mode.)

  Tip: keep this Termux session awake (termux-wake-lock) while streaming.

EOF
exec "$REPO_ROOT/backend/target/release/mediafusion-api"
