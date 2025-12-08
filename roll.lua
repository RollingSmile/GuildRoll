-- Ensure GuildRoll_RollPos is initialized with default values
GuildRoll_RollPos = GuildRoll_RollPos or { x = 400, y = 300 }
GuildRoll_showRollWindow = GuildRoll_showRollWindow == nil and true or GuildRoll_showRollWindow

-- Function to execute commands
local function ExecuteCommand(command)
    if command == "roll 101" then
        RandomRoll(1, 101)
    elseif command == "roll 100" then
        RandomRoll(1, 100)
    elseif command == "roll 99" then
        RandomRoll(1, 99)
    elseif command == "roll 98" then
        RandomRoll(1, 98)
    elseif command == "ret ms" then
        -- simple MS (client random 1-100)
        RandomRoll(1, 100)
    elseif command == "ret os" then
        -- simple OS (client random 1-99) -- no OSPenalty applied
        RandomRoll(1, 99)
    elseif command == "ret tmog" then
        -- transmog roll simple 1-98
        RandomRoll(1, 98)
    elseif command == "ret epms" then
        -- EP-aware MainSpec roll (1+EP .. 100+EP)
        if GuildRoll and GuildRoll.RollCommand then
            GuildRoll:RollCommand(false, false, false, 0)
        end
    elseif command == "ret sr" then
        -- EP-aware SR roll (100+EP .. 200+EP)
        if GuildRoll and GuildRoll.RollCommand then
            GuildRoll:RollCommand(true, false, false, 0)
        end
    elseif command == "ret csr" then
        -- Use static popup dialog to input CSR weeks (0..15) and validate
        StaticPopupDialogs["RET_CSR_INPUT"] = {
            text = "Enter number of weeks you SR this item (0..15):",
            button1 = TEXT(ACCEPT),
            button2 = TEXT(CANCEL),
            hasEditBox = 1,
            maxLetters = 5,
            OnAccept = function(self)
                local editBox = _G[self:GetName().."EditBox"]
                local number = tonumber(editBox and editBox:GetText())
                if number ~= nil then
                    local bonus = GuildRoll:calculateBonus(number)
                    if bonus == nil then
                        print("Invalid number entered. Valid values: 0,1 or 2..15")
                    else
                        GuildRoll:RollCommand(true, false, false, bonus)
                    end
                else
                    print("Invalid number entered.")
                end
            end,
            OnShow = function(self)
                local editBox = _G[self:GetName().."EditBox"]
                if editBox then
                    editBox:SetText("")
                    editBox:SetFocus()
                end
            end,
            OnHide = function(self)
                if ChatFrameEditBox and ChatFrameEditBox:IsVisible() then
                    ChatFrameEditBox:SetFocus()
                end
            end,
            EditBoxOnEnterPressed = function(editBox)
                local parent = editBox:GetParent()
                local number = tonumber(editBox:GetText())
                if number ~= nil then
                    local bonus = GuildRoll:calculateBonus(number)
                    if bonus == nil then
                        print("Invalid number entered. Valid values: 0,1 or 2..15")
                    else
                        GuildRoll:RollCommand(true, false, false, bonus)
                    end
                else
                    print("Invalid number entered.")
                end
                parent:Hide()
            end,
            EditBoxOnEscapePressed = function(self)
                self:GetParent():Hide()
            end,
            timeout = 0,
            exclusive = 1,
            whileDead = 1,
            hideOnEscape = 1,
        }
        StaticPopup_Show("RET_CSR_INPUT")
    elseif command == "ret show" then
        if GuildRoll_standings and GuildRoll_standings.Toggle then
            GuildRoll_standings:Toggle()
        end
    elseif command == "noice" then
end

-- Create a frame for the Roll button
local rollFrame = CreateFrame("Frame", "ShootyRollFrame", UIParent)
rollFrame:SetWidth(80)
rollFrame:SetHeight(41)
rollFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", GuildRoll_RollPos.x, GuildRoll_RollPos.y)

function GuildRoll:ResetButton()
    rollFrame:SetWidth(80)
    rollFrame:SetHeight(41)
    rollFrame:SetMovable(false)
    rollFrame:ClearAllPoints()
    rollFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", 400, 300)
    rollFrame:SetMovable(true)
end

if not GuildRoll_showRollWindow then
    rollFrame:Hide()
end
rollFrame:SetMovable(true)
rollFrame:EnableMouse(true)
rollFrame:RegisterForDrag("LeftButton")

