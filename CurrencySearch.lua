local ADDON_NAME = ...

-- Normalize text so matching is accent-insensitive and tolerant of punctuation.
local function Normalize(text)
    if not text then
        return ""
    end

    local normalized = string.lower(text)
    normalized = normalized
        :gsub("[àáâä]", "a")
        :gsub("[èéêë]", "e")
        :gsub("[ìíîï]", "i")
        :gsub("[òóôö]", "o")
        :gsub("[ùúûü]", "u")
        :gsub("ç", "c")
        :gsub("[%'%’%-%_%.%,%:%;%(%)]", " ")
        :gsub("^%s+", "")
        :gsub("%s+$", "")
        :gsub("%s+", " ")

    return normalized
end

local function SplitWords(query)
    local words = {}

    for word in (query or ""):gmatch("%S+") do
        table.insert(words, word)
    end

    return words
end

local function ContainsAllWords(text, words)
    local normalized = Normalize(text)

    for _, word in ipairs(words) do
        if not normalized:find(word, 1, true) then
            return false
        end
    end

    return true
end

local function Matches(text, query)
    -- Match empty queries so the full currency list is shown by default.
    local normalizedQuery = Normalize(query)
    if normalizedQuery == "" then
        return true
    end

    return ContainsAllWords(text or "", SplitWords(normalizedQuery))
end

local function NewDataProvider()
    -- Dragonflight+ exposes CreateDataProvider; older clients can still build
    -- one from DataProviderMixin.
    if type(CreateDataProvider) == "function" then
        return CreateDataProvider()
    end

    local provider = CreateFromMixins(DataProviderMixin)
    provider:Init()
    return provider
end

local function EnumerateProvider(provider, callback)
    if not provider then
        return
    end

    if provider.Enumerate then
        -- Some APIs enumerate as (index, value) while others yield only value.
        for a, b in provider:Enumerate() do
            local element = b
            if element == nil then
                element = a
            end
            callback(element)
        end
        return
    end

    if provider.GetSize and provider.GetElementData then
        local size = provider:GetSize()
        for i = 1, size do
            callback(provider:GetElementData(i))
        end
    end
end

local State = {
    installed = false,
    installing = false,
    query = "",
    searchBox = nil,
    clearButton = nil,
    tokenFrame = nil,
    scrollBox = nil,
    originalProvider = nil,
    pendingInstall = false,
    installRetryTicker = nil,
    hooksInstalled = false,
    pending = {
        refreshOriginalProvider = false,
        applyFilter = false,
        restoreOriginalProvider = false,
        resetQuery = false,
    },
}

local function IsInCombat()
    return type(InCombatLockdown) == "function" and InCombatLockdown()
end

local function IsCurrencyTransferActive()
    local candidates = {
        _G.CurrencyTransferMenu,
        _G.TokenFramePopup,
        _G.AccountCurrencyTransferFrame,
    }

    for _, frame in ipairs(candidates) do
        if frame and frame.IsShown and frame:IsShown() then
            return true
        end
    end

    return false
end

local IsTokenUILoaded do
    local addOnsAPI = C_AddOns or AddOns

    if addOnsAPI and addOnsAPI.IsAddOnLoaded then
        IsTokenUILoaded = function()
            return addOnsAPI.IsAddOnLoaded("Blizzard_TokenUI")
        end
    elseif IsAddOnLoaded then
        IsTokenUILoaded = function()
            return IsAddOnLoaded("Blizzard_TokenUI")
        end
    else
        IsTokenUILoaded = function()
            return false
        end
    end
end

local function FindTokenFrame()
    return _G.TokenFrame or (_G.CharacterFrame and _G.CharacterFrame.TokenFrame)
end

local function FindScrollBox(tokenFrame)
    if not tokenFrame then
        return nil
    end

    local candidates = {
        tokenFrame.ScrollBox,
        tokenFrame.TokenContainer and tokenFrame.TokenContainer.ScrollBox,
        _G.TokenFrameContainer and _G.TokenFrameContainer.ScrollBox,
    }

    for _, candidate in ipairs(candidates) do
        if candidate and candidate.SetDataProvider and candidate.GetDataProvider then
            return candidate
        end
    end

    return nil
end

local function GetTokenName(element)
    if type(element) == "table" then
        return element.name or element.currencyName
    end

    return nil
end

local function BuildFilteredProvider(query)
    local original = State.originalProvider
    local normalizedQuery = Normalize(query)

    if not original then
        return nil
    end

    if normalizedQuery == "" then
        -- Reuse the original provider when no query is active to preserve any
        -- order and metadata managed by Blizzard's UI.
        return original
    end

    local filtered = NewDataProvider()

    EnumerateProvider(original, function(element)
        local name = GetTokenName(element)
        if name and Matches(name, normalizedQuery) then
            filtered:Insert(element)
        end
    end)

    return filtered
end

local function CanMutateCurrencyUI()
    return not IsInCombat()
        and not IsCurrencyTransferActive()
        and State.installed
        and State.tokenFrame
        and State.tokenFrame:IsShown()
        and State.scrollBox
        and State.originalProvider
end

local function ApplyFilter()
    if not State.scrollBox or not State.originalProvider then
        return
    end

    if not CanMutateCurrencyUI() then
        return
    end

    local provider = BuildFilteredProvider(State.query)
    if not provider then
        return
    end

    State.scrollBox:SetDataProvider(provider, ScrollBoxConstants.RetainScrollPosition)

    if State.scrollBox.FullUpdate then
        State.scrollBox:FullUpdate()
    elseif State.scrollBox.Update then
        State.scrollBox:Update()
    end
