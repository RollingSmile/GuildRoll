-- DroppedLoot.lua
-- Persists dropped items across sessions
-- Uses GuildRoll saved variables

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
return DroppedLoot
