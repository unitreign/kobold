-- kobold/ui/prompts.lua — Kobold
-- Kobold's own popups for messages, typing and numbers, in the style of its
-- other popups (a rounded box), used in place of KOReader's dialogs:
--   KoboldPrompts.Notice  a message box; a drop-in for KOReader's
--                         InfoMessage (text, timeout), closed by a tap
--   KoboldPrompts.text    a text box with the keyboard below, Cancel / Save
--   KoboldPrompts.number  a number with - and + buttons, Cancel / Set

local Blitbuffer      = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device          = require("device")
local FrameContainer  = require("ui/widget/container/framecontainer")
local Geom            = require("ui/geometry")
local GestureRange    = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local InputContainer  = require("ui/widget/container/inputcontainer")
local InputText       = require("ui/widget/inputtext")
local LineWidget      = require("ui/widget/linewidget")
local TextBoxWidget   = require("ui/widget/textboxwidget")
local TextWidget      = require("ui/widget/textwidget")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("kobold.l10n")
local KoboldPopup     = require("kobold.ui.popup")
local KoboldWidgets   = require("kobold.ui.widgets")

local Screen = Device.screen

local KoboldPrompts = {}

local function inside(pos, r)
    return r and pos.x >= r.x and pos.x < r.x + r.w and pos.y >= r.y and pos.y < r.y + r.h
end

-- Box sizes shared by the popups here.
local function sizes()
    local W = Screen:getWidth()
    local border = Screen:scaleBySize(2)
    local pad = Screen:scaleBySize(20)
    local w = math.min(W - 2 * Screen:scaleBySize(36), Screen:scaleBySize(560))
    return { border = border, pad = pad, w = w, inner = w - 2 * (border + pad), gap = Screen:scaleBySize(14) }
end

local function frame(S, content)
    return FrameContainer:new{
        bordersize = S.border, padding = S.pad,
        radius = KoboldPopup.radius(),
        background = Blitbuffer.COLOR_WHITE,
        content,
    }
end

-- A grey button, as in Kobold's panels.
local function button(text, w, h)
    return FrameContainer:new{
        bordersize = 0, padding = 0, background = Blitbuffer.COLOR_LIGHT_GRAY,
        CenterContainer:new{ dimen = Geom:new{ w = w, h = h },
            TextWidget:new{ text = text, face = KoboldWidgets.italicFace(17), max_width = w } },
    }
end

-- Notice ---------------------------------------------------------------------

-- A message in a box in the middle of the screen. Shown and closed like
-- KOReader's InfoMessage (UIManager:show / UIManager:close); `timeout`
-- closes it by itself after that many seconds. Any tap closes it.
local Notice = InputContainer:extend{
    modal = true,
    name = "kobold_notice",
    text = "",
    timeout = nil,
}

function Notice:init()
    local W, H = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = W, h = H }
    local S = sizes()
    local text = TextBoxWidget:new{ text = tostring(self.text or ""), face = KoboldWidgets.face(17),
        width = S.inner, alignment = "center" }
    if text:getSize().h > math.floor(H * 0.6) then
        text = TextBoxWidget:new{ text = tostring(self.text or ""), face = KoboldWidgets.face(17),
            width = S.inner, alignment = "center",
            height = math.floor(H * 0.6), height_overflow_show_ellipsis = true }
    end
    local box = frame(S, text)
    local size = box:getSize()
    local x, y = math.floor((W - size.w) / 2), math.floor((H - size.h) / 2)
    self.frame_dimen = Geom:new{ x = x, y = y, w = size.w, h = size.h }
    self[1] = KoboldPopup.place(self.dimen, x, y, box)
    if Device:hasKeys() then
        self.key_events = { Close = { { Device.input.group.Back } } }
    end
    if Device:isTouchDevice() then
        self.ges_events = { TapNotice = { GestureRange:new{ ges = "tap", range = self.dimen } } }
    end
end

function Notice:onShow()
    UIManager:setDirty(self, function() return "ui", self.frame_dimen end)
    if self.timeout then
        UIManager:scheduleIn(self.timeout, function() self:onClose() end)
    end
    return true
end

function Notice:onCloseWidget()
    UIManager:setDirty(nil, function() return "ui", self.frame_dimen end)
end

function Notice:onTapNotice()
    return self:onClose()
end

function Notice:onClose()
    if self.closed then return true end
    self.closed = true
    UIManager:close(self)
    return true
end

KoboldPrompts.Notice = Notice

-- Text -------------------------------------------------------------------

local TextPrompt = InputContainer:extend{
    name = "kobold_text_prompt",
    -- Also gets taps the keyboard does not use, so a tap outside the box
    -- cancels (KOReader gives a tap to the keyboard first).
    is_always_active = true,
    title = nil,
    description = nil, -- grey text under the title
    notice = nil,      -- a small note under the field (in italics)
    text = "",
    hint = nil,
    ok_text = nil,
    on_ok = nil,       -- on_ok(text) -> nil to close, or a message to stay open
    on_cancel = nil,
}

