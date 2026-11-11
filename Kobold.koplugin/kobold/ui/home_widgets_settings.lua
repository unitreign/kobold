-- kobold/ui/home_widgets_settings.lua — Kobold
-- Kobold Settings > Home widgets: what each part of the Home screen shows
-- and what tapping it does.
--   My Books widget    the latest books, or a series or collection
--   Collection widget  a random collection, or a series or collection
--   Continue reading   the title (the book's or custom text), tap action and
--                      label (a popup, stats_settings.lua)
--   Reading stats      the lines, their tap actions and the label (its own
--                      page, stats_settings.lua)
-- A widget showing a series or collection takes its name as the title.

local _               = require("kobold.l10n")
local KoboldEditors   = require("kobold.ui.editors")
local KoboldPrefs     = require("kobold.data.prefs")

local KoboldHomeWidgetsSettings = {}

-- "Shows" for a widget: its default, or the chosen series or collection.
-- `pref` holds { kind = "series" | "collections", key, name }, or nil.
local function sourceLabel(pref, default_label)
    local src = KoboldPrefs.get(pref)
    if type(src) == "table" and src.name then return src.name end
    return default_label
end

-- Every series or collection (`kind`), by name, to pick one for `pref`.
local function pickGroup(pref, kind, done)
    local MyBooksData = require("kobold.data.mybooks")
    local groups = MyBooksData.getGroups(MyBooksData.getBooks(), kind)
    table.sort(groups, function(a, b) return a.name:lower() < b.name:lower() end)
    local choices = {}
    for _i, g in ipairs(groups) do
        if #g.books > 0 then
            choices[#choices + 1] = { id = g.key, label = _.T(_("%1 (%2)"), g.name, #g.books) }
        end
    end
    local current = KoboldPrefs.get(pref)
    local by_key = {}
    for _i, g in ipairs(groups) do by_key[g.key] = g end
    KoboldEditors.list(kind == "series" and _("Choose a series") or _("Choose a collection"),
        choices, type(current) == "table" and current.kind == kind and current.key or nil,
        function(key)
            local g = by_key[key]
            if g then KoboldPrefs.set(pref, { kind = kind, key = g.key, name = g.name }) end
        end, done,
        kind == "series" and _("No series found in your library.") or _("You have no collections with books yet."))
end

-- The "Shows" row of a stack widget: its default, a series or a collection.
local function sourceRow(pref, default_label, done)
    local src = KoboldPrefs.get(pref)
    local custom = type(src) == "table"
    return {
        title = _("Shows"),
        value = sourceLabel(pref, default_label),
        on_tap = function()
            -- A series or collection is picked from a list each time, so
            -- those two are never shown ticked here.
            KoboldEditors.choose(_("Shows"), {
                { id = "default", label = default_label },
                { id = "series", label = _("A series…") },
                { id = "collections", label = _("A collection…") },
            }, not custom and "default" or nil, function(id)
                if id == "default" then
                    KoboldPrefs.set(pref, nil)
                    done()
                else
                    pickGroup(pref, id, done)
                end
            end)
        end,
    }
end

-- Rows for the Home widgets page. `settings` is the page (stats settings
-- open over it); `done` redraws it.
function KoboldHomeWidgetsSettings.spec(settings, done)
    return {
        { section = _("My Books widget") },
        sourceRow("home_left", _("Latest books"), done),
        { section = _("Collection widget") },
        sourceRow("home_right", _("A random collection"), done),
        { section = _("Continue reading") },
        {
            title = _("Title, tap action and label"),
            value = _("Edit"), action = true,
            on_tap = function() require("kobold.ui.stats_settings").show(settings, done, "continue") end,
        },
        { section = _("Reading stats") },
        {
            title = _("Lines, tap actions and label"),
            value = _("Edit"), action = true,
            on_tap = function() require("kobold.ui.stats_settings").show(settings, done) end,
        },
    }
end

return KoboldHomeWidgetsSettings
