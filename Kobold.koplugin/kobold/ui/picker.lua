-- kobold/ui/picker.lua — Kobold
-- Kobold's own popups for choosing and confirming, in the style of its
-- other popups (a rounded box in the middle of the screen), used in place
-- of KOReader's dialogs:
--   KoboldPicker.choose  a list of choices, the current one ticked; long
--                        lists get pages (swipe, or tap the page arrows)
--   KoboldPicker.icons   the same as a grid of icons with their names
--   KoboldPicker.confirm a question with Cancel and an OK button
-- Tapping outside the box cancels.

local Blitbuffer      = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device          = require("device")
local FrameContainer  = require("ui/widget/container/framecontainer")
local Geom            = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local InputContainer  = require("ui/widget/container/inputcontainer")
local LeftContainer   = require("ui/widget/container/leftcontainer")
local OverlapGroup    = require("ui/widget/overlapgroup")
local RightContainer  = require("ui/widget/container/rightcontainer")
local TextBoxWidget   = require("ui/widget/textboxwidget")
local TextWidget      = require("ui/widget/textwidget")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("kobold.l10n")
local KoboldPopup     = require("kobold.ui.popup")
local KoboldSettingsList = require("kobold.ui.settings_list")
local KoboldTaps      = require("kobold.ui.taps")
local KoboldWidgets   = require("kobold.ui.widgets")

local Screen = Device.screen

local function inside(pos, r)
    return r and pos.x >= r.x and pos.x < r.x + r.w and pos.y >= r.y and pos.y < r.y + r.h
end

-- The box sizes shared by every popup here.
local function box()
    local W = Screen:getWidth()
    local border = Screen:scaleBySize(2)
    local pad = Screen:scaleBySize(20)
    local w = math.min(W - 2 * Screen:scaleBySize(36), Screen:scaleBySize(560))
    return { border = border, pad = pad, w = w, inner = w - 2 * (border + pad) }
end

-- Places `content` (exactly inner wide) in a rounded box in the middle of
-- the screen. Returns the layer and the box's screen rect.
local function placeBox(dimen, B, content)
    local frame = FrameContainer:new{
        bordersize = B.border, padding = B.pad,
        radius = KoboldPopup.radius(),
        background = Blitbuffer.COLOR_WHITE,
        content,
    }
    local size = frame:getSize()
    local x = math.floor((dimen.w - size.w) / 2)
    local y = math.floor((dimen.h - size.h) / 2)
    return KoboldPopup.place(dimen, x, y, frame), Geom:new{ x = x, y = y, w = size.w, h = size.h }
end

-- Choosing --------------------------------------------------------------

local Picker = InputContainer:extend{
    -- Modal, so it opens above the status bar popups (which are modal too).
    modal = true,
    name = "kobold_picker",
    title = nil,
    choices = nil,   -- { { id, label, icon = spec (grid only) }, ... }
    current = nil,
    grid = false,
    on_pick = nil,   -- on_pick(id), after the popup closed
    on_cancel = nil,
}

function Picker:init()
    local W, H = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = W, h = H }
    self.page = 1
    if Device:hasKeys() then
        self.key_events = { Close = { { Device.input.group.Back } } }
    end
    self[1] = self:build()
    KoboldTaps.add(self, "KoboldPickerTap", 0, 0, W, H, function(ges) self:onTap(ges.pos) end)
    self:registerTouchZones({ {
        id = "KoboldPickerSwipe", ges = "swipe",
        screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
        handler = function(ges)
            if ges.direction == "north" or ges.direction == "west" then
                self:goTo(self.page + 1)
            elseif ges.direction == "south" or ges.direction == "east" then
                self:goTo(self.page - 1)
            else
                return false
            end
            return true
        end,
    } })
end

