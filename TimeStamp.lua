local addonName = ...

local mfloor = math.floor

-- ---------------------------------------------------------------------------
-- Shared field refreshers (return true if there is something to show)
-- ---------------------------------------------------------------------------
local function refreshName(t)
    t:SetText(UnitName("player") .. " - " .. GetRealmName())
    return true
end

local function refreshClass(t)
    t:SetText("The " .. UnitClass("player"))
    return true
end

local function refreshGuild(t)
    local guildName, rankName = GetGuildInfo("player")
    if guildName ~= nil then
        t:SetText(rankName .. " of <" .. guildName .. ">")
        return true
    end
    return false
end

local function refreshLevel(t)
    local xpMax = UnitXPMax("player")
    local pct = (xpMax and xpMax > 0) and mfloor(UnitXP("player") / xpMax * 100) or 0
    t:SetText("Level: " .. UnitLevel("player") .. (pct > 0 and " XP: " .. pct .. "%" or ""))
    return true
end

local function refreshItemlvl(t)
    local _, equipped = GetAverageItemLevel()
    t:SetText("Item level: " .. mfloor(equipped or 0))
    return true
end

local function refreshZone(t)
    local zone = GetRealZoneText()
    local _, _, diff = GetInstanceInfo()
    t:SetText(zone .. (diff and diff > 0 and " " .. GetDifficultyInfo(diff) or ""))
    return true
end

local function refreshSubzone(t)
    local zone = GetRealZoneText()
    local sub = GetSubZoneText()
    if sub ~= "" and zone ~= sub then
        t:SetText(sub)
        return true
    end
    return false
end

local function refreshTimestamp(t)
    t:SetText(date("%B %d, %Y %I:%M%p"))
    return true
end

local function refreshXpack(t)
    t:SetText(_G["EXPANSION_NAME" .. GetExpansionLevel()] or "Midnight")
    return true
end

local FIELD_ORDER = {
    {name = "name",      title = true,  refresh = refreshName},
    {name = "class",     title = false, refresh = refreshClass},
    {name = "guild",     title = false, refresh = refreshGuild},
    {name = "level",     title = false, refresh = refreshLevel},
    {name = "itemlvl",   title = false, refresh = refreshItemlvl},
    {name = "zone",      title = true,  refresh = refreshZone},
    {name = "subzone",   title = false, refresh = refreshSubzone},
    {name = "timestamp", title = false, refresh = refreshTimestamp},
    {name = "xpack",     title = false, refresh = refreshXpack},
}

local function layoutParts(parts, anchor, gap)
    parts[1].fs:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
    parts[1].refresh(parts[1].fs)
    local last = parts[1].fs
    for i = 2, #parts do
        local p = parts[i]
        if p.refresh(p.fs) then
            local yOff = (p.name == "zone") and -gap or 0
            p.fs:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, yOff)
            last = p.fs
        else
            p.fs:SetText(" ")
        end
    end
end

-- ---------------------------------------------------------------------------
-- Screenshot bookkeeping: track which kind of shot is in flight so the
-- SCREENSHOT_SUCCEEDED/FAILED handler knows what to tear down.
-- ---------------------------------------------------------------------------
local pendingClean = false   -- a /ts clean shot (UIParent was hidden)

-- 1) Clean full-screen card (/ts). Top-level frame so it survives UIParent:Hide().
local shot = CreateFrame("Frame", "TimeStampFrame")
shot:SetFrameStrata("FULLSCREEN_DIALOG")
shot:Hide()

local PAD_TOP, PAD_SIDE = 8, 10
shot:SetPoint("TOPLEFT", UIParent, "TOPLEFT", PAD_SIDE, -PAD_TOP)
shot:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -PAD_SIDE, PAD_TOP)

local shotParts = {}
for i, def in ipairs(FIELD_ORDER) do
    local fs = shot:CreateFontString(nil, "OVERLAY", def.title and "QuestTitleFont" or "QuestFont")
    fs:SetTextColor(1, 0.8, 0, 1)
    shotParts[i] = {fs = fs, refresh = def.refresh, name = def.name}
end

-- 2) Info overlay (the flash). Lives on UIParent, hidden except at capture.
local hud = CreateFrame("Frame", "TimeStampHUD", UIParent)
hud:SetSize(300, 150)
hud:SetMovable(true)
hud:SetClampedToScreen(true)
hud:Hide()

local hudBG = hud:CreateTexture(nil, "BACKGROUND")
hudBG:SetAllPoints(hud)
hudBG:SetColorTexture(0, 0, 0, 0.35)
hudBG:Hide()

local hudParts = {}
for i, def in ipairs(FIELD_ORDER) do
    local fs = hud:CreateFontString(nil, "OVERLAY", def.title and "GameFontNormalLarge" or "GameFontNormal")
    fs:SetTextColor(1, 0.8, 0, 1)
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetShadowOffset(1, -1)
    hudParts[i] = {fs = fs, refresh = def.refresh, name = def.name}
