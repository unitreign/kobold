-- kobold/data/stats.lua — Kobold
-- Reading statistics from KOReader's statistics.sqlite3. Builds no widgets.

local lfs             = require("libs/libkoreader-lfs")

local KoboldStats = {}

-- Opens statistics.sqlite3, runs fn(conn) and closes it again.
-- Returns fn's result, or nil when the database or sqlite binding is unavailable.
local function withDB(fn)
    local ok_ds, DataStorage = pcall(require, "datastorage")
    if not ok_ds or not DataStorage then return nil end
    local db_path = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
    if lfs.attributes(db_path, "mode") ~= "file" then return nil end

    local ok_sq, SQ3 = pcall(require, "lua-ljsqlite3/init")
    if not ok_sq or not SQ3 then return nil end

    local ok, result = pcall(function()
        local conn = SQ3.open(db_path)
        local ok_fn, res = pcall(fn, conn)
        pcall(function() conn:close() end)
        if not ok_fn then error(res) end
        return res
    end)
    if not ok then return nil end
    return result
end

-- Value in column `col` (1-based) of the first row of a query, or nil.
local function firstValue(conn, sql, col)
    local res = conn:exec(sql)
    return res and res[col] and res[col][1]
end

-- "<size>:<mtime>" of statistics.sqlite3, or nil. It changes whenever the
-- statistics plugin saves reading time, which happens while reading.
local function dbFingerprint()
    local ok_ds, DataStorage = pcall(require, "datastorage")
    if not ok_ds or not DataStorage then return nil end
    local attr = lfs.attributes(DataStorage:getSettingsDir() .. "/statistics.sqlite3")
    if not attr or attr.mode ~= "file" then return nil end
    return (attr.size or 0) .. ":" .. (attr.modification or 0)
end

-- Results kept until the database changes: { [key] = { fp, result } }. Home
-- asks for the same numbers on every visit; between reading sessions they
-- cannot change, so the database is not opened again.
local memo = {}

-- Runs fn(conn) and returns { value = <its result> }, or nil when the
-- database is unavailable. The wrapper keeps a NULL result (nothing read in
-- that period) apart from a missing database. `key` names the query for
-- the memo; include anything the query depends on (a start time, ...).
local function query(key, fn)
    local fp = dbFingerprint()
    if not fp then return nil end
    local m = memo[key]
    if m and m.fp == fp then return m.result end
    local result = withDB(function(conn) return { value = fn(conn) } end)
    memo[key] = { fp = fp, result = result }
    return result
end

-- Total reading time across all books, in whole hours. nil when unavailable.
function KoboldStats.totalReadHours()
    local r = query("total", function(conn)
        return firstValue(conn, "SELECT SUM(duration) FROM page_stat;", 1)
    end)
    if not r then return nil end
    return math.floor((tonumber(r.value) or 0) / 3600 + 0.5)
end

-- os.time() of today 00:00 and of this Monday 00:00, local time.
local function todayStart()
    local now = os.date("*t")
    return os.time{ year = now.year, month = now.month, day = now.day, hour = 0, min = 0, sec = 0 }
end

local function weekStart()
    local now = os.date("*t")
    local days_since_monday = (now.wday + 5) % 7  -- wday: 1 = Sunday
    return os.time{
        year = now.year, month = now.month, day = now.day - days_since_monday,
        hour = 0, min = 0, sec = 0,
    }
end

-- Seconds read since `since`. nil when unavailable.
local function secondsSince(since)
    local r = query("seconds:" .. since, function(conn)
        return firstValue(conn, string.format(
            "SELECT SUM(duration) FROM page_stat WHERE start_time >= %d;", since), 1)
    end)
    if not r then return nil end
    return tonumber(r.value) or 0
end

-- Distinct pages read since `since`. nil when unavailable.
local function pagesSince(since)
    local r = query("pages:" .. since, function(conn)
        return firstValue(conn, string.format(
            "SELECT COUNT(*) FROM (SELECT DISTINCT id_book, page FROM page_stat WHERE start_time >= %d);",
            since), 1)
    end)
    if not r then return nil end
    return tonumber(r.value) or 0
end

