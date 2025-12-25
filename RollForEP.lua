-- RollForEP.lua
-- Module for managing loot roll sessions visible only to master looter admin

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

-- Initialize SavedVariable
GuildRoll_rollForEPCache = GuildRoll_rollForEPCache or {
  lastImport = nil,  -- {timestamp, srData}
  sessions = {}      -- Historical sessions
}

-- Constants
local RECENT_RAID_CACHE_SECONDS = 3
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

-- Module state
local RollForEP = {
  currentLoot = nil,  -- Current session: {itemLink, rolls={}, systemRolls={}, humanAnnounces={}, startTime, closed}
  enabled = false,
  lastMLCheck = 0,
  isMasterLooter = false,
  srData = {}  -- Imported SR data: {playerName = {sr=count, weeks=count}}
}

-- Helper: Strip realm suffix from player name
local function StripRealm(name)
  if not name then return nil end
  return string.gsub(name, "%-[^%-]+$", "")
end

-- Helper: Check if local player is master looter
local function IsMasterLooter()
  local now = GetTime()
  if now - RollForEP.lastMLCheck < 1 then
    return RollForEP.isMasterLooter
  end
  
  RollForEP.lastMLCheck = now
  local method, partyIndex, raidIndex = GetLootMethod()
  
  if method ~= "master" then
    RollForEP.isMasterLooter = false
    return false
  end
  
  local playerName = StripRealm(UnitName("player"))
  
  -- Check if in raid
  if GetNumRaidMembers() > 0 then
    if raidIndex and raidIndex > 0 then
      local mlName = StripRealm(UnitName("raid" .. raidIndex))
      RollForEP.isMasterLooter = (mlName == playerName)
      return RollForEP.isMasterLooter
    end
  elseif GetNumPartyMembers() > 0 then
    if partyIndex and partyIndex > 0 then
      local mlName = StripRealm(UnitName("party" .. partyIndex))
      RollForEP.isMasterLooter = (mlName == playerName)
      return RollForEP.isMasterLooter
    elseif partyIndex == 0 then
      RollForEP.isMasterLooter = true
      return true
    end
  end
  
  RollForEP.isMasterLooter = false
  return false
end

-- Helper: Check if local player can use RollForEP (master looter AND admin)
local function CanUseRollForEP()
  if not GuildRoll or not GuildRoll.IsAdmin then
    return false
  end
  
  local isAdmin = false
  local ok, result = pcall(function() return GuildRoll:IsAdmin() end)
  if ok and result then
    isAdmin = true
  end
  
  return isAdmin and IsMasterLooter()
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
-- Returns: rollType, announcedEP, minVal, maxVal, srWeeks
local function ParseHumanAnnounce(msg, systemMin, systemMax)
  if not msg then return nil end
  
  msg = string.lower(msg)
  
  -- CSR pattern: "cumulative sr" with weeks and EP
  -- Example: "I rolled Cumulative SR 179 - 278 with 48 EP + 100 from SR +30 for 4 consecutive weeks"
  local csrMatch = string.match(msg, "cumulative%s+sr")
  if csrMatch then
    local weeks = tonumber(string.match(msg, "(%d+)%s+consecutive%s+weeks?"))
    local ep = tonumber(string.match(msg, "with%s+(%d+)%s+ep"))
    local min = tonumber(string.match(msg, "(%d+)%s*%-%s*%d+"))
    local max = tonumber(string.match(msg, "%d+%s*%-%s*(%d+)"))
    return "CSR", ep, min, max, weeks
  end
  
  -- SR pattern: "soft reserve" or just "sr" with EP
  -- Example: "I rolled SR 100 - 200 with 50 EP"
  local srMatch = string.match(msg, "soft%s+reserve") or string.match(msg, "%s+sr%s+") or string.match(msg, "^sr%s+")
  if srMatch then
    local ep = tonumber(string.match(msg, "with%s+(%d+)%s+ep"))
    local min = tonumber(string.match(msg, "(%d+)%s*%-%s*%d+"))
    local max = tonumber(string.match(msg, "%d+%s*%-%s*(%d+)"))
    return "SR", ep, min, max, nil
  end
  
  -- EP/MS pattern: mentions EP explicitly
  -- Example: "I rolled MS 1 - 100 with 50 EP"
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
-- Returns: isValid, rollType, flags
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
    -- These require EP validation
    if not announcedEP then
      return false, "INVALID", flags
    end
    
    local actualEP = GetPlayerEP(playerName)
    if math.abs(actualEP - announcedEP) > 0.5 then
      return false, "INVALID", flags
    end
  elseif rollType == "101" or rollType == "100" or rollType == "99" or rollType == "98" then
    -- Check min >= 1
    if min < 1 then
      return false, "INVALID", flags
    end
    
    -- Check value in range
    if value < min or value > max then
      return false, "INVALID", flags
    end
    
    -- 99 done by alt gets ALT flag (already added above)
  end
  
  return true, rollType, flags