end

local function updateHUD()
    layoutParts(hudParts, hud, 6)
end

hud:RegisterForDrag("LeftButton")
hud:SetScript("OnDragStart", function(self) if self:IsMovable() then self:StartMoving() end end)
hud:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    TimeStampDB.point, TimeStampDB.relPoint, TimeStampDB.x, TimeStampDB.y = point, relPoint, x, y
end)

local function msg(text) print("|cff00ccffTimeStamp|r: " .. text) end

-- Every screenshot WE take goes through here so the companion hook (below)
-- can tell our own shots apart from ones fired by other addons / the game.
local ourShot = false
local function rawScreenshot()
    ourShot = true
    Screenshot()
end

-- The two capture actions -----------------------------------------------------
local function flashShot()
    -- Normal screenshot (UI visible) + info overlay shown just for the capture.
    updateHUD()
    hud:Show()
    pendingClean = false
    rawScreenshot()
end

local function cleanShot()
    if InCombatLockdown() then
        msg("can't take a clean (UI-hidden) shot during combat - try /ts snap instead.")
        return
    end
    UIParent:Hide()
    layoutParts(shotParts, shot, PAD_TOP)
    shot:Show()
    pendingClean = true
    rawScreenshot()
end

-- Companion mode: when another addon or the game takes a screenshot, fire our
-- own overlay shot just after it (produces a second file). Off by default.
local companionScheduled = false
hooksecurefunc("Screenshot", function()
    if ourShot then
        ourShot = false          -- this was our own shot; ignore it
        return
    end
    if not (TimeStampDB and TimeStampDB.companion) then return end
    if companionScheduled then return end
    companionScheduled = true
    -- Let the original capture finish, then take ours with the overlay shown.
    C_Timer.After(0.15, function()
        companionScheduled = false
        flashShot()
    end)
end)

shot:RegisterEvent("SCREENSHOT_SUCCEEDED")
shot:RegisterEvent("SCREENSHOT_FAILED")
shot:SetScript("OnEvent", function()
    if pendingClean then
        shot:Hide()
        UIParent:Show()
        pendingClean = false
    end
    -- Hide the flash overlay again unless the user is positioning it.
    if TimeStampDB and TimeStampDB.locked then
        hud:Hide()
    end
end)

-- ---------------------------------------------------------------------------
-- SavedVariables + state
-- ---------------------------------------------------------------------------
local DEFAULTS = {
    locked = true,
    intercept = true,   -- hijack the screenshot key for the overlay shot
    companion = false,  -- also stamp screenshots taken by other addons / the game
    point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", x = 16, y = 240,
}

local function applyPosition()
    hud:ClearAllPoints()
    hud:SetPoint(TimeStampDB.point, UIParent, TimeStampDB.relPoint, TimeStampDB.x, TimeStampDB.y)
end

local function applyLock()
    if TimeStampDB.locked then
        hud:EnableMouse(false)
        hudBG:Hide()
        hud:Hide()
    else
        updateHUD()
        hud:EnableMouse(true)
        hudBG:Show()
        hud:Show()
    end
end

-- Remap the screenshot key to our overlay shot (out of combat only).
local snapBtn = CreateFrame("Button", "TimeStampSnapButton", UIParent)
snapBtn:RegisterForClicks("AnyDown")
snapBtn:SetScript("OnClick", flashShot)

local keybindDirty = false
local function applyKeybind()
    if InCombatLockdown() then keybindDirty = true; return end
    ClearOverrideBindings(snapBtn)
    if TimeStampDB and TimeStampDB.intercept then
        local k1, k2 = GetBindingKey("SCREENSHOT")
        if k1 then SetOverrideBindingClick(snapBtn, true, k1, "TimeStampSnapButton") end
        if k2 then SetOverrideBindingClick(snapBtn, true, k2, "TimeStampSnapButton") end
    end
    keybindDirty = false
end

