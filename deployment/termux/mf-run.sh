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
# Address other devices use to reach this phone. Auto-detects the WiFi/LAN IP;
# override with MF_HOST=192.168.x.y. Falls back to 127.0.0.1 (this device only).
detect_lan_ip() {
  { ifconfig 2>/dev/null || ip -4 addr 2>/dev/null; } \
    | grep -oE 'inet (addr:)?([0-9]+\.){3}[0-9]+' | grep -oE '([0-9]+\.){3}[0-9]+' \
    | grep -vE '^127\.' | grep -E '^(192\.168|10\.|172\.(1[6-9]|2[0-9]|3[01]))' | head -n1
}
MF_HOST="${MF_HOST:-$(detect_lan_ip)}"
MF_HOST="${MF_HOST:-127.0.0.1}"
export HOST_URL="http://$MF_HOST:8001"
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

# TV cache cleaner (hourly + after TV reboot). Needs: pkg install android-tools
if command -v adb >/dev/null 2>&1 && [ -f "$HOME/tv-cache-clean.sh" ]; then
  pkill -f tv-cache-clean.sh 2>/dev/null || true
  nohup bash "$HOME/tv-cache-clean.sh" >> "$HOME/tv-cache-clean.log" 2>&1 &
fi

BIN="$REPO_DIR/backend/target/release/mediafusion-api"
if [ ! -x "$BIN" ]; then
  echo "[mf-run] binary not found at $BIN — run the installer first."
  exit 1
fi

echo "[mf-run] addon URL (this phone): http://127.0.0.1:8001/manifest.json"
echo "[mf-run] addon URL (LAN):        $HOST_URL/manifest.json"
while true; do
  echo "[mf-run] starting addon at $(date)"
  "$BIN"
  echo "[mf-run] addon exited ($?). restarting in 5s..."
  sleep 5
done
