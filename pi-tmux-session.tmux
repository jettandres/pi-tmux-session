#!/usr/bin/env bash
# pi-tmux-session (pi-usage) — tpm plugin entry.
#
# Adds an "⏱ 5h 12m agentic" status-right segment (sum of active agentic
# time across all Pi sessions today) and binds a hotkey that opens the
# per-session breakdown in a tmux popup.
#
# Configuration (set in ~/.tmux.conf before the tpm run line):
#   set -g @pi-usage-idle-minutes 10   # gaps longer than this (min) = idle
#   set -g @pi-usage-scope today       # today | open (all sessions vs open ones)
#   set -g @pi-usage-key P             # keybinding for the breakdown popup
#
# The popup script reads the tmux options itself, so the status segment
# picks up changes without reloading the plugin.

CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"

get_tmux_option() {
  local option="$1" default="$2" value
  value="$(tmux show-option -gqv "$option" 2>/dev/null)"
  printf '%s' "${value:-$default}"
}

KEY="$(get_tmux_option @pi-usage-key P)"

# status-right segment — appended once, never clobbers the existing bar.
if ! tmux show-option -gqv status-right 2>/dev/null | grep -q 'pi_usage\.sh'; then
  tmux set-option -ga status-right "#(bash '$CURRENT_DIR/scripts/pi_usage.sh')"
fi

# per-session breakdown popup
tmux bind-key "$KEY" run-shell "bash '$CURRENT_DIR/scripts/pi_usage_popup.sh'"

# show the segment immediately instead of waiting for status-interval
tmux refresh-client -S
