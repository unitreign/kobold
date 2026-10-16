-- kobold/ui/session.lua — Kobold
-- Remembers which Kobold screen a book was opened from, so closing the book
-- comes back to that screen (and, for My Books, the same tab, group and
-- page) instead of KOReader's file browser.
--
-- How it fits together: opening a book closes the Kobold screen (see
-- reader.lua and the ShowingReader handler in widgets.lua), which records it
-- here. Closing the book makes KOReader build a new file browser, which runs
-- Kobold's plugin init again; main.lua then takes the record and reopens it.

local KoboldSession = {}

local pending = nil  -- { tab = "home" | "books" | "more", state = table or nil }

-- Records `screen` as the place to return to. Screens may provide
-- getReturnState() for anything else worth restoring.
function KoboldSession.rememberScreen(screen)
    if not screen or not screen.kobold_tab then return end
    pending = {
        tab = screen.kobold_tab,
        state = screen.getReturnState and screen:getReturnState() or nil,
    }
end

-- Records a tab to show the next time the file browser starts (used to
-- open Kobold over a book: the book is closed first, see main.lua).
function KoboldSession.rememberTab(tab, state)
    pending = { tab = tab, state = state }
end

-- The recorded screen, cleared so it is used once. nil when there is none.
function KoboldSession.take()
    local p = pending
    pending = nil
    return p
end

return KoboldSession
