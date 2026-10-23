local _, ns = ...

local Capture = {}
ns.Capture = Capture

local SAFETY_SECONDS = 3          -- restore everything even if no screenshot event arrives
local COMPANION_WAIT_SECONDS = 3  -- fallback if a foreign screenshot never reports back

local pending                -- "overlay" or "card" while one of our screenshots is in flight
local ownCall = false        -- true while we call Screenshot() ourselves
local hidUI = false          -- we hid UIParent for a clean card
local restoreAfterCombat = false
local safetyTimer
local companionQueued = false
local companionTimer
local countdownTicker
local keybindDirty = false
local appliedKeys

-- Large centered text (countdown and notices). Not parented to UIParent so it
-- can also be shown while the UI is hidden.
local notice = CreateFrame("Frame", "TimeStampNotice")
notice:SetFrameStrata("FULLSCREEN_DIALOG")
notice:SetSize(800, 160)
notice:Hide()

local noticeText = notice:CreateFontString(nil, "OVERLAY")
noticeText:SetPoint("CENTER")
noticeText:SetWidth(780)
noticeText:SetTextColor(1, 0.82, 0)

local function showNotice(text, size)
    noticeText:SetFont(ns.Fonts:Default(), size, "OUTLINE, THICK")
    noticeText:SetText(text)
    notice:SetScale(UIParent:GetEffectiveScale())
    notice:ClearAllPoints()
    notice:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
    notice:Show()
end

local function takeScreenshot()
    ownCall = true
    Screenshot()
    ownCall = false
end

local function restoreUI()
    if not hidUI then
        return
    end
    -- Showing UIParent is blocked in combat; wait for combat to end.
    if InCombatLockdown() then
        restoreAfterCombat = true
        local key = GetBindingKey("TOGGLEUI")
        showNotice("Your UI was hidden for a TimeStamp screenshot.\nIt comes back when you leave combat"
            .. (key and (" - or press " .. GetBindingText(key) .. ".") or "."), 18)
        return
    end
    hidUI = false
    restoreAfterCombat = false
    notice:Hide()
    UIParent:Show()
end

local function finish()
    if safetyTimer then
        safetyTimer:Cancel()
        safetyTimer = nil
    end
    if not pending then
        return
    end
    pending = nil
    restoreUI()
    ns.Overlay:EndCapture()
end

function Capture:IsBusy()
    return pending ~= nil
end

-- Starts a capture. The safety timer is armed first so the UI always comes
-- back, and a rendering error never prevents the screenshot itself.
local function beginCapture(mode)
    pending = mode
    safetyTimer = C_Timer.NewTimer(SAFETY_SECONDS, finish)
    local ok, err = pcall(ns.Overlay.ShowForCapture, ns.Overlay, mode)
    if not ok then
        geterrorhandler()(err)
    end
end

-- ---------------------------------------------------------------------------
-- The two kinds of shots
-- ---------------------------------------------------------------------------

-- Normal screenshot (UI visible) with the overlay shown just for the capture.
function Capture:Overlay()
    if pending or countdownTicker then
        return
    end
    beginCapture("overlay")
    takeScreenshot()
end

-- Clean card: UI hidden, only the character card on screen. Running it again
-- during the countdown cancels it.
function Capture:Card()
    if countdownTicker then
        self:CancelCountdown()
        ns.Print("clean shot cancelled.")
        return
    end
    if pending then
        return
    end
    if InCombatLockdown() then
        ns.Print("can't take a clean (UI-hidden) shot during combat - try /ts snap instead.")
        return
    end
    if ns.db.countdown > 0 then
        self:StartCountdown(ns.db.countdown)
    else
        self:CardNow()
    end
end

