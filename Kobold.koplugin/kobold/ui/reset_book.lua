-- kobold/ui/reset_book.lua — Kobold
-- "Reset this book?" in Kobold's popup style: the same warning and choices
-- as KOReader's Reset (settings and progress, custom cover, custom
-- metadata, each ticked when the book has it), in a rounded box in the
-- middle of the screen, with Cancel and Reset. Tapping outside cancels.

local Blitbuffer      = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device          = require("device")
local FrameContainer  = require("ui/widget/container/framecontainer")
local Geom            = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local InputContainer  = require("ui/widget/container/inputcontainer")
local LeftContainer   = require("ui/widget/container/leftcontainer")
local TextBoxWidget   = require("ui/widget/textboxwidget")
local TextWidget      = require("ui/widget/textwidget")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("kobold.l10n")
local KoboldBookStatus = require("kobold.data.book_status")
local KoboldPopup     = require("kobold.ui.popup")
local KoboldTaps      = require("kobold.ui.taps")
local KoboldWidgets   = require("kobold.ui.widgets")

local Screen = Device.screen

local KoboldResetBook = InputContainer:extend{
    name = "kobold_reset_book",
    file = nil,
    title = nil,       -- the book's title, shown in the warning
    on_done = nil,     -- called after the book was reset
}

-- The choices, in KOReader's order and words.
local PARTS = {
    { key = "settings", text = _("document settings, progress, bookmarks, highlights, notes") },
    { key = "cover",    text = _("custom cover image") },
    { key = "metadata", text = _("custom book metadata") },
}

-- Round tick on the left of a choice: dark with a white tick when chosen,
-- light grey when not, faded out when the book has nothing to remove there.
local function tick(size, on, enabled)
    return FrameContainer:new{
        bordersize = 0, padding = 0, radius = math.floor(size / 2),
        background = on and Blitbuffer.COLOR_DARK_GRAY
            or (enabled and Blitbuffer.COLOR_LIGHT_GRAY or Blitbuffer.COLOR_WHITE),
        CenterContainer:new{
            dimen = Geom:new{ w = size, h = size },
            TextWidget:new{
                text = on and "✓" or "", face = KoboldWidgets.face(15), bold = true,
                fgcolor = Blitbuffer.COLOR_WHITE,
            },
        },
    }
end

function KoboldResetBook:init()
    local W, H = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = W, h = H }
    if Device:hasKeys() then
        self.key_events = { Close = { { Device.input.group.Back } } }
    end
    self.has = KoboldBookStatus.resetParts(self.file)
    self.chosen = {}
    for _i, p in ipairs(PARTS) do self.chosen[p.key] = self.has[p.key] or false end
    self[1] = self:build()
    KoboldTaps.add(self, "KoboldResetTap", 0, 0, W, H, function(ges)
        self:onTap(ges.pos)
    end)
end

