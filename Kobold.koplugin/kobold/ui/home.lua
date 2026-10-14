-- kobold/ui/home.lua — Kobold
-- Full-screen Home view. Top: up to four covers with their progress under each.
-- Middle: My Books and a collection, each a stack of three covers. Bottom: the
-- latest book read and reading stats. Bottom nav is shared with the other screens.

local Blitbuffer      = require("ffi/blitbuffer")
local Device          = require("device")
local FrameContainer  = require("ui/widget/container/framecontainer")
local Geom            = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local InputContainer  = require("ui/widget/container/inputcontainer")
local LeftContainer   = require("ui/widget/container/leftcontainer")
local LineWidget      = require("ui/widget/linewidget")
local OverlapGroup    = require("ui/widget/overlapgroup")
local TextBoxWidget   = require("ui/widget/textboxwidget")
local TextWidget      = require("ui/widget/textwidget")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local KoboldCovers    = require("kobold.data.covers")
local KoboldPrefs     = require("kobold.data.prefs")
local KoboldActions   = require("kobold.ui.actions")
local KoboldHomeData  = require("kobold.data.home")
local KoboldNav       = require("kobold.ui.nav")
local KoboldReader    = require("kobold.ui.reader")
local KoboldRouter    = require("kobold.ui.router")
local KoboldTaps      = require("kobold.ui.taps")
local KoboldWidgets   = require("kobold.ui.widgets")

local Screen = Device.screen

local COVER_RATIO = 1.5  -- height / width of a book cover

local KoboldHome = InputContainer:extend{
    -- Not modal: KOReader menus and dialogs (also non-modal) must be able to
    -- open on top of this screen.
    covers_fullscreen = true,
    -- Shows book covers: asks the e-ink controller to dither its refreshes,
    -- so cover images come out smooth instead of banded.
    dithered = true,
    name = "kobold_home",
    kobold_tab = "home",
}
KoboldWidgets.addScreenEvents(KoboldHome)

