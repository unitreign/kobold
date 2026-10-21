-- kobold/ui/transition.lua — Kobold
-- The small "Opening book" / "Closing book" panel shown while KOReader opens
-- or closes a book from Kobold: a rounded box in the middle of the screen,
-- in the style of Kobold's popups. Painted at once, so it is on screen while
-- KOReader does the slow part. Can be turned off in Kobold Settings.

local Blitbuffer      = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device          = require("device")
local FrameContainer  = require("ui/widget/container/framecontainer")
local Geom            = require("ui/geometry")
local InputContainer  = require("ui/widget/container/inputcontainer")
local TextWidget      = require("ui/widget/textwidget")
local UIManager       = require("ui/uimanager")
local KoboldPrefs     = require("kobold.data.prefs")
local KoboldPopup     = require("kobold.ui.popup")
local KoboldWidgets   = require("kobold.ui.widgets")

local Screen = Device.screen

local KoboldTransition = {}

local Panel = InputContainer:extend{
    modal = true,
    name = "kobold_transition",
    text = nil,
}

function Panel:init()
    local W, H = Screen:getWidth(), Screen:getHeight()
    local box = FrameContainer:new{
        bordersize = Screen:scaleBySize(2),
        padding = Screen:scaleBySize(24),
        padding_left = Screen:scaleBySize(40), padding_right = Screen:scaleBySize(40),
        radius = KoboldPopup.radius(),
        background = Blitbuffer.COLOR_WHITE,
        TextWidget:new{ text = self.text, face = KoboldWidgets.face(20) },
    }
    local size = box:getSize()
    -- The window covers the screen (KOReader draws a window from its dimen's
    -- corner, and the box is centred inside it); box_dimen is the part that
    -- needs refreshing.
    self.dimen = Geom:new{ x = 0, y = 0, w = W, h = H }
    self.box_dimen = Geom:new{
        x = math.floor((W - size.w) / 2), y = math.floor((H - size.h) / 2),
        w = size.w, h = size.h,
    }
    self[1] = CenterContainer:new{ dimen = Geom:new{ w = W, h = H }, box }
end


local current = nil

-- True when the panel is turned on (Kobold Settings, off by default). On,
-- Kobold shows its own panel and KOReader's "Opening file" message is
-- hidden; off, opening and closing look exactly as in KOReader.
function KoboldTransition.enabled()
    return KoboldPrefs.get("transition") == true
end

-- Shows the panel with `text` and paints it right away.
function KoboldTransition.show(text)
    if not KoboldTransition.enabled() then return end
    KoboldTransition.close()
    current = Panel:new{ text = text }
    UIManager:show(current, "ui", current.box_dimen)
    UIManager:forceRePaint()
    -- Safety: the panel is modal and blocks taps, so it never stays longer
    -- than this even if the book never reports back.
    local shown = current
    UIManager:scheduleIn(15, function()
        if current == shown then KoboldTransition.close() end
    end)
end

-- Closes the panel once the book is fully open (see reader.lua), with a
-- full refresh: the book was opened quietly (no KOReader message, a light
-- refresh), so this leaves the page clean.
function KoboldTransition.bookReady()
    if current then
        KoboldTransition.close()
        UIManager:setDirty("all", "full")
    end
end

function KoboldTransition.close()
    if current then
        local p = current
        current = nil
        UIManager:close(p)
    end
end

return KoboldTransition
