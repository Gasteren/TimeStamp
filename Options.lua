local _, ns = ...

local Options = {}
ns.Options = Options

local floor = math.floor
local DEFAULTS = ns.DEFAULTS

local categories = {}  -- [category] = true for our settings pages
local mainCategory

local POINT_LABELS = {
    TOPLEFT = "Top left",
    TOP = "Top",
    TOPRIGHT = "Top right",
    LEFT = "Left",
    CENTER = "Center",
    RIGHT = "Right",
    BOTTOMLEFT = "Bottom left",
    BOTTOM = "Bottom",
    BOTTOMRIGHT = "Bottom right",
}

local LINE_TOOLTIP = "Choose what appears on this line. Picking an item that is already used on another line swaps the two."

-- ---------------------------------------------------------------------------
-- Settings plumbing. Values live in TimeStampDB; paths like "overlay.point"
-- address one level of nesting.
-- ---------------------------------------------------------------------------
local function variableName(path)
    return "TimeStamp_" .. (path:gsub("%.", "_"))
end

local function lookup(root, path)
    local group, key = path:match("^([^.]+)%.(.+)$")
    if group then
        return root[group], key
    end
    return root, path
end

local function getValue(path)
    local tbl, key = lookup(ns.db, path)
    return tbl[key]
end

local function getDefault(path)
    local tbl, key = lookup(DEFAULTS, path)
    return tbl[key]
end

local function setValue(path, value)
    local tbl, key = lookup(ns.db, path)
    if type(value) == "number" then
        value = floor(value * 100 + 0.5) / 100
    end
    tbl[key] = value
end

local function registerSetting(category, path, name, onChange)
    local default = getDefault(path)
    return Settings.RegisterProxySetting(category, variableName(path), type(default), name, default,
        function()
            return getValue(path)
        end,
        function(value)
            setValue(path, value)
            if onChange then
                onChange(value)
            end
            ns.Overlay:Update()
        end)
end

local function addCheckbox(category, path, name, tooltip, onChange)
    Settings.CreateCheckbox(category, registerSetting(category, path, name, onChange), tooltip)
end

local function addSlider(category, path, name, tooltip, minValue, maxValue, step, formatter)
    local setting = registerSetting(category, path, name)
    local sliderOptions = Settings.CreateSliderOptions(minValue, maxValue, step)
    sliderOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, formatter)
    Settings.CreateSlider(category, setting, sliderOptions, tooltip)
end

local function addDropdown(category, path, name, tooltip, getOptions, onChange)
    Settings.CreateDropdown(category, registerSetting(category, path, name, onChange), getOptions, tooltip)
end

local function addColor(category, path, name, tooltip)
    Settings.CreateColorSwatch(category, registerSetting(category, path, name), tooltip)
end

local function addHeader(layout, text, tooltip)
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text, tooltip))
end

local function addButton(layout, name, text, onClick, tooltip)
    layout:AddInitializer(CreateSettingsButtonInitializer(name, text, onClick, tooltip, true))
end

-- Dropdown option builders: called each time a dropdown opens.
local function staticOptions(list)
    return function()
        local container = Settings.CreateControlTextContainer()
        for _, entry in ipairs(list) do
            container:Add(entry[1], entry[2], entry[3])
        end
        return container:GetData()
    end
end

local function pointOptions()
    local container = Settings.CreateControlTextContainer()
    for _, point in ipairs(ns.POINTS) do
        container:Add(point, POINT_LABELS[point])
    end
    return container:GetData()
end

local function fontOptions()
    local container = Settings.CreateControlTextContainer()
    for _, font in ipairs(ns.Fonts:GetOptions()) do
        container:Add(font.value, font.label)
    end
    return container:GetData()
end

local function separatorOptions()
    local container = Settings.CreateControlTextContainer()
    for _, entry in ipairs(ns.Fields.SEPARATORS) do
        container:Add(entry.key, entry.label)
    end
    return container:GetData()
end

local function dateOptions()
    local container = Settings.CreateControlTextContainer()
    for _, entry in ipairs(ns.Fields.DATE_FORMATS) do
        container:Add(entry.key, ns.Fields:FormatDate(entry.key))
    end
    return container:GetData()
