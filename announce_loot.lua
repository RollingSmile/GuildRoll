-- Guard: Check if required libraries are available before proceeding
local L
do
  local ok, result = pcall(function() return AceLibrary("AceLocale-2.2") end)
  if not ok or not result or type(result.new) ~= "function" then return end
  ok, L = pcall(function() return result:new("guildroll") end)
  if not ok or not L then return end
end

-- Helper: Strip realm suffix from player name
local function StripRealm(name)
  if not name then return "" end
  return string.gsub(name, "%-[^%-]+$", "")
end

-- Helper: Check if player has permission to announce loot
-- Permission: RAID + Admin AND (Master Looter OR (RaidLeader when not master loot))
local function IsAdminAndMLOrRLWhenNoML()
  if not GuildRoll or not GuildRoll.IsAdmin then
    return false
  end
  
  -- Pre-check: Must be in a raid (not party, not solo)
  local ok, numRaidMembers = pcall(GetNumRaidMembers)
  if not ok or not numRaidMembers or numRaidMembers == 0 then
    return false
  end
  
  local success, isAdmin = pcall(function() return GuildRoll:IsAdmin() end)
  if not success or not isAdmin then
    return false
  end
  
  -- Check if player is master looter
  if GuildRoll.lootMaster then
    local ok, isMasterLooter = pcall(function() return GuildRoll:lootMaster() end)
    if ok and isMasterLooter then
      return true
    end
  end
  
  -- Check if raid leader when loot method is not master
  local ok, method = pcall(GetLootMethod)
  if ok and method ~= "master" then
    local success, isRL = pcall(IsRaidLeader)
    if success and isRL then
      return true
    end
  end
  
  return false
end

-- Helper: Get SR/CSR list for an item
-- Looks in session first (GuildRoll._RollForEP_currentLoot.srlist),
-- fallback to GuildRoll_rollForEPCache.lastImport.srlist
-- Returns list of player names who have SR/CSR for the item (stripped of realm suffix)
local function GetSRListForItem(itemID, itemName)
  local srlist = {}
  local found = {}
  
  -- Try session srlist first
  if GuildRoll and GuildRoll._RollForEP_currentLoot and GuildRoll._RollForEP_currentLoot.srlist then
    local sessionSR = GuildRoll._RollForEP_currentLoot.srlist
    for player, items in pairs(sessionSR) do
      if type(items) == "table" then
        for _, item in ipairs(items) do
          local match = false
          if type(item) == "table" then
            -- Match by itemID first
            if item.itemID and itemID and tonumber(item.itemID) == tonumber(itemID) then
              match = true
            -- Fallback to itemName
            elseif item.itemName and itemName and item.itemName == itemName then
              match = true
            end
          end
          
          if match then
            local cleanName = StripRealm(player)
            if cleanName and cleanName ~= "" and not found[cleanName] then
              table.insert(srlist, cleanName)
              found[cleanName] = true
            end
          end
        end
      end
    end
  end
  
  -- Fallback to cache
  if table.getn(srlist) == 0 and GuildRoll_rollForEPCache and GuildRoll_rollForEPCache.lastImport and GuildRoll_rollForEPCache.lastImport.srlist then
    local cacheSR = GuildRoll_rollForEPCache.lastImport.srlist
    for player, items in pairs(cacheSR) do
      if type(items) == "table" then
        for _, item in ipairs(items) do
          local match = false
          if type(item) == "table" then
            -- Match by itemID first
            if item.itemID and itemID and tonumber(item.itemID) == tonumber(itemID) then
              match = true
            -- Fallback to itemName
            elseif item.itemName and itemName and item.itemName == itemName then
              match = true
            end
          end
          
          if match then
            local cleanName = StripRealm(player)
            if cleanName and cleanName ~= "" and not found[cleanName] then
              table.insert(srlist, cleanName)
              found[cleanName] = true
            end
          end
        end
      end
    end
  end
  
  return srlist
end

-- Helper: Format SR list with max 7 names, append " +N more" if exceeded
local function FormatSRList(srlist)
  if not srlist or table.getn(srlist) == 0 then
    return ""
  end
  
  local count = table.getn(srlist)
  local maxShow = 7
  local names = {}
  
  for i = 1, math.min(count, maxShow) do
    table.insert(names, srlist[i])
  end
  
  local result = table.concat(names, ", ")
  
  if count > maxShow then
    result = result .. " +" .. (count - maxShow) .. " more"
  end
  
  return result
end

