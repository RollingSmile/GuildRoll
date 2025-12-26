-- RollWithEP.lua
-- Roll management module with enhanced UI and tie-handling for Turtle WoW (WoW 1.12)
-- Master looter or raid leader (when no ML) can manage loot rolls with SR/CSR priority
-- All strings use AceLocale for future localization

-- Guard: Check if required libraries are available
local T, D, C, L
do
  local ok, result = pcall(function() return AceLibrary("Tablet-2.0") end)
  if not ok or not result then return end
  T = result
  
  ok, result = pcall(function() return AceLibrary("Dewdrop-2.0") end)
  if not ok or not result then return end
  D = result
  
  ok, result = pcall(function() return AceLibrary("Crayon-2.0") end)
  if not ok or not result then return end
  C = result
  
  ok, result = pcall(function() return AceLibrary("AceLocale-2.2") end)
  if not ok or not result or type(result.new) ~= "function" then return end
  ok, L = pcall(function() return result:new("guildroll") end)
  if not ok or not L then return end
end

-- Use existing localization from localization.lua
-- RollWithEP-specific strings should be added to localization.lua instead
-- For now, we just use the existing locale instance without registering new translations

-- Wait for GuildRoll table to be initialized before accessing it
-- GuildRoll is created in guildroll.lua which loads after this file
-- We'll initialize VARS in the functions that need them instead of at load time

-- Constants - reuse PRIORITY_MAP from RollForEP concept
local PRIORITY_MAP = {
  CSR = 4,
  SR = 4,
  ["101"] = 4,
  EP = 3,
  ["100"] = 3,
  ["99"] = 1,
  ["98"] = 0,
  INVALID = -1
}

local RECENT_RAID_CACHE_SECONDS = 3

-- Module state
local RollWithEP = {
  currentSession = nil,  -- {itemLink, itemID, itemName, slotIndex, rolls=[], systemRolls=[], humanAnnounces=[], startTime, closed, winner, tieState}
  enabled = false,
  lastMLCheck = 0,
  isMasterLooter = false,
  currentMasterLooter = nil,
  lootSlots = {}  -- Cached loot slots from current loot window
}

-- Helper: Strip realm suffix from player name
local function StripRealm(name)
  if not name then return nil end
  return string.gsub(name, "%-[^%-]+$", "")
end

-- Helper: Check if local player is master looter
local function IsMasterLooter()
  local now = GetTime()
  if now - RollWithEP.lastMLCheck < 1 then
    return RollWithEP.isMasterLooter, RollWithEP.currentMasterLooter
  end
  
  RollWithEP.lastMLCheck = now
  local method, partyIndex, raidIndex = GetLootMethod()
  
  if method ~= "master" then
    RollWithEP.isMasterLooter = false
    RollWithEP.currentMasterLooter = nil
    return false, nil
  end
  
  local playerName = StripRealm(UnitName("player"))
  
  -- Check if in raid
  if GetNumRaidMembers() > 0 then
    if raidIndex and raidIndex > 0 then
      local mlName = StripRealm(UnitName("raid" .. raidIndex))
      RollWithEP.isMasterLooter = (mlName == playerName)
      RollWithEP.currentMasterLooter = mlName
      return RollWithEP.isMasterLooter, mlName
    end
  elseif GetNumPartyMembers() > 0 then
    if partyIndex and partyIndex > 0 then
      local mlName = StripRealm(UnitName("party" .. partyIndex))
      RollWithEP.isMasterLooter = (mlName == playerName)
      RollWithEP.currentMasterLooter = mlName
      return RollWithEP.isMasterLooter, mlName
    elseif partyIndex == 0 then
      RollWithEP.isMasterLooter = true
      RollWithEP.currentMasterLooter = playerName
      return true, playerName
    end
  end
  
  RollWithEP.isMasterLooter = false
  RollWithEP.currentMasterLooter = nil
  return false, nil
end

-- Helper: Check if local player is raid leader
local function IsRaidLeader()
  if GetNumRaidMembers() > 0 then
    return IsRaidLeader and IsRaidLeader() or false
  end
  return false
end

-- Helper: Check if local player can use RollWithEP MODULE features (roll tracking, etc.)
-- Permission: RAID + Admin + Master Loot method + (Master Looter OR Raid Leader when no ML)
local function CanUseRollWithEP()
  if not GuildRoll then
    return false
  end
  
  -- Pre-check 1: Must be in a raid (not party, not solo)
  local ok, numRaidMembers = pcall(GetNumRaidMembers)
  if not ok or not numRaidMembers or numRaidMembers == 0 then
    return false
  end
  
  -- Pre-check 2: Loot method must be Master Loot
  local lootMethod, mlPartyIndex, mlRaidIndex = GetLootMethod()
  if lootMethod ~= "master" then
    return false  -- Must be master loot
  end
  
  -- Pre-check 3: Must be Admin
  if not GuildRoll.IsAdmin then
    return false
  end
  
  local ok, isAdmin = pcall(function() return GuildRoll:IsAdmin() end)
  if not ok or not isAdmin then
    return false
  end
  
  -- Pre-check 4: Must be Master Looter OR Raid Leader
  local isMl = IsMasterLooter()
  local isRl = IsRaidLeader()
  
  if not isMl and not isRl then
    return false
  end
  
  return true
end

-- Helper: Check if can access MENU features (Import CSV, Set DE/Bank)
-- Permission: Admin + InRaid only (no Master Loot requirement)
-- This allows configuration even when not currently managing loot
local function CanUseMenuFeatures()
  if not GuildRoll then
    return false
  end
  
  -- Must be in a raid (not party, not solo)
  local ok, numRaidMembers = pcall(GetNumRaidMembers)
  if not ok or not numRaidMembers or numRaidMembers == 0 then
    return false
  end
  
  -- Must be Admin - check if IsAdmin function exists
  if not GuildRoll.IsAdmin or type(GuildRoll.IsAdmin) ~= "function" then
    return false
  end
  
  local ok, isAdmin = pcall(function() return GuildRoll:IsAdmin() end)
  if not ok or not isAdmin then
    return false
  end
  
  return true
