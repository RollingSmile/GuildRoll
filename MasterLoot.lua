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
return MasterLoot
