-- kobold/data/home.lua — Kobold
-- Assembles the data the home screen needs. Builds no widgets.

local lfs             = require("libs/libkoreader-lfs")
local KoboldLibrary   = require("kobold.data.library")
local KoboldPerf      = require("kobold.data.perf")
local KoboldPrefs     = require("kobold.data.prefs")
local KoboldStats     = require("kobold.data.stats")

local KoboldHomeData = {}

-- Books from ReadHistory that are started but not finished (most recent first).
-- hours_left is estimated from the book's own reading stats (pages left times
-- average seconds per page), or nil when KOReader has no stats for the book.
function KoboldHomeData.getCurrentlyReading(n)
    local ok, RH = pcall(require, "readhistory")
    if not ok or not RH or not RH.hist then return {} end

    local picked = {}
    for _, entry in ipairs(RH.hist) do
        if #picked >= n then break end
        local file = entry.file
        if file and lfs.attributes(file, "mode") == "file" then
            local info = KoboldLibrary.getDocInfoCached(file) or {}
            local pf = info.percent
            if pf and pf > 0 and pf < 1 and info.status ~= "complete" then
                picked[#picked + 1] = { file = file, percent = pf, pages = info.pages, md5 = info.md5 }
            end
        end
    end

    local md5s = {}
    for _, b in ipairs(picked) do
        if b.md5 then md5s[#md5s + 1] = b.md5 end
    end
    local rates = KoboldStats.secondsPerPage(md5s)

    for _, b in ipairs(picked) do
        local rate = b.md5 and rates[b.md5]
        if rate and b.pages then
            local pages_left = b.pages * (1 - b.percent)
            b.hours_left = pages_left * rate / 3600
        end
    end
    return picked
end

-- The most recently opened book from ReadHistory that still exists, or nil.
function KoboldHomeData.getLatestRead()
    local ok, RH = pcall(require, "readhistory")
    if not ok or not RH or not RH.hist then return nil end
    for _, entry in ipairs(RH.hist) do
        if entry.file and lfs.attributes(entry.file, "mode") == "file" then
            local info = KoboldLibrary.getDocInfoCached(entry.file) or {}
            return { file = entry.file, title = KoboldLibrary.getTitle(entry.file, info) }
        end
    end
    return nil
end

-- A random KOReader collection (ReadCollection), or nil when none exist.
local right_pick = nil  -- { right = the right column data }, see getHomeData

-- True when every book in the kept pick still exists, and its collection
-- (if any) still holds them.
local function stillValid(pick, all_files)
    local right = pick.right
    if right.collection then
        local ok, RC = pcall(require, "readcollection")
        local coll = ok and RC and RC.coll and RC.coll[right.collection]
        if not coll then return false end
        for _i, f in ipairs(right.files) do
            if not coll[f] or lfs.attributes(f, "mode") ~= "file" then return false end
        end
        return #right.files > 0
    end
    local all = {}
    for _i, f in ipairs(all_files) do all[f] = true end
    for _i, f in ipairs(right.files) do
        if not all[f] then return false end
    end
    return true
end

local finishHomeData

local function getRandomCollection()
    local ok, RC = pcall(require, "readcollection")
    if not ok or not RC or not RC.coll then return nil end

    local names = {}
    for name, items in pairs(RC.coll) do
        if next(items) ~= nil then
            names[#names + 1] = name
        end
    end
    if #names == 0 then return nil end

    local name = names[math.random(#names)]
    local files = {}
    for _, item in pairs(RC.coll[name]) do
        if item.file and lfs.attributes(item.file, "mode") == "file" then
            files[#files + 1] = item.file
        end
    end
    if #files == 0 then return nil end
    return { name = name, files = files }
end

-- Reading stats line `pref` ("stats_line1" or "stats_line2") as set in
-- Kobold Settings: { text, action }, or nil when it shows nothing (stat set
-- to Nothing or unavailable, or empty custom text).
function KoboldHomeData.statsLine(pref)
    local text
    if KoboldPrefs.get(pref .. "_kind") == "text" then
        text = KoboldPrefs.get(pref .. "_text")
        if type(text) ~= "string" or text:match("^%s*$") then text = nil end
    else
        local line = KoboldStats.line(KoboldPrefs.get(pref))
        text = line and line.text() or nil
    end
    if not text then return nil end
    return { text = text, action = KoboldPrefs.get(pref .. "_action") }
end

-- Everything the home screen needs in one call:
--   reading  = { { file, percent }, ... }   (up to 4)
--   my_books = { file, ... }                (3 most recently modified)
--   right    = { title, subtitle, files, collection } (a random collection, with
--              its ReadCollection name; or More Books, with no collection)
--   total    = number of books found
--   stats    = { line1, line2 } for the reading stats block, each
--              { text, action } or nil (see statsLine)
function KoboldHomeData.getHomeData()
    local t = KoboldPerf.start()
    local books = KoboldLibrary.scan()

    local all_files = {}
    for i, b in ipairs(books) do all_files[i] = b.file end

    local my_books = {}
    for i = 1, math.min(3, #all_files) do my_books[i] = all_files[i] end

    local my_set = {}
    for _, f in ipairs(my_books) do my_set[f] = true end

    -- The random pick is kept for the whole KOReader session, so Home does
    -- not change under the reader's eyes each time a book closes. It is
    -- picked again only when its collection or books are gone.
    if right_pick and stillValid(right_pick, all_files) then
        local data_right = right_pick.right
        if not data_right.collection then data_right.subtitle = #all_files .. " BOOKS" end
        return finishHomeData(t, all_files, my_books, data_right)
    end

    local right
    local coll = getRandomCollection()
    if coll then
        right = {
            title = coll.name,
            subtitle = "COLLECTION",
            collection = coll.name,  -- its key in ReadCollection
            files = KoboldLibrary.pickRandom(coll.files, 3),
        }
    else
        right = {
            title = "More Books",
            subtitle = #all_files .. " BOOKS",
            files = KoboldLibrary.pickRandom(all_files, 3, my_set),
        }
    end

    right_pick = { right = right }
    return finishHomeData(t, all_files, my_books, right)
end

-- The rest of the Home data around the right column `right`.
finishHomeData = function(t, all_files, my_books, right)
    local data = {
        reading = KoboldHomeData.getCurrentlyReading(4),
        latest = KoboldHomeData.getLatestRead(),
        stats = {
            line1 = KoboldHomeData.statsLine("stats_line1"),
            line2 = KoboldHomeData.statsLine("stats_line2"),
        },
        my_books = my_books,
        right = right,
        total = #all_files,
    }
    KoboldPerf.log("home data", t, "books=%d", #all_files)
    return data
end

return KoboldHomeData
