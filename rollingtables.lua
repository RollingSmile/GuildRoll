-- Guard: Check if required libraries are available before proceeding
local T, D, L
do
  local ok, result = pcall(function() return AceLibrary("Tablet-2.0") end)
  if not ok or not result then return end
  T = result
  
  ok, result = pcall(function() return AceLibrary("Dewdrop-2.0") end)
  if not ok or not result then return end
  D = result
  
  ok, result = pcall(function() return AceLibrary("AceLocale-2.2") end)
  if not ok or not result or type(result.new) ~= "function" then return end
  ok, L = pcall(function() return result:new("guildroll") end)
  if not ok or not L then return end
end

GuildRoll_RollingTable = GuildRoll:NewModule("GuildRoll_RollingTable", "AceDB-2.0")

-- Helper: Strip realm suffix from player name
local function StripRealm(name)
  if not name then return "" end
  return string.gsub(name, "%-[^%-]+$", "")
end

-- Helper: Check if player has permission to manage rolls
-- Permission: Admin AND (Master Looter OR (RaidLeader when not master loot))
local function IsAdminAndMLOrRLWhenNoML()
  if not GuildRoll or not GuildRoll.IsAdmin then
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
            if item.itemID and itemID and tonumber(item.itemID) == tonumber(itemID) then
              match = true
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
            if item.itemID and itemID and tonumber(item.itemID) == tonumber(itemID) then
              match = true
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

-- Helper: Determine if player has SR/CSR for item
local function HasSR(playerName, srlist)
  if not srlist or table.getn(srlist) == 0 then
    return false
  end
  
  local cleanName = StripRealm(playerName)
  for _, name in ipairs(srlist) do
    if StripRealm(name) == cleanName then
      return true
    end
  end
  
  return false
end

-- Public API: CreateRollSession
-- Initializes a new roll session for an item
function GuildRoll:CreateRollSession(itemLink, itemID)
  if not itemLink then
    return
  end
  
  -- Extract itemName from link
  local itemName = nil
  local nameMatch = string.match(itemLink, "%[(.-)%]")
  if nameMatch then
    itemName = nameMatch
  end
  
  -- Get SR list
  local srlist = GetSRListForItem(itemID, itemName)
  
  -- Initialize session
  GuildRoll._RollingTable_currentRoll = {
    itemLink = itemLink,
    itemID = itemID,
    srlist = srlist,
    bids = {},  -- playerName -> rollValue
    winner = nil,
    started = false,
    ts = time()
  }
  
  -- Refresh tablet if registered
  if T then
    pcall(function() T:Refresh("RollingTable") end)
  end
end

-- Public API: RecordSystemRoll
-- Records a roll from CHAT_MSG_SYSTEM
function GuildRoll:RecordSystemRoll(playerName, value)
  if not GuildRoll._RollingTable_currentRoll then
    return
  end
  
  if not playerName or not value then
    return
  end
  
  local cleanName = StripRealm(playerName)
  local rollValue = tonumber(value)
  
  if not rollValue then
    return
  end
  
  -- Store the bid
  GuildRoll._RollingTable_currentRoll.bids[cleanName] = rollValue
  
  -- Refresh tablet
  if T then
    pcall(function() T:Refresh("RollingTable") end)
  end
end

-- Public API: SetWinnerForItem
-- Sets the winner for the current roll session
function GuildRoll:SetWinnerForItem(playerName)
  if not GuildRoll._RollingTable_currentRoll then
    return
  end
  
  if not playerName then
    GuildRoll._RollingTable_currentRoll.winner = nil
  else
    local cleanName = StripRealm(playerName)
    GuildRoll._RollingTable_currentRoll.winner = cleanName
  end
  
  -- Refresh tablet
  if T then
    pcall(function() T:Refresh("RollingTable") end)
  end
end

-- Public API: CloseRollSession
-- Closes the current roll session
function GuildRoll:CloseRollSession()
  GuildRoll._RollingTable_currentRoll = nil
  
  -- Refresh tablet
  if T then
    pcall(function() T:Refresh("RollingTable") end)
  end
end

-- CHAT_MSG_SYSTEM handler to detect rolls
local function OnChatMsgSystem(msg)
  if not GuildRoll._RollingTable_currentRoll then
    return
  end
  
  -- Pattern: "PlayerName rolls 42 (1-100)"
  local playerName, roll = string.match(msg, "^(.+) rolls (%d+) %(")
  
  if playerName and roll then
    GuildRoll:RecordSystemRoll(playerName, roll)
  end
end

-- Register CHAT_MSG_SYSTEM event
if GuildRoll and GuildRoll.RegisterEvent then
  pcall(function()
    GuildRoll:RegisterEvent("CHAT_MSG_SYSTEM", OnChatMsgSystem)
  end)
end