end

local function lineOptions()
    local container = Settings.CreateControlTextContainer()
    container:Add("none", "|cff808080Empty|r")
    container:Add("spacer", "Spacer / line break",
        "Stacked: adds a gap.\nCompact: starts a new line; a second spacer in a row adds a gap.")
    for _, def in ipairs(ns.Fields.list) do
        container:Add(def.key, def.label)
    end
    return container:GetData()
end

local function formatNumber(value)
    return tostring(ns.Round(value))
end

local function formatPercent(value)
    return ("%d%%"):format(ns.Round(value * 100))
end

local function formatSeconds(value)
    value = ns.Round(value)
    return value == 0 and "Off" or (value .. " s")
end

-- ---------------------------------------------------------------------------
-- Line slots: each field can be used once; choosing a used one swaps lines.
-- ---------------------------------------------------------------------------
local function setLine(index, value)
    local lines = ns.db.lines
    local previous = lines[index]
    lines[index] = value
    if value ~= "none" and value ~= "spacer" then
        for other = 1, ns.NUM_LINES do
            if other ~= index and lines[other] == value then
                lines[other] = previous
                Settings.NotifyUpdate(variableName("line" .. other))
                break
            end
        end
    end
    ns.Overlay:Update()
end

local function addLineSlots(category)
    for i = 1, ns.NUM_LINES do
        local setting = Settings.RegisterProxySetting(category, variableName("line" .. i), "string",
            ("Line %d"):format(i), DEFAULTS.lines[i],
            function()
                return ns.db.lines[i]
            end,
            function(value)
                setLine(i, value)
            end)
        Settings.CreateDropdown(category, setting, lineOptions, LINE_TOOLTIP)
    end
end

-- ---------------------------------------------------------------------------
-- Pages
-- ---------------------------------------------------------------------------
local function buildMainPage()
    local category, layout = Settings.RegisterVerticalLayoutCategory("TimeStamp")
    mainCategory = category
    categories[category] = true

    addHeader(layout, "Taking screenshots",
        "You can also bind keys for both kinds of screenshots under Options > Keybindings > AddOns.")
    addCheckbox(category, "intercept", "Stamp my screenshot key",
        "Your normal screenshot key takes the screenshot with the info overlay on it.\n\nTurn this off to take plain screenshots with that key.",
        function()
            ns.Capture:ApplyKeybind()
        end)
    addCheckbox(category, "companion", "Companion mode",
        "Whenever another addon (Memoria, Memento, ...) or the game takes a screenshot, TimeStamp saves an extra copy with your details stamped on it.")
    addSlider(category, "countdown", "Clean shot countdown",
        "Wait a few seconds before a clean card shot (/ts) so you can strike a pose. Run /ts again to cancel.",
        0, 10, 1, formatSeconds)

    addHeader(layout, "Screenshot overlay",
        "Shown on screenshots taken with your screenshot key, /ts snap, or companion mode.")
    addDropdown(category, "overlay.point", "Position",
        "Where the overlay sits on your screen. Drag the preview to fine-tune it.", pointOptions,
        function()
            ns.Overlay:ResetOffsets("overlay")
        end)
    addSlider(category, "overlay.scale", "Scale", nil, ns.SCALE_RANGE[1], ns.SCALE_RANGE[2], 0.05, formatPercent)
    addButton(layout, "Preview", "Show overlay", function()
        ns.Overlay:ShowPreview("overlay")
    end, "Show the overlay while these settings are open. Drag it to move it; right-click it to hide it.")

    addHeader(layout, "Clean card", "Used by /ts: your UI is hidden and only your character card is captured.")
    addDropdown(category, "card.point", "Position",
        "Where the card sits on your screen. Drag the preview to fine-tune it.", pointOptions,
        function()
            ns.Overlay:ResetOffsets("card")
        end)
    addSlider(category, "card.scale", "Scale", nil, ns.SCALE_RANGE[1], ns.SCALE_RANGE[2], 0.05, formatPercent)
    addButton(layout, "Preview", "Show card", function()
        ns.Overlay:ShowPreview("card")
    end, "Show the clean card while these settings are open. Drag it to move it; right-click it to hide it.")

    addHeader(layout, "Positions")
    addButton(layout, "Reset positions", "Reset", function()
        ns.Overlay:ResetPosition("overlay")
        ns.Overlay:ResetPosition("card")
    end, "Move the overlay and the card back to their default spots.")

    return category
