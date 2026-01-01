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
-- Expected format: "PlayerName rolls 1-100 (75)" or "PlayerName rolls 101-200 (150)"
function RollParser:ParseRoll(message)
    if not message then return nil end
    
    -- Pattern: PlayerName rolls min-max (result)
    local _, _, playerName, minRoll, maxRoll, result = string.find(message, "^(.+) rolls (%d+)%-(%d+) %((%d+)%)%.?$")
    
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
    self.lootframe_onshow_hooked = false
    return self
end

-- Try to hook loot buttons (internal helper)
local function try_hook_buttons(self)
    local found_any = false
    
    DEFAULT_CHAT_FRAME:AddMessage("[MasterLootFrame] Attempting to hook loot buttons...")
    
    -- Try to find and hook LootButton1..20
    for i = 1, 20 do
        local button = _G["LootButton" .. i]
        if button then
            found_any = true
            -- Only hook if not already hooked
            if not self.original_click_handlers[i] then
                -- Store original handler
                self.original_click_handlers[i] = button:GetScript("OnClick")
                
                DEFAULT_CHAT_FRAME:AddMessage(string.format("[MasterLootFrame] Hooked LootButton%d", i))
                
                -- Set new handler - must capture self in closure properly
                -- In WoW 1.12, 'this' and 'arg1' are global variables set by the event system
                button:SetScript("OnClick", function()
                    -- 'this' refers to the button that was clicked
                    -- 'arg1' is the mouse button ("LeftButton", "RightButton", etc.)
                    DEFAULT_CHAT_FRAME:AddMessage(string.format("[MasterLootFrame] Button clicked: slot=%s, mouse=%s", tostring(this and this:GetID()), tostring(arg1)))
                    self:on_loot_button_click(this, arg1)
                end)
            end
        end
    end
    
    if found_any then
        self.hooked = true
        DEFAULT_CHAT_FRAME:AddMessage("[MasterLootFrame] Buttons hooked successfully")
    else
        DEFAULT_CHAT_FRAME:AddMessage("[MasterLootFrame] No buttons found to hook")
    end
    
    return found_any
end

-- Hook loot buttons to show candidate selection (robust version)
function MasterLootFrame:hook_loot_buttons()
    DEFAULT_CHAT_FRAME:AddMessage("[MasterLootFrame] hook_loot_buttons() called")
    
    if self.hooked then 
        DEFAULT_CHAT_FRAME:AddMessage("[MasterLootFrame] Already hooked, returning")
        return 
    end
    
    -- Try to hook buttons now
    local found = try_hook_buttons(self)
    
    -- If no buttons found yet, hook LootFrame OnShow to retry when it appears
    if not found and not self.lootframe_onshow_hooked then
        DEFAULT_CHAT_FRAME:AddMessage("[MasterLootFrame] Setting up LootFrame OnShow hook")
        local lootFrame = _G["LootFrame"]
        if lootFrame then
            -- Store original OnShow handler
            self.original_lootframe_onshow = lootFrame:GetScript("OnShow")
            
            -- Set new OnShow that retries hooking
            lootFrame:SetScript("OnShow", function()
                DEFAULT_CHAT_FRAME:AddMessage("[MasterLootFrame] LootFrame OnShow triggered")
                -- Call original handler first
                if self.original_lootframe_onshow then
                    self.original_lootframe_onshow()
                end
                
                -- Try to hook buttons
                try_hook_buttons(self)
            end)
            
            self.lootframe_onshow_hooked = true
        else
            DEFAULT_CHAT_FRAME:AddMessage("[MasterLootFrame] LootFrame not found!")
        end
    end
end

-- Restore original loot button handlers
function MasterLootFrame:restore_loot_buttons()
    if not self.hooked and not self.lootframe_onshow_hooked then return end
    
    -- Restore button handlers
    for i = 1, 20 do
        local button = _G["LootButton" .. i]
        if button and self.original_click_handlers[i] then
            button:SetScript("OnClick", self.original_click_handlers[i])
        end
    end
    
    -- Restore LootFrame OnShow if we hooked it
    if self.lootframe_onshow_hooked then
        local lootFrame = _G["LootFrame"]
        if lootFrame and self.original_lootframe_onshow then
            lootFrame:SetScript("OnShow", self.original_lootframe_onshow)
        end
        self.lootframe_onshow_hooked = false
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
    DEFAULT_CHAT_FRAME:AddMessage("[MasterLootFrame] show() called")
    self:hook_loot_buttons()
end

-- Hide the frame
function MasterLootFrame:hide()
    self:hide_candidate_selection()
    self:restore_loot_buttons()
end

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

-- =============================================================================
-- END OF LOOTSYSTEM.LUA
-- =============================================================================
if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("[LOOTSYSTEM] lootsystem.lua loaded successfully - all 8 modules exported")
end

return MasterLootWarning
