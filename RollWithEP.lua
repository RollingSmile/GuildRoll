-- RollWithEP.lua
-- Roll management module with enhanced UI and tie-handling for Turtle WoW (WoW 1.12)
-- Master looter or raid leader (when no ML) can manage loot rolls with SR/CSR priority
-- Strings use AceLocale for localization readiness (do not hardcode UI text)

-- Guard: require libraries, bail out if missing
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

-- Module constants (reuse prioritization idea from legacy)
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
  currentSession = nil, -- session object { itemLink, itemID, itemName, slotIndex, rolls, systemRolls, humanAnnounces, startTime, closed, winner, tieState }
  enabled = false,
  lastMLCheck = 0,
  srData = {}, -- imported SR data (optional): { playerName = { sr = count, weeks = count, items = { {itemID=itemID, itemName=itemName}, ... } } }
  lootSlots = nil,
  -- settings
  _settings = {
    useCustomLootFrame = false,
  }
}

-- Ensure shared cache exists (defensive: core should initialize, but fallback here)
if GuildRoll_rollForEPCache == nil then
  GuildRoll_rollForEPCache = { lastImport = nil, sessions = {} }
end

-- Helper: Strip realm suffix from a player name
local function StripRealm(name)
  if not name then return nil end
  -- Support both localized and plain names; remove "-Realm" if present
  local clean = string.gsub(name, "%-[^%-]+$", "")
  return clean
end

-- Helper: Determine if a given playerName is an alt and return main if found
-- This function consults GuildRoll.parseAlt if available, otherwise heuristics (no-op)
local function IsPlayerAlt(playerName)
  local clean = StripRealm(playerName)
  if not clean then return false, nil end

  if GuildRoll and type(GuildRoll.parseAlt) == "function" then
    local success, main, main_class, main_rank, g_officernote = pcall(function() return GuildRoll:parseAlt(clean) end)
    if success and main then
      return true, main
    end
  end

  return false, nil
end

-- Helper: Get EP for a player using GuildRoll API if available
local function GetPlayerEP(playerName)
  if not GuildRoll or type(GuildRoll.get_ep_v3) ~= "function" then
    return 0
  end
  local ok, ep = pcall(function() return GuildRoll:get_ep_v3(playerName) end)
  if ok and ep then return ep end
  return 0
end

-- Determine whether the local player can use RollWithEP UI/features
local function CanUseRollWithEP()
  -- Must have the GuildRoll table and be in a raid and be admin
  if not GuildRoll then return false end

  local ok, numRaid = pcall(GetNumRaidMembers)
  if not ok or not numRaid or numRaid == 0 then return false end

  if not GuildRoll.IsAdmin or type(GuildRoll.IsAdmin) ~= "function" then return false end
  local ok2, isAdmin = pcall(function() return GuildRoll:IsAdmin() end)
  if not ok2 or not isAdmin then return false end

  -- OK: in raid and admin
  return true
end

-- Helper: iterate SR data structure to find matches for an item
local function iterateSRData(srData, itemID, itemName, srlist, found)
  if not srData then return end
  for playerName, data in pairs(srData) do
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

-- Public helper: get list of players who have SR/CSR for a given item
-- This function prefers RollWithEP.srData, then the shared import cache (GuildRoll_rollForEPCache.lastImport)
local function GetSRListForItem(itemID, itemName)
  local srlist = {}
  local found = {}

  -- 1) Prefer module-local import if present
  if RollWithEP and RollWithEP.srData and next(RollWithEP.srData) then
    iterateSRData(RollWithEP.srData, itemID, itemName, srlist, found)
  end

  -- 2) Fallback to shared cache lastImport (legacy compatibility)
  if table.getn(srlist) == 0 and GuildRoll_rollForEPCache and GuildRoll_rollForEPCache.lastImport and GuildRoll_rollForEPCache.lastImport.srData then
    iterateSRData(GuildRoll_rollForEPCache.lastImport.srData, itemID, itemName, srlist, found)
  end

  return srlist
end

-- Helper: infer roll type based on range (kept for compatibility)
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

