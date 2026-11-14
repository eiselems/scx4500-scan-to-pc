#!/bin/sh
# Hook for scx4500-buttond.py: Scan -> PC opens Skanpage (KDE scanning app) and starts a preview scan.
#
# - Not running: write default scan options for the last-used scanner into Skanpage's state file,
#   start Skanpage detached, wait for its window, then send the "Preview" shortcut (P).
# - Already running: focus it and send Space = Scan, which adds a page to the open document (Skanpage closes
#   an open preview itself first). Press repeatedly for multi-page documents, then save/export the PDF in Skanpage.
#
# Skanpage has no CLI/D-Bus way to scan, so the key is sent through Hyprland (hyprctl, Lua dispatchers,
# Hyprland >= 0.55). Without Hyprland it just opens Skanpage.
#
# Settings (environment, e.g. via `Environment=` in the systemd unit):
#   SCX_MODE           scan mode written as default   (default "Black and White - Line Art";
#                      smfp driver: "Color - 16 Million Colors", "Grayscale - 256 Levels",
#                      "Black and White - Halftone", "Black and White - Line Art")
#   SCX_RESOLUTION     dpi written as default          (default 300; smfp: 75 100 150 200 300 600 1200 2400)
#   SCX_PREVIEW        1 = start a preview after opening (default 1)
#   SCX_PREVIEW_DELAY  seconds between window appearing and P (default 3; scanner must be ready)
# From the daemon: SCX_EVENT (raw 8-byte event, hex), SCX_DEST (destination number).

MODE="${SCX_MODE:-Black and White - Line Art}"
RES="${SCX_RESOLUTION:-300}"
PREVIEW="${SCX_PREVIEW:-1}"
DELAY="${SCX_PREVIEW_DELAY:-3}"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/skanpagestaterc"
CLASS="org.kde.skanpage"

have_hypr() { command -v hyprctl >/dev/null && [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ]; }

window_open() { hyprctl clients -j 2>/dev/null | grep -q "\"class\": \"$CLASS\""; }

# Focus Skanpage and send one of its shortcuts (P = Preview, space = Scan); Qt only reacts when focused.
send_key() {
    hyprctl dispatch "hl.dsp.focus({ window = \"class:$CLASS\" })" >/dev/null
    sleep 0.3
    hyprctl dispatch "hl.dsp.send_shortcut({ mods = \"\", key = \"$1\", window = \"class:$CLASS\" })" >/dev/null
    echo "sent $1 to skanpage"
}

if pgrep -x skanpage >/dev/null; then
    if have_hypr; then
        send_key space
    else
        command -v notify-send >/dev/null && notify-send -a "SCX-4500" "Scan to PC" "Skanpage is already open"
    fi
    exit 0
fi

# Defaults for the scanner Skanpage used last (Skanpage rewrites this file on exit, so only while closed).
if command -v kwriteconfig6 >/dev/null && [ -f "$STATE" ]; then
    dev=$(kreadconfig6 --file "$STATE" --group general --key deviceName)
    if [ -n "$dev" ]; then
        kwriteconfig6 --file "$STATE" --group "Options For $dev" --key mode "$MODE"
        kwriteconfig6 --file "$STATE" --group "Options For $dev" --key resolution "$RES"
        echo "defaults for $dev: mode=$MODE resolution=$RES"
    fi
fi

setsid -f skanpage >/dev/null 2>&1 </dev/null

if [ "$PREVIEW" = 1 ] && have_hypr; then
    # In the background, so the daemon goes back to polling right away.
    (
        i=0
        until window_open; do
            i=$((i + 1)); [ $i -gt 60 ] && { echo "skanpage window did not appear"; exit 1; }
            sleep 0.5
        done
        sleep "$DELAY"
        send_key P
    ) &
fi
