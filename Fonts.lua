local _, ns = ...

local Fonts = {}
ns.Fonts = Fonts

local LSM_PREFIX = "lsm:"
local FALLBACK_FONT = "Fonts\\FRIZQT__.TTF"

-- Fonts shipped with the game client, grouped by the script they can render.
local BUILTIN = {
    roman = {
        { "Fonts\\FRIZQT__.TTF", "Friz Quadrata" },
        { "Fonts\\ARIALN.TTF", "Arial Narrow" },
        { "Fonts\\MORPHEUS.TTF", "Morpheus" },
        { "Fonts\\SKURRI.TTF", "Skurri" },
    },
    russian = {
        { "Fonts\\FRIZQT___CYR.TTF", "Friz Quadrata" },
        { "Fonts\\ARIALN.TTF", "Arial Narrow" },
        { "Fonts\\MORPHEUS_CYR.TTF", "Morpheus" },
        { "Fonts\\SKURRI_CYR.TTF", "Skurri" },
    },
    korean = {
        { "Fonts\\2002.TTF", "2002" },
        { "Fonts\\2002B.TTF", "2002 Bold" },
        { "Fonts\\K_Pagetext.TTF", "Pagetext" },
        { "Fonts\\K_Damage.TTF", "Damage" },
    },
    simplifiedChinese = {
        { "Fonts\\ARKai_T.ttf", "AR Kai T" },
        { "Fonts\\ARKai_C.ttf", "AR Kai C" },
        { "Fonts\\ARHei.ttf", "AR Hei" },
    },
    traditionalChinese = {
        { "Fonts\\bLEI00D.ttf", "Lei" },
        { "Fonts\\bKAI00M.ttf", "Kai" },
        { "Fonts\\bHEI00M.ttf", "Hei" },
        { "Fonts\\bHEI01B.ttf", "Hei Bold" },
    },
}

local LOCALE_SCRIPT = {
    ruRU = "russian",
    koKR = "korean",
    zhCN = "simplifiedChinese",
    zhTW = "traditionalChinese",
}

local function getSharedMedia()
    local libStub = _G.LibStub
    return libStub and libStub("LibSharedMedia-3.0", true)
end

local function normalize(path)
    return (path:gsub("/", "\\"):upper())
end

function Fonts:Default()
    return STANDARD_TEXT_FONT or FALLBACK_FONT
end

-- Saved values are "default", a font file path, or "lsm:<name>" for LibSharedMedia fonts.
function Fonts:Resolve(key)
    if type(key) ~= "string" or key == "" or key == "default" then
        return self:Default()
    end
    if key:sub(1, #LSM_PREFIX) == LSM_PREFIX then
        local lsm = getSharedMedia()
        local path = lsm and lsm:Fetch("font", key:sub(#LSM_PREFIX + 1), true)
        return path or self:Default()
    end
    return key
end

-- Returns { { value = ..., label = ... }, ... } for the font dropdowns.
function Fonts:GetOptions()
    local options, seen = {}, {}
    local function add(value, label, path)
        local id = normalize(path)
        if not seen[id] then
            seen[id] = true
            options[#options + 1] = { value = value, label = label }
        end
    end

    options[1] = { value = "default", label = "Game default" }
    for _, font in ipairs(BUILTIN[LOCALE_SCRIPT[GetLocale()] or "roman"]) do
        add(font[1], font[2], font[1])
    end

    local lsm = getSharedMedia()
    if lsm then
        for _, name in ipairs(lsm:List("font")) do
            local path = lsm:Fetch("font", name, true)
            if type(path) == "string" then
                add(LSM_PREFIX .. name, name, path)
            end
        end
    end
    return options
end