-- Helper: validate a roll entry (returns isValid, rollType, flags)
local function ValidateRoll(entry)
  local rollType = entry.rollType
  local playerName = entry.playerName
  local value = entry.value
  local min = entry.min
  local max = entry.max
  local announcedEP = entry.announcedEP
  local flags = {}

  local isAlt, mainName = IsPlayerAlt(playerName)
  if isAlt then
    table.insert(flags, "ALT")
    if mainName then table.insert(flags, "Main:" .. mainName) end
  end

  -- Type inference if not provided
  if not rollType then
    rollType = InferRollType(min, max)
  end

  if rollType == "CSR" or rollType == "SR" or rollType == "EP" then
    if not announcedEP then
      return false, "INVALID", flags
    end
    local actualEP = GetPlayerEP(playerName)
    if math.abs(actualEP - announcedEP) > 0.5 then
      return false, "INVALID", flags
    end
    return true, rollType, flags
  elseif rollType == "101" or rollType == "100" or rollType == "99" or rollType == "98" then
    -- system roll ranges, accept as-is
    return true, rollType, flags
  else
    return false, "INVALID", flags
  end
end

-- Internal: attempt to match system rolls to human announces for open session (keeps compatibility with previous RollForEP design)
local function MatchRollMessages(session)
  if not session then return end
  local now = GetTime()

  -- Process unmatched system rolls and try to match them with human announces in time window
  for i, sysRoll in ipairs(session.systemRolls) do
    if not sysRoll.matched then
      local playerName = sysRoll.playerName
      local rollTime = sysRoll.timestamp

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

      -- Create combined entry
      local entry = {
        playerName = playerName,
        value = sysRoll.value,
        min = sysRoll.min,
        max = sysRoll.max,
        timestamp = sysRoll.timestamp,
        announcedEP = matchedAnnounce and matchedAnnounce.announcedEP or nil,
        srWeeks = matchedAnnounce and matchedAnnounce.srWeeks or nil,
        rollType = nil,
        flags = {},
      }

      -- If we have an announce, mark it matched
      if matchedAnnounce then
        matchedAnnounce.matched = true
        sysRoll.matched = true
      end

      -- Validate entry
      local ok, rtype, flags = pcall(function() return ValidateRoll(entry) end)
      if ok and rtype and rtype ~= "INVALID" then
        entry.rollType = rtype
        entry.flags = flags or {}
        table.insert(session.rolls, entry)
      else
        -- Accept as unknown roll if not valid
        entry.rollType = "INVALID"
        entry.flags = flags or {}
        table.insert(session.rolls, entry)
      end
    end
  end
end

-- Event handler for system message (capturing "Name rolls N (min-max)")
local function OnSystemMessage(msg)
  if not RollWithEP.enabled or not RollWithEP.currentSession then return end

  -- Parse system roll message
  local playerName, value, min, max = string.match(msg, "(.+) rolls (%d+) %((%d+)%-(%d+)%)")
  if playerName and value and min and max then
    playerName = StripRealm(playerName)
    local entry = {
      playerName = playerName,
      value = tonumber(value),
      min = tonumber(min),
      max = tonumber(max),
      timestamp = GetTime(),
      matched = false
    }
    table.insert(RollWithEP.currentSession.systemRolls, entry)
    MatchRollMessages(RollWithEP.currentSession)
  end
end

-- Event handler for raid chat announces (players announcing their roll type, EP etc.)
local function OnRaidMessage(msg, author)
  if not RollWithEP.enabled or not RollWithEP.currentSession then return end
  if not msg or not author then return end

  -- Expected human announce formats (examples): "SR by Name EP:123 weeks:2" or "SR Name {EP}"
  -- Provide flexible parsing but avoid strict dependence on exact old formats.
  local playerName = StripRealm(author)
  -- Basic pattern: expecting "SR" / "CSR" / "EP" followed by EP number optionally
  local rollType, announcedEP, srWeeks = string.match(msg, "^(%a+)%s+EP:?%s*(%d+)%s*weeks:?%s*(%d+)")
  if not rollType then
    rollType = string.match(msg, "^(%a+)")
    announcedEP = tonumber(string.match(msg, "EP:?%s*(%d+)")) or tonumber(string.match(msg, "(%d+)"))
    srWeeks = tonumber(string.match(msg, "weeks:?%s*(%d+)"))
  else
    announcedEP = tonumber(announcedEP)
    srWeeks = tonumber(srWeeks)
  end

  if rollType then
    local announce = {
      playerName = playerName,
      rollType = string.upper(rollType),
      announcedEP = announcedEP,
      srWeeks = srWeeks,
      timestamp = GetTime(),
      matched = false
    }
    table.insert(RollWithEP.currentSession.humanAnnounces, announce)
    MatchRollMessages(RollWithEP.currentSession)
  end
end