-- First-run prompt: a small dialog with Enable / Keep Off plus a
-- "Don't remind me again" checkbox. Only the checkbox sets the saved flag,
-- so the choice (on/off) is separate from whether to keep asking.
local promptFrame
local function showCompanionPrompt()
    if promptFrame then
        promptFrame.check:SetChecked(false)
        promptFrame:Show()
        return
    end

    local f = CreateFrame("Frame", "TimeStampPrompt", UIParent, "BackdropTemplate")
    f:SetSize(440, 250)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -18)
    title:SetText("|cff00ccffTimeStamp|r")

    local body = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    body:SetPoint("TOPLEFT", 24, -46)
    body:SetPoint("TOPRIGHT", -24, -46)
    body:SetJustifyH("LEFT")
    body:SetSpacing(3)
    body:SetText("Would you like TimeStamp to add your character details to your screenshots automatically?\n\nWhen this is on, it works alongside Memoria, Memento, and any other addon that takes screenshots for you - whenever one of those snaps a shot, TimeStamp saves an extra copy with your details stamped on it.\n\nYou can change this anytime with |cffffd100/ts companion|r.")

    local check = CreateFrame("CheckButton", "TimeStampPromptCheck", f, "UICheckButtonTemplate")
    check:SetPoint("BOTTOMLEFT", 22, 18)
    check:SetSize(24, 24)
    local checkLabel = check:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    checkLabel:SetPoint("LEFT", check, "RIGHT", 4, 1)
    checkLabel:SetText("Don't remind me again")
    f.check = check

    local enable = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    enable:SetSize(110, 24)
    enable:SetPoint("BOTTOMRIGHT", -16, 16)
    enable:SetText("Enable")
    enable:SetScript("OnClick", function()
        TimeStampDB.companion = true
        if check:GetChecked() then TimeStampDB.seenCompanionPrompt = true end
        f:Hide()
        msg("companion mode |cff44ff44ON|r. Toggle anytime with /ts companion.")
    end)

    local keepoff = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    keepoff:SetSize(110, 24)
    keepoff:SetPoint("RIGHT", enable, "LEFT", -8, 0)
    keepoff:SetText("Keep Off")
    keepoff:SetScript("OnClick", function()
        TimeStampDB.companion = false
        if check:GetChecked() then TimeStampDB.seenCompanionPrompt = true end
        f:Hide()
        msg("companion mode left |cffff4444OFF|r. Turn it on later with /ts companion.")
    end)

    tinsert(UISpecialFrames, "TimeStampPrompt")  -- Esc closes it (no choice saved)

    promptFrame = f
    f:Show()
end

local init = CreateFrame("Frame")
init:RegisterEvent("ADDON_LOADED")
init:RegisterEvent("PLAYER_LOGIN")
init:RegisterEvent("UPDATE_BINDINGS")
init:RegisterEvent("PLAYER_REGEN_ENABLED")
init:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == addonName then
            TimeStampDB = TimeStampDB or {}
            for k, v in pairs(DEFAULTS) do
                if TimeStampDB[k] == nil then TimeStampDB[k] = v end
            end
            self:UnregisterEvent("ADDON_LOADED")
        end
    elseif event == "PLAYER_LOGIN" then
        applyPosition()
        applyLock()
        applyKeybind()
        if not TimeStampDB.seenCompanionPrompt then
            C_Timer.After(4, function()
                if not TimeStampDB.seenCompanionPrompt then
                    showCompanionPrompt()
                end
            end)
        end
    elseif event == "UPDATE_BINDINGS" then
        if TimeStampDB then applyKeybind() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if keybindDirty then applyKeybind() end
    end
end)

-- ---------------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------------
SLASH_TimeStamp1 = "/timestamp"
SLASH_TimeStamp2 = "/ts"
SlashCmdList["TimeStamp"] = function(input)
    local cmd = (input or ""):lower():match("^%s*(%S*)")
    if cmd == "snap" then
        flashShot()
    elseif cmd == "key" then
        TimeStampDB.intercept = not TimeStampDB.intercept
        applyKeybind()
        if TimeStampDB.intercept then
            local k1 = GetBindingKey("SCREENSHOT")
            msg("screenshot key overlay |cff44ff44ON|r" .. (k1 and (" (" .. k1 .. ")") or " - but no screenshot key is bound; use /ts snap"))
        else
            msg("screenshot key overlay |cffff4444OFF|r (your key takes a normal screenshot again)")
        end
    elseif cmd == "companion" then
        TimeStampDB.companion = not TimeStampDB.companion
        if TimeStampDB.companion then
            msg("companion mode |cff44ff44ON|r - screenshots from other addons/the game get a second, stamped shot.")
        else
            msg("companion mode |cffff4444OFF|r")
        end
    elseif cmd == "unlock" then
        TimeStampDB.locked = false
        applyLock()
        msg("overlay unlocked - drag it where you want, then /ts lock.")
    elseif cmd == "lock" then
        TimeStampDB.locked = true
        applyLock()
        msg("overlay locked and hidden until the next screenshot.")
    elseif cmd == "reset" then
        TimeStampDB.point, TimeStampDB.relPoint = DEFAULTS.point, DEFAULTS.relPoint
        TimeStampDB.x, TimeStampDB.y = DEFAULTS.x, DEFAULTS.y
        applyPosition()
        msg("overlay position reset.")
    elseif cmd == "help" or cmd == "?" then
        msg("commands:")
        print("  /ts            clean full-screen card (hides the UI)")
        print("  /ts snap       normal screenshot with the info overlay")
        print("  /ts key        toggle overlay on your screenshot key")
        print("  /ts companion  also stamp other addons' / the game's screenshots (2nd file)")
        print("  /ts unlock     show + unlock overlay to drag it")
        print("  /ts lock       lock + hide the overlay")
        print("  /ts reset      reset overlay position")
    else
        cleanShot()
    end
end
