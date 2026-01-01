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

_G.AwardedLoot = AwardedLoot
return AwardedLoot
