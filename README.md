# NaN Usage, a Noctalia plugin

Your NaN (nan.builders) subscription quota in the Noctalia bar. The widget shows the
model that is worst off: its usage percentage, the time to the reset, and a colour that
follows the burn rate instead of the percentage alone. Clicking it opens a panel with
the detail for every model. The plugin talks to NaN's cloud API itself, so there is
nothing to install alongside it and no command has to be on `PATH`.

`nan-usage/` is the plugin, and its id is `cmoro-deusto/nan-usage`. The directory name
is the part of the id after the slash, which is the layout a plugin source has to have,
and that is what makes this repository installable as one.

![The panel: consumption per period, each model's share of it, and the detail behind the selected row](screenshots/panel.png)

## The widget in the bar

The bar has room for one model: the one that is worst off, its usage, and the time to
the reset. The colour follows how alarming the burn rate is, not the percentage on its
own.

![The bar widget: the NaN mark, the usage percentage, and the time to the reset](screenshots/bar.png)

Hovering the widget lists the values instead. There is one line per model, with tokens
used against the cap and the time to the reset, and then one line per period. It fits in
a tooltip.

![The tooltip: a line per model with tokens against the cap, and a line per period](screenshots/tooltip.png)

## Installing it

### As a source

Use this one. Noctalia then owns the plugin, so it can update and remove it.

```sh
noctalia msg plugins source add nan-usage git https://github.com/cmoro-deusto/nan-usage-noctalia
noctalia msg plugins enable cmoro-deusto/nan-usage
```

The repository is the source, and the plugin is the `nan-usage/` directory inside it. To
update it later, open Settings, then Plugins, and use the source's Update.

### From a local checkout

The same thing, pointed at a directory you edit. This is how to work on the plugin.

```sh
cd /path/to/nan-usage-noctalia
noctalia msg plugins source add nan-usage path "$PWD"
noctalia msg plugins enable cmoro-deusto/nan-usage
```

`.luau` edits hot-reload. Manifest changes are read on the next configuration reload, and
toggling the plugin forces one.

### As a drop-in

Use this if you would rather not add a source. Noctalia only reads
`~/.local/share/noctalia/plugins/`, so there is no uninstall action and the files stay
yours.

```sh
cp -r nan-usage ~/.local/share/noctalia/plugins/
```

Then enable it in Settings, then Plugins.

### After installing

Add the widget from the bar's widget picker. To open the panel from anywhere, including
a compositor key binding:

```sh
noctalia msg panel-toggle cmoro-deusto/nan-usage:panel
```

A NaN API key is needed at `~/.config/nan/api-key`. That is the same file NaN's own
`nan` command line tool reads, so if you already use it there is nothing to do. Another
path can be set in the plugin's settings. Without a key the widget shows a dash and the
tooltip says which file it wanted.

If your Noctalia already lists `cmoro-deusto/nan-usage` in its plugin store, that is the
same plugin, and installing it from there keeps it updated with the rest.

## Updating and removing it

From a git source, use the source's Update in Settings, then Plugins, and reload the
configuration if the manifest changed. To remove it, disable the plugin and then remove
the source. If you dropped it in by hand, delete
`~/.local/share/noctalia/plugins/nan-usage/`.

## The plugin's own page

`nan-usage/README.md` is written for someone deciding whether to enable the plugin. It
explains what the colours mean, lists every setting, and says what the plugin touches:
three GETs to NaN's API per poll, one file read, no file written, and one spawned
command, which is the browser opener behind the panel's link button.

## Working on the plugin

```sh
make test
```

That runs the three checks in `nan-usage/tests/`:

- `shared_test.lua` tests the model on its own, with no host and no stubs at all,
  because the model takes the current time as an argument instead of reading a clock.
  Levels, projections and every piece of text are asserted exactly, under a fixed clock.
- `plugin_test.lua` drives the real `service.luau`, `bar.luau` and `panel.luau` against
  stubs of the Noctalia API. It asserts that the poller reads the key, asks its
  endpoints with it and publishes what came back; that a failed poll keeps the last good
  numbers and says why; that the surfaces paint that data without spawning anything; and
  that a refresh is asked for over the shared state channel. Plain Lua 5.4, no
  dependencies, under a second.
- `plugin_check.py` reads rather than runs. It checks the manifest against its
  translation keys, the plugin directory against its id, and every API member, `ui`
  control, `ui` prop, callback and translation key against Noctalia's own type
  definitions, which it downloads. The check is skipped without network. It needs Python
  3.11 or newer for its TOML reader.

The first two exist because the mistakes that cost the most time in this plugin were
invisible to reading: a first line Luau rejects while `luac` accepts it, a `local`
function called above its own definition, and a prop the host keeps because the next
render did not set it.

Two things are easy to get wrong when editing the plugin. Bump `version` in
`plugin.toml` when the plugin changes, with the changelog entry in the same commit.
Cleaning up a file in this repository, this README included, needs neither. Write
`translations/en.json` as nested objects, because a dotted key would be rewritten on the
next i18n sync, so `a.b` as a key silently churns.

## The icons

`nan-usage/nan.svg` is the source of the three rasters the plugin draws: the coloured
mark, and a black-on-white and white-on-black ghost pair for the theme. Regenerate them
with `./generate-icons.sh` at the repository root after changing the SVG. It needs
`rsvg-convert`, and it writes into `nan-usage/`, which is where the plugin ships them.

They are rasters because whether a Qt build can render SVG depends on its image plugins
being installed, and an icon that silently fails to appear is worse than a slightly
larger file.

## License

MIT, see [LICENSE](LICENSE).