-- Add a border to the frame so it's visible
rollFrame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 16,
    insets = { left = 8, right = 8, top = 8, bottom = 8 }
})

-- Create the Roll button inside the frame
local rollButton = CreateFrame("Button", "ShootyRollButton", rollFrame, "UIPanelButtonTemplate")
rollButton:SetWidth(96)
rollButton:SetHeight(30)
rollButton:SetText("Roll")
rollButton:SetPoint("CENTER", rollFrame, "CENTER")
-- Ensure the button receives mouse events and sits above parent
rollButton:EnableMouse(true)
rollButton:SetFrameLevel((rollFrame:GetFrameLevel() or 0) + 5)

-- Container for roll buttons, initially hidden
local rollOptionsFrame = CreateFrame("Frame", "RollOptionsFrame", rollFrame)
rollOptionsFrame:SetPoint("TOP", rollButton, "BOTTOM", 0, -2)
rollOptionsFrame:SetWidth(140)
rollOptionsFrame:SetHeight(160)
rollOptionsFrame:Hide()
rollOptionsFrame:SetFrameLevel(rollButton:GetFrameLevel() - 1)

-- Function to create roll option buttons
local function CreateRollButton(name, parent, command, anchor, width, font)
    local buttonFrame = CreateFrame("Frame", nil, parent)
    buttonFrame:SetWidth(120)
    buttonFrame:SetHeight(24)
    buttonFrame:SetPoint("TOP", anchor, "BOTTOM", 0, -2)

    buttonFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 16,
        insets = { left = 5, right = 5, top = 5, bottom = 5 }
    })

    local button = CreateFrame("Button", nil, buttonFrame, "UIPanelButtonTemplate")
    button:SetWidth(width or 110)
    button:SetHeight(20)
    button:SetText(name)
    button:SetPoint("CENTER", buttonFrame, "CENTER")
    if font then
        pcall(function() button:GetFontString():SetFont("Fonts\\FRIZQT__.TTF", 10) end)
    end
    button:SetScript("OnClick", function()
        ExecuteCommand(command)
        rollOptionsFrame:Hide()
    end)

    return buttonFrame
end

-- Helper: get player's rankIndex and the rankIndex of the "Core Raider" rank (if found)
local DEFAULT_REQUIRED_RANK_INDEX = 3 -- fallback if "Core Raider" rank not found; adjust if your guild uses different ordering (0 = Guild Master)

-- Safe function to get rank indices; returns (playerRankIndex, requiredRankIndex) or (nil, nil) if not possible
local function SafeGetPlayerAndRequiredRankIndices()
    if not IsInGuild() then return nil, nil end
    -- avoid calling GuildRoster in combat; pcall to avoid throwing errors
    if GuildRoster then
        pcall(GuildRoster)
    end
    local num = GetNumGuildMembers and (GetNumGuildMembers(true) or 0) or 0
    if num <= 0 then return nil, nil end
    local playerName = UnitName("player")
    local playerRankIndex, requiredRankIndex
    for i = 1, num do
        -- Use pcall to be safe around API quirks
        local ok, name, rankName, rankIndex = pcall(function() return GetGuildRosterInfo(i) end)
        if ok and name then
            local simpleName = string.match(name, "^[^-]+") or name
            if playerName and simpleName == playerName and playerRankIndex == nil then
                playerRankIndex = rankIndex
            end
            if rankName and type(rankName) == "string" then
                local rn = rankName:lower()
                if rn == "core raider" and requiredRankIndex == nil then
                    requiredRankIndex = rankIndex
                end
            end
            if playerRankIndex and requiredRankIndex then break end
        end
    end
    return playerRankIndex, requiredRankIndex
end

-- Determine if current player may see CSR button: Core Raider (by rank index) or higher
local function CanSeeCSR()
    if not IsInGuild() then return false end
    local playerRankIndex, requiredRankIndex = SafeGetPlayerAndRequiredRankIndices()
    if not playerRankIndex then return false end
    if not requiredRankIndex then
        requiredRankIndex = DEFAULT_REQUIRED_RANK_INDEX
    end
    -- rankIndex: lower number = higher rank
    return playerRankIndex <= requiredRankIndex
end

-- Build options list lazily: call CanSeeCSR() only now (not at file-load time)
local options = {
    { "MS", "ret ms" },           -- simple 1-100
    { "OS", "ret os" },           -- simple 1-99
    { "Tmog", "ret tmog" },       -- simple 1-98
    { "EP(MS)", "ret epms" },     -- EP-aware MS (1+EP .. 100+EP)
    { "SR", "ret sr" },           -- EP-aware SR (100+EP .. 200+EP)
}