-- Start a roll session for an item
function RollWithEP_StartRollForItem(itemLink, itemID, itemName, slotIndex)
  if not CanUseRollWithEP() then
    if GuildRoll and GuildRoll.defaultPrint then
      GuildRoll:defaultPrint(L["Only master looter or raid leader admin can use this feature."])
    end
    return
  end

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

  -- Resolve SR list for the item (module-local SR data or shared cache)
  local srList = GetSRListForItem(itemID, itemName)

  -- Announce SR summary in raid (if any)
  if srList and table.getn(srList) > 0 then
    local srSummary = string.format("%s - SR list loaded for %d players.", itemLink or "Item", table.getn(srList))
    local channel = (GetNumRaidMembers() and GetNumRaidMembers() > 0) and "RAID" or "SAY"
    SendChatMessage(srSummary, channel)
  end

  -- Open tablet for session
  if T and T.Register and not T:IsRegistered("RollWithEP") then
    T:Register("RollWithEP",
      "children", function() T:SetTitle(L["RollWithEP - Loot Session"]); BuildTablet() end,
      "clickable", true,
      "showTitleWhenDetached", true,
      "showHintWhenDetached", true,
      "cantAttach", true,
      "menu", function()
        if GuildRoll and GuildRoll.SafeDewdropAddLine then
          GuildRoll:SafeDewdropAddLine("text", L["Close"], "func", function() pcall(function() T:Close("RollWithEP") end) end)
        else
          D:AddLine("text", L["Close"], "func", function() pcall(function() T:Close("RollWithEP") end) end)
        end
      end
    )
  end

  if T and not T:IsAttached("RollWithEP") then
    pcall(function() T:Open("RollWithEP") end)
  end
  pcall(function() T:Refresh("RollWithEP") end)

  if GuildRoll and GuildRoll.defaultPrint then
    GuildRoll:defaultPrint(string.format(L["Started roll session for: %s"], itemLink or itemName or "Unknown"))
  end
end

-- Close current roll session
local function RollWithEP_CloseRollRequest()
  if not CanUseRollWithEP() then
    if GuildRoll and GuildRoll.defaultPrint then
      GuildRoll:defaultPrint(L["Only master looter or raid leader admin can close rolls."])
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

  if T and T.IsAttached and T:IsAttached("RollWithEP") then
    pcall(function() T:Refresh("RollWithEP") end)
  end

  if GuildRoll and GuildRoll.defaultPrint then
    GuildRoll:defaultPrint(L["Roll session closed."])
  end
end

-- Give item to selected player (announce; master looter must do the actual GiveMasterLoot if desired)
local function RollWithEP_GiveToPlayer(playerName)
  if not CanUseRollWithEP() then
    if GuildRoll and GuildRoll.defaultPrint then
      GuildRoll:defaultPrint(L["Only master looter or raid leader admin can give loot."])
    end
    return
  end

  if not RollWithEP.currentSession then
    if GuildRoll and GuildRoll.defaultPrint then
      GuildRoll:defaultPrint(L["No active loot session."])
    end
    return
  end

  local itemLink = RollWithEP.currentSession.itemLink or "Unknown Item"
  local channel = (GetNumRaidMembers() and GetNumRaidMembers() > 0) and "RAID" or "SAY"
  SendChatMessage(string.format("%s receives %s", playerName, itemLink), channel)

  -- Optionally close session
  RollWithEP.currentSession = nil
  pcall(function() T:Refresh("RollWithEP") end)
end

-- UI: Build Tablet content for current session (simple listing)
function BuildTablet()
  if not RollWithEP.currentSession then
    T:AddLine("text", L["No active session."])
    return
  end

  local session = RollWithEP.currentSession

  -- Header
  T:AddLine("text", string.format(L["Item: %s"], session.itemLink or session.itemName or "Unknown"))

  -- Rolls
  if session.rolls and table.getn(session.rolls) > 0 then
    for _, roll in ipairs(session.rolls) do
      local color = { r = 1, g = 1, b = 1 }
      if roll.rollType == "CSR" or roll.rollType == "SR" then
        color = { r = 0.6, g = 0.9, b = 0.6 }
      elseif roll.rollType == "EP" then
        color = { r = 0.6, g = 0.6, b = 0.9 }
      end

      local flagsText = table.concat(roll.flags or {}, ", ")
      local valueText = roll.value or 0
      T:AddLine(
        "text", roll.playerName,
        "text2", string.format("%d (%d-%d)", valueText, roll.min or 0, roll.max or 0),
        "text3", roll.rollType,
        "text4", flagsText,
        "textR", color.r, "textG", color.g, "textB", color.b,
        "func", function()
          RollWithEP_GiveToPlayer(roll.playerName)
        end
      )
    end
  else
    T:AddLine("text", L["No rolls yet."])
  end

  -- Actions
  if not session.closed then
    T:AddLine("text", " ")
    T:AddLine(
      "text", L["Close Roll"],
      "func", function() RollWithEP_CloseRollRequest() end
    )
  else
    T:AddLine("text", L["Session closed."])
  end
