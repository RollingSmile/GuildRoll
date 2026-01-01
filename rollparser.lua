-- RollParser Module for GuildRoll
-- Parses RollFor-style loot submissions and system roll messages
-- Supports CSR/SR/MS roll types with EP integration

local L = AceLibrary("AceLocale-2.2"):new("guildroll")

-- Module state
GuildRoll_RollParser = {
    -- Track active loot submissions
    activeLoot = {},
    -- Track recent rolls
    recentRolls = {},
    -- Settings
    timeout = 300, -- 5 minutes timeout for loot tracking
    maxRolls = 50, -- Maximum number of rolls to track
}

local RollParser = GuildRoll_RollParser

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
    local rlMatch = string.match(message, "^%[RL%]")
    if not rlMatch then
        return nil
    end
    
    debugPrint("Found [RL] message: " .. message)
    
    -- Parse the submission
    -- Pattern: [RL] PlayerName: ItemInfo - RollType
    local playerName, itemInfo, rollType = string.match(message, "%[RL%]%s*([^:]+):%s*(.-)%s*%-%s*(%w+)%s*$")
    
    if not playerName or not itemInfo or not rollType then
        -- Try alternative pattern without item info
        playerName, rollType = string.match(message, "%[RL%]%s*([^:]+):%s*(%w+)%s*$")
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
    
    -- Validate roll type
    local validTypes = {
        MS = true,
        SR = true,
        CSR = true,
        MAINSPEC = true,
        SECONDARYSPEC = true,
        OFFSPEC = true,
        OS = true,
    }
    
    if not validTypes[rollType] then
        debugPrint("Invalid roll type: " .. rollType)
        return nil
    end
    
    -- Map alternative names to standard types
    if rollType == "MAINSPEC" then rollType = "MS" end
    if rollType == "SECONDARYSPEC" then rollType = "SR" end
    if rollType == "OFFSPEC" then rollType = "OS" end
    
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
    local playerName, minRoll, maxRoll, result = string.match(message, "^(.+) rolls (%d+)%-(%d+) %((%d+)%)%.?$")
    
    if not playerName or not minRoll or not maxRoll or not result then
        return nil
    end
    
    -- Clean up player name (remove server name if present)
    -- Use utility function if available, otherwise inline pattern
    if GuildRoll and GuildRoll.stripRealmName then
        playerName = GuildRoll:stripRealmName(playerName)
    else
        playerName = string.gsub(playerName, "%-[^%-]+$", "")
    end
    
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
-- CSR: 100+ EP to 200+ EP (SR bonus + CSR bonus)
-- SR: 100+ EP to 200+ EP
-- MS: 1+ EP to 100+ EP
function RollParser:DetermineEPFromRoll(roll)
    if not roll then return nil, nil end
    
    local min = roll.min
    local max = roll.max
    
    -- Calculate EP and roll type
    local ep = 0
    local rollType = nil
    
    if min >= 101 and max >= 200 then
        -- SR or CSR range (101+EP to 200+EP)
        -- Base EP is min - 101
        ep = min - 101
        
        -- Check if it's CSR (has additional bonus beyond 100)
        local totalBonus = max - min
        if totalBonus > 100 then
            -- CSR with bonus weeks
            rollType = "CSR"
        else
            rollType = "SR"
        end
    elseif min >= 1 and max >= 100 and max <= 200 then
        -- MS range (1+EP to 100+EP)
        ep = min - 1
        rollType = "MS"
    elseif min == 1 and max == 100 then
        -- Standard roll (no EP)
        ep = 0
        rollType = "Standard"
    elseif min == 1 and max == 99 then
        -- OS/Alt roll
        ep = 0
        rollType = "OS"
    elseif min == 1 and max == 98 then
        -- Transmog roll
        ep = 0
        rollType = "Transmog"
    else
        -- Unknown roll type
        rollType = "Unknown"
    end
    
    return ep, rollType
end

-- Associate a roll with a submission
function RollParser:AssociateRollWithSubmission(roll)
    if not roll then return nil end
    
    -- Find matching submission for this player
    local playerName = roll.player
    local matchingSubmission = nil
    
    for i = #self.activeLoot, 1, -1 do
        local submission = self.activeLoot[i]
        if submission.player == playerName then
            -- Check if submission is not too old
            if (time() - submission.timestamp) <= self.timeout then
                matchingSubmission = submission
                break
            end
        end
    end
    
    if matchingSubmission then
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
    end
    
    return nil
end

-- Add a submission to tracking
function RollParser:AddSubmission(submission)
    if not submission then return end
    
    -- Clean up old submissions
    local currentTime = time()
    local i = 1
    while i <= #self.activeLoot do
        if (currentTime - self.activeLoot[i].timestamp) > self.timeout then
            table.remove(self.activeLoot, i)
        else
            i = i + 1
        end
    end
    
    -- Add new submission
    table.insert(self.activeLoot, submission)
    debugPrint(string.format("Added submission for %s (%s) - total active: %d", submission.player, submission.rollType, #self.activeLoot))
end

-- Add a roll to tracking
function RollParser:AddRoll(roll)
    if not roll then return end
    
    -- Keep only recent rolls
    if #self.recentRolls >= self.maxRolls then
        table.remove(self.recentRolls, 1)
    end
    
    table.insert(self.recentRolls, roll)
end

-- Handle a chat message
function RollParser:HandleChatMessage(message, sender, msgType)
    if not message then return end
    
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
    
    -- Clean up old submissions
    local i = 1
    while i <= #self.activeLoot do
        if (currentTime - self.activeLoot[i].timestamp) > self.timeout then
            table.remove(self.activeLoot, i)
        else
            i = i + 1
        end
    end
    
    -- Clean up old rolls
    if #self.recentRolls > self.maxRolls then
        while #self.recentRolls > self.maxRolls do
            table.remove(self.recentRolls, 1)
        end
    end
end

-- Initialize the parser
function RollParser:Initialize()
    debugPrint("RollParser initialized")
    
    -- Set up periodic cleanup
    if not self.cleanupScheduled then
        self.cleanupScheduled = true
        -- Schedule cleanup every 60 seconds
        if GuildRoll and GuildRoll.ScheduleRepeatingEvent then
            GuildRoll:ScheduleRepeatingEvent("RollParserCleanup", function() RollParser:Cleanup() end, 60)
        end
    end
end

-- Export functions to GuildRoll namespace
if GuildRoll then
    GuildRoll.RollParser = RollParser
end

return RollParser
