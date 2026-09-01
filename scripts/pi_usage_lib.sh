#!/usr/bin/env bash
# Shared helpers for the pi-usage tmux plugin.
# Meant to be sourced by the plugin scripts (not run directly).

set -uo pipefail

PI_USAGE_SESSIONS_DIR="${PI_USAGE_SESSIONS_DIR:-$HOME/.pi/agent/sessions}"

pi_usage_tmux_option() {
  local name="$1" default="$2" value
  value="$(tmux show-option -gqv "$name" 2>/dev/null)"
  printf '%s' "${value:-$default}"
}

# Config: env vars win (handy for testing), otherwise tmux @ options.
PI_USAGE_IDLE_MIN="${PI_USAGE_IDLE_MINUTES:-$(pi_usage_tmux_option @pi-usage-idle-minutes 10)}"
PI_USAGE_SCOPE="${PI_USAGE_SCOPE:-$(pi_usage_tmux_option @pi-usage-scope today)}"

PI_USAGE_TODAY="$(date +%F)"
PI_USAGE_START_OF_DAY="$(date -d "$PI_USAGE_TODAY 00:00:00" +%s)"

# --- helpers ---------------------------------------------------------------

# Format seconds as "5h 12m", "42m", "8s" or "0m".
pi_usage_format_duration() {
  local secs="$1" h m s
  if [ "$secs" -eq 0 ]; then
    printf '0m'
    return
  fi
  h=$((secs / 3600)); m=$(((secs % 3600) / 60)); s=$((secs % 60))
  if   [ "$h" -gt 0 ]; then printf '%dh %dm' "$h" "$m"
  elif [ "$m" -gt 0 ]; then printf '%dm' "$m"
  else printf '%ds' "$s"; fi
}

# cwds of tmux panes currently running pi (one per line).
pi_usage_open_pane_cwds() {
  tmux list-panes -a -F '#{pane_current_command}|#{pane_title}|#{pane_current_path}' 2>/dev/null |
    gawk -F'|' '($1 == "pi" || $2 ~ /^π /) && $3 != "" { print $3 }'
}

# Session header (first line of a session file): cwd<TAB>start-iso
pi_usage_header() {
  local file="$1"
  head -1 "$file" | gawk '{
    cwd = ""; st = ""
    i = index($0, "\"cwd\":\"");       if (i) { s = substr($0, i + 7);  j = index(s, "\""); cwd = substr(s, 1, j - 1) }
    i = index($0, "\"timestamp\":\""); if (i) { s = substr($0, i + 13); j = index(s, "\""); st  = substr(s, 1, j - 1) }
    print cwd "\t" st
  }'
}

# Active seconds (today only) for one session file.
#
# Walks every entry timestamp in the file (all entry types count as
# activity) and sums the gaps between consecutive entries, ignoring any gap
# longer than the idle threshold. The tail (last entry -> now) is counted
# only while the session is still within the idle threshold, so the number
# ticks up live while you work and freezes once you walk away.
#
# Entries older than the start of today are dropped, and the session header
# line (line 1) is never treated as activity.
pi_usage_active_seconds() {
  local file="$1"
  gawk -v now="$(date +%s)" -v start="$PI_USAGE_START_OF_DAY" -v idle="$((PI_USAGE_IDLE_MIN * 60))" '
    function ts(iso, a) {
      split(iso, a, /[-T:.Z]/)          # y m d H M S [ms]
      return mktime(a[1]" "a[2]" "a[3]" "a[4]" "a[5]" "a[6], 1)
    }
    NR == 1 { next }                    # session header, not activity
    {
      i = index($0, "\"timestamp\":\"")
      if (!i) next
      s = substr($0, i + 13); j = index(s, "\""); iso = substr(s, 1, j - 1)
      t = ts(iso)
      if (t < start) next
      if (have) {
        d = t - prev
        if (d > 0 && d <= idle) total += d
      }
      prev = t; have = 1
    }
    END {
      if (have) {
        d = now - prev
        if (d >= 0 && d <= idle) total += d
      }
      print total + 0
    }' "$file"
}
