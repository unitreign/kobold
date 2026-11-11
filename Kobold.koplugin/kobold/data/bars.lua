-- kobold/data/bars.lua — Kobold
-- What the toolbar (the icons at the right of the status bar) and the nav
-- bar (the tabs at the bottom) hold, in order, and the custom actions that
-- can go in them. Set in Kobold Settings > Toolbar, Nav bar and Custom
-- actions. Builds no widgets.
--
-- Items are ids: the built-in ones below, or a custom action's id
-- ("custom:3"). Any item can be removed and added back, except More in the
-- nav bar: it leads to Kobold Settings, so it always stays. Kobold opens on
-- the first screen tab in the nav bar.

local _               = require("kobold.l10n")
local KoboldPrefs     = require("kobold.data.prefs")

local KoboldBars = {}

-- Built-in items, in their default order.
KoboldBars.TOOLBAR_BUILTIN = {
    { id = "brightness", label = _("Brightness") },
    { id = "wifi",       label = _("Wi-Fi") },
    { id = "battery",    label = _("Battery") },
    { id = "search",     label = _("Search") },
}
KoboldBars.NAV_BUILTIN = {
    { id = "home",  label = _("Home") },
    { id = "books", label = _("My Books") },
    { id = "more",  label = _("More") },
}
-- Nav items that open a Kobold screen (tabs that can be selected).
local SCREENS = { home = true, books = true, more = true }

-- How many fit before it looks crowded (shown in the settings, not enforced).
KoboldBars.TOOLBAR_RECOMMENDED = 6
KoboldBars.NAV_RECOMMENDED = 5

local function ids(list)
    local out = {}
    for i, item in ipairs(list) do out[i] = item.id end
    return out
end

local function copy(list)
    local out = {}
    for i, v in ipairs(list) do out[i] = v end
    return out
end

-- Custom actions ----------------------------------------------------------

-- { { id = "custom:N", name, icon, kind = "plugin" | "action",
--     module, entry (plugin) | action (KOReader action id) }, ... }
function KoboldBars.customList()
    local list = KoboldPrefs.get("custom_actions")
    return type(list) == "table" and list or {}
end

function KoboldBars.custom(id)
    for _i, c in ipairs(KoboldBars.customList()) do
        if c.id == id then return c end
    end
    return nil
end

-- Adds or replaces custom action `c` (by c.id; a new one gets an id).
-- Returns its id.
function KoboldBars.saveCustom(c)
    local list = copy(KoboldBars.customList())
    if not c.id then
        local n = tonumber(KoboldPrefs.get("custom_next")) or 1
        c.id = "custom:" .. n
        KoboldPrefs.set("custom_next", n + 1)
        list[#list + 1] = c
    else
        local found = false
        for i, old in ipairs(list) do
            if old.id == c.id then list[i] = c found = true end
        end
        if not found then list[#list + 1] = c end
    end
    KoboldPrefs.set("custom_actions", list)
    return c.id
end

-- Deletes a custom action, and takes it out of both bars.
function KoboldBars.deleteCustom(id)
    local list = {}
    for _i, c in ipairs(KoboldBars.customList()) do
        if c.id ~= id then list[#list + 1] = c end
    end
    KoboldPrefs.set("custom_actions", list)
    for _i, bar in ipairs({ "toolbar", "nav" }) do
        local items = {}
        for _j, item in ipairs(KoboldBars.items(bar)) do
            if item ~= id then items[#items + 1] = item end
        end
        KoboldBars.setItems(bar, items)
    end
end

-- Runs custom action `id`. False when it could not run.
function KoboldBars.runCustom(id)
    local c = KoboldBars.custom(id)
    if not c then return false end
    if c.kind == "action" then
        return require("kobold.ui.actions").run(c.action)
    end
    local ok = require("kobold.data.plugins").run(c.module, c.entry)
    if not ok then
        local UIManager = require("ui/uimanager")
        UIManager:show(require("ui/widget/infomessage"):new{
            text = _.T(_("%1 is not available. The plugin may be turned off."), c.name or ""),
        })
    end
    return ok
end

-- The bars -----------------------------------------------------------------

local function builtins(bar)
    return bar == "nav" and KoboldBars.NAV_BUILTIN or KoboldBars.TOOLBAR_BUILTIN
end

local function isBuiltin(bar, id)
    for _i, b in ipairs(builtins(bar)) do
        if b.id == id then return true end
    end
    return false
end

-- The ids in bar `bar` ("toolbar" or "nav"), in order. Custom actions that
-- were deleted are left out; the nav bar always has More.
function KoboldBars.items(bar)
    local saved = KoboldPrefs.get(bar .. "_items")
    local list = type(saved) == "table" and saved or ids(builtins(bar))
    local out, has_more = {}, false
    for _i, id in ipairs(list) do
        if isBuiltin(bar, id) or KoboldBars.custom(id) then
            out[#out + 1] = id
            if id == "more" then has_more = true end
        end
    end
    if bar == "nav" and not has_more then out[#out + 1] = "more" end
    return out
end

function KoboldBars.setItems(bar, list)
    KoboldPrefs.set(bar .. "_items", list)
end

-- What can be added to bar `bar`: its built-ins not in it, then every
-- custom action not in it. { { id, label }, ... }
function KoboldBars.addable(bar)
    local present = {}
    for _i, id in ipairs(KoboldBars.items(bar)) do present[id] = true end
    local out = {}
    for _i, b in ipairs(builtins(bar)) do
        if not present[b.id] then out[#out + 1] = { id = b.id, label = b.label } end
    end
    for _i, c in ipairs(KoboldBars.customList()) do
        if not present[c.id] then out[#out + 1] = { id = c.id, label = c.name } end
    end
    return out
end

-- The name of item `id` in bar `bar`.
function KoboldBars.label(bar, id)
    for _i, b in ipairs(builtins(bar)) do
        if b.id == id then return b.label end
    end
    local c = KoboldBars.custom(id)
    return c and c.name or id
end

-- True when the item can be removed (everything but More in the nav bar).
function KoboldBars.removable(bar, id)
    return not (bar == "nav" and id == "more")
end

-- True for a nav item that opens a Kobold screen.
function KoboldBars.isScreen(id)
    return SCREENS[id] == true
end

-- The tab Kobold opens on: the first screen in the nav bar.
function KoboldBars.startTab()
    for _i, id in ipairs(KoboldBars.items("nav")) do
        if SCREENS[id] then return id end
    end
    return "more"
end

return KoboldBars