end

-- Helper: Get SR data for an item
-- Returns list of player names who have SR/CSR for the item
local function GetSRListForItem(itemID, itemName)
  local srlist = {}
  local found = {}
  
  -- Check RollForEP module data if available
  if RollForEP and RollForEP.srData then
    -- RollForEP.srData format: {playerName = {sr=count, weeks=count, items=[...]}}
    for playerName, data in pairs(RollForEP.srData) do
      if type(data) == "table" and data.items then
        for _, item in ipairs(data.items) do
          local match = false
          if item.itemID and itemID and tonumber(item.itemID) == tonumber(itemID) then
            match = true
          elseif item.itemName and itemName and item.itemName == itemName then
            match = true
          end
          
          if match then
            local cleanName = StripRealm(playerName)
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
  if table.getn(srlist) == 0 and GuildRoll_rollForEPCache and GuildRoll_rollForEPCache.lastImport then
    local cache = GuildRoll_rollForEPCache.lastImport
    if cache.srData then
      for playerName, data in pairs(cache.srData) do
        if type(data) == "table" and data.items then
          for _, item in ipairs(data.items) do
            local match = false
            if item.itemID and itemID and tonumber(item.itemID) == tonumber(itemID) then
              match = true
            elseif item.itemName and itemName and item.itemName == itemName then
              match = true
            end
            
            if match then
              local cleanName = StripRealm(playerName)
              if cleanName and cleanName ~= "" and not found[cleanName] then
                table.insert(srlist, cleanName)
                found[cleanName] = true
              end
            end
          end
        end
      end
    end
  end
  
  return srlist
end

-- Helper: Get EP for a player
local function GetPlayerEP(playerName)
  if not GuildRoll or not GuildRoll.get_ep_v3 then
    return 0
  end
  
  local name = StripRealm(playerName)
  local ok, ep = pcall(function() return GuildRoll:get_ep_v3(name) end)
  if ok and ep then
    return tonumber(ep) or 0
  end
  return 0
end

-- Helper: Check if player is an alt
local function IsPlayerAlt(playerName)
  if not GuildRoll or not GuildRoll.parseAlt then
    return false
  end
  
  local name = StripRealm(playerName)
  local ok, main = pcall(function() return GuildRoll:parseAlt(name) end)
  if ok and main and type(main) == "string" then
    local mainClean = StripRealm(main)
    if mainClean ~= name then
      return true, mainClean
    end
  end
  return false, nil
end

-- Helper: Parse human announce message for roll details
local function ParseHumanAnnounce(msg, systemMin, systemMax)
  if not msg then return nil end
  
  msg = string.lower(msg)
  
  -- CSR pattern
  local csrMatch = string.match(msg, "cumulative%s+sr") or string.match(msg, "csr")
  if csrMatch then
    local weeks = tonumber(string.match(msg, "(%d+)%s+consecutive%s+weeks?")) or tonumber(string.match(msg, "(%d+)%s+weeks?"))
    local ep = tonumber(string.match(msg, "with%s+(%d+)%s+ep"))
    local min = tonumber(string.match(msg, "(%d+)%s*%-%s*%d+"))
    local max = tonumber(string.match(msg, "%d+%s*%-%s*(%d+)"))
    return "CSR", ep, min, max, weeks
  end
  
  -- SR pattern
  local srMatch = string.match(msg, "soft%s+reserve") or string.match(msg, "%s+sr%s+") or string.match(msg, "^sr%s+")
  if srMatch then
    local ep = tonumber(string.match(msg, "with%s+(%d+)%s+ep"))
    local min = tonumber(string.match(msg, "(%d+)%s*%-%s*%d+"))
    local max = tonumber(string.match(msg, "%d+%s*%-%s*(%d+)"))
    return "SR", ep, min, max, nil
  end
  
  -- EP/MS pattern
  local epMatch = string.match(msg, "with%s+%d+%s+ep") or string.match(msg, "ms")
  if epMatch then
    local ep = tonumber(string.match(msg, "with%s+(%d+)%s+ep"))
    return "EP", ep, systemMin, systemMax, nil
  end
  
  return nil
end

-- Helper: Infer roll type from system roll range
local function InferRollType(min, max)
  if max == 101 and min >= 1 then
    return "101"
  elseif max == 100 and min >= 1 then
    return "100"
  elseif max == 99 and min >= 1 then
    return "99"
  elseif max == 98 and min >= 1 then
    return "98"
  end
  return nil
end

-- Helper: Validate a roll entry
local function ValidateRoll(entry)
  local rollType = entry.rollType
  local playerName = entry.playerName
  local value = entry.value
  local min = entry.min
  local max = entry.max
  local announcedEP = entry.announcedEP
  local flags = {}
  
  -- Check if player is alt
  local isAlt, mainName = IsPlayerAlt(playerName)
  if isAlt then
    table.insert(flags, "ALT")
    if mainName then
      table.insert(flags, "Main:" .. mainName)
    end
  end
  
  -- Validate based on roll type
  if rollType == "CSR" or rollType == "SR" or rollType == "EP" then
    if not announcedEP then
      return false, "INVALID", flags
    end
    
    local actualEP = GetPlayerEP(playerName)
    if math.abs(actualEP - announcedEP) > 0.5 then
      return false, "INVALID", flags
    end
  elseif rollType == "101" or rollType == "100" or rollType == "99" or rollType == "98" then
    if min < 1 then
      return false, "INVALID", flags
    end
    
    if value < min or value > max then
      return false, "INVALID", flags
    end
  end
  
  return true, rollType, flags
end

