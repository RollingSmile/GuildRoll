-- Localization support
local L = AceLibrary("AceLocale-2.2"):new("guildroll")

-- Ensure GuildRoll_RollPos is initialized with default values
GuildRoll_RollPos = GuildRoll_RollPos or { x = 400, y = 300 }
GuildRoll_showRollWindow = GuildRoll_showRollWindow == nil and true or GuildRoll_showRollWindow
-- Initialize CSR threshold (default = 3, meaning rank index 0-3 can see CSR)
GuildRoll_CSRThreshold = GuildRoll_CSRThreshold or 3
-- Initialize EnableRollButtons flag (default = false)
GuildRoll_EnableRollButtons = GuildRoll_EnableRollButtons or false

-- Helper: Check if player has permission to view CSR based on rank index
-- Robust version that handles stale/empty guild roster, strips realm names, compares rankIndex safely
local function PlayerHasCSRPermission()
    if not IsInGuild() then
        return false
    end

    local threshold = tonumber(GuildRoll_CSRThreshold)
    if not threshold then
      -- No threshold set => CSR hidden
      return false
    end

    local playerName = UnitName("player")
    if playerName then
        playerName = string.gsub(playerName, "%-[^%-]+$", "")
    end

    local numMembers = GetNumGuildMembers()
    if not numMembers or numMembers == 0 then
        pcall(GuildRoster)
        return false
    end

    for i = 1, numMembers do
        local name, rank, rankIndex = GetGuildRosterInfo(i)
        if name then
            name = string.gsub(name, "%-[^%-]+$", "")
        end

        if name == playerName and rankIndex then
            local numericRank = tonumber(rankIndex)
            return numericRank and numericRank <= threshold
        end
    end

    return false
end

-- Helper: Check if current character is an Alt using GuildRoll:parseAlt
-- Returns true if the character has an alt tag (has a main), false otherwise
local function IsAlt()
    if not GuildRoll or not GuildRoll.parseAlt then
        return false
    end
    
    local playerName = UnitName("player")
    if not playerName then
        return false
    end
    
    -- Strip realm suffix from player name for comparison
    local playerNameClean = string.gsub(playerName, "%-[^%-]+$", "")
    
    -- If guild roster is empty, trigger a refresh
    local numMembers = GetNumGuildMembers()
    if not numMembers or numMembers == 0 then
        pcall(GuildRoster)
        return false
    end
    
    -- pcall-wrapped call to parseAlt with cleaned player name
    local success, main = pcall(function()
        return GuildRoll:parseAlt(playerNameClean)
    end)
    
    -- If parseAlt returns a main character name, this is an alt
    if success and main and type(main) == "string" then
        -- Strip realm suffix from main name for comparison
        local mainClean = string.gsub(main, "%-[^%-]+$", "")
        if mainClean ~= playerNameClean then
            return true
        end
    end
    
    return false
end

-- Helper: try to find the EditBox for a StaticPopup dialog robustly
local function GetVisibleStaticPopupEditBox(dialog)
    -- Try using the dialog passed in (if any)
    if dialog and dialog.GetName then
        local name = dialog:GetName()
        if name then
            local eb = _G[name .. "EditBox"]
            if eb then return eb end
        end
    end

    -- Fallback: scan known StaticPopup frames for a shown one
    local num = STATICPOPUP_NUMDIALOGS or 4
    for i = 1, num do
        local dlg = _G["StaticPopup" .. i]
        if dlg and dlg:IsShown() then
            local eb = _G[dlg:GetName() .. "EditBox"]
            if eb then return eb end
        end
    end

    return nil
end

