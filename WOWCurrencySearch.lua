local ADDON_NAME = ...

local searchText = ""
local initialized = false

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
    if TokenFrame and TokenFrame:IsShown() and TokenFrame_Update then
        TokenFrame_Update()
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

    hooksecurefunc("TokenFrame_Update", ApplyFilter)
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")

eventFrame:SetScript("OnEvent", function(_, event, name)
    if event ~= "ADDON_LOADED" then
        return
    end

    if name == ADDON_NAME or name == "Blizzard_TokenUI" then
        if IsAddOnLoaded("Blizzard_TokenUI") then
            CreateSearchBox()
        end
    end
end)

if IsAddOnLoaded("Blizzard_TokenUI") then
    CreateSearchBox()
end
