#!/data/data/com.termux/files/usr/bin/bash
# Termux:Boot entry — auto-starts MediaFusion on device boot.
# Requires the "Termux:Boot" app installed and opened once.
termux-wake-lock
exec bash "$HOME/mf-run.sh" >> "$HOME/mf-run.log" 2>&1
