#!/usr/bin/env bash
# pi-usage status segment. Prints, for tmux status-right, e.g.:
#
#   #[fg=#1d3245,bg=#e2e98f] ⏱ 5h 12m agentic #[fg=#e2e98f,bg=#3b4261]
#
# Prints nothing when there is no Pi usage today, so the segment
# disappears instead of showing "0m".
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=pi_usage_lib.sh
. "$DIR/pi_usage_lib.sh"

# Session files touched today (open or closed sessions).
mapfile -t FILES < <(find "$PI_USAGE_SESSIONS_DIR" -maxdepth 2 -type f -name '*.jsonl' -newermt "$PI_USAGE_TODAY" 2>/dev/null)

if [ "$PI_USAGE_SCOPE" = "open" ]; then
  # Keep only sessions whose cwd has a pi pane currently open.
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
  exit 0   # no usage today (or nothing open in "open" scope) -> hide
fi

total=0
for f in "${FILES[@]}"; do
  a="$(pi_usage_active_seconds "$f")"
  total=$((total + a))
done

printf '#[fg=#1d3245,bg=#e2e98f] ⏱ %s agentic #[fg=#e2e98f,bg=#3b4261]' "$(pi_usage_format_duration "$total")"