end

local function buildAppearancePage(parent)
    local category, layout = Settings.RegisterVerticalLayoutSubcategory(parent, "Appearance")
    categories[category] = true

    addHeader(layout, "Fonts", "Headings are the name and zone lines; every other line uses the text font.")
    addDropdown(category, "titleFont", "Heading font",
        "Fonts shared through LibSharedMedia by your other addons are listed too.", fontOptions)
    addSlider(category, "titleSize", "Heading size", nil, 8, 64, 1, formatNumber)
    addDropdown(category, "textFont", "Text font",
        "Fonts shared through LibSharedMedia by your other addons are listed too.", fontOptions)
    addSlider(category, "textSize", "Text size", nil, 6, 48, 1, formatNumber)
    addDropdown(category, "outline", "Outline", nil,
        staticOptions({ { "NONE", "None" }, { "OUTLINE", "Thin" }, { "THICKOUTLINE", "Thick" } }))
    addCheckbox(category, "shadow", "Drop shadow")

    addHeader(layout, "Colors")
    addColor(category, "titleColor", "Heading color")
    addColor(category, "textColor", "Text color")
    addCheckbox(category, "classColorName", "Class-colored name", "Show your name in your class color.")

    addHeader(layout, "Background", "A backdrop helps the text stand out against bright scenery.")
    addDropdown(category, "background", "Style", nil, staticOptions({
        { "none", "None" },
        { "shade", "Shade", "A solid dark panel behind the text." },
        { "fade", "Fade", "A dark band that fades out to the side." },
        { "box", "Tooltip box", "A panel with a tooltip-style border." },
    }))
    addSlider(category, "bgOpacity", "Opacity", nil, 0, 1, 0.05, formatPercent)
end

local function buildLayoutPage(parent)
    local category, layout = Settings.RegisterVerticalLayoutSubcategory(parent, "Layout")
    categories[category] = true

    addHeader(layout, "Arrangement")
    addDropdown(category, "arrangement", "Arrangement", nil, staticOptions({
        { "stacked", "Stacked", "One item per line." },
        { "compact", "Compact", "Items share a line. Use a spacer to start a new line." },
    }))
    addDropdown(category, "separator", "Separator",
        "Placed between items that share a line in the compact arrangement.", separatorOptions)
    addDropdown(category, "align", "Text alignment", "Auto follows the position: left, center or right.",
        staticOptions({ { "AUTO", "Auto" }, { "LEFT", "Left" }, { "CENTER", "Center" }, { "RIGHT", "Right" } }))
    addSlider(category, "lineSpacing", "Line spacing", nil, 0, 20, 1, formatNumber)
    addSlider(category, "spacerSize", "Spacer size", "Height of the gap a spacer adds.", 0, 40, 1, formatNumber)

    addHeader(layout, "Lines", "Pick what goes on each line, from top to bottom.")
    addLineSlots(category)

    addHeader(layout, "Line details")
    addCheckbox(category, "showRealm", "Realm name", "Show your realm after your name.")
    addCheckbox(category, "showTitle", "Character title", "Show your selected title with your name.")
    addCheckbox(category, "showRace", "Race", "Show your race on the class line.")
    addCheckbox(category, "showSpec", "Specialization", "Show your specialization on the class line.")
    addCheckbox(category, "showRank", "Guild rank", "Show your rank on the guild line.")
    addCheckbox(category, "showXP", "Experience while leveling", "Show your experience progress on the level line.")
    addDropdown(category, "dateFormat", "Date format", nil, dateOptions)
    addButton(layout, "Personal note", "Edit note", function()
        Options:ShowNoteDialog()
    end, "A line of your own, like \"First Mythic kill!\". Saved per character.\n\nAlso: /ts note <text>")
end

-- ---------------------------------------------------------------------------
-- Live preview while one of our pages is open
-- ---------------------------------------------------------------------------
local function isOurCategory(category)
    return category ~= nil and categories[category] == true
