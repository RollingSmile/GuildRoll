-- MasterLootWarning.lua
-- Optional: Creates on-screen warning if not master looter in raids

local MasterLootWarning = {}
MasterLootWarning.__index = MasterLootWarning

-- Constructor
function MasterLootWarning.new()
    local self = setmetatable({}, MasterLootWarning)
    self.warning_frame = nil
    self.check_timer = nil
    return self
end

-- Check if in raid and not master looter
function MasterLootWarning:should_show_warning()
    -- Only show warning in raids
    if GetNumRaidMembers() == 0 then
        return false
    end
    
    -- Check loot method
    local loot_method, master_party, master_raid = GetLootMethod()
    if loot_method == "master" then
        -- Check if we're the master looter
        local player_name = UnitName("player")
        
        -- In 1.12, master_raid is the raid index
        if master_raid then
            local master = GetMasterLootCandidate(master_raid)
            if master == player_name then
                return false  -- We are the master looter
            end
        end
        
        -- Not the master looter
        return true
    end
    
    return false
end

-- Create warning frame
function MasterLootWarning:create_warning_frame()
    if self.warning_frame then
        return self.warning_frame
    end
    
    local frame = CreateFrame("Frame", "MasterLootWarningFrame", UIParent)
    frame:SetWidth(300)
    frame:SetHeight(60)
    frame:SetPoint("TOP", UIParent, "TOP", 0, -100)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    frame:SetBackdropColor(1, 0, 0, 0.8)
    frame:SetFrameStrata("HIGH")
    
    -- Warning text
    local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    text:SetPoint("CENTER")
    text:SetText("Not Master Looter!")
    text:SetTextColor(1, 1, 0)
    
    -- Close button
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function()
        self:hide_warning()
    end)
    
    frame:Hide()
    self.warning_frame = frame
    
    return frame
end

-- Show warning
function MasterLootWarning:show_warning()
    local frame = self:create_warning_frame()
    frame:Show()
end

-- Hide warning
function MasterLootWarning:hide_warning()
    if self.warning_frame then
        self.warning_frame:Hide()
    end
end

-- Start checking (on a timer)
function MasterLootWarning:start_checking()
    if self.check_timer then
        return
    end
    
    -- Check every 5 seconds
    self.check_timer = CreateFrame("Frame")
    self.check_timer.elapsed = 0
    self.check_timer:SetScript("OnUpdate", function()
        this.elapsed = this.elapsed + arg1
        if this.elapsed >= 5 then
            this.elapsed = 0
            
            if self:should_show_warning() then
                self:show_warning()
            else
                self:hide_warning()
            end
        end
    end)
end

-- Stop checking
function MasterLootWarning:stop_checking()
    if self.check_timer then
        self.check_timer:SetScript("OnUpdate", nil)
        self.check_timer = nil
    end
    self:hide_warning()
end

-- Export to global namespace
_G.MasterLootWarning = MasterLootWarning
if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("[DEBUG] MasterLootWarning exported to _G")
end
return MasterLootWarning
