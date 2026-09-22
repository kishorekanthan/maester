# Maester provider contract — v1

A provider is any executable in `~/.config/maester/providers/`. Maester knows nothing
about what it monitors; it renders whatever providers report.

## Subcommands

| Invocation | Required | Meaning |
|---|---|---|
| `<provider> status` | yes | Print **one** JSON object on stdout, exit 0. |
| `<provider> stream` | no | Print one JSON object **per line**, forever. |
| `<provider> do <action-id> [item-id]` | only if actions are declared | Perform it. Exit 0 = success. |

Maester polls `status` every `capabilities.refresh` seconds (default 5, 4s timeout).
If `capabilities.stream` is true it instead runs `stream` as a supervised long-lived
child, restarting it with backoff and falling back to polling after repeated failure.

## The object

```json
{
  "schema": 1,
  "title": "Running apps",
  "state": "warn",
  "summary": "1 not responding",
  "capabilities": { "stream": true, "refresh": 5 },
  "lines":   [ {"label": "Foreground", "value": "3 apps", "state": "ok"} ],
  "metrics": [ {"id": "cpu", "label": "CPU", "value": 6.2, "unit": "%", "pct": 6.2} ],
  "items":   [ {"id": "12345", "label": "Mail",
                "detail": "not responding · 47s", "state": "warn",
                "metrics": [ {"id": "cpu", "label": "CPU", "value": 2.57, "unit": "%", "pct": 2.57},
                             {"id": "mem", "label": "Mem", "value": 304.8, "unit": "MiB", "pct": 2.6} ],
                "actions": [ {"id": "open", "label": "Open"},
                             {"id": "quit", "label": "Quit"},
                             {"id": "force-quit", "label": "Force quit"} ] } ],
  "actions": [ {"id": "activity_monitor", "label": "Open Activity Monitor", "terminal": true} ]
}
```

### Fields

- `schema` — must be `1`.
- `title` — section heading. Required.
- `state` — `ok` | `warn` | `error` | `off`. Required. The menu bar icon is the
  worst state across all providers.
- `summary` — one short line under the title. Optional.
- `icon` — what the thing *is*, shown in place of the state tick. Optional, on
  the report and on each item. Health is not lost: it moves to a small badge on
  the icon's corner, which appears only when the state is not `ok`. Schemes:
  - `bundle:<id>` — an application's icon, e.g. `bundle:com.apple.Safari`.
  - `path:<abs path>` — the icon for a file. A path inside an app bundle resolves
    to the *outermost* `.app`, so a helper shows its application's icon.
  - `pid:<n>` — the icon of a running application. Use `bundle:` where you can:
    a pid changes on every relaunch.
  - `sf:<symbol>` — an SF Symbol, e.g. `sf:apple.logo`. Drawn in the label colour.
  - `asset:<name>` — a glyph Maester ships (`Resources/glyphs/<name>.png`), for
    ideas SF Symbols has no symbol for. `robot` is the one that exists today.

  A hint that will not resolve falls back to the state tick, so naming an app
  that is not installed degrades rather than blanking the row.
- `capabilities.stream` — declare `stream` support. `capabilities.refresh` — poll
  seconds (clamped to 1–3600).
- `lines` — plain label/value rows. `state` optional, colours the value.
- `metrics` — a metric carries **either** `value` + `unit` (numeric: charted, and
  Maester keeps a 60-sample history for the sparkline) **or** `text` (display only).
  `pct` (0–100) draws a bar where a percentage is meaningful.
- `items` — repeating rows with their own metrics and actions. `label` is
  required. `id` must be stable across reports: it is the sparkline history
  key and the argument passed to `do`.
- `actions` — buttons. `terminal: true` is a display hint only (shows a terminal
  glyph); the provider itself is responsible for opening a window if it wants one.
  `removes: true` on an item action says that a successful run makes the item
  cease to exist. Maester then hides that row as soon as the action returns,
  rather than leaving it on screen until the next report. The row comes back if
  the next report still lists it, and after 8 seconds regardless, so a
  mis-declared action costs a brief flicker and not a permanently missing row.
  The flag is a statement about the item, not an instruction: Maester never
  learns what the action does.

## Trust model

The contract carries **no command strings**. Maester only ever executes
`<provider> do <declared-id> [item-id]`, and the id must match one the provider
declared in its most recent report. A provider cannot ask Maester to run arbitrary
text.

Providers are refused at load time unless the file **and** its directory are owned by
you and are not group- or world-writable — the same check `ssh` and `sudo` apply to
their own configs. The reason is shown in the panel rather than silently swallowed.

## Being a good provider

- Exit fast. A `status` that takes longer than 4s is reported as `timed out`.
- Never block on the network without a timeout of your own.
- Print nothing but JSON on stdout. Diagnostics go to stderr; Maester surfaces
  stderr when an action fails.
- Prefer `off` over `error` when the thing you monitor is simply not running.
- Report `—`/absent metrics rather than stale ones when the source is unavailable.

## Checking your provider

```
maester-doctor            # every provider
maester-doctor apps       # one
```

It runs `status`, validates the object against this document, checks permissions,
and reports violations.
