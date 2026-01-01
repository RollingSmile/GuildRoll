-- MasterLootTracker.lua
-- Tracks slot -> item mapping for master loot
-- Stores item.id, name, link, quality for each loot slot

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
return MasterLootTracker
