-- kobold/ui/mybooks/rows.lua — Kobold
-- Building the list and grid on the My Books screen: book, series, group
-- and empty rows, the side bar, the cover grid and its page footer.
-- Adds methods to the My Books screen class (see mybooks.lua, which
-- installs this with the values it shares).

local Blitbuffer        = require("ffi/blitbuffer")
local CenterContainer   = require("ui/widget/container/centercontainer")
local Device            = require("device")
local Geom              = require("ui/geometry")
local HorizontalGroup   = require("ui/widget/horizontalgroup")
local HorizontalSpan    = require("ui/widget/horizontalspan")
local LeftContainer     = require("ui/widget/container/leftcontainer")
local LineWidget        = require("ui/widget/linewidget")
local RightContainer    = require("ui/widget/container/rightcontainer")
local TextBoxWidget     = require("ui/widget/textboxwidget")
local TextWidget        = require("ui/widget/textwidget")
local VerticalGroup     = require("ui/widget/verticalgroup")
local VerticalSpan      = require("ui/widget/verticalspan")
local _                 = require("kobold.l10n")
local KoboldMyBooksData = require("kobold.data.mybooks")
local KoboldWidgets     = require("kobold.ui.widgets")

local Screen = Device.screen

return function(KoboldMyBooks, shared)
    local COVER_RATIO = shared.COVER_RATIO
    local countText = shared.countText

    -- Status text in the right column: Unread, 42% read, or Finished.
    local function statusText(item)
        if item.status == "finished" then return _("Finished") end
        if item.status == "reading" then
            if item.percent then
                return _.T(_("%1% read"), math.floor(item.percent * 100))
            end
            return _("Reading")
        end
        return _("Unread")
    end

    -- One book row: cover, title over authors, and status over format and size
    -- on the right, with the "…" menu button under them. Exactly row_h tall.
    local SERIES_MAX_CHARS = 26

    -- "NAME - N" for the series line, the name cut after SERIES_MAX_CHARS.
    local function seriesLine(item)
        local util = require("util")
        local name = item.series:upper()
        local chars = util.splitToChars and util.splitToChars(name) or nil
        if chars and #chars > SERIES_MAX_CHARS then
            name = table.concat(chars, "", 1, SERIES_MAX_CHARS):gsub("%s+$", "") .. "..."
        elseif not chars and #name > SERIES_MAX_CHARS then
            name = name:sub(1, SERIES_MAX_CHARS) .. "..."
        end
        if item.series_index then
            local n = item.series_index
            if n == math.floor(n) then n = math.floor(n) end
            name = name .. " - " .. tostring(n)
        end
        return name
    end

    function KoboldMyBooks:buildBookRow(item)
        local L = self.L
        local face_title = KoboldWidgets.face(17)
        local title = TextBoxWidget:new{
            text = item.title, face = face_title, width = L.text_w, alignment = "left",
        }
        if title:getSize().h > L.title_max_h then
            title:free()
            title = TextBoxWidget:new{
                text = item.title, face = face_title, width = L.text_w, alignment = "left",
                height = L.title_max_h, height_overflow_show_ellipsis = true,
            }
        end

        local middle = VerticalGroup:new{ align = "left", title }
        -- Series under the title, in small capitals: the name cut short, then
        -- its number ("THE SAGA OF TANYA... - 1").
        if item.series then
            middle[#middle + 1] = VerticalSpan:new{ width = Screen:scaleBySize(2) }
            middle[#middle + 1] = TextWidget:new{
                text = seriesLine(item),
                face = KoboldWidgets.face(12),
                max_width = L.text_w,
            }
        end
        if item.authors then
            middle[#middle + 1] = VerticalSpan:new{ width = Screen:scaleBySize(4) }
            middle[#middle + 1] = TextWidget:new{
                text = item.authors,
                face = KoboldWidgets.face(14),
                fgcolor = KoboldWidgets.subtitleColor(),
                max_width = L.text_w,
            }
        end

        local size = KoboldMyBooksData.formatSize(item.size)
        local format = item.ext ~= "" and item.ext or nil
        if format and size then format = format .. " · " .. size else format = format or size end
        local right = VerticalGroup:new{
            align = "right",
            TextWidget:new{ text = statusText(item), face = KoboldWidgets.face(14), max_width = L.right_w },
        }
        if format then
            right[#right + 1] = VerticalSpan:new{ width = Screen:scaleBySize(2) }
            right[#right + 1] = TextWidget:new{
                text = format,
                face = KoboldWidgets.face(13),
                fgcolor = KoboldWidgets.subtitleColor(),
                max_width = L.right_w,
            }
        end
        right[#right + 1] = VerticalSpan:new{ width = Screen:scaleBySize(4) }
        local dots = TextWidget:new{ text = "…", face = KoboldWidgets.face(18), bold = true }
        right[#right + 1] = dots
        -- Where the "..." sits in the row (its middle, from the row's top), for
        -- the book menu's arrow. The right column is centred in the row.
        local right_h = right:getSize().h
        item.dots_y = math.floor((L.row_h - right_h) / 2) + right_h - math.floor(dots:getSize().h / 2)

        return HorizontalGroup:new{
            CenterContainer:new{
                dimen = Geom:new{ w = L.thumb_w, h = L.row_h },
                KoboldWidgets.makeCover(item.file, L.thumb_w, L.thumb_h),
            },
            HorizontalSpan:new{ width = L.col_gap },
            LeftContainer:new{
                dimen = Geom:new{ w = L.text_w, h = L.row_h },
                middle,
            },
            HorizontalSpan:new{ width = L.col_gap },
            RightContainer:new{
                dimen = Geom:new{ w = L.right_w, h = L.row_h },
                right,
            },
        }
    end

    -- One author / series / collection row: name over its book count, and a
    -- right chevron. A series row also starts with the cover of its first book,
    -- sized like a book row. Exactly as tall as rowSize() says.
    -- A series row, as on the e-reader: the first book's cover (with a small
    -- stack of edges above it when the series has more than one book), the
    -- series name, its author, and the book count at the bottom.
    function KoboldMyBooks:buildSeriesRow(group)
        local L = self.L
        local _n, _slot, row_h = self:rowSize()
        local first = group.books[1]

        -- Cover, shortened to make room for the stack lines when there are any.
        local line_h = Screen:scaleBySize(2)
        local line_gap = Screen:scaleBySize(2)
        local stacked = #group.books > 1
        local stack_h = stacked and 2 * (line_h + line_gap) or 0
        local cover_h = L.thumb_h - stack_h
        local cover_w = math.floor(cover_h / COVER_RATIO)
        local cw = KoboldWidgets.coverSize(first and first.file, cover_w, cover_h)
        local thumb = VerticalGroup:new{ align = "center" }
        if stacked then
            local inset = Screen:scaleBySize(4)
            for k = 2, 1, -1 do
                thumb[#thumb + 1] = LineWidget:new{
                    dimen = Geom:new{ w = math.max(1, cw - 2 * k * inset), h = line_h },
                    background = Blitbuffer.COLOR_DARK_GRAY,
                }
                thumb[#thumb + 1] = VerticalSpan:new{ width = line_gap }
            end
        end
        thumb[#thumb + 1] = KoboldWidgets.makeCover(first and first.file, cover_w, cover_h)

        -- Authors of the series: the first book's, which the others share in
        -- almost every series.
        local authors = first and first.authors
        local text_w = L.list_w - L.thumb_w - L.col_gap
        local top = VerticalGroup:new{
            align = "left",
            TextWidget:new{ text = group.name, face = KoboldWidgets.face(17), max_width = text_w },
        }
        if authors then
            top[#top + 1] = VerticalSpan:new{ width = Screen:scaleBySize(4) }
            top[#top + 1] = TextWidget:new{ text = authors, face = KoboldWidgets.face(14), max_width = text_w }
        end
        local count = TextWidget:new{
            text = countText(#group.books), face = KoboldWidgets.face(14), max_width = text_w,
        }
        local pad = L.row_pad
        local fill = math.max(0, row_h - 2 * pad - top:getSize().h - count:getSize().h)

        -- Exactly the list's width: rows sized by their text made the list
        -- narrower on a page with a single series (no separator lines to set
        -- the width), and the side bar moved toward the middle with it.
        return KoboldWidgets.fixed(L.list_w, row_h, HorizontalGroup:new{
            CenterContainer:new{ dimen = Geom:new{ w = L.thumb_w, h = row_h }, thumb },
            HorizontalSpan:new{ width = L.col_gap },
            VerticalGroup:new{
                align = "left",
                VerticalSpan:new{ width = pad },
                top,
                VerticalSpan:new{ width = fill },
                count,
                VerticalSpan:new{ width = pad },
            },
        })
    end

    function KoboldMyBooks:buildGroupRow(group)
        local L = self.L
        local _n, _slot, row_h = self:rowSize()
        local text_w = L.list_w - L.col_gap - L.chevron
        local row = HorizontalGroup:new{}
        if self.tab == "series" then
            return self:buildSeriesRow(group)
        end
        if self.tab == "collections" then
            -- The collection's name on the left in italics, its book count on
            -- the right.
            local count = TextWidget:new{ text = countText(#group.books), face = KoboldWidgets.italicFace(15) }
            local name_w = L.list_w - count:getSize().w - 2 * L.col_gap
            return KoboldWidgets.fixed(L.list_w, row_h, HorizontalGroup:new{
                align = "center",
                HorizontalSpan:new{ width = L.col_gap },
                LeftContainer:new{
                    dimen = Geom:new{ w = name_w, h = row_h },
                    TextWidget:new{ text = group.name, face = KoboldWidgets.italicFace(18), max_width = name_w },
                },
                count,
            })
        end
        row[#row + 1] = LeftContainer:new{
            dimen = Geom:new{ w = text_w, h = row_h },
            VerticalGroup:new{
                align = "left",
                TextWidget:new{ text = group.name, face = KoboldWidgets.face(17), max_width = text_w },
                VerticalSpan:new{ width = Screen:scaleBySize(4) },
                TextWidget:new{
                    text = countText(#group.books),
                    face = KoboldWidgets.face(14),
                    fgcolor = KoboldWidgets.subtitleColor(),
                    max_width = text_w,
                },
            },
        }
        row[#row + 1] = HorizontalSpan:new{ width = L.col_gap }
        row[#row + 1] = CenterContainer:new{
            dimen = Geom:new{ w = L.chevron, h = row_h },
            KoboldWidgets.icon("chevron.right", L.chevron),
        }
        return row
    end

    -- Message shown when the current view has nothing to list.
    function KoboldMyBooks:emptyText()
        if self.tab == "files" then return _("This folder is empty.") end
        if self.tab == "books" then
            if self.filter == "all" then return _("No books found in your home folder.") end
            return _("No books match this filter.")
        end
        if self:inCollection() then
            if self:collView().filter ~= "all" then return _("No books match this filter.") end
            return _("No books in this collection yet. Use ... > Manage collection to add some.")
        end
        if self.group then return _("No books here.") end
        if self.tab == "authors" then return _("No authors found.") end
        if self.tab == "series" then return _("No series found.") end
        return _("No collections yet. Use ... > New collection to make one.")
    end

    -- The rows of the current page, each with a separator under it. Always
    -- list_w x list_h, so the side bar stays put on a short last page.
    function KoboldMyBooks:buildList()
        local L = self.L
        if #self.list == 0 then
            return CenterContainer:new{
                dimen = Geom:new{ w = L.list_w, h = L.list_h },
                TextWidget:new{
                    text = self:emptyText(),
                    face = KoboldWidgets.face(16),
                    fgcolor = KoboldWidgets.subtitleColor(),
                    max_width = L.list_w,
                },
            }
        end
        local groups = self:showsGroups()
        local _n, slot_h = self:rowSize()
        local list = VerticalGroup:new{ align = "left" }
        local used = 0
        local count = #self.page_items
        for i, item in ipairs(self.page_items) do
            if groups then
                list[#list + 1] = self:buildGroupRow(item)
            elseif item.is_dir then
                list[#list + 1] = self:buildFolderRow(item)
            else
                list[#list + 1] = self:buildBookRow(item)
            end
            used = used + slot_h - L.line_h
            -- No separator under the last row of the page.
            if i < count then
                list[#list + 1] = LineWidget:new{
                    dimen = Geom:new{ w = L.list_w, h = L.line_h },
                    background = Blitbuffer.COLOR_LIGHT_GRAY,
                }
                used = used + L.line_h
            end
        end
        list[#list + 1] = VerticalSpan:new{ width = math.max(0, L.list_h - used) }
        return list
    end

    -- Side bar that makes the pages read like one scrolling list: an up arrow,
    -- a track with a thumb showing where this page sits, and a down arrow. With
    -- a single page only a faint track is drawn. Exactly list_h tall.
    function KoboldMyBooks:buildSidebar()
        local L = self.L
        return VerticalGroup:new{
            VerticalSpan:new{ width = L.bar_inset },
            KoboldWidgets.pageBar(self:barOpts()),
        }
    end

    -- Size and position of the side bar, for pageBar and pageBarTarget.
    function KoboldMyBooks:barOpts()
        local L = self.L
        return { w = L.bar_w, h = L.bar_h, page = self.page, pages = self.pages, arrow = L.chevron }
    end

    -- Grid view: rows of covers, each with its status and "..." under it.
    -- Covers stand on a common bottom line. Exactly grid_h tall.
    function KoboldMyBooks:buildGrid()
        local L = self.L
        if #self.list == 0 then
            return CenterContainer:new{
                dimen = Geom:new{ w = L.content_w, h = L.grid_h },
                TextWidget:new{
                    text = self:emptyText(), face = KoboldWidgets.face(16),
                    fgcolor = KoboldWidgets.subtitleColor(), max_width = L.content_w,
                },
            }
        end
        local grid = VerticalGroup:new{ align = "left" }
        local used = 0
        for r = 1, L.grid_rows do
            local row = HorizontalGroup:new{ align = "top" }
            local any = false
            for c = 1, L.grid_cols do
                local item = self.page_items[(r - 1) * L.grid_cols + c]
                if c > 1 then row[#row + 1] = HorizontalSpan:new{ width = L.grid_gap_x } end
                if item then
                    any = true
                    -- A series shows its first book's cover, its name and count;
                    -- a book its status and "...".
                    local is_group = item.books ~= nil
                    local file = is_group and item.books[1] and item.books[1].file or item.file
                    local _sw, sh = KoboldWidgets.coverSize(file, L.grid_cell_w, L.grid_cover_h)
                    local line1, line2
                    if is_group then
                        line1 = TextWidget:new{ text = item.name, face = KoboldWidgets.face(14), max_width = L.grid_cell_w }
                        line2 = TextWidget:new{
                            text = countText(#item.books), face = KoboldWidgets.face(13),
                            fgcolor = KoboldWidgets.subtitleColor(), max_width = L.grid_cell_w,
                        }
                    else
                        line1 = TextWidget:new{ text = statusText(item), face = KoboldWidgets.face(14), max_width = L.grid_cell_w }
                        line2 = TextWidget:new{ text = "…", face = KoboldWidgets.face(18), bold = true }
                    end
                    row[#row + 1] = VerticalGroup:new{
                        align = "left",
                        KoboldWidgets.fixed(L.grid_cell_w, L.grid_cover_h, VerticalGroup:new{
                            align = "left",
                            VerticalSpan:new{ width = (sh and L.grid_cover_h - sh) or 0 },
                            KoboldWidgets.makeCover(file, L.grid_cell_w, L.grid_cover_h),
                        }),
                        VerticalSpan:new{ width = L.grid_text_gap },
                        line1,
                        line2,
                    }
                else
                    row[#row + 1] = HorizontalSpan:new{ width = L.grid_cell_w }
                end
            end
            if not any then break end
            if r > 1 then
                grid[#grid + 1] = VerticalSpan:new{ width = L.grid_gap_y }
                used = used + L.grid_gap_y
            end
            grid[#grid + 1] = KoboldWidgets.fixed(L.content_w, L.grid_cell_h, row)
            used = used + L.grid_cell_h
        end
        grid[#grid + 1] = VerticalSpan:new{ width = math.max(0, L.grid_h - used) }
        return grid
    end

    -- Page footer for grid view: chevrons where there is a page to go to, and
    -- "Page x of y" between them. Tap the left or right half to turn pages.
    function KoboldMyBooks:buildFooter()
        local L = self.L
        local icon_size = L.chevron
        local function chevron(name, shown)
            if shown then return KoboldWidgets.icon(name, icon_size) end
            return HorizontalSpan:new{ width = icon_size }
        end
        local label = TextWidget:new{
            text = _.T(_("Page %1 of %2"), self.page, self.pages),
            face = KoboldWidgets.face(14),
            fgcolor = KoboldWidgets.subtitleColor(),
        }
        local spacer = math.floor((L.content_w - 2 * icon_size - label:getSize().w) / 2)
        return CenterContainer:new{
            dimen = Geom:new{ w = L.content_w, h = L.footer_h },
            HorizontalGroup:new{
                align = "center",
                chevron("chevron.left", self.page > 1),
                HorizontalSpan:new{ width = math.max(spacer, 0) },
                label,
                HorizontalSpan:new{ width = math.max(spacer, 0) },
                chevron("chevron.right", self.page < self.pages),
            },
        }
    end
end
