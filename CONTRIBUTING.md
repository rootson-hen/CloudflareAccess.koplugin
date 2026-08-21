# Contributing to Cloudflare Access

Thanks for your interest in contributing! This plugin is developed against the
[KOReader](https://github.com/koreader/koreader) frontend APIs.

## Getting the code

This repository includes the KOReader source as a **git submodule** (under
`koreader/`) for LSP autocompletion and code reference only. The submodule is
**not** required at runtime — the plugin works without it on a device.

### Clone with submodules

```sh
git clone --recurse-submodules https://github.com/rootson-hen/CloudflareAccess.koplugin.git
```

If you already cloned without `--recurse-submodules`, initialise the submodule
afterwards:

```sh
git submodule update --init --recursive
```

> **Note:** The submodule is pinned to a specific stable KOReader release tag
> (`v2026.03`). You normally do not need to change it.

## Editor setup

A `.luarc.json` is included for
[lua-language-server](https://github.com/LuaLS/lua-language-server) (LuaLS). It
points the LSP at `koreader/frontend/` so `require()` calls resolve to real
KOReader modules, and tells the server not to diagnose the submodule's own
files.

## Prerequisites

Install [LuaRocks](https://luarocks.org/) and the dev tools. KOReader runs on
**LuaJIT** (Lua 5.1 compatible), so the linter and test runner must be installed
against LuaJIT — not Lua 5.5+, which is incompatible with `luacheck`.

```sh
# macOS (Homebrew)
brew install luajit luarocks
luarocks --lua-dir="$(brew --prefix luajit)" install luacheck
luarocks --lua-dir="$(brew --prefix luajit)" install busted
```

Verify the install (Lua should report **LuaJIT**, not Lua 5.5):

```sh
luacheck --version   # Lua: LuaJIT 2.1…
busted --version     # 2.3.0
```

## Linting

The project ships a `.luacheckrc` adapted from KOReader's own config
(`std = "luajit"`, `max_line_length = 120`). Run:

```sh
luacheck .
```

All commits must pass with zero warnings.

## Testing

Pure-Lua modules (e.g. `lib/url_match.lua`) have unit tests using
[busted](https://lunarmodules.github.io/busted/):

```sh
busted spec/
```

## Testing on the KOReader emulator

KOReader includes a `kodev` build tool that can run a desktop emulator. See the
[KOReader README](https://github.com/koreader/koreader#building-prerequisites)
for build prerequisites and platform instructions.

To test this plugin in the emulator, copy the plugin files into the submodule's
`plugins/` directory, then build and run:

```sh
mkdir -p koreader/plugins/CloudflareAccess.koplugin
cp -r *.lua ui lib koreader/plugins/CloudflareAccess.koplugin/
cd koreader && ./kodev build && ./kodev run
```

## Optional: kopl CLI

[`kopl`](https://github.com/consoleaf/kopl) is a community Go-based tool that
can scaffold koplugins and run static checks. It is **not** required — the
`luacheck` + `busted` setup above is sufficient — but some may find it useful.

## Maintenance and operating model

- **Repository Owner:** [`rootson-hen`](https://github.com/rootson-hen) retains ownership, release signing authority, and final project governance.
- **Development & Maintenance Agent:** [`alfred-rootson`](https://github.com/alfred-rootson) performs routine implementation, dependency checks, automated testing, and maintenance pull requests.
