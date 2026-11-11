-- kobold/ui/editors.lua — Kobold
-- Small editors used by Kobold's settings: pick one of a few choices, pick
-- from a long list or a grid of icons, pick a number, type a text, pick a
-- KOReader action, confirm. All in Kobold's own popups (picker.lua,
-- prompts.lua). Each calls `done`
-- once it closes (saved or not), so the caller can redraw its values.

local Device       = require("device")
local InfoMessage  = require("kobold.ui.prompts").Notice
local UIManager    = require("ui/uimanager")
local _            = require("kobold.l10n")
local KoboldActions = require("kobold.ui.actions")

local Screen = Device.screen

local KoboldEditors = {}

local function call(fn) if fn then fn() end end

-- One row per choice, the current one ticked, in Kobold's own popup
-- (picker.lua). `choices` = { { id, label } }.
function KoboldEditors.choose(title, choices, current, on_pick, done)
    require("kobold.ui.picker").choose(title, choices, current, function(id)
        if id ~= current then on_pick(id) end
        call(done)
    end, function() call(done) end)
end

-- A number between min and max, with - and + (prompts.lua).
function KoboldEditors.number(opts, on_set, done)
    require("kobold.ui.prompts").number{
        title = opts.title, info = opts.info,
        value = opts.value, min = opts.min, max = opts.max, default = opts.default,
        on_set = function(v)
            on_set(v)
            call(done)
        end,
        on_cancel = function() call(done) end,
    }
end

-- A line of text, typed with the keyboard (prompts.lua). on_save gets the
-- trimmed text. `notice`, when given, is a small note under the field.
function KoboldEditors.text(title, description, current, on_save, done, notice)
    require("kobold.ui.prompts").text{
        title = title, description = description, notice = notice,
        text = current or "",
        on_ok = function(text)
            on_save(text)
            call(done)
        end,
        on_cancel = function() call(done) end,
    }
end

-- A long list to pick one from, in pages (picker.lua): `choices` =
-- { { id, label } }, the current one ticked. `empty` is shown instead when
-- there is nothing to pick.
function KoboldEditors.list(title, choices, current, on_pick, done, empty)
    if #choices == 0 then
        UIManager:show(InfoMessage:new{ text = empty or _("Nothing to choose from.") })
        call(done)
        return
    end
    require("kobold.ui.picker").choose(title, choices, current, function(id)
        on_pick(id)
        call(done)
    end, function() call(done) end)
end

-- Icons to pick one from, as a grid (picker.lua): `choices` = { { id, label } },
-- each id an icon spec (see KoboldWidgets.iconFromSpec).
function KoboldEditors.icons(title, choices, current, on_pick, done, empty)
    if #choices == 0 then
        UIManager:show(InfoMessage:new{ text = empty or _("Nothing to choose from.") })
        call(done)
        return
    end
    require("kobold.ui.picker").icons(title, choices, current, function(id)
        on_pick(id)
        call(done)
    end, function() call(done) end)
end

-- Every KOReader action, other plugins' included.
function KoboldEditors.action(title, current, on_pick, done)
    local choices = {}
    for _i, action in ipairs(KoboldActions.list()) do
        choices[#choices + 1] = { id = action.id, label = action.title }
    end
    KoboldEditors.list(title, choices, current, on_pick, done, _("No KOReader actions were found."))
end

function KoboldEditors.confirm(text, ok_text, on_ok, done)
    require("kobold.ui.picker").confirm(text, ok_text, function()
        on_ok()
        call(done)
    end, function() call(done) end)
end

return KoboldEditors