function TextPrompt:init()
    local W, H = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = W, h = H }
    local S = sizes()
    local foot_h = Screen:scaleBySize(50)
    local button_w = math.floor((S.inner - S.gap) / 2)
    self.input = InputText:new{
        text = self.text or "",
        hint = self.hint or "",
        face = KoboldWidgets.face(18),
        width = S.inner,
        bordersize = 0, padding = 0, margin = 0,
        focused = true,
        parent = self,
        enter_callback = function() self:submit() end,
    }
    local content = VerticalGroup:new{ align = "left" }
    local top_h = 0
    local function add(widget)
        content[#content + 1] = widget
        top_h = top_h + widget:getSize().h
    end
    if self.title then
        add(TextWidget:new{ text = self.title, face = KoboldWidgets.face(19), bold = true, max_width = S.inner })
        add(VerticalSpan:new{ width = S.gap })
    end
    if self.description then
        add(TextBoxWidget:new{ text = self.description, face = KoboldWidgets.face(14), width = S.inner,
            fgcolor = KoboldWidgets.subtitleColor() })
        add(VerticalSpan:new{ width = S.gap })
    end
    add(self.input)
    add(LineWidget:new{ dimen = Geom:new{ w = S.inner, h = Screen:scaleBySize(2) },
        background = Blitbuffer.COLOR_DARK_GRAY })
    if self.notice then
        add(VerticalSpan:new{ width = S.gap })
        add(TextBoxWidget:new{ text = self.notice, face = KoboldWidgets.italicFace(14), width = S.inner })
    end
    add(VerticalSpan:new{ width = 2 * S.gap })
    content[#content + 1] = HorizontalGroup:new{
        button(_("Cancel"), button_w, foot_h),
        HorizontalSpan:new{ width = S.gap },
        button(self.ok_text or _("Save"), button_w, foot_h),
    }
    local box = frame(S, content)
    local size = box:getSize()
    -- Near the top, so the keyboard below leaves it in view.
    local x = math.floor((W - size.w) / 2)
    local y = math.max(Screen:scaleBySize(40), math.floor(H * 0.08))
    self.frame_dimen = Geom:new{ x = x, y = y, w = size.w, h = size.h }
    self[1] = KoboldPopup.place(self.dimen, x, y, box)
    local x0, y0 = x + S.border + S.pad, y + S.border + S.pad
    self.cancel_rect = Geom:new{ x = x0, y = y0 + top_h, w = button_w, h = foot_h }
    self.ok_rect = Geom:new{ x = x0 + button_w + S.gap, y = y0 + top_h, w = button_w, h = foot_h }
    if Device:hasKeys() then
        self.key_events = { Close = { { Device.input.group.Back } } }
    end
    if Device:isTouchDevice() then
        self.ges_events = { TapPrompt = { GestureRange:new{ ges = "tap", range = self.dimen } } }
    end
end

function TextPrompt:submit()
    local text = (self.input:getText() or ""):match("^%s*(.-)%s*$")
    local problem = self.on_ok and self.on_ok(text)
    if problem then
        UIManager:show(Notice:new{ text = problem, timeout = 3 })
        return
    end
    self.done = true
    self:onClose()
end

function TextPrompt:onTapPrompt(_, ges)
    if self.closed then return false end
    local pos = ges.pos
    if inside(pos, self.ok_rect) then self:submit() return true end
    if inside(pos, self.cancel_rect) or not inside(pos, self.frame_dimen) then return self:onClose() end
    self.input:onShowKeyboard()
    return true
end

function TextPrompt:onClose()
    if self.closed then return true end
    self.closed = true
    self.input:onCloseKeyboard()
    UIManager:close(self, "ui", self.frame_dimen)
    if not self.done and self.on_cancel then self.on_cancel() end
    return true
end

-- A line of text, typed with the keyboard. opts = { title, description,
-- notice, text, hint, ok_text, on_ok, on_cancel }; on_ok(text) gets the
-- trimmed text and returns nil to close, or a message to show and stay open.
function KoboldPrompts.text(opts)
    local w = TextPrompt:new(opts)
    UIManager:show(w, "ui", w.frame_dimen)
    w.input:onShowKeyboard()
    return w
end

-- Number -------------------------------------------------------------------

local NumberPrompt = InputContainer:extend{
    name = "kobold_number_prompt",
    title = nil,
    info = nil,
    value = 1, min = 1, max = 99, default = nil,
    on_set = nil,
    on_cancel = nil,
}

function NumberPrompt:init()
    local W, H = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = W, h = H }
    if Device:hasKeys() then
        self.key_events = { Close = { { Device.input.group.Back } } }
    end
    if Device:isTouchDevice() then
        self.ges_events = { TapNumber = { GestureRange:new{ ges = "tap", range = self.dimen } } }
    end
    self[1] = self:build()
