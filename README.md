# pi-tmux-session · pi-usage

A [tmux](https://github.com/tmux/tmux) plugin that tracks how long you've been
doing agentic coding with [Pi](https://github.com/earendil-works/pi-mono) — the
**active** time across all your Pi sessions, aggregated per day.

It shows a live `⏱ 5h 12m agentic` segment in the tmux status bar and opens a
per-session breakdown popup on a hotkey.

## What it measures

Pi saves every session as a JSONL transcript under
`~/.pi/agent/sessions/--<cwd>--/<timestamp>_<uuid>.jsonl`. Each entry (user
message, assistant reply, tool call, compaction, …) carries an ISO timestamp.

The plugin walks those timestamps and sums the **gaps between consecutive
entries**, which is a much better proxy for "time spent agentic coding" than
wall-clock elapsed time:

- gaps **longer than an idle threshold** (default 10 min) are treated as idle
  and excluded — lunch breaks and left-open panes don't count;
- the tail (last entry → now) counts only while you're still within the idle
  threshold, so the number **ticks up live** while you work and freezes once
  you walk away;
- entries **before today** are dropped, so it always reports the current day.

Sessions are discovered from session files touched today, so **closed sessions
count too** — it's your daily total, not just what's currently open. (Set
`@pi-usage-scope open` to restrict to panes that are open right now.)

## Install

### with tpm (recommended)

The plugin is public on GitHub: <https://github.com/jettandres/pi-tmux-session>

In `~/.tmux.conf`:

```tmux
set -g @plugin 'jettandres/pi-tmux-session'

# options (optional, shown with defaults)
set -g @pi-usage-idle-minutes 10   # gaps longer than this (min) = idle
set -g @pi-usage-scope today       # today | open
set -g @pi-usage-key P             # breakdown popup key (prefix + <key>)
```

Install and reload:

```sh
~/.tmux/plugins/tpm/bin/install_plugins   # or prefix + I in tmux
tmux source-file ~/.tmux.conf             # or restart tmux
```

### developing locally (symlink)

If you're hacking on the plugin itself, clone it and symlink into tpm:

```sh
git clone https://github.com/jettandres/pi-tmux-session ~/codes/ai-slops/pi-tmux-session
ln -s ~/codes/ai-slops/pi-tmux-session ~/.tmux/plugins/pi-tmux-session
```

Then in `~/.tmux.conf` use `set -g @plugin 'pi-tmux-session'`. Edits in the
local checkout take effect on the next config reload — no re-clone needed.

### without tpm

```sh
git clone https://github.com/jettandres/pi-tmux-session ~/.tmux/plugins/pi-tmux-session
```

```tmux
run-shell ~/.tmux/plugins/pi-tmux-session/pi-tmux-session.tmux
```

## Usage

| Action | Keys |
|---|---|
| Open / close the per-session breakdown | `prefix + P` (Esc or any key inside also closes) |
| Live total in the status bar | `⏱ 5h 12m agentic` (refreshes every `status-interval`) |

The breakdown popup groups sessions by project, each session showing its start
time and active duration:

```text
  ─ Pi agentic usage · Tue Sep 01 ─
  ⏱ 2h 17m total · 5 sessions · idle > 10m excluded

  job-hunter  (1h 57m)
    17:04  1h 28m
    16:20  29m
  pi-tmux-session  (10m)
    18:11  10m
  Alvaro  (9m)
    18:04  9m
```

## How it works

```
pi-tmux-session.tmux          tpm entry: appends the status-right segment,
                              binds the popup key, refreshes the bar
scripts/
  pi_usage.sh                 status segment (#() interpolation)
  pi_usage_popup.sh           toggles the breakdown popup (display-popup)
  pi_usage_breakdown.sh       pretty-printed per-session breakdown
  pi_usage_lib.sh             shared logic (discovery + active-time math)
```

- **Discovery:** `find ~/.pi/agent/sessions -maxdepth 2 -name '*.jsonl'
  -newermt today` — session files touched today (subagent sessions under
  `sessions/subagents/` are excluded).
- **Active time:** GNU awk parses each entry's first `"timestamp":"…"` field,
  converts to epoch with `mktime(..., 1)` (UTC), and sums gaps ≤ idle
  threshold. The session header line (line 1) is never counted as activity.
- **Performance:** ~25 ms per 1 MB session file; well within the default 5 s
  `status-interval`.

## Notes & limitations

- **Ephemeral sessions** (`pi --no-session`) write no file and are not
  tracked.
- **Panels sharing a working directory** resolve to the same session file and
  are counted once.
- Requires GNU tools: `bash 4+`, `gawk` (for `mktime(..., 1)` UTC flag),
  GNU `find`/`date`. Linux recommended; macOS would need a small port.
- The status segment hides itself when there's no Pi usage today.

## Configuration reference

| Option | Default | Description |
|---|---|---|
| `@pi-usage-idle-minutes` | `10` | gaps longer than this (minutes) are idle |
| `@pi-usage-scope` | `today` | `today` = all sessions today (open or closed), `open` = only panes open right now |
| `@pi-usage-key` | `P` | key (after prefix) that toggles the breakdown popup |
