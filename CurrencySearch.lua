local ADDON_NAME = ...

local CurrencySearch = CreateFrame("Frame")
CurrencySearch.db = nil
CurrencySearch.searchBox = nil
CurrencySearch.currentQuery = ""
CurrencySearch._isApplying = false
CurrencySearch._didHookRefreshTargets = false
CurrencySearch._didFlattenHeaders = false
CurrencySearch._savedHeaderStates = nil
CurrencySearch._didRegisterRuntimeEvents = false
CurrencySearch._didHookRowButtons = false

local function trim(text)
    if not text then
        return ""
    end

    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function lower(text)
    return string.lower(text or "")
end

local function contains(haystack, needle)
    return string.find(haystack, needle, 1, true) ~= nil
end

local function tokenize(text)
    local tokens = {}
    for token in string.gmatch(text or "", "%S+") do
        tokens[#tokens + 1] = token
    end

    return tokens
end

local function startsWith(text, prefix)
    return prefix ~= "" and string.sub(text, 1, string.len(prefix)) == prefix
end

local function matchesQuery(rowName, query)
    if rowName == "" or query == "" then
        return false
    end

    if contains(rowName, query) then
        return true
    end

    local rowWords = tokenize(rowName)
    local queryWords = tokenize(query)

    if #queryWords == 0 then
        return false
    end

    for _, queryWord in ipairs(queryWords) do
        local matchedWord = false
        for _, rowWord in ipairs(rowWords) do
            if startsWith(rowWord, queryWord) or contains(rowWord, queryWord) then
                matchedWord = true
                break
            end
        end

        if not matchedWord then
            return false
        end
    end

    return true
end

local function getButtonData(button)
    if not button then
        return nil
    end

    if button.GetElementData then
        local data = button:GetElementData()
        if data then
            return data
        end
    end

    return button.data
end

local function getCurrencyInfoForButton(button)
    if not button then
        return nil
    end

    if button.currencyInfo then
        return button.currencyInfo
    end

    if button.info then
        return button.info
    end

    local data = getButtonData(button)
    if data then
        if data.currencyInfo then
            return data.currencyInfo
        end

        if data.info then
            return data.info
        end

        if data.name or data.isHeader ~= nil then
            return data
        end
    end

    if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyListInfo then
        local index = button.index or button.currencyIndex or button.dataIndex or (button.GetID and button:GetID())
        if not index and data then
            index = data.index or data.currencyIndex or data.listIndex
        end

        if index then
            return C_CurrencyInfo.GetCurrencyListInfo(index)
        end
    end

    return nil
end

local function getCurrencyListIndex(button, info)
    local data = getButtonData(button)

    if info then
        if info.index then
            return info.index
        end

        if info.currencyIndex then
            return info.currencyIndex
        end

        if info.listIndex then
            return info.listIndex
        end
    end

    if data then
        if data.index then
            return data.index
        end

        if data.currencyIndex then
            return data.currencyIndex
        end

        if data.listIndex then
            return data.listIndex
        end
    end

    return button and (button.index or button.currencyIndex or button.dataIndex or (button.GetID and button:GetID())) or nil
end

local function isHeaderExpanded(info)
    if not info then
        return nil
    end

    if info.isHeaderExpanded ~= nil then
        return info.isHeaderExpanded
    end

    if info.isExpanded ~= nil then
        return info.isExpanded
    end

    return nil
end

local function setHeaderExpanded(index, shouldExpand)
    if not index then
        return
    end

    if C_CurrencyInfo and C_CurrencyInfo.ExpandCurrencyList then
        pcall(C_CurrencyInfo.ExpandCurrencyList, index, shouldExpand)
        return
    end

    if ExpandCurrencyList then
        pcall(ExpandCurrencyList, index, shouldExpand and 1 or 0)
    end
end

local function getCurrencyLabel(button)
    local info = getCurrencyInfoForButton(button)
    if info and info.name and info.name ~= "" then
        return info.name
    end

    if button and button.Name and button.Name.GetText then
        return button.Name:GetText()
    end

    if button and button.name and button.name.GetText then
        return button.name:GetText()
    end

    if button and button.CurrencyName and button.CurrencyName.GetText then
        return button.CurrencyName:GetText()
    end

    if button and button.GetRegions then
        for _, region in ipairs({ button:GetRegions() }) do
            if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                local text = region:GetText()
                if text and text ~= "" then
                    return text
                end
            end
        end
    end

    return nil
end

local function isHeaderRow(button)
    local info = getCurrencyInfoForButton(button)
    if info and info.isHeader ~= nil then
        return info.isHeader
    end

    if button and button.isHeader ~= nil then
        return button.isHeader
    end

    local data = getButtonData(button)
    if data and data.isHeader ~= nil then
        return data.isHeader
    end

    return false
end

local function isFilterableCurrencyRow(button)
    if isHeaderRow(button) then
        return false
    end

    local info = getCurrencyInfoForButton(button)
    if info and info.name ~= nil then
        return true
    end

    local label = getCurrencyLabel(button)
    return label ~= nil and trim(label) ~= ""
end

local function isProtectedUtilityButton(button)
    if not button then
        return false
    end

    local objectName = button.GetName and button:GetName() or nil
    if objectName and string.find(objectName, "Transfer", 1, true) then
        return true
    end

    local data = getButtonData(button)
    if data then
        local dataType = data.entryType or data.type or data.buttonType
        if dataType == "transfer" or dataType == "transferLog" then
            return true
        end
    end

    return false
end

function CurrencySearch:HookRowButtons(buttons)
    for _, button in ipairs(buttons) do
        if button and not button._currencySearchHooked and button.HookScript then
            button:HookScript("OnShow", function()
                CurrencySearch:RefreshIfVisible()
            end)
            button._currencySearchHooked = true
        end
    end

    self._didHookRowButtons = true
end

function CurrencySearch:GetRootFrame()
    if TokenFrame and TokenFrame:IsObjectType("Frame") then
        return TokenFrame
    end

    if CurrencyFrame and CurrencyFrame:IsObjectType("Frame") then
        return CurrencyFrame
    end

    return nil
end

function CurrencySearch:CollectCurrencyButtons()
    local result = {}

    if TokenFrameContainer and TokenFrameContainer.buttons then
        for _, button in ipairs(TokenFrameContainer.buttons) do
            if button and button.IsObjectType and button:IsObjectType("Button") then
                result[#result + 1] = button
            end
        end
    end

    if CurrencyFrame and CurrencyFrame.Container and CurrencyFrame.Container.buttons then
        for _, button in ipairs(CurrencyFrame.Container.buttons) do
            if button and button.IsObjectType and button:IsObjectType("Button") then
                result[#result + 1] = button
            end
        end
    end

    if #result > 0 then
        return result
    end

    local root = self:GetRootFrame()
    if not root then
        return result
    end

    local stack = { root }
    while #stack > 0 do
        local node = table.remove(stack)
        for _, child in ipairs({ node:GetChildren() }) do
            stack[#stack + 1] = child
            if child and child.IsObjectType and child:IsObjectType("Button") then
                local info = getCurrencyInfoForButton(child)
                if info and (info.name or info.isHeader ~= nil) then
                    result[#result + 1] = child
                end
            end
        end
    end

    return result
end

function CurrencySearch:ApplyFilter()
    if self._isApplying then
        return
    end

    self._isApplying = true

    local enabled = self.db and self.db.enabled
    local query = lower(trim(self.currentQuery))
    local hasQuery = query ~= ""

    local buttons = self:CollectCurrencyButtons()
    self:HookRowButtons(buttons)

    if enabled and hasQuery then
        if not self._didFlattenHeaders then
            self._savedHeaderStates = {}
            for _, button in ipairs(buttons) do
                local info = getCurrencyInfoForButton(button)
                if isHeaderRow(button) then
                    local index = getCurrencyListIndex(button, info)
                    local expanded = isHeaderExpanded(info)
                    if index and expanded ~= nil and self._savedHeaderStates[index] == nil then
                        self._savedHeaderStates[index] = expanded
                    end

                    if index and expanded == false then
                        setHeaderExpanded(index, true)
                    end
                end
            end

            self._didFlattenHeaders = true
            buttons = self:CollectCurrencyButtons()
        end
    elseif self._didFlattenHeaders then
        if self._savedHeaderStates then
            for index, expanded in pairs(self._savedHeaderStates) do
                setHeaderExpanded(index, expanded)
            end
        end

        self._savedHeaderStates = nil
        self._didFlattenHeaders = false
        buttons = self:CollectCurrencyButtons()
    end

    for _, button in ipairs(buttons) do
        if button then
            if not enabled or not hasQuery then
                button:Show()
            else
                if isProtectedUtilityButton(button) then
                    button:Show()
                elseif isHeaderRow(button) then
                    button:Hide()
                else
                    local rowName = lower(getCurrencyLabel(button) or "")
                    local show = isFilterableCurrencyRow(button) and matchesQuery(rowName, query)
                    if show then
                        button:Show()
                    else
                        button:Hide()
                    end
                end
            end
        end
    end

    self._isApplying = false

end

function CurrencySearch:ClearFilter(clearSearchText)
    self.currentQuery = ""

    if clearSearchText and self.searchBox and self.searchBox:GetText() ~= "" then
        self.searchBox:SetText("")
    end

    self:ApplyFilter()
end

function CurrencySearch:HandleCurrencyTabClosed()
    self:ClearFilter(true)
end

function CurrencySearch:HandleSearchCleared()
    self:ClearFilter(false)
end

function CurrencySearch:HookRefreshTargets()
    if self._didHookRefreshTargets then
        return
    end

    local function hookRegion(region)
        if not region then
            return
        end

        if region.HookScript then
            local function safeHook(scriptName)
                pcall(region.HookScript, region, scriptName, function()
                    CurrencySearch:RefreshIfVisible()
                end)
            end

            safeHook("OnVerticalScroll")
            safeHook("OnValueChanged")
            safeHook("OnMouseWheel")
        end

        if region.ScrollBar then
            hookRegion(region.ScrollBar)
        end

        if region.scrollBar then
            hookRegion(region.scrollBar)
        end
    end

    hookRegion(TokenFrameContainer)
    if TokenFrame and TokenFrame.ScrollBar then
        hookRegion(TokenFrame.ScrollBar)
    end

    if CurrencyFrame and CurrencyFrame.Container then
        hookRegion(CurrencyFrame.Container)
    end

    self._didHookRefreshTargets = true
end

function CurrencySearch:RegisterRuntimeEvents()
    if self._didRegisterRuntimeEvents then
        return
    end

    self:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
    self:RegisterEvent("PLAYER_MONEY")
    self:RegisterEvent("CURRENCY_TRANSFER_LOG_UPDATE")
    self._didRegisterRuntimeEvents = true
end

function CurrencySearch:TryInitializeUIBindings()
    self:CreateSearchBox()
    self:InitializeSlashCommands()
    self:HookRefreshTargets()
    self:RegisterRuntimeEvents()

    if TokenFrame and not self._tokenFrameHooksAdded then
        TokenFrame:HookScript("OnShow", function()
            CurrencySearch:CreateSearchBox()
            CurrencySearch:UpdateSearchBoxVisibility()
            CurrencySearch:RefreshIfVisible()
        end)

        TokenFrame:HookScript("OnHide", function()
            CurrencySearch:HandleCurrencyTabClosed()
        end)

        self._tokenFrameHooksAdded = true
    end

    if CurrencyFrame and not self._currencyFrameHooksAdded then
        CurrencyFrame:HookScript("OnShow", function()
            CurrencySearch:CreateSearchBox()
            CurrencySearch:UpdateSearchBoxVisibility()
            CurrencySearch:RefreshIfVisible()
        end)

        CurrencyFrame:HookScript("OnHide", function()
            CurrencySearch:HandleCurrencyTabClosed()
        end)

        self._currencyFrameHooksAdded = true
    end
end

function CurrencySearch:RefreshIfVisible()
    local root = self:GetRootFrame()
    if root and root:IsShown() then
        self:ApplyFilter()
    end
end

function CurrencySearch:SetEnabled(enabled)
    self.db.enabled = enabled and true or false

    if not self.db.enabled then
        if self._didFlattenHeaders and self._savedHeaderStates then
            for index, expanded in pairs(self._savedHeaderStates) do
                setHeaderExpanded(index, expanded)
            end
        end

        self._savedHeaderStates = nil
        self._didFlattenHeaders = false
        self:ClearFilter(true)
    end

    self:RefreshIfVisible()

    if self.db.enabled then
        print("CurrencySearch: enabled")
    else
        print("CurrencySearch: disabled")
    end
end

function CurrencySearch:CreateSearchBox()
    if self.searchBox then
        return
    end

    local parent = self:GetRootFrame()
    if not parent then
        return
    end

    local searchBox = CreateFrame("EditBox", "CurrencySearchEditBox", parent, "SearchBoxTemplate")
    searchBox:SetSize(180, 20)
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(20)
    searchBox:SetPoint("TOPLEFT", parent, "TOPLEFT", 56, -32)

    searchBox:HookScript("OnTextChanged", function(editBox)
        CurrencySearch.currentQuery = editBox:GetText() or ""
        CurrencySearch:ApplyFilter()
    end)

    searchBox:HookScript("OnEscapePressed", function(editBox)
        editBox:ClearFocus()
    end)

    local clearButton = searchBox.ClearButton
    if clearButton then
        clearButton:HookScript("OnClick", function()
            CurrencySearch:HandleSearchCleared()
        end)
    end

    self.searchBox = searchBox
    self:UpdateSearchBoxVisibility()
end

function CurrencySearch:UpdateSearchBoxVisibility()
    if not self.searchBox then
        return
    end

    if self.db and self.db.enabled then
        self.searchBox:Show()
    else
        self.searchBox:Hide()
    end
end

function CurrencySearch:InitializeSlashCommands()
    SLASH_CURRENCYSEARCH1 = "/cs"
    SlashCmdList.CURRENCYSEARCH = function(message)
        local cmd = lower(trim(message))

        if cmd == "on" or cmd == "enable" then
            CurrencySearch:SetEnabled(true)
            CurrencySearch:UpdateSearchBoxVisibility()
            return
        end

        if cmd == "off" or cmd == "disable" then
            CurrencySearch:SetEnabled(false)
            CurrencySearch:UpdateSearchBoxVisibility()
            return
        end

        print("CurrencySearch commands: /cs on, /cs off, /cs enable, /cs disable")
    end
end

function CurrencySearch:OnEvent(event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == "Blizzard_TokenUI" then
            self:TryInitializeUIBindings()
            return
        end

        if arg1 ~= ADDON_NAME then
            return
        end

        if CurrencySearchDB == nil then
            CurrencySearchDB = {}
        end

        if CurrencySearchDB.enabled == nil then
            CurrencySearchDB.enabled = true
        end

        self.db = CurrencySearchDB
        return
    end

    if event == "PLAYER_LOGIN" then
        self:TryInitializeUIBindings()

        if not TokenFrame and not CurrencyFrame then
            self:RegisterEvent("ADDON_LOADED")
            UIParentLoadAddOn("Blizzard_TokenUI")
        end

        if TokenFrame_Update then
            hooksecurefunc("TokenFrame_Update", function()
                CurrencySearch:RefreshIfVisible()
            end)
        end

        return
    end
    if event == "CURRENCY_DISPLAY_UPDATE" or event == "PLAYER_MONEY" or event == "CURRENCY_TRANSFER_LOG_UPDATE" then
        self:RefreshIfVisible()
    end
end

CurrencySearch:SetScript("OnEvent", function(_, event, ...)
    CurrencySearch:OnEvent(event, ...)
end)

CurrencySearch:RegisterEvent("ADDON_LOADED")
CurrencySearch:RegisterEvent("PLAYER_LOGIN")
