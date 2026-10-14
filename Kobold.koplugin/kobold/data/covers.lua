-- kobold/data/covers.lua — Kobold
-- Book covers from the cover browser's cache (BookInfoManager), kept in
-- memory once decoded, plus background extraction for books that have no
-- cover yet. Builds no widgets.
--
-- Memory cache: one entry per book, holding the cover scaled down to the
-- largest size any Kobold screen has asked for. A smaller slot draws the same
-- bitmap and lets ImageWidget shrink it, so a book costs one decode per
-- session, not one per screen or page. Bounded by bytes, oldest use evicted.
-- Dropped entries are not freed by hand: a widget on screen may still draw
-- them, and Blitbuffer frees its memory itself once nothing refers to it.
--
-- Disk cache (cover_disk.lua): every scaled cover is also saved, so after a
-- restart a cover is a file read instead of a decompress and scale.

local Device          = require("device")
local Event           = require("ui/event")
local UIManager       = require("ui/uimanager")
local logger          = require("logger")
local lfs             = require("libs/libkoreader-lfs")
local KoboldBookInfo  = require("kobold.data.bookinfo")
local KoboldCoverDisk = require("kobold.data.cover_disk")

local Screen = Device.screen

local KoboldCovers = {}

local BYTE_BUDGET = 12 * 1024 * 1024

local cache = {}       -- [file] = { bb, bytes, used, full } or false (no cover)
local cache_bytes = 0
local use_counter = 0
local last_fingerprint = nil
local last_check = 0

local function bim()
    local ok, BIM = pcall(require, "bookinfomanager")
    if ok and BIM then return BIM end
    return nil
end

local function bbBytes(bb)
    local ok, n = pcall(function() return tonumber(bb.stride) * bb:getHeight() end)
    if ok and n then return n end
    return bb:getWidth() * bb:getHeight()
end

-- When the cover browser's database changes (new covers extracted), books
-- remembered as "no cover" are tried again. Checked at most once a second.
local function checkFingerprint()
    local now = os.time()
    if now == last_check then return end
    last_check = now
    local fp = KoboldBookInfo.fingerprint()
    if fp ~= last_fingerprint then
        last_fingerprint = fp
        for file, entry in pairs(cache) do
            if entry == false then cache[file] = nil end
        end
    end
end

local function evict()
    while cache_bytes > BYTE_BUDGET do
        local oldest_file, oldest_used = nil, math.huge
        for file, entry in pairs(cache) do
            if entry and entry.used < oldest_used then
                oldest_file, oldest_used = file, entry.used
            end
        end
        if not oldest_file then return end
        cache_bytes = cache_bytes - cache[oldest_file].bytes
        cache[oldest_file] = nil
    end
end

local function store(file, bb, full)
    local old = cache[file]
    if old then cache_bytes = cache_bytes - old.bytes end
    use_counter = use_counter + 1
    local entry = { bb = bb, bytes = bbBytes(bb), used = use_counter, full = full }
    cache[file] = entry
    cache_bytes = cache_bytes + entry.bytes
    evict()
end

-- Largest scale (<= 1 means shrink) that fits a cw x ch cover inside w x h.
local function fitScale(cw, ch, w, h)
    return math.min(w / cw, h / ch)
end

-- Cover bitmap for `file`, at least as large as its fit inside w x h (or the
-- original when the original is smaller), or nil when there is no cover.
-- The bitmap belongs to this cache: draw it with image_disposable = false.
function KoboldCovers.get(file, w, h)
    if not file then return nil end
    checkFingerprint()
    local entry = cache[file]
    if entry == false then return nil end
    if entry then
        local bb = entry.bb
        if entry.full or fitScale(bb:getWidth(), bb:getHeight(), w, h) <= 1.001 then
            use_counter = use_counter + 1
            entry.used = use_counter
            return bb
        end
    end

    -- Saved by an earlier session, already scaled: a plain file read.
    local mtime = lfs.attributes(file, "modification") or 0
    local saved, saved_full = KoboldCoverDisk.load(file, mtime)
    if saved and (saved_full or fitScale(saved:getWidth(), saved:getHeight(), w, h) <= 1.001) then
        store(file, saved, saved_full)
        return saved
    end

    local BIM = bim()
    if not BIM then return nil end
    local ok, bi = pcall(function() return BIM:getBookInfo(file, true) end)
    if not (ok and bi and bi.cover_bb and bi.has_cover and bi.cover_fetched) then
        cache[file] = false
        return nil
    end
    local src = bi.cover_bb
    local sw, sh = src:getWidth(), src:getHeight()
    local scale = fitScale(sw, sh, w, h)
    if scale >= 1 then
        store(file, src, true)
        KoboldCoverDisk.save(file, mtime, src, true)
        return src
    end
    local ok_scale, bb = pcall(function()
        return src:scale(math.max(1, math.floor(sw * scale)), math.max(1, math.floor(sh * scale)))
    end)
    if not ok_scale or not bb then bb = src end
    store(file, bb, bb == src)
    KoboldCoverDisk.save(file, mtime, bb, bb == src)
    return bb
