-- kobold/ui/session.lua — Kobold
-- Remembers which Kobold screen a book was opened from, so closing the book
-- comes back to that screen (and, for My Books, the same tab, group and
-- page) instead of KOReader's file browser.
--
-- How it fits together: opening a book does not close the Kobold screen.
-- It is "parked": it stays in KOReader's window stack under the reader,
-- which covers it (see reader.lua and the ShowingReader handler in
-- widgets.lua). Closing the book makes KOReader build a new file browser,
-- which runs Kobold's plugin init again; main.lua then lifts the parked
-- screen above the new browser, so it shows without being built again.
-- If the parked screen is gone, the tab is opened fresh from the record.

local UIManager = require("ui/uimanager")

local KoboldSession = {}

local pending = nil  -- { tab = "home" | "books" | "more", state = table or nil, screen = parked or nil }

-- Records `screen` as the place to return to, and parks it (it is kept
-- alive under the reader). Screens may provide getReturnState() for
-- anything else worth restoring.
function KoboldSession.rememberScreen(screen)
    if not screen or not screen.kobold_tab then return end
    pending = {
        tab = screen.kobold_tab,
        state = screen.getReturnState and screen:getReturnState() or nil,
        screen = screen,
    }
end

-- Records a tab to show the next time the file browser starts (used to
-- open Kobold over a book: the book is closed first, see main.lua).
function KoboldSession.rememberTab(tab, state)
    KoboldSession.dropParked()
    pending = { tab = tab, state = state }
end

-- True when `w` is still in KOReader's window stack.
local function inStack(w)
    for _i, entry in ipairs(UIManager._window_stack or {}) do
        if entry.widget == w then return true end
    end
    return false
end

-- Closes a parked screen that will not be shown again.
function KoboldSession.dropParked()
    local w = pending and pending.screen
    if w and inStack(w) then UIManager:close(w) end
    if pending then pending.screen = nil end
end

-- Moves parked screen `w` to the top of the window stack and asks for a
-- full repaint (also clears what the book page left on the screen). False
-- when it is no longer in the stack.
function KoboldSession.raise(w)
    local stack = UIManager._window_stack
    if not w or type(stack) ~= "table" then return false end
    for i, entry in ipairs(stack) do
        if entry.widget == w then
            table.remove(stack, i)
            table.insert(stack, entry)
            UIManager:setDirty(w, "full")
            return true
        end
    end
    return false
end

-- True when closing the book will bring Kobold back.
function KoboldSession.returning()
    return pending ~= nil
end

-- The recorded screen, cleared so it is used once. nil when there is none.
function KoboldSession.take()
    local p = pending
    pending = nil
    return p
end

return KoboldSession
