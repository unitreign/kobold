-- kobold/data/cover_disk.lua — Kobold
-- Covers already scaled for Kobold, saved as raw bitmaps in KOReader's cache
-- folder, so the first screens after a restart read them back (a plain file
-- read) instead of asking the cover browser to decompress and scale them
-- again. Builds no widgets.
--
-- Each file holds one book's cover: a header with the book's path, the book
-- file's modification time and the bitmap's size and type, then the pixels.
-- A file whose header does not match (another book with the same hash, a
-- changed book, a half-written file) is a miss, never a wrong cover. The
-- folder is kept under a byte limit by removing the oldest files.

local Blitbuffer      = require("ffi/blitbuffer")
local ffi             = require("ffi")
local lfs             = require("libs/libkoreader-lfs")
local logger          = require("logger")

local KoboldCoverDisk = {}

local MAGIC     = "KBC1"
local MAX_BYTES = 48 * 1024 * 1024  -- trimmed down to TRIM_TO when over
local TRIM_TO   = 36 * 1024 * 1024

local dir_path = nil    -- resolved folder, or false when unavailable
local trimmed = false   -- the size check runs once per session

local function dir()
    if dir_path ~= nil then return dir_path or nil end
    dir_path = false
    local ok, DataStorage = pcall(require, "datastorage")
    if not ok or not DataStorage then return nil end
    local cache = DataStorage:getDataDir() .. "/cache"
    local d = cache .. "/kobold_covers"
    if lfs.attributes(cache, "mode") ~= "directory" then pcall(lfs.mkdir, cache) end
    if lfs.attributes(d, "mode") ~= "directory" then pcall(lfs.mkdir, d) end
    if lfs.attributes(d, "mode") == "directory" then dir_path = d end
    return dir_path or nil
end

-- djb2 hash of the path, as 8 hex digits. Lua 5.1 arithmetic only (no
-- bitwise operators); the value stays exact in a double.
local function hash(s)
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
    return string.format("%08x", h)
end

local function pathFor(file)
    local d = dir()
    return d and (d .. "/" .. hash(file) .. ".bb") or nil
end

-- Removes the oldest files until the folder is under TRIM_TO, when it has
-- grown past MAX_BYTES.
local function trim()
    if trimmed then return end
    trimmed = true
    local d = dir()
    if not d then return end
    local files, total = {}, 0
    for name in lfs.dir(d) do
        if name:sub(-3) == ".bb" then
            local attr = lfs.attributes(d .. "/" .. name)
            if attr and attr.mode == "file" then
                files[#files + 1] = { path = d .. "/" .. name, size = attr.size, time = attr.modification }
                total = total + attr.size
            end
        end
    end
    if total <= MAX_BYTES then return end
    table.sort(files, function(a, b) return a.time < b.time end)
    for _i, f in ipairs(files) do
        if total <= TRIM_TO then break end
        if os.remove(f.path) then total = total - f.size end
    end
end

-- Saved cover for `file` whose book file time is `mtime`: the bitmap and
-- whether it is the full-size original. nil when there is none.
function KoboldCoverDisk.load(file, mtime)
    local path = pathFor(file)
    if not path then return nil end
    local f = io.open(path, "rb")
    if not f then return nil end
    local ok, bb, full = pcall(function()
        if f:read("*l") ~= MAGIC or f:read("*l") ~= file then return nil end
        local saved_mtime, w, h, stride, btype, is_full =
            (f:read("*l") or ""):match("^(%d+) (%d+) (%d+) (%d+) (%d+) ([01])$")
        if not saved_mtime or tonumber(saved_mtime) ~= mtime then return nil end
        w, h, stride, btype = tonumber(w), tonumber(h), tonumber(stride), tonumber(btype)
        local data = f:read(stride * h)
        if not data or #data ~= stride * h then return nil end
        local out = Blitbuffer.new(w, h, btype)
        local out_stride = tonumber(out.stride)
        local dst = ffi.cast("uint8_t *", out.data)
        if out_stride == stride then
            ffi.copy(dst, data, #data)
        else
            local row = math.min(stride, out_stride)
            for y = 0, h - 1 do
                ffi.copy(dst + y * out_stride, data:sub(y * stride + 1, y * stride + row), row)
            end
        end
        return out, is_full == "1"
    end)
    f:close()
    if ok and bb then return bb, full end
    return nil
end

-- Saves `bb` as the cover of `file` (book file time `mtime`). Written to a
-- temporary file first, so a crash never leaves a half-written cover.
function KoboldCoverDisk.save(file, mtime, bb, full)
    local path = pathFor(file)
    if not path then return end
    trim()
    local ok, err = pcall(function()
        local w, h, stride = bb:getWidth(), bb:getHeight(), tonumber(bb.stride)
        local tmp = path .. ".tmp"
        local f = assert(io.open(tmp, "wb"))
        f:write(MAGIC, "\n", file, "\n",
            string.format("%d %d %d %d %d %s\n", mtime, w, h, stride, bb:getType(), full and "1" or "0"))
        f:write(ffi.string(bb.data, stride * h))
        f:close()
        os.remove(path)
        assert(os.rename(tmp, path))
    end)
    if not ok then logger.dbg("Kobold: cover save failed:", tostring(err)) end
end

return KoboldCoverDisk
