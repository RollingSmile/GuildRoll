-- =============================================================================
-- LOOTSYSTEM.LUA - Consolidated Master Loot System for GuildRoll
-- =============================================================================
-- This file contains all lootsystem modules in a single file to ensure
-- reliable loading in WoW addon system.
-- =============================================================================

if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("[LOOTSYSTEM] lootsystem.lua is loading...")
end

-- =============================================================================
-- RollParser Module for GuildRoll
-- Parses RollFor-style loot submissions and system roll messages
-- Supports CSR/SR/MS roll types with EP integration
-- =============================================================================

-- Module state
GuildRoll_RollParser = {
    -- Track active loot submissions by player name for fast lookup
    activeSubmissions = {},
    -- Track recent rolls
    recentRolls = {},
    -- Settings
    timeout = 300, -- 5 minutes timeout for loot tracking
    maxRolls = 50, -- Maximum number of rolls to track
}

local RollParser = GuildRoll_RollParser

-- Valid roll types (constant)
local VALID_ROLL_TYPES = {
    MS = true,
    SR = true,
    CSR = true,
    MAINSPEC = true,
    SECONDARYSPEC = true,
    OFFSPEC = true,
    OS = true,
}

-- Roll type mapping
local ROLL_TYPE_MAP = {
    MAINSPEC = "MS",
    SECONDARYSPEC = "SR",
    OFFSPEC = "OS",
}

-- Debug helper
local function debugPrint(msg)
    if GuildRoll and GuildRoll.DEBUG and GuildRoll.debugPrint then
        GuildRoll:debugPrint("RollParser: " .. tostring(msg))
    end
end

-- Parse [RL] submission line
-- Expected format: "[RL] PlayerName: [ItemLink] - RollType"
-- RollType can be: MS, SR, CSR, or variants
function RollParser:ParseSubmission(message, sender)
    if not message then return nil end
    
    -- Check for [RL] prefix
    if not string.find(message, "^%[RL%]") then
        return nil
    end
    
    debugPrint("Found [RL] message: " .. message)
    
    -- Parse the submission
    -- Pattern: [RL] PlayerName: ItemInfo - RollType
    local _, _, playerName, itemInfo, rollType = string.find(message, "%[RL%]%s*([^:]+):%s*(.-)%s*%-%s*(%w+)%s*$")
    
    if not playerName or not itemInfo or not rollType then
        -- Try alternative pattern without item info: [RL] PlayerName: RollType
        _, _, playerName, rollType = string.find(message, "%[RL%]%s*([^:]+):%s*(%w+)%s*$")
        itemInfo = ""
    end
    
    if not playerName or not rollType then
        debugPrint("Failed to parse submission: " .. message)
        return nil
    end
    
    -- Clean up player name
    playerName = string.gsub(playerName, "^%s+", "")
    playerName = string.gsub(playerName, "%s+$", "")
    
    -- Normalize roll type
    rollType = string.upper(rollType)
    
    -- Validate roll type before proceeding
    if not VALID_ROLL_TYPES[rollType] then
        debugPrint("Invalid roll type: " .. rollType .. " from message: " .. message)
        return nil
    end
    
    -- Map alternative names to standard types
    if ROLL_TYPE_MAP[rollType] then
        rollType = ROLL_TYPE_MAP[rollType]
    end
    
    local submission = {
        player = playerName,
        itemInfo = itemInfo,
        rollType = rollType,
        timestamp = time(),
        sender = sender,
    }
    
    debugPrint(string.format("Parsed submission: %s - %s (%s)", playerName, rollType, itemInfo))
    
    return submission
end

-- Parse system roll message
-- Expected format: "PlayerName rolls 75 (1-100)" - WoW 1.12 format
function RollParser:ParseRoll(message)
    if not message then return nil end
    
    -- Pattern: PlayerName rolls result (min-max)
    local _, _, playerName, result, minRoll, maxRoll = string.find(message, "^(.+) rolls (%d+) %((%d+)%-(%d+)%)%.?$")
    
    if not playerName or not minRoll or not maxRoll or not result then
        return nil
    end
    
    -- Clean up player name (remove server name if present)
    playerName = string.gsub(playerName, "%-[^%-]+$", "")
    
    minRoll = tonumber(minRoll)
    maxRoll = tonumber(maxRoll)
    result = tonumber(result)
    
    if not minRoll or not maxRoll or not result then
        return nil
    end
    
    local roll = {
        player = playerName,
        min = minRoll,
        max = maxRoll,
        result = result,
        timestamp = time(),
    }
    
    debugPrint(string.format("Parsed roll: %s rolled %d-%d (%d)", playerName, minRoll, maxRoll, result))
    
    return roll
end

-- Determine EP from roll range
-- MS: 1+EP to 100+EP (range of 99)
-- SR/CSR: 101+EP+bonus to 200+EP+bonus (range of 99)
-- Note: CSR is SR with a cumulative bonus, but we can't distinguish them
-- from the roll range alone without knowing the player's exact EP.
function RollParser:DetermineEPFromRoll(roll)
    if not roll then return nil, nil end
    
    local min = roll.min
    local max = roll.max
    
    -- Calculate EP and roll type
    local ep = 0
    local rollType = nil
    
    -- Check the range to determine type
    local rangeSize = max - min
    
    -- Standard fixed rolls (no EP)
    if min == 1 and max == 100 then
        ep = 0
        rollType = "Standard"
    elseif min == 1 and max == 99 then
        ep = 0
        rollType = "OS"
    elseif min == 1 and max == 98 then
        ep = 0
        rollType = "Transmog"
    -- EP-aware rolls: Standard range is 99 (e.g., 1-100 MS, 101-200 SR)
    -- Accept range of 99-100 to handle CSR cumulative bonuses which may extend range
    elseif rangeSize >= 99 and rangeSize <= 100 then
        if min >= 101 then
            -- SR/CSR range: 101+EP to 200+EP (or higher with cumulative bonuses)
            rollType = "SR"
            ep = min - 101
        elseif min >= 1 and max <= 100 then
            -- MS range: 1+EP to 100+EP (max must be <= 100 to distinguish from SR)
            rollType = "MS"
            ep = min - 1
        else
            rollType = "Unknown"
        end
    else
        -- Unknown roll type or invalid range
        rollType = "Unknown"
    end
    
    return ep, rollType
