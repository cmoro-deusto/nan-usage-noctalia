# Changelog

The format loosely follows [Keep a Changelog](https://keepachangelog.com/), and
the project uses [semantic versioning](https://semver.org/).

## [0.1.0] — unreleased

First release.

### Added

- **A bar widget** showing the percentage of the model that is worst off, the time
  to its reset and the tool's gauge, coloured by consequence: amber when the
  average burn rate projects past 75 % at the reset, red when it would exhaust the
  quota with a lockout of at least a tenth of the period.
- **A panel** with the account's aggregate consumption as one bar per period, each
  model's share of the period's tokens, and — per model — the percentage, the
  tokens used against the cap, the time to the reset and the tool's reading of the
  burn rate. Noctalia places it, so it needs no compositor configuration.
- **Values in the tooltip**, one line per model and per consumption period.
- The logo as a themed ghost — white or black ink to match the shell's mode — or
  the coloured mark, from rasters generated out of one SVG.
- Tests: one that executes both scripts against stubs of the Noctalia API, and one
  that checks the manifest, the translations, the plugin id and every API member,
  `ui` prop and callback the scripts use against Noctalia's own definitions.