-- Function to execute commands
local function ExecuteCommand(command)
    if command == "roll 101" then
        RandomRoll(1, 101)
    elseif command == "roll 100" then
        RandomRoll(1, 100)
    elseif command == "roll 99" then
        RandomRoll(1, 99)
    elseif command == "roll tmog" then
        -- Tmog roll uses 98 to differentiate from other OS rolls (99)
        RandomRoll(1, 98)
    elseif command == "roll ep" then
        -- EP-aware MainSpec roll (1+EP .. 100+EP)
        if GuildRoll and GuildRoll.RollCommand then
            GuildRoll:RollCommand(false, 0)
        end
    elseif command == "roll sr" then
        -- EP-aware SR roll (100+EP .. 200+EP)
        if GuildRoll and GuildRoll.RollCommand then
            GuildRoll:RollCommand(true, 0)
        end
    elseif command == "roll csr" then
        -- Use static popup dialog to input CSR weeks (0..15) and validate
        StaticPopupDialogs["CSR_INPUT"] = {
            text = L["Enter number of weeks you SR this item (0..15):"],
            button1 = TEXT(ACCEPT),
            button2 = TEXT(CANCEL),
            hasEditBox = 1,
            maxLetters = 5,
            OnAccept = function(self)
                -- Use helper to get the editbox robustly
                local editBox = GetVisibleStaticPopupEditBox(self)
                local number = tonumber(editBox and editBox:GetText())
                if number ~= nil then
                    if GuildRoll and GuildRoll.calculateBonus then
                        local bonus = GuildRoll:calculateBonus(number)
                        if bonus == nil then
                            print("Invalid number entered. Valid values: 0,1 or 2..15")
                        else
                            if GuildRoll.RollCommand then
                                GuildRoll:RollCommand(true, bonus)
                            end
                        end
                    else
                        print("GuildRoll not available.")
                    end
                else
                    print("Invalid number entered.")
                end
            end,
            OnShow = function(self)
                -- Use helper and guard against nil
                local editBox = GetVisibleStaticPopupEditBox(self)
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
                local parent = editBox and editBox:GetParent()
                local number = tonumber(editBox and editBox:GetText())
                if number ~= nil then
                    if GuildRoll and GuildRoll.calculateBonus then
                        local bonus = GuildRoll:calculateBonus(number)
                        if bonus == nil then
                            print("Invalid number entered. Valid values: 0,1 or 2..15")
                        else
                            if GuildRoll.RollCommand then
                                GuildRoll:RollCommand(true, bonus)
                            end
                        end
                    else
                        print("GuildRoll not available.")
                    end
                else
                    print("Invalid number entered.")
                end
                if parent and parent.Hide then parent:Hide() end
            end,
            EditBoxOnEscapePressed = function(editBox)
                -- Callback can be invoked with the editBox as argument; guard it
                local parent = editBox and editBox:GetParent()
                if parent and parent.Hide then parent:Hide() end
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

-- Function to execute admin commands
local function ExecuteAdminCommand(command)
    if command == "toggle_standings" then
        if GuildRoll_standings and GuildRoll_standings.Toggle then
            pcall(function() GuildRoll_standings:Toggle() end)
        end
    elseif command == "buff_check" then
        if GuildRoll_BuffCheck and GuildRoll_BuffCheck.CheckBuffs then
            pcall(function() GuildRoll_BuffCheck:CheckBuffs() end)
        end
    elseif command == "consumes_check" then
        if GuildRoll_BuffCheck and GuildRoll_BuffCheck.CheckConsumes then
            pcall(function() GuildRoll_BuffCheck:CheckConsumes() end)
        end
    elseif command == "flasks_check" then
        if GuildRoll_BuffCheck and GuildRoll_BuffCheck.CheckFlasks then
            pcall(function() GuildRoll_BuffCheck:CheckFlasks() end)
        end
    elseif command == "give_ep_raid" then
        if GuildRoll and GuildRoll.PromptAwardRaidEP then
            pcall(function() GuildRoll:PromptAwardRaidEP() end)
        end
    end
end

-- Create a frame for the Roll button
local rollFrame = CreateFrame("Frame", "GuildEpRollFrame", UIParent)
-- Make the frame snug around the button: button 96x30 with small padding (insets = 3)
rollFrame:SetWidth(102)  -- 96 + 3*2
rollFrame:SetHeight(36)  -- 30 + 3*2
rollFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", GuildRoll_RollPos.x, GuildRoll_RollPos.y)

function GuildRoll:ResetButton()
    -- Match reset size to the frame so the border encloses the button snugly
    rollFrame:SetWidth(102)
    rollFrame:SetHeight(36)
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

-- Add a border to the frame so it's visible; small insets make it close to the button
rollFrame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 16,
    insets = { left = 3, right = 3, top = 3, bottom = 3 }
})