-- Seconds read since Monday 00:00 this week (local time). nil when unavailable.
function KoboldStats.weekReadSeconds()
    return secondsSince(weekStart())
end

-- Days in a row with any reading, counting back from today (or from
-- yesterday, so the streak is not lost before today's first page).
function KoboldStats.streakDays()
    local r = query("streak:" .. os.date("%Y-%m-%d"), function(conn)
        local res = conn:exec(string.format(
            "SELECT DISTINCT date(start_time, 'unixepoch', 'localtime') AS d FROM page_stat"
            .. " WHERE start_time >= %d ORDER BY d DESC;", os.time() - 400 * 86400))
        return res and res[1] or {}
    end)
    if not r then return nil end
    local read = {}
    for _i, d in ipairs(r.value) do read[d] = true end
    local today = os.date("*t")
    local function day(offset)
        return os.date("%Y-%m-%d", os.time{
            year = today.year, month = today.month, day = today.day - offset, hour = 12,
        })
    end
    local offset = read[day(0)] and 0 or 1
    local days = 0
    while read[day(offset + days)] do days = days + 1 end
    return days
end

local function hoursText(seconds, suffix)
    local h = math.floor(seconds / 3600 + 0.5)
    if seconds > 0 and h == 0 then return "Less than 1 hour " .. suffix end
    return h .. (h == 1 and " hour " or " hours ") .. suffix
end

local function plural(n, one, many)
    return n .. " " .. (n == 1 and one or many)
end

-- Lines the Home reading stats can show (Kobold Settings), in menu order.
-- text() returns the line, or nil when the statistics are unavailable.
KoboldStats.LINES = {
    { id = "total_hours", label = "Total hours read", text = function()
        local h = KoboldStats.totalReadHours()
        return h and (h .. " hours read totally")
    end },
    { id = "week_hours", label = "Hours this week", text = function()
        local s = KoboldStats.weekReadSeconds()
        return s and hoursText(s, "this week")
    end },
    { id = "today_time", label = "Time read today", text = function()
        local s = secondsSince(todayStart())
        if not s then return nil end
        if s < 3600 then return plural(math.floor(s / 60 + 0.5), "minute", "minutes") .. " today" end
        return hoursText(s, "today")
    end },
    { id = "today_pages", label = "Pages read today", text = function()
        local n = pagesSince(todayStart())
        return n and (plural(n, "page", "pages") .. " today")
    end },
    { id = "week_pages", label = "Pages read this week", text = function()
        local n = pagesSince(weekStart())
        return n and (plural(n, "page", "pages") .. " this week")
    end },
    { id = "streak", label = "Reading streak", text = function()
        local n = KoboldStats.streakDays()
        return n and (plural(n, "day", "days") .. " in a row")
    end },
    { id = "none", label = "Nothing", text = function() return nil end },
}

-- The line with this id, or nil.
function KoboldStats.line(id)
    for _i, line in ipairs(KoboldStats.LINES) do
        if line.id == id then return line end
    end
    return nil
end

-- Average seconds spent per distinct page, keyed by partial md5 checksum.
-- Books with no statistics are left out of the result.
function KoboldStats.secondsPerPage(md5s)
    local rates = {}
    if #md5s == 0 then return rates end
    local fp = dbFingerprint()
    local key = "rates:" .. table.concat(md5s, ",")
    local m = memo[key]
    if fp and m and m.fp == fp then return m.result end

    withDB(function(conn)
        for _, md5 in ipairs(md5s) do
            if md5:match("^%x+$") then
                local id = firstValue(conn, string.format(
                    "SELECT id FROM book WHERE md5 = '%s' ORDER BY last_open DESC LIMIT 1;", md5), 1)
                if id then
                    local res = conn:exec(string.format(
                        "SELECT SUM(duration), COUNT(DISTINCT page) FROM page_stat WHERE id_book = %d;",
                        tonumber(id)))
                    local total = res and res[1] and tonumber(res[1][1])
                    local pages = res and res[2] and tonumber(res[2][1])
                    if total and pages and pages > 0 then
                        rates[md5] = total / pages
                    end
                end
            end
        end
    end)
    if fp then memo[key] = { fp = fp, result = rates } end
    return rates
end

return KoboldStats
