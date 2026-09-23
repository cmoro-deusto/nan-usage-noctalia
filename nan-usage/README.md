# NaN Usage

Your [NaN](https://nan.builders) subscription quota in the Noctalia bar: how much
of each model's allowance is gone, how long until it resets, and whether the burn
rate is heading for a lockout — with a panel of per-model detail behind it.

The plugin talks to the NaN cloud API itself. It needs no command installed, spawns
no process and writes no file.

## Plugin

| | |
| --- | --- |
| ID | `cmoro-deusto/nan-usage` |
| Bar widget | `bar` |
| Panel | `panel` |
| Service | `poller` |
| License | MIT |
| Plugin API | 22 (`require`) |

## Requirements

**A NaN API key**, at `~/.config/nan/api-key` by default — the same file the `nan`
command line tool reads, so if you already use that, there is nothing to do. A
different path can be set under Settings.

Nothing else. There is no command to install and nothing to keep on `PATH`: the
plugin asks `cloud-api.nan.builders` directly, with that key.

## Usage

The bar widget shows the percentage of the model that is worst off and its time to
reset. It is coloured by the burn rate rather than by the percentage alone:

- your theme's own colour while the rate is fine,
- amber once the average rate projects past 75 % by the reset, or once the quota
  would run out,
- red once usage passes 90 %, or once that run-out would leave the account without
  quota for a tenth of the period or more.

- **Left click** opens the panel. Pressing again closes it.
- **Right click** opens these settings.
- **Hover** lists the values: tokens used against the cap and the time to reset for
  each model, then one line per consumption period.
- **The gauge** beside the text is what `panel_gauge` says: `bar`, or `none` for text
  only. See Notes for why there is no ring.
- **The link button** in the panel's header copies NaN's dashboard address
  (`cloud.nan.builders`) to your clipboard. It does not open a browser: doing that
  means spawning `gio` or `xdg-open`, and this plugin starts no process at all.

The panel has two columns: the account and its models on the left, the selected
one's detail on the right. `Overall` is the first entry and what the panel opens on;
it shows the aggregate consumption, one bar per period, and each model's share of
the period's tokens. Pick a model to see its percentage, a thicker bar, the time to
its reset, tokens used against the cap, and the reading of its burn rate.

Open the panel from anywhere, including a compositor key binding:

```sh
noctalia msg panel-toggle cmoro-deusto/nan-usage:panel
```

## Settings

Set in **Settings → Plugins** (the gear on the plugin's row), or from the panel's
own cog.

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `api_key` | `file` | `~/.config/nan/api-key` | The file holding your NaN API key. |
| `interval` | `int` | `300` | Seconds between requests to the NaN API. |
| `panel_model` | `select` | `worst` | Which model the bar reflects: the most alarming, the fullest, or a pinned one. |
| `panel_model_id` | `string` | `deepseek-v4-flash` | The model to pin, when `panel_model` is `fixed`. |
| `panel_gauge` | `select` | `bar` | The indicator beside the text: `bar` or `none`. |
| `show_percentage` | `bool` | `true` | The usage figure in the bar. |
| `show_reset` | `bool` | `true` | The countdown to the reset, in the bar. |
| `show_model` | `bool` | `true` | Which model the figure belongs to, abbreviated (`ds4f`). |
| `hide_unused` | `bool` | `false` | Drop models with no usage from the panel's list. |
| `show_metrics` | `bool` | `true` | The account-wide 24 h / month / 30 d totals, in the panel and the tooltip. Turning it off also saves the request. |
| `show_icon` | `bool` | `true` | Draw the NaN mark in the bar. |
| `icon_style` | `select` | `ghost` | `ghost` draws the mark in the theme's own ink (white on a dark theme, black on a light one); `color` draws it as NaN does. |
| `show_glyph` | `bool` | `false` | Draw a glyph instead of the mark, when `show_icon` is off. |
| `glyph` | `glyph` | `chart-pie` | Which glyph, when `show_glyph` is on. |
| `show_tooltip` | `bool` | `true` | Show the details on hover. |
| `left_click` | `select` | `panel` | What a left click does: open the panel, or nothing. |

## Where the data comes from

Three requests, once per `interval`, all of them `GET`s to
`https://cloud-api.nan.builders` with your key as a bearer token:

| Endpoint | What it carries |
| --- | --- |
| `/api/usage/quota` | Every model's allowance for the period, what is used, when it resets. |
| `/api/auth/me` | The account handle, region and tier. |
| `/api/metrics/usage` | Aggregate consumption over 24 h, the month and 30 d. Skipped when `show_metrics` is off. |

That is the whole of the plugin's traffic. Nothing else is contacted, no file is
read but the key, and no file is written — the key and the responses are held in
memory only, so a reload starts from nothing and shows a dash until the first
request lands.

The NaN API has no published contract; the shapes it returns were read from the
NaN panel itself. Answers are parsed leniently — numbers may arrive as strings,
timestamps as epoch seconds or ISO dates — and anything unreadable is reported in
the tooltip rather than swallowed.

## Notes

- **Levels come from the rate, not the percentage.** 80 % of a month on the third
  day is a warning, and so is a projection that lands past 75 %; running out is
  critical only when it would leave you without quota for a tenth of the period or
  more, because running out just before the reset is merely a bad day.
- **A bar widget cannot draw a ring.** Noctalia has no arc primitive inside a bar,
  and `ui.progress` is the only gauge it renders there, so the only gauge settings
  are a bar and none. The panel draws its own bars, which have the room.
- **The tooltip carries values, not sentences**, on purpose: the captions are long
  enough that a tooltip cuts their tail, and a cut-off number is worse than none.
  The captions are in the panel, which has the room.
- **One poller serves every monitor.** The widget can be on several bars; the service
  is one entry per plugin, so the API traffic does not multiply.
- **When something is wrong** the last good numbers stay on the bar and the tooltip
  says so, together with the reason: a missing key, a rejected key, an unreachable
  API, or an answer that could not be read.
- **Debugging.** Noctalia logs every prop or control it skips; add the plugin's own
  lines with `grep -i 'NaN Usage' ~/.cache/noctalia/noctalia.log`. If the bar shows
  a dash, the tooltip names the reason.
- **Community project, not official**: not affiliated with or endorsed by
  nan.builders. "NaN" and its logo belong to their owners, and the logo shipped here
  — the SVG the rasters are drawn from — derives from their public favicon.
  MIT-licensed.

## Tests

Run from this directory:

```sh
lua tests/shared_test.lua          # the model, under a fixed clock, with no host
lua tests/plugin_test.lua          # the three entries against stubs of the API
python3 tests/plugin_check.py      # reads the manifest, the translations and the scripts
```

The first is the model on its own: levels, projections and every text, asserted
exactly — which is only possible because the model takes the current time as an
argument instead of reading a clock.

The second drives the real `service.luau`, `bar.luau` and `panel.luau`: that the
poller reads the key, asks the endpoints, publishes what came back and keeps the
last good numbers when one fails; that the widget and the panel paint that data
without spawning anything; and that a refresh is asked for over the shared state
channel rather than by running a program.

The third is static, and needs Python 3.11 or newer for its TOML reader: the
manifest against its own translation keys, the plugin directory against its id,
and every API member, `ui` control, `ui` prop, callback and translation key the
scripts use against Noctalia's own definitions, which it downloads — the check is
skipped without network. It also refuses a `local` function called above its own
definition, which is a nil global at runtime.
