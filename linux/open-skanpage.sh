#!/bin/sh
# Hook for scx4500-buttond.py: Scan -> PC opens Skanpage (KDE scanning app).
# Skanpage is started detached so the daemon keeps polling while it is open.
# If Skanpage is already running, nothing new is started (just a notification).
# Environment: SCX_EVENT (raw 8-byte event, hex), SCX_DEST (destination number).
if pgrep -x skanpage >/dev/null; then
    command -v notify-send >/dev/null && notify-send -a "SCX-4500" "Scan to PC" "Skanpage is already open"
    exit 0
fi
setsid -f skanpage >/dev/null 2>&1 </dev/null
