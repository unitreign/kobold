-- kobold/data/library.lua — Kobold
-- Library scanning and sidecar reads. Builds no widgets.

local lfs             = require("libs/libkoreader-lfs")
local KoboldBookInfo  = require("kobold.data.bookinfo")
local KoboldPerf      = require("kobold.data.perf")

local KoboldLibrary = {}

local BOOK_EXTENSIONS = {
    epub = true, pdf = true, mobi = true, azw = true, azw3 = true,
    fb2 = true, cbz = true, cbr = true, djvu = true, txt = true,
    rtf = true, htm = true, html = true,
}

local SCAN_MAX_DEPTH = 5
local SCAN_MAX_FILES = 3000
-- The scan is redone only when a folder it walked has changed (a book or a
-- sidecar folder added, removed or renamed). This timer is a backstop for
-- storage that does not update folder times.
local SCAN_SAFETY_TTL = 10 * 60  -- seconds

-- {
--   time  = os.time() of the walk,
--   books = { { file, mtime, size }, ... } newest first,
--   dirs  = { [dir] = mtime } of every folder walked,
--   sdr   = { [dir] = { ["Name.sdr"] = true } } sidecar folders seen per folder,
--   sdr_by_name = true when sidecars can be found from `sdr` alone,
-- }
local library_cache = nil

math.randomseed(os.time())

local function isBookFile(name)
    local ext = name:match("%.([^%./]+)$")
    return ext ~= nil and BOOK_EXTENSIONS[ext:lower()] == true
end

