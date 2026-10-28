-- kobold/ui/search_prompt.lua — Kobold
-- A small search popup in the e-reader's style: a bordered box near the top
-- of the screen with the search icon and a text field typed into directly,
-- the keyboard below. The keyboard's Go key searches; a tap outside the box
-- closes it. Used by Add books to collection.

local Blitbuffer      = require("ffi/blitbuffer")
local Device          = require("device")
local FrameContainer  = require("ui/widget/container/framecontainer")
local Geom            = require("ui/geometry")
local GestureRange    = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local InputContainer  = require("ui/widget/container/inputcontainer")
local InputText       = require("ui/widget/inputtext")
local LeftContainer   = require("ui/widget/container/leftcontainer")
local UIManager       = require("ui/uimanager")
local _               = require("gettext")
local KoboldPopup     = require("kobold.ui.popup")
local KoboldWidgets   = require("kobold.ui.widgets")

local Screen = Device.screen

local KoboldSearchPrompt = InputContainer:extend{
    name = "kobold_search_prompt",
    -- Also gets taps the keyboard does not use, so a tap outside the box
    -- closes it (KOReader gives a tap to the keyboard first).
    is_always_active = true,
    text = "",
    hint = nil,
    on_search = nil,  -- called with the trimmed text ("" clears the search)
}

function KoboldSearchPrompt:init()
    local W, H = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = W, h = H }
    local R = KoboldPopup.panelRect()
    local border = Screen:scaleBySize(2)
    local pad = Screen:scaleBySize(12)
    local icon = Screen:scaleBySize(26)
    local box_h = Screen:scaleBySize(60)
    local fw = R.w - 2 * Screen:scaleBySize(20)
    local fx = R.x + Screen:scaleBySize(20)
    local fy = R.y + Screen:scaleBySize(120)
    local inner_h = box_h - 2 * border
    local field_w = fw - 2 * border - icon - 3 * pad
    self.input = InputText:new{
        text = self.text or "",
        hint = self.hint or _("title, author, or series"),
        face = KoboldWidgets.face(18),
        width = field_w,
        bordersize = 0, padding = 0, margin = 0,
        focused = true,
        parent = self,
        enter_callback = function() self:submit() end,
    }
    local box = FrameContainer:new{
        bordersize = border, padding = 0, radius = KoboldPopup.radius(),
        background = Blitbuffer.COLOR_WHITE,
        KoboldWidgets.fixed(fw - 2 * border, inner_h, HorizontalGroup:new{
            align = "center",
            HorizontalSpan:new{ width = pad },
            KoboldWidgets.customIcon("search", icon, "appbar.search"),
            HorizontalSpan:new{ width = pad },
            LeftContainer:new{ dimen = Geom:new{ w = field_w, h = inner_h }, self.input },
        }),
    }
    self.frame_dimen = Geom:new{ x = fx, y = fy, w = fw, h = box_h }
    self[1] = KoboldPopup.place(self.dimen, fx, fy, box)
    if Device:hasKeys() then
        self.key_events = { Close = { { Device.input.group.Back } } }
    end
    if Device:isTouchDevice() then
        self.ges_events = { TapPrompt = { GestureRange:new{ ges = "tap", range = self.dimen } } }
    end
end

function KoboldSearchPrompt:submit()
    local text = (self.input:getText() or ""):match("^%s*(.-)%s*$")
    self:onClose()
    if self.on_search then self.on_search(text) end
end

-- Taps inside the box are the text field's; anywhere else closes.
function KoboldSearchPrompt:onTapPrompt(_, ges)
    if self.closed then return false end
    if ges.pos:intersectWith(self.frame_dimen) then
        self.input:onShowKeyboard()
        return true
    end
    return self:onClose()
end

function KoboldSearchPrompt:onClose()
    if self.closed then return true end
    self.closed = true
    self.input:onCloseKeyboard()
    UIManager:close(self, "ui", self.frame_dimen)
    return true
end

-- Opens the popup with the keyboard up. opts = { text, hint, on_search }.
function KoboldSearchPrompt.show(opts)
    local w = KoboldSearchPrompt:new(opts)
    UIManager:show(w, "ui", w.frame_dimen)
    w.input:onShowKeyboard()
    return w
end

return KoboldSearchPrompt