-- Create the Roll button inside the frame
local rollButton = CreateFrame("Button", "GuildEpRollButton", rollFrame, "UIPanelButtonTemplate")
rollButton:SetWidth(96)
rollButton:SetHeight(30)
rollButton:SetText("Roll")
rollButton:SetPoint("CENTER", rollFrame, "CENTER")
rollButton:EnableMouse(true)
rollButton:SetFrameLevel((rollFrame:GetFrameLevel() or 0) + 5)
-- Register for both left and right clicks
rollButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")

-- Make the button participate in dragging so you can drag by holding the button itself
-- Drag will start when the mouse moves past the system drag threshold (standard behavior)
rollButton:RegisterForDrag("LeftButton")
rollButton:SetScript("OnDragStart", function()
    if rollFrame and rollFrame.StartMoving then
        rollFrame:StartMoving()
    end
end)
rollButton:SetScript("OnDragStop", function()
    if rollFrame and rollFrame.StopMovingOrSizing then
        rollFrame:StopMovingOrSizing()
        -- save position
        GuildRoll_RollPos.x = rollFrame:GetLeft()
        GuildRoll_RollPos.y = rollFrame:GetTop()
    end
end)

-- Container for roll buttons popup (two columns), initially hidden
local rollOptionsFrame = CreateFrame("Frame", "RollOptionsFrame", rollFrame)
rollOptionsFrame:SetPoint("TOP", rollButton, "BOTTOM", 0, -2)
rollOptionsFrame:SetWidth(110)  -- Width for two columns of 48px buttons + padding
rollOptionsFrame:SetHeight(100)  -- Will be adjusted based on content
rollOptionsFrame:Hide()
rollOptionsFrame:SetFrameLevel(rollButton:GetFrameLevel() - 1)

-- Add backdrop to popup
rollOptionsFrame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
})

-- Container for admin menu buttons, initially hidden
local adminOptionsFrame = CreateFrame("Frame", "AdminOptionsFrame", rollFrame)
adminOptionsFrame:SetPoint("TOP", rollButton, "BOTTOM", 0, -2)
adminOptionsFrame:SetWidth(140)
adminOptionsFrame:SetHeight(140)
adminOptionsFrame:Hide()
adminOptionsFrame:SetFrameLevel(rollButton:GetFrameLevel() - 1)

-- Tooltip text mapping for roll buttons
local rollButtonTooltips = {
    ["CSR"] = "Input weeks and roll SR",
    ["SR"] = "Roll SR with EP",
    ["EP"] = "Roll MS with EP",
    ["101"] = "Roll SR with no EP",
    ["100"] = "Roll MS with no EP",
    ["99"] = "For OS and Alts",
    ["Tmog"] = "Roll for Tmog",
    ["Standings"] = "Show standings"
}

-- Function to create compact roll button for two-column layout
local function CreateCompactRollButton(name, parent, command)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetWidth(48)
    button:SetHeight(22)
    button:SetText(name)
    -- Initial position at 0,0 - will be repositioned by RepositionRollButtons()
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    
    -- Set small font size
    pcall(function() 
        button:GetFontString():SetFont("Fonts\\FRIZQT__.TTF", 9) 
    end)
    
    button:SetScript("OnClick", function()
        ExecuteCommand(command)
        rollOptionsFrame:Hide()
    end)
    
    -- Add tooltip handlers
    if rollButtonTooltips[name] then
        button:SetScript("OnEnter", function()
            GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
            GameTooltip:SetText(rollButtonTooltips[name], 1, 1, 1)
            GameTooltip:Show()
        end)
        
        button:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end
    
    return button
end

-- Storage for button references for easy enable/disable
local rollPopupButtons = {}

-- Function to create admin button
local function CreateAdminButton(name, parent, command, anchor, width)
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
    
    button:SetScript("OnClick", function()
        ExecuteAdminCommand(command)
        adminOptionsFrame:Hide()
    end)

    return buttonFrame
end

