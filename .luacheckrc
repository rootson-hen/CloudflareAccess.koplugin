-- luacheck configuration for CloudflareAccess.koplugin
-- Adapted from KOReader's .luacheckrc (koreader/.luacheckrc)

std = "luajit"

-- Don't warn on unused implicit self or function arguments
self = false
unused_args = false

-- Enforce a 120-column soft limit (per project conventions, §6)
max_line_length = 120

-- KOReader runtime globals available to plugins (read-only)
read_globals = {
    "G_reader_settings",
    "G_defaults",
}

-- LuaJIT provides these but luacheck's luajit std may not list them
globals = {
    "table.pack",
    "table.unpack",
}

-- Exclude the KOReader submodule and any vendored libraries
exclude_files = {
    "koreader/",
    ".lua/",
    ".luarocks/",
}

-- Allow underscore-prefixed throwaway locals
ignore = {
    "211/__*", -- unused variable starting with __
    "231/__",  -- unused implicit self named _
}

-- busted test framework globals in spec files
files["spec/"].std = "+busted"
