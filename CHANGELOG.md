# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.1] - 2026-07-22

### Fixed

- Proper case-insensitive HTTP header collision detection. Caller-supplied headers now suppress custom rule injection regardless of capitalization.

## [0.3.0] - 2026-07-21

### Fixed

- Wire `config.migrate()` into plugin startup (was never called on init).
- Preserve `enabled` and `secret` flags when editing a custom rule — Lua
  `and`/`or` falsey trap no longer resets `false` to `true`.
- Re-read custom rule state on every row render — toggling enabled from
  submenu now reflects immediately without closing/reopening the editor.
- Hide Copy button in log viewer when clipboard is unavailable (feature
  detection via `Device` capability flags).
- Reject `nil`, non-string, non-table, and empty-string inputs in
  `config.lua` domain and custom-header helpers with early returns.
- Preserve LuaSocket 4-tuple `(ok, code, headers, status)` return in both
  table-form and string-form wrappers (status was lost).
- Forward POST body argument when promoting string-form requests to table
  form — `request(url, "k=v")` now sets method POST, content-length, and
  `ltn12.source.string(body)`.

### Changed

- Replace dead `cf_active` return with per-request summary log line
  (`applied: cf=<yes|no>, custom=<count>`). Suppressed when nothing
  injected (reduces noise).
- Single-pass redaction with unified 32-char threshold on charset
  `[A-Za-z0-9+/=_-]` — replaces original two-pass hex/base64 design.

### Added

- Throttle repeated "skip host=" debug lines — one-slot cache coalesces
  consecutive identical skips into `"skip host=X (suppressed N times)"`.
  Cache resets on injection boundaries.
- Show inherited global allowlist size in custom rule rows
  (`"inherits global (N)"`).

### Tests

- Close coverage gaps: case-insensitive caller collision, CF Access not
  matching with custom rule only, secret=false logging boundary, 4-tuple
  status preservation through injection.

### Build

- GitHub Actions CI workflow: LuaJIT 2.1, luacheck, busted, LuaRocks cache
  on ubuntu-latest. CI badge in README.
- Release packaging script (`scripts/package.sh`) that produces
  `dist/CloudflareAccess.koplugin-vX.Y.Z.zip` with runtime files only.
  Tag-triggered GitHub Actions workflow artifact upload.

### Docs

- Unify `crash.log` path references across README, architecture docs, and
  log viewer UI (all reference `DataStorage:getDataDir()`).
- Add explicit per-platform plugin install paths to README (Android/Kobo/
  Kindle/desktop emulator).
- Update architecture docs for single-pass redaction and skip-line
  throttling sections.

## [0.2.0] - 2026-06-22

### Added

- **Custom HTTP header rules** — define arbitrary user-defined HTTP
  headers (e.g. `Authorization`, `X-Api-Key`) with per-rule hostname
  scoping, secret masking, and enable/disable toggles. Enables use cases
  beyond Cloudflare Access: Authelia, Authentik, Google IAP, Tailscale
  Funnel, static API keys, and more.
- Schema v2 migration: idempotent, non-destructive upgrade from v0.1.0
  settings. Adds `custom_headers = {}` if missing.
- Typed config accessors with deep-copy semantics: `getCustomHeaders`,
  `setCustomHeaders`, `addCustomHeader`, `updateCustomHeader`,
  `removeCustomHeader`, `getCustomHeader`, `setCustomHeaderEnabled`.
- `lib/header_rules.lua`: pure helpers for rule validation (RFC 7230
  token grammar, CRLF injection prevention, length caps), domain
  matching (`effective_domains`, `applies`), and value masking
  (`mask_preview`, `redact_for_log`).
- Header injection order: caller-supplied > CF Access > custom rules.
  Later custom rules with the same name overwrite earlier ones, but
  never overwrite caller or CF Access headers.
- Per-rule domain scoping: empty per-rule domains inherit the global
  allowlist. Empty per-rule + empty global = match everything (with
  warning).
- Separate one-time warning for custom rules with no effective allowlist
  (`warned_empty_allowlist_custom` ack flag, independent from CF Access
  warning).
- In-app UI for custom header rules: list view with per-rule submenu
  (Edit, Enabled toggle, Secret toggle, Delete), multi-field edit dialog
  with validation.
- Test connection now shows which headers were injected (names only,
  never values), grouped by source (CF Access / custom).
- `docs/custom-headers.md`: detailed setup guide with use case examples.
- Redaction sanity tests verifying header values never leak into logs.

### Changed

- Hooks refactored: shared `apply_headers()` code path for table-form
  and promoted string-form requests. Custom headers applied after CF
  Access injection.
- About dialog updated to v0.2.0 with broader description.
- README, SECURITY.md, and architecture docs updated to cover custom
  header rules.

## [0.1.0] - 2026-06-22

### Added

- Cloudflare Access service-token header injection (`CF-Access-Client-Id`,
  `CF-Access-Client-Secret`) into outgoing HTTP/HTTPS requests via
  `socket.http` and `ssl.https` monkey-patching.
- Hostname allowlist with exact-match and subdomain matching
  (`example.com` matches `*.example.com`). Case-insensitive, trailing-dot
  normalization.
- Empty-allowlist global mode (discouraged) with one-time warning dialog
  and persistent ⚠ menu marker.
- In-app configuration UI: enable/disable toggle, credential editors
  (Client ID with masked preview, Client Secret with password input),
  allowlist domain editor (add/remove with validation), log level
  selector (Off/Warn/Info/Debug).
- Test connection diagnostic: probes a URL and shows HTTP status, cf-ray,
  redirect location, and contextual hints.
- In-app log viewer with ring buffer (200 entries, volatile), redaction
  of secret-like strings, and buttons for Refresh, Clear, Copy, and
  showing the log file path.
- Leveled logging facade over KOReader's logger with `[CFAccess]` prefix,
  lazy formatting, and defense-in-depth redaction.
- Live configuration: enable/disable, credential edits, allowlist changes,
  and log level take effect immediately without restart.
- MIT license, README, CONTRIBUTING guide, architecture docs, and
  SECURITY.md with threat model.

[Unreleased]: https://github.com/WojtekHenszke/CloudflareAccess.koplugin/compare/v0.3.1...HEAD
[0.3.1]: https://github.com/WojtekHenszke/CloudflareAccess.koplugin/releases/tag/v0.3.1
[0.3.0]: https://github.com/WojtekHenszke/CloudflareAccess.koplugin/compare/v0.3.0...v0.3.1
[0.2.0]: https://github.com/WojtekHenszke/CloudflareAccess.koplugin/compare/v0.2.0...v0.3.0
[0.1.0]: https://github.com/WojtekHenszke/CloudflareAccess.koplugin/releases/tag/v0.1.0
