-- SPDX-License-Identifier: MIT
--[[-- Monkey-patch `socket.http` and `ssl.https` to inject CF Access headers
and user-defined custom headers.

Installs wrappers around `socket.http.request` and `ssl.https.request` that
inject `CF-Access-Client-Id` / `CF-Access-Client-Secret` headers for
allowlisted hosts, followed by any user-defined custom header rules.

The wrappers read configuration on every call so that toggling enable/disable,
editing credentials, changing the allowlist, or editing custom rules takes
effect immediately without a restart.

When disabled or credentials are empty, the CF Access wrappers are a perfect
no-op. Custom header rules are evaluated independently.

@module koplugin.cloudflareaccess.hooks
--]]

local log = require("lib.log")
local url_match = require("lib.url_match")
local header_rules = require("lib.header_rules")

local M = {}

local installed = false
local orig_http_request
local orig_https_request

--- Check whether a header is already present (case-insensitive).
-- @tparam table headers the request headers table
-- @string name the header name to check
-- @treturn boolean true if the header is already set
local function has_header(headers, name)
    if type(headers) ~= "table" then
        return false
    end
    local name_lower = name:lower()
    for k, _ in pairs(headers) do
        if type(k) == "string" and k:lower() == name_lower then
            return true
        end
    end
    return false
end

--- Inject CF Access headers into a table-form request if needed.
-- Never overwrites headers the caller already set.
local function inject_cf_headers(req, client_id, client_secret)
    req.headers = req.headers or {}
    if not has_header(req.headers, "CF-Access-Client-Id") then
        req.headers["CF-Access-Client-Id"] = client_id
    end
    if not has_header(req.headers, "CF-Access-Client-Secret") then
        req.headers["CF-Access-Client-Secret"] = client_secret
    end
end

--- Inject custom header rules into a table-form request.
-- Applied after CF Access. Caller-supplied and CF Access headers are never
-- overwritten. Later rules with the same name overwrite earlier ones.
-- @tparam table req the request table (mutated)
-- @tparam table custom_headers array of rule tables
-- @string host the request hostname
-- @tparam table global_domains the global CF Access allowlist
local function inject_custom_headers(req, custom_headers, host, global_domains)
    if type(custom_headers) ~= "table" then return 0 end
    req.headers = req.headers or {}
    -- Track header names set by custom rules (so later rules can overwrite
    -- earlier ones, but never caller or CF Access headers)
    local custom_set = {}
    local applied_count = 0
    for _, rule in ipairs(custom_headers) do
        if rule.enabled and header_rules.applies(rule, host, global_domains) then
            if has_header(req.headers, rule.name) and not custom_set[rule.name:lower()] then
                -- Header was set by caller or CF Access — do not overwrite
                log.dbg("suppressed rule %q (caller or CF Access already set) for host=%s",
                    rule.name, host)
            else
                if custom_set[rule.name:lower()] then
                    log.dbg("suppressed earlier rule %q (overwritten by later rule) for host=%s",
                        rule.name, host)
                end
                req.headers[rule.name] = rule.value
                custom_set[rule.name:lower()] = true
                applied_count = applied_count + 1
                log.dbg("applied rule %q for host=%s", rule.name, host)
            end
        end
    end
    return applied_count
end

--- Log the response status and cf-ray if present.
local function log_response(host, path, code, headers)
    local cf_ray = type(headers) == "table" and headers["cf-ray"]
        or type(headers) == "table" and headers["CF-Ray"]
    if cf_ray then
        log.dbg("host=%s path=%s status=%s cf-ray=%s", host, path, code, cf_ray)
    else
        log.dbg("host=%s path=%s status=%s", host, path, code)
    end
end

--- Extract path from a URL string.
local function get_path(url)
    local parsed = require("socket.url").parse(url or "")
    if parsed and parsed.path and parsed.path ~= "" then
        return parsed.path
    end
    return "/"
end

