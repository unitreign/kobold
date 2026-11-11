-- kobold/ui/editors.lua — Kobold
-- Small editors used by Kobold's settings: pick one of a few choices, pick
-- from a long list or a grid of icons, pick a number, type a text, pick a
-- KOReader action, confirm. Choosing and confirming use Kobold's own popups
-- (picker.lua); numbers and text use KOReader's (they need its keyboard and
-- spinner). Each calls `done`
-- once it closes (saved or not), so the caller can redraw its values.

local Device       = require("device")
local InfoMessage  = require("ui/widget/infomessage")
local InputDialog  = require("ui/widget/inputdialog")
local SpinWidget   = require("ui/widget/spinwidget")
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

-- A number between min and max.
function KoboldEditors.number(opts, on_set, done)
    UIManager:show(SpinWidget:new{
        title_text = opts.title,
        info_text = opts.info,
        value = opts.value,
        value_min = opts.min,
        value_max = opts.max,
        value_step = 1,
        default_value = opts.default,
        callback = function(spin)
            on_set(spin.value)
            call(done)
        end,
        cancel_callback = function() call(done) end,
    })
end

-- A line of text. on_save gets the trimmed text.
function KoboldEditors.text(title, description, current, on_save, done)
    local dialog
    dialog = InputDialog:new{
        title = title,
        description = description,
        input = current or "",
        buttons = {{
            {
                text = _("Cancel"),
                id = "close",
                callback = function()
                    UIManager:close(dialog)
                    call(done)
                end,
            },
            {
                text = _("Save"),
                is_enter_default = true,
                callback = function()
                    local text = dialog:getInputText():match("^%s*(.-)%s*$")
                    UIManager:close(dialog)
                    on_save(text)
                    call(done)
                end,
            },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
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
