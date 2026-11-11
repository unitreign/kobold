-- kobold/ui/editors.lua — Kobold
-- Small editors used by Kobold's settings: pick one of a few choices, pick
-- a number, type a text, pick a KOReader action, confirm. Each calls `done`
-- once it closes (saved or not), so the caller can redraw its values.

local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox   = require("ui/widget/confirmbox")
local Device       = require("device")
local InfoMessage  = require("ui/widget/infomessage")
local InputDialog  = require("ui/widget/inputdialog")
local Menu         = require("ui/widget/menu")
local SpinWidget   = require("ui/widget/spinwidget")
local UIManager    = require("ui/uimanager")
local _            = require("kobold.l10n")
local KoboldActions = require("kobold.ui.actions")

local Screen = Device.screen

local KoboldEditors = {}

local function call(fn) if fn then fn() end end

-- One button per choice, the current one checked. `choices` = { { id, label } }.
function KoboldEditors.choose(title, choices, current, on_pick, done)
    local dialog
    local buttons = {}
    for _i, c in ipairs(choices) do
        buttons[#buttons + 1] = {{
            text = (c.id == current and "✓  " or "") .. c.label,
            callback = function()
                UIManager:close(dialog)
                if c.id ~= current then on_pick(c.id) end
                call(done)
            end,
        }}
    end
    dialog = ButtonDialog:new{
        title = title,
        width = math.floor(Screen:getWidth() * 0.7),
        buttons = buttons,
        tap_close_callback = function() call(done) end,
    }
    UIManager:show(dialog)
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

-- Full-screen list to pick one from, for lists too long for choose():
-- `choices` = { { id, label } }, the current one ticked. `empty` is shown
-- instead when there is nothing to pick.
function KoboldEditors.list(title, choices, current, on_pick, done, empty)
    local items = {}
    for _i, c in ipairs(choices) do
        items[#items + 1] = { text = (c.id == current and "✓  " or "") .. c.label, choice_id = c.id }
    end
    if #items == 0 then
        UIManager:show(InfoMessage:new{ text = empty or _("Nothing to choose from.") })
        call(done)
        return
    end
    local menu
    menu = Menu:new{
        title = title,
        item_table = items,
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        onMenuChoice = function(_menu, item)
            on_pick(item.choice_id)
            UIManager:close(menu)
            call(done)
        end,
        -- Menu leaves closing itself to this callback.
        close_callback = function()
            UIManager:close(menu)
            call(done)
        end,
    }
    UIManager:show(menu)
end

-- Full-screen list of every KOReader action, other plugins' included.
function KoboldEditors.action(title, current, on_pick, done)
    local choices = {}
    for _i, action in ipairs(KoboldActions.list()) do
        choices[#choices + 1] = { id = action.id, label = action.title }
    end
    KoboldEditors.list(title, choices, current, on_pick, done, _("No KOReader actions were found."))
end

function KoboldEditors.confirm(text, ok_text, on_ok, done)
    UIManager:show(ConfirmBox:new{
        text = text,
        ok_text = ok_text,
        ok_callback = function()
            on_ok()
            call(done)
        end,
        cancel_callback = function() call(done) end,
    })
end

return KoboldEditors
