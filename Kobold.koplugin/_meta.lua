local _ = require("gettext")

-- Version from kobold/meta.lua, so it is set in one place. _meta.lua is
-- loaded on its own, before the plugin folder is on the module path.
local dir = (debug.getinfo(1, "S").source or ""):match("^@(.*)/_meta%.lua$")
local ok, meta = pcall(dofile, (dir or ".") .. "/kobold/meta.lua")

return {
    name = "kobold",
    fullname = _("Kobold"),
    description = _("Kobold home screen: currently reading, my books and collections."),
    version = ok and type(meta) == "table" and meta.VERSION or nil,
}
