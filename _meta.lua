local _ = require("gettext")
return {
    name = "cloudflareaccess",
    fullname = _("Cloudflare Access"),
    description = _([[
Injects Cloudflare Access service-token headers and user-defined custom
HTTP headers into outgoing HTTP/HTTPS requests, optionally restricted to
a hostname allowlist.]]),
    version = "0.3.1",
}
