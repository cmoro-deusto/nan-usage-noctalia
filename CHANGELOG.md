# Changelog

The format loosely follows [Keep a Changelog](https://keepachangelog.com/), and
the project uses [semantic versioning](https://semver.org/).

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
- **No command line tool to install.** The plugin owns the API key, polls
  `cloud-api.nan.builders` itself and keeps the answers in memory, and writes no
  file. The only command it shells out to is the browser opener behind the panel's
  link button, and only when that button is pressed.
- Tests: the model under a fixed clock with no host at all, the three entries
  against stubs of the Noctalia API, and a static check of the manifest, the
  translations, the plugin id and every API member, `ui` prop and callback the
  scripts use against Noctalia's own definitions.
