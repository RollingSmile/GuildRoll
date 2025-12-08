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
    elseif command == "roll ep" then
        -- EP-aware MainSpec roll (1+EP .. 100+EP)
        if GuildRoll and GuildRoll.RollCommand then
            GuildRoll:RollCommand(false, false, false, 0)
        end
    elseif command == "roll sr" then
        -- EP-aware SR roll (100+EP .. 200+EP)
        if GuildRoll and GuildRoll.RollCommand then
            GuildRoll:RollCommand(true, false, false, 0)
        end
    elseif command == "roll csr" then
        -- Use static popup dialog to input CSR weeks (0..15) and validate
        StaticPopupDialogs["CSR_INPUT"] = {
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
        StaticPopup_Show("CSR_INPUT")
    elseif command == "show ep" then
        if GuildRoll_standings and GuildRoll_standings.Toggle then
            GuildRoll_standings:Toggle()
        end
    end
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
rollButton:EnableMouse(true)
rollButton:SetFrameLevel((rollFrame:GetFrameLevel() or 0) + 5)

-- Container for roll buttons, initially hidden
local rollOptionsFrame = CreateFrame("Frame", "RollOptionsFrame", rollFrame)
rollOptionsFrame:SetPoint("TOP", rollButton, "BOTTOM", 0, -2)
rollOptionsFrame:SetWidth(140)
rollOptionsFrame:SetHeight(140)
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

-- == Revised rank detection with small caching ==
-- We know your guild rank layout: 0..3 should see CSR (0 GM, 1 Officer, 2 Veteran, 3 Core Raider)
-- Simple cache updated on PLAYER_LOGIN and GUILD_ROSTER_UPDATE to avoid repeated scans.

local CSR_DEBUG = false -- set to true to get debug prints in chat

local cachedRank = {
    ready = false,    -- true when roster checked at least once
    rankIndex = nil,  -- numeric index when available
    rankName = nil,   -- rank name when available
}

-- UpdateGuildRankCache: attempts to populate cachedRank; returns true if cache.ready true after call
local function UpdateGuildRankCache()
    if not IsInGuild() then
        if CSR_DEBUG then print("UpdateGuildRankCache: not in guild") end
        cachedRank.ready = true
        cachedRank.rankIndex = nil
        cachedRank.rankName = nil
        return true
    end

    -- Request roster refresh safely (modern or legacy)
    if C_GuildInfo and C_GuildInfo.RequestGuildRoster then
        pcall(C_GuildInfo.RequestGuildRoster)
    else
        pcall(GuildRoster)
    end

    local okNum, num = pcall(function() return GetNumGuildMembers(true) end)
    num = (okNum and num) and num or 0
    if num <= 0 then
        if CSR_DEBUG then print("UpdateGuildRankCache: roster not ready (num <= 0)") end
        cachedRank.ready = false
        cachedRank.rankIndex = nil
        cachedRank.rankName = nil
        return false
    end

    local playerName = UnitName("player")
    for i = 1, num do
        local name, rankName, rankIndex
        -- Try legacy API (GetGuildRosterInfo) which is widely supported
        local ok, n1, n2, n3 = pcall(function() return GetGuildRosterInfo(i) end)
        if ok and n1 then
            name = n1
            rankName = n2
            rankIndex = n3
        end

        -- If name obtained, compare (strip realm)
        if name then
            local simpleName = string.match(name, "^[^-]+") or name
            if simpleName == playerName then
                cachedRank.ready = true
                cachedRank.rankIndex = rankIndex
                cachedRank.rankName = rankName
                if CSR_DEBUG then
                    print(("UpdateGuildRankCache: found player -> rankIndex=%s rankName=%s"):format(tostring(rankIndex), tostring(rankName)))
                end
                return true
            end
        end
    end

    -- roster ready but player not found
    cachedRank.ready = true
    cachedRank.rankIndex = nil
    cachedRank.rankName = nil
    if CSR_DEBUG then print("UpdateGuildRankCache: roster ready but player not found") end
    return true
end

-- GetPlayerRankInfo now reads from cache; returns rankIndex, rankName, ready
local function GetPlayerRankInfo()
    return cachedRank.rankIndex, cachedRank.rankName, cachedRank.ready
end

-- CanSeeCSR uses API checks first, then the cached rankIndex (0..3 allowed)
local function CanSeeCSR()
    if not IsInGuild() then
        if CSR_DEBUG then print("CanSeeCSR: not in guild") end
        return false
    end

    if IsGuildLeader and IsGuildLeader() then
        if CSR_DEBUG then print("CanSeeCSR: IsGuildLeader -> true") end
        return true
    end
    if IsGuildOfficer and IsGuildOfficer() then
        if CSR_DEBUG then print("CanSeeCSR: IsGuildOfficer -> true") end
        return true
    end

    local rankIndex, rankName, ready = GetPlayerRankInfo()
    if not ready then
        if CSR_DEBUG then print("CanSeeCSR: cache not ready, returning false for now") end
        return false
    end

    if rankIndex and type(rankIndex) == "number" then
        if rankIndex >= 0 and rankIndex <= 3 then
            if CSR_DEBUG then print(("CanSeeCSR: rankIndex %d => CSR allowed"):format(rankIndex)) end
            return true
        else
            if CSR_DEBUG then print(("CanSeeCSR: rankIndex %d => CSR denied"):format(rankIndex)) end
            return false
        end
    end

    if CSR_DEBUG then print("CanSeeCSR: no rankIndex available, denying by default") end
    return false
end

-- Build options list lazily: EP-aware options + CSR (if permitted) + numeric legacy rolls + standings
local options = {
    { "EP(MS)", "roll ep" },     -- EP-aware MS (1+EP .. 100+EP)
    { "SR", "roll sr" },         -- EP-aware SR (100+EP .. 200+EP)
}

if CanSeeCSR() then
    table.insert(options, { "CSR", "roll csr" })
end

table.insert(options, { "101", "roll 101" })
table.insert(options, { "100", "roll 100" })
table.insert(options, { "99", "roll 99" })
table.insert(options, { "98", "roll 98" })
table.insert(options, { "Standings", "show ep" })

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

-- Safer rebuild handler: update cache first, then rebuild the options list deterministically
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event ~= "GUILD_ROSTER_UPDATE" and event ~= "PLAYER_LOGIN" then
        return
    end

    -- Update cached rank info (will set cachedRank.ready accordingly)
    UpdateGuildRankCache()

    -- Rebuild the options table fresh based on current CSR visibility
    local newOptions = {
        { "EP(MS)", "roll ep" },
        { "SR", "roll sr" },
    }
    if CanSeeCSR() then
        table.insert(newOptions, { "CSR", "roll csr" })
    end
    table.insert(newOptions, { "101", "roll 101" })
    table.insert(newOptions, { "100", "roll 100" })
    table.insert(newOptions, { "99", "roll 99" })
    table.insert(newOptions, { "98", "roll 98" })
    table.insert(newOptions, { "Standings", "show ep" })

    -- Clear existing option widgets safely
    if rollOptionsFrame then
        for i = rollOptionsFrame:GetNumChildren(), 1, -1 do
            local child = select(i, rollOptionsFrame:GetChildren())
            if child then
                child:Hide()
                child:SetParent(nil)
            end
        end
    end

    -- Recreate buttons under the rollOptionsFrame
    previousButton = rollOptionsFrame
    for _, opt in ipairs(newOptions) do
        local buttonFrame = CreateRollButton(opt[1], rollOptionsFrame, opt[2], previousButton, opt[3] or 110, opt[4] or false)
        if previousButton == rollOptionsFrame then
            buttonFrame:SetPoint("TOP", rollOptionsFrame, "TOP", 0, 0)
        else
            buttonFrame:SetPoint("TOP", previousButton, "BOTTOM", 0, 5)
        end
        previousButton = buttonFrame
    end

    -- Restore saved position behavior
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