end

function NumberPrompt:build()
    local W, H = Screen:getWidth(), Screen:getHeight()
    local S = sizes()
    local foot_h = Screen:scaleBySize(50)
    local step_sz = Screen:scaleBySize(64)
    local button_w = math.floor((S.inner - S.gap) / 2)
    local content = VerticalGroup:new{ align = "left" }
    local top_h = 0
    local function add(widget)
        content[#content + 1] = widget
        top_h = top_h + widget:getSize().h
    end
    add(TextWidget:new{ text = self.title or "", face = KoboldWidgets.face(19), bold = true, max_width = S.inner })
    if self.info then
        add(VerticalSpan:new{ width = S.gap })
        add(TextBoxWidget:new{ text = self.info, face = KoboldWidgets.face(14), width = S.inner,
            fgcolor = KoboldWidgets.subtitleColor() })
    end
    add(VerticalSpan:new{ width = S.gap })
    local stepper_y = top_h
    local function stepButton(text, active)
        return FrameContainer:new{
            bordersize = Screen:scaleBySize(2), padding = 0, radius = math.floor(step_sz / 2),
            color = active and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_LIGHT_GRAY,
            background = Blitbuffer.COLOR_WHITE,
            CenterContainer:new{ dimen = Geom:new{ w = step_sz - 4, h = step_sz - 4 },
                TextWidget:new{ text = text, face = KoboldWidgets.face(26),
                    fgcolor = active and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY } },
        }
    end
    local mid_w = S.inner - 2 * step_sz
    add(HorizontalGroup:new{
        align = "center",
        stepButton("−", self.value > self.min),
        CenterContainer:new{ dimen = Geom:new{ w = mid_w, h = step_sz },
            TextWidget:new{ text = tostring(self.value), face = KoboldWidgets.face(30), bold = true } },
        stepButton("+", self.value < self.max),
    })
    if self.default then
        add(CenterContainer:new{ dimen = Geom:new{ w = S.inner, h = Screen:scaleBySize(30) },
            TextWidget:new{ text = _.T(_("Default: %1"), self.default), face = KoboldWidgets.face(13),
                fgcolor = KoboldWidgets.subtitleColor() } })
    end
    add(VerticalSpan:new{ width = 2 * S.gap })
    content[#content + 1] = HorizontalGroup:new{
        button(_("Cancel"), button_w, foot_h),
        HorizontalSpan:new{ width = S.gap },
        button(_("Set"), button_w, foot_h),
    }
    local box = frame(S, content)
    local size = box:getSize()
    local x, y = math.floor((W - size.w) / 2), math.floor((H - size.h) / 2)
    self.frame_dimen = Geom:new{ x = x, y = y, w = size.w, h = size.h }
    local x0, y0 = x + S.border + S.pad, y + S.border + S.pad
    self.minus_rect = Geom:new{ x = x0, y = y0 + stepper_y, w = step_sz, h = step_sz }
    self.plus_rect = Geom:new{ x = x0 + S.inner - step_sz, y = y0 + stepper_y, w = step_sz, h = step_sz }
    self.cancel_rect = Geom:new{ x = x0, y = y0 + top_h, w = button_w, h = foot_h }
    self.ok_rect = Geom:new{ x = x0 + button_w + S.gap, y = y0 + top_h, w = button_w, h = foot_h }
    return KoboldPopup.place(self.dimen, x, y, box)
end

function NumberPrompt:step(delta)
    local v = math.max(self.min, math.min(self.max, self.value + delta))
    if v == self.value then return end
    self.value = v
    self[1] = self:build()
    UIManager:setDirty(self, "ui", self.frame_dimen)
end

function NumberPrompt:onTapNumber(_, ges)
    local pos = ges.pos
    if inside(pos, self.minus_rect) then self:step(-1)
    elseif inside(pos, self.plus_rect) then self:step(1)
    elseif inside(pos, self.ok_rect) then
        self.done = true
        self:onClose()
        if self.on_set then self.on_set(self.value) end
    elseif inside(pos, self.cancel_rect) or not inside(pos, self.frame_dimen) then
        self:onClose()
    end
    return true
end

function NumberPrompt:onClose()
    if self.closed then return true end
    self.closed = true
    UIManager:close(self, "ui", self.frame_dimen)
    if not self.done and self.on_cancel then self.on_cancel() end
    return true
end

-- A number between opts.min and opts.max. opts = { title, info, value, min,
-- max, default, on_set(value), on_cancel }.
function KoboldPrompts.number(opts)
    local w = NumberPrompt:new(opts)
    UIManager:show(w, "ui", w.frame_dimen)
    return w
end

return KoboldPrompts