-- Function to build admin menu options
local function BuildAdminOptions()
    local opts = {}
    table.insert(opts, { "Standings", "toggle_standings" })
    table.insert(opts, { "Buff Check", "buff_check" })
    table.insert(opts, { "Consumes Check", "consumes_check" })
    table.insert(opts, { "Flasks Check", "flasks_check" })
    table.insert(opts, { "Give EP to Raid", "give_ep_raid" })
    return opts
end

-- Create all roll popup buttons (positioning will be dynamic based on mode)
local col1X = 6  -- X offset for column 1
local col2X = 56 -- X offset for column 2 (6 + 48 + 2 padding)

-- Create all buttons we might need (initial position at 0,0, will be repositioned)
rollPopupButtons.CSR = CreateCompactRollButton("CSR", rollOptionsFrame, "roll csr")
rollPopupButtons.SR = CreateCompactRollButton("SR", rollOptionsFrame, "roll sr")
rollPopupButtons.EP = CreateCompactRollButton("EP", rollOptionsFrame, "roll ep")
rollPopupButtons["101"] = CreateCompactRollButton("101", rollOptionsFrame, "roll 101")
rollPopupButtons["100"] = CreateCompactRollButton("100", rollOptionsFrame, "roll 100")
rollPopupButtons["99"] = CreateCompactRollButton("99", rollOptionsFrame, "roll 99")
rollPopupButtons.Tmog = CreateCompactRollButton("Tmog", rollOptionsFrame, "roll tmog")
rollPopupButtons.Standings = CreateCompactRollButton("Standings", rollOptionsFrame, "show ep")

-- Function to reposition buttons based on current mode
local function RepositionRollButtons()
    local buttonSpacing = 24
    
    -- Col1 positioning (always the same)
    rollPopupButtons.CSR:SetPoint("TOPLEFT", rollOptionsFrame, "TOPLEFT", col1X, -6)
    rollPopupButtons.SR:SetPoint("TOPLEFT", rollOptionsFrame, "TOPLEFT", col1X, -6 - buttonSpacing)
    rollPopupButtons.EP:SetPoint("TOPLEFT", rollOptionsFrame, "TOPLEFT", col1X, -6 - buttonSpacing * 2)
    rollPopupButtons.Standings:SetPoint("TOPLEFT", rollOptionsFrame, "TOPLEFT", col1X, -6 - buttonSpacing * 3)
    
    -- Col2 positioning (always the same)
    rollPopupButtons["101"]:SetPoint("TOPLEFT", rollOptionsFrame, "TOPLEFT", col2X, -6)
    rollPopupButtons["100"]:SetPoint("TOPLEFT", rollOptionsFrame, "TOPLEFT", col2X, -6 - buttonSpacing)
    rollPopupButtons["99"]:SetPoint("TOPLEFT", rollOptionsFrame, "TOPLEFT", col2X, -6 - buttonSpacing * 2)
    rollPopupButtons.Tmog:SetPoint("TOPLEFT", rollOptionsFrame, "TOPLEFT", col2X, -6 - buttonSpacing * 3)
end

-- Call reposition on load
RepositionRollButtons()

