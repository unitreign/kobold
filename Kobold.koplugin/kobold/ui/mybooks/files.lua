-- kobold/ui/mybooks/files.lua — Kobold
-- The Files tab on the My Books screen: folders under KOReader's home
-- folder, with books and subfolders as rows.
-- Adds methods to the My Books screen class (see mybooks.lua, which
-- installs this with the values it shares).

local CenterContainer = require("ui/widget/container/centercontainer")
local Device          = require("device")
local Geom            = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local InfoMessage     = require("ui/widget/infomessage")
local LeftContainer   = require("ui/widget/container/leftcontainer")
local TextWidget      = require("ui/widget/textwidget")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("gettext")
local lfs             = require("libs/libkoreader-lfs")
local KoboldWidgets   = require("kobold.ui.widgets")

local Screen = Device.screen

return function(KoboldMyBooks, shared)
    local fileChooser = shared.fileChooser

    -- Files tab ------------------------------------------------------------

    -- The home folder set in KOReader (where the library lives).
    function KoboldMyBooks:filesRoot()
        local home = G_reader_settings and G_reader_settings:readSetting("home_dir")
        if home and lfs.attributes(home, "mode") == "directory" then return (home:gsub("/+$", "")) end
        return "/"
    end

    function KoboldMyBooks:currentFolder()
        local dir = self.folder
        if not dir or lfs.attributes(dir, "mode") ~= "directory" then dir = self:filesRoot() end
        if dir ~= "/" then dir = dir:gsub("/+$", "") end
        self.folder = dir
        return dir
    end

    function KoboldMyBooks:parentFolder()
        local dir = self:currentFolder()
        local parent = dir:match("^(.*)/[^/]+/*$")
        if not parent or parent == "" then parent = "/" end
        return parent
    end

    -- Entries of folder `dir`: subfolders, then books KOReader can open, each
    -- sorted by name. Hidden files and book data folders (.sdr) are left out.
    -- Books use the library's entries when known, so status and covers match.
    function KoboldMyBooks:listFolder(dir)
        local DocumentRegistry = require("document/documentregistry")
        local by_file = {}
        for _i, b in ipairs(self.books) do by_file[b.file] = b end
        local dirs, files = {}, {}
        local ok, iter, state = pcall(lfs.dir, dir)
        if not ok then return {} end
        for name in iter, state do
            if name:sub(1, 1) ~= "." and not name:match("%.sdr$") then
                local path = (dir == "/" and "" or dir) .. "/" .. name
                local attr = lfs.attributes(path)
                if attr and attr.mode == "directory" then
                    dirs[#dirs + 1] = { is_dir = true, path = path, name = name }
                elseif attr and attr.mode == "file" and DocumentRegistry:hasProvider(path) then
                    files[#files + 1] = by_file[path] or {
                        file = path, mtime = attr.modification or 0, size = attr.size,
                        title = name:gsub("%.[^%.]+$", ""), title_from_file = true,
                        sort_key = name:lower(), author_list = {},
                        ext = (name:match("%.([^%.]+)$") or ""):upper(),
                    }
                end
            end
        end
        table.sort(dirs, function(a, b) return a.name:lower() < b.name:lower() end)
        table.sort(files, function(a, b) return (a.file:match("[^/]+$") or ""):lower() < (b.file:match("[^/]+$") or ""):lower() end)
        for _i, f in ipairs(files) do dirs[#dirs + 1] = f end
        return dirs
    end

    -- Shows folder `dir`; the page of the folder being left is remembered for
    -- coming back to it.
    function KoboldMyBooks:openFolder(dir)
        self.folder_pages = self.folder_pages or {}
        self.folder_pages[self:currentFolder()] = self.page
        self.folder = dir
        self.page = self.folder_pages[dir] or 1
        self:applyList()
        self:refresh()
    end

    -- KOReader's long-press menu for a folder (rename, delete, cut, copy, set as
    -- home, ...). Changes it makes refresh the file browser, which reloads this
    -- list through hookFileManager.
    function KoboldMyBooks:showFolderMenu(dir)
        local fc = fileChooser()
        local show = fc and fc.showFileDialog
        local ok = false
        if show then
            ok = pcall(show, fc, { path = dir, is_file = false, text = (dir:match("[^/]+$") or dir) .. "/" })
        end
        if not ok then
            UIManager:show(InfoMessage:new{ text = _("The folder menu is not available.") })
        end
    end

    -- A folder row: folder icon, name, and how many items are inside.
    function KoboldMyBooks:buildFolderRow(item)
        local L = self.L
        local _n, _slot, row_h = self:rowSize()
        local count = 0
        local ok, iter, state = pcall(lfs.dir, item.path)
        if ok then
            for name in iter, state do
                if name:sub(1, 1) ~= "." and not name:match("%.sdr$") then count = count + 1 end
            end
        end
        local icon_size = math.floor(L.thumb_w * 0.8)
        local text_w = L.list_w - L.thumb_w - 3 * L.col_gap - L.chevron
        return HorizontalGroup:new{
            CenterContainer:new{
                dimen = Geom:new{ w = L.thumb_w, h = row_h },
                KoboldWidgets.icon("folder", icon_size, { fallback = "appbar.filebrowser" }),
            },
            HorizontalSpan:new{ width = L.col_gap },
            LeftContainer:new{
                dimen = Geom:new{ w = text_w, h = row_h },
                VerticalGroup:new{
                    align = "left",
                    TextWidget:new{ text = item.name, face = KoboldWidgets.face(17), max_width = text_w },
                    VerticalSpan:new{ width = Screen:scaleBySize(4) },
                    TextWidget:new{
                        text = count == 1 and _("1 item") or string.format(_("%d items"), count),
                        face = KoboldWidgets.face(14),
                        fgcolor = KoboldWidgets.subtitleColor(),
                        max_width = text_w,
                    },
                },
            },
            HorizontalSpan:new{ width = L.col_gap },
            CenterContainer:new{
                dimen = Geom:new{ w = L.chevron, h = row_h },
                KoboldWidgets.icon("chevron.right", L.chevron),
            },
        }
    end
end