function KoboldResetBook:build()
    local W, H = Screen:getWidth(), Screen:getHeight()
    local border  = Screen:scaleBySize(2)
    local pad     = Screen:scaleBySize(24)
    local box_w   = math.min(W - 2 * Screen:scaleBySize(40), Screen:scaleBySize(520))
    local inner_w = box_w - 2 * (border + pad)
    local gap     = Screen:scaleBySize(14)
    local tick_sz = Screen:scaleBySize(26)
    local row_h   = Screen:scaleBySize(48)
    local foot_h  = Screen:scaleBySize(50)
    local button_w = math.floor((inner_w - gap) / 2)

    local page = VerticalGroup:new{
        align = "left",
        TextWidget:new{ text = _("Reset this book?"), face = KoboldWidgets.face(20), bold = true,
            max_width = inner_w },
        VerticalSpan:new{ width = gap },
        TextBoxWidget:new{ text = self.title or self.file, face = KoboldWidgets.italicFace(17),
            width = inner_w },
        VerticalSpan:new{ width = gap },
        TextBoxWidget:new{ text = _("Information will be permanently lost."),
            face = KoboldWidgets.face(15), width = inner_w },
        VerticalSpan:new{ width = gap },
    }
    -- Rows are measured from the top of the box once it is placed (below).
    local rows_top = 0
    for _i, child in ipairs(page) do rows_top = rows_top + child:getSize().h end
    local text_w = inner_w - tick_sz - gap
    for _i, p in ipairs(PARTS) do
        local enabled = self.has[p.key]
        page[#page + 1] = LeftContainer:new{
            dimen = Geom:new{ w = inner_w, h = row_h },
            HorizontalGroup:new{
                align = "center",
                tick(tick_sz, self.chosen[p.key], enabled),
                HorizontalSpan:new{ width = gap },
                TextBoxWidget:new{
                    text = p.text, face = KoboldWidgets.face(15), width = text_w,
                    fgcolor = enabled and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY,
                },
            },
        }
    end
    page[#page + 1] = VerticalSpan:new{ width = gap }

    -- Cancel and Reset, in the grey buttons of Kobold's panels. Reset is
    -- greyed out while nothing is chosen.
    local any = false
    for _k, v in pairs(self.chosen) do any = any or v end
    local function button(text, active)
        return FrameContainer:new{
            bordersize = 0, padding = 0, background = Blitbuffer.COLOR_LIGHT_GRAY,
            CenterContainer:new{ dimen = Geom:new{ w = button_w, h = foot_h },
                TextWidget:new{ text = text, face = KoboldWidgets.italicFace(17),
                    fgcolor = active and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY } },
        }
    end
    page[#page + 1] = HorizontalGroup:new{
        button(_("Cancel"), true),
        HorizontalSpan:new{ width = gap },
        button(_("Reset"), any),
    }
    page:resetLayout()

    local box = FrameContainer:new{
        bordersize = border, padding = pad,
        radius = KoboldPopup.radius(),
        background = Blitbuffer.COLOR_WHITE,
        page,
    }
    local size = box:getSize()
    local x = math.floor((W - size.w) / 2)
    local y = math.floor((H - size.h) / 2)
    self.frame_dimen = Geom:new{ x = x, y = y, w = size.w, h = size.h }

    -- Tap areas, in screen coordinates.
    local x0, y0 = x + border + pad, y + border + pad
    self.rows = {}
    for i, p in ipairs(PARTS) do
        self.rows[i] = { key = p.key, rect = Geom:new{ x = x0, y = y0 + rows_top + (i - 1) * row_h, w = inner_w, h = row_h } }
    end
    local foot_y = y0 + rows_top + #PARTS * row_h + gap
    self.cancel_rect = Geom:new{ x = x0, y = foot_y, w = button_w, h = foot_h }
    self.reset_rect = Geom:new{ x = x0 + button_w + gap, y = foot_y, w = button_w, h = foot_h }
    self.any = any
    return KoboldPopup.place(self.dimen, x, y, box)
end

function KoboldResetBook:onTap(pos)
    if not pos:intersectWith(self.frame_dimen) or pos:intersectWith(self.cancel_rect) then
        return self:onClose()
    end
    if pos:intersectWith(self.reset_rect) then
        if not self.any then return end
        local file, chosen, on_done = self.file, self.chosen, self.on_done
        self:onClose()
        KoboldBookStatus.reset(file, chosen)
        if on_done then on_done() end
        return
    end
    for _i, row in ipairs(self.rows) do
        if pos:intersectWith(row.rect) and self.has[row.key] then
            self.chosen[row.key] = not self.chosen[row.key]
            self[1] = self:build()
            UIManager:setDirty(self, "ui", self.frame_dimen)
            return
        end
    end
end

function KoboldResetBook:onClose()
    KoboldPopup.close(self)
    return true
end

-- Shows the dialog for `file`. `title` is shown in the warning; `on_done`
-- runs after a reset.
function KoboldResetBook.show(file, title, on_done)
    KoboldPopup.show(KoboldResetBook:new{ file = file, title = title, on_done = on_done })
end

return KoboldResetBook
