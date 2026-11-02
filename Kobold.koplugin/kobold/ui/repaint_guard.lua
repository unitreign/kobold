-- kobold/ui/repaint_guard.lua — Kobold
-- Stops windows hidden under a full-screen Kobold screen from refreshing
-- the display. The file browser below Kobold (and plugins drawing on it,
-- such as a clock in its title bar) can redraw itself every minute; KOReader
-- then repaints and refreshes the screen although nothing visible changed.
--
-- UIManager:setDirty is wrapped: a request for a window that has a
-- full-screen Kobold screen above it in the window stack is dropped.
-- Everything else goes through untouched, including requests for Kobold's
-- own screens, popups and dialogs, and requests not naming a window. When
-- a Kobold screen closes it is removed from the stack first, so the windows
-- below are repainted normally then.

local UIManager = require("ui/uimanager")

local KoboldRepaintGuard = {}

local function isKoboldScreen(w)
    return w and w.covers_fullscreen and type(w.name) == "string" and w.name:sub(1, 7) == "kobold_"
end

-- True when `widget` is a window in the stack that is fully covered: any
-- window under a full-screen Kobold screen, or a Kobold screen parked under
-- the reader (or another full-screen window) while a book is open.
local function hiddenUnderKobold(widget)
    if type(widget) ~= "table" then return false end
    local stack = UIManager._window_stack
    if type(stack) ~= "table" then return false end
    local kobold_above, fullscreen_above = false, false
    for i = #stack, 1, -1 do
        local w = stack[i].widget
        if w == widget then
            return kobold_above or (isKoboldScreen(widget) and fullscreen_above)
        end
        if isKoboldScreen(w) then kobold_above = true end
        if w and w.covers_fullscreen then fullscreen_above = true end
    end
    return false  -- not a window (a part of one): leave it alone
end

-- Installs the wrapper once per KOReader session (the flag lives on
-- UIManager). The wrapper asks UIManager._kobold_repaint_check, which every
-- install sets to this module's check, so after Restart Kobold reloads the
-- code (and installs again, see more.lua) the new check is the one used.
function KoboldRepaintGuard.install()
    UIManager._kobold_repaint_check = hiddenUnderKobold
    if UIManager._kobold_repaint_guard then return end
    local orig = UIManager.setDirty
    UIManager._kobold_repaint_guard = orig
    UIManager.setDirty = function(um, widget, ...)
        local hidden = um._kobold_repaint_check
        if hidden and hidden(widget) then return end
        return orig(um, widget, ...)
    end
end

return KoboldRepaintGuard
