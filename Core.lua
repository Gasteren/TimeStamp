local addonName, ns = ...

local floor, min, max = math.floor, math.min, math.max

ns.NUM_LINES = 14
ns.isForever = WOW_PROJECT_CAMELOT ~= nil and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT

ns.POINTS = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }
ns.POINT_SET = {}
for _, point in ipairs(ns.POINTS) do
    ns.POINT_SET[point] = true
end

ns.DEFAULTS = {
    -- capturing
    intercept = true,   -- the normal screenshot key also shows the overlay
    companion = false,  -- stamp an extra copy of screenshots taken by other addons / the game
    countdown = 0,      -- seconds before a clean card shot

    -- placement: x/y are UIParent units between the same `point` of the frame and the screen
    overlay = { point = "BOTTOMLEFT", x = 16, y = 240, scale = 1 },
    card = { point = "TOPLEFT", x = 16, y = -16, scale = 1.2 },

    -- appearance
    titleFont = "default",
    titleSize = 16,
    textFont = "default",
    textSize = 12,
    outline = "NONE",
    shadow = true,
    titleColor = "ffffcc00",
    textColor = "ffffcc00",
    classColorName = false,
    background = "none",
    bgOpacity = 0.5,

    -- layout
    arrangement = "stacked",
    separator = "dot",
    align = "AUTO",
    lineSpacing = 2,
    spacerSize = 8,
    lines = { "name", "class", "guild", "level", "itemlvl", "spacer", "zone", "subzone", "date", "xpack", "note", "none", "none", "none" },

    -- line details
    showRealm = true,
    showTitle = false,
    showRace = true,
    showSpec = false,
    showRank = true,
    showXP = true,
    dateFormat = "long12",
}

local RANGES = {
    countdown = { 0, 10 },
    titleSize = { 8, 64 },
    textSize = { 6, 48 },
    bgOpacity = { 0, 1 },
    lineSpacing = { 0, 20 },
    spacerSize = { 0, 40 },
}
ns.SCALE_RANGE = { 0.5, 2.5 }

local CHOICES = {
    outline = { NONE = true, OUTLINE = true, THICKOUTLINE = true },
    background = { none = true, shade = true, fade = true, box = true },
    arrangement = { stacked = true, compact = true },
    align = { AUTO = true, LEFT = true, CENTER = true, RIGHT = true },
}

local function listHasKey(list, key)
    for _, entry in ipairs(list) do
        if entry.key == key then
            return true
        end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Utilities
-- ---------------------------------------------------------------------------
function ns.Print(text)
    print("|cff00ccffTimeStamp|r: " .. text)
end

-- Midnight-era clients can hand addons "secret" values: they may be displayed
-- and concatenated, but comparing them or doing math with them is an error.
function ns.IsSecret(value)
    return issecretvalue ~= nil and issecretvalue(value) == true
end

function ns.HasText(value)
    if not value then
        return false
    end
    if ns.IsSecret(value) then
        return true
    end
    return value ~= ""
end

function ns.Round(value)
    return floor(value + 0.5)
end

-- Offsets that keep a frame anchored at `point` a `margin` away from the screen edges.
function ns.EdgeOffsets(point, margin)
    local x = point:find("LEFT") and margin or point:find("RIGHT") and -margin or 0
    local y = point:find("TOP") and -margin or point:find("BOTTOM") and margin or 0
    return x, y
end

local function copyTable(source)
    local copy = {}
    for k, v in pairs(source) do
        copy[k] = type(v) == "table" and copyTable(v) or v
    end
    return copy
end
ns.CopyTable = copyTable

-- ---------------------------------------------------------------------------
-- Saved variables
-- ---------------------------------------------------------------------------
local function applyDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(target[k]) ~= "table" then
                target[k] = copyTable(v)
            else
                applyDefaults(target[k], v)
            end
        elseif type(target[k]) ~= type(v) then
            target[k] = v
        end
    end
end

