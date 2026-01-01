-- MasterLootFrame.lua
-- UI for displaying loot candidates and handling selections
-- Creates, anchors and shows candidate UI
-- Provides hook_loot_buttons/restore_loot_buttons

local MasterLootFrame = {}
MasterLootFrame.__index = MasterLootFrame

-- Constructor
function MasterLootFrame.new()
    local self = setmetatable({}, MasterLootFrame)
    self.frames = {}  -- slot -> frame mapping
    self.hooked = false
    self.original_click_handlers = {}
    return self
end

-- Hook loot buttons to show candidate selection
function MasterLootFrame:hook_loot_buttons()
    if self.hooked then return end
    
    -- Hook LootButton click handlers
    for i = 1, LOOTFRAME_NUMBUTTONS or 4 do
        local button = _G["LootButton" .. i]
        if button then
            -- Store original handler
            self.original_click_handlers[i] = button:GetScript("OnClick")
            
            -- Set new handler
            button:SetScript("OnClick", function()
                self:on_loot_button_click(this, arg1)
            end)
        end
    end
    
    self.hooked = true
end

-- Restore original loot button handlers
function MasterLootFrame:restore_loot_buttons()
    if not self.hooked then return end
    
    for i = 1, LOOTFRAME_NUMBUTTONS or 4 do
        local button = _G["LootButton" .. i]
        if button and self.original_click_handlers[i] then
            button:SetScript("OnClick", self.original_click_handlers[i])
        end
    end
    
    self.hooked = false
    self.original_click_handlers = {}
end

-- Handle loot button click
function MasterLootFrame:on_loot_button_click(button, mouse_button)
    if not button then return end
    
    -- Get slot from button
    local slot = button:GetID()
    if not slot then return end
    
    -- Check if shift-click (master loot)
    if IsShiftKeyDown() and mouse_button == "LeftButton" then
        -- Show candidate selection
        self:show_candidate_selection(slot, button)
    else
        -- Call original handler if exists
        local original = self.original_click_handlers[button:GetID()]
        if original then
            original()
        end
    end
end

-- Show candidate selection for a slot
function MasterLootFrame:show_candidate_selection(slot, anchor_frame)
    if not slot then return end
    
    -- Hide any existing candidate frame
    self:hide_candidate_selection()
    
    -- Get candidates
    local num_candidates = 0
    for i = 1, 40 do
        if GetMasterLootCandidate(i) then
            num_candidates = num_candidates + 1
        else
            break
        end
    end
    
    if num_candidates == 0 then
        return
    end
    
    -- Create candidate frame
    local frame = CreateFrame("Frame", "MasterLootCandidateFrame", UIParent)
    frame:SetWidth(200)
    frame:SetHeight(math.min(num_candidates * 20 + 10, 400))
    frame:SetPoint("LEFT", anchor_frame, "RIGHT", 5, 0)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    frame:SetFrameStrata("DIALOG")
    
    -- Create scroll frame for candidates
    local scroll = CreateFrame("ScrollFrame", "MasterLootCandidateScroll", frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", -28, 8)
    
    -- Create candidate buttons
    local content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(180)
    content:SetHeight(num_candidates * 20)
    scroll:SetScrollChild(content)
    
    local y_offset = 0
    for i = 1, num_candidates do
        local candidate_name = GetMasterLootCandidate(i)
        if candidate_name then
            local btn = CreateFrame("Button", nil, content)
            btn:SetWidth(180)
            btn:SetHeight(18)
            btn:SetPoint("TOPLEFT", 0, -y_offset)
            btn:SetNormalFontObject("GameFontNormal")
            btn:SetText(candidate_name)
            
            -- Button background
            local bg = btn:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetTexture(0.2, 0.2, 0.2, 0.8)
            
            -- Highlight
            local hl = btn:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetTexture(0.4, 0.4, 0.4, 0.8)
            
            -- Click handler
            btn:SetScript("OnClick", function()
                self:give_loot_to_candidate(slot, i)
                self:hide_candidate_selection()
            end)
            
            y_offset = y_offset + 20
        end
    end
    
    -- Store frame
    self.frames[slot] = frame
    frame:Show()
end

-- Hide candidate selection
function MasterLootFrame:hide_candidate_selection()
    for slot, frame in pairs(self.frames) do
        if frame then
            frame:Hide()
        end
    end
    self.frames = {}
end

-- Give loot to candidate
function MasterLootFrame:give_loot_to_candidate(slot, candidate_index)
    if not slot or not candidate_index then return end
    
    -- Call GiveMasterLoot
    GiveMasterLoot(slot, candidate_index)
    
    -- Notify (optional callback)
    if self.on_loot_given then
        local candidate_name = GetMasterLootCandidate(candidate_index)
        self.on_loot_given(slot, candidate_index, candidate_name)
    end
end

-- Set callback for when loot is given
function MasterLootFrame:set_on_loot_given(callback)
    self.on_loot_given = callback
end

-- Show the frame
function MasterLootFrame:show()
    self:hook_loot_buttons()
end

-- Hide the frame
function MasterLootFrame:hide()
    self:hide_candidate_selection()
    self:restore_loot_buttons()
end

_G.MasterLootFrame = MasterLootFrame
return MasterLootFrame
