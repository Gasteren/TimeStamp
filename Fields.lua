local _, ns = ...

local Fields = {}
ns.Fields = Fields

local floor = math.floor
local IsSecret, HasText = ns.IsSecret, ns.HasText

Fields.SPACER = "spacer"
Fields.NONE = "none"

-- `title` lines use the heading font and color.
Fields.list = {
    { key = "name", label = "Character name", title = true },
    { key = "class", label = "Race & class" },
    { key = "guild", label = "Guild" },
    { key = "level", label = "Level & experience" },
    { key = "itemlvl", label = "Item level" },
    { key = "zone", label = "Zone & difficulty", title = true },
    { key = "subzone", label = "Subzone" },
    { key = "coords", label = "Map coordinates" },
    { key = "date", label = "Date & time" },
    { key = "xpack", label = "Expansion" },
    { key = "note", label = "Personal note" },
}

Fields.byKey = {}
for _, def in ipairs(Fields.list) do
    Fields.byKey[def.key] = def
end

-- A literal "|" must be written as "||" in WoW text.
Fields.SEPARATORS = {
    { key = "dot", label = "Middle dot  \194\183", text = "  \194\183  " },
    { key = "bar", label = "Bar  ||", text = "  ||  " },
    { key = "dash", label = "Dash  -", text = "  -  " },
    { key = "slash", label = "Slash  /", text = "  /  " },
    { key = "space", label = "Wide space", text = "      " },
}

-- ---------------------------------------------------------------------------
-- Date & time
-- ---------------------------------------------------------------------------
local function monthName(month)
    local names = CALENDAR_FULLDATE_MONTH_NAMES
    return names and names[month] or date("%B")
end

local function weekdayName(weekday)
    local names = CALENDAR_WEEKDAY_NAMES
    return names and names[weekday] or date("%A")
end

local function clock12(t)
    local hour = t.hour % 12
    if hour == 0 then
        hour = 12
    end
    local suffix = t.hour < 12 and (TIMEMANAGER_AM or "AM") or (TIMEMANAGER_PM or "PM")
    return ("%d:%02d %s"):format(hour, t.min, suffix)
end

local function clock24(t)
    return ("%02d:%02d"):format(t.hour, t.min)
end

Fields.DATE_FORMATS = {
    { key = "long12", format = function(t)
        return ("%s %d, %d %s"):format(monthName(t.month), t.day, t.year, clock12(t))
    end },
    { key = "long24", format = function(t)
        return ("%s %d, %d %s"):format(monthName(t.month), t.day, t.year, clock24(t))
    end },
    { key = "dayMonth24", format = function(t)
        return ("%d %s %d %s"):format(t.day, monthName(t.month), t.year, clock24(t))
    end },
    { key = "weekday", format = function(t)
        return ("%s, %s %d, %d"):format(weekdayName(t.wday), monthName(t.month), t.day, t.year)
    end },
    { key = "weekday12", format = function(t)
        return ("%s, %s %d, %d %s"):format(weekdayName(t.wday), monthName(t.month), t.day, t.year, clock12(t))
    end },
    { key = "us12", format = function(t)
        return ("%02d/%02d/%d %s"):format(t.month, t.day, t.year, clock12(t))
    end },
    { key = "eu24", format = function(t)
        return ("%02d/%02d/%d %s"):format(t.day, t.month, t.year, clock24(t))
    end },
    { key = "dots24", format = function(t)
        return ("%02d.%02d.%d %s"):format(t.day, t.month, t.year, clock24(t))
    end },
    { key = "iso", format = function(t)
        return ("%d-%02d-%02d %s"):format(t.year, t.month, t.day, clock24(t))
    end },
    { key = "dateOnly", format = function(t)
        return ("%s %d, %d"):format(monthName(t.month), t.day, t.year)
    end },
}

function Fields:FormatDate(key)
    local now = date("*t")
    for _, entry in ipairs(self.DATE_FORMATS) do
        if entry.key == key then
            return entry.format(now)
        end
    end
    return self.DATE_FORMATS[1].format(now)
end

-- ---------------------------------------------------------------------------
-- Field providers: return the text for a line, or nil to skip it
-- ---------------------------------------------------------------------------
local providers = {}

local function getSpecName()
    local api = C_SpecializationInfo
    local getSpecialization = (api and api.GetSpecialization) or GetSpecialization
    local getSpecializationInfo = (api and api.GetSpecializationInfo) or GetSpecializationInfo
    if not (getSpecialization and getSpecializationInfo) then
        return
    end
    local index = getSpecialization()
    if type(index) ~= "number" or IsSecret(index) or index < 1 then
        return
    end
    local _, name = getSpecializationInfo(index)
    if HasText(name) then
        return name
    end
end

local function canShowExperience()
    if GameRulesUtil and GameRulesUtil.CanShowExperienceBar then
        return GameRulesUtil.CanShowExperienceBar()
    end
    return not (IsPlayerAtEffectiveMaxLevel and IsPlayerAtEffectiveMaxLevel())
end