end

-- Helper: Match system roll with human announce
local function MatchRollMessages()
  if not RollForEP.currentLoot then return end
  
  local session = RollForEP.currentLoot
  local now = GetTime()
  
  -- Process unmatched system rolls
  for i, sysRoll in ipairs(session.systemRolls) do
    if not sysRoll.matched then
      local playerName = sysRoll.playerName
      local rollValue = sysRoll.value
      local rollMin = sysRoll.min
      local rollMax = sysRoll.max
      local rollTime = sysRoll.timestamp
      
      -- Look for matching human announce within time window
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
        -- Parse human announce
        rollType, announcedEP, _, _, srWeeks = ParseHumanAnnounce(matchedAnnounce.message, rollMin, rollMax)
        matchedAnnounce.matched = true
      end
      
      -- Fallback: infer from system roll range
      if not rollType then
        rollType = InferRollType(rollMin, rollMax)
      end
      
      -- If we can determine type, create and add entry
      if rollType then
        -- Create entry
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
        
        -- Validate
        local isValid, validatedType, flags = ValidateRoll(entry)
        if not isValid then
          entry.rollType = "INVALID"
        else
          entry.rollType = validatedType
        end
        entry.flags = flags
        
        -- Add to rolls
        table.insert(session.rolls, entry)
      end
      
      -- Mark as matched regardless of whether we could determine type
      sysRoll.matched = true
    end
  end
end

-- Event handler: CHAT_MSG_SYSTEM (system roll messages)
local function OnSystemMessage(msg)
  if not RollForEP.enabled or not RollForEP.currentLoot then return end
  
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
    
    table.insert(RollForEP.currentLoot.systemRolls, entry)
    MatchRollMessages()
  end
end

-- Event handler: CHAT_MSG_RAID and CHAT_MSG_RAID_LEADER (human announces)
local function OnRaidMessage(msg, sender)
  if not RollForEP.enabled or not RollForEP.currentLoot then return end
  
  sender = StripRealm(sender)
  
  -- Check if message contains roll-related keywords
  local lowerMsg = string.lower(msg)
  if string.match(lowerMsg, "roll") or string.match(lowerMsg, "sr") or string.match(lowerMsg, "ep") then
    local entry = {
      playerName = sender,
      message = msg,
      timestamp = GetTime(),
      matched = false
    }
    
    table.insert(RollForEP.currentLoot.humanAnnounces, entry)
    MatchRollMessages()
  end
end