end

-- Size of the cover fitted inside w x h keeping its shape, or nil, nil when
-- there is no cover.
function KoboldCovers.fittedSize(file, w, h)
    local bb = KoboldCovers.get(file, w, h)
    if not bb then return nil, nil end
    local cw, ch = bb:getWidth(), bb:getHeight()
    local scale = fitScale(cw, ch, w, h)
    return math.max(1, math.floor(cw * scale)), math.max(1, math.floor(ch * scale))
end

-- Cover size asked for when extracting: the largest Kobold slot (a Home top
-- row cover, a quarter of the screen width at 2:3). Smaller slots shrink it.
local function coverSpecs()
    local w = math.floor(math.min(Screen:getWidth(), Screen:getHeight()) / 4)
    return { max_cover_w = w, max_cover_h = math.floor(w * 1.5) }
end

-- Files to extract: not read by the cover browser yet, or read without a
-- cover attempt. A book whose cover was tried and failed is not retried.
local function needsExtraction(row)
    return not row or not row.cover_fetched
end

-- True while the cover browser runs a background job (ours or anyone's).
local function busy(BIM)
    if not BIM.isExtractingInBackground then return false end
    local ok, b = pcall(function() return BIM:isExtractingInBackground() end)
    return ok and b
end

local requested = {}   -- [file] = true once asked for this session
local watch = nil      -- { fn = scheduled poll, until_time }

local function stopWatch()
    if watch then
        UIManager:unschedule(watch.fn)
        watch = nil
    end
end

-- Polls every 2 seconds until the cover browser's background job ends, then
-- broadcasts KoboldCoversUpdated once, so every open Kobold screen redraws
-- with the new covers (whichever screen asked for them).
local function startWatch(BIM, budget_s)
    stopWatch()
    local w = { until_time = os.time() + budget_s }
    w.fn = function()
        if busy(BIM) and os.time() < w.until_time then
            UIManager:scheduleIn(2, w.fn)
            return
        end
        watch = nil
        last_check = 0  -- re-read the fingerprint now, so new covers load
        UIManager:broadcastEvent(Event:new("KoboldCoversUpdated"))
    end
    watch = w
    UIManager:scheduleIn(2, w.fn)
end

-- Asks the cover browser to extract, in the background, the covers of any
-- of `files` that have none yet (the books on the screen right now). Open
-- Kobold screens get KoboldCoversUpdated when it is done. Does nothing while a
-- background job is already running, so it never interrupts one; each file
-- is asked for at most once per session.
function KoboldCovers.ensure(files)
    local BIM = bim()
    if not BIM or not BIM.extractInBackground or busy(BIM) then return end
    local map = KoboldBookInfo.getMap()
    local specs = coverSpecs()
    local list = {}
    for _i, file in ipairs(files) do
        if file and not requested[file] and needsExtraction(map[file]) then
            requested[file] = true
            list[#list + 1] = { filepath = file, cover_specs = specs }
        end
    end
    if #list == 0 then return end
    local ok, err = pcall(function() BIM:extractInBackground(list) end)
    if not ok then
        logger.warn("Kobold: cover extraction failed to start:", tostring(err))
        return
    end
    startWatch(BIM, 120)
end

-- Queues every book in `files` that has no cover yet for background
-- extraction (Kobold Settings > Prepare covers). Returns the number queued,
-- 0 when all have covers, or nil when the cover browser is busy or missing.
function KoboldCovers.prepareAll(files)
    local BIM = bim()
    if not BIM or not BIM.extractInBackground or busy(BIM) then return nil end
    local map = KoboldBookInfo.getMap()
    local specs = coverSpecs()
    local list = {}
    for _i, file in ipairs(files) do
        if needsExtraction(map[file]) then
            requested[file] = true
            list[#list + 1] = { filepath = file, cover_specs = specs }
        end
    end
    if #list == 0 then return 0 end
    local ok = pcall(function() BIM:extractInBackground(list) end)
    if not ok then return nil end
    -- A large library can take a long time; watch for up to an hour.
    startWatch(BIM, 3600)
    return #list
end

return KoboldCovers