-- Add CSR only if allowed by rank (evaluate now)
if CanSeeCSR() then
    table.insert(options, { "CSR", "ret csr" })
end

-- Add remaining/legacy options
table.insert(options, { "101", "roll 101" })
table.insert(options, { "100", "roll 100" })
table.insert(options, { "Standings", "ret show" })

-- Create roll buttons dynamically with closer spacing
local previousButton = rollOptionsFrame
for _, option in ipairs(options) do
    local buttonFrame = CreateRollButton(option[1], rollOptionsFrame, option[2], previousButton, option[3] or 110, option[4] or false)

    if previousButton == rollOptionsFrame then
        buttonFrame:SetPoint("TOP", rollOptionsFrame, "TOP", 0, 0)
    else
        buttonFrame:SetPoint("TOP", previousButton, "BOTTOM", 0, 5)
    end
    previousButton = buttonFrame
end

-- Toggle roll buttons on Roll button click
rollButton:SetScript("OnClick", function()
    -- debug print to verify click handler is run
    -- This should always print when clicking the button
    print("ShootyRollButton clicked; rollOptionsFrame shown? ", rollOptionsFrame:IsShown())
    if rollOptionsFrame:IsShown() then
        rollOptionsFrame:Hide()
    else
        rollOptionsFrame:Show()
    end
end)

-- Dragging & saving position
rollFrame:SetScript("OnMouseDown", function(_, button)
    if button == "LeftButton" then
        rollFrame:StartMoving()
    end
end)
rollFrame:SetScript("OnMouseUp", function(_, button)
    if button == "LeftButton" then
        rollFrame:StopMovingOrSizing()
        GuildRoll_RollPos.x = rollFrame:GetLeft()
        GuildRoll_RollPos.y = rollFrame:GetTop()
    end
end)
rollFrame:SetScript("OnDragStart", function() rollFrame:StartMoving() end)
rollFrame:SetScript("OnDragStop", function()
    rollFrame:StopMovingOrSizing()
    GuildRoll_RollPos.x = rollFrame:GetLeft()
    GuildRoll_RollPos.y = rollFrame:GetTop()
end)

-- Restore saved position on load
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("GUILD_ROSTER_UPDATE")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    -- On login or roster update, if the CSR visibility might change, update the UI button list
    -- Rebuild options only if roster update happened or on login
    if event == "GUILD_ROSTER_UPDATE" or event == "PLAYER_LOGIN" then
        -- Recompute CSR visibility
        local csrVisible = CanSeeCSR()
        -- If CSR became available and it's not in the options, add it and recreate buttons
        local foundCSR = false
        for _, opt in ipairs(options) do
            if opt[1] == "CSR" then foundCSR = true; break end
        end
        if csrVisible and not foundCSR then
            table.insert(options, #options - 3, { "CSR", "ret csr" }) -- insert before legacy options
            -- remove and re-create buttons: simple approach - hide old frames and create new list
            for i = rollOptionsFrame:GetNumChildren(), 1, -1 do
                local child = select(i, rollOptionsFrame:GetChildren())
                if child and child ~= nil and child.GetName and child:GetName() then
                    child:Hide()
                    child:SetParent(nil)
                end
            end
            previousButton = rollOptionsFrame
            for _, option in ipairs(options) do
                local buttonFrame = CreateRollButton(option[1], rollOptionsFrame, option[2], previousButton, option[3] or 110, option[4] or false)
                if previousButton == rollOptionsFrame then
                    buttonFrame:SetPoint("TOP", rollOptionsFrame, "TOP", 0, 0)
                else
                    buttonFrame:SetPoint("TOP", previousButton, "BOTTOM", 0, 5)
                end
                previousButton = buttonFrame
            end
        end
    end

    -- Restore position behavior
    if GuildRoll_RollPos.x and GuildRoll_RollPos.y then
        rollFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", GuildRoll_RollPos.x, GuildRoll_RollPos.y)
    else
        GuildRoll_RollPos = { x = 400, y = 300 }
        rollFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", GuildRoll_RollPos.x, GuildRoll_RollPos.y)
    end
    if not GuildRoll_showRollWindow then
        rollFrame:Hide()
    else
        rollFrame:Show()
    end
end)