end

-- Associate a roll with a submission
function RollParser:AssociateRollWithSubmission(roll)
    if not roll then return nil end
    
    -- Find matching submission for this player using hash table lookup
    local playerName = roll.player
    local matchingSubmission = self.activeSubmissions[playerName]
    
    if matchingSubmission then
        -- Check if submission is not too old
        if (time() - matchingSubmission.timestamp) <= self.timeout then
            debugPrint(string.format("Associated roll from %s with submission (%s)", playerName, matchingSubmission.rollType))
            
            -- Determine EP from roll
            local ep, detectedRollType = self:DetermineEPFromRoll(roll)
            
            return {
                player = playerName,
                rollType = matchingSubmission.rollType,
                itemInfo = matchingSubmission.itemInfo,
                rollResult = roll.result,
                rollMin = roll.min,
                rollMax = roll.max,
                ep = ep,
                detectedRollType = detectedRollType,
                timestamp = time(),
            }
        else
            -- Submission is too old, clean it up
            self.activeSubmissions[playerName] = nil
        end
    end
    
    return nil
end

-- Add a submission to tracking
function RollParser:AddSubmission(submission)
    if not submission then return end
    
    -- Add/update submission in hash table keyed by player name
    self.activeSubmissions[submission.player] = submission
    debugPrint(string.format("Added submission for %s (%s)", submission.player, submission.rollType))
end

-- Add a roll to tracking
function RollParser:AddRoll(roll)
    if not roll then return end
    
    -- Keep only recent rolls
    if table.getn(self.recentRolls) >= self.maxRolls then
        table.remove(self.recentRolls, 1)
    end
    
    table.insert(self.recentRolls, roll)
end

-- Handle a chat message
function RollParser:HandleChatMessage(message, sender, msgType)
    if not message then return end
    
    -- Periodically clean up old data (every 500 messages to reduce overhead)
    if not self.messageCount then self.messageCount = 0 end
    self.messageCount = self.messageCount + 1
    if self.messageCount >= 500 then
        self:Cleanup()
        self.messageCount = 0
    end
    
    -- Try to parse as submission first
    local submission = self:ParseSubmission(message, sender)
    if submission then
        self:AddSubmission(submission)
        return
    end
    
    -- Try to parse as roll
    local roll = self:ParseRoll(message)
    if roll then
        self:AddRoll(roll)
        
        -- Try to associate with submission
        local associated = self:AssociateRollWithSubmission(roll)
        if associated then
            -- Trigger event or callback for associated roll
            if GuildRoll and GuildRoll.OnLootRoll then
                GuildRoll:OnLootRoll(associated)
            end
        end
        
        return
    end
end

-- Clean up old data
function RollParser:Cleanup()
    local currentTime = time()
    
    -- Clean up old submissions from hash table
    for playerName, submission in pairs(self.activeSubmissions) do
        if (currentTime - submission.timestamp) > self.timeout then
            self.activeSubmissions[playerName] = nil
        end
    end
    
    -- Clean up old rolls
    if table.getn(self.recentRolls) > self.maxRolls then
        while table.getn(self.recentRolls) > self.maxRolls do
            table.remove(self.recentRolls, 1)
        end
    end
end

-- Initialize the parser
function RollParser:Initialize()
    debugPrint("RollParser initialized")
    
    -- Note: Periodic cleanup could be added here using a timer system
    -- For now, cleanup is called manually when needed
end

-- Export functions to GuildRoll namespace
if GuildRoll then
    GuildRoll.RollParser = RollParser
end

_G.GuildRoll_RollParser = GuildRoll_RollParser
if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("[lootsystem] RollParser loaded")
end
-- Module continues - do not return here

-- =============================================================================
-- MasterLootTracker.lua
-- Tracks slot -> item mapping for master loot
-- Stores item.id, name, link, quality for each loot slot
-- =============================================================================

if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("[DEBUG] MasterLootTracker.lua is loading...")
end

local MasterLootTracker = {}
MasterLootTracker.__index = MasterLootTracker

-- Constructor
function MasterLootTracker.new()
    local self = setmetatable({}, MasterLootTracker)
    self.slots = {}  -- slot -> item mapping
    return self
end

-- Add an item to a slot
-- slot: loot slot index (1-based)
-- item: table with { id, name, link, quality }
function MasterLootTracker:add(slot, item)
    if not slot or not item then return end
    
    self.slots[slot] = {
        id = item.id,
        name = item.name,
        link = item.link,
        quality = item.quality
    }
end

-- Get item for a slot
-- Returns: item table or nil
function MasterLootTracker:get(slot)
    return self.slots[slot]
end

-- Clear a specific slot
function MasterLootTracker:clear_slot(slot)
    self.slots[slot] = nil
end

-- Clear all slots
function MasterLootTracker:clear_all()
    self.slots = {}
end

-- Get all slots
function MasterLootTracker:get_all()
    return self.slots
end

-- Check if a slot exists
function MasterLootTracker:has_slot(slot)
    return self.slots[slot] ~= nil
