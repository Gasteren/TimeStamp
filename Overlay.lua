local _, ns = ...

local Overlay = {}
ns.Overlay = Overlay

local max, min = math.max, math.min
local IsSecret = ns.IsSecret

local PADDING = 8
local FADE_EXTRA = 48
local POSITION_MARGIN = 16

-- "OUTLINE, THICK" is the form Blizzard's own code uses for a thick outline.
local OUTLINE_FLAGS = { NONE = "", OUTLINE = "OUTLINE", THICKOUTLINE = "OUTLINE, THICK" }

local BOX_BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileEdge = true,
    tileSize = 16,
    edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

-- One frame serves both shots. It has no parent so it stays visible while
-- UIParent is hidden for the clean card; scale is matched to UIParent manually.
local frame = CreateFrame("Frame", "TimeStampOverlay", nil, "BackdropTemplate")
frame:SetFrameStrata("FULLSCREEN_DIALOG")
frame:SetClampedToScreen(true)
frame:SetMovable(true)
frame:EnableMouse(false)
frame:RegisterForDrag("LeftButton")
if frame.SetDontSavePosition then
    frame:SetDontSavePosition(true)
end
frame:Hide()
Overlay.frame = frame

local shade = frame:CreateTexture(nil, "BACKGROUND")
shade:SetAllPoints()
local fadeLeft = frame:CreateTexture(nil, "BACKGROUND")
fadeLeft:SetColorTexture(1, 1, 1, 1)
local fadeRight = frame:CreateTexture(nil, "BACKGROUND")
fadeRight:SetColorTexture(1, 1, 1, 1)

local fontStrings = {}

Overlay.mode = "overlay"          -- placement in use: "overlay" or "card"
Overlay.previewMode = "overlay"   -- what the preview shows
Overlay.previewSources = {}       -- reasons the preview is visible ("settings", "unlock")
Overlay.interactive = false

-- ---------------------------------------------------------------------------
-- Rendering helpers
-- ---------------------------------------------------------------------------
local function getFontString(index)
    local fs = fontStrings[index]
    if not fs then
        fs = frame:CreateFontString(nil, "OVERLAY")
        fs:SetWordWrap(false)
        fontStrings[index] = fs
    end
    return fs
end

-- A missing or invalid font file must never leave a font string without a font.
local function setFont(fs, key, size, flags)
    local ok, success = pcall(fs.SetFont, fs, ns.Fonts:Resolve(key), size, flags)
    if not (ok and success) then
        pcall(fs.SetFont, fs, ns.Fonts:Default(), size, flags)
    end
    if not fs:GetFont() then
        fs:SetFontObject(GameFontNormal)
    end
end

local function parseColor(hex, fallback)
    if type(hex) ~= "string" or not hex:match("^%x%x%x%x%x%x%x%x$") then
        hex = fallback
    end
    return tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, tonumber(hex:sub(7, 8), 16) / 255
end

local function resolveAlign(align, point)
    if align == "LEFT" or align == "CENTER" or align == "RIGHT" then
        return align
    end
    if point:find("LEFT") then
        return "LEFT"
    elseif point:find("RIGHT") then
        return "RIGHT"
    end
    return "CENTER"
end

local function measure(fs, size)
    local width, height = fs:GetStringWidth(), fs:GetStringHeight()
    if type(width) ~= "number" or IsSecret(width) then
        width = size * 16
    end
    if type(height) ~= "number" or IsSecret(height) or height <= 0 then
        height = size
    end
    return width, height
end

local function setFade(texture, fromAlpha, toAlpha)
    texture:SetGradient("HORIZONTAL", CreateColor(0, 0, 0, fromAlpha), CreateColor(0, 0, 0, toAlpha))
    texture:Show()
end

