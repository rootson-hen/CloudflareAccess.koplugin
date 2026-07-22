-- Integration tests for hooks.lua custom header injection.
-- Uses a mocked socket.http to verify header injection behavior.

-- Mock socket.http that captures the request and returns a canned response
local captured_requests
local mock_http

local function setup_mock()
    captured_requests = {}
    mock_http = {
        request = function(req, body)
            if type(req) == "table" then
                table.insert(captured_requests, {
                    url = req.url,
                    headers = req.headers or {},
                    method = req.method,
                })
            else
                table.insert(captured_requests, {
                    url = req,
                    headers = {},
                    string_form = true,
                })
            end
            return 1, 200, { ["cf-ray"] = "test-ray-123" }, "HTTP/1.1 200 OK"
        end,
    }
    package.loaded["socket.http"] = mock_http
    package.loaded["ssl.https"] = mock_http
end

local function teardown_mock()
    package.loaded["socket.http"] = nil
    package.loaded["ssl.https"] = nil
end

-- Helper: make a valid rule
local function make_rule(overrides)
    return {
        name = overrides.name or "X-Test-Header",
        value = overrides.value or "test-value",
        domains = overrides.domains or {},
        enabled = overrides.enabled == nil and true or overrides.enabled,
        secret = overrides.secret == nil and true or overrides.secret,
    }
end

