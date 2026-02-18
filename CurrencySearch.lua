local ADDON_NAME = ...
local DEBUG_TRANSFER_DETECTION = false
local MODE_STRICT = "strict"
local MODE_COMPAT = "compat"

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
    pendingFilterRefresh = false,
    pendingRestoreOriginalProvider = false,
    tokenFrameWasShown = false,
    visibilityTicker = nil,
    transferWasActive = false,
    disableNoticeShown = false,
    mutationPauseActive = false,
    strictModeBlockNoticeShown = false,
}

local function IsInCombat()
    return type(InCombatLockdown) == "function" and InCombatLockdown()
end

local function ShouldDisableForTaintSafety()
    if _G.CurrencySearchForceDisable == true then
        return true
    end

    if not CurrencySearchDB or CurrencySearchDB.mode ~= MODE_STRICT then
        return false
    end

    if not C_CurrencyInfo then
        return false
    end

    local strictModeRiskApis = {
        "IsAccountCurrencyTransferActive",
        "IsAccountCharacterCurrencyTransferActive",
        "IsCurrencyTransferModeActive",
    }

    for _, apiName in ipairs(strictModeRiskApis) do
        if type(C_CurrencyInfo[apiName]) == "function" then
            return true
        end
    end

    return false
end

local function GetCurrentMode()
    if not CurrencySearchDB then
        CurrencySearchDB = {}
    end

    if CurrencySearchDB.mode ~= MODE_COMPAT and CurrencySearchDB.mode ~= MODE_STRICT then
        CurrencySearchDB.mode = MODE_STRICT
    end

    return CurrencySearchDB.mode
end


local function ShowStrictModeBlockNoticeOnce()
    if State.strictModeBlockNoticeShown then
        return
    end

    State.strictModeBlockNoticeShown = true
    print(string.format(
        "%s: strict mode is active; filtering install is disabled on clients with account-currency transfer APIs to reduce taint risk. Use /currencysearch mode compat to allow filtering (higher taint risk).",
        ADDON_NAME
    ))
end

local function ShowMutationDeferredNoticeOnce()
    if State.disableNoticeShown then
        return
    end

    State.disableNoticeShown = true
    print(string.format("%s: temporarily pausing currency filtering while protected transfer/combat state is active.", ADDON_NAME))
end

local function UpdateMutationPauseState(isPaused)
    if isPaused then
        if not State.mutationPauseActive then
            State.mutationPauseActive = true
            State.disableNoticeShown = false
        end
        return
    end

    State.mutationPauseActive = false
    State.disableNoticeShown = false
end

local FindTokenFrame

local lastTransferDebugReason

local function LogTransferDetection(reason)
    if not DEBUG_TRANSFER_DETECTION then
        return
    end

    if lastTransferDebugReason == reason then
        return
    end

    lastTransferDebugReason = reason
    print(string.format("%s: transfer state detected via %s", ADDON_NAME, reason))
end

local function SafeCall(method, target)
    if type(method) ~= "function" then
        return false
    end

    local ok, result = pcall(method, target)
    return ok and result == true
end

local function HasActiveTransferFlag(target, sourceLabel)
    if type(target) ~= "table" then
        return false
    end

    local methodNames = {
        "IsCurrencyTransferActive",
        "IsCurrencyTransferModeActive",
        "IsAccountCurrencyTransferActive",
        "IsAccountTransferModeActive",
        "IsTransferModeActive",
        "IsInTransferMode",
    }

    for _, methodName in ipairs(methodNames) do
        if SafeCall(target[methodName], target) then
            LogTransferDetection(string.format("%s:%s()", sourceLabel, methodName))
            return true
        end
    end

    local fieldNames = {
        "isCurrencyTransferActive",
        "isCurrencyTransferMode",
        "isAccountCurrencyTransferActive",
        "isAccountTransferMode",
        "isTransferModeActive",
        "isInTransferMode",
    }

    for _, fieldName in ipairs(fieldNames) do
        if target[fieldName] == true then
            LogTransferDetection(string.format("%s.%s", sourceLabel, fieldName))
            return true
        end
    end

    return false
end