end

-- Export to global namespace
_G.MasterLootTracker = MasterLootTracker
if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("[DEBUG] MasterLootTracker exported to _G")
end
-- Module continues - do not return here

-- =============================================================================
-- DroppedLoot.lua
-- Persists dropped items across sessions
-- Uses GuildRoll saved variables
-- =============================================================================

local DroppedLoot = {}
DroppedLoot.__index = DroppedLoot

-- Constructor
function DroppedLoot.new()
    local self = setmetatable({}, DroppedLoot)
    
    -- Initialize saved variable if needed
    if not GuildRoll_DroppedLoot then
        GuildRoll_DroppedLoot = {}
    end
    
    self.items = GuildRoll_DroppedLoot
    return self
end

-- Add a dropped item
-- item: table with { id, name, link, quality, timestamp }
function DroppedLoot:add(item)
    if not item or not item.id then return end
    
    item.timestamp = item.timestamp or time()
    
    table.insert(self.items, {
        id = item.id,
        name = item.name,
        link = item.link,
        quality = item.quality,
        timestamp = item.timestamp
    })
end

-- Get all dropped items
function DroppedLoot:get_all()
    return self.items
end

-- Get dropped items from the last N seconds
-- seconds: time window (default 3600 = 1 hour)
function DroppedLoot:get_recent(seconds)
    seconds = seconds or 3600
    local now = time()
    local recent = {}
    
    for _, item in ipairs(self.items) do
        if (now - item.timestamp) < seconds then
            table.insert(recent, item)
        end
    end
    
    return recent
end

-- Clear old items (older than N seconds)
-- seconds: age threshold (default 7200 = 2 hours)
function DroppedLoot:clear_old(seconds)
    seconds = seconds or 7200
    local now = time()
    local new_items = {}
    
    for _, item in ipairs(self.items) do
        if (now - item.timestamp) < seconds then
            table.insert(new_items, item)
        end
    end
    
    self.items = new_items
    GuildRoll_DroppedLoot = new_items
end

-- Clear all dropped items
function DroppedLoot:clear_all()
    self.items = {}
    GuildRoll_DroppedLoot = {}
end

-- Persist current state (saves to saved variables)
function DroppedLoot:persist()
    GuildRoll_DroppedLoot = self.items
end

-- Export to global namespace
_G.DroppedLoot = DroppedLoot
if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("[DEBUG] DroppedLoot exported to _G")
end
-- Module continues - do not return here

-- =============================================================================
-- AwardedLoot.lua
-- Tracks awarded items to avoid double-awarding
-- Persists to saved variables

local AwardedLoot = {}
AwardedLoot.__index = AwardedLoot

-- Constructor
function AwardedLoot.new()
    local self = setmetatable({}, AwardedLoot)
    
    -- Initialize saved variable if needed
    if not GuildRoll_AwardedLoot then
        GuildRoll_AwardedLoot = {}
    end
    
    self.awarded = GuildRoll_AwardedLoot
    return self
end

-- Add an awarded item
-- item_id: item ID
-- player: player name
-- timestamp: optional timestamp (defaults to current time)
function AwardedLoot:add(item_id, player, timestamp)
    if not item_id or not player then return end
    
    timestamp = timestamp or time()
    
    table.insert(self.awarded, {
        item_id = item_id,
        player = player,
        timestamp = timestamp
    })
end

-- Check if an item was recently awarded (within last N seconds)
-- item_id: item ID
-- seconds: time window (default 60)
-- Returns: true if awarded recently, false otherwise
function AwardedLoot:was_recently_awarded(item_id, seconds)
    if not item_id then return false end
    
    seconds = seconds or 60
    local now = time()
    
    for _, award in ipairs(self.awarded) do
        if award.item_id == item_id and (now - award.timestamp) < seconds then
            return true
        end
    end
    
    return false
end

-- Clear old awards (older than N seconds)
-- seconds: age threshold (default 3600 = 1 hour)
function AwardedLoot:clear_old(seconds)
    seconds = seconds or 3600
    local now = time()
    local new_awarded = {}
    
    for _, award in ipairs(self.awarded) do
        if (now - award.timestamp) < seconds then
            table.insert(new_awarded, award)
        end
    end
    
    self.awarded = new_awarded
    GuildRoll_AwardedLoot = new_awarded
end

-- Clear all awarded items
function AwardedLoot:clear_all()
    self.awarded = {}
    GuildRoll_AwardedLoot = {}
end

-- Get all awarded items
function AwardedLoot:get_all()
    return self.awarded
end

-- Export to global namespace
_G.AwardedLoot = AwardedLoot
if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("[DEBUG] AwardedLoot exported to _G")
end
-- Module continues - do not return here

-- =============================================================================
-- DroppedLootAnnounce.lua
-- Scans loot on LOOT_OPENED and populates MasterLootTracker
-- Filters by loot threshold and announces items

local DroppedLootAnnounce = {}
DroppedLootAnnounce.__index = DroppedLootAnnounce

-- Quality color codes
local QUALITY_COLORS = {
    [0] = "|cff9d9d9d",  -- Poor (gray)
    [1] = "|cffffffff",  -- Common (white)
    [2] = "|cff1eff00",  -- Uncommon (green)
    [3] = "|cff0070dd",  -- Rare (blue)
    [4] = "|cffa335ee",  -- Epic (purple)
    [5] = "|cffff8000",  -- Legendary (orange)
}

-- Constructor
-- master_loot_tracker: MasterLootTracker instance
-- dropped_loot: DroppedLoot instance
function DroppedLootAnnounce.new(master_loot_tracker, dropped_loot)
    local self = setmetatable({}, DroppedLootAnnounce)
    self.tracker = master_loot_tracker
    self.dropped_loot = dropped_loot
    return self
