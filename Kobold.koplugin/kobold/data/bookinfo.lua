-- kobold/data/bookinfo.lua — Kobold
-- Title, authors, series and cover state for every book the cover browser
-- (BookInfoManager) has already read, fetched in ONE query instead of one
-- lookup per book. The result is also saved to a small file, tagged with the
-- size and time of the cover browser's database; while that database is
-- unchanged, a cold start reads the file and runs no query at all.
-- Builds no widgets.

local lfs             = require("libs/libkoreader-lfs")
local logger          = require("logger")
local KoboldPerf      = require("kobold.data.perf")

local KoboldBookInfo = {}

local SNAPSHOT_VERSION = 1

local memo = nil  -- { fingerprint = string, map = { [path] = row } }

local function settingsDir()
    local ok, DataStorage = pcall(require, "datastorage")
    if ok and DataStorage then return DataStorage end
    return nil
end

-- "v1:<size>:<mtime>" of bookinfo_cache.sqlite3, or nil when it is missing.
-- Any write by the cover browser (a new cover, a re-read) changes it.
function KoboldBookInfo.fingerprint()
    local DataStorage = settingsDir()
    if not DataStorage then return nil end
    local path = DataStorage:getSettingsDir() .. "/bookinfo_cache.sqlite3"
    local attr = lfs.attributes(path)
    if not attr or attr.mode ~= "file" then return nil end
    return string.format("v%d:%d:%d", SNAPSHOT_VERSION, attr.size or 0, attr.modification or 0)
end

local function snapshotStore()
    local DataStorage = settingsDir()
    local ok_p, Persist = pcall(require, "persist")
    if not (DataStorage and ok_p and Persist) then return nil end
    local dir = DataStorage:getDataDir() .. "/cache"
    if lfs.attributes(dir, "mode") ~= "directory" then pcall(lfs.mkdir, dir) end
    local ok, store = pcall(function()
        return Persist:new{ path = dir .. "/kobold_bookinfo.dat", codec = "zstd" }
    end)
    if ok then return store end
    return nil
end

-- Columns read per book. The second list is a fallback in case a future
-- cover browser drops one of the optional columns.
local QUERIES = {
    { sql = "SELECT directory, filename, title, authors, series, series_index, has_cover, cover_fetched"
        .. " FROM bookinfo WHERE in_progress = 0;",
      cols = { "title", "authors", "series", "series_index", "has_cover", "cover_fetched" } },
    { sql = "SELECT directory, filename, title, authors FROM bookinfo WHERE in_progress = 0;",
      cols = { "title", "authors" } },
}

-- One query over the cover browser's bookinfo table. Returns
-- { [directory .. filename] = { title, authors, series, series_index,
-- has_cover, cover_fetched } }, or nil when the database cannot be read.
local function queryAll()
    local ok_bim, BIM = pcall(require, "bookinfomanager")
    if not ok_bim or not BIM or type(BIM.openDbConnection) ~= "function" then return nil end
    if not pcall(function() BIM:openDbConnection() end) then return nil end
    local conn = BIM.db_conn
    if not conn or type(conn.exec) ~= "function" then return nil end

    for _i, q in ipairs(QUERIES) do
        local ok, rows = pcall(function() return conn:exec(q.sql) end)
        if ok then
            local map = {}
            if not rows then return map end  -- empty table
            -- exec returns columns: rows[column][row]. The stored directory
            -- ends with "/", so directory .. filename is the full path.
            local n = rows[1] and #rows[1] or 0
            for r = 1, n do
                local row = {}
                for c, name in ipairs(q.cols) do
                    local v = rows[c + 2] and rows[c + 2][r]
                    if v ~= nil then row[name] = type(v) == "cdata" and tonumber(v) or v end
                end
                map[(rows[1][r] or "") .. (rows[2][r] or "")] = row
            end
            return map
        end
        logger.warn("Kobold: bookinfo query failed:", tostring(rows))
    end
    return nil
end

-- The whole map, from memory, the saved file, or a fresh query, in that
-- order. Always a table (empty when the cover browser is not available).
function KoboldBookInfo.getMap()
    local fingerprint = KoboldBookInfo.fingerprint()
    if not fingerprint then return {} end
    if memo and memo.fingerprint == fingerprint then return memo.map end

    local t = KoboldPerf.start()
    local store = snapshotStore()
    if store then
        local ok, saved = pcall(store.load, store)
        if ok and type(saved) == "table" and saved.fingerprint == fingerprint
            and type(saved.map) == "table" then
            memo = { fingerprint = fingerprint, map = saved.map }
            KoboldPerf.log("bookinfo snapshot", t)
            return saved.map
        end
    end

    local map = queryAll()
    if not map then return {} end
    memo = { fingerprint = fingerprint, map = map }
    if store then pcall(store.save, store, { fingerprint = fingerprint, map = map }) end
    KoboldPerf.log("bookinfo query", t)
    return map
end

-- The row for one book, or nil when the cover browser has not read it.
function KoboldBookInfo.get(file)
    return KoboldBookInfo.getMap()[file]
end

return KoboldBookInfo
