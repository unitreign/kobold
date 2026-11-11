-- kobold/data/tokens.lua — Kobold
-- Live values in custom text: a Home text line such as
-- "[streak] days in a row · [time]" shows the current values in place of
-- the tokens. Builds no widgets.
--
-- A token Kobold does not know is left as typed, so a typo shows. A known
-- token without a value right now (no reading stats yet, no book opened)
-- shows a dash.

local Device          = require("device")
local _               = require("kobold.l10n")
local KoboldStats     = require("kobold.data.stats")

local KoboldTokens = {}

-- "1h 20m", "45m": a reading time.
local function duration(seconds)
    if not seconds then return nil end
    local minutes = math.floor(seconds / 60 + 0.5)
    if minutes < 60 then return _.T(_("%1m"), minutes) end
    return _.T(_("%1h %2m"), math.floor(minutes / 60), minutes % 60)
end

-- The book read last: { file, title } or nil.
local function latestBook()
    return require("kobold.data.home").getLatestRead()
end

-- Every token, in the order the help lists them. `live` ones change by
-- themselves, so text using them is redrawn every minute.
KoboldTokens.LIST = {
    { id = "time", live = true, value = function()
        return require("kobold.ui.widgets").clockText()
    end },
    { id = "date", live = true, value = function() return os.date("%d %b") end },
    { id = "battery", live = true, value = function()
        local ok, n = pcall(function() return Device:getPowerDevice():getCapacity() end)
        return ok and n or nil
    end },
    { id = "streak", value = function() return KoboldStats.streakDays() end },
    { id = "today_time", value = function() return duration(KoboldStats.todaySeconds()) end },
    { id = "today_pages", value = function() return KoboldStats.todayPages() end },
    { id = "week_hours", value = function()
        local s = KoboldStats.weekReadSeconds()
        return s and math.floor(s / 3600 + 0.5)
    end },
    { id = "week_pages", value = function() return KoboldStats.weekPages() end },
    { id = "total_hours", value = function() return KoboldStats.totalReadHours() end },
    { id = "books_finished", value = function()
        local MyBooksData = require("kobold.data.mybooks")
        return #MyBooksData.filter(MyBooksData.getBooks(), "finished")
    end },
    { id = "book", value = function()
        local b = latestBook()
        return b and b.title
    end },
    { id = "progress", value = function()
        local b = latestBook()
        local info = b and require("kobold.data.library").getDocInfoCached(b.file)
        return info and info.percent and math.floor(info.percent * 100 + 0.5) or nil
    end },
}

local BY_ID = {}
for _i, t in ipairs(KoboldTokens.LIST) do BY_ID[t.id] = t end

-- `text` with its tokens replaced, and true when one of them is live.
function KoboldTokens.expand(text)
    local live = false
    local out = text:gsub("%[([%w_]+)%]", function(id)
        local t = BY_ID[id]
        if not t then return nil end  -- unknown: left as typed
        if t.live then live = true end
        local ok, v = pcall(t.value)
        if not ok or v == nil then return "–" end
        return tostring(v)
    end)
    return out, live
end

-- The tokens, for the text editor's help: "[time] [date] ...".
function KoboldTokens.help()
    local names = {}
    for i, t in ipairs(KoboldTokens.LIST) do names[i] = "[" .. t.id .. "]" end
    return _.T(_("Tokens show live values: %1"), table.concat(names, " "))
end

return KoboldTokens