-- Helper: Match system roll with human announce
local function MatchRollMessages()
  if not RollWithEP.currentSession then return end
  
  local session = RollWithEP.currentSession
  
  -- Process unmatched system rolls
  for i, sysRoll in ipairs(session.systemRolls) do
    if not sysRoll.matched then
      local playerName = sysRoll.playerName
      local rollValue = sysRoll.value
      local rollMin = sysRoll.min
      local rollMax = sysRoll.max
      local rollTime = sysRoll.timestamp
      
      -- Look for matching human announce
      local matchedAnnounce = nil
      for j, announce in ipairs(session.humanAnnounces) do
        if not announce.matched and announce.playerName == playerName then
          local timeDiff = math.abs(announce.timestamp - rollTime)
          if timeDiff <= RECENT_RAID_CACHE_SECONDS then
            matchedAnnounce = announce
            break
          end
        end
      end
      
      -- Create roll entry
      local rollType = nil
      local announcedEP = nil
      local srWeeks = nil
      
      if matchedAnnounce then
        rollType, announcedEP, _, _, srWeeks = ParseHumanAnnounce(matchedAnnounce.message, rollMin, rollMax)
        matchedAnnounce.matched = true
      end
      
      -- Fallback: infer from system roll range
      if not rollType then
        rollType = InferRollType(rollMin, rollMax)
      end
      
      if rollType then
        local entry = {
          playerName = playerName,
          value = rollValue,
          min = rollMin,
          max = rollMax,
          rollType = rollType,
          announcedEP = announcedEP,
          srWeeks = srWeeks,
          timestamp = rollTime
        }
        
        local isValid, validatedType, flags = ValidateRoll(entry)
        if not isValid then
          entry.rollType = "INVALID"
        else
          entry.rollType = validatedType
        end
        entry.flags = flags
        
        table.insert(session.rolls, entry)
      end
      
      sysRoll.matched = true
    end
  end
  
  -- Update winner and tie state
  UpdateWinnerAndTieState()
  RefreshTablet()
end

-- Helper: Update winner and tie state
function UpdateWinnerAndTieState()
  if not RollWithEP.currentSession or table.getn(RollWithEP.currentSession.rolls) == 0 then
    RollWithEP.currentSession.winner = nil
    RollWithEP.currentSession.tieState = nil
    return
  end
  
  local session = RollWithEP.currentSession
  
  -- Sort rolls by priority then value
  local sortedRolls = {}
  for _, roll in ipairs(session.rolls) do
    if roll.rollType ~= "INVALID" then
      table.insert(sortedRolls, roll)
    end
  end
  
  table.sort(sortedRolls, function(a, b)
    local priorityA = PRIORITY_MAP[a.rollType] or 0
    local priorityB = PRIORITY_MAP[b.rollType] or 0
    if priorityA ~= priorityB then
      return priorityA > priorityB
    end
    return a.value > b.value
  end)
  
  if table.getn(sortedRolls) == 0 then
    session.winner = nil
    session.tieState = nil
    return
  end
  
  -- Check for tie at top
  local topRoll = sortedRolls[1]
  local topPriority = PRIORITY_MAP[topRoll.rollType] or 0
  local topValue = topRoll.value
  
  local tiedPlayers = {topRoll.playerName}
  for i = 2, table.getn(sortedRolls) do
    local roll = sortedRolls[i]
    local priority = PRIORITY_MAP[roll.rollType] or 0
    if priority == topPriority and roll.value == topValue then
      table.insert(tiedPlayers, roll.playerName)
    else
      break
    end
  end
  
  if table.getn(tiedPlayers) > 1 then
    session.tieState = {
      players = tiedPlayers,
      priority = topPriority,
      value = topValue
    }
    session.winner = "Tie"
  else
    session.winner = topRoll.playerName
    session.tieState = nil
  end
end

-- Event handler: CHAT_MSG_SYSTEM (system roll messages)
local function OnSystemMessage(msg)
  if not RollWithEP.enabled or not RollWithEP.currentSession then return end
  
  -- Parse: "Name rolls N (min-max)"
  local playerName, value, min, max = string.match(msg, "(.+) rolls (%d+) %((%d+)%-(%d+)%)")
  if playerName and value and min and max then
    playerName = StripRealm(playerName)
    value = tonumber(value)
    min = tonumber(min)
    max = tonumber(max)
    
    local entry = {
      playerName = playerName,
      value = value,
      min = min,
      max = max,
      timestamp = GetTime(),
      matched = false
    }
    
    table.insert(RollWithEP.currentSession.systemRolls, entry)
    MatchRollMessages()
  end
end

-- Event handler: CHAT_MSG_RAID and CHAT_MSG_RAID_LEADER (human announces)
local function OnRaidMessage(msg, sender)
  if not RollWithEP.enabled or not RollWithEP.currentSession then return end
  
  sender = StripRealm(sender)
  
  -- Check if message contains roll-related keywords
  local lowerMsg = string.lower(msg)
  if string.match(lowerMsg, "roll") or string.match(lowerMsg, "sr") or string.match(lowerMsg, "ep") or string.match(lowerMsg, "csr") then
    local entry = {
      playerName = sender,
      message = msg,
      timestamp = GetTime(),
      matched = false
    }
    
    table.insert(RollWithEP.currentSession.humanAnnounces, entry)
    MatchRollMessages()
  end
end

-- UI: Refresh Tablet
function RefreshTablet()
  if not T:IsRegistered("RollWithEP") then
    T:Register("RollWithEP",
      "children", function()
        T:SetTitle(L["RollWithEP - Loot Session"])
        BuildTablet()
      end,
      "clickable", true,
      "showTitleWhenDetached", true,
      "showHintWhenDetached", true,
      "cantAttach", true,
      "menu", function()
        if GuildRoll and GuildRoll.SafeDewdropAddLine then
          GuildRoll:SafeDewdropAddLine(
            "text", L["Close"],
            "func", function() 
              pcall(function() T:Close("RollWithEP") end)
            end
          )
        else
          D:AddLine(
            "text", L["Close"],
            "func", function() 
              pcall(function() T:Close("RollWithEP") end)
            end
          )
        end
      end
    )
  end
  
  if not T:IsAttached("RollWithEP") then
    pcall(function() T:Open("RollWithEP") end)
  end
  pcall(function() T:Refresh("RollWithEP") end)
