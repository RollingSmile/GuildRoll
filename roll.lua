-- Ensure GuildRoll_RollPos is initialized with default values
GuildRoll_RollPos = GuildRoll_RollPos or { x = 400, y = 300 }
GuildRoll_showRollWindow = true

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
        if GuildRoll and GuildRoll.RollCommand then
            GuildRoll:RollCommand(false, false,false, 0)
        end
    elseif command == "ret os" then
        if GuildRoll and GuildRoll.RollCommand then
            GuildRoll:RollCommand(false, false,true, 0)
        end
    elseif command == "ret sr" then
        if GuildRoll and GuildRoll.RollCommand then
            GuildRoll:RollCommand(true, false,false, 0)
        end
    elseif command == "ret csr" then
        -- Use static popup dialog to input bonus
        StaticPopupDialogs["RET_CSR_INPUT"] = {
            text = "Enter number of weeks you SR this item:",
            button1 = TEXT(ACCEPT),
            button2 = TEXT(CANCEL),
            hasEditBox = 1,
            maxLetters = 5,
            OnAccept = function()
                local editBox = getglobal(this:GetParent():GetName().."EditBox")
                local number = tonumber(editBox:GetText())
                if number then
                    local bonus = GuildRoll:calculateBonus(number)
                    GuildRoll:RollCommand(true, false,false, bonus)
                else
                    print("Invalid number entered.")
                end
            end,
            OnShow = function()
                local editBox = getglobal(this:GetParent():GetName().."EditBox")
                getglobal(this:GetName().."EditBox"):SetText("")
                getglobal(this:GetName().."EditBox"):SetFocus()
            end,
            OnHide = function()
                if ChatFrameEditBox:IsVisible() then
                    ChatFrameEditBox:SetFocus()
                end
            end,
            EditBoxOnEnterPressed = function()
                local editBox = getglobal(this:GetParent():GetName().."EditBox")
                local number = tonumber(editBox:GetText())
                if number then
                    local bonus = GuildRoll:calculateBonus(number)
                    GuildRoll:RollCommand(true, false,false, bonus)
                else
                    print("Invalid number entered.")
                end
                this:GetParent():Hide()
            end,
            EditBoxOnEscapePressed = function()
                this:GetParent():Hide()
            end,
            timeout = 0,
            exclusive = 1,
            whileDead = 1,
            hideOnEscape = 1,
        }
        StaticPopup_Show("RET_CSR_INPUT")
    elseif command == "ret show" then
        GuildRoll_standings:Toggle()
    elseif command == "noice" then
        local noices ={ {"nice","SAY"},{"noice","SAY"},{"Nice !","YELL"},{"NOICE !","YELL"},{"NOIIICE","YELL"},{"NOYCE !","YELL"},{"niiice","SAY"},{"Errhm, noice","SAY"}}
        local noice = noices[math.random(1,table.getn(noices))]
        SendChatMessage(noice[1],noice[2])
        if noice[2] == "YELL" then DoEmote("cheer") end;
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
rollButton:SetText("The Buttoon")
rollButton:SetPoint("CENTER", rollFrame, "CENTER")

-- Container for roll buttons, initially hidden
local rollOptionsFrame = CreateFrame("Frame", "RollOptionsFrame", rollFrame)
rollOptionsFrame:SetPoint("TOP", rollButton, "BOTTOM", 0, -2)
rollOptionsFrame:SetWidth(70)
rollOptionsFrame:SetHeight(30)
rollOptionsFrame:Hide()

-- Function to create roll option buttons
local function CreateRollButton(name, parent, command, anchor,width, font)
    local buttonFrame = CreateFrame("Frame", nil, parent)
    buttonFrame:SetWidth(70)
    buttonFrame:SetHeight(30)
    buttonFrame:SetPoint("TOP", anchor, "BOTTOM", 0, -2)

    buttonFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 16,
        insets = { left = 5, right = 5, top = 5, bottom = 5 }
    })

    local button = CreateFrame("Button", nil, buttonFrame, "UIPanelButtonTemplate")
    button:SetWidth(width or 60)
    button:SetHeight(20)
    button:SetText(name)
    button:SetPoint("CENTER", buttonFrame, "CENTER")
    if font then
    button:SetFont("Fonts\\FRIZQT__.TTF", 8)
    end
    button:SetScript("OnClick", function()
        ExecuteCommand(command)
        -- Only hide if the command isn't "shooty show"
        if command ~= "shooty show" then
            rollOptionsFrame:Hide()
        end
    end)

    return buttonFrame
end

 
-- Roll option buttons configuration
local options = {
    { "MS", "ret ms" },
    { "OS", "ret os" },
    { "SR", "ret sr" },
    { "CSR", "ret csr" },
    { "Tmog", "roll 98" },
    { "101", "roll 101"},
    { "100", "roll 100" },
    { "Standings", "ret show" }
}

-- Create roll buttons dynamically with closer spacing
local previousButton = rollOptionsFrame
for _, option in ipairs(options) do
    local buttonFrame = CreateRollButton(option[1], rollOptionsFrame, option[2], previousButton,option[3] or 60,option[4] or false)

    if previousButton == rollOptionsFrame then
        -- For the first button, set it relative to the rollOptionsFrame
        buttonFrame:SetPoint("TOP", rollOptionsFrame, "TOP", 0, 0)  -- Align with the top of the options frame 
    else
        -- For subsequent buttons, set their position based on the previous button
        buttonFrame:SetPoint("TOP", previousButton, "BOTTOM", 0, 5)  -- Close spacing
    end
    previousButton = buttonFrame  -- Update previousButton to the current buttonFrame for the next iteration
end

-- Toggle roll buttons on Roll button click
rollButton:SetScript("OnClick", function()
    if rollOptionsFrame:IsShown() then
        rollOptionsFrame:Hide()
    else
        rollOptionsFrame:Show()
    end
end)

-- Fix for dragging functionality for the frame
rollFrame:SetScript("OnMouseDown", function(_, arg1)
    if arg1 == "LeftButton" then
        rollFrame:StartMoving()
    end
end)

rollFrame:SetScript("OnMouseUp", function(_, arg1)
    if arg1 == "LeftButton" then
        rollFrame:StopMovingOrSizing()
        GuildRoll_RollPos.x = rollFrame:GetLeft()
        GuildRoll_RollPos.y = rollFrame:GetTop()
    end
end)

rollFrame:SetScript("OnDragStart", function()
    rollFrame:StartMoving()
end)

rollFrame:SetScript("OnDragStop", function()
    rollFrame:StopMovingOrSizing()
    GuildRoll_RollPos.x = rollFrame:GetLeft()
    GuildRoll_RollPos.y = rollFrame:GetTop()
end)

-- Restore saved position on load
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function()
    if GuildRoll_RollPos.x and GuildRoll_RollPos.y then
        rollFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", GuildRoll_RollPos.x, GuildRoll_RollPos.y)
    else
        GuildRoll_RollPos = { x = 400, y = 300 }
        rollFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", GuildRoll_RollPos.x, GuildRoll_RollPos.y)
    end
    if not GuildRoll_showRollWindow then
        rollFrame:Hide()
    end
end)