describe("hooks custom headers integration", function()
    local hooks

    before_each(function()
        setup_mock()
        -- Force re-require hooks so it picks up the mock
        package.loaded["hooks"] = nil
        hooks = require("hooks")
        hooks._reset_for_test()
    end)

    after_each(function()
        teardown_mock()
    end)

    describe("table form", function()
        it("injects custom headers for matching host", function()
            hooks.install(function()
                return {
                    enabled = false,
                    client_id = "",
                    client_secret = "",
                    domains = { "example.com" },
                    custom_headers = {
                        make_rule({ name = "X-Custom", value = "custom-val", domains = { "example.com" } }),
                    },
                }
            end)

            mock_http.request({ url = "https://example.com/path" })
            assert.equals("custom-val", captured_requests[1].headers["X-Custom"])
        end)

        it("does not inject custom headers for non-matching host", function()
            hooks.install(function()
                return {
                    enabled = false,
                    client_id = "",
                    client_secret = "",
                    domains = {},
                    custom_headers = {
                        make_rule({ name = "X-Custom", value = "custom-val", domains = { "example.com" } }),
                    },
                }
            end)

            mock_http.request({ url = "https://other.com/path" })
            assert.is_nil(captured_requests[1].headers["X-Custom"])
        end)

        it("skips disabled rules", function()
            hooks.install(function()
                return {
                    enabled = false,
                    client_id = "",
                    client_secret = "",
                    domains = {},
                    custom_headers = {
                        make_rule({ name = "X-Disabled", value = "val", enabled = false, domains = { "example.com" } }),
                    },
                }
            end)

            mock_http.request({ url = "https://example.com/path" })
            assert.is_nil(captured_requests[1].headers["X-Disabled"])
        end)

        it("applies CF Access headers AND custom headers together", function()
            hooks.install(function()
                return {
                    enabled = true,
                    client_id = "<client-id>",
                    client_secret = "<client-secret>",
                    domains = { "example.com" },
                    custom_headers = {
                        make_rule({ name = "X-Custom", value = "custom-val", domains = {} }),
                    },
                }
            end)

            mock_http.request({ url = "https://example.com/path" })
            assert.equals("<client-id>", captured_requests[1].headers["CF-Access-Client-Id"])
            assert.equals("<client-secret>", captured_requests[1].headers["CF-Access-Client-Secret"])
            assert.equals("custom-val", captured_requests[1].headers["X-Custom"])
        end)

        it("does not overwrite caller-supplied headers", function()
            hooks.install(function()
                return {
                    enabled = true,
                    client_id = "<client-id>",
                    client_secret = "<client-secret>",
                    domains = { "example.com" },
                    custom_headers = {
                        make_rule({ name = "X-Custom", value = "injected", domains = {} }),
                    },
                }
            end)

            mock_http.request({
                url = "https://example.com/path",
                headers = { ["X-Custom"] = "caller-value" },
            })
            assert.equals("caller-value", captured_requests[1].headers["X-Custom"])
        end)

        it("later custom rule overwrites earlier one with same name", function()
            hooks.install(function()
                return {
                    enabled = false,
                    client_id = "",
                    client_secret = "",
                    domains = {},
                    custom_headers = {
                        make_rule({ name = "X-Dup", value = "first", domains = {} }),
                        make_rule({ name = "X-Dup", value = "second", domains = {} }),
                    },
                }
            end)

            mock_http.request({ url = "https://example.com/path" })
            assert.equals("second", captured_requests[1].headers["X-Dup"])
        end)

        it("custom rule with empty domains inherits global allowlist", function()
            hooks.install(function()
                return {
                    enabled = false,
                    client_id = "",
                    client_secret = "",
                    domains = { "example.com" },
                    custom_headers = {
                        make_rule({ name = "X-Inherited", value = "val", domains = {} }),
                    },
                }
            end)

            mock_http.request({ url = "https://example.com/path" })
            assert.equals("val", captured_requests[1].headers["X-Inherited"])

            mock_http.request({ url = "https://other.com/path" })
            assert.is_nil(captured_requests[2].headers["X-Inherited"])
        end)

        it("custom rule with empty domains + empty global matches everything", function()
            hooks.install(function()
                return {
                    enabled = false,
                    client_id = "",
                    client_secret = "",
                    domains = {},
                    custom_headers = {
                        make_rule({ name = "X-Global", value = "val", domains = {} }),
                    },
                }
            end)

            mock_http.request({ url = "https://anything.com/path" })
            assert.equals("val", captured_requests[1].headers["X-Global"])
        end)
    end)

    describe("string form", function()
        it("promotes string form and injects custom headers", function()
            hooks.install(function()
                return {
                    enabled = false,
                    client_id = "",
                    client_secret = "",
                    domains = {},
                    custom_headers = {
                        make_rule({ name = "X-Custom", value = "custom-val", domains = {} }),
                    },
                }
            end)

            local _body, code = mock_http.request("https://example.com/path")
            assert.equals(200, code)
            assert.truthy(_body)
        end)

        it("passes through unchanged when no rules apply", function()
            hooks.install(function()
                return {
                    enabled = false,
                    client_id = "",
                    client_secret = "",
                    domains = {},
                    custom_headers = {
                        make_rule({ name = "X-Custom", value = "val", domains = { "example.com" } }),
                    },
                }
            end)

            local _, code = mock_http.request("https://other.com/path")
            assert.equals(200, code)
            -- String form passed through directly, no promotion
            assert.is_true(captured_requests[1].string_form)
        end)
    end)

    describe("no-op when disabled", function()
        it("passes through when CF disabled and no custom headers", function()
            hooks.install(function()
                return {
                    enabled = false,
                    client_id = "",
                    client_secret = "",
                    domains = {},
                    custom_headers = {},
                }
            end)

            mock_http.request({ url = "https://example.com/path" })
            assert.same({}, captured_requests[1].headers)
        end)
    end)

    describe("redaction sanity", function()
        local log

        before_each(function()
            log = require("lib.log")
            log.setLevel("dbg")
            log.clear()
        end)

        it("never logs custom header values", function()
            local secret_value = "super-secret-token-value-12345"
            hooks.install(function()
                return {
                    enabled = false,
                    client_id = "",
                    client_secret = "",
                    domains = {},
                    custom_headers = {
                        make_rule({ name = "X-Secret", value = secret_value, domains = {} }),
                    },
                }
            end)

            mock_http.request({ url = "https://example.com/path" })

            -- Check all log entries — the secret value must not appear
            local entries = log.getEntries()
            for _, entry in ipairs(entries) do
                assert.is_nil(entry.message:find(secret_value, 1, true),
                    "Header value leaked into log: " .. entry.message)
            end
        end)

        it("never logs CF Access credentials", function()
            local client_secret = "abcdef0123456789abcdef0123456789"
            hooks.install(function()
                return {
                    enabled = true,
                    client_id = "abcdef0123456789abcdef0123456789",
                    client_secret = client_secret,
                    domains = { "example.com" },
                    custom_headers = {},
                }
            end)

            mock_http.request({ url = "https://example.com/path" })

            local entries = log.getEntries()
            for _, entry in ipairs(entries) do
                assert.is_nil(entry.message:find(client_secret, 1, true),
                    "Client secret leaked into log: " .. entry.message)
            end
        end)

        it("logs rule names but not values", function()
            hooks.install(function()
                return {
                    enabled = false,
                    client_id = "",
                    client_secret = "",
                    domains = {},
                    custom_headers = {
                        make_rule({ name = "X-Logged-Name", value = "secret-value", domains = {} }),
                    },
                }
            end)

            mock_http.request({ url = "https://example.com/path" })

            local entries = log.getEntries()
            local found_name = false
            for _, entry in ipairs(entries) do
                if entry.message:find("X-Logged-Name", 1, true) then
                    found_name = true
                end
                assert.is_nil(entry.message:find("secret-value", 1, true),
                    "Value leaked into log: " .. entry.message)
            end
            assert.is_true(found_name, "Rule name was not logged")
        end)
    end)

    describe("summary log", function()
        local log

        before_each(function()
            log = require("lib.log")
            log.setLevel("dbg")
            log.clear()
            -- Force re-require hooks to get fresh apply_headers closure
            package.loaded["hooks"] = nil
            hooks = require("hooks")
            hooks._reset_for_test()
        end)

        it("emits summary line when CF headers injected", function()
            hooks.install(function()
                return {
                    enabled = true,
                    client_id = "cf-id",
                    client_secret = "cf-secret",
                    domains = { "example.com" },
                    custom_headers = {},
                }
            end)

            mock_http.request({ url = "https://example.com/path" })

            local entries = log.getEntries()
            local found = false
            for _, entry in ipairs(entries) do
                if entry.message:find("^applied:") then
                    found = true
                    assert.truthy(entry.message:find("cf=yes", 1, true))
                    assert.truthy(entry.message:find("custom=0", 1, true))
                end
            end
            assert.is_true(found, "Summary log line not emitted")
        end)

        it("emits summary line when custom headers injected", function()
            hooks.install(function()
                return {
                    enabled = false,
                    client_id = "",
                    client_secret = "",
                    domains = {},
                    custom_headers = {
                        make_rule({ name = "X-Custom", value = "val", domains = {} }),
                    },
                }
            end)

            mock_http.request({ url = "https://example.com/path" })

            local entries = log.getEntries()
            local found = false
            for _, entry in ipairs(entries) do
                if entry.message:find("^applied:") then
                    found = true
                    assert.truthy(entry.message:find("cf=no", 1, true))
                    assert.truthy(entry.message:find("custom=1", 1, true))
                end
            end
            assert.is_true(found, "Summary log line not emitted")
        end)

        it("suppresses summary line on no-op passthrough", function()
            hooks.install(function()
                return {
                    enabled = false,
                    client_id = "",
                    client_secret = "",
                    domains = {},
                    custom_headers = {},
                }
            end)

            mock_http.request({ url = "https://example.com/path" })

            local entries = log.getEntries()
            for _, entry in ipairs(entries) do
                assert.is_nil(entry.message:find("^applied:"),
                    "Summary line emitted on no-op: " .. entry.message)
            end
        end)
    end)

    describe("case-insensitive caller collision", function()
        local log

        before_each(function()
            log = require("lib.log")
            log.setLevel("dbg")
            log.clear()
        end)

        it("respects caller header when rule has different case name", function()
            hooks.install(function()
                return {
                    enabled = false,
                    client_id = "",
                    client_secret = "",
                    domains = {},
                    custom_headers = {
                        make_rule({ name = "X-Custom", value = "injected", domains = {} }),
                    },
                }
            end)

            mock_http.request({
                url = "https://example.com/path",
                headers = { ["x-custom"] = "caller" },
            })
            assert.equals("caller", captured_requests[1].headers["x-custom"])

            local found = false
            for _, entry in ipairs(log.getEntries()) do
                if entry.message:find("suppressed rule") then
                    found = true
                end
            end
            assert.is_true(found, "suppressed rule log line not emitted")
        end)

        it("respects caller header when caller has mixed case and rule is lowercased", function()
            hooks.install(function()
                return {
                    enabled = false,
                    client_id = "",
                    client_secret = "",
                    domains = {},
                    custom_headers = {
                        make_rule({ name = "x-custom", value = "injected", domains = {} }),
                    },
                }
            end)

            mock_http.request({
                url = "https://example.com/path",
                headers = { ["X-Custom"] = "caller" },
            })
            -- Caller's mixed-case key is preserved untouched
            assert.equals("caller", captured_requests[1].headers["X-Custom"])
            -- No duplicate injected under any casing variant
            assert.is_nil(captured_requests[1].headers["x-custom"],
                "Rule injected duplicate header under lowercased key")
            assert.is_nil(captured_requests[1].headers["X-CUSTOM"],
                "Rule injected duplicate header under uppercased key")

            local found = false
            for _, entry in ipairs(log.getEntries()) do
                if entry.message:find("suppressed rule") then
                    found = true
                end
            end
            assert.is_true(found, "suppressed rule log line not emitted")
        end)

        it("respects caller UPPERCASE header when rule is lowercased", function()
            hooks.install(function()
                return {
                    enabled = false,
                    client_id = "",
                    client_secret = "",
                    domains = {},
                    custom_headers = {
                        make_rule({ name = "x-custom", value = "injected", domains = {} }),
                    },
                }
            end)

            mock_http.request({
                url = "https://example.com/path",
                headers = { ["X-CUSTOM"] = "caller" },
            })
            assert.equals("caller", captured_requests[1].headers["X-CUSTOM"])
            assert.is_nil(captured_requests[1].headers["x-custom"],
                "Rule injected duplicate under lowercased key")
            assert.is_nil(captured_requests[1].headers["X-Custom"],
                "Rule injected duplicate under mixed-case key")
        end)

        it("injects normally when no caller header exists", function()
            hooks.install(function()
                return {
                    enabled = false,
                    client_id = "",
                    client_secret = "",
                    domains = {},
                    custom_headers = {
                        make_rule({ name = "X-Custom", value = "injected", domains = {} }),
                    },
                }
            end)

            mock_http.request({
                url = "https://example.com/path",
                headers = {},
            })
            assert.equals("injected", captured_requests[1].headers["X-Custom"])
        end)
    end)

    describe("CF Access not matching, custom rule matching", function()
        local log

        before_each(function()
            log = require("lib.log")
            log.setLevel("dbg")
            log.clear()
            package.loaded["hooks"] = nil
            hooks = require("hooks")
            hooks._reset_for_test()
        end)

        it("injects only custom header when CF domains do not match", function()
            hooks.install(function()
                return {
                    enabled = true,
                    client_id = "cf-client-id",
                    client_secret = "cf-client-secret",
                    domains = { "auth.example.com" },
                    custom_headers = {
                        make_rule({ name = "X-Media", value = "media-val", domains = { "media.example.com" } }),
                    },
                }
            end)

            mock_http.request({ url = "https://media.example.com/path" })
            assert.is_nil(captured_requests[1].headers["CF-Access-Client-Id"])
            assert.is_nil(captured_requests[1].headers["CF-Access-Client-Secret"])
            assert.equals("media-val", captured_requests[1].headers["X-Media"])

            local found = false
            for _, entry in ipairs(log.getEntries()) do
                if entry.message:find("^applied:") then
                    found = true
                    assert.truthy(entry.message:find("cf=no", 1, true))
                    assert.truthy(entry.message:find("custom=1", 1, true))
                end
            end
            assert.is_true(found, "Summary log line not emitted")
        end)
    end)

    describe("custom header with secret=false", function()
        local log

        before_each(function()
            log = require("lib.log")
            log.setLevel("dbg")
            log.clear()
            package.loaded["hooks"] = nil
            hooks = require("hooks")
            hooks._reset_for_test()
        end)

        it("logs the rule name but not the value", function()
            hooks.install(function()
                return {
                    enabled = false,
                    client_id = "",
                    client_secret = "",
                    domains = {},
                    custom_headers = {
                        make_rule({ name = "X-NonSecret", value = "visible-value", secret = false, domains = {} }),
                    },
                }
            end)

            mock_http.request({ url = "https://example.com/path" })

            local entries = log.getEntries()
            local found_name = false
            for _, entry in ipairs(entries) do
                if entry.message:find("X-NonSecret", 1, true) then
                    found_name = true
                end
                assert.is_nil(entry.message:find("visible-value", 1, true),
                    "Non-secret value leaked into log: " .. entry.message)
            end
            assert.is_true(found_name, "Rule name was not logged")
        end)
    end)

    describe("status preservation", function()
        it("preserves the 4th return value through injection", function()
            hooks.install(function()
                return {
                    enabled = false,
                    client_id = "",
                    client_secret = "",
                    domains = {},
                    custom_headers = {
                        make_rule({ name = "X-Status", value = "val", domains = {} }),
                    },
                }
            end)

            local ok, code, headers, status = mock_http.request({ url = "https://example.com/path" })
            assert.equals(1, ok)
            assert.equals(200, code)
            assert.same({ ["cf-ray"] = "test-ray-123" }, headers)
            assert.equals("HTTP/1.1 200 OK", status)
        end)
    end)

    describe("empty allowlist install warning", function()
        local log

        before_each(function()
            log = require("lib.log")
            log.setLevel("warn")
            log.clear()
            package.loaded["hooks"] = nil
            hooks = require("hooks")
            hooks._reset_for_test()
        end)

        it("warns when installed with enabled and empty allowlist", function()
            hooks.install(function()
                return {
                    enabled = true,
                    client_id = "cf-id",
                    client_secret = "cf-secret",
                    domains = {},
                    custom_headers = {},
                }
            end)

            local entries = log.getEntries()
            local found = false
            for _, entry in ipairs(entries) do
                if entry.level == "warn" and entry.message:find("empty allowlist", 1, true) then
                    found = true
                end
            end
            assert.is_true(found, "Empty allowlist warning not emitted")
        end)
    end)
end)
