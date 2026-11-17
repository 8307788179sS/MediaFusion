#!/data/data/com.termux/files/usr/bin/bash
#  Clears the Android TV's app caches (Stremio torrent cache included) over adb:
#    - every CLEAN_EVERY seconds (default 1 hour)
#    - right after the TV reboots (detected via its boot_id)
#  Skips a run while something is playing on the TV and retries shortly after.
#  Uses `pm trim-caches`: only cache is removed — Stremio login/addons stay.
#
#  Setup (once):  pkg install android-tools
#                 adb connect <TV_IP>:5555   -> accept "Allow debugging" on the TV
#  Run:           nohup bash ~/tv-cache-clean.sh > ~/tv-cache-clean.log 2>&1 &
TV="${TV:-192.168.1.33:5555}"
CLEAN_EVERY="${CLEAN_EVERY:-3600}"   # seconds between cleans
CHECK_EVERY="${CHECK_EVERY:-300}"    # how often to check the TV
STATE="$HOME/.tv-cache-clean.state"  # "<boot_id> <last_clean_epoch>"

log() { echo "[tv-cache] $(date '+%F %T') $*"; }

tv() { timeout 30 adb -s "$TV" shell "$@" 2>/dev/null | tr -d '\r'; }

ensure_connected() {
  [ "$(timeout 10 adb -s "$TV" get-state 2>/dev/null)" = "device" ] && return 0
  timeout 15 adb connect "$TV" >/dev/null 2>&1
  [ "$(timeout 10 adb -s "$TV" get-state 2>/dev/null)" = "device" ]
}

is_playing() {
  # PlaybackState 3 = STATE_PLAYING in any media session
  tv dumpsys media_session | grep -q 'state=PlaybackState {state=3'
}

free_space() { tv df -h /data | awk 'NR==2{print $4}'; }

# Stremio only accepts plain-http addons on 127.0.0.1, so make the TV's
# 127.0.0.1:8001 tunnel to this device's addon (adb reverse). Re-checked
# every loop so it survives TV reboots / adb reconnects.
ensure_reverse() {
  if ! timeout 10 adb -s "$TV" reverse --list 2>/dev/null | grep -q 'tcp:8001 tcp:8001'; then
    timeout 10 adb -s "$TV" reverse tcp:8001 tcp:8001 >/dev/null 2>&1 \
      && log "TV 127.0.0.1:8001 -> this device's addon (reverse set)"
  fi
}

last_boot=""; last_clean=0
[ -f "$STATE" ] && read -r last_boot last_clean < "$STATE"

log "started: TV=$TV every=${CLEAN_EVERY}s"
while true; do
  if ensure_connected; then
    ensure_reverse
    boot_id="$(tv cat /proc/sys/kernel/random/boot_id)"
    now=$(date +%s)
    reason=""
    if [ -n "$boot_id" ] && [ "$boot_id" != "$last_boot" ]; then
      reason="TV rebooted"
    elif [ $((now - last_clean)) -ge "$CLEAN_EVERY" ]; then
      reason="hourly"
    fi
    if [ -n "$reason" ]; then
      if is_playing; then
        log "$reason, but TV is playing — will retry"
      else
        before="$(free_space)"
        tv pm trim-caches 999G >/dev/null
        log "cleared ($reason): free ${before} -> $(free_space)"
        last_boot="$boot_id"; last_clean=$now
        echo "$last_boot $last_clean" > "$STATE"
      fi
    fi
  else
    log "TV not reachable (off?)"
  fi
  sleep "$CHECK_EVERY"
done