--- Apply all header injections (CF Access + custom) to a table-form request.
-- This is the shared code path for both table-form and promoted string-form.
-- @tparam table|nil skip_cache table with host and count fields (resets on inject)
local function apply_headers(req, config, host, skip_cache)
    local domains = config.domains or {}

    -- 1. CF Access headers (if enabled and host matches)
    local cf_injected = false
    if config.enabled
       and config.client_id and config.client_id ~= ""
       and config.client_secret and config.client_secret ~= ""
       and url_match.is_allowed(host, domains) then
        inject_cf_headers(req, config.client_id, config.client_secret)
        log.dbg("injected CF Access for host=%s path=%s", host, get_path(req.url))
        cf_injected = true
    end

    -- 2. Custom header rules (applied after CF Access)
    local custom_count = inject_custom_headers(req, config.custom_headers, host, domains)

    if cf_injected or custom_count > 0 then
        log.dbg("applied: host=%s cf=%s custom=%d", host, cf_injected and "yes" or "no", custom_count)
        if skip_cache then
            skip_cache.host = nil
            skip_cache.count = 0
        end
    end
end

--- Create a wrapper around an original request function.
-- @func orig the original `socket.http.request` or `ssl.https.request`
-- @func get_config closure returning the current config table
local function wrap(orig, get_config)
    local skip_cache = { host = nil, count = 0 }
    return function(req, body)
        local config = get_config()
        local host

        if type(req) == "table" then
            host = url_match.get_host(req.url)
            apply_headers(req, config, host, skip_cache)
            local ok, code, headers, status = orig(req, body)
            log_response(host, get_path(req.url), code, headers)
            return ok, code, headers, status
        elseif type(req) == "string" then
            host = url_match.get_host(req)
            local domains = config.domains or {}

            -- Check if any injection would apply
            local cf_would_apply = config.enabled
                and config.client_id and config.client_id ~= ""
                and config.client_secret and config.client_secret ~= ""
                and url_match.is_allowed(host, domains)
            local custom_would_apply = false
            if type(config.custom_headers) == "table" then
                for _, rule in ipairs(config.custom_headers) do
                    if rule.enabled and header_rules.applies(rule, host, domains) then
                        custom_would_apply = true
                        break
                    end
                end
            end

            if cf_would_apply or custom_would_apply then
                -- Promote string form to table form so we can attach headers
                local ltn12 = require("ltn12")
                local sink_t = {}
                local t = {
                    url = req,
                    sink = ltn12.sink.table(sink_t),
                    headers = {},
                }
                if body then
                    t.method = "POST"
                    t.source = ltn12.source.string(body)
                    t.headers["Content-Length"] = tostring(#body)
                    if not t.headers["Content-Type"] then
                        t.headers["Content-Type"] = "application/x-www-form-urlencoded"
                    end
                end
                apply_headers(t, config, host, skip_cache)
                log.dbg("injected (string form) for host=%s path=%s", host, get_path(req))
                local ok, code, headers, status = orig(t)
                log_response(host, get_path(req), code, headers)
                if ok == nil then
                    return nil, code, headers, status
                end
                return table.concat(sink_t), code, headers, status
            else
                if host == skip_cache.host then
                    skip_cache.count = skip_cache.count + 1
                else
                    if skip_cache.count > 0 then
                        log.dbg("skip host=%s (suppressed %d times)", skip_cache.host, skip_cache.count)
                        skip_cache.count = 0
                    end
                    skip_cache.host = host
                    log.dbg("skip host=%s (not in allowlist)", host or "(no host)")
                end
                return orig(req, body)
            end
        end
        return orig(req, body)
    end
end

--- Install the HTTP/HTTPS hooks.
-- @func get_config closure returning the current config table with fields:
--   enabled (bool), client_id (string), client_secret (string),
--   domains (table), custom_headers (table)
function M.install(get_config)
    if installed then
        return
    end

    local http_module = package.loaded["socket.http"] or require("socket.http")
    local https_module = package.loaded["ssl.https"] or require("ssl.https")

    orig_http_request = http_module.request
    orig_https_request = https_module.request

    http_module.request = wrap(orig_http_request, get_config)
    https_module.request = wrap(orig_https_request, get_config)

    installed = true
    log.info("hooks installed")

    -- One-time warning if enabled with an empty allowlist
    local config = get_config()
    if config.enabled and #config.domains == 0 then
        log.warn("hooks installed with empty allowlist — headers will be sent to every host")
    end
end

--- Check whether hooks are currently installed.
-- @treturn boolean
function M.is_installed()
    return installed
end

--- Reset installed state (test-only).
function M._reset_for_test()
    installed = false
    orig_http_request = nil
    orig_https_request = nil
end

return M