-- The rows (list) or cells (grid) of the current page, drawn with their top
-- left at (0, 0); the tap rects are moved to the screen afterwards.
function Picker:buildBody(inner, max_h)
    if self.grid then
        local cell_w = Screen:scaleBySize(96)
        local icon_sz = Screen:scaleBySize(36)
        local label_h = KoboldWidgets.lineHeight(KoboldWidgets.face(12))
        local cell_h = icon_sz + label_h + Screen:scaleBySize(18)
        local cols = math.max(1, math.floor(inner / cell_w))
        cell_w = math.floor(inner / cols)
        local rows = math.max(1, math.floor(max_h / cell_h))
        local per = cols * rows
        self.pages = math.max(1, math.ceil(#self.choices / per))
        self.page = math.max(1, math.min(self.page, self.pages))
        local body = VerticalGroup:new{ align = "left" }
        local hits = {}
        local first = (self.page - 1) * per + 1
        for r = 0, rows - 1 do
            local line = HorizontalGroup:new{}
            for c = 0, cols - 1 do
                local choice = self.choices[first + r * cols + c]
                if choice then
                    local picked = choice.id == self.current
                    line[#line + 1] = FrameContainer:new{
                        bordersize = picked and Screen:scaleBySize(2) or 0, padding = 0,
                        radius = Screen:scaleBySize(8),
                        background = Blitbuffer.COLOR_WHITE,
                        CenterContainer:new{
                            dimen = Geom:new{ w = cell_w - (picked and 2 * Screen:scaleBySize(2) or 0),
                                h = cell_h - (picked and 2 * Screen:scaleBySize(2) or 0) },
                            VerticalGroup:new{
                                KoboldWidgets.iconFromSpec(choice.icon or choice.id, icon_sz),
                                VerticalSpan:new{ width = Screen:scaleBySize(4) },
                                TextWidget:new{ text = choice.label, face = KoboldWidgets.face(12),
                                    max_width = cell_w - Screen:scaleBySize(6) },
                            },
                        },
                    }
                    local id = choice.id
                    hits[#hits + 1] = { rect = Geom:new{ x = c * cell_w, y = r * cell_h, w = cell_w, h = cell_h },
                        on_tap = function() self:pick(id) end }
                end
            end
            if #line > 0 then body[#body + 1] = line end
        end
        return body, hits
    end

    -- A list: the same rows as Kobold Settings, with a tick on the current one.
    local spec = {}
    for _i, choice in ipairs(self.choices) do
        local id = choice.id
        spec[#spec + 1] = {
            title = choice.label, value = id == self.current and "✓" or "",
            on_tap = function() self:pick(id) end,
        }
    end
    self.starts = self.starts or (function()
        local starts = { 1 }
        while true do
            local _l, _h, nxt = KoboldSettingsList.build(spec, 0, 0, inner,
                { from = starts[#starts], max_h = max_h, value_ratio = 0.12 })
            if not nxt then break end
            starts[#starts + 1] = nxt
        end
        return starts
    end)()
    self.pages = #self.starts
    self.page = math.max(1, math.min(self.page, self.pages))
    local list, hits = KoboldSettingsList.build(spec, 0, 0, inner,
        { from = self.starts[self.page], max_h = max_h, value_ratio = 0.12 })
    return list, hits
end

function Picker:build()
    local H = Screen:getHeight()
    local B = box()
    local title_h = Screen:scaleBySize(44)
    local foot_h = Screen:scaleBySize(40)
    local max_h = math.floor(H * 0.62) - title_h - foot_h
    local body, hits = self:buildBody(B.inner, max_h)
    local body_h = body:getSize().h
    if self.pages > 1 then body_h = max_h end  -- every page the same height

    local content = VerticalGroup:new{
        align = "left",
        LeftContainer:new{
            dimen = Geom:new{ w = B.inner, h = title_h },
            TextWidget:new{ text = self.title or "", face = KoboldWidgets.face(19), bold = true,
                max_width = B.inner },
        },
        KoboldWidgets.fixed(B.inner, body_h, body),
    }
    if self.pages > 1 then
        local arrow = Screen:scaleBySize(26)
        content[#content + 1] = OverlapGroup:new{
            dimen = Geom:new{ w = B.inner, h = foot_h },
            LeftContainer:new{ dimen = Geom:new{ w = B.inner, h = foot_h },
                self.page > 1 and KoboldWidgets.icon("chevron.left", arrow) or HorizontalSpan:new{ width = arrow } },
            CenterContainer:new{ dimen = Geom:new{ w = B.inner, h = foot_h },
                TextWidget:new{ text = _.T(_("Page %1 of %2"), self.page, self.pages),
                    face = KoboldWidgets.face(14), fgcolor = KoboldWidgets.subtitleColor() } },
            RightContainer:new{ dimen = Geom:new{ w = B.inner, h = foot_h },
                self.page < self.pages and KoboldWidgets.icon("chevron.right", arrow) or HorizontalSpan:new{ width = arrow } },
        }
    end
    local layer, rect = placeBox(self.dimen, B, content)
    self.frame_dimen = rect
    local x0, y0 = rect.x + B.border + B.pad, rect.y + B.border + B.pad
    for _i, h in ipairs(hits) do
        h.rect.x, h.rect.y = h.rect.x + x0, h.rect.y + y0 + title_h
    end
    self.hits = hits
    local foot_y = y0 + title_h + body_h
    self.prev_rect = self.pages > 1 and Geom:new{ x = x0, y = foot_y, w = math.floor(B.inner / 2), h = foot_h } or nil
    self.next_rect = self.pages > 1 and Geom:new{ x = x0 + math.floor(B.inner / 2), y = foot_y,
        w = B.inner - math.floor(B.inner / 2), h = foot_h } or nil
    return layer
end

function Picker:goTo(page)
    page = math.max(1, math.min(self.pages or 1, page))
    if page == self.page then return end
    self.page = page
    self[1] = self:build()
    UIManager:setDirty(self, "ui", self.frame_dimen)
end

function Picker:onTap(pos)
    if not inside(pos, self.frame_dimen) then return self:onClose() end
    if inside(pos, self.prev_rect) then return self:goTo(self.page - 1) end
    if inside(pos, self.next_rect) then return self:goTo(self.page + 1) end
    if self.grid then
        for _i, h in ipairs(self.hits) do
            if inside(pos, h.rect) then return h.on_tap() end
        end
        return
    end
    KoboldSettingsList.pressTap(self, self.hits, pos)
end

function Picker:pick(id)
    self.picked = true
    KoboldPopup.close(self)
    if self.on_pick then self.on_pick(id) end
end

function Picker:onClose()
    KoboldPopup.close(self)
    if not self.picked and self.on_cancel then self.on_cancel() end
    return true
end

local KoboldPicker = {}

-- A list to pick one from. `on_pick(id)` runs after it closes; `on_cancel`
-- when it is closed without a pick.
function KoboldPicker.choose(title, choices, current, on_pick, on_cancel)
    KoboldPopup.show(Picker:new{ title = title, choices = choices, current = current,
        on_pick = on_pick, on_cancel = on_cancel })
end

-- A grid of icons to pick one from: choices are { id, label, icon }, the
-- icon a spec for KoboldWidgets.iconFromSpec (the id when left out).
function KoboldPicker.icons(title, choices, current, on_pick, on_cancel)
    KoboldPopup.show(Picker:new{ title = title, choices = choices, current = current, grid = true,
        on_pick = on_pick, on_cancel = on_cancel })
end

-- Confirming --------------------------------------------------------------

local Confirm = InputContainer:extend{
    modal = true,
    name = "kobold_confirm",
    text = nil,
    ok_text = nil,
    cancel_text = nil,
    on_ok = nil,
    on_cancel = nil,
}

function Confirm:init()
    local W, H = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = W, h = H }
    if Device:hasKeys() then
        self.key_events = { Close = { { Device.input.group.Back } } }
    end
    local B = box()
    local gap = Screen:scaleBySize(14)
    local foot_h = Screen:scaleBySize(50)
    local button_w = math.floor((B.inner - gap) / 2)
    local function button(text)
        return FrameContainer:new{
            bordersize = 0, padding = 0, background = Blitbuffer.COLOR_LIGHT_GRAY,
            CenterContainer:new{ dimen = Geom:new{ w = button_w, h = foot_h },
                TextWidget:new{ text = text, face = KoboldWidgets.italicFace(17), max_width = button_w } },
        }
    end
    local message = TextBoxWidget:new{ text = self.text, face = KoboldWidgets.face(17), width = B.inner }
    -- Long text (release notes) is cut to fit the screen.
    local max_text_h = math.floor(H * 0.6)
    if message:getSize().h > max_text_h then
        message = TextBoxWidget:new{ text = self.text, face = KoboldWidgets.face(17), width = B.inner,
            height = max_text_h, height_overflow_show_ellipsis = true }
    end
    local text_h = message:getSize().h
    local layer, rect = placeBox(self.dimen, B, VerticalGroup:new{
        align = "left",
        message,
        VerticalSpan:new{ width = 2 * gap },
        HorizontalGroup:new{
            button(self.cancel_text or _("Cancel")),
            HorizontalSpan:new{ width = gap },
            button(self.ok_text or _("OK")),
        },
    })
    self[1] = layer
    self.frame_dimen = rect
    local x0 = rect.x + B.border + B.pad
    local foot_y = rect.y + B.border + B.pad + text_h + 2 * gap
    self.cancel_rect = Geom:new{ x = x0, y = foot_y, w = button_w, h = foot_h }
    self.ok_rect = Geom:new{ x = x0 + button_w + gap, y = foot_y, w = button_w, h = foot_h }
    KoboldTaps.add(self, "KoboldConfirmTap", 0, 0, W, H, function(ges)
        local pos = ges.pos
        if inside(pos, self.ok_rect) then
            self.done = true
            KoboldPopup.close(self)
            if self.on_ok then self.on_ok() end
        elseif inside(pos, self.cancel_rect) or not inside(pos, self.frame_dimen) then
            self:onClose()
        end
    end)
end

function Confirm:onClose()
    KoboldPopup.close(self)
    if not self.done and self.on_cancel then self.on_cancel() end
    return true
end

-- A question with Cancel (or `cancel_text`) and `ok_text`. `on_ok` runs
-- when confirmed, `on_cancel` otherwise.
function KoboldPicker.confirm(text, ok_text, on_ok, on_cancel, cancel_text)
    KoboldPopup.show(Confirm:new{ text = text, ok_text = ok_text, cancel_text = cancel_text,
        on_ok = on_ok, on_cancel = on_cancel })
end

return KoboldPicker