end

-- UI: Build Tablet content
function BuildTablet()
  if not RollWithEP.currentSession then
    T:AddLine("text", L["No active loot session"], "textR", 1, "textG", 0, "textB", 0)
    return
  end
  
  local session = RollWithEP.currentSession
  
  -- Header
  T:AddLine(
    "text", string.format(L["Item: %s"], session.itemLink or "Unknown"),
    "textR", 1, "textG", 0.82, "textB", 0
  )
  
  T:AddLine(
    "text", string.format(L["Status: %s"], session.closed and L["CLOSED"] or L["OPEN"]),
    "textR", 1, "textG", session.closed and 0 or 1, "textB", 0
  )
  
  -- Winner
  if session.winner then
    T:AddLine(
      "text", string.format(L["Winner: %s"], session.winner),
      "textR", 0, "textG", 1, "textB", 1
    )
  end
  
  T:AddLine("text", " ")
  
  -- Sort rolls by priority then value
  local sortedRolls = {}
  for _, roll in ipairs(session.rolls) do
    table.insert(sortedRolls, roll)
  end
  
  table.sort(sortedRolls, function(a, b)
    local priorityA = PRIORITY_MAP[a.rollType] or 0
    local priorityB = PRIORITY_MAP[b.rollType] or 0
    if priorityA ~= priorityB then
      return priorityA > priorityB
    end
    return a.value > b.value
  end)
  
  -- Column headers
  T:AddLine(
    "text", L["Player"],
    "text2", L["Roll"],
    "text3", L["Type"],
    "text4", L["Flags"],
    "textR", 1, "textG", 1, "textB", 1,
    "textR2", 1, "textG2", 1, "textB2", 1,
    "textR3", 1, "textG3", 1, "textB3", 1,
    "textR4", 1, "textG4", 1, "textB4", 1
  )
  
  -- Rolls
  for i, roll in ipairs(sortedRolls) do
    local color = {r = 1, g = 1, b = 1}
    if roll.rollType == "INVALID" then
      color = {r = 1, g = 0, b = 0}
    elseif roll.playerName == session.winner and session.winner ~= "Tie" then
      color = {r = 0, g = 1, b = 0}
    end
    
    local flagsText = table.concat(roll.flags or {}, ", ")
    
    T:AddLine(
      "text", roll.playerName,
      "text2", string.format("%d (%d-%d)", roll.value, roll.min, roll.max),
      "text3", roll.rollType,
      "text4", flagsText,
      "textR", color.r, "textG", color.g, "textB", color.b,
      "textR2", color.r, "textG2", color.g, "textB2", color.b,
      "textR3", color.r, "textG3", color.g, "textB3", color.b,
      "textR4", color.r, "textG4", color.g, "textB4", color.b
    )
  end
  
  T:AddLine("text", " ")
  
  -- Actions
  if not session.closed then
    if session.tieState then
      -- Show Ask Tie Roll button
      T:AddLine(
        "text", "[" .. L["Ask Tie Roll"] .. "]",
        "textR", 1, "textG", 0.5, "textB", 0,
        "func", function()
          RollWithEP_AskTieRoll()
        end
      )
    else
      -- Show Stop Rolls button
      T:AddLine(
        "text", "[" .. L["Stop Rolls"] .. "]",
        "textR", 1, "textG", 0, "textB", 0,
        "func", function()
          RollWithEP_CloseRolls()
        end
      )
    end
  else
    -- Show Give buttons after closed
    if session.winner and session.winner ~= "Tie" then
      T:AddLine(
        "text", "[" .. L["Give to Winner"] .. "]",
        "textR", 0, "textG", 1, "textB", 0,
        "func", function()
          RollWithEP_GiveToWinner()
        end
      )
    end
  end
  
  -- Always show DE/Bank and Give to Player
  T:AddLine(
    "text", "[" .. L["Give to DE/Bank"] .. "]",
    "textR", 0, "textG", 1, "textB", 1,
    "func", function()
      RollWithEP_GiveToDE()
    end
  )
  
  T:AddLine(
    "text", "[" .. L["Give to Player"] .. "]",
    "textR", 0, "textG", 1, "textB", 0,
    "func", function()
      ShowPlayerPicker()
    end
  )
end

-- Helper: Show player picker
function ShowPlayerPicker()
  if not RollWithEP.currentSession then return end
  
  -- Build list of raid members
  local raidMembers = {}
  local numRaid = GetNumRaidMembers()
  if numRaid > 0 then
    for i = 1, numRaid do
      local name = GetRaidRosterInfo(i)
      if name then
        table.insert(raidMembers, StripRealm(name))
      end
    end
  else
    local numParty = GetNumPartyMembers()
    if numParty > 0 then
      table.insert(raidMembers, StripRealm(UnitName("player")))
      for i = 1, numParty do
        local name = UnitName("party" .. i)
        if name then
          table.insert(raidMembers, StripRealm(name))
        end
      end
    end
  end
  
  if table.getn(raidMembers) == 0 then
    if GuildRoll and GuildRoll.defaultPrint then
      GuildRoll:defaultPrint(L["No raid members found."])
    end
    return
  end
  
  -- Show picker using Dewdrop
  pcall(function()
    D:Open("RollWithEP_PlayerPicker",
      "children", function()
        D:AddLine(
          "text", L["Select Player"],
          "isTitle", true
        )
        for _, name in ipairs(raidMembers) do
          if GuildRoll and GuildRoll.SafeDewdropAddLine then
            GuildRoll:SafeDewdropAddLine(
              "text", name,
              "func", function()
                RollWithEP_GiveToPlayer(name)
                pcall(function() D:Close() end)
              end
            )
          else
            D:AddLine(
              "text", name,
              "func", function()
                RollWithEP_GiveToPlayer(name)
                pcall(function() D:Close() end)
              end
            )
          end
        end
      end
    )
  end)
end

