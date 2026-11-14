#!/bin/sh
# Called by scx4500-buttond.py when Scan -> PC is pressed.
# Environment: SCX_EVENT (raw 8-byte event, hex), SCX_DEST (destination number, 1 = "My Documents").
# Optional: SCX_SCAN_DIR (default ~/Scans), SCX_SANE_DEVICE (see `scanimage -L`), SCX_RESOLUTION.
set -eu
dir="${SCX_SCAN_DIR:-$HOME/Scans}"
mkdir -p "$dir"
file="$dir/scan_$(date +%Y%m%d_%H%M%S).png"
scanimage ${SCX_SANE_DEVICE:+-d "$SCX_SANE_DEVICE"} --format=png --resolution "${SCX_RESOLUTION:-300}" > "$file"
echo "saved $file (event $SCX_EVENT, destination $SCX_DEST)"