function Capture:CardNow()
    if pending then
        return
    end
    if InCombatLockdown() then
        ns.Print("can't take a clean (UI-hidden) shot during combat - try /ts snap instead.")
        return
    end
    beginCapture("card")
    -- IsBusy() is already true here, which matters: hiding UIParent fires OnHide
    -- handlers (e.g. the settings panel's) that check it.
    hidUI = UIParent:IsShown()
    if hidUI then
        UIParent:Hide()
    end
    takeScreenshot()
end

function Capture:StartCountdown(seconds)
    local remaining = seconds
    showNotice(tostring(remaining), 72)
    countdownTicker = C_Timer.NewTicker(1, function()
        remaining = remaining - 1
        if InCombatLockdown() then
            Capture:CancelCountdown()
            ns.Print("clean shot cancelled - you entered combat.")
        elseif remaining > 0 then
            showNotice(tostring(remaining), 72)
        else
            Capture:CancelCountdown()
            Capture:CardNow()
        end
    end)
end

function Capture:CancelCountdown()
    if countdownTicker then
        countdownTicker:Cancel()
        countdownTicker = nil
    end
    notice:Hide()
end

-- ---------------------------------------------------------------------------
-- Screenshot events and companion mode
-- ---------------------------------------------------------------------------
local function onScreenshotDone()
    if pending then
        finish()
    elseif companionQueued then
        companionQueued = false
        if companionTimer then
            companionTimer:Cancel()
            companionTimer = nil
        end
        -- Take our stamped copy on the next frame, after the other capture is done.
        C_Timer.After(0, function()
            Capture:Overlay()
        end)
    end
end

ns.RegisterEvent("SCREENSHOT_SUCCEEDED", onScreenshotDone)
ns.RegisterEvent("SCREENSHOT_FAILED", onScreenshotDone)

-- Companion mode: when another addon or the game takes a screenshot, follow it
-- with a stamped copy of our own (a second file).
hooksecurefunc("Screenshot", function()
    if ownCall or pending or companionQueued or not (ns.db and ns.db.companion) then
        return
    end
    companionQueued = true
    companionTimer = C_Timer.NewTimer(COMPANION_WAIT_SECONDS, function()
        companionTimer = nil
        if companionQueued then
            companionQueued = false
            Capture:Overlay()
        end
    end)
end)

-- ---------------------------------------------------------------------------
-- Screenshot key: route it through our overlay shot (out of combat only)
-- ---------------------------------------------------------------------------
local snapButton = CreateFrame("Button", "TimeStampSnapButton", UIParent)
snapButton:RegisterForClicks("AnyDown")
snapButton:SetScript("OnClick", function()
    Capture:Overlay()
end)

function Capture:ApplyKeybind()
    if not ns.db then
        return
    end
    if InCombatLockdown() then
        keybindDirty = true
        return
    end
    keybindDirty = false

    local key1, key2 = GetBindingKey("SCREENSHOT")
    local wanted = ns.db.intercept and ((key1 or "") .. "\n" .. (key2 or "")) or ""
    -- Changing override bindings fires UPDATE_BINDINGS; only touch them when needed.
    if wanted == appliedKeys then
        return
    end
    appliedKeys = wanted

    ClearOverrideBindings(snapButton)
    if ns.db.intercept then
        if key1 then
            SetOverrideBindingClick(snapButton, true, key1, "TimeStampSnapButton")
        end
        if key2 then
            SetOverrideBindingClick(snapButton, true, key2, "TimeStampSnapButton")
        end
    end
end

ns.RegisterEvent("PLAYER_LOGIN", function()
    Capture:ApplyKeybind()
end)

ns.RegisterEvent("UPDATE_BINDINGS", function()
    Capture:ApplyKeybind()
end)

ns.RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if keybindDirty then
        Capture:ApplyKeybind()
    end
    if restoreAfterCombat then
        restoreUI()
    end
end)

-- If the player brings the UI back themselves (e.g. Alt+Z) while we wait for
-- combat to end, stop waiting.
UIParent:HookScript("OnShow", function()
    if hidUI and not pending then
        hidUI = false
        restoreAfterCombat = false
        notice:Hide()
    end
end)
