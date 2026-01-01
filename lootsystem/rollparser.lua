-- RollParser Module for GuildRoll
-- Parses RollFor-style loot submissions and system roll messages
-- Supports CSR/SR/MS roll types with EP integration

local L = AceLibrary("AceLocale-2.2"):new("guildroll")

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
    local rlMatch = string.match(message, "^%[RL%]")
    if not rlMatch then
        return nil
    end
    
    debugPrint("Found [RL] message: " .. message)
    
    -- Parse the submission
    -- Pattern: [RL] PlayerName: ItemInfo - RollType
    local playerName, itemInfo, rollType = string.match(message, "%[RL%]%s*([^:]+):%s*(.-)%s*%-%s*(%w+)%s*$")
    
    if not playerName or not itemInfo or not rollType then
        -- Try alternative pattern without item info: [RL] PlayerName: RollType
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
    local playerName, minRoll, maxRoll, result = string.match(message, "^(.+) rolls (%d+)%-(%d+) %((%d+)%)%.?$")
    
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
    -- Accept range of 100 to handle CSR cumulative bonuses which may increase range slightly
    elseif rangeSize >= 99 and rangeSize <= 100 then
        if min >= 101 then
            -- SR/CSR range: 101+EP to 200+EP (or higher with cumulative bonuses)
            rollType = "SR"
            ep = min - 101
        elseif min >= 1 and min <= 100 then
            -- MS range: 1+EP to 100+EP
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
    if #self.recentRolls >= self.maxRolls then
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
    if #self.recentRolls > self.maxRolls then
        while #self.recentRolls > self.maxRolls do
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

return RollParser