end

local function refreshSettingsPreview()
    local panel = SettingsPanel
    local open = panel ~= nil and panel:IsShown() and isOurCategory(panel:GetCurrentCategory())
    ns.Overlay:SetPreview("settings", open)
end

local function resetOffsetsAfterDefaults()
    ns.Overlay:ResetOffsets("overlay")
    ns.Overlay:ResetOffsets("card")
    ns.Overlay:Update()
end

EventRegistry:RegisterCallback("Settings.CategoryChanged", function(_, category)
    ns.Overlay:SetPreview("settings", isOurCategory(category))
end, Options)

EventRegistry:RegisterCallback("SettingsPanel.OnHide", function()
    -- A clean card hides UIParent (and this panel) for a moment; keep the preview state.
    if ns.Capture:IsBusy() then
        return
    end
    ns.Overlay.previewMode = "overlay"
    ns.Overlay:SetPreview("settings", false)
end, Options)

EventRegistry:RegisterCallback("Settings.CategoryDefaulted", function(_, category)
    if category == mainCategory then
        resetOffsetsAfterDefaults()
    end
end, Options)

EventRegistry:RegisterCallback("Settings.Defaulted", resetOffsetsAfterDefaults, Options)

-- ---------------------------------------------------------------------------
-- Public
-- ---------------------------------------------------------------------------
function Options:Open()
    if not mainCategory then
        return
    end
    if InCombatLockdown() then
        ns.Print("the settings can't be opened during combat.")
        return
    end
    Settings.OpenToCategory(mainCategory:GetID())
end

-- Refreshes a control after its value changed outside the settings panel.
function Options:Notify(path)
    if mainCategory then
        Settings.NotifyUpdate(variableName(path))
    end
end

function Options:SetNote(text)
    text = type(text) == "string" and strtrim(text) or ""
    ns.charDB.note = text ~= "" and text or nil
    ns.Overlay:Update()
end

-- ---------------------------------------------------------------------------
-- Note dialog
-- ---------------------------------------------------------------------------
local noteDialog

local function createNoteDialog()
    local dialog = CreateFrame("Frame", "TimeStampNoteDialog", UIParent, "BackdropTemplate")
    dialog:SetSize(440, 150)
    dialog:SetPoint("CENTER", 0, 140)
    dialog:SetFrameStrata("FULLSCREEN_DIALOG")
    dialog:SetToplevel(true)
    dialog:EnableMouse(true)
    dialog:SetBackdrop(BACKDROP_DIALOG_32_32)
    dialog:Hide()

    local title = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -18)
    title:SetText("TimeStamp note")

    local hint = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOP", title, "BOTTOM", 0, -6)
    hint:SetText("Shown on this character's screenshots. Leave it empty to remove it.")

    local editBox = CreateFrame("EditBox", nil, dialog, "InputBoxTemplate")
    editBox:SetSize(360, 24)
    editBox:SetPoint("TOP", hint, "BOTTOM", 0, -10)
    editBox:SetAutoFocus(false)
    editBox:SetMaxLetters(120)
    dialog.editBox = editBox

    local function save()
        Options:SetNote(editBox:GetText())
        dialog:Hide()
    end
    editBox:SetScript("OnEnterPressed", save)
    editBox:SetScript("OnEscapePressed", function()
        dialog:Hide()
    end)

    local saveButton = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    saveButton:SetSize(110, 24)
    saveButton:SetPoint("BOTTOMRIGHT", dialog, "BOTTOM", -4, 18)
    saveButton:SetText(SAVE or "Save")
    saveButton:SetScript("OnClick", save)

    local cancelButton = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    cancelButton:SetSize(110, 24)
    cancelButton:SetPoint("BOTTOMLEFT", dialog, "BOTTOM", 4, 18)
    cancelButton:SetText(CANCEL or "Cancel")
    cancelButton:SetScript("OnClick", function()
        dialog:Hide()
    end)

    tinsert(UISpecialFrames, "TimeStampNoteDialog")
    return dialog
end