local function IsCurrencyTransferActive()
    -- Keep the legacy frame checks, but layer on newer Token UI state checks.
    local candidates = {
        _G.CurrencyTransferMenu,
        _G.TokenFramePopup,
        _G.AccountCurrencyTransferFrame,
    }

    for _, frame in ipairs(candidates) do
        if frame and frame.IsShown and frame:IsShown() then
            LogTransferDetection("legacy visible transfer frame")
            return true
        end
    end

    local tokenFrame = FindTokenFrame()
    local tokenUICandidates = {
        tokenFrame,
        tokenFrame and tokenFrame.CurrencyTransferMenu,
        tokenFrame and tokenFrame.TransferMenu,
        tokenFrame and tokenFrame.AccountStorePanel,
        _G.AccountCurrencyTransferFrame,
        _G.CurrencyTransferMenu,
    }

    for _, candidate in ipairs(tokenUICandidates) do
        if HasActiveTransferFlag(candidate, "TokenUI") then
            return true
        end
    end

    if C_CurrencyInfo then
        local apiPredicates = {
            "IsCurrencyTransferActive",
            "IsAccountCurrencyTransferActive",
            "IsAccountCharacterCurrencyTransferActive",
            "IsCurrencyTransferModeActive",
        }

        for _, predicateName in ipairs(apiPredicates) do
            if SafeCall(C_CurrencyInfo[predicateName], C_CurrencyInfo) then
                LogTransferDetection(string.format("C_CurrencyInfo.%s()", predicateName))
                return true
            end
        end
    end

    return false
end

local ApplyFilter

local function CanMutateCurrencyUI()
    return not IsInCombat() and not IsCurrencyTransferActive()
end

local function RestoreOriginalProvider()
    if not State.scrollBox or not State.originalProvider then
        return false
    end

    if State.scrollBox:GetDataProvider() == State.originalProvider then
        return true
    end

    State.scrollBox:SetDataProvider(State.originalProvider, ScrollBoxConstants.RetainScrollPosition)
    return true
end

local function ProcessDeferredProviderMutations()
    if not CanMutateCurrencyUI() then
        UpdateMutationPauseState(true)
        if State.pendingRestoreOriginalProvider or State.pendingFilterRefresh then
            ShowMutationDeferredNoticeOnce()
        end
        return false
    end

    UpdateMutationPauseState(false)

    if State.pendingRestoreOriginalProvider then
        if RestoreOriginalProvider() then
            State.pendingRestoreOriginalProvider = false
        end
    end

    if State.pendingFilterRefresh then
        State.pendingFilterRefresh = false
        ApplyFilter()
    end

    return true
end

local function ResetFilterToDefault()
    if State.query == "" then
        return
    end

    State.query = ""

    if State.searchBox and State.searchBox.GetText and State.searchBox:GetText() ~= "" then
        State.searchBox:SetText("")
    end

    if not CanMutateCurrencyUI() then
        State.pendingRestoreOriginalProvider = true
        ShowMutationDeferredNoticeOnce()
        return
    end

    RestoreOriginalProvider()
end

local function HandleTransferStateChange()
    local isActive = IsCurrencyTransferActive()
    if isActive and not State.transferWasActive and Normalize(State.query) ~= "" then
        -- Keep the user's query/UI text untouched while transfer mode is
        -- active, and refresh it automatically when protected state ends.
        State.pendingFilterRefresh = true
        ShowMutationDeferredNoticeOnce()
    end

    State.transferWasActive = isActive
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

FindTokenFrame = function()
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

ApplyFilter = function()
    if ShouldDisableForTaintSafety() then
        ShowStrictModeBlockNoticeOnce()
        if not CanMutateCurrencyUI() then
            State.pendingRestoreOriginalProvider = true
            ShowMutationDeferredNoticeOnce()
            return
        end

        RestoreOriginalProvider()
        return
    end

    if not CanMutateCurrencyUI() then
        UpdateMutationPauseState(true)
        State.pendingFilterRefresh = true
        ShowMutationDeferredNoticeOnce()

        return
    end

    UpdateMutationPauseState(false)

    if not State.scrollBox or not State.originalProvider then
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
        ApplyFilter()
    end)

    editBox:SetScript("OnTextChanged", function(self)
        State.query = self:GetText() or ""
        ApplyFilter()
    end)

    editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        self:SetText("")
    end)

    State.searchBox = editBox
    State.clearButton = clearButton
end

local function EnsureVisibilityWatcher()
    if State.visibilityTicker then
        return
    end

    State.visibilityTicker = C_Timer.NewTicker(0.2, function()
        HandleTransferStateChange()
        ProcessDeferredProviderMutations()

        if not State.tokenFrame then
            return
        end

        local isShown = State.tokenFrame.IsShown and State.tokenFrame:IsShown()
        if isShown and not State.tokenFrameWasShown then
            State.tokenFrameWasShown = true
            RefreshOriginalProvider()
            ApplyFilter()
            return
        end

        if not isShown and State.tokenFrameWasShown then
            State.tokenFrameWasShown = false

            if State.searchBox and State.searchBox.GetText and State.searchBox:GetText() ~= "" then
                State.searchBox:SetText("")
            end

            State.query = ""

            if not CanMutateCurrencyUI() then
                State.pendingRestoreOriginalProvider = true
            else
                RestoreOriginalProvider()
            end
        end
    end)
