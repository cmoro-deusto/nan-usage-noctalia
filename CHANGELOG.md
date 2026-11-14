# Changelog

The format loosely follows [Keep a Changelog](https://keepachangelog.com/), and
the project uses [semantic versioning](https://semver.org/).

## [2.0.0] — 2026-11-13

NaN bills subscriptions in credits now, and the API key no longer reaches the
account and metrics endpoints 1.0.1 read, so the plugin is rebuilt around credits.

### Changed

- **One request per poll**, to NaN's documented usage report,
  `https://api.nan.builders/v1/usage`. The plugin no longer calls
  `cloud-api.nan.builders`: its quota endpoint stopped updating, and its account and
  metrics endpoints now refuse API keys.
- **The bar shows the period's credits**: the share of the allowance used (or the
  credits used or left), the time to the renewal, and a colour that follows the
  pace, counting credit packs. It shows `paused` when the subscription is, and the
  packs left once the allowance is spent.
- **The panel is rebuilt around the billing period**: credits used, left and in
  packs with the pace drawn ahead of them, the tokens split into new input, cached
  input and output with the cache share, credits per day, and each model's share.
  A model's detail adds an estimate of its credits split by token type.
- **`dependencies` names only `xdg-open`.** Noctalia shows the list as "requires
  …", and `gio, xdg-open` read as both being needed; either one works, and with
  neither the address is copied instead.

### Added

- **The cache share** in the tooltip and the panel, and in the bar with the new
  `show_cache` setting.
- **What the cache saved**, in credits.
- **Every model's prices** per 1M tokens of new input, cached input and output, in
  its detail, for the models you have not used yet too.
- **`bar_value`**: the bar's figure as a percentage, credits used, or credits left.
- **More gauges**: besides the bar, a battery that drains as credits go, and a
  sparkline of credits per day.
- **A banner and a "Buy a credit pack" button** when the credits and packs are
  spent, and a banner when the subscription is paused.
- **`prices.luau`**, NaN's per-model prices, and `tools/prices-from-har.py`, which
  generates it from a HAR of NaN's own price list.

### Removed

- The per-model token caps and the plan tier: no endpoint an API key can read
  reports them any more.
- The settings `panel_model`, `panel_model_id`, `show_model`, `hide_unused`,
  `show_metrics` and `show_percentage`. Values saved for them are ignored.

## [1.0.1] — 2026-10-26

Made in the community plugins repository by its maintainers.

### Changed

- The panel's cards use the renamed palette roles `surface_container` and
  `outline_variant`, which need plugin API 43.

## [1.0.0] — 2026-09-23

First release.

### Added

- **A bar widget** showing the percentage of the model that is worst off, the time
  to its reset and its gauge, coloured by consequence: amber when the
  average burn rate projects past 75 % at the reset, red when it would exhaust the
  quota with a lockout of at least a tenth of the period.
- **A panel** with the account's aggregate consumption as one bar per period, each
  model's share of the period's tokens, and — per model — the percentage, the
  tokens used against the cap, the time to the reset and the reading of its burn
  rate. Noctalia places it, so it needs no compositor configuration.
- **Values in the tooltip**, one line per model and per consumption period.
- **The dashboard address is copied, not opened**: an opener would mean spawning
  `gio` or `xdg-open`, and the plugin starts no process.
- The logo as a themed ghost — white or black ink to match the shell's mode — or
  the coloured mark, from rasters generated out of one SVG.
- **Self-contained.** The plugin owns the API key, polls `cloud-api.nan.builders`
  itself, keeps what it reads in memory and writes no file. The only command it
  shells out to is the browser opener behind the panel's link button, and only when
  that button is pressed.
- Tests: the model under a fixed clock with no host at all, the three entries
  against stubs of the Noctalia API, and a static check of the manifest, the
  translations, the plugin id and every API member, `ui` prop and callback the
  scripts use against Noctalia's own definitions.
