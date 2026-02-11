local ADDON_NAME = ...

local searchText = ""
local initialized = false
local pendingFilterApply = false
local ApplyFilter

local filterFrame = CreateFrame("Frame")
filterFrame:SetScript("OnUpdate", function()
    if pendingFilterApply then
        pendingFilterApply = false
        ApplyFilter()
    end
end)

local function ScheduleFilterApply()
    pendingFilterApply = true
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

local function GetButtons()
    if not TokenFrameContainer then
        return nil
    end

    if TokenFrameContainer.buttons then
        return TokenFrameContainer.buttons
    end

    if TokenFrameContainer.ScrollBox and TokenFrameContainer.ScrollBox:GetFrames() then
        return TokenFrameContainer.ScrollBox:GetFrames()
    end

    return nil
end

local function ButtonMatches(button, query)
    if not button then
        return false
    end

    local nameText

    if button.name and button.name.GetText then
        nameText = button.name:GetText()
    elseif button.Name and button.Name.GetText then
        nameText = button.Name:GetText()
    end

    if not nameText or nameText == "" then
        return false
    end

    return string.find(string.lower(nameText), query, 1, true) ~= nil
end

ApplyFilter = function()
    local query = string.lower(searchText or "")

    local buttons = GetButtons()
    if not buttons then
        return
    end

    local hasMatch = false

    for _, button in pairs(buttons) do
        if query == "" or ButtonMatches(button, query) then
            button:Show()
            hasMatch = true
        else
            button:Hide()
        end
    end

    if query ~= "" and not hasMatch then
        for _, button in pairs(buttons) do
            button:Hide()
        end
    end
end

local function RefreshTokenFrame()
    if not TokenFrame or not TokenFrame:IsShown() then
        return
    end

    if type(TokenFrame_Update) == "function" then
        TokenFrame_Update()
    elseif type(CurrencyFrame_Update) == "function" then
        CurrencyFrame_Update()
    elseif TokenFrame and type(TokenFrame.Update) == "function" then
        TokenFrame:Update()
    elseif TokenFrameContainer and type(TokenFrameContainer.Update) == "function" then
        TokenFrameContainer:Update()
    else
        ApplyFilter()
        return
    end

    ScheduleFilterApply()
end

local function HookUpdateHandler()
    if type(TokenFrame_Update) == "function" then
        hooksecurefunc("TokenFrame_Update", ApplyFilter)
        return
    end

    if type(CurrencyFrame_Update) == "function" then
        hooksecurefunc("CurrencyFrame_Update", ApplyFilter)
        return
    end

    if TokenFrame and type(TokenFrame.Update) == "function" then
        hooksecurefunc(TokenFrame, "Update", ApplyFilter)
        return
    end

    if TokenFrameContainer and type(TokenFrameContainer.Update) == "function" then
        hooksecurefunc(TokenFrameContainer, "Update", ApplyFilter)
    end
end

local function CreateSearchBox()
    if initialized or not TokenFrame then
        return
    end

    initialized = true

    local editBox = CreateFrame("EditBox", "WOWCurrencySearchBox", TokenFrame, "SearchBoxTemplate")
    editBox:SetSize(160, 20)
    editBox:SetPoint("TOPLEFT", TokenFrame, "TOPLEFT", 70, -35)
    editBox:SetAutoFocus(false)

    if editBox.Instructions then
        editBox.Instructions:SetText(SEARCH)
    end

    editBox:SetScript("OnTextChanged", function(self)
        searchText = self:GetText() or ""

        if self.Instructions then
            if searchText == "" and not self:HasFocus() then
                self.Instructions:Show()
            else
                self.Instructions:Hide()
            end
        end

        ScheduleFilterApply()
        RefreshTokenFrame()
    end)

    editBox:SetScript("OnEditFocusGained", function(self)
        if self.Instructions then
            self.Instructions:Hide()
        end
    end)

    editBox:SetScript("OnEditFocusLost", function(self)
        if self.Instructions and (self:GetText() or "") == "" then
            self.Instructions:Show()
        end
    end)

    editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        self:SetText("")
    end)

    TokenFrame:HookScript("OnHide", function()
        editBox:SetText("")
        searchText = ""
    end)

    HookUpdateHandler()

    TokenFrame:HookScript("OnShow", ScheduleFilterApply)
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")

eventFrame:SetScript("OnEvent", function(_, event, name)
    if event ~= "ADDON_LOADED" then
        return
    end

    if name == ADDON_NAME or name == "Blizzard_TokenUI" then
        if IsTokenUILoaded() then
            CreateSearchBox()
        end
    end
end)

if IsTokenUILoaded() then
    CreateSearchBox()
end