end


local function TryInstall()
    if State.installed or State.installing then
        return
    end

    if IsInCombat() then
        State.pendingInstall = true
        return
    end

    if ShouldDisableForTaintSafety() then
        ShowStrictModeBlockNoticeOnce()
        return
    end

    State.strictModeBlockNoticeShown = false

    State.installing = true

    local tokenFrame = FindTokenFrame()
    if not tokenFrame then
        State.installing = false
        return
    end

    if not State.searchBox then
        CreateSearchUI(tokenFrame)
    end

    if not tokenFrame:IsShown() then
        -- TokenFrame can exist before scroll data exists; keep retrying the
        -- provider wiring while allowing the search UI to be created now.
        C_Timer.After(0.3, TryInstall)
        State.installing = false
        return
    end

    local scrollBox = FindScrollBox(tokenFrame)
    if not scrollBox then
        State.installing = false
        C_Timer.After(0.3, TryInstall)
        return
    end

    local provider = scrollBox:GetDataProvider()
    if not provider then
        State.installing = false
        C_Timer.After(0.3, TryInstall)
        return
    end

    State.tokenFrame = tokenFrame
    State.scrollBox = scrollBox
    State.originalProvider = provider

    EnsureVisibilityWatcher()
    State.tokenFrameWasShown = tokenFrame:IsShown()

    State.installed = true
    State.installing = false
    ApplyFilter()
end

local function ReevaluateModeState()
    if ShouldDisableForTaintSafety() then
        if State.searchBox and State.searchBox.GetText and State.searchBox:GetText() ~= "" then
            State.searchBox:SetText("")
        end
        State.query = ""

        if not CanMutateCurrencyUI() then
            State.pendingRestoreOriginalProvider = true
            ShowMutationDeferredNoticeOnce()
            return
        end

        RestoreOriginalProvider()
        return
    end

    TryInstall()

    if State.installed then
        ApplyFilter()
    end
end

SLASH_CURRENCYSEARCH1 = "/currencysearch"
SlashCmdList.CURRENCYSEARCH = function(message)
    local normalized = Normalize(message or "")
    local command, value = normalized:match("^(%S+)%s*(.-)$")

    if command ~= "mode" then
        print(string.format("%s: usage: /currencysearch mode strict|compat", ADDON_NAME))
        return
    end

    if value ~= MODE_STRICT and value ~= MODE_COMPAT then
        print(string.format("%s: unknown mode '%s'. Expected strict or compat.", ADDON_NAME, value ~= "" and value or ""))
        return
    end

    local currentMode = GetCurrentMode()
    if currentMode == value then
        print(string.format("%s: mode already set to %s.", ADDON_NAME, value))
        return
    end

    CurrencySearchDB.mode = value

    if value == MODE_COMPAT then
        print(string.format(
            "%s: compatibility mode enabled. Filtering is allowed with combat/transfer guards, but this increases the risk of taint (including ADDON_ACTION_FORBIDDEN during transfer UI interactions).",
            ADDON_NAME
        ))
    else
        print(string.format("%s: strict mode enabled. Conservative taint-safety install gating is active.", ADDON_NAME))
    end

    ReevaluateModeState()
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

eventFrame:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name == ADDON_NAME or name == "Blizzard_TokenUI" then
            -- Try a few times because Blizzard's frame setup can finish across
            -- multiple frames after ADDON_LOADED fires.
            C_Timer.After(0.5, TryInstall)
            C_Timer.After(1.5, TryInstall)
            C_Timer.After(3.0, TryInstall)
        end
        return
    end

    if event == "CURRENCY_DISPLAY_UPDATE" then
        if State.installed then
            HandleTransferStateChange()
            RefreshOriginalProvider()
            if Normalize(State.query) ~= "" then
                ApplyFilter()
            end
        end
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        if State.pendingInstall then
            State.pendingInstall = false
            TryInstall()
        end

        ProcessDeferredProviderMutations()

        return
    end

end)

if IsTokenUILoaded() then
    C_Timer.After(0, TryInstall)
end

GetCurrentMode()