-- Tablet registration
if T then
  pcall(function()
    T:Register("RollingTable",
      "children", function()
        -- Header
        T:SetTitle("Rolling Table")
        
        local currentRoll = GuildRoll._RollingTable_currentRoll
        
        if not currentRoll then
          T:AddLine(
            "text", "No active roll session",
            "textR", 0.7,
            "textG", 0.7,
            "textB", 0.7
          )
          return
        end
        
        -- Show item
        T:AddLine(
          "text", "Item: " .. (currentRoll.itemLink or "Unknown"),
          "textR", 1,
          "textG", 1,
          "textB", 1
        )
        
        T:AddLine(
          "text", " "
        )
        
        -- Column headers
        T:AddLine(
          "text", "Player",
          "text2", "Expected",
          "text3", "Incoming",
          "text4", "Result",
          "text5", "Winner",
          "textR", 1,
          "textG", 0.82,
          "textB", 0,
          "text2R", 1,
          "text2G", 0.82,
          "text2B", 0,
          "text3R", 1,
          "text3G", 0.82,
          "text3B", 0,
          "text4R", 1,
          "text4G", 0.82,
          "text4B", 0,
          "text5R", 1,
          "text5G", 0.82,
          "text5B", 0
        )
        
        -- Build list of players who rolled
        local players = {}
        for playerName, _ in pairs(currentRoll.bids) do
          table.insert(players, playerName)
        end
        
        -- Sort by roll value descending
        table.sort(players, function(a, b)
          local rollA = currentRoll.bids[a] or 0
          local rollB = currentRoll.bids[b] or 0
          return rollA > rollB
        end)
        
        -- Display each player
        for _, playerName in ipairs(players) do
          local rollValue = currentRoll.bids[playerName]
          local hasSR = HasSR(playerName, currentRoll.srlist)
          local isWinner = currentRoll.winner == playerName
          
          -- Determine expected range based on SR
          local expected = hasSR and "SR" or "MS"
          
          -- Result
          local result = rollValue and tostring(rollValue) or "-"
          
          -- Winner marker
          local winnerMark = isWinner and "✓" or ""
          
          -- Colors
          local r, g, b = 1, 1, 1
          if isWinner then
            r, g, b = 0, 1, 0  -- Green for winner
          elseif hasSR then
            r, g, b = 1, 0.5, 0  -- Orange for SR
          end
          
          T:AddLine(
            "text", playerName,
            "text2", expected,
            "text3", "Roll",
            "text4", result,
            "text5", winnerMark,
            "textR", r,
            "textG", g,
            "textB", b,
            "text2R", r,
            "text2G", g,
            "text2B", b,
            "text3R", r,
            "text3G", g,
            "text3B", b,
            "text4R", r,
            "text4G", g,
            "text4B", b,
            "text5R", r,
            "text5G", g,
            "text5B", b,
            "func", function()
              if IsAdminAndMLOrRLWhenNoML() then
                -- Toggle winner on click
                if currentRoll.winner == playerName then
                  GuildRoll:SetWinnerForItem(nil)
                else
                  GuildRoll:SetWinnerForItem(playerName)
                end
              end
            end
          )
        end
      end,
      "showTitleWhenDetached", true,
      "cantAttach", true,
      "menu", function(level, value)
        if level == 1 then
          -- Start Rolls action
          D:AddLine(
            "text", "Start Rolls",
            "tooltipTitle", "Start Rolls",
            "tooltipText", "Announce start rolling for this item",
            "checked", false,
            "func", function()
              if GuildRoll._RollingTable_currentRoll then
                local currentRoll = GuildRoll._RollingTable_currentRoll
                if currentRoll.itemLink and GuildRoll.AnnounceStartRollingFor then
                  pcall(function()
                    GuildRoll:AnnounceStartRollingFor(currentRoll.itemLink, currentRoll.itemID)
                    currentRoll.started = true
                  end)
                end
              end
            end,
            "disabled", not IsAdminAndMLOrRLWhenNoML() or not GuildRoll._RollingTable_currentRoll
          )
          
          -- Clear Winner action
          D:AddLine(
            "text", "Clear Winner",
            "tooltipTitle", "Clear Winner",
            "tooltipText", "Clear the current winner selection",
            "checked", false,
            "func", function()
              GuildRoll:SetWinnerForItem(nil)
            end,
            "disabled", not IsAdminAndMLOrRLWhenNoML() or not GuildRoll._RollingTable_currentRoll or not GuildRoll._RollingTable_currentRoll.winner
          )
          
          -- Close Session action
          D:AddLine(
            "text", "Close Session",
            "tooltipTitle", "Close Session",
            "tooltipText", "Close the current roll session",
            "checked", false,
            "func", function()
              GuildRoll:CloseRollSession()
            end,
            "disabled", not IsAdminAndMLOrRLWhenNoML() or not GuildRoll._RollingTable_currentRoll
          )
        end
      end
    )
  end)
end

-- Toggle function for RollingTable
function GuildRoll_RollingTable:Toggle()
  if T then
    pcall(function()
      if T:IsAttached("RollingTable") then
        T:Detach("RollingTable")
      elseif T:IsRegistered("RollingTable") then
        T:Open("RollingTable")
      end
    end)
  end
end