-- API: Start roll for item
function RollWithEP_StartRollForItem(itemLink, itemID, itemName, slotIndex)
  if not CanUseRollWithEP() then
    if GuildRoll and GuildRoll.defaultPrint then
      GuildRoll:defaultPrint(L["Only master looter or raid leader admin can use this feature."])
    end
    return
  end
  
  -- Create new session
  RollWithEP.currentSession = {
    itemLink = itemLink,
    itemID = itemID,
    itemName = itemName,
    slotIndex = slotIndex,
    rolls = {},
    systemRolls = {},
    humanAnnounces = {},
    startTime = GetTime(),
    closed = false,
    winner = nil,
    tieState = nil
  }
  
  RollWithEP.enabled = true
  
  -- Get SR list for item
  local srList = GetSRListForItem(itemID, itemName)
  
  -- Determine chat channel
  local channel = "SAY"
  if GetNumRaidMembers() > 0 then
    channel = "RAID"
  end
  
  -- Announce in chat
  local message = string.format(L["Roll for %s"], itemLink)
  if table.getn(srList) > 0 then
    local srNames = table.concat(srList, ", ")
    if table.getn(srList) > 7 then
      srNames = table.concat({srList[1], srList[2], srList[3], srList[4], srList[5], srList[6], srList[7]}, ", ")
      srNames = srNames .. " +" .. (table.getn(srList) - 7) .. " more"
    end
    message = message .. " - " .. string.format(L["SoftReserves: %s"], srNames)
  end
  
  SendChatMessage(message, channel)
  
  -- Open Tablet
  RefreshTablet()
  
  if GuildRoll and GuildRoll.defaultPrint then
    GuildRoll:defaultPrint(string.format(L["Started roll session for: %s"], itemLink))
  end
end

-- API: Close rolls (announce winner and change to Give buttons)
function RollWithEP_CloseRolls()
  if not CanUseRollWithEP() then
    if GuildRoll and GuildRoll.defaultPrint then
      GuildRoll:defaultPrint(L["Only master looter or raid leader admin can use this feature."])
    end
    return
  end
  
  if not RollWithEP.currentSession then
    if GuildRoll and GuildRoll.defaultPrint then
      GuildRoll:defaultPrint(L["No active loot session."])
    end
    return
  end
  
  RollWithEP.currentSession.closed = true
  
  -- Announce winner
  local channel = "SAY"
  if GetNumRaidMembers() > 0 then
    channel = "RAID"
  end
  
  if RollWithEP.currentSession.winner and RollWithEP.currentSession.winner ~= "Tie" then
    local message = string.format(L["Winner: %s"], RollWithEP.currentSession.winner) .. " - " .. RollWithEP.currentSession.itemLink
    SendChatMessage(message, channel)
  end
  
  -- Refresh Tablet
  RefreshTablet()
  
  if GuildRoll and GuildRoll.defaultPrint then
    GuildRoll:defaultPrint(L["Roll session closed."])
  end
end

-- API: Ask tie roll
function RollWithEP_AskTieRoll()
  if not CanUseRollWithEP() then
    return
  end
  
  if not RollWithEP.currentSession or not RollWithEP.currentSession.tieState then
    return
  end
  
  local session = RollWithEP.currentSession
  local tiedPlayers = session.tieState.players
  
  -- Announce tie roll request
  local channel = "SAY"
  if GetNumRaidMembers() > 0 then
    channel = "RAID"
  end
  
  local playerList = table.concat(tiedPlayers, ", ")
  local message = string.format(L["Tie roll for %s - Roll now!"], session.itemLink) .. " (" .. playerList .. ")"
  SendChatMessage(message, channel)
  
  -- Clear current rolls and prepare for tie breaker
  session.rolls = {}
  session.systemRolls = {}
  session.humanAnnounces = {}
  session.tieState = nil
  session.winner = nil
  
  RefreshTablet()
end

-- API: Give to winner
function RollWithEP_GiveToWinner()
  if not CanUseRollWithEP() then
    return
  end
  
  if not RollWithEP.currentSession or not RollWithEP.currentSession.winner or RollWithEP.currentSession.winner == "Tie" then
    return
  end
  
  local winner = RollWithEP.currentSession.winner
  local itemLink = RollWithEP.currentSession.itemLink
  
  -- Show confirmation popup
  StaticPopupDialogs["ROLLWITHEP_CONFIRM_GIVE"] = {
    text = string.format(L["Confirm award %s to %s?"], itemLink, winner),
    button1 = L["Confirm"],
    button2 = L["Cancel"],
    OnAccept = function()
      -- Announce award
      local channel = "SAY"
      if GetNumRaidMembers() > 0 then
        channel = "RAID"
      end
      
      local message = string.format(L["%s receives %s"], winner, itemLink)
      SendChatMessage(message, channel)
      
      -- Integration point for GiveMasterLoot
      -- TODO: Implement GiveMasterLoot(slotIndex, candidateIndex) here when ready
      -- Example: GiveMasterLoot(RollWithEP.currentSession.slotIndex, GetCandidateIndex(winner))
      
      -- Close session
      RollWithEP.currentSession = nil
      RollWithEP.enabled = false
      if T and T.IsAttached and T:IsAttached("RollWithEP") then
        pcall(function() T:Close("RollWithEP") end)
      end
      
      if GuildRoll and GuildRoll.defaultPrint then
        GuildRoll:defaultPrint(string.format(L["Item given to: %s"], winner))
      end
    end,
    OnCancel = function()
      if GuildRoll and GuildRoll.defaultPrint then
        GuildRoll:defaultPrint(L["Award cancelled"])
      end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true
  }
  
  StaticPopup_Show("ROLLWITHEP_CONFIRM_GIVE")
end