local function sanitize(db, charDB)
    for key, range in pairs(RANGES) do
        db[key] = min(range[2], max(range[1], db[key]))
    end

    for key, allowed in pairs(CHOICES) do
        if not allowed[db[key]] then
            db[key] = ns.DEFAULTS[key]
        end
    end
    if not listHasKey(ns.Fields.SEPARATORS, db.separator) then
        db.separator = ns.DEFAULTS.separator
    end
    if not listHasKey(ns.Fields.DATE_FORMATS, db.dateFormat) then
        db.dateFormat = ns.DEFAULTS.dateFormat
    end
    for _, key in ipairs({ "titleColor", "textColor" }) do
        if not db[key]:match("^%x%x%x%x%x%x%x%x$") then
            db[key] = ns.DEFAULTS[key]
        end
    end

    for _, mode in ipairs({ "overlay", "card" }) do
        local place, default = db[mode], ns.DEFAULTS[mode]
        if not ns.POINT_SET[place.point] then
            place.point, place.x, place.y = default.point, default.x, default.y
        end
        place.scale = min(ns.SCALE_RANGE[2], max(ns.SCALE_RANGE[1], place.scale))
    end

    -- Every field may appear at most once; unknown entries become empty lines.
    local seen = {}
    for i = 1, ns.NUM_LINES do
        local key = db.lines[i]
        if key ~= "spacer" and key ~= "none" then
            if ns.Fields.byKey[key] and not seen[key] then
                seen[key] = true
            else
                key = "none"
            end
        end
        db.lines[i] = key
    end
    for i = #db.lines, ns.NUM_LINES + 1, -1 do
        db.lines[i] = nil
    end

    if type(charDB.note) ~= "string" or charDB.note == "" then
        charDB.note = nil
    end
end

-- Version 1 stored a single anchor for a fixed 300x150 frame.
local function migrate(db)
    if (tonumber(db.version) or 1) < 2 then
        if type(db.point) == "string" then
            local legacy = {
                point = db.point,
                relPoint = type(db.relPoint) == "string" and db.relPoint or db.point,
                x = tonumber(db.x) or 0,
                y = tonumber(db.y) or 0,
            }
            local isDefault = legacy.point == "BOTTOMLEFT" and legacy.relPoint == "BOTTOMLEFT"
                and legacy.x == 16 and legacy.y == 240
            if not isDefault then
                ns.legacyPosition = legacy
            end
        end
        db.point, db.relPoint, db.x, db.y, db.locked = nil, nil, nil, nil, nil
    end
    db.version = 2
end

local LEGACY_WIDTH, LEGACY_HEIGHT = 300, 150

-- Keeps the text where the old version drew it (its top-left corner).
local function convertLegacyPosition()
    local legacy = ns.legacyPosition
    ns.legacyPosition = nil
    if not (legacy and ns.POINT_SET[legacy.point] and ns.POINT_SET[legacy.relPoint]) then
        return
    end

    local p, rp = legacy.point, legacy.relPoint
    local width, height = UIParent:GetWidth(), UIParent:GetHeight()
    local ax = (rp:find("LEFT") and 0 or rp:find("RIGHT") and width or width / 2) + legacy.x
    local ay = (rp:find("TOP") and height or rp:find("BOTTOM") and 0 or height / 2) + legacy.y
    local left = p:find("LEFT") and ax or p:find("RIGHT") and ax - LEGACY_WIDTH or ax - LEGACY_WIDTH / 2
    local top = p:find("TOP") and ay or p:find("BOTTOM") and ay + LEGACY_HEIGHT or ay + LEGACY_HEIGHT / 2

    local overlay = ns.db.overlay
    overlay.point = "TOPLEFT"
    overlay.x = ns.Round(left)
    overlay.y = ns.Round(top - height)
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------
local safecall = securecallfunction or pcall
local eventFrame = CreateFrame("Frame")
local eventHandlers = {}
local initCallbacks = {}

