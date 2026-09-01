#!/usr/bin/env bash
# Per-session breakdown for the display-popup. Ends waiting for a keypress
# so the popup stays open until dismissed (Esc or any key).
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=pi_usage_lib.sh
. "$DIR/pi_usage_lib.sh"

mapfile -t FILES < <(find "$PI_USAGE_SESSIONS_DIR" -maxdepth 2 -type f -name '*.jsonl' -newermt "$PI_USAGE_TODAY" 2>/dev/null)

if [ "$PI_USAGE_SCOPE" = "open" ]; then
  declare -A open_set=()
  while IFS= read -r c; do [ -n "$c" ] && open_set[$c]=1; done < <(pi_usage_open_pane_cwds)
  kept=()
  for f in "${FILES[@]}"; do
    cwd="$(pi_usage_header "$f" | cut -f1)"
    [ -n "${open_set[$cwd]:-}" ] && kept+=("$f")
  done
  FILES=("${kept[@]}")
fi

if [ "${#FILES[@]}" -eq 0 ]; then
  printf '\n  No Pi sessions %s.\n' "$([ "$PI_USAGE_SCOPE" = "open" ] && printf 'open' || printf 'today')"
  printf '\n  ⏎ press any key to close '
  read -r -n 1 -s
  exit 0
fi

declare -A active proj start
total=0
for f in "${FILES[@]}"; do
  a="$(pi_usage_active_seconds "$f")"
  active[$f]=$a
  total=$((total + a))
  IFS=$'\t' read -r cwd st <<<"$(pi_usage_header "$f")"
  if [ -n "$cwd" ]; then proj[$f]="$(basename "$cwd")"; else proj[$f]="?"; fi
  start[$f]="$(date -d "$st" '+%H:%M' 2>/dev/null || printf '?')"
done

# group files by project, projects sorted by their total active time
declare -A proj_total proj_list
for f in "${FILES[@]}"; do
  p="${proj[$f]}"
  proj_total[$p]=$(( ${proj_total[$p]:-0} + active[$f] ))
  proj_list[$p]="${proj_list[$p]:-}"$'\n'"$f"
done
mapfile -t PROJS < <(for p in "${!proj_total[@]}"; do
  printf '%012d\t%s\n' "${proj_total[$p]}" "$p"
done | sort -k1,1nr | cut -f2)

if [ "$total" -eq 0 ]; then lvl=0; else lvl="$(pi_usage_health_level "$total")"; fi
budget_min="${PI_USAGE_HEALTH_LIMITS##*,}"   # last limit = daily budget

# legend: one icon per tier with its limit (e.g. 󱜙<1h 󱚣<2h 󱚟<4h 󱚥≥4h)
legend=""
blvl=1
IFS=',' read -r -a blims <<< "$PI_USAGE_HEALTH_LIMITS"
for bl in "${blims[@]}"; do
  legend+="$(pi_usage_health_icon "$blvl")<$(pi_usage_format_limit "$bl") "
  blvl=$((blvl + 1))
done
legend+="$(pi_usage_health_icon "$blvl")≥$(pi_usage_format_limit "${blims[${#blims[@]} - 1]}")"

printf '\n'
printf '  ─ Pi agentic usage · %s ─\n' "$(date '+%a %b %d')"
printf '  #[fg=#1d3245,bg=%s] %s %s #[default]   %s\n' \
  "$(pi_usage_health_color "$lvl")" "$(pi_usage_health_icon "$lvl")" \
  "$(pi_usage_health_name "$lvl")" "$(pi_usage_budget_line "$total" "$budget_min")"
printf '  %d session%s · idle > %sm excluded\n' \
  "${#FILES[@]}" "$([ "${#FILES[@]}" -gt 1 ] && printf s || true)" \
  "$PI_USAGE_IDLE_MIN"
printf '\n'

for p in "${PROJS[@]}"; do
  printf '  %s  (%s)\n' "$p" "$(pi_usage_format_duration "${proj_total[$p]}")"
  # sessions of this project, most active first
  mapfile -t PF < <(printf '%s\n' "${proj_list[$p]}" | sed '1d' | while IFS= read -r f; do
    printf '%012d\t%s\n' "${active[$f]}" "$f"
done | sort -k1,1nr | cut -f2)
  for f in "${PF[@]}"; do
    printf '    %s  %s\n' "${start[$f]}" "$(pi_usage_format_duration "${active[$f]}")"
  done
done

printf '\n  levels: %s\n' "$legend"
printf '  scope: %s\n' "$PI_USAGE_SCOPE"
printf '  ⏎ press any key to close '
read -r -n 1 -s