-- API: Give to player
function RollWithEP_GiveToPlayer(playerName)
  if not CanUseRollWithEP() then
    return
  end
  
  if not RollWithEP.currentSession then
    return
  end
  
  local itemLink = RollWithEP.currentSession.itemLink
  
  -- Show confirmation popup
  StaticPopupDialogs["ROLLWITHEP_CONFIRM_GIVE_PLAYER"] = {
    text = string.format(L["Confirm award %s to %s?"], itemLink, playerName),
    button1 = L["Confirm"],
    button2 = L["Cancel"],
    OnAccept = function()
      -- Announce award
      local channel = "SAY"
      if GetNumRaidMembers() > 0 then
        channel = "RAID"
      end
      
      local message = string.format(L["%s receives %s"], playerName, itemLink)
      SendChatMessage(message, channel)
      
      -- Integration point for GiveMasterLoot
      -- TODO: Implement GiveMasterLoot(slotIndex, candidateIndex) here when ready
      
      -- Close session
      RollWithEP.currentSession = nil
      RollWithEP.enabled = false
      if T and T.IsAttached and T:IsAttached("RollWithEP") then
        pcall(function() T:Close("RollWithEP") end)
      end
      
      if GuildRoll and GuildRoll.defaultPrint then
        GuildRoll:defaultPrint(string.format(L["Item given to: %s"], playerName))
      end
    end,
    OnCancel = function()
      if GuildRoll and GuildRoll.defaultPrint then
        GuildRoll:defaultPrint(L["Award cancelled"])
      end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true
  }
  
  StaticPopup_Show("ROLLWITHEP_CONFIRM_GIVE_PLAYER")
end

-- API: Give to DE/Bank
function RollWithEP_GiveToDE()
  if not CanUseRollWithEP() then
    return
  end
  
  if not RollWithEP.currentSession then
    return
  end
  
  -- Initialize VARS if needed
  if not GuildRoll.VARS then
    GuildRoll.VARS = {}
  end
  
  -- Check if DE player is set and still online
  local dePlayer = GuildRoll.VARS.lootDE
  local deML = GuildRoll.VARS.lootDE_ML
  local isMl, currentML = IsMasterLooter()
  
  -- Reset DE if ML changed or DE player is offline
  if dePlayer and (deML ~= currentML or not UnitExists(dePlayer)) then
    GuildRoll.VARS.lootDE = nil
    GuildRoll.VARS.lootDE_ML = nil
    dePlayer = nil
  end
  
  -- If no DE set, prompt to select
  if not dePlayer then
    -- Show player picker for DE selection
    local raidMembers = {}
    local numRaid = GetNumRaidMembers()
    if numRaid > 0 then
      for i = 1, numRaid do
        local name = GetRaidRosterInfo(i)
        if name then
          table.insert(raidMembers, StripRealm(name))
        end
      end
    else
      local numParty = GetNumPartyMembers()
      if numParty > 0 then
        table.insert(raidMembers, StripRealm(UnitName("player")))
        for i = 1, numParty do
          local name = UnitName("party" .. i)
          if name then
            table.insert(raidMembers, StripRealm(name))
          end
        end
      end
    end
    
    if table.getn(raidMembers) == 0 then
      if GuildRoll and GuildRoll.defaultPrint then
        GuildRoll:defaultPrint(L["No raid members found."])
      end
      return
    end
    
    -- Show DE picker
    pcall(function()
      D:Open("RollWithEP_DEPicker",
        "children", function()
          D:AddLine(
            "text", L["Select DE/Bank player"],
            "isTitle", true
          )
          for _, name in ipairs(raidMembers) do
            if GuildRoll and GuildRoll.SafeDewdropAddLine then
              GuildRoll:SafeDewdropAddLine(
                "text", name,
                "func", function()
                  -- Set DE player
                  GuildRoll.VARS.lootDE = name
                  GuildRoll.VARS.lootDE_ML = currentML
                  pcall(function() D:Close() end)
                  -- Now give to DE
                  RollWithEP_GiveToDEConfirm(name)
                end
              )
            else
              D:AddLine(
                "text", name,
                "func", function()
                  GuildRoll.VARS.lootDE = name
                  GuildRoll.VARS.lootDE_ML = currentML
                  pcall(function() D:Close() end)
                  RollWithEP_GiveToDEConfirm(name)
                end
              )
            end
          end
        end
      )
    end)
  else
    -- DE player already set, proceed with confirmation
    RollWithEP_GiveToDEConfirm(dePlayer)
  end
end

-- Helper: Confirm DE/Bank assignment
function RollWithEP_GiveToDEConfirm(dePlayer)
  if not RollWithEP.currentSession then
    return
  end
  
  local itemLink = RollWithEP.currentSession.itemLink
  
  StaticPopupDialogs["ROLLWITHEP_CONFIRM_DE"] = {
    text = string.format(L["Confirm award %s to %s?"], itemLink, dePlayer .. " (DE/Bank)"),
    button1 = L["Confirm"],
    button2 = L["Cancel"],
    OnAccept = function()
      -- Announce DE/Bank
      local channel = "SAY"
      if GetNumRaidMembers() > 0 then
        channel = "RAID"
      end
      
      local message = string.format(L["%s (for DE/Bank)"], itemLink)
      SendChatMessage(message, channel)
      
      -- Integration point for GiveMasterLoot
      -- TODO: Implement GiveMasterLoot(slotIndex, candidateIndex) here when ready
      
      -- Close session
      RollWithEP.currentSession = nil
      RollWithEP.enabled = false
      if T and T.IsAttached and T:IsAttached("RollWithEP") then
        pcall(function() T:Close("RollWithEP") end)
      end
      
      if GuildRoll and GuildRoll.defaultPrint then
        GuildRoll:defaultPrint(L["Item marked for DE/Bank"])
      end
    end,
    OnCancel = function()
      if GuildRoll and GuildRoll.defaultPrint then
        GuildRoll:defaultPrint(L["Award cancelled"])
      end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true
  }
  
  StaticPopup_Show("ROLLWITHEP_CONFIRM_DE")
end