end

-- Parse item ID from item link
-- Example: "|cff9d9d9d|Hitem:7073:0:0:0|h[Broken Fang]|h|r"
local function parse_item_id(link)
    if not link then return nil end
    
    local _, _, item_id = string.find(link, "item:(%d+)")
    return tonumber(item_id)
end

-- Get loot threshold
local function get_loot_threshold()
    local threshold = GetLootThreshold()
    if not threshold then
        return 2  -- Default to Uncommon
    end
    return threshold
end

-- Check if item quality meets threshold
local function meets_threshold(quality, threshold)
    return quality >= threshold
end

-- On LOOT_OPENED event
-- Scans all loot slots and populates tracker
function DroppedLootAnnounce:on_loot_opened()
    -- Check if we're the master looter
    local loot_method, master_party, master_raid = GetLootMethod()
    if loot_method ~= "master" then
        return  -- Not master loot
    end
    
    -- Clear tracker
    self.tracker:clear_all()
    
    local num_items = GetNumLootItems()
    if not num_items or num_items == 0 then
        return
    end
    
    local threshold = get_loot_threshold()
    local announcements = {}
    
    for slot = 1, num_items do
        local link = GetLootSlotLink(slot)
        local icon, name, quantity, quality = GetLootSlotInfo(slot)
        
        if link and name and quality then
            -- Parse item ID
            local item_id = parse_item_id(link)
            
            -- Check if meets threshold
            if meets_threshold(quality, threshold) then
                -- Add to tracker
                self.tracker:add(slot, {
                    id = item_id,
                    name = name,
                    link = link,
                    quality = quality
                })
                
                -- Add to dropped loot history
                if self.dropped_loot and item_id then
                    self.dropped_loot:add({
                        id = item_id,
                        name = name,
                        link = link,
                        quality = quality
                    })
                end
                
                -- Build announcement
                local color = QUALITY_COLORS[quality] or "|cffffffff"
                table.insert(announcements, string.format("%s%s|r", color, link))
            end
        end
    end
    
    -- Announce items (if any)
    if table.getn(announcements) > 0 then
        self:announce_items(announcements)
    end
end

-- Announce items to raid/party
function DroppedLootAnnounce:announce_items(announcements)
    if not announcements or table.getn(announcements) == 0 then
        return
    end
    
    -- Determine channel (RAID or PARTY)
    local channel = "SAY"
    if GetNumRaidMembers() > 0 then
        channel = "RAID"
    elseif GetNumPartyMembers() > 0 then
        channel = "PARTY"
    end
    
    -- Send announcement
    local msg = "Loot: " .. table.concat(announcements, ", ")
    
    -- Split if too long (255 char limit)
    if string.len(msg) > 250 then
        msg = string.sub(msg, 1, 247) .. "..."
    end
    
    SendChatMessage(msg, channel)
end

-- Export to global namespace
_G.DroppedLootAnnounce = DroppedLootAnnounce
if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("[DEBUG] DroppedLootAnnounce exported to _G")
end
-- Module continues - do not return here

-- =============================================================================
-- MasterLootFrame.lua
-- Custom Loot UI with Roll System
-- Replaces Blizzard LootFrame with custom interface
-- Supports roll sessions with SR/MS/OS/Tmog priority ranking

local MasterLootFrame = {}
MasterLootFrame.__index = MasterLootFrame

-- Roll type priorities (lower = higher priority)
local ROLL_PRIORITIES = {
    SR = 1,   -- Soft Reserve: CSR, SR, 101
    MS = 2,   -- Main Spec: EP, 100
    OS = 3,   -- Off Spec: 99
    Tmog = 4, -- Transmog: 98
}

-- Determine roll type from roll value
local function get_roll_type(roll_value)
    if roll_value == 101 then
        return "SR"
    elseif roll_value == 100 then
        return "MS"
    elseif roll_value == 99 then
        return "OS"
    elseif roll_value == 98 then
        return "Tmog"
    elseif roll_value >= 101 then
        return "SR" -- CSR or SR with EP
    elseif roll_value >= 1 and roll_value <= 100 then
        -- Could be MS with EP, default to MS
        return "MS"
    end
    return "MS" -- Default
end

-- Constructor
function MasterLootFrame.new()
    local self = setmetatable({}, MasterLootFrame)
    self.mainFrame = nil
    self.itemButtons = {}
    self.activeRollSession = nil -- {slot, itemLink, rolls={}}
    self.rankingFrame = nil
    self.isShown = false
    return self
end

