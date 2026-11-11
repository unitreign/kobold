-- kobold/ui/bars_settings.lua — Kobold
-- The settings rows for the toolbar, the nav bar and custom actions (the
-- data is in kobold/data/bars.lua):
--   Toolbar / Nav bar  the items in order; tap one to move it or remove it,
--                      "Add an item" lists what was removed plus every
--                      custom action. More cannot be removed.
--   Custom actions     a name, an icon and what it runs: a KOReader action
--                      or a plugin's menu entry. Made here, then added to a
--                      bar from the bar's page.

local DataStorage     = require("datastorage")
local Event           = require("ui/event")
local UIManager       = require("ui/uimanager")
local lfs             = require("libs/libkoreader-lfs")
local _               = require("kobold.l10n")
local KoboldBars      = require("kobold.data.bars")
local KoboldEditors   = require("kobold.ui.editors")
local KoboldMeta      = require("kobold.meta")

local KoboldBarsSettings = {}

-- Open Kobold screens are built again with the new bars.
local function barsChanged()
    UIManager:broadcastEvent(Event:new("KoboldIconsChanged"))
end

-- Bar items -----------------------------------------------------------------

-- Move up, Move down or Remove for item `i` of bar `bar`.
local function itemMenu(bar, i, done)
    local items = KoboldBars.items(bar)
    local id = items[i]
    local choices = {}
    if i > 1 then choices[#choices + 1] = { id = "up", label = _("Move up") } end
    if i < #items then choices[#choices + 1] = { id = "down", label = _("Move down") } end
    if KoboldBars.removable(bar, id) then
        choices[#choices + 1] = { id = "remove", label = _("Remove") }
    end
    KoboldEditors.choose(KoboldBars.label(bar, id), choices, nil, function(what)
        if what == "up" then
            items[i], items[i - 1] = items[i - 1], items[i]
        elseif what == "down" then
            items[i], items[i + 1] = items[i + 1], items[i]
        else
            table.remove(items, i)
        end
        KoboldBars.setItems(bar, items)
        barsChanged()
    end, done)
end

-- The rows listing bar `bar` ("toolbar" or "nav"), its Add row and a note
-- on how many fit.
function KoboldBarsSettings.itemRows(bar, done)
    local items = KoboldBars.items(bar)
    local rows = { { section = _("Items, in order") } }
    for i, id in ipairs(items) do
        local note = ""
        if bar == "nav" and id == "more" then
            note = _("Always shown")
        elseif bar == "nav" and KoboldBars.startTab() == id then
            note = _("Opens first")
        end
        rows[#rows + 1] = {
            title = KoboldBars.label(bar, id),
            value = note,
            on_tap = function() itemMenu(bar, i, done) end,
        }
    end
    rows[#rows + 1] = {
        title = _("Add an item"), value = "+",
        on_tap = function()
            KoboldEditors.list(bar == "nav" and _("Add to the nav bar") or _("Add to the toolbar"),
                KoboldBars.addable(bar), nil, function(id)
                    local list = KoboldBars.items(bar)
                    if bar == "nav" then
                        -- New tabs go before More, which stays last.
                        local at = #list
                        for j, item in ipairs(list) do
                            if item == "more" then at = j end
                        end
                        table.insert(list, at, id)
                    else
                        list[#list + 1] = id
                    end
                    KoboldBars.setItems(bar, list)
                    barsChanged()
                end, done,
                _("Everything is already here. Make your own items in Custom actions."))
        end,
    }
    local recommended = bar == "nav" and KoboldBars.NAV_RECOMMENDED or KoboldBars.TOOLBAR_RECOMMENDED
    rows[#rows + 1] = { section = _.T(_("Recommended: up to %1 items. More can look crowded."), recommended) }
    return rows
end

-- Icons ---------------------------------------------------------------------

-- The folder for the user's own icons (kept when Kobold is updated).
local function ownIconsDir()
    local dir = DataStorage:getSettingsDir() .. "/kobold_icons"
    if lfs.attributes(dir, "mode") ~= "directory" then pcall(lfs.mkdir, dir) end
    return dir
end

-- Icon files in `dir` (svg or png): { { id = prefix .. name, label }, ... }.
local function iconsIn(dir, prefix, full_path)
    local out = {}
    if not dir or lfs.attributes(dir, "mode") ~= "directory" then return out end
    for name in lfs.dir(dir) do
        local base, ext = name:match("^(.+)%.(%w+)$")
        if base and (ext:lower() == "svg" or ext:lower() == "png") then
            out[#out + 1] = { id = prefix .. (full_path and (dir .. "/" .. name) or base), label = base }
        end
    end
    table.sort(out, function(a, b) return a.label:lower() < b.label:lower() end)
    return out
end

-- Picks an icon for a custom action: Kobold's, KOReader's, or the user's
-- own (files in settings/kobold_icons). `on_pick(spec)`, see
-- KoboldWidgets.iconFromSpec.
local function pickIcon(current, on_pick, done)
    KoboldEditors.choose(_("Icon"), {
        { id = "kobold", label = _("Kobold icons") },
        { id = "koreader", label = _("KOReader icons") },
        { id = "own", label = _("My own icons") },
    }, nil, function(source)
        local icons, empty
        if source == "kobold" then
            icons = iconsIn(KoboldMeta.DIR and KoboldMeta.DIR .. "/icons", "kobold:")
        elseif source == "koreader" then
            icons = iconsIn("resources/icons/mdlight", "koreader:")
        else
            local dir = ownIconsDir()
            icons = iconsIn(dir, "file:", true)
            empty = _.T(_("No icons yet. Put SVG or PNG files in %1 and try again."), dir)
        end
        KoboldEditors.icons(_("Icon"), icons, current, on_pick, done, empty)
    end, done)
end

-- Custom actions ------------------------------------------------------------

-- Picks what a custom action runs: on_pick({ kind, action | module, entry,
-- title }).
local function pickTarget(on_pick, done)
    KoboldEditors.choose(_("Runs"), {
        { id = "action", label = _("A KOReader action") },
        { id = "plugin", label = _("A plugin") },
    }, nil, function(kind)
        if kind == "action" then
            local actions = require("kobold.ui.actions").list()
            local choices, titles = {}, {}
            for i, a in ipairs(actions) do
                choices[i] = { id = a.id, label = a.title }
                titles[a.id] = a.title
            end
            KoboldEditors.list(_("KOReader action"), choices, nil, function(id)
                on_pick({ kind = "action", action = id, title = titles[id] })
            end, done, _("No KOReader actions were found."))
        else
            local entries = require("kobold.data.plugins").list()
            local choices, by_id = {}, {}
            for i, e in ipairs(entries) do
                local id = e.module .. "\0" .. e.entry
                choices[i] = { id = id, label = e.title }
                by_id[id] = e
            end
            KoboldEditors.list(_("Plugin"), choices, nil, function(id)
                local e = by_id[id]
                on_pick({ kind = "plugin", module = e.module, entry = e.entry, title = e.title })
            end, done, _("No plugins with menu entries were found."))
        end
    end, done)
end

local function kindLabel(c)
    return c.kind == "action" and _("KOReader action") or _("Plugin")
end

-- New custom action: what it runs, then its name, then its icon.
local function newCustom(done)
    pickTarget(function(target)
        KoboldEditors.text(_("Name"), _("Shown under the icon in the nav bar."), target.title or "",
            function(name)
                local c = {
                    name = name ~= "" and name or target.title,
                    kind = target.kind, action = target.action,
                    module = target.module, entry = target.entry,
                }
                KoboldBars.saveCustom(c)
                pickIcon(nil, function(spec)
                    c.icon = spec
                    KoboldBars.saveCustom(c)
                    barsChanged()
                end, done)
            end, done)
    end, done)
end

-- Rename, Change icon, Change what it runs, Test or Delete.
local function customMenu(c, done)
    KoboldEditors.choose(c.name, {
        { id = "rename", label = _("Rename") },
        { id = "icon", label = _("Change icon") },
        { id = "target", label = _("Change what it runs") },
        { id = "test", label = _("Run it now") },
        { id = "delete", label = _("Delete") },
    }, nil, function(what)
        if what == "rename" then
            KoboldEditors.text(_("Name"), nil, c.name, function(name)
                if name ~= "" then c.name = name KoboldBars.saveCustom(c) barsChanged() end
            end, done)
        elseif what == "icon" then
            pickIcon(c.icon, function(spec)
                c.icon = spec
                KoboldBars.saveCustom(c)
                barsChanged()
            end, done)
        elseif what == "target" then
            pickTarget(function(target)
                c.kind, c.action, c.module, c.entry = target.kind, target.action, target.module, target.entry
                KoboldBars.saveCustom(c)
            end, done)
        elseif what == "test" then
            KoboldBars.runCustom(c.id)
        else
            KoboldEditors.confirm(_.T(_("Delete %1? It is also taken out of the toolbar and nav bar."), c.name),
                _("Delete"), function()
                    KoboldBars.deleteCustom(c.id)
                    barsChanged()
                end, done)
        end
    end)
end

-- Rows for the Custom actions page.
function KoboldBarsSettings.customRows(done)
    local rows = { { section = _("Your actions") } }
    for _i, c in ipairs(KoboldBars.customList()) do
        rows[#rows + 1] = {
            title = c.name, value = kindLabel(c),
            on_tap = function() customMenu(c, done) end,
        }
    end
    rows[#rows + 1] = {
        title = _("New custom action"), value = "+",
        on_tap = function() newCustom(done) end,
    }
    rows[#rows + 1] = { section = _("Add them to the toolbar or nav bar from those pages.") }
    return rows
end

return KoboldBarsSettings
