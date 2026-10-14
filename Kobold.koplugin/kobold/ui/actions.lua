-- kobold/ui/actions.lua — Kobold
-- KOReader actions (the ones gestures and profiles can run, including those
-- other plugins register) for Kobold's tap targets: listing them for a
-- picker, and running one by id.

local Event           = require("ui/event")
local InfoMessage     = require("ui/widget/infomessage")
local UIManager       = require("ui/uimanager")
local _               = require("gettext")

local KoboldActions = {}

-- KOReader keeps its action table private inside the dispatcher module. Its
-- registerAction function closes over it, so it is read from there. Returns
-- the table, or nil when this KOReader build is laid out differently.
local function actionTable()
    local ok, Dispatcher = pcall(require, "dispatcher")
    if not ok or not Dispatcher or not Dispatcher.registerAction then return nil end
    pcall(function() Dispatcher:init() end)
    local i = 1
    while true do
        local name, value = debug.getupvalue(Dispatcher.registerAction, i)
        if not name then return nil end
        if name == "settingsList" and type(value) == "table" then return value end
        i = i + 1
    end
end

-- A runnable action: a plain event with no value to choose.
local function isSimple(def)
    return type(def) == "table" and def.title and def.event and def.category == "none"
        and (def.condition == nil or def.condition == true)
end

-- Every simple action, sorted by title: { { id, title }, ... }.
function KoboldActions.list()
    local out = {}
    for id, def in pairs(actionTable() or {}) do
        if isSimple(def) then out[#out + 1] = { id = id, title = tostring(def.title) } end
    end
    table.sort(out, function(a, b) return a.title:lower() < b.title:lower() end)
    return out
end

-- Title of action `id`, or the id itself when it is not registered.
function KoboldActions.title(id)
    local def = (actionTable() or {})[id]
    return def and def.title and tostring(def.title) or tostring(id)
end

-- Runs action `id`. Its event goes to the file manager, which passes it to
-- KOReader's modules and plugins (statistics, cloud storage, ...). Sending it
-- through UIManager would hand it to the top widget, a Kobold screen, which
-- does not handle it. Anything it opens shows above Kobold.
function KoboldActions.run(id)
    local def = (actionTable() or {})[id]
    local ok_fm, FileManager = pcall(require, "apps/filemanager/filemanager")
    local fm = ok_fm and FileManager and FileManager.instance
    if not (isSimple(def) and fm) then
        UIManager:show(InfoMessage:new{
            text = _("This action is not available: ") .. tostring(id),
        })
        return false
    end
    local ok, err = pcall(function() fm:handleEvent(Event:new(def.event, def.arg)) end)
    if not ok then
        UIManager:show(InfoMessage:new{ text = _("The action failed: ") .. tostring(err) })
    end
    return ok
end

return KoboldActions
