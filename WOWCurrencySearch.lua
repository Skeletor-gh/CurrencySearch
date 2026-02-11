local ADDON_NAME = ...

local searchText = ""
local initialized = false

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
    if not button or not button:IsShown() then
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

local function ApplyFilter()
    local query = string.lower(searchText or "")

    if query == "" then
        return
    end

    local buttons = GetButtons()
    if not buttons then
        return
    end

    for _, button in ipairs(buttons) do
        if ButtonMatches(button, query) then
            button:Show()
        else
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
    else
        ApplyFilter()
    end
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
    end
end

local function CreateSearchBox()
    if initialized or not TokenFrame then
        return
    end

    initialized = true

    local editBox = CreateFrame("EditBox", "WOWCurrencySearchBox", TokenFrame, "SearchBoxTemplate")
    editBox:SetSize(160, 20)
    editBox:SetPoint("TOPRIGHT", TokenFrame, "TOPRIGHT", -30, -30)
    editBox:SetAutoFocus(false)
    editBox.Instructions:SetText(SEARCH)

    editBox:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then
            return
        end

        searchText = self:GetText() or ""
        RefreshTokenFrame()
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

    TokenFrame:HookScript("OnShow", ApplyFilter)
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