function providers.name(db)
    local name = db.showTitle and UnitPVPName("player") or nil
    if not name then
        name = UnitName("player")
    end
    if not name then
        return
    end
    if db.showRealm then
        local realm = GetRealmName()
        if HasText(realm) then
            name = name .. " - " .. realm
        end
    end
    if db.classColorName then
        local _, classFile = UnitClass("player")
        local color = classFile and not IsSecret(classFile)
            and ((C_ClassColor and C_ClassColor.GetClassColor(classFile)) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]))
        if color and color.GenerateHexColorMarkup then
            name = color:GenerateHexColorMarkup() .. name .. "|r"
        end
    end
    return name
end

function providers.class(db)
    local text = UnitClass("player")
    if not text then
        return
    end
    if db.showSpec then
        local spec = getSpecName()
        if spec then
            text = spec .. " " .. text
        end
    end
    if db.showRace then
        local race = UnitRace("player")
        if HasText(race) then
            text = race .. " " .. text
        end
    end
    return text
end

function providers.guild(db)
    local guildName, rankName = GetGuildInfo("player")
    if not guildName then
        return
    end
    local guild = "<" .. guildName .. ">"
    if db.showRank and HasText(rankName) then
        return rankName .. " of " .. guild
    end
    return guild
end

function providers.level(db)
    local level = UnitLevel("player")
    if not level then
        return
    end
    local text = (LEVEL or "Level") .. " " .. level
    if db.showXP and canShowExperience() then
        local current, needed = UnitXP("player"), UnitXPMax("player")
        if type(current) == "number" and type(needed) == "number" and not IsSecret(current) and not IsSecret(needed) and needed > 0 then
            text = text .. "  (" .. floor(current / needed * 100) .. "% XP)"
        end
    end
    return text
end

function providers.itemlvl()
    if not GetAverageItemLevel then
        return
    end
    local _, equipped = GetAverageItemLevel()
    if type(equipped) ~= "number" or IsSecret(equipped) or equipped < 1 then
        return
    end
    return (STAT_AVERAGE_ITEM_LEVEL or "Item Level") .. " " .. floor(equipped)
end

function providers.zone()
    local zone = GetRealZoneText()
    if not HasText(zone) then
        zone = GetZoneText()
    end
    if not HasText(zone) then
        return
    end
    local _, instanceType, difficultyID = GetInstanceInfo()
    if instanceType ~= "none" and type(difficultyID) == "number" and not IsSecret(difficultyID) and difficultyID > 0 then
        local difficulty = GetDifficultyInfo(difficultyID)
        if HasText(difficulty) then
            zone = zone .. " (" .. difficulty .. ")"
        end
    end
    return zone
end

function providers.subzone()
    local subzone = GetSubZoneText()
    if not HasText(subzone) then
        return
    end
    local zone = GetRealZoneText()
    if not IsSecret(subzone) and not IsSecret(zone) and subzone == zone then
        return
    end
    return subzone
end

function providers.coords()
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then
        return
    end
    local mapID = C_Map.GetBestMapForUnit("player")
    local position = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
    if not position then
        return
    end
    local x, y = position:GetXY()
    if type(x) ~= "number" or type(y) ~= "number" or IsSecret(x) or IsSecret(y) or (x == 0 and y == 0) then
        return
    end
    return ("%.1f, %.1f"):format(x * 100, y * 100)
end

function providers.date(db)
    return Fields:FormatDate(db.dateFormat)
end

function providers.xpack()
    if ns.isForever then
        return "World of Warcraft: Forever"
    end
    local level = (GetClientDisplayExpansionLevel and GetClientDisplayExpansionLevel())
        or (GetExpansionLevel and GetExpansionLevel())
    return level and _G["EXPANSION_NAME" .. level]
end

function providers.note()
    local note = ns.charDB and ns.charDB.note
    if HasText(note) then
        return note
    end
end

-- Errors in one field never break a screenshot: the line is simply skipped.
function Fields:GetText(key, db)
    local provider = providers[key]
    if not provider then
        return
    end
    local ok, text = pcall(provider, db)
    if ok and HasText(text) then
        return text
    end
end

local function separatorText(key)
    for _, entry in ipairs(Fields.SEPARATORS) do
        if entry.key == key then
            return entry.text
        end
    end
    return Fields.SEPARATORS[1].text
end

-- Turns the configured line slots into render lines: { text, title, gap }.
-- Stacked: every item gets its own line and spacers add a gap.
-- Compact: items share a line; a spacer starts a new line, a second spacer adds a gap.
function Fields:BuildLines(db)
    local lines = {}
    local compact = db.arrangement == "compact"
    local separator = separatorText(db.separator)
    local gap, current = 0, nil

    for i = 1, ns.NUM_LINES do
        local key = db.lines[i]
        if key == self.SPACER then
            if compact and current then
                lines[#lines + 1] = current
                current = nil
            elseif #lines > 0 then
                gap = gap + 1
            end
        elseif key and key ~= self.NONE then
            local text = self:GetText(key, db)
            if text then
                if compact and current then
                    current.text = current.text .. separator .. text
                else
                    local def = self.byKey[key]
                    local line = { text = text, title = def and def.title or false, gap = gap }
                    gap = 0
                    if compact then
                        current = line
                    else
                        lines[#lines + 1] = line
                    end
                end
            end
        end
    end

    if current then
        lines[#lines + 1] = current
    end
    return lines
end