local function applyBackground(style, opacity, align)
    frame:SetBackdrop(nil)
    shade:Hide()
    fadeLeft:Hide()
    fadeRight:Hide()

    if style == "box" then
        frame:SetBackdrop(BOX_BACKDROP)
        frame:SetBackdropColor(0, 0, 0, opacity)
        frame:SetBackdropBorderColor(0.8, 0.8, 0.8, min(1, opacity + 0.3))
    elseif style == "shade" then
        shade:SetColorTexture(0, 0, 0, opacity)
        shade:Show()
    elseif style == "fade" then
        -- Solid behind the text, fading out past its open side(s).
        fadeLeft:ClearAllPoints()
        fadeRight:ClearAllPoints()
        if align == "LEFT" then
            fadeLeft:SetPoint("TOPLEFT")
            fadeLeft:SetPoint("BOTTOMRIGHT", FADE_EXTRA, 0)
            setFade(fadeLeft, opacity, 0)
        elseif align == "RIGHT" then
            fadeLeft:SetPoint("TOPLEFT", -FADE_EXTRA, 0)
            fadeLeft:SetPoint("BOTTOMRIGHT")
            setFade(fadeLeft, 0, opacity)
        else
            fadeLeft:SetPoint("TOPLEFT", -FADE_EXTRA, 0)
            fadeLeft:SetPoint("BOTTOMRIGHT", frame, "BOTTOM")
            setFade(fadeLeft, 0, opacity)
            fadeRight:SetPoint("TOPLEFT", frame, "TOP")
            fadeRight:SetPoint("BOTTOMRIGHT", FADE_EXTRA, 0)
            setFade(fadeRight, opacity, 0)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Rendering and placement
-- ---------------------------------------------------------------------------
function Overlay:Render(mode, interactive)
    local db = ns.db
    local place = db[mode]
    local lines = ns.Fields:BuildLines(db)
    if #lines == 0 and interactive then
        lines[1] = { text = "TimeStamp", title = true, gap = 0 }
    end

    local align = resolveAlign(db.align, place.point)
    local flags = OUTLINE_FLAGS[db.outline] or ""
    local titleR, titleG, titleB = parseColor(db.titleColor, ns.DEFAULTS.titleColor)
    local textR, textG, textB = parseColor(db.textColor, ns.DEFAULTS.textColor)

    local y, width = PADDING, 0
    for i, line in ipairs(lines) do
        local fs = getFontString(i)
        local size = line.title and db.titleSize or db.textSize
        setFont(fs, line.title and db.titleFont or db.textFont, size, flags)
        if line.title then
            fs:SetTextColor(titleR, titleG, titleB)
        else
            fs:SetTextColor(textR, textG, textB)
        end
        fs:SetShadowColor(0, 0, 0, 1)
        if db.shadow then
            fs:SetShadowOffset(1, -1)
        else
            fs:SetShadowOffset(0, 0)
        end
        fs:SetJustifyH(align)
        fs:SetText(line.text)

        if i > 1 then
            y = y + db.lineSpacing
        end
        y = y + line.gap * db.spacerSize

        fs:ClearAllPoints()
        if align == "LEFT" then
            fs:SetPoint("TOPLEFT", PADDING, -y)
        elseif align == "RIGHT" then
            fs:SetPoint("TOPRIGHT", -PADDING, -y)
        else
            fs:SetPoint("TOP", 0, -y)
        end

        local lineWidth, lineHeight = measure(fs, size)
        width = max(width, lineWidth)
        y = y + lineHeight
        fs:Show()
    end
    for i = #lines + 1, #fontStrings do
        fontStrings[i]:Hide()
    end

    self.empty = #lines == 0
    frame:SetSize(max(width, 1) + PADDING * 2, y + PADDING)

    local style, opacity = db.background, db.bgOpacity
    if interactive and style == "none" then
        style, opacity = "shade", 0.35
    end
    applyBackground(self.empty and "none" or style, opacity, align)

    self.mode = mode
    self:ApplyPlacement()
end

function Overlay:ApplyPlacement()
    local place = ns.db[self.mode]
    frame:SetScale(UIParent:GetEffectiveScale() * place.scale)
    frame:ClearAllPoints()
    frame:SetPoint(place.point, UIParent, place.point, place.x / place.scale, place.y / place.scale)
end