-- UI: Refresh Tablet
local function RefreshTablet()
  if not T:IsRegistered("RollForEP") then
    T:Register("RollForEP",
      "children", function()
        T:SetTitle("RollForEP - Loot Session")
        BuildTablet()
      end,
      "clickable", true,
      "showTitleWhenDetached", true,
      "showHintWhenDetached", true,
      "cantAttach", true,
      "menu", function()
        if GuildRoll and GuildRoll.SafeDewdropAddLine then
          GuildRoll:SafeDewdropAddLine(
            "text", "Close",
            "func", function() 
              pcall(function() T:Close("RollForEP") end)
            end
          )
        else
          D:AddLine(
            "text", "Close",
            "func", function() 
              pcall(function() T:Close("RollForEP") end)
            end
          )
        end
      end
    )
  end
  
  if not T:IsAttached("RollForEP") then
    pcall(function() T:Open("RollForEP") end)
  end
  pcall(function() T:Refresh("RollForEP") end)
end

-- UI: Build Tablet content
function BuildTablet()
  if not RollForEP.currentLoot then
    T:AddLine("text", "No active loot session", "textR", 1, "textG", 0, "textB", 0)
    return
  end
  
  local session = RollForEP.currentLoot
  
  -- Header
  T:AddLine(
    "text", "Item: " .. (session.itemLink or "Unknown"),
    "textR", 1, "textG", 0.82, "textB", 0
  )
  
  T:AddLine(
    "text", "Status: " .. (session.closed and "CLOSED" or "OPEN"),
    "textR", 1, "textG", session.closed and 0 or 1, "textB", 0
  )
  
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
    "text", "Player",
    "text2", "Roll",
    "text3", "Type",
    "text4", "Flags",
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
      "textR4", color.r, "textG4", color.g, "textB4", color.b,
      "func", function()
        -- Give to this player
        RollForEP_GiveToPlayer(roll.playerName)
      end
    )
  end
  
  T:AddLine("text", " ")
  
  -- Actions
  if not session.closed then
    T:AddLine(
      "text", "[Close Roll]",
      "textR", 1, "textG", 0, "textB", 0,
      "func", function()
        RollForEP_CloseRollRequest()
      end
    )
  end
  
  T:AddLine(
    "text", "[Give to DE/Bank]",
    "textR", 0, "textG", 1, "textB", 1,
    "func", function()
      RollForEP_SetDE()
    end
  )
  
  T:AddLine(
    "text", "[Give to Player]",
    "textR", 0, "textG", 1, "textB", 0,
    "func", function()
      ShowPlayerPicker()
    end
  )
end

-- Helper: Show player picker for Give to Player
function ShowPlayerPicker()
  if not RollForEP.currentLoot then return end
  
  -- Build list of raid members (no pets)
  local raidMembers = {}
  local numRaid = GetNumRaidMembers()
  if numRaid > 0 then
    for i = 1, numRaid do
      local name = GetRaidRosterInfo(i)
      if name and not UnitIsUnit("raid" .. i, "pet") then
        table.insert(raidMembers, StripRealm(name))
      end
    end
  end
  
  if #raidMembers == 0 then
    if GuildRoll and GuildRoll.defaultPrint then
      GuildRoll:defaultPrint("No raid members found.")
    end
    return
  end
  
  -- Show picker using Dewdrop
  pcall(function()
    D:Open("RollForEP_PlayerPicker",
      "children", function()
        for _, name in ipairs(raidMembers) do
          if GuildRoll and GuildRoll.SafeDewdropAddLine then
            GuildRoll:SafeDewdropAddLine(
              "text", name,
              "func", function()
                RollForEP_GiveToPlayer(name)
                pcall(function() D:Close() end)
              end
            )
          else
            D:AddLine(
              "text", name,
              "func", function()
                RollForEP_GiveToPlayer(name)
                pcall(function() D:Close() end)
              end
            )
          end
        end
      end
    )
  end)
end