-- True when every sidecar must sit next to its book ("Name.sdr" in the
-- book's folder), so the folder listings the walk already made are enough
-- to tell which books have one. Not true when KOReader keeps sidecars in its
-- own docsettings or hash folders; then each book is checked on its own.
local function sidecarsByName()
    local where = G_reader_settings and G_reader_settings:readSetting("document_metadata_folder") or "doc"
    if where ~= "doc" then return false end
    local ok, DataStorage = pcall(require, "datastorage")
    if not ok or not DataStorage then return false end
    for _i, method in ipairs({ "getDocSettingsDir", "getDocSettingsHashDir" }) do
        if DataStorage[method] then
            local ok_dir, dir = pcall(DataStorage[method], DataStorage)
            if ok_dir and dir and lfs.attributes(dir, "mode") == "directory" then return false end
        end
    end
    return true
end

local function dirsChanged(dirs)
    for dir, mtime in pairs(dirs) do
        if lfs.attributes(dir, "modification") ~= mtime then return true end
    end
    return false
end

-- Walks the KOReader home directory (bounded by depth and file count) and
-- returns books sorted by modification time, newest first:
-- { { file, mtime, size }, ... }. Cached until a walked folder changes.
function KoboldLibrary.scan()
    local now = os.time()
    if library_cache and now - library_cache.time < SCAN_SAFETY_TTL
        and not dirsChanged(library_cache.dirs) then
        return library_cache.books
    end

    local t = KoboldPerf.start()
    local books, dirs, sdr, dir_count = {}, {}, {}, 0
    local home = G_reader_settings and G_reader_settings:readSetting("home_dir")

    if home and lfs.attributes(home, "mode") == "directory" then
        local function walk(dir, depth)
            if depth > SCAN_MAX_DEPTH or #books >= SCAN_MAX_FILES then return end
            dirs[dir] = lfs.attributes(dir, "modification")
            dir_count = dir_count + 1
            local ok, iter, state = pcall(lfs.dir, dir)
            if not ok then return end
            local sdr_here = {}
            sdr[dir] = sdr_here
            for name in iter, state do
                if name:sub(1, 1) ~= "." and #books < SCAN_MAX_FILES then
                    local path = dir .. "/" .. name
                    -- One stat per entry: mode, time and size together.
                    local attr = lfs.attributes(path)
                    if attr and attr.mode == "directory" then
                        if name:sub(-4) == ".sdr" then
                            sdr_here[name] = true  -- a sidecar, not a folder of books
                        else
                            walk(path, depth + 1)
                        end
                    elseif attr and attr.mode == "file" and isBookFile(name) then
                        books[#books + 1] = {
                            file = path,
                            mtime = attr.modification or 0,
                            size = attr.size,
                        }
                    end
                end
            end
        end
        walk(home, 0)
    end

    table.sort(books, function(a, b) return a.mtime > b.mtime end)
    library_cache = { time = now, books = books, dirs = dirs, sdr = sdr, sdr_by_name = sidecarsByName() }
    KoboldPerf.log("library scan", t, "books=%d dirs=%d", #books, dir_count)
    return books
end

-- Forgets the cached scan, so the next scan() reads the disk again (after a
-- book was deleted, for example).
function KoboldLibrary.invalidate()
    library_cache = nil
end

-- A stamp that changes whenever the book's sidecar changes: the sidecar
-- file's modification time, or 0 for a sidecar folder without a metadata
-- file. nil when the book has no sidecar (it was never opened).
function KoboldLibrary.sidecarStamp(file)
    local dir, base = file:match("^(.*)/([^/]+)$")
    local stem = base and (base:match("^(.*)%.[^%.]+$") or base)
    local cache = library_cache
    if dir and cache and cache.sdr_by_name and cache.sdr[dir] then
        if not cache.sdr[dir][stem .. ".sdr"] then return nil end
        local ext = base:match("%.([^%.]+)$") or ""
        local sdr_dir = dir .. "/" .. stem .. ".sdr/metadata."
        return lfs.attributes(sdr_dir .. ext .. ".lua", "modification")
            or lfs.attributes(sdr_dir .. ext:lower() .. ".lua", "modification")
            or 0
    end

    -- Sidecars may live elsewhere: ask KOReader, one book at a time.
    local ok_ds, DocSettings = pcall(require, "docsettings")
    if not ok_ds or not DocSettings then return 0 end
    if DocSettings.findSidecarFile then
        local ok, path = pcall(function() return DocSettings:findSidecarFile(file) end)
        if ok then
            if not path then return nil end
            return lfs.attributes(path, "modification") or 0
        end
    end
    if DocSettings.hasSidecarFile then
        local ok, has = pcall(function() return DocSettings:hasSidecarFile(file) end)
        if ok and not has then return nil end
    end
    -- Unknown change time: a new stamp every call, so it is always re-read.
    return "t" .. os.time()
end

-- Returns up to n random values, skipping any value present in `exclude`.
function KoboldLibrary.pickRandom(values, n, exclude)
    local pool = {}
    for _, v in ipairs(values) do
        if not (exclude and exclude[v]) then
            pool[#pool + 1] = v
        end
    end
    local out = {}
    while #pool > 0 and #out < n do
        out[#out + 1] = table.remove(pool, math.random(#pool))
    end
    return out
end

-- Title, authors and series from the cover browser's metadata (one batched
-- read for the whole library, see bookinfo.lua), or nil when it has nothing
-- for the book.
function KoboldLibrary.getCachedProps(file)
    return KoboldBookInfo.get(file)
end

local function nonEmpty(s)
    if type(s) == "string" and s ~= "" then return s end
    return nil
end

-- A book's title: the sidecar's title (`info` from getDocInfo, if already
-- read), then the cover browser's cache, then the file name.
function KoboldLibrary.getTitle(file, info)
    local props = KoboldLibrary.getCachedProps(file) or {}
    return nonEmpty(info and info.title) or nonEmpty(props.title)
        or file:match("([^/]+)%.[^%.]+$") or file
end

-- Reads progress, status, title, authors, series, page count and md5 from the
-- book's sidecar file.
function KoboldLibrary.getDocInfo(file)
    local ok_ds, DocSettings = pcall(require, "docsettings")
    if not ok_ds or not DocSettings then return nil end
    local ok_open, ds = pcall(function() return DocSettings:open(file) end)
    if not ok_open or not ds then return nil end
    local percent = ds:readSetting("percent_finished")
    local summary = ds:readSetting("summary")
    local props = ds:readSetting("doc_props")
    local pages = ds:readSetting("doc_pages")
    local md5 = ds:readSetting("partial_md5_checksum")
    pcall(function() ds:close() end)
    -- Corrections made in KOReader's Book information are kept apart from
    -- the book, in custom_metadata.lua; they win over the book's own.
    pcall(function()
        local custom_file = DocSettings:findCustomMetadataFile(file)
        if not custom_file then return end
        local custom = DocSettings.openSettingsFile(custom_file):readSetting("custom_props")
        if type(custom) ~= "table" then return end
        props = type(props) == "table" and props or {}
        local merged = {}
        for k, v in pairs(props) do merged[k] = v end
        for k, v in pairs(custom) do merged[k] = v end
        props = merged
    end)
    return {
        percent = percent,
        status = type(summary) == "table" and summary.status or nil,
        title = type(props) == "table" and props.title or nil,
        authors = type(props) == "table" and props.authors or nil,
        series = type(props) == "table" and props.series or nil,
        series_index = type(props) == "table" and props.series_index or nil,
        pages = type(pages) == "number" and pages or nil,
        md5 = type(md5) == "string" and md5 or nil,
    }
end

-- getDocInfo, remembered until the book's sidecar changes (its stamp, see
-- sidecarStamp). nil for a book with no sidecar, without reading anything.
-- Home and My Books both read through this, so a sidecar is parsed once.
local docinfo_memo = {}  -- [file] = { stamp, info }

-- Forgets every remembered sidecar read and the library scan, after
-- KOReader changed a book's metadata (see widgets.lua).
function KoboldLibrary.forgetDocInfo()
    docinfo_memo = {}
    library_cache = nil
end

function KoboldLibrary.getDocInfoCached(file)
    local stamp = KoboldLibrary.sidecarStamp(file)
    if stamp == nil then
        docinfo_memo[file] = nil
        return nil
    end
    local m = docinfo_memo[file]
    if m and m.stamp == stamp then return m.info end
    local info = KoboldLibrary.getDocInfo(file)
    docinfo_memo[file] = { stamp = stamp, info = info }
    return info
end

return KoboldLibrary
