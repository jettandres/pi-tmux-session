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

# Health meter: comma-separated daily limits in minutes.
# Levels: fresh(0) < healthy(1) < moderate(2) < heavy(3) < over-dependent(4+)
PI_USAGE_HEALTH_LIMITS="${PI_USAGE_HEALTH_LIMITS:-$(pi_usage_tmux_option @pi-usage-health-limits "60,120,240")}"

# --- health meter ------------------------------------------------------------

# Level for a number of active seconds: 0 = fresh, 1..N = tiers from limits.
pi_usage_health_level() {
  local secs="$1" lim lvl=1
  local IFS=','
  for lim in $PI_USAGE_HEALTH_LIMITS; do
    [ "$secs" -lt "$((lim * 60))" ] && break
    lvl=$((lvl + 1))
  done
  printf '%d' "$lvl"
}

pi_usage_health_icon() {
  case "$1" in
    0) printf '󰚩' ;;   # robot
    1) printf '󱜙' ;;   # robot-happy
    2) printf '󱚣' ;;   # robot-excited
    3) printf '󱚟' ;;   # robot-confused
    4) printf '󱚥' ;;   # robot-love
    5) printf '󱚡' ;;   # robot-dead (spare tier)
    *) printf '󰚩' ;;
  esac
}

pi_usage_health_color() {
  case "$1" in
    0) printf '#606b81' ;;   # slate (fresh)
    1) printf '#7ddc8f' ;;   # green  (healthy)
    2) printf '#e2e98f' ;;   # yellow (moderate, matches palette)
    3) printf '#e0a35f' ;;   # orange (heavy)
    4) printf '#e06b6b' ;;   # red    (over-dependent)
    5) printf '#d05252' ;;   # deep red (spare tier)
    *) printf '#606b81' ;;
  esac
}

pi_usage_health_name() {
  case "$1" in
    0) printf 'fresh' ;;
    1) printf 'healthy' ;;
    2) printf 'moderate' ;;
    3) printf 'heavy' ;;
    4) printf 'over-dependent' ;;
    5) printf 'burnt out' ;;
    *) printf 'fresh' ;;
  esac
}

# "1h 20m used · 2h 40m left of 4h budget" (or OVER budget)
pi_usage_budget_line() {
  local secs="$1" budget_min="$2" used left
  used="$(pi_usage_format_duration "$secs")"
  if [ "$secs" -lt "$((budget_min * 60))" ]; then
    left="$(pi_usage_format_duration "$((budget_min * 60 - secs))")"
    printf '%s used · %s left of %s budget' "$used" "$left" "$(pi_usage_format_duration "$((budget_min * 60))")"
  else
    printf '%s used · OVER the %s budget' "$used" "$(pi_usage_format_duration "$((budget_min * 60))")"
  fi
}

# compact limit label: 60 -> 1h, 90 -> 90m
pi_usage_format_limit() {
  local m="$1"
  if [ $((m % 60)) -eq 0 ]; then printf '%dh' "$((m / 60))"; else printf '%dm' "$m"; fi
}

# Format seconds as "5h 12m", "42m", "8s" or "0m".
pi_usage_format_duration() {
  local secs="$1" h m s
  if [ "$secs" -eq 0 ]; then
    printf '0m'
    return
  fi
  h=$((secs / 3600)); m=$(((secs % 3600) / 60)); s=$((secs % 60))
  if   [ "$h" -gt 0 ] && [ "$m" -gt 0 ]; then printf '%dh %dm' "$h" "$m"
  elif [ "$h" -gt 0 ]; then printf '%dh' "$h"
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
