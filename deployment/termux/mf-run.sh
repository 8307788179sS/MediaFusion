#!/data/data/com.termux/files/usr/bin/bash
#  Keep-alive runner for the local MediaFusion addon on Termux.
#  Ensures Postgres + Redis, starts the manifest proxy (:8001) and the
#  API (:8000), and restarts the API if it ever crashes.
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
PGDATA="$PREFIX/var/lib/postgresql"
REPO_DIR="${REPO_DIR:-$HOME/MediaFusion}"

export PGHOST="$PREFIX/tmp"
export SECRET_KEY="mediafusionlocalfixedsecret00000"
export POSTGRES_URI="postgresql://mediafusion:mediafusion@127.0.0.1:5432/mediafusion"
export REDIS_URL="redis://127.0.0.1:6379"
export STREAM_RS_PORT="8000"
export HOST_URL="http://127.0.0.1:8001"
export ADDON_NAME="MediaFusion Local"
export SQLX_OFFLINE=true
export RUST_LOG="info"
# native-tls (OpenSSL) CA bundle
export SSL_CERT_FILE="$PREFIX/etc/tls/cert.pem"
export SSL_CERT_DIR="$PREFIX/etc/tls"
# speed: gate slow/dead public indexers faster
export PUBLIC_INDEXERS_SOURCE_HEALTH_MIN_SAMPLES="3"
export PUBLIC_INDEXERS_SOURCE_MAX_TIMEOUT_RATE="0.2"
export PUBLIC_INDEXERS_SOURCE_MIN_SUCCESS_RATE="0.25"

# keep CPU awake
termux-wake-lock 2>/dev/null || true

# ensure Postgres
pg_ctl -D "$PGDATA" status >/dev/null 2>&1 || \
  pg_ctl -D "$PGDATA" -o "-k $PREFIX/tmp" -l "$PGDATA/pg.log" start || true
# ensure Redis
redis-cli ping >/dev/null 2>&1 || redis-server --daemonize yes --save '' --appendonly no
sleep 2

# manifest-fixer proxy on :8001 (configurable->false so Stremio installs)
pkill -f mfmproxy.py 2>/dev/null || true
sleep 1
nohup python3 "$HOME/mfmproxy.py" > "$HOME/mfmproxy.log" 2>&1 &

BIN="$REPO_DIR/backend/target/release/mediafusion-api"
if [ ! -x "$BIN" ]; then
  echo "[mf-run] binary not found at $BIN — run the installer first."
  exit 1
fi

echo "[mf-run] addon URL: http://127.0.0.1:8001/manifest.json"
while true; do
  echo "[mf-run] starting addon at $(date)"
  "$BIN"
  echo "[mf-run] addon exited ($?). restarting in 5s..."
  sleep 5
done