function Options:ShowNoteDialog()
    noteDialog = noteDialog or createNoteDialog()
    noteDialog.editBox:SetText(ns.charDB.note or "")
    noteDialog:Show()
    noteDialog.editBox:SetFocus()
    noteDialog.editBox:HighlightText()
end

-- ---------------------------------------------------------------------------
-- First-run prompt: Enable / Keep Off plus "Don't remind me again". Only the
-- checkbox stops future prompts, so the choice is separate from the reminder.
-- ---------------------------------------------------------------------------
local companionPrompt

local function createCompanionPrompt()
    local prompt = CreateFrame("Frame", "TimeStampPrompt", UIParent, "BackdropTemplate")
    prompt:SetSize(440, 270)
    prompt:SetPoint("CENTER")
    prompt:SetFrameStrata("DIALOG")
    prompt:EnableMouse(true)
    prompt:SetBackdrop(BACKDROP_DIALOG_32_32)

    local title = prompt:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -18)
    title:SetText("|cff00ccffTimeStamp|r")

    local body = prompt:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    body:SetPoint("TOPLEFT", 24, -46)
    body:SetPoint("TOPRIGHT", -24, -46)
    body:SetJustifyH("LEFT")
    body:SetSpacing(3)
    body:SetText("Would you like TimeStamp to add your character details to your screenshots automatically?\n\n"
        .. "When this is on, it works alongside Memoria, Memento, and any other addon that takes screenshots for you - "
        .. "whenever one of those snaps a shot, TimeStamp saves an extra copy with your details stamped on it.\n\n"
        .. "You can change this anytime in the settings (|cffffd100/ts config|r) or with |cffffd100/ts companion|r.")

    local check = CreateFrame("CheckButton", nil, prompt, "UICheckButtonTemplate")
    check:SetPoint("BOTTOMLEFT", 22, 18)
    check:SetSize(24, 24)
    local checkLabel = check:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    checkLabel:SetPoint("LEFT", check, "RIGHT", 4, 1)
    checkLabel:SetText("Don't remind me again")
    prompt.check = check

    local function choose(enabled)
        ns.SetOption("companion", enabled)
        if check:GetChecked() then
            ns.db.seenCompanionPrompt = true
        end
        prompt:Hide()
        if enabled then
            ns.Print("companion mode |cff44ff44ON|r. Change it anytime with /ts companion or /ts config.")
        else
            ns.Print("companion mode left |cffff4444OFF|r. Turn it on later with /ts companion or /ts config.")
        end
    end

    local enable = CreateFrame("Button", nil, prompt, "UIPanelButtonTemplate")
    enable:SetSize(110, 24)
    enable:SetPoint("BOTTOMRIGHT", -16, 16)
    enable:SetText("Enable")
    enable:SetScript("OnClick", function()
        choose(true)
    end)

    local keepOff = CreateFrame("Button", nil, prompt, "UIPanelButtonTemplate")
    keepOff:SetSize(110, 24)
    keepOff:SetPoint("RIGHT", enable, "LEFT", -8, 0)
    keepOff:SetText("Keep Off")
    keepOff:SetScript("OnClick", function()
        choose(false)
    end)

    tinsert(UISpecialFrames, "TimeStampPrompt") -- Esc closes it without saving a choice
    return prompt
end

function Options:ShowCompanionPrompt()
    companionPrompt = companionPrompt or createCompanionPrompt()
    companionPrompt.check:SetChecked(false)
    companionPrompt:Show()
end

-- ---------------------------------------------------------------------------
-- Setup
-- ---------------------------------------------------------------------------
ns.OnInitialize(function()
    local main = buildMainPage()
    buildAppearancePage(main)
    buildLayoutPage(main)
    Settings.RegisterAddOnCategory(main)
end)

ns.RegisterEvent("PLAYER_LOGIN", function()
    if SettingsPanel then
        -- Reopening the panel on one of our pages doesn't fire CategoryChanged.
        SettingsPanel:HookScript("OnShow", function()
            C_Timer.After(0, refreshSettingsPreview)
        end)
    end

    if not ns.db.seenCompanionPrompt then
        C_Timer.After(4, function()
            if not ns.db.seenCompanionPrompt then
                Options:ShowCompanionPrompt()
            end
        end)
    end
end)