-- Addon message handler for GIVE_REQ
local function OnAddonMessage(prefix, message, channel, sender)
  if not GuildRoll or not GuildRoll.VARS or prefix ~= GuildRoll.VARS.prefix then return end
  
  sender = StripRealm(sender)
  
  -- Parse GIVE_REQ messages
  if string.match(message, "^GIVE_REQ:") then
    -- Only process if we are the master looter
    local isMl = IsMasterLooter()
    if not isMl then return end
    
    -- Extract payload: GIVE_REQ:winner:itemLink
    local winner, itemLink = string.match(message, "^GIVE_REQ:([^:]+):(.+)$")
    if winner and itemLink then
      -- Show confirmation popup
      StaticPopupDialogs["ROLLWITHEP_GIVE_REQ"] = {
        text = string.format("Admin %s requests to give %s to %s. Confirm?", sender, itemLink, winner),
        button1 = L["Confirm"],
        button2 = L["Cancel"],
        OnAccept = function()
          -- Send confirmation back
          if GuildRoll.VARS.prefix then
            SendAddonMessage(GuildRoll.VARS.prefix, "GIVE_CONF:" .. winner .. ":" .. itemLink, "WHISPER", sender)
          end
          
          -- Announce
          local ch = "SAY"
          if GetNumRaidMembers() > 0 then
            ch = "RAID"
          end
          SendChatMessage(string.format(L["%s receives %s"], winner, itemLink), ch)
        end,
        OnCancel = function()
          -- Send cancel back
          if GuildRoll.VARS.prefix then
            SendAddonMessage(GuildRoll.VARS.prefix, "GIVE_CANC:" .. winner .. ":" .. itemLink, "WHISPER", sender)
          end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true
      }
      
      StaticPopup_Show("ROLLWITHEP_GIVE_REQ")
    end
  end
end

-- Initialize event handlers
if GuildRoll then
  -- Register events
  pcall(function()
    GuildRoll:RegisterEvent("CHAT_MSG_SYSTEM", function(self, msg)
      OnSystemMessage(msg)
    end)
  end)
  
  pcall(function()
    GuildRoll:RegisterEvent("CHAT_MSG_RAID", function(self, msg, sender)
      OnRaidMessage(msg, sender)
    end)
  end)
  
  pcall(function()
    GuildRoll:RegisterEvent("CHAT_MSG_RAID_LEADER", function(self, msg, sender)
      OnRaidMessage(msg, sender)
    end)
  end)
  
  pcall(function()
    GuildRoll:RegisterEvent("CHAT_MSG_ADDON", function(self, prefix, message, channel, sender)
      OnAddonMessage(prefix, message, channel, sender)
    end)
  end)
end

-- Ensure GuildRoll table exists (since we load before guildroll.lua)
if not GuildRoll then
  GuildRoll = {}
end

-- Public API for integration
GuildRoll.RollWithEP_StartRollForItem = RollWithEP_StartRollForItem

-- API: Show loot UI with item list
-- Called by announce_loot.lua when loot window opens
function GuildRoll.RollWithEP_ShowLootUI(lootItems)
  if not CanUseRollWithEP() then
    return
  end
  
  if not lootItems or table.getn(lootItems) == 0 then
    return
  end
  
  -- Store loot items for contextual menu access
  RollWithEP.lootSlots = lootItems
  
  -- Open Tablet showing loot items
  if not T:IsRegistered("RollWithEP_Loot") then
    T:Register("RollWithEP_Loot",
      "children", function()
        T:SetTitle(L["Loot found:"])
        BuildLootTablet()
      end,
      "clickable", true,
      "showTitleWhenDetached", true,
      "showHintWhenDetached", true,
      "cantAttach", true,
      "menu", function()
        if GuildRoll and GuildRoll.SafeDewdropAddLine then
          GuildRoll:SafeDewdropAddLine(
            "text", L["Close"],
            "func", function() 
              pcall(function() T:Close("RollWithEP_Loot") end)
            end
          )
        else
          D:AddLine(
            "text", L["Close"],
            "func", function() 
              pcall(function() T:Close("RollWithEP_Loot") end)
            end
          )
        end
      end
    )
  end
  
  if not T:IsAttached("RollWithEP_Loot") then
    pcall(function() T:Open("RollWithEP_Loot") end)
  end
  pcall(function() T:Refresh("RollWithEP_Loot") end)
end

-- UI: Build loot tablet
function BuildLootTablet()
  if not RollWithEP.lootSlots or table.getn(RollWithEP.lootSlots) == 0 then
    T:AddLine("text", L["No active loot session"], "textR", 1, "textG", 0, "textB", 0)
    return
  end
  
  -- List each loot item with SR info
  for _, lootItem in ipairs(RollWithEP.lootSlots) do
    local itemLink = lootItem.itemLink
    local itemID = lootItem.itemID
    local itemName = lootItem.itemName
    local slotIndex = lootItem.slot
    
    -- Get SR list
    local srList = GetSRListForItem(itemID, itemName)
    local srText = ""
    if table.getn(srList) > 0 then
      srText = " (SR: " .. table.concat(srList, ", ") .. ")"
      if table.getn(srList) > 5 then
        srText = " (SR: " .. table.concat({srList[1], srList[2], srList[3], srList[4], srList[5]}, ", ") .. " +" .. (table.getn(srList) - 5) .. " more)"
      end
    end
    
    T:AddLine(
      "text", itemLink .. srText,
      "textR", 1, "textG", 0.82, "textB", 0,
      "func", function()
        -- Show contextual menu for this item
        ShowItemContextMenu(itemLink, itemID, itemName, slotIndex)
      end
    )
  end
end