end

local function RefreshOriginalProvider()
    if not State.scrollBox then
        return
    end

    local currentProvider = State.scrollBox:GetDataProvider()
    -- Only refresh our source provider while no filter is active; otherwise we
    -- might accidentally treat a filtered provider as the authoritative source.
    if Normalize(State.query) == "" and currentProvider then
        State.originalProvider = currentProvider
    end
end

local QueueDeferredAction

local function CreateSearchUI(tokenFrame)
    local editBox = CreateFrame("EditBox", nil, tokenFrame, "InputBoxTemplate")
    editBox:SetSize(140, 20)
    editBox:SetPoint("TOPLEFT", tokenFrame, "TOPLEFT", 70, -35)
    editBox:SetAutoFocus(false)
    editBox:SetTextInsets(8, 20, 0, 0)

    local clearButton = CreateFrame("Button", nil, tokenFrame, "UIPanelCloseButton")
    clearButton:SetSize(18, 18)
    clearButton:SetPoint("RIGHT", editBox, "RIGHT", 2, 0)

    clearButton:SetScript("OnClick", function()
        editBox:SetText("")
        State.query = ""
        QueueDeferredAction("applyFilter")
    end)

    editBox:SetScript("OnTextChanged", function(self)
        State.query = self:GetText() or ""
        QueueDeferredAction("applyFilter")
    end)

    editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        self:SetText("")
    end)

    State.searchBox = editBox
    State.clearButton = clearButton
end

local function ProcessDeferredActions()
    if not CanMutateCurrencyUI() then
        return
    end

    if State.pending.resetQuery then
        State.pending.resetQuery = false
        State.query = ""

        if State.searchBox and State.searchBox.GetText and State.searchBox:GetText() ~= "" then
            State.searchBox:SetText("")
        end
    end

    if State.pending.restoreOriginalProvider then
        State.pending.restoreOriginalProvider = false

        if State.scrollBox:GetDataProvider() ~= State.originalProvider then
            State.scrollBox:SetDataProvider(State.originalProvider, ScrollBoxConstants.RetainScrollPosition)
        end
    end

    if State.pending.refreshOriginalProvider then
        State.pending.refreshOriginalProvider = false
        RefreshOriginalProvider()
    end

    if State.pending.applyFilter then
        State.pending.applyFilter = false
        ApplyFilter()
    end
end

QueueDeferredAction = function(action)
    if State.pending[action] == nil then
        return
    end

    State.pending[action] = true
    ProcessDeferredActions()
end

local function InstallTokenFrameHooks(tokenFrame)
    if State.hooksInstalled or not tokenFrame or not tokenFrame.HookScript then
        return
    end

    tokenFrame:HookScript("OnShow", function()
        QueueDeferredAction("refreshOriginalProvider")
        QueueDeferredAction("applyFilter")
    end)

    tokenFrame:HookScript("OnHide", function()
        State.pending.resetQuery = true
        State.pending.restoreOriginalProvider = true
    end)

    State.hooksInstalled = true
end

local TryInstall

local function StopInstallRetryTicker()
    if not State.installRetryTicker then
        return
    end

    State.installRetryTicker:Cancel()
    State.installRetryTicker = nil
end

local function StartInstallRetryTicker()
    if State.installRetryTicker or State.installed then
        return
    end

    State.installRetryTicker = C_Timer.NewTicker(0.5, function()
        if State.installed then
            StopInstallRetryTicker()
            return
        end

        TryInstall()
    end)
end


TryInstall = function()
    if State.installed or State.installing then
        return
    end

    if IsInCombat() then
        State.pendingInstall = true
        return
    end

    State.installing = true

    local tokenFrame = FindTokenFrame()
    if not tokenFrame then
        State.installing = false
        StartInstallRetryTicker()
        return
    end

    local scrollBox = FindScrollBox(tokenFrame)
    if not scrollBox then
        State.installing = false
        StartInstallRetryTicker()
        return
    end

    local provider = scrollBox:GetDataProvider()
    if not provider then
        State.installing = false
        StartInstallRetryTicker()
        return
    end

    State.tokenFrame = tokenFrame
    State.scrollBox = scrollBox
    State.originalProvider = provider

    if not State.searchBox then
        CreateSearchUI(tokenFrame)
    end
    InstallTokenFrameHooks(tokenFrame)

    State.installed = true
    State.installing = false
    StopInstallRetryTicker()

    QueueDeferredAction("refreshOriginalProvider")
    QueueDeferredAction("applyFilter")
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

eventFrame:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name == ADDON_NAME or name == "Blizzard_TokenUI" then
            TryInstall()
            StartInstallRetryTicker()
        end
        return
    end

    if event == "CURRENCY_DISPLAY_UPDATE" then
        if not State.installed then
            TryInstall()
            StartInstallRetryTicker()
            return
        end

        QueueDeferredAction("refreshOriginalProvider")
        QueueDeferredAction("applyFilter")
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        if State.pendingInstall then
            State.pendingInstall = false
            TryInstall()
            StartInstallRetryTicker()
        end

        ProcessDeferredActions()

        return
    end

end)

if IsTokenUILoaded() then
    TryInstall()
    StartInstallRetryTicker()
end