function ns.RegisterEvent(event, handler)
    local list = eventHandlers[event]
    if not list then
        list = {}
        eventHandlers[event] = list
        eventFrame:RegisterEvent(event)
    end
    list[#list + 1] = handler
end

function ns.OnInitialize(callback)
    initCallbacks[#initCallbacks + 1] = callback
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = eventHandlers[event]
    if list then
        for i = 1, #list do
            safecall(list[i], event, ...)
        end
    end
end)

ns.RegisterEvent("ADDON_LOADED", function(_, loadedName)
    if loadedName ~= addonName or ns.db then
        return
    end
    if type(TimeStampDB) ~= "table" then
        TimeStampDB = {}
    end
    if type(TimeStampCharDB) ~= "table" then
        TimeStampCharDB = {}
    end
    ns.db, ns.charDB = TimeStampDB, TimeStampCharDB

    migrate(ns.db)
    applyDefaults(ns.db, ns.DEFAULTS)
    sanitize(ns.db, ns.charDB)

    for i = 1, #initCallbacks do
        safecall(initCallbacks[i])
    end
end)

ns.RegisterEvent("PLAYER_LOGIN", function()
    convertLegacyPosition()
end)

-- ---------------------------------------------------------------------------
-- Options shared by slash commands and the settings panel
-- ---------------------------------------------------------------------------
function ns.SetOption(key, value)
    ns.db[key] = value
    ns.Options:Notify(key)
    ns.Overlay:Update()
end

-- ---------------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------------
local function onOff(value)
    return value and "|cff44ff44ON|r" or "|cffff4444OFF|r"
end

local function printHelp()
    ns.Print("commands:")
    print("  |cffffd100/ts|r - clean card screenshot (hides your UI)")
    print("  |cffffd100/ts snap|r - normal screenshot with the info overlay")
    print("  |cffffd100/ts config|r - open the settings")
    print("  |cffffd100/ts note <text>|r - set a personal note (|cffffd100/ts note clear|r removes it)")
    print("  |cffffd100/ts key|r - toggle the overlay on your screenshot key")
    print("  |cffffd100/ts companion|r - toggle stamping screenshots taken by other addons")
    print("  |cffffd100/ts unlock|r [card] - show the overlay (or card) to drag it; |cffffd100/ts lock|r hides it")
    print("  |cffffd100/ts reset|r - reset the overlay and card positions")
end

local function handleSlash(input)
    local cmd, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()

    if cmd == "" then
        ns.Capture:Card()
    elseif cmd == "snap" or cmd == "overlay" then
        ns.Capture:Overlay()
    elseif cmd == "config" or cmd == "options" or cmd == "settings" or cmd == "opt" then
        ns.Options:Open()
    elseif cmd == "key" then
        ns.SetOption("intercept", not ns.db.intercept)
        ns.Capture:ApplyKeybind()
        if ns.db.intercept then
            local key = GetBindingKey("SCREENSHOT")
            ns.Print("screenshot key overlay " .. onOff(true)
                .. (key and (" (" .. GetBindingText(key) .. ")") or " - but no screenshot key is bound; use /ts snap"))
        else
            ns.Print("screenshot key overlay " .. onOff(false) .. " (your key takes a normal screenshot again)")
        end
    elseif cmd == "companion" then
        ns.SetOption("companion", not ns.db.companion)
        ns.Print("companion mode " .. onOff(ns.db.companion)
            .. (ns.db.companion and " - screenshots from other addons or the game get a second, stamped copy." or ""))
    elseif cmd == "note" then
        if rest == "" then
            local note = ns.charDB.note
            ns.Print(note and ("note: " .. note) or "no note set. Use /ts note <text>.")
        elseif rest:lower() == "clear" then
            ns.Options:SetNote(nil)
            ns.Print("note cleared.")
        else
            ns.Options:SetNote(rest)
            ns.Print("note set: " .. (ns.charDB.note or ""))
        end
    elseif cmd == "unlock" or cmd == "move" then
        ns.Overlay:Unlock(rest:lower() == "card" and "card" or "overlay")
        ns.Print("drag the preview to move it. Right-click it or type /ts lock when you're done.")
    elseif cmd == "lock" then
        ns.Overlay:Lock()
        ns.Print("overlay locked and hidden until the next screenshot.")
    elseif cmd == "reset" then
        ns.Overlay:ResetPosition("overlay")
        ns.Overlay:ResetPosition("card")
        ns.Print("overlay and card positions reset.")
    else
        printHelp()
    end
end

SLASH_TIMESTAMP1 = "/ts"
SLASH_TIMESTAMP2 = "/timestamp"
SlashCmdList.TIMESTAMP = handleSlash

-- ---------------------------------------------------------------------------
-- Key bindings (Bindings.xml) and the minimap addon compartment
-- ---------------------------------------------------------------------------
BINDING_HEADER_TIMESTAMP = "TimeStamp"
BINDING_NAME_TIMESTAMP_CLEAN = "TimeStamp: clean card screenshot"
BINDING_NAME_TIMESTAMP_OVERLAY = "TimeStamp: screenshot with overlay"

function TimeStamp_CleanShot()
    ns.Capture:Card()
end

function TimeStamp_OverlayShot()
    ns.Capture:Overlay()
end

function TimeStamp_OnAddonCompartmentClick(_, mouseButton)
    if mouseButton == "RightButton" then
        ns.Capture:Card()
    else
        ns.Options:Open()
    end
end

function TimeStamp_OnAddonCompartmentEnter(_, button)
    GameTooltip:SetOwner(button, "ANCHOR_LEFT")
    GameTooltip:SetText("TimeStamp", 1, 1, 1)
    GameTooltip:AddLine("Left-click: open settings", 1, 0.82, 0)
    GameTooltip:AddLine("Right-click: clean card screenshot", 1, 0.82, 0)
    GameTooltip:Show()
end

function TimeStamp_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end
