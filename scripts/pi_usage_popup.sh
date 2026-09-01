#!/usr/bin/env bash
# Toggles the per-session breakdown popup.
#   prefix + P  -> open (or close if already open)
# Inside the popup, any key (Esc included) closes it too.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLAG="${TMPDIR:-/tmp}/pi-usage-popup-$(id -u)"

if [ -f "$FLAG" ]; then
  # popup is open -> close it
  rm -f "$FLAG"
  tmux display-popup -C >/dev/null 2>&1
  exit 0
fi

touch "$FLAG"
tmux display-popup -E -w 65% -h 60% -b rounded \
  "bash '$DIR/pi_usage_breakdown.sh'; rm -f '$FLAG'"
