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
    
    local item_id = string.match(link, "item:(%d+)")
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
    if #announcements > 0 then
        self:announce_items(announcements)
    end
end

-- Announce items to raid/party
function DroppedLootAnnounce:announce_items(announcements)
    if not announcements or #announcements == 0 then
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

_G.DroppedLootAnnounce = DroppedLootAnnounce
return DroppedLootAnnounce
