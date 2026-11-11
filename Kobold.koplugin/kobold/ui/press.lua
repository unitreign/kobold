-- kobold/ui/press.lua — Kobold
-- Press feedback for tabs and list rows, as on the e-reader: the item turns
-- to its opposite (black on a light page, light in night mode) while it is
-- pressed, and its action runs when the finger comes up.
--   Press.tap(widget, rect, fn)      a quick tap: flash, then run fn
--   Press.hold(widget, rect)         the finger stays down: stay inverted
--   Press.release(widget, rect, fn)  the finger comes up after a hold
-- `widget` is the window the item is on (for the redraw afterwards); `rect`
-- the item on screen.

local Device          = require("device")
local UIManager       = require("ui/uimanager")

local Screen = Device.screen

local Press = {}

local held = nil  -- { widget, rect } while a finger is down on an item

-- Inverts `rect` on the screen and shows it right away.
local function invert(rect)
    pcall(function()
        Screen.bb:invertRect(rect.x, rect.y, rect.w, rect.h)
        Screen:refreshFast(rect.x, rect.y, rect.w, rect.h)
    end)
end

-- Draws `rect` of `widget` normally again.
local function restore(widget, rect)
    UIManager:setDirty(widget, function() return "fast", rect end)
end

function Press.tap(widget, rect, fn)
    if not rect then return fn() end
    if held then
        -- The tap ends a hold on the same item: release already ran it.
        held = nil
        return
    end
    invert(rect)
    UIManager:scheduleIn(0.12, function()
        restore(widget, rect)
        fn()
    end)
end

function Press.hold(widget, rect)
    if not rect then return end
    if held then restore(held.widget, held.rect) end
    held = { widget = widget, rect = rect }
    invert(rect)
end

function Press.release(widget, rect, fn)
    local h = held
    held = nil
    if h then restore(h.widget, h.rect) end
    -- Run only when the finger came up on the item it went down on.
    if h and rect and h.rect.x == rect.x and h.rect.y == rect.y and fn then fn() end
end

return Press