-- ========================================================================
-- UPDATED FUNCTION: Show all 8 buttons always, but selectively disable them
-- ========================================================================
local function UpdateRollPopupVisibility()
    -- Reposition buttons first
    RepositionRollButtons()
    
    -- Get current state
    local enableRollButtons = GuildRoll_EnableRollButtons == true
    local isAlt = IsAlt()
    local hasCSRPerm = PlayerHasCSRPermission()
    
    -- ALWAYS SHOW all buttons
    rollPopupButtons.CSR:Show()
    rollPopupButtons.SR:Show()
    rollPopupButtons.EP:Show()
    rollPopupButtons["101"]:Show()
    rollPopupButtons["100"]:Show()
    rollPopupButtons["99"]:Show()
    rollPopupButtons.Tmog:Show()
    rollPopupButtons.Standings:Show()
    
    -- Now handle enabling/disabling
    if enableRollButtons then
        -- ADMIN OVERRIDE: Enable all buttons for everyone
        rollPopupButtons.CSR:Enable()
        rollPopupButtons.SR:Enable()
        rollPopupButtons.EP:Enable()
        rollPopupButtons["101"]:Enable()
        rollPopupButtons["100"]:Enable()
        rollPopupButtons["99"]:Enable()
        rollPopupButtons.Tmog:Enable()
        rollPopupButtons.Standings:Enable()
    else
        -- NORMAL MODE: Apply restrictions
        if isAlt then
            -- ALT: Only 99, Tmog, Standings enabled
            rollPopupButtons.CSR:Disable()
            rollPopupButtons.SR:Disable()
            rollPopupButtons.EP:Disable()
            rollPopupButtons["101"]:Disable()
            rollPopupButtons["100"]:Disable()
            rollPopupButtons["99"]:Enable()
            rollPopupButtons.Tmog:Enable()
            rollPopupButtons.Standings:Enable()
        else
            -- MAIN: All enabled except CSR depends on rank
            rollPopupButtons.SR:Enable()
            rollPopupButtons.EP:Enable()
            rollPopupButtons["101"]:Enable()
            rollPopupButtons["100"]:Enable()
            rollPopupButtons["99"]:Enable()
            rollPopupButtons.Tmog:Enable()
            rollPopupButtons.Standings:Enable()
            
            -- CSR: Enable/Disable based on rank threshold
            if hasCSRPerm then
                rollPopupButtons.CSR:Enable()
            else
                rollPopupButtons.CSR:Disable()
            end
        end
    end
end

-- Initial visibility update
UpdateRollPopupVisibility()

-- Create admin option buttons dynamically
local adminOptions = BuildAdminOptions()
local previousAdminButton = adminOptionsFrame
for _, option in ipairs(adminOptions) do
    local buttonFrame = CreateAdminButton(option[1], adminOptionsFrame, option[2], previousAdminButton, 110)
    
    if previousAdminButton == adminOptionsFrame then
        buttonFrame:SetPoint("TOP", adminOptionsFrame, "TOP", 0, 0)
    else
        buttonFrame:SetPoint("TOP", previousAdminButton, "BOTTOM", 0, 5)
    end
    previousAdminButton = buttonFrame
end

-- Toggle roll buttons on Roll button click
-- In WoW 1.12, OnClick uses global arg1 for the button type ("LeftButton" or "RightButton")
rollButton:SetScript("OnClick", function()
    if arg1 == "RightButton" then
        -- Right-click: hide both frames first, then show admin menu if admin, otherwise show normal menu
        rollOptionsFrame:Hide()
        adminOptionsFrame:Hide()
        
        -- Check if player is admin with defensive programming
        local isAdmin = false
        if GuildRoll and GuildRoll.IsAdmin then
            local ok, result = pcall(function() return GuildRoll:IsAdmin() end)
            isAdmin = ok and result
        end
        
        if isAdmin then
            adminOptionsFrame:Show()
        else
            -- Update visibility before showing
            UpdateRollPopupVisibility()
            rollOptionsFrame:Show()
        end
    elseif arg1 == "LeftButton" then
        -- Left-click: toggle normal menu, hide admin menu
        adminOptionsFrame:Hide()
        if rollOptionsFrame:IsShown() then
            rollOptionsFrame:Hide()
        else
            -- Update visibility before showing
            UpdateRollPopupVisibility()
            rollOptionsFrame:Show()
        end
    end
end)

-- Public function to rebuild roll options (called from menu when threshold or settings change)
function GuildRoll:RebuildRollOptions()
    -- Simply update visibility/enabled state of existing buttons
    UpdateRollPopupVisibility()
end

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

-- Restore saved position on load and handle visibility updates
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("GUILD_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("PLAYER_GUILD_UPDATE")

-- Event handler: update button visibility on relevant events
eventFrame:SetScript("OnEvent", function(self, event, ...)
    -- Update roll popup visibility on all relevant events
    UpdateRollPopupVisibility()
    
    -- Rebuild roll options to update CSR visibility
    if GuildRoll and GuildRoll.RebuildRollOptions then
        GuildRoll:RebuildRollOptions()
    end

    -- Restore saved position behavior (only on login)
    if event == "PLAYER_LOGIN" then
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
    end
end)