-- Screen position (in pixels) of `point` on a region.
local function pointPosition(region, point)
    local left, bottom, width, height = region:GetRect()
    if not left or IsSecret(left) or IsSecret(bottom) or IsSecret(width) or IsSecret(height) then
        return
    end
    local scale = region:GetEffectiveScale()
    local x = point:find("LEFT") and left or point:find("RIGHT") and left + width or left + width / 2
    local y = point:find("TOP") and bottom + height or point:find("BOTTOM") and bottom or bottom + height / 2
    return x * scale, y * scale
end

function Overlay:SavePosition()
    local place = ns.db[self.mode]
    local frameX, frameY = pointPosition(frame, place.point)
    local screenX, screenY = pointPosition(UIParent, place.point)
    if frameX and screenX then
        local uiScale = UIParent:GetEffectiveScale()
        place.x = ns.Round((frameX - screenX) / uiScale)
        place.y = ns.Round((frameY - screenY) / uiScale)
    end
    self:ApplyPlacement()
end

-- Keeps the current anchor point but moves the frame to its standard spot.
function Overlay:ResetOffsets(mode)
    local place, default = ns.db[mode], ns.DEFAULTS[mode]
    if place.point == default.point then
        place.x, place.y = default.x, default.y
    else
        place.x, place.y = ns.EdgeOffsets(place.point, POSITION_MARGIN)
    end
end

function Overlay:ResetPosition(mode)
    ns.db[mode].point = ns.DEFAULTS[mode].point
    self:ResetOffsets(mode)
    ns.Options:Notify(mode .. ".point")
    self:Update()
end

-- ---------------------------------------------------------------------------
-- Visibility: hidden while you play, shown for captures and previews
-- ---------------------------------------------------------------------------
function Overlay:IsPreviewing()
    return next(self.previewSources) ~= nil
end

function Overlay:Update()
    if not ns.db or ns.Capture:IsBusy() then
        return
    end
    if self:IsPreviewing() then
        self.interactive = true
        frame:EnableMouse(true)
        self:Render(self.previewMode, true)
        frame:Show()
    else
        self.interactive = false
        frame:EnableMouse(false)
        frame:Hide()
    end
end

function Overlay:SetPreview(source, enabled)
    self.previewSources[source] = enabled and true or nil
    self:Update()
end

function Overlay:ShowPreview(mode)
    self.previewMode = mode
    self:SetPreview("settings", true)
end

function Overlay:Unlock(mode)
    self.previewMode = mode
    self:SetPreview("unlock", true)
end

function Overlay:Lock()
    self:SetPreview("unlock", false)
end

function Overlay:Dismiss()
    wipe(self.previewSources)
    self:Update()
end

function Overlay:ShowForCapture(mode)
    self.interactive = false
    frame:EnableMouse(false)
    if GameTooltip:IsOwned(frame) then
        GameTooltip:Hide()
    end
    self:Render(mode, false)
    frame:SetShown(not self.empty)
end

function Overlay:EndCapture()
    self:Update()
end

-- ---------------------------------------------------------------------------
-- Dragging (preview only)
-- ---------------------------------------------------------------------------
frame:SetScript("OnDragStart", function(self)
    if Overlay.interactive then
        self:StartMoving()
    end
end)

frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    if Overlay.interactive then
        Overlay:SavePosition()
    end
end)

frame:SetScript("OnMouseUp", function(_, button)
    if button == "RightButton" and Overlay.interactive then
        Overlay:Dismiss()
    end
end)

frame:SetScript("OnEnter", function(self)
    if not Overlay.interactive then
        return
    end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(Overlay.mode == "card" and "TimeStamp clean card" or "TimeStamp overlay", 1, 1, 1)
    GameTooltip:AddLine("Drag to move. Right-click to hide this preview.", 1, 0.82, 0, true)
    GameTooltip:Show()
end)

frame:SetScript("OnLeave", function(self)
    if GameTooltip:IsOwned(self) then
        GameTooltip:Hide()
    end
end)

local function onScreenChanged()
    if frame:IsShown() then
        Overlay:ApplyPlacement()
    end
end
ns.RegisterEvent("UI_SCALE_CHANGED", onScreenChanged)
ns.RegisterEvent("DISPLAY_SIZE_CHANGED", onScreenChanged)
