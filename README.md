[![CI](https://github.com/rootson-hen/CloudflareAccess.koplugin/actions/workflows/ci.yml/badge.svg)](https://github.com/rootson-hen/CloudflareAccess.koplugin/actions/workflows/ci.yml)

# Cloudflare Access

A KOReader plugin that injects [Cloudflare Access](https://developers.cloudflare.com/cloudflare-one/identity/service-tokens/) service-token headers (`CF-Access-Client-Id`, `CF-Access-Client-Secret`) and user-defined custom HTTP headers into outgoing HTTP/HTTPS requests, with a configurable hostname allowlist and an in-app log viewer for troubleshooting.

> **Despite the name**, this plugin also supports arbitrary custom HTTP headers — not just Cloudflare Access. See [Custom header rules](#custom-header-rules) below.

## What it does

If you self-host services behind Cloudflare Access (e.g. Calibre-Web, an OPDS catalog, a wiki) and use KOReader to browse or download from them, KOReader's requests will be blocked by Cloudflare unless the correct service-token headers are present. This plugin injects those headers automatically — no need to edit `.lua` files on your device.

## Why

The original solution was a [user patch](https://github.com/crocodilestick/koreader-cloudflare-auth-patch) that injected the headers globally into every HTTP request. That works, but it risks leaking your service token to third-party hosts (GitHub auto-updater, news feeds, dictionary lookups, etc.). This plugin replaces the patch with a proper, configurable KOReader plugin that supports a hostname allowlist.

## Installation

KOReader's data directory (where `crash.log` lives) varies by platform. Install by downloading the release ZIP, extracting the `CloudflareAccess.koplugin/` directory, and placing it into the `plugins/` folder for your platform:

- **Android (incl. Onyx Boox):** `/sdcard/koreader/plugins/` (or wherever KOReader was installed)
- **Kobo:** `.adds/koreader/plugins/` (note `.adds` is hidden — enable show hidden files on your computer)
- **Kindle:** `koreader/plugins/` within whichever extension root KOReader was installed to
- **Desktop emulator:** `koreader/plugins/` next to the emulator binary

Restart KOReader — the plugin appears in the main menu under the gear icon.

On GitHub, this repository is tagged with the topic `koreader-plugin` for discoverability by community indexers and the KOReader AppStore plugin.

## Configuration

All configuration is done from KOReader's UI — no SSH, no editing `.lua` files.

Open **Settings → Network → Cloudflare Access** to:

- **Enable/disable** the plugin.
- **Set Client ID and Client Secret** — paste your Cloudflare Access service-token credentials.
- **Manage allowed domains** — add or remove hostnames that should receive the headers.
- **Custom header rules** — define arbitrary HTTP headers (e.g. `Authorization`, `X-Api-Key`) with per-rule domain scoping and secret masking. See [Custom header rules](#custom-header-rules) below.
- **Set the log level** — Off / Warn / Info / Debug.
- **View logs** — inspect recent plugin activity in-app.
- **Test connection** — probe a URL and see the HTTP status, cf-ray, and redirect info.
- **About** — version info.

Settings are stored in `koreader/settings/cloudflareaccess.lua` on your device.

### Operating modes

| Mode | Allowlist | Behavior | Recommended? |
|------|-----------|----------|--------------|
| **Allowlist** (recommended) | ≥ 1 domain | Headers injected only for matching hosts | ✅ Yes |
| **Global** (fallback) | Empty | Headers injected for every host | ⚠ Discouraged |

**Allowlist mode** (recommended): Add the apex domains of your Cloudflare-protected services. A domain like `example.com` matches `example.com` and all subdomains (`*.example.com`). Headers are only sent to matching hosts.

**Global mode** (discouraged): If the allowlist is empty, the plugin injects headers into every outgoing request — matching the original patch's behavior. This is convenient for quick setup but risks leaking your service token to third-party hosts. A one-time warning is shown when this mode is active, and a ⚠ marker appears in the menu.

## Custom header rules

In addition to Cloudflare Access service tokens, the plugin supports **user-defined custom HTTP header rules**. Each rule specifies:

- **Header name** — any valid HTTP header name (RFC 7230 token, e.g. `X-Api-Key`, `Authorization`).
- **Header value** — the string value to inject.
- **Domains** — optional per-rule hostname scoping. If empty, the rule inherits the global allowlist. If both are empty, the rule matches every host (with a warning).
- **Enabled** — toggle the rule on/off without deleting it.
- **Secret** — when `true` (default), the value is masked in the UI (`abcd…wxyz`) and never logged. When `false`, the value is shown in the UI but still never logged.

### Header injection order

When multiple sources define the same header, the first one wins:

1. **Caller-supplied headers** — headers already set by KOReader code are never overwritten.
2. **CF Access credentials** — `CF-Access-Client-Id` / `CF-Access-Client-Secret` (if enabled and host matches).
3. **Custom rules** — applied in order. Later rules with the same name overwrite earlier ones, but never overwrite caller or CF Access headers.

Header names are matched case-insensitively according to HTTP semantics. A caller-supplied `X-Custom` header prevents injection of `x-custom`, `X-CUSTOM`, or any other casing variant.

### Use cases

| Use case | Example header |
|----------|---------------|
| Authelia / Authentik | `Authorization: Basic ...` or custom auth header |
| Google IAP | `X-Goog-Iap-Jwt-Assertion` |
| Tailscale Funnel | `X-Tailscale-Auth` |
| Static API key | `X-Api-Key: your-key` |
| Custom reverse proxy | `X-Proxy-Auth: token` |

See [docs/custom-headers.md](docs/custom-headers.md) for detailed setup examples.

## Security notes

- **Where the secret is stored:** In `koreader/settings/cloudflareaccess.lua` on your device, in plain text. This is the same security level as KOReader's other settings. Protect your device accordingly.
- **How to rotate:** Generate a new service token in the Cloudflare dashboard, then update the Client ID and Client Secret in the plugin's menu.
- **Allowlist semantics:** Matching is case-insensitive. An entry `example.com` matches `example.com` and any subdomain (`sub.example.com`). Sibling domains like `evilexample.com` do **not** match. See [SECURITY.md](SECURITY.md) for the full threat model.

## Troubleshooting

**First step:** Open **Cloudflare Access → View logs** in the KOReader menu. This shows recent plugin activity without needing SSH.

The log level defaults to **Warn**. Switch to **Debug** while reproducing an issue, then switch back to reduce noise.

### Common log lines and their meanings

| Log line | Meaning |
|----------|---------|
| `injected for host=...` | Headers were injected for this host (it matched the allowlist) |
| `skip host=... (not in allowlist)` | The host did not match any allowlist entry; no headers sent |
| `hooks installed with empty allowlist` | The plugin is in global mode — headers go to every host |
| `host=... status=302 cf-ray=...` | The request got a redirect; check if it points to cloudflareaccess.com |

### Common HTTP status patterns

| Status | Meaning |
|--------|---------|
| **200** | Success — CF Access passed and the app served the request |
| **302 → cloudflareaccess.com** | CF Access authentication failed — check your Client ID and Secret |
| **401** | CF Access passed, but the app behind it (e.g. Calibre-Web) requires its own login |
| **403** | CF Access blocked the request — the service token may be expired or misconfigured |

### Finding the full log file

The in-app viewer shows the plugin's ring buffer (volatile, not persisted). For the full KOReader log, the file is at `crash.log` inside the KOReader data directory. The canonical path is resolved at runtime by `DataStorage:getDataDir()`. Common platform-specific paths:

- **Kobo:** `.adds/koreader/crash.log`
- **Kindle:** `linkss/koreader/crash.log` (or wherever KOReader is installed)
- **Android:** `koreader/crash.log`
- **Desktop/emulator:** `koreader/crash.log` (next to the KOReader binary)

Use the **Log file** button in the viewer to see the absolute path on your device.

## Comparison with the upstream patch

| Feature | Upstream patch | This plugin |
|---------|---------------|-------------|
| Installation | Manual `.lua` file edit | Drop-in plugin directory |
| Configuration | Edit code constants | In-app UI |
| Host filtering | Allowlist (hardcoded) | Allowlist (editable at runtime) |
| Empty allowlist | Not applicable | Global mode with warning |
| Custom headers | No | Yes — arbitrary rules with per-rule scoping |
| Logging | `logger.info` only | Leveled ring buffer + in-app viewer |
| Test connection | No | Yes (shows injected header names) |
| Enable/disable | Restart required | Live toggle |

Upstream patch: [crocodilestick/koreader-cloudflare-auth-patch](https://github.com/crocodilestick/koreader-cloudflare-auth-patch)

## License

MIT — see [LICENSE](LICENSE).

## Credits

- [crocodilestick](https://github.com/crocodilestick) for the original Cloudflare Access user patch that this plugin replaces.
- The [KOReader](https://github.com/koreader/koreader) team for the excellent e-reader platform and plugin system.