-- API: Import SR data from text
function GuildRoll.RollForEP_ImportFromText(text)
  if not text or text == "" then
    if GuildRoll and GuildRoll.defaultPrint then
      GuildRoll:defaultPrint("No SR data provided.")
    end
    return
  end
  
  -- Parse SR data (simple format: PlayerName:SRCount:Weeks)
  local srData = {}
  for line in string.gmatch(text, "[^\r\n]+") do
    local name, sr, weeks = string.match(line, "([^:]+):(%d+):(%d+)")
    if name and sr then
      name = StripRealm(name)
      srData[name] = {
        sr = tonumber(sr) or 0,
        weeks = tonumber(weeks) or 0
      }
    end
  end
  
  RollForEP.srData = srData
  GuildRoll_rollForEPCache.lastImport = {
    timestamp = time(),
    srData = srData
  }
  
  -- Count SR data entries
  local count = 0
  for _ in pairs(srData) do
    count = count + 1
  end
  
  if GuildRoll and GuildRoll.defaultPrint then
    GuildRoll:defaultPrint(string.format("Imported SR data for %d players.", count))
  end
  
  -- If admin and not master looter, send to master looter
  if not IsMasterLooter() and GuildRoll and GuildRoll.IsAdmin and GuildRoll:IsAdmin() then
    -- Find master looter
    local method, partyIndex, raidIndex = GetLootMethod()
    if method == "master" then
      local mlName = nil
      if GetNumRaidMembers() > 0 and raidIndex then
        mlName = StripRealm(UnitName("raid" .. raidIndex))
      elseif GetNumPartyMembers() > 0 and partyIndex then
        mlName = StripRealm(UnitName("party" .. partyIndex))
      end
      
      if mlName and GuildRoll and GuildRoll.VARS and GuildRoll.VARS.prefix then
        -- Send import command via whisper
        local payload = "IMPORT:" .. text
        SendAddonMessage(GuildRoll.VARS.prefix, payload, "WHISPER", mlName)
      end
    end
  end
end

-- API: Set DE/Bank for current item
function RollForEP_SetDE()
  if not CanUseRollForEP() then
    if GuildRoll and GuildRoll.defaultPrint then
      GuildRoll:defaultPrint("Only master looter admin can use this feature.")
    end
    return
  end
  
  if not RollForEP.currentLoot then
    if GuildRoll and GuildRoll.defaultPrint then
      GuildRoll:defaultPrint("No active loot session.")
    end
    return
  end
  
  local itemLink = RollForEP.currentLoot.itemLink or "Unknown Item"
  
  -- Announce in RAID
  SendChatMessage(string.format("%s (for DE/Bank)", itemLink), "RAID")
  
  -- Try to give loot (would need slot info - simplified here)
  -- GiveMasterLoot(slotIndex, candidateIndex)
  
  if GuildRoll and GuildRoll.defaultPrint then
    GuildRoll:defaultPrint("Item marked for DE/Bank: " .. itemLink)
  end
  
  -- Close session
  RollForEP.currentLoot = nil
  if T and T.IsAttached and T:IsAttached("RollForEP") then
    pcall(function() T:Close("RollForEP") end)
  end
end

-- API: Start roll for item
function RollForEP_StartRollForItem(itemLink)
  if not CanUseRollForEP() then
    if GuildRoll and GuildRoll.defaultPrint then
      GuildRoll:defaultPrint("Only master looter admin can start rolls.")
    end
    return
  end
  
  -- Create new session
  RollForEP.currentLoot = {
    itemLink = itemLink,
    rolls = {},
    systemRolls = {},
    humanAnnounces = {},
    startTime = GetTime(),
    closed = false
  }
  
  RollForEP.enabled = true
  
  -- Announce SR summary in RAID/SAY
  local srCount = 0
  for _ in pairs(RollForEP.srData) do
    srCount = srCount + 1
  end
  local srSummary = "Roll for " .. itemLink .. " - SR data loaded for " .. srCount .. " players."
  SendChatMessage(srSummary, "RAID")
  
  -- Open Tablet
  RefreshTablet()
  
  if GuildRoll and GuildRoll.defaultPrint then
    GuildRoll:defaultPrint("Started roll session for: " .. itemLink)
  end
end