-- Helper: Show contextual menu for an item
function ShowItemContextMenu(itemLink, itemID, itemName, slotIndex)
  pcall(function()
    D:Open("RollWithEP_ItemMenu",
      "children", function()
        D:AddLine(
          "text", L["Start Rolls"],
          "func", function()
            RollWithEP_StartRollForItem(itemLink, itemID, itemName, slotIndex)
            pcall(function() D:Close() end)
          end
        )
        D:AddLine(
          "text", L["Give to DE/Bank"],
          "func", function()
            -- Create a temporary session for DE/Bank only
            RollWithEP.currentSession = {
              itemLink = itemLink,
              itemID = itemID,
              itemName = itemName,
              slotIndex = slotIndex,
              rolls = {},
              systemRolls = {},
              humanAnnounces = {},
              startTime = GetTime(),
              closed = true,
              winner = nil,
              tieState = nil
            }
            RollWithEP_GiveToDE()
            pcall(function() D:Close() end)
          end
        )
        D:AddLine(
          "text", L["Give to Player"],
          "func", function()
            -- Create a temporary session for Give to Player only
            RollWithEP.currentSession = {
              itemLink = itemLink,
              itemID = itemID,
              itemName = itemName,
              slotIndex = slotIndex,
              rolls = {},
              systemRolls = {},
              humanAnnounces = {},
              startTime = GetTime(),
              closed = true,
              winner = nil,
              tieState = nil
            }
            ShowPlayerPicker()
            pcall(function() D:Close() end)
          end
        )
      end
    )
  end)
end

-- ============================================================================
-- Public API Exposure
-- ============================================================================

-- Expose menu permission check (Admin + InRaid only)
-- NOTE: This must be exposed early so guildroll.lua's buildMenu() can reference it
if GuildRoll then
  function GuildRoll.RollWithEP_CanUse()
    -- Always print debug to help diagnose
    local numRaid = 0
    local isAdmin = false
    local hasIsAdminFunc = false
    
    pcall(function()
      numRaid = GetNumRaidMembers() or 0
    end)
    
    if GuildRoll.IsAdmin and type(GuildRoll.IsAdmin) == "function" then
      hasIsAdminFunc = true
      pcall(function()
        isAdmin = GuildRoll:IsAdmin() or false
      end)
    end
    
    local result = CanUseMenuFeatures()
    
    -- Always print debug to console when menu opens
    if GuildRoll.defaultPrint then
      pcall(function()
        GuildRoll:defaultPrint(string.format("[RollWithEP Debug] CanUse=%s | InRaid=%d | IsAdmin=%s | HasFunc=%s", 
          tostring(result), numRaid, tostring(isAdmin), tostring(hasIsAdminFunc)))
      end)
    end
    
    return result
  end
end

-- Expose CSV import function (uses menu permissions)
function GuildRoll.RollWithEP_ImportCSV(csvData)
  if not CanUseMenuFeatures() then
    if GuildRoll and GuildRoll.defaultPrint then
      GuildRoll:defaultPrint(L["You don't have permission to import CSV."])
    end
    return false
  end
  
  if not csvData or csvData == "" then
    if GuildRoll and GuildRoll.defaultPrint then
      GuildRoll:defaultPrint(L["No CSV data provided."])
    end
    return false
  end
  
  -- Initialize cache if needed
  if not GuildRoll_rollForEPCache then
    GuildRoll_rollForEPCache = {}
  end
  
  -- Parse CSV data
  local ok, result = pcall(function()
    local srData = {}
    local playerCount = 0
    
    -- Parse CSV line by line
    for line in string.gmatch(csvData .. "\n", "(.-)\n") do
      -- Skip empty lines and header
      if line and line ~= "" and not string.find(line, "^Player,") then
        -- Parse CSV line: Player,ItemID,ItemName,Week
        local player, itemID, itemName, week = string.match(line, "^([^,]+),([^,]*),([^,]*),([^,]*)$")
        
        if player and player ~= "" then
          -- Strip realm suffix
          player = StripRealm(player)
          
          -- Initialize player if needed
          if not srData[player] then
            srData[player] = {
              sr = 0,
              weeks = {},
              items = {}
            }
            playerCount = playerCount + 1
          end
          
          -- Add item to player's SR list
          local item = {
            itemID = itemID and itemID ~= "" and tonumber(itemID) or nil,
            itemName = itemName and itemName ~= "" and itemName or nil,
            week = week and week ~= "" and tonumber(week) or nil
          }
          
          table.insert(srData[player].items, item)
          srData[player].sr = srData[player].sr + 1
          
          -- Track week if provided
          if item.week and not srData[player].weeks[item.week] then
            srData[player].weeks[item.week] = true
          end
        end
      end
    end
    
    -- Store in cache
    GuildRoll_rollForEPCache.lastImport = {
      srData = srData,
      timestamp = time(),
      playerCount = playerCount
    }
    
    -- Also expose in RollForEP module if available
    if RollForEP then
      RollForEP.srData = srData
    end
    
    return playerCount
  end)
  
  if ok and result then
    if GuildRoll and GuildRoll.defaultPrint then
      GuildRoll:defaultPrint(string.format(L["CSV imported successfully! %d players with soft reserves."], result))
    end
    return true
  else
    if GuildRoll and GuildRoll.defaultPrint then
      GuildRoll:defaultPrint(L["Failed to parse CSV. Please check format."])
    end
    return false
  end
end

-- Expose Set DE/Bank function (uses menu permissions)
function GuildRoll.RollWithEP_SetDEBank(playerName)
  if not CanUseMenuFeatures() then
    if GuildRoll and GuildRoll.defaultPrint then
      GuildRoll:defaultPrint(L["You don't have permission to set DE/Bank player."])
    end
    return
  end
  
  if not GuildRoll.VARS then
    GuildRoll.VARS = {}
  end
  
  if playerName and playerName ~= "" then
    GuildRoll.VARS.lootDE = StripRealm(playerName)
    GuildRoll.VARS.lootDE_ML = StripRealm(UnitName("player"))
    if GuildRoll and GuildRoll.defaultPrint then
      GuildRoll:defaultPrint(string.format(L["DE/Bank player set to: %s"], GuildRoll.VARS.lootDE))
    end
  else
    GuildRoll.VARS.lootDE = nil
    GuildRoll.VARS.lootDE_ML = nil
    if GuildRoll and GuildRoll.defaultPrint then
      GuildRoll:defaultPrint(L["DE/Bank player cleared."])
    end
  end
end
