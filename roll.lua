-- Ensure GuildRoll_RollPos is initialized with default values
GuildRoll_RollPos = GuildRoll_RollPos or { x = 400, y = 300 }
GuildRoll_showRollWindow = GuildRoll_showRollWindow == nil and true or GuildRoll_showRollWindow
-- Initialize CSR threshold (default = 3, meaning rank index 0-3 can see CSR)
GuildRoll_CSRThreshold = GuildRoll_CSRThreshold or 3

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
    elseif command == "roll 98" then
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

-- Function to build dynamic roll options list
local function BuildRollOptions()
    local opts = {
        { "EP(MS)", "roll ep" },
        { "SR", "roll sr" },
    }
    
    -- Add CSR only if player has permission
    if PlayerHasCSRPermission() then
        table.insert(opts, { "CSR", "roll csr" })
    end
    
    -- Add numeric rolls and standings
    table.insert(opts, { "101", "roll 101" })
    table.insert(opts, { "100", "roll 100" })
    table.insert(opts, { "99", "roll 99" })
    table.insert(opts, { "98", "roll 98" })
    table.insert(opts, { "Standings", "show ep" })
    
    return opts
end

-- Build initial options list
local options = BuildRollOptions()

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

-- Public function to rebuild roll options (called from menu when threshold changes)
function GuildRoll:RebuildRollOptions()
    -- Clear existing option widgets
    if rollOptionsFrame then
        -- Avoid using global select() (some environment may have overwritten it).
        -- Collect children into a table, then index it directly.
        local children = { rollOptionsFrame:GetChildren() }
        -- Use table.getn for compatibility with older Lua versions used in some WoW clients
        local n = table.getn(children)
        for i = n, 1, -1 do
            local child = children[i]
            if child then
                child:Hide()
                child:SetParent(nil)
            end
        end
    end
    
    -- Rebuild options list
    local newOptions = BuildRollOptions()
    
    -- Recreate buttons
    local previousButton = rollOptionsFrame
    for _, opt in ipairs(newOptions) do
        local buttonFrame = CreateRollButton(opt[1], rollOptionsFrame, opt[2], previousButton, opt[3] or 110, opt[4] or false)
        if previousButton == rollOptionsFrame then
            buttonFrame:SetPoint("TOP", rollOptionsFrame, "TOP", 0, 0)
        else
            buttonFrame:SetPoint("TOP", previousButton, "BOTTOM", 0, 5)
        end
        previousButton = buttonFrame
    end
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

-- Restore saved position on load
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("GUILD_ROSTER_UPDATE")

-- Event handler: rebuild options when player logs in or guild roster updates
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event ~= "GUILD_ROSTER_UPDATE" and event ~= "PLAYER_LOGIN" then
        return
    end
    
    -- Rebuild roll options to update CSR visibility
    if GuildRoll and GuildRoll.RebuildRollOptions then
        GuildRoll:RebuildRollOptions()
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