-- Helper: Determine if SR or CSR based on item data
-- Returns "SR" or "CSR wkN" format
local function GetSRType(itemID, itemName, playerName)
  -- Check session data first
  if GuildRoll and GuildRoll._RollForEP_currentLoot and GuildRoll._RollForEP_currentLoot.srlist then
    local sessionSR = GuildRoll._RollForEP_currentLoot.srlist
    local cleanPlayer = StripRealm(playerName)
    
    if sessionSR[playerName] or sessionSR[cleanPlayer] then
      local items = sessionSR[playerName] or sessionSR[cleanPlayer]
      if type(items) == "table" then
        for _, item in ipairs(items) do
          if type(item) == "table" then
            local match = false
            if item.itemID and itemID and tonumber(item.itemID) == tonumber(itemID) then
              match = true
            elseif item.itemName and itemName and item.itemName == itemName then
              match = true
            end
            
            if match then
              if item.weeks and tonumber(item.weeks) and tonumber(item.weeks) > 0 then
                return "CSR wk" .. item.weeks
              else
                return "SR"
              end
            end
          end
        end
      end
    end
  end
  
  -- Fallback to cache
  if GuildRoll_rollForEPCache and GuildRoll_rollForEPCache.lastImport and GuildRoll_rollForEPCache.lastImport.srlist then
    local cacheSR = GuildRoll_rollForEPCache.lastImport.srlist
    local cleanPlayer = StripRealm(playerName)
    
    if cacheSR[playerName] or cacheSR[cleanPlayer] then
      local items = cacheSR[playerName] or cacheSR[cleanPlayer]
      if type(items) == "table" then
        for _, item in ipairs(items) do
          if type(item) == "table" then
            local match = false
            if item.itemID and itemID and tonumber(item.itemID) == tonumber(itemID) then
              match = true
            elseif item.itemName and itemName and item.itemName == itemName then
              match = true
            end
            
            if match then
              if item.weeks and tonumber(item.weeks) and tonumber(item.weeks) > 0 then
                return "CSR wk" .. item.weeks
              else
                return "SR"
              end
            end
          end
        end
      end
    end
  end
  
  return "SR"  -- Default
end

-- LOOT_OPENED event handler
-- Announces loot when permitted player opens a corpse/container
-- Integration: Also opens RollWithEP UI if available (new module)
local function OnLootOpened()
  -- Check permission
  if not IsAdminAndMLOrRLWhenNoML() then
    return
  end
  
  -- Get number of loot slots
  local ok, numSlots = pcall(GetNumLootItems)
  if not ok or not numSlots or numSlots == 0 then
    return
  end
  
  -- Determine chat channel
  local channel = "SAY"
  local ok, numRaidMembers = pcall(GetNumRaidMembers)
  if ok and numRaidMembers and numRaidMembers > 0 then
    channel = "RAID"
  end
  
  -- Announce first line
  local ok = pcall(function()
    SendChatMessage("Loot found:", channel)
  end)
  
  if not ok then
    return
  end
  
  -- Announce each loot slot and collect loot data for RollWithEP
  local lootItems = {}
  for slot = 1, numSlots do
    local ok, lootIcon, lootName, lootQuantity, rarity = pcall(GetLootSlotInfo, slot)
    if ok and lootName then
      -- Get item link
      local success, itemLink = pcall(GetLootSlotLink, slot)
      if success and itemLink then
        -- Extract itemID from link
        local itemID = nil
        local idMatch = string.match(itemLink, "item:(%d+)")
        if idMatch then
          itemID = tonumber(idMatch)
        end
        
        -- Store loot item for RollWithEP
        table.insert(lootItems, {
          slot = slot,
          itemLink = itemLink,
          itemID = itemID,
          itemName = lootName
        })
        
        -- Get SR list for this item
        local srlist = GetSRListForItem(itemID, lootName)
        
        -- Format message
        local message = itemLink
        
        if srlist and table.getn(srlist) > 0 then
          -- Build detailed SR/CSR info
          local srInfo = {}
          for _, playerName in ipairs(srlist) do
            local srType = GetSRType(itemID, lootName, playerName)
            table.insert(srInfo, playerName .. " (" .. srType .. ")")
          end
          
          -- Limit to 7 names
          local count = table.getn(srInfo)
          local maxShow = 7
          local displayInfo = {}
          
          for i = 1, math.min(count, maxShow) do
            table.insert(displayInfo, srInfo[i])
          end
          
          message = message .. " " .. table.concat(displayInfo, ", ")
          
          if count > maxShow then
            message = message .. " +" .. (count - maxShow) .. " more"
          end
        end
        
        -- Send message
        pcall(function()
          SendChatMessage(message, channel)
        end)
      end
    end
  end
  
  -- Integration point: Open RollWithEP UI if module is loaded
  -- The RollWithEP module provides interactive roll management UI
  if GuildRoll and GuildRoll.RollWithEP_ShowLootUI then
    pcall(function()
      GuildRoll.RollWithEP_ShowLootUI(lootItems)
    end)
  end
end

-- Register LOOT_OPENED event
if GuildRoll and GuildRoll.RegisterEvent then
  pcall(function()
    GuildRoll:RegisterEvent("LOOT_OPENED", OnLootOpened)
  end)
end

-- Public API: AnnounceStartRollingFor
-- Announces "Start rolling for [ITEM_LINK]" with SR list if applicable
function GuildRoll:AnnounceStartRollingFor(itemLink, itemID)
  -- Check permission
  if not IsAdminAndMLOrRLWhenNoML() then
    return
  end
  
  if not itemLink then
    return
  end
  
  -- Extract itemName from link if possible
  local itemName = nil
  local nameMatch = string.match(itemLink, "%[(.-)%]")
  if nameMatch then
    itemName = nameMatch
  end
  
  -- Determine chat channel
  local channel = "SAY"
  local ok, numRaidMembers = pcall(GetNumRaidMembers)
  if ok and numRaidMembers and numRaidMembers > 0 then
    channel = "RAID"
  end
  
  -- Get SR list
  local srlist = GetSRListForItem(itemID, itemName)
  
  -- Format message
  local message = "Start rolling for " .. itemLink
  
  if srlist and table.getn(srlist) > 0 then
    local formattedSR = FormatSRList(srlist)
    if formattedSR and formattedSR ~= "" then
      message = message .. " (SoftReserves: " .. formattedSR .. ")"
    end
  end
  
  -- Send message
  pcall(function()
    SendChatMessage(message, channel)
  end)
end
