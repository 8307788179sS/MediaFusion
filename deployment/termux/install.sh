#!/data/data/com.termux/files/usr/bin/bash
#
#  MediaFusion — one-shot installer for Termux (Android phone/tablet).
#  Runs a local, token-less Stremio addon on the device itself.
#
#  Usage (inside Termux):
#      pkg install -y git
#      git clone https://github.com/8307788179sS/MediaFusion.git
#      cd MediaFusion
#      bash deployment/termux/install.sh
#
#  After it finishes it starts the server and prints the addon URL to add
#  in Stremio:   http://127.0.0.1:8001/manifest.json
#
set -e
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PGDATA="$PREFIX/var/lib/postgresql"

say() { printf '\n\033[1;35m==> %s\033[0m\n' "$*"; }

# 1 ── packages ───────────────────────────────────────────────────────────────
say "Installing packages (one-time, ~250 MB)"
pkg update -y
pkg install -y rust postgresql redis git clang make pkg-config openssl \
               binutils python ca-certificates

# 2 ── libgcc shim (fixes the Termux '-lgcc not found' linker error) ──────────
say "Adding libgcc shim"
echo 'INPUT(-lunwind)' > "$PREFIX/lib/libgcc.a"

# 3 ── source patches (free/local defaults) ──────────────────────────────────
say "Applying local-mode patches"
UD="$REPO_DIR/backend/src/models/user_data.rs"
MF="$REPO_DIR/backend/src/routes/manifest.rs"
# live search ON by default so the public addon actually scrapes
sed -i 's/#\[serde(default, rename = "lss"/#[serde(default = "default_true", rename = "lss"/' "$UD" || true
# not "configurable" -> Stremio installs without the (unbuilt) config page
sed -i 's/"configurable":true/"configurable":false/' "$MF" || true

# 4 ── PostgreSQL ────────────────────────────────────────────────────────────
say "Setting up PostgreSQL"
[ -d "$PGDATA/base" ] || initdb "$PGDATA"
pg_ctl -D "$PGDATA" -o "-k $PREFIX/tmp" -l "$PGDATA/pg.log" start || true
sleep 3
export PGHOST="$PREFIX/tmp"
psql -d postgres -tc "SELECT 1 FROM pg_roles WHERE rolname='mediafusion'" | grep -q 1 || \
  psql -d postgres -c "CREATE ROLE mediafusion LOGIN PASSWORD 'mediafusion' SUPERUSER;"
psql -d postgres -tc "SELECT 1 FROM pg_database WHERE datname='mediafusion'" | grep -q 1 || \
  psql -d postgres -c "CREATE DATABASE mediafusion OWNER mediafusion;"

# 5 ── Redis ─────────────────────────────────────────────────────────────────
say "Starting Redis"
redis-cli ping >/dev/null 2>&1 || redis-server --daemonize yes --save '' --appendonly no

# 6 ── build the backend (SLOW: 20-40 min, keep device charging) ─────────────
say "Building MediaFusion (first build is slow — keep the device charging)"
( cd "$REPO_DIR/backend" && \
  CARGO_PROFILE_RELEASE_LTO=false \
  CARGO_PROFILE_RELEASE_CODEGEN_UNITS=16 \
  CARGO_PROFILE_RELEASE_OPT_LEVEL=2 \
  SQLX_OFFLINE=true \
  CARGO_BUILD_JOBS=3 \
  cargo build --release --bin mediafusion-api --no-default-features --features "jemalloc tls-native" )

# 7 ── install the run script + proxy into $HOME ─────────────────────────────
say "Installing run scripts"
cp "$REPO_DIR/deployment/termux/mf-run.sh"   "$HOME/mf-run.sh"
cp "$REPO_DIR/deployment/termux/mfmproxy.py" "$HOME/mfmproxy.py"
chmod +x "$HOME/mf-run.sh"
# 'mf' management command (mf start|stop|restart|status|update|log)
cp "$REPO_DIR/deployment/termux/mf" "$PREFIX/bin/mf"
chmod +x "$PREFIX/bin/mf"
# boot autostart (needs the Termux:Boot app installed)
mkdir -p "$HOME/.termux/boot"
cp "$REPO_DIR/deployment/termux/start-mediafusion.sh" "$HOME/.termux/boot/start-mediafusion.sh" 2>/dev/null || true
chmod +x "$HOME/.termux/boot/start-mediafusion.sh" 2>/dev/null || true

# 8 ── start it ──────────────────────────────────────────────────────────────
say "Starting MediaFusion"
pkill -9 -f mediafusion-api 2>/dev/null || true
pkill -9 -f mfmproxy.py 2>/dev/null || true
nohup bash "$HOME/mf-run.sh" > "$HOME/mf-run.log" 2>&1 &
sleep 8

cat <<EOF

────────────────────────────────────────────────────────────
  Done.  MediaFusion is running.

  In Stremio on THIS device, add this addon:

      http://127.0.0.1:8001/manifest.json

  Open a movie -> scroll to "MediaFusion Local" streams.
  Tip: pick 720p/1080p with more seeders for faster play.

  To restart later:   bash ~/mf-run.sh &
────────────────────────────────────────────────────────────
EOF