-- API: Close roll request
function RollForEP_CloseRollRequest()
  if not CanUseRollForEP() then
    if GuildRoll and GuildRoll.defaultPrint then
      GuildRoll:defaultPrint("Only master looter admin can close rolls.")
    end
    return
  end
  
  if not RollForEP.currentLoot then
    if GuildRoll and GuildRoll.defaultPrint then
      GuildRoll:defaultPrint("No active loot session.")
    end
    return
  end
  
  RollForEP.currentLoot.closed = true
  
  -- Refresh Tablet
  if T and T.IsAttached and T:IsAttached("RollForEP") then
    RefreshTablet()
  end
  
  if GuildRoll and GuildRoll.defaultPrint then
    GuildRoll:defaultPrint("Roll session closed.")
  end
end

-- API: Give to player
function RollForEP_GiveToPlayer(playerName)
  if not CanUseRollForEP() then
    if GuildRoll and GuildRoll.defaultPrint then
      GuildRoll:defaultPrint("Only master looter admin can give loot.")
    end
    return
  end
  
  if not RollForEP.currentLoot then
    if GuildRoll and GuildRoll.defaultPrint then
      GuildRoll:defaultPrint("No active loot session.")
    end
    return
  end
  
  local itemLink = RollForEP.currentLoot.itemLink or "Unknown Item"
  
  -- Announce in RAID
  SendChatMessage(string.format("%s receives %s", playerName, itemLink), "RAID")
  
  -- Try to give loot (would need slot info - simplified here)
  -- GiveMasterLoot(slotIndex, candidateIndex)
  
  if GuildRoll and GuildRoll.defaultPrint then
    GuildRoll:defaultPrint("Item given to: " .. playerName)
  end
  
  -- Close session
  RollForEP.currentLoot = nil
  if T and T.IsAttached and T:IsAttached("RollForEP") then
    pcall(function() T:Close("RollForEP") end)
  end
end

-- API: Submit roll (for player buttons - future use)
function GuildRoll.RollForEP_SubmitRoll(rollType, value, min, max)
  -- This would be called by player UI buttons
  -- For now, rolls are captured via chat events
end

-- Addon message handler
local function OnAddonMessage(prefix, message, channel, sender)
  if not GuildRoll or not GuildRoll.VARS or prefix ~= GuildRoll.VARS.prefix then return end
  if not IsMasterLooter() then return end
  if not GuildRoll.IsAdmin or not GuildRoll:IsAdmin() then return end
  
  sender = StripRealm(sender)
  
  -- Parse message
  if string.match(message, "^IMPORT:") then
    local text = string.sub(message, 8)
    GuildRoll.RollForEP_ImportFromText(text)
  elseif string.match(message, "^SET_DE$") then
    RollForEP_SetDE()
  elseif string.match(message, "^START:") then
    local itemLink = string.sub(message, 7)
    RollForEP_StartRollForItem(itemLink)
  elseif string.match(message, "^CLOSE$") then
    RollForEP_CloseRollRequest()
  end
end

-- Initialize event handlers
if GuildRoll then
  -- Register events
  GuildRoll:RegisterEvent("CHAT_MSG_SYSTEM", function()
    OnSystemMessage(arg1)
  end)
  
  GuildRoll:RegisterEvent("CHAT_MSG_RAID", function()
    OnRaidMessage(arg1, arg2)
  end)
  
  GuildRoll:RegisterEvent("CHAT_MSG_RAID_LEADER", function()
    OnRaidMessage(arg1, arg2)
  end)
  
  -- Register addon message handler
  GuildRoll:RegisterEvent("CHAT_MSG_ADDON", function()
    OnAddonMessage(arg1, arg2, arg3, arg4)
  end)
  
  -- Load saved SR data
  if GuildRoll_rollForEPCache.lastImport and GuildRoll_rollForEPCache.lastImport.srData then
    RollForEP.srData = GuildRoll_rollForEPCache.lastImport.srData
  end
end