-- Create the custom loot frame
function MasterLootFrame:create_loot_frame()
    if self.mainFrame then
        return self.mainFrame
    end
    
    -- Main frame
    local frame = CreateFrame("Frame", "GuildRoll_CustomLootFrame", UIParent)
    frame:SetWidth(300)
    frame:SetHeight(400)
    frame:SetPoint("CENTER", UIParent, "CENTER", -200, 0)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() frame:StartMoving() end)
    frame:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    frame:Hide()
    
    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("Master Loot")
    frame.title = title
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)
    closeBtn:SetScript("OnClick", function()
        self:hide()
    end)
    
    -- Scroll frame for items
    local scrollFrame = CreateFrame("ScrollFrame", "GuildRoll_LootScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 20, -50)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 20)
    frame.scrollFrame = scrollFrame
    
    -- Content frame for items
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(250)
    content:SetHeight(1) -- Will resize based on items
    scrollFrame:SetScrollChild(content)
    frame.content = content
    
    self.mainFrame = frame
    return frame
end

-- Populate loot items
function MasterLootFrame:populate_loot_items()
    if not self.mainFrame then return end
    
    local content = self.mainFrame.content
    
    -- Clear existing buttons
    for _, btn in ipairs(self.itemButtons) do
        btn:Hide()
        btn:SetParent(nil)
    end
    self.itemButtons = {}
    
    -- Get number of loot items
    local numItems = GetNumLootItems()
    
    if numItems == 0 then
        return
    end
    
    -- Create item buttons
    local yOffset = 0
    for slot = 1, numItems do
        local itemLink = GetLootSlotLink(slot)
        local icon, name, quantity, quality = GetLootSlotInfo(slot)
        
        if itemLink and name then
            local btn = self:create_item_button(content, slot, itemLink, icon, name, quantity, quality)
            btn:SetPoint("TOPLEFT", 0, -yOffset)
            table.insert(self.itemButtons, btn)
            yOffset = yOffset + 45
        end
    end
    
    -- Resize content
    content:SetHeight(math.max(yOffset, 1))
end

-- Create an item button
function MasterLootFrame:create_item_button(parent, slot, itemLink, icon, name, quantity, quality)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetWidth(240)
    btn:SetHeight(40)
    -- Note: SetNormalFontObject doesn't exist in WoW 1.12
    -- Font is set on the FontString below
    
    -- Background
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(0.1, 0.1, 0.1, 0.8)
    
    -- Icon
    local iconTex = btn:CreateTexture(nil, "ARTWORK")
    iconTex:SetWidth(32)
    iconTex:SetHeight(32)
    iconTex:SetPoint("LEFT", 4, 0)
    iconTex:SetTexture(icon)
    
    -- Item name
    local nameText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameText:SetPoint("LEFT", iconTex, "RIGHT", 5, 0)
    nameText:SetPoint("RIGHT", -5, 0)
    nameText:SetJustifyH("LEFT")
    nameText:SetText(name .. (quantity > 1 and (" x" .. quantity) or ""))
    
    -- Set color based on quality
    if quality then
        local r, g, b = GetItemQualityColor(quality)
        nameText:SetTextColor(r, g, b)
    end
    
    -- Highlight
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture(0.3, 0.3, 0.3, 0.5)
    
    -- Click handler
    btn:SetScript("OnClick", function()
        self:show_item_menu(slot, itemLink, btn)
    end)
    
    btn.slot = slot
    btn.itemLink = itemLink
    
    return btn
end

-- Show item context menu
function MasterLootFrame:show_item_menu(slot, itemLink, anchorFrame)
    -- Create menu frame if needed
    if not self.menuFrame then
        local menu = CreateFrame("Frame", "GuildRoll_ItemMenu", UIParent)
        menu:SetWidth(120)
        menu:SetHeight(60)
        menu:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:Hide()
        
        -- Start Rolls button
        local startBtn = CreateFrame("Button", nil, menu)
        startBtn:SetWidth(100)
        startBtn:SetHeight(25)
        startBtn:SetPoint("TOP", 0, -10)
        
        -- Create text on button (SetText doesn't work in WoW 1.12)
        local startText = startBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        startText:SetPoint("CENTER", startBtn, "CENTER", 0, 0)
        startText:SetText("Start Rolls")
        
        local startBg = startBtn:CreateTexture(nil, "BACKGROUND")
        startBg:SetAllPoints()
        startBg:SetTexture(0.2, 0.6, 0.2, 0.8)
        
        local startHl = startBtn:CreateTexture(nil, "HIGHLIGHT")
        startHl:SetAllPoints()
        startHl:SetTexture(0.3, 0.8, 0.3, 0.8)
        
        startBtn:SetScript("OnClick", function()
            menu:Hide()
            self:start_roll_session(menu.currentSlot, menu.currentItemLink)
        end)
        
        menu.startBtn = startBtn
        self.menuFrame = menu
    end
    
    local menu = self.menuFrame
    menu.currentSlot = slot
    menu.currentItemLink = itemLink
    
    -- Position menu
    menu:ClearAllPoints()
    menu:SetPoint("LEFT", anchorFrame, "RIGHT", 5, 0)
    menu:Show()
    
    -- Hide menu after delay or on next click
    menu:SetScript("OnUpdate", function()
        if not MouseIsOver(menu) and not MouseIsOver(anchorFrame) then
            menu:Hide()
            menu:SetScript("OnUpdate", nil)
        end
    end)
end

-- Start a roll session
function MasterLootFrame:start_roll_session(slot, itemLink)
    DEFAULT_CHAT_FRAME:AddMessage("[MasterLootFrame] Starting roll session for slot " .. slot)
    
    -- Close existing session
    if self.activeRollSession then
        self:close_roll_session()
    end
    
    -- Create new session
    self.activeRollSession = {
        slot = slot,
        itemLink = itemLink,
        rolls = {}, -- {player, rollType, result, timestamp}
        startTime = time()
    }
    
    -- Show ranking frame
    self:show_ranking_frame()
    
    -- Hook chat to capture rolls
    self:hook_roll_messages()
end

-- Show ranking frame
function MasterLootFrame:show_ranking_frame()
    if self.rankingFrame then
        self.rankingFrame:Show()
        self:update_ranking_display()
        return
    end
    
    -- Create ranking frame
    local frame = CreateFrame("Frame", "GuildRoll_RankingFrame", UIParent)
    frame:SetWidth(400)
    frame:SetHeight(400)
    frame:SetPoint("CENTER", UIParent, "CENTER", 250, 0)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() frame:StartMoving() end)
    frame:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    
    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("Roll Rankings")
    frame.title = title
    
    -- Item name
    local itemName = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    itemName:SetPoint("TOP", title, "BOTTOM", 0, -5)
    itemName:SetWidth(360)
    itemName:SetJustifyH("CENTER")
    frame.itemName = itemName
    
    -- Headers
    local headerFrame = CreateFrame("Frame", nil, frame)
    headerFrame:SetPoint("TOPLEFT", 20, -60)
    headerFrame:SetPoint("TOPRIGHT", -20, -60)
    headerFrame:SetHeight(20)
    
    local nameHeader = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameHeader:SetPoint("LEFT", 5, 0)
    nameHeader:SetText("Player")
    
    local typeHeader = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    typeHeader:SetPoint("LEFT", 150, 0)
    typeHeader:SetText("Type")
    
    local resultHeader = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    resultHeader:SetPoint("LEFT", 250, 0)
    resultHeader:SetText("Roll")
    
    -- Scroll frame for rankings
    local scrollFrame = CreateFrame("ScrollFrame", "GuildRoll_RankingScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 20, -85)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 50)
    frame.scrollFrame = scrollFrame
    
    -- Content frame
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(340)
    content:SetHeight(1)
    scrollFrame:SetScrollChild(content)
    frame.content = content
    
    -- Close Rolls button
    local closeRollsBtn = CreateFrame("Button", nil, frame)
    closeRollsBtn:SetWidth(120)
    closeRollsBtn:SetHeight(30)
    closeRollsBtn:SetPoint("BOTTOM", 0, 12)
    
    -- Create text on button (SetText doesn't work in WoW 1.12)
    local closeText = closeRollsBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    closeText:SetPoint("CENTER", closeRollsBtn, "CENTER", 0, 0)
    closeText:SetText("Close Rolls")
    
    local closeBg = closeRollsBtn:CreateTexture(nil, "BACKGROUND")
    closeBg:SetAllPoints()
    closeBg:SetTexture(0.6, 0.2, 0.2, 0.8)
    
    local closeHl = closeRollsBtn:CreateTexture(nil, "HIGHLIGHT")
    closeHl:SetAllPoints()
    closeHl:SetTexture(0.8, 0.3, 0.3, 0.8)
    
    closeRollsBtn:SetScript("OnClick", function()
        self:confirm_close_rolls()
    end)
    
    frame.closeRollsBtn = closeRollsBtn
    frame.rollRows = {}
    
    self.rankingFrame = frame
    frame:Show()
    
    self:update_ranking_display()
end

-- Update ranking display
function MasterLootFrame:update_ranking_display()
    if not self.rankingFrame or not self.activeRollSession then
        return
    end
    
    local frame = self.rankingFrame
    local content = frame.content
    
    -- Update item name
    if self.activeRollSession.itemLink then
        frame.itemName:SetText(self.activeRollSession.itemLink)
    end
    
    -- Clear existing rows
    for _, row in ipairs(frame.rollRows) do
        row:Hide()
        row:SetParent(nil)
    end
    frame.rollRows = {}
    
    -- Sort rolls by priority
    local sortedRolls = {}
    for _, roll in ipairs(self.activeRollSession.rolls) do
        table.insert(sortedRolls, roll)
    end
    
    table.sort(sortedRolls, function(a, b)
        local aPriority = ROLL_PRIORITIES[a.rollType] or 999
        local bPriority = ROLL_PRIORITIES[b.rollType] or 999
        
        if aPriority ~= bPriority then
            return aPriority < bPriority
        end
        
        return a.result > b.result
    end)
    
    -- Create rows
    local yOffset = 0
    for i, roll in ipairs(sortedRolls) do
        local row = self:create_roll_row(content, roll, i)
        row:SetPoint("TOPLEFT", 0, -yOffset)
        table.insert(frame.rollRows, row)
        yOffset = yOffset + 25
    end
    
    -- Resize content
    content:SetHeight(math.max(yOffset, 1))
end

-- Create a roll row
function MasterLootFrame:create_roll_row(parent, roll, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetWidth(340)
    row:SetHeight(22)
    
    -- Background (alternate colors)
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    if mod(index, 2) == 0 then
        bg:SetTexture(0.15, 0.15, 0.15, 0.8)
    else
        bg:SetTexture(0.1, 0.1, 0.1, 0.8)
    end
    
    -- Player name
    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameText:SetPoint("LEFT", 5, 0)
    nameText:SetWidth(140)
    nameText:SetJustifyH("LEFT")
    nameText:SetText(roll.player)
    
    -- Roll type with color
    local typeText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    typeText:SetPoint("LEFT", 150, 0)
    typeText:SetText(roll.rollType)
    
    -- Color by priority
    if roll.rollType == "SR" then
        typeText:SetTextColor(1, 0.5, 0) -- Orange
    elseif roll.rollType == "MS" then
        typeText:SetTextColor(0, 1, 0) -- Green
    elseif roll.rollType == "OS" then
        typeText:SetTextColor(0.5, 0.5, 1) -- Light blue
    elseif roll.rollType == "Tmog" then
        typeText:SetTextColor(0.8, 0.8, 0.8) -- Gray
    end
    
    -- Roll result
    local resultText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    resultText:SetPoint("LEFT", 250, 0)
    resultText:SetText(tostring(roll.result))
    
    return row
end

-- Hook roll messages
function MasterLootFrame:hook_roll_messages()
    -- Use existing RollParser if available
    if not GuildRoll_RollParser then
        return
    end
    
    -- Set up event listener for system messages
    if not self.rollEventFrame then
        self.rollEventFrame = CreateFrame("Frame")
        self.rollEventFrame:RegisterEvent("CHAT_MSG_SYSTEM")
        
        -- Store reference to self for the event handler
        local mlf = self
        self.rollEventFrame:SetScript("OnEvent", function()
            -- In WoW 1.12, event arguments are global: event, arg1, arg2, etc.
            if event == "CHAT_MSG_SYSTEM" and arg1 then
                mlf:on_roll_message(arg1)
            end
        end)
    end
end

-- Handle roll message
function MasterLootFrame:on_roll_message(message)
    if not self.activeRollSession then
        return
    end
    
    -- Parse roll using RollParser
    local roll = GuildRoll_RollParser:ParseRoll(message)
    
    if not roll then
        return
    end
    
    -- Determine roll type
    local rollType = get_roll_type(roll.result)
    
    -- Check if player already rolled
    for i, existingRoll in ipairs(self.activeRollSession.rolls) do
        if existingRoll.player == roll.player then
            -- Update existing roll
            self.activeRollSession.rolls[i] = {
                player = roll.player,
                rollType = rollType,
                result = roll.result,
                timestamp = time()
            }
            self:update_ranking_display()
            return
        end
    end
    
    -- Add new roll
    table.insert(self.activeRollSession.rolls, {
        player = roll.player,
        rollType = rollType,
        result = roll.result,
        timestamp = time()
    })
    
    self:update_ranking_display()
end

-- Confirm close rolls
function MasterLootFrame:confirm_close_rolls()
    if not self.activeRollSession or table.getn(self.activeRollSession.rolls) == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("[MasterLootFrame] No rolls to close")
        self:close_roll_session()
        return
    end
    
    -- Get winner (first in sorted list)
    local sortedRolls = {}
    for _, roll in ipairs(self.activeRollSession.rolls) do
        table.insert(sortedRolls, roll)
    end
    
    table.sort(sortedRolls, function(a, b)
        local aPriority = ROLL_PRIORITIES[a.rollType] or 999
        local bPriority = ROLL_PRIORITIES[b.rollType] or 999
        
        if aPriority ~= bPriority then
            return aPriority < bPriority
        end
        
        return a.result > b.result
    end)
    
    local winner = sortedRolls[1]
    
    if not winner then
        self:close_roll_session()
        return
    end
    
    -- Show confirmation dialog
    local dialog = StaticPopup_Show("GUILDROLL_CONFIRM_LOOT_ASSIGNMENT")
    if dialog then
        dialog.data = {
            frame = self,
            slot = self.activeRollSession.slot,
            winner = winner.player
        }
    end
end

-- Assign loot to winner
function MasterLootFrame:assign_loot_to_winner(slot, winnerName)
    -- Find candidate index
    local candidateIndex = nil
    for i = 1, 40 do
        local candidateName = GetMasterLootCandidate(i)
        if candidateName == winnerName then
            candidateIndex = i
            break
        end
    end
    
    if not candidateIndex then
        DEFAULT_CHAT_FRAME:AddMessage("[MasterLootFrame] ERROR: Winner not found in candidates!")
        return
    end
    
    -- Assign loot
    GiveMasterLoot(slot, candidateIndex)
    
    DEFAULT_CHAT_FRAME:AddMessage("[MasterLootFrame] Assigned loot to " .. winnerName)
    
    -- Notify callback
    if self.on_loot_given then
        self.on_loot_given(slot, candidateIndex, winnerName)
    end
    
    -- Close session
    self:close_roll_session()
end

-- Close roll session
function MasterLootFrame:close_roll_session()
    if self.rankingFrame then
        self.rankingFrame:Hide()
    end
    
    if self.rollEventFrame then
        self.rollEventFrame:UnregisterEvent("CHAT_MSG_SYSTEM")
    end
    
    self.activeRollSession = nil
end

-- Set callback for when loot is given
function MasterLootFrame:set_on_loot_given(callback)
    self.on_loot_given = callback
end

-- Show the frame
function MasterLootFrame:show()
    DEFAULT_CHAT_FRAME:AddMessage("[MasterLootFrame] show() called")
    
    -- Hide Blizzard LootFrame and prevent errors
    if LootFrame then
        LootFrame:Hide()
        -- Set page to 1 to prevent arithmetic errors in Blizzard's scripts
        -- that still run even when frame is hidden
        LootFrame.page = 1
    end
    
    -- Create and show custom frame
    self:create_loot_frame()
    self:populate_loot_items()
    
    if self.mainFrame then
        self.mainFrame:Show()
        self.isShown = true
    end
end

-- Hide the frame
function MasterLootFrame:hide()
    if self.mainFrame then
        self.mainFrame:Hide()
        self.isShown = false
    end
    
    if self.menuFrame then
        self.menuFrame:Hide()
    end
    
    -- Close any active roll session
    self:close_roll_session()
    
    -- Show Blizzard LootFrame again
    if LootFrame then
        LootFrame:Show()
    end
end

-- Register confirmation dialog
StaticPopupDialogs["GUILDROLL_CONFIRM_LOOT_ASSIGNMENT"] = {
    text = "Assign %s to %s?",
    button1 = "Yes",
    button2 = "No",
    OnShow = function()
        local itemLink = this.data.frame.activeRollSession.itemLink or "item"
        local winner = this.data.winner or "unknown"
        this.text:SetText(string.format("Assign %s to %s?", itemLink, winner))
    end,
    OnAccept = function()
        this.data.frame:assign_loot_to_winner(this.data.slot, this.data.winner)
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1
}

-- Export to global namespace
_G.MasterLootFrame = MasterLootFrame
if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("[DEBUG] MasterLootFrame exported to _G")
end
-- Module continues - do not return here

-- =============================================================================
-- MasterLoot.lua
-- Orchestrates master loot flow
-- Handles LOOT_OPENED, LOOT_CLOSED, LOOT_SLOT_CLEARED, and error messages
-- Uses GiveMasterLoot and MasterLootFrame

local MasterLoot = {}
MasterLoot.__index = MasterLoot

-- Constructor
-- master_loot_frame: MasterLootFrame instance
-- master_loot_tracker: MasterLootTracker instance
-- awarded_loot: AwardedLoot instance
function MasterLoot.new(master_loot_frame, master_loot_tracker, awarded_loot)
    local self = setmetatable({}, MasterLoot)
    self.frame = master_loot_frame
    self.tracker = master_loot_tracker
    self.awarded_loot = awarded_loot
    self.is_open = false
    
    -- Set callback for when loot is given
    if self.frame then
        self.frame:set_on_loot_given(function(slot, candidate_index, candidate_name)
            self:on_loot_given(slot, candidate_index, candidate_name)
        end)
    end
    
    return self
end

-- On LOOT_OPENED event
function MasterLoot:on_loot_opened()
    DEFAULT_CHAT_FRAME:AddMessage("[MasterLoot] on_loot_opened() called")
    
    -- Check if we're the master looter
    local loot_method, master_party, master_raid = GetLootMethod()
    DEFAULT_CHAT_FRAME:AddMessage(string.format("[MasterLoot] Loot method: %s", tostring(loot_method)))
    
    if loot_method ~= "master" then
        DEFAULT_CHAT_FRAME:AddMessage("[MasterLoot] Not master loot, exiting")
        return
    end
    
    self.is_open = true
    
    -- Show frame
    if self.frame then
        DEFAULT_CHAT_FRAME:AddMessage("[MasterLoot] Calling frame:show()")
        self.frame:show()
    else
        DEFAULT_CHAT_FRAME:AddMessage("[MasterLoot] ERROR: frame is nil!")
    end
end

-- On LOOT_CLOSED event
function MasterLoot:on_loot_closed()
    self.is_open = false
    
    -- Hide frame
    if self.frame then
        self.frame:hide()
    end
    
    -- Clear tracker
    if self.tracker then
        self.tracker:clear_all()
    end
end

-- On LOOT_SLOT_CLEARED event
-- slot: loot slot that was cleared
function MasterLoot:on_loot_slot_cleared(slot)
    if not slot or not self.tracker then
        return
    end
    
    -- Get item from tracker
    local item = self.tracker:get(slot)
    if not item then
        return
    end
    
    -- Award the item
    self:award_item(item, slot)
    
    -- Clear from tracker
    self.tracker:clear_slot(slot)
end

-- Award an item
-- item: item table with { id, name, link, quality }
-- slot: loot slot
function MasterLoot:award_item(item, slot)
    if not item or not item.id then
        return
    end
    
    -- Check if already awarded recently
    if self.awarded_loot and self.awarded_loot:was_recently_awarded(item.id, 30) then
        -- Already awarded, skip
        return
    end
    
    -- We don't know who got it yet (that info comes from GiveMasterLoot callback)
    -- So we just mark it as awarded with a placeholder
    -- The actual player will be set in on_loot_given
    
    -- For now, just log it
    if GuildRoll and GuildRoll.DEBUG then
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "[MasterLoot] Item awarded: %s (slot %d)",
            item.link or item.name or "Unknown", slot
        ))
    end
end

-- On loot given (called by MasterLootFrame)
-- slot: loot slot
-- candidate_index: candidate index
-- candidate_name: candidate name
function MasterLoot:on_loot_given(slot, candidate_index, candidate_name)
    if not slot or not candidate_name then
        return
    end
    
    -- Get item from tracker
    local item = self.tracker:get(slot)
    if not item then
        return
    end
    
    -- Add to awarded loot
    if self.awarded_loot and item.id then
        self.awarded_loot:add(item.id, candidate_name)
    end
    
    -- Log award
    DEFAULT_CHAT_FRAME:AddMessage(string.format(
        "[MasterLoot] Awarded %s to %s",
        item.link or item.name or "Unknown", candidate_name
    ))
end

-- On UI_ERROR_MESSAGE event
-- msg: error message
function MasterLoot:on_error_message(msg)
    if not msg then return end
    
    -- Check for specific error messages
    if string.find(msg, "Inventory is full") or string.find(msg, "inventory is full") then
        self:on_recipient_inventory_full()
    elseif string.find(msg, "too far") or string.find(msg, "Too far") then
        self:on_player_is_too_far()
    else
        self:on_unknown_error_message(msg)
    end
end

-- Handler for inventory full error
function MasterLoot:on_recipient_inventory_full()
    DEFAULT_CHAT_FRAME:AddMessage("[MasterLoot] ERROR: Recipient's inventory is full!")
end

-- Handler for player too far error
function MasterLoot:on_player_is_too_far()
    DEFAULT_CHAT_FRAME:AddMessage("[MasterLoot] ERROR: Player is too far away!")
end

-- Handler for unknown error
function MasterLoot:on_unknown_error_message(msg)
    if GuildRoll and GuildRoll.DEBUG then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("[MasterLoot] ERROR: %s", msg))
    end
end

_G.MasterLoot = MasterLoot
if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("[lootsystem] MasterLoot loaded")
end
-- Module continues - do not return here

-- =============================================================================
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
    text:SetPoint("CENTER", frame, "CENTER", 0, 0)
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

-- =============================================================================
-- END OF LOOTSYSTEM.LUA
-- =============================================================================
if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("[LOOTSYSTEM] lootsystem.lua loaded successfully - all 8 modules exported")
end

return MasterLootWarning