end

-- Register events: chat/system handling
if GuildRoll then
  -- Use pcall wrappers to avoid hard errors if functions are unavailable
  pcall(function()
    GuildRoll:RegisterEvent("CHAT_MSG_SYSTEM", function() OnSystemMessage(arg1) end)
  end)
  pcall(function()
    GuildRoll:RegisterEvent("CHAT_MSG_RAID", function() OnRaidMessage(arg1, arg2) end)
  end)
  pcall(function()
    GuildRoll:RegisterEvent("CHAT_MSG_RAID_LEADER", function() OnRaidMessage(arg1, arg2) end)
  end)
  -- Addon message handler (optional): parse remote commands if needed
  pcall(function()
    GuildRoll:RegisterEvent("CHAT_MSG_ADDON", function(self, prefix, message, channel, sender)
      -- Only handle messages intended for this addon's prefix and intended for roll coordination
      if not message or not prefix then return end
      if not GuildRoll or not GuildRoll.VARS or prefix ~= GuildRoll.VARS.prefix then return end
      -- simple parsing examples:
      if message == "ROLL_WITH_EP_CLOSE" then
        if CanUseRollWithEP() then RollWithEP_CloseRollRequest() end
      end
    end)
  end)
end

-- Public API exposure for integration with other parts of the addon
if not GuildRoll then GuildRoll = {} end
GuildRoll.RollWithEP_StartRollForItem = RollWithEP_StartRollForItem
GuildRoll.RollWithEP_ShowLootUI = function(lootItems)
  -- Called by announce_loot or external modules when loot window opens
  if not CanUseRollWithEP() then return end
  if not lootItems or table.getn(lootItems) == 0 then return end
  RollWithEP.lootSlots = lootItems

  if not T:IsRegistered("RollWithEP_Loot") then
    T:Register("RollWithEP_Loot",
      "children", function() T:SetTitle(L["Loot found:"]); BuildLootTablet() end,
      "clickable", true,
      "showTitleWhenDetached", true,
      "showHintWhenDetached", true,
      "cantAttach", true,
      "menu", function()
        if GuildRoll and GuildRoll.SafeDewdropAddLine then
          GuildRoll:SafeDewdropAddLine("text", L["Close"], "func", function() pcall(function() T:Close("RollWithEP_Loot") end) end)
        else
          D:AddLine("text", L["Close"], "func", function() pcall(function() T:Close("RollWithEP_Loot") end) end)
        end
      end
    )
  end

  if not T:IsAttached("RollWithEP_Loot") then
    pcall(function() T:Open("RollWithEP_Loot") end)
  end
  pcall(function() T:Refresh("RollWithEP_Loot") end)
end

-- Build loot tablet for RollWithEP_ShowLootUI
function BuildLootTablet()
  if not RollWithEP.lootSlots or table.getn(RollWithEP.lootSlots) == 0 then
    T:AddLine("text", L["No loot available."])
    return
  end

  for _, slot in ipairs(RollWithEP.lootSlots) do
    local itemLink = slot.itemLink or slot.link or "Unknown"
    local itemID = slot.itemID or nil
    local itemName = slot.itemName or nil
    T:AddLine(
      "text", itemLink,
      "func", function()
        -- Start roll for this specific item (slotIndex optional)
        RollWithEP_StartRollForItem(itemLink, itemID, itemName, slot.slotIndex)
      end
    )
  end
end

-- Export helper functions for debugging and compatibility
RollWithEP.GetSRListForItem = GetSRListForItem
RollWithEP.GetPlayerEP = GetPlayerEP
RollWithEP.ValidateRoll = ValidateRoll
RollWithEP.StartRollForItem = RollWithEP_StartRollForItem
RollWithEP.CloseRoll = RollWithEP_CloseRollRequest
RollWithEP.GiveToPlayer = RollWithEP_GiveToPlayer

-- Expose module globally for debugging (non-persistent)
_G["RollWithEP"] = RollWithEP

-- End of RollWithEP.lua
