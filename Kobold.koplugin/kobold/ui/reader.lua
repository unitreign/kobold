-- kobold/ui/reader.lua — Kobold
-- Opens a book from a Kobold screen.

local InfoMessage     = require("ui/widget/infomessage")
local UIManager       = require("ui/uimanager")
local _               = require("gettext")
local KoboldSession   = require("kobold.ui.session")

local KoboldReader = {}

-- Closes `screen`, then opens the book with KOReader's reader (the same call
-- SimpleUI uses). The screen is remembered so closing the book returns to it.
-- A failure is shown on screen instead of being ignored.
function KoboldReader.open(screen, file)
    -- The screen is parked, not closed: it stays under the reader so it
    -- can come back at once when the book closes (see session.lua).
    KoboldSession.rememberScreen(screen)
    -- "Opening Book" panel (Kobold Settings), painted before KOReader starts
    -- the slow part; the book then opens on the next tick. It stays on top
    -- (it is modal) while the book loads, and closes once the book is fully
    -- open, through showReader's after-open callback.
    local Transition = require("kobold.ui.transition")
    Transition.show(_("Opening Book"))
    local function openNow()
        local ok, err = pcall(function()
            local ReaderUI = package.loaded["apps/reader/readerui"]
                or require("apps/reader/readerui")
            -- With the panel on, KOReader's own "Opening file" message is
            -- hidden (its "seamless" open), so only Kobold's panel shows.
            local quiet = Transition.enabled()
            ReaderUI:showReader(file, nil, quiet or nil, nil,
                quiet and function() Transition.bookReady() end or nil)
        end)
        if not ok then
            Transition.close()
            UIManager:show(InfoMessage:new{
                text = _("Could not open the book: ") .. tostring(err),
            })
        end
    end
    if Transition.enabled() then UIManager:nextTick(openNow) else openNow() end
end

-- How a tap opens a book: "single" or "double". Kobold Settings can pick
-- one; by default it follows KOReader, where double-tap opening comes from
-- the "browser double tap" user patch (setting browser_double_tap).
local function tapMode()
    local own = require("kobold.data.prefs").get("open_tap")
    if own == "single" or own == "double" then return own, 500 end
    local cfg = G_reader_settings and G_reader_settings:readSetting("browser_double_tap")
    if type(cfg) == "table" and cfg.require_double_tap then
        return "double", tonumber(cfg.timeout_ms) or 500
    end
    return "single", 500
end

local last_tap = nil  -- { file, ms }

-- Opens `file` from a tap. In double-tap mode the first tap only arms it:
-- a second tap on the same book within the time limit opens it.
function KoboldReader.tapOpen(screen, file)
    local mode, timeout_ms = tapMode()
    if mode == "single" then return KoboldReader.open(screen, file) end
    local now = os.time() * 1000 + math.floor((os.clock() % 1) * 1000)
    local ok, time = pcall(require, "ui/time")
    if ok and time and time.now then now = time.to_ms(time.now()) end
    if last_tap and last_tap.file == file and now - last_tap.ms <= timeout_ms then
        last_tap = nil
        return KoboldReader.open(screen, file)
    end
    last_tap = { file = file, ms = now }
end

return KoboldReader
