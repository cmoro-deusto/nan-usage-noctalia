# NaN Usage

Your [NaN](https://nan.builders) subscription quota in the Noctalia bar: how
loaded the worst model is, the time until its reset, and a colour when the burn
rate is heading for trouble. The panel behind the widget shows one bar per model,
where the period's tokens went, and the account's aggregate consumption.

It is a front end to `nan-usage`: the plugin runs that command line tool, paints
what it prints, and decides nothing itself.

## Plugin

| Field | Value |
| --- | --- |
| ID | `nan-usage/quota` |
| Entries | Bar widget: `bar`; panel: `panel` |

## Requirements

Install **`nan-usage`** and put it on `PATH` — the bar widget runs it, and nothing
works without it. The tool needs a NaN API key in `~/.config/nan/api-key`, the
same file the `nan` CLI uses; `nan-usage doctor` reports on the key, the API, the
cache and the widget setup in one go.

GTK4 is **optional**: it is only used by `nan-usage popup` and `nan-usage prefs`,
the separate windows described under Notes. The widget and the panel are Noctalia
surfaces and need nothing beyond the shell itself.

## Usage

The bar widget shows the percentage of the model that is worst off and its time
to reset, coloured by the tool's verdict: your theme's own colour while the burn
rate is fine, amber if the average rate projects past 75 % by the reset, red if
that rate would exhaust the quota and leave you locked out for a tenth of the
period or more.

- **Left click** opens the panel. Pressing again closes it.
- **Right click** opens the tool's GTK settings window, if GTK4 is installed.
- **Hover** lists the values: tokens used against the cap and the time to reset
  for each model, then one line per consumption period.
- **The gauge** beside the text is what `panel_gauge` says: `bar` or `ring` (both
  draw the bar — see Notes) or `none` for text only.

The panel has two columns: the account and its models on the left, the selected
one's detail on the right. `Overall` is the first entry and what the panel opens
on; it shows the aggregate consumption, one bar per period, and each model's
share of the period's tokens. Pick a model to see its percentage, a thicker bar,
the time to its reset, tokens used against the cap, and the tool's reading of its
burn rate.

Open the panel from anywhere, including a compositor key binding:

```sh
noctalia msg panel-toggle nan-usage/quota:panel
```

## Settings

Set in **Settings → Plugins** (the gear on the plugin's row), or from the panel's
own cog.

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `command` | `string` | `nan-usage` | The executable to run. Give it an absolute path if the shell Noctalia spawns cannot reach your `PATH`. |
| `left_click` | `select` | `panel` | What a left click does: open the panel, open the GTK popup window instead, or nothing. |
| `interval` | `int` | `60` | Seconds between records. This is *not* the poll interval: the tool asks the NaN API on its own schedule (`poll_seconds` in its own configuration) and recomputes the reset countdowns in between. |
| `show_icon` | `bool` | `true` | Draw the NaN mark in the bar. |
| `icon_style` | `select` | `ghost` | `ghost` draws the mark in the theme's own ink (white on a dark theme, black on a light one); `color` draws it as NaN does. |
| `show_glyph` | `bool` | `false` | Draw a glyph instead of the mark, when `show_icon` is off. |
| `glyph` | `glyph` | `chart-pie` | Which glyph, when `show_glyph` is on. |
| `show_tooltip` | `bool` | `true` | Show the details on hover. |

The gauge follows the **tool's** own setting rather than a second copy here:

```sh
nan-usage config set panel_gauge bar     # ring, bar or none
```

## Notes

- **Commands it runs.** The widget keeps one `nan-usage watch --json` process
  alive (the tool is what talks to NaN, with your key in `~/.config/nan/api-key`
  and its cache in `$XDG_CACHE_HOME/nan-usage/`). The panel's refresh button runs
  `nan-usage json --force`, right click runs `nan-usage prefs`, and the link button
  opens NaN's dashboard, `cloud.nan.builders`, in your browser — through `gio
  open`, falling back to `xdg-open`, reporting the failure when neither exists. The
  plugin itself makes no network request and writes no file.
- **A bar widget cannot draw a ring.** Noctalia has no arc primitive inside the
  bar, so `ring` comes out as the bar; only the separate GTK popup draws a real
  ring. The setting is honoured, its shape is not.
- **The tooltip carries values, not sentences**, on purpose: the tool's captions
  are long enough that a tooltip cuts their tail, and a cut-off number is worse
  than none. The captions are in the panel, which has the room.
- **Multi-monitor.** Each bar gets its own widget instance and therefore its own
  `watch` process. They share one cache and the tool's poll floor, so this does not
  multiply the API traffic.
- **The GTK windows are optional** and separate: `nan-usage popup` (a per-model
  popup with the burn-rate projection, floated under the bar by a compositor rule)
  and `nan-usage prefs` (the tool's own settings). Neither is needed for the widget
  or the panel.
- **Debugging.** The panel logs one line when it loads; Noctalia logs every prop or
  control it skips. If the bar is empty or the panel blank:
  `grep -i 'NaN Usage' ~/.cache/noctalia/noctalia.log`, then `nan-usage doctor`.
- **The plugin is optional to the tool.** Nothing here changes what the command
  line tool, its popup or its settings window do; they work with Noctalia absent.

## Tests

Run from this directory:

```sh
lua tests/plugin_test.lua          # executes both scripts against stubs of the API
python3 tests/plugin_check.py      # reads the manifest, the translations and the scripts
```

The first drives the real `bar.luau` and `panel.luau` through a record, a failed
record and an unreadable one; it clicks a model and checks that the highlight moved
with it, opens the overall entry, refreshes with a working and a failing command,
and checks the gauge, the tooltip and the icon against the settings. Several bugs
in this plugin could only ever show up at runtime, so the tests run the scripts
rather than reading them.

The second is static, and needs Python 3.11 or newer for its TOML reader: the
manifest against its own translation keys, the plugin directory against its id, and
every API member, `ui` control, `ui` prop, callback and translation key the scripts
use against Noctalia's own definitions, which it downloads — the check is skipped
without network. It also refuses a `local` function called above its own
definition, which is a nil global at runtime.