-- Widgets side by side with `gap` between each.
local function spacedRow(cells, gap)
    local row = HorizontalGroup:new{}
    for i, cell in ipairs(cells) do
        if i > 1 then row[#row + 1] = HorizontalSpan:new{ width = gap } end
        row[#row + 1] = cell
    end
    return row
end

-- Three covers on one bottom edge. The front cover (1) is drawn last, so covers
-- 2 and 3 sit behind it and only their visible parts show.
local function stackedCovers(files, L)
    local stack = OverlapGroup:new{
        dimen = Geom:new{ w = L.col_w, h = L.bot_h },
    }
    -- A thin white strip on the right of the front and middle covers keeps
    -- them apart from the cover behind, as on the e-reader's own shelf.
    local gap = Screen:scaleBySize(3)
    for i = 3, 1, -1 do
        local _, sh = KoboldWidgets.coverSize(files[i], L.stack_w[i], L.stack_h[i])
        local cover = KoboldWidgets.makeCover(files[i], L.stack_w[i], L.stack_h[i])
        if i < 3 and files[i] and files[i + 1] then
            cover = FrameContainer:new{
                bordersize = 0, padding = 0, padding_right = gap,
                background = Blitbuffer.COLOR_WHITE,
                cover,
            }
        end
        stack[#stack + 1] = VerticalGroup:new{
            VerticalSpan:new{ width = L.bot_h - sh },
            HorizontalGroup:new{
                HorizontalSpan:new{ width = L.stack_x[i] },
                cover,
            },
        }
    end
    return stack
end


function KoboldHome:init()
    local W, H = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = W, h = H }

    if Device:hasKeys() then
        self.key_events = {
            Close = { { Device.input.group.Back } },
        }
    end

    -- Read once per open: the random collection stays the same when the
    -- screen is redrawn with newly extracted covers.
    self.data = KoboldHomeData.getHomeData()
    self:build()

    -- Covers missing from the cover browser are extracted in the background;
    -- refreshCovers runs when they are ready.
    local files = {}
    for _i, item in ipairs(self.data.reading) do files[#files + 1] = item.file end
    for _i, f in ipairs(self.data.my_books) do files[#files + 1] = f end
    for _i, f in ipairs(self.data.right.files) do files[#files + 1] = f end
    KoboldCovers.ensure(files)
end

-- Redraws the whole screen with the covers now in the cover cache.
function KoboldHome:refreshCovers()
    self:build()
    UIManager:setDirty(self, "ui")
end

-- Builds the screen from self.data and registers its tap zones (registering
-- the same zones again on a rebuild replaces them).
function KoboldHome:build()
    local W, H = Screen:getWidth(), Screen:getHeight()
    local data      = self.data
    local margin    = Screen:scaleBySize(30)
    local gap       = Screen:scaleBySize(20)
    local content_w = W - 2 * margin

    -- Fixed heights of every band except the stacked covers (bot_h), which
    -- takes whatever height is left above the nav bar.
    local status_h     = Screen:scaleBySize(40)
    local section_gap  = Screen:scaleBySize(30)
    local tight_gap    = Screen:scaleBySize(6)
    local caption_h    = Screen:scaleBySize(28)
    local caption_sub_h = Screen:scaleBySize(26)
    local title_gap    = Screen:scaleBySize(14)
    local title_h      = Screen:scaleBySize(30)
    local subtitle_h   = Screen:scaleBySize(26)
    local line_gap     = Screen:scaleBySize(20)
    local line_h       = Screen:scaleBySize(2)
    -- Bottom titles reserve exactly two lines of the 18 pt face, so a one-line
    -- title and a two-line title leave the subtitle on the same row.
    local info_title_h = 2 * TextWidget:new{ text = "Ag", face = KoboldWidgets.face(18) }:getSize().h
    local info_sub_h   = Screen:scaleBySize(26)
    local info_pad     = Screen:scaleBySize(12)
    local nav_h        = KoboldNav.height()

    -- Top row: four covers, widths from the screen, height by the 2:3 ratio.
    local top_w = math.floor((content_w - 3 * gap) / 4)
    local top_h = math.floor(top_w * COVER_RATIO)

    -- Middle row: two columns. The stack's visible parts add up to exactly
    -- col_w when the front cover is u wide, the middle 0.9u and the back 0.8u,
    -- with each back cover 40% hidden: total = u + 0.6 * (0.9u + 0.8u) = 2.02u.
    local col_gap = 2 * gap
    local col_w   = math.floor((content_w - col_gap) / 2)
    local u       = math.floor(col_w / 2.02)
    -- Height left above the nav bar after every fixed band. Shrink the stack if
    -- the width-based height would run into the nav bar.
    local fixed_h = status_h + section_gap + top_h + tight_gap + caption_h + caption_sub_h
        + section_gap + title_gap + title_h + subtitle_h
        + line_gap + line_h + info_title_h + info_sub_h + info_pad
    local avail_h = H - nav_h - margin - fixed_h
    if math.floor(u * COVER_RATIO) > avail_h then
        u = math.max(math.floor(avail_h / COVER_RATIO), 1)
    end
    local bot_h   = math.floor(u * COVER_RATIO)  -- shared bottom edge of the stack
    local stack_w = { u, math.floor(u * 0.9), math.floor(u * 0.8) }
    local stack_h = { bot_h, math.floor(stack_w[2] * COVER_RATIO), math.floor(stack_w[3] * COVER_RATIO) }
    local stack_x = { 0, math.floor(u * 0.64), math.floor(u * 1.22) }

    local L = {
        top_w = top_w, top_h = top_h,
        top_gap = math.floor((content_w - 4 * top_w) / 3),
        tight_gap = tight_gap, caption_h = caption_h, caption_sub_h = caption_sub_h,
        bot_h = bot_h, col_w = col_w, col_gap = col_gap,
        stack_w = stack_w, stack_h = stack_h, stack_x = stack_x,
        title_gap = title_gap, title_h = title_h, subtitle_h = subtitle_h,
        line_gap = line_gap, line_h = line_h, content_w = content_w,
        info_title_h = info_title_h, info_sub_h = info_sub_h,
    }

    local body = FrameContainer:new{
        width = W, bordersize = 0, padding = margin, padding_bottom = 0,
        VerticalGroup:new{
            KoboldWidgets.statusBarFrame(self, margin, content_w, status_h),
            VerticalSpan:new{ width = section_gap },
            self:buildReadingSection(data.reading, L),
            VerticalSpan:new{ width = section_gap },
            self:buildLibrarySection(data, L),
            VerticalSpan:new{ width = line_gap },
            -- One separator per column, with a gap between them.
            HorizontalGroup:new{
                LineWidget:new{
                    dimen = Geom:new{ w = L.col_w, h = line_h },
                    background = Blitbuffer.COLOR_LIGHT_GRAY,
                },
                HorizontalSpan:new{ width = L.col_gap },
                LineWidget:new{
                    dimen = Geom:new{ w = L.col_w, h = line_h },
                    background = Blitbuffer.COLOR_LIGHT_GRAY,
                },
            },
            self:buildInfoSection(data, L),
        },
    }

    -- Swipe down from the top edge opens the KOReader menu.
    KoboldTaps.topMenu(self)

    -- Tap zones. Each rectangle uses the same values as the layout above:
    -- the body starts at `margin`, then status bar, reading row, library row,
    -- separator and info band, in that order.
    local y_read = margin + status_h + section_gap
    local y_lib  = y_read + top_h + tight_gap + caption_h + caption_sub_h + section_gap
    local lib_h  = bot_h + title_gap + title_h + subtitle_h
    local y_info = y_lib + lib_h + line_gap + line_h
    -- Stacks: My Books opens the Books tab; a collection opens that
    -- collection in the Collections tab; More Books opens the Books tab.
    KoboldTaps.add(self, "KoboldStackMyBooks", margin, y_lib, col_w, lib_h, function()
        KoboldRouter.show("books", self)
    end)
    local collection = data.right and data.right.collection
    KoboldTaps.add(self, "KoboldStackRight", margin + col_w + col_gap, y_lib, col_w, lib_h, function()
        if collection then
            KoboldRouter.show("books", self, { tab = "collections", group_key = collection })
        else
            KoboldRouter.show("books", self)
        end
    end)
    for i = 1, 4 do
        local item = data.reading[i]
        if item and item.file then
            local file = item.file
            KoboldTaps.add(self, "KoboldTop" .. i,
                margin + (i - 1) * (top_w + L.top_gap), y_read, top_w, top_h,
                function() KoboldReader.open(self, file) end)
        end
    end
    if data.latest and data.latest.file then
        local file = data.latest.file
        KoboldTaps.add(self, "KoboldContinue", margin, y_info, col_w,
            info_title_h + info_sub_h,
            function() KoboldReader.open(self, file) end)
    end
    -- Reading stats: each line runs its own action from Kobold Settings. With
    -- two lines the lower half of the title runs the second line's action;
    -- the rest of the block runs the first line's.
    KoboldTaps.add(self, "KoboldStats", margin + col_w + col_gap, y_info, col_w,
        info_title_h + info_sub_h,
        function(ges)
            local actions = self.stats_actions or {}
            local second = actions[2] and ges.pos.y >= y_info + math.floor(info_title_h / 2)
                and ges.pos.y < y_info + info_title_h
            local action = second and actions[2] or actions[1]
            if action then KoboldActions.run(action) end
        end)

    self[1] = FrameContainer:new{
        width = W,
        height = H,
        bordersize = 0,
        padding = 0,
        background = Blitbuffer.COLOR_WHITE,
        OverlapGroup:new{
            dimen = Geom:new{ w = W, h = H },
            body,
            KoboldNav.attach(self, W, H, "home"),
        },
    }
end


-- Text under a top cover: hours left from the book's own reading stats.
local function hoursToGoText(item)
    if not item then return "" end
    local h = item.hours_left
    if not h then return "No stats yet" end
    if h < 0.5 then return "less than 1 hour to go" end
    local n = math.floor(h + 0.5)
    return n .. (n == 1 and " hour" or " hours") .. " to go"
end

-- Up to four covers in a row. Under each: the percentage read, then the hours
-- left. Every caption is left-aligned to its cover (align = "left").
function KoboldHome:buildReadingSection(reading, L)
    local cells = {}
    for i = 1, 4 do
        local item = reading[i]
        local pct = item and (math.floor(item.percent * 100 + 0.5) .. "% read") or ""
        cells[i] = VerticalGroup:new{
            align = "left",
            KoboldWidgets.fixed(L.top_w, L.top_h,
                KoboldWidgets.makeCover(item and item.file, L.top_w, L.top_h)),
            VerticalSpan:new{ width = L.tight_gap },
            LeftContainer:new{
                dimen = Geom:new{ w = L.top_w, h = L.caption_h },
                TextWidget:new{ text = pct, face = KoboldWidgets.face(16), max_width = L.top_w },
            },
            LeftContainer:new{
                dimen = Geom:new{ w = L.top_w, h = L.caption_sub_h },
                TextWidget:new{
                    text = hoursToGoText(item),
                    face = KoboldWidgets.face(14),
                    fgcolor = KoboldWidgets.subtitleColor(),
                    max_width = L.top_w,
                },
            },
        }
    end
    return spacedRow(cells, L.top_gap)
end

-- Two columns: a stack of three covers over a left-aligned title and subtitle.
-- Left: My Books. Right: a random collection, or More Books.
function KoboldHome:buildLibrarySection(data, L)
    local function column(files, title, subtitle)
        return VerticalGroup:new{
            align = "left",
            stackedCovers(files, L),
            VerticalSpan:new{ width = L.title_gap },
            LeftContainer:new{
                dimen = Geom:new{ w = L.col_w, h = L.title_h },
                TextWidget:new{ text = title, face = KoboldWidgets.face(18), max_width = L.col_w },
            },
            LeftContainer:new{
                dimen = Geom:new{ w = L.col_w, h = L.subtitle_h },
                TextWidget:new{
                    text = subtitle,
                    face = KoboldWidgets.face(14),
                    fgcolor = KoboldWidgets.subtitleColor(),
                    max_width = L.col_w,
                },
            },
        }
    end

    return HorizontalGroup:new{
        column(data.my_books, "My Books", data.total .. " BOOKS"),
        HorizontalSpan:new{ width = L.col_gap },
        column(data.right.files, data.right.title, data.right.subtitle),
    }
end

-- Number of lines `text` takes at the info title face in width `w`.
local function titleLines(text, w)
    local face = KoboldWidgets.face(18)
    local box = TextBoxWidget:new{ text = text, face = face, width = w }
    local one = TextBoxWidget:new{ text = "A", face = face, width = w }
    local lines = math.floor(box:getSize().h / math.max(one:getSize().h, 1) + 0.5)
    box:free()
    one:free()
    return lines
end

-- Bottom band: latest read title on the left, reading stats on the right.
-- Titles are wrapped to the column width and aligned left.
function KoboldHome:buildInfoSection(data, L)
    -- Title cell is always two lines tall. A one-line title leaves a blank
    -- line below it, so both subtitles sit on the same row.
    local function block(title, subtitle)
        return VerticalGroup:new{
            align = "left",
            LeftContainer:new{
                dimen = Geom:new{ w = L.col_w, h = L.info_title_h },
                TextBoxWidget:new{
                    text = title,
                    face = KoboldWidgets.face(18),
                    width = L.col_w,
                    height = L.info_title_h,
                    height_overflow_show_ellipsis = true,
                    alignment = "left",
                },
            },
            LeftContainer:new{
                dimen = Geom:new{ w = L.col_w, h = L.info_sub_h },
                TextWidget:new{
                    text = subtitle,
                    face = KoboldWidgets.face(14),
                    fgcolor = KoboldWidgets.subtitleColor(),
                    max_width = L.col_w,
                },
            },
        }
    end

    local left_title = "No recent book"
    if data.latest then
        left_title = data.latest.title or KoboldWidgets.bookTitle(data.latest.file)
    end
    -- Right title: the first stats line from Kobold Settings. When the left
    -- title wraps to two lines, the second stats line fills the same space.
    -- self.stats_actions holds the tap action of each shown line, top first.
    local stats = data.stats or {}
    local first = stats.line1 or stats.line2
    local right_title = first and first.text or "No reading stats"
    self.stats_actions = { first and first.action }
    if stats.line1 and stats.line2 and titleLines(left_title, L.col_w) >= 2 then
        right_title = stats.line1.text .. "\n" .. stats.line2.text
        self.stats_actions = { stats.line1.action, stats.line2.action }
    end
    local label = KoboldPrefs.get("stats_label") or "Reading Stats"
    return HorizontalGroup:new{
        block(left_title, "Continue Reading"),
        HorizontalSpan:new{ width = L.col_gap },
        block(right_title, label),
    }
end

function KoboldHome:onClose()
    UIManager:close(self)
    return true
end

return KoboldHome

