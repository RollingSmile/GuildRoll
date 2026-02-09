-- utils.lua: Utility functions for GuildRoll
-- Contains helper functions for string manipulation, numeric operations, and member verification

-- ========================================================================
-- LIBRARY IMPORTS
-- ========================================================================

-- Import Ace libraries needed by utility functions
local C = AceLibrary("Crayon-2.0")      -- Chat color formatting
local BC = AceLibrary("Babble-Class-2.2") -- Class name translations
local BZ = AceLibrary("Babble-Zone-2.2") -- Zone name translations
local L = AceLibrary("AceLocale-2.2"):new("guildroll") -- Localization

-- ========================================================================
-- LOCAL VARIABLES
-- ========================================================================

-- Output format string for chat messages
local out = "|cff9664c8guildroll:|r %s"

-- ========================================================================
-- GLOBAL CONSTANTS AND TABLES
-- ========================================================================

-- Initialize global tables for raid/party units and item quality colors
-- These must be initialized before they are used
local partyUnit = {}
local raidUnit = {}
local hexColorQuality = {}

-- Initialize raid and party unit arrays
for i=1,40 do
  raidUnit[i] = "raid"..i
end
for i=1,4 do
  partyUnit[i] = "party"..i
end

-- Initialize item quality color mapping
-- This requires ITEM_QUALITY_COLORS to be defined by the game client
if ITEM_QUALITY_COLORS then
  for i=-1,6 do
    if ITEM_QUALITY_COLORS[i] and ITEM_QUALITY_COLORS[i].hex then
      hexColorQuality[ITEM_QUALITY_COLORS[i].hex] = i
    end
  end
end

-- RaidKey mapping table (will be initialized with localized strings in guildroll.lua)
-- This is a forward declaration; actual values set after localization loads
RaidKey = {}

-- ========================================================================
-- MATH UTILITIES
-- ========================================================================

-- Math utility: Round number to nearest integer
function GuildRoll:num_round(i)
  return math.floor(i+0.5)
end

-- String utility: Split string by delimiter, returns multiple values
function GuildRoll:strsplit(delimiter, subject)
  local delimiter, fields = delimiter or ":", {}
  local pattern = string.format("([^%s]+)", delimiter)
  string.gsub(subject, pattern, function(c) fields[table.getn(fields)+1] = c end)
  return unpack(fields)
end

-- String utility: Split string by delimiter, returns table
function GuildRoll:strsplitT(delimiter, subject)
  local tbl = {GuildRoll:strsplit(delimiter, subject)}
  return tbl
end

-- String utility: Convert word to CamelCase
function GuildRoll:camelCase(word)
  return string.gsub(word,"(%a)([%w_']*)",function(head,tail) 
    return string.format("%s%s",string.upper(head),string.lower(tail)) 
  end)
end

-- Version parsing utility: Compare addon versions
function GuildRoll:parseVersion(version,otherVersion)
  if version then  
    if not GuildRoll._version then
      GuildRoll._version = {  
        major = 0,
        minor = 0,
        patch = 0
      }
    end
    for major,minor,patch in string.gfind(version,"(%d+)[^%d]?(%d*)[^%d]?(%d*)") do
      GuildRoll._version.major = tonumber(major)
      GuildRoll._version.minor = tonumber(minor)
      GuildRoll._version.patch = tonumber(patch)
    end
  end
  if (otherVersion) then
    if not GuildRoll._otherversion then GuildRoll._otherversion = {} end
    for major,minor,patch in string.gfind(otherVersion,"(%d+)[^%d]?(%d*)[^%d]?(%d*)") do
      GuildRoll._otherversion.major = tonumber(major)
      GuildRoll._otherversion.minor = tonumber(minor)
      GuildRoll._otherversion.patch = tonumber(patch)      
    end
    if (GuildRoll._otherversion.major ~= nil and GuildRoll._version ~= nil and GuildRoll._version.major ~= nil) then
      if (GuildRoll._otherversion.major < GuildRoll._version.major) then -- we are newer
        return
      elseif (GuildRoll._otherversion.major > GuildRoll._version.major) then -- they are newer
        return true, "major"        
      else -- tied on major, go minor
        if (GuildRoll._otherversion.minor ~= nil and GuildRoll._version.minor ~= nil) then
          if (GuildRoll._otherversion.minor < GuildRoll._version.minor) then -- we are newer
            return
          elseif (GuildRoll._otherversion.minor > GuildRoll._version.minor) then -- they are newer
            return true, "minor"
          else -- tied on minor, go patch
            if (GuildRoll._otherversion.patch ~= nil and GuildRoll._version.patch ~= nil) then
              if (GuildRoll._otherversion.patch < GuildRoll._version.patch) then -- we are newer
                return
              elseif (GuildRoll._otherversion.patch > GuildRoll._version.patch) then -- they are newer
                return true, "patch"
              end
            elseif (GuildRoll._otherversion.patch ~= nil and GuildRoll._version.patch == nil) then -- they are newer
              return true, "patch"
            end
          end    
        elseif (GuildRoll._otherversion.minor ~= nil and GuildRoll._version.minor == nil) then -- they are newer
          return true, "minor"
        end
      end
    end
  end
end

-- Guild member verification wrapper (with silent flag)
function GuildRoll:verifyGuildMember(name,silent)
  return GuildRoll:verifyGuildMember(name,silent,false)
end

-- Guild member verification: Check if player is in guild and meets requirements
function GuildRoll:verifyGuildMember(name,silent,ignorelevel)
  for i=1,GetNumGuildMembers(1) do
    local g_name, g_rank, g_rankIndex, g_level, g_class, g_zone, g_note, g_officernote, g_online = GetGuildRosterInfo(i)
    if (string.lower(name) == string.lower(g_name)) and (ignorelevel or tonumber(g_level) >= GuildRoll.VARS.minlevel) then 
      return g_name, g_class, g_rank, g_officernote
    end
  end
  if (name) and name ~= "" and not (silent) then
    self:defaultPrint(string.format(L["%s not found in the guild or not max level!"],name))
  end
  return
end

-- Raid utility: Check if player is in raid
function GuildRoll:inRaid(name)
  for i=1,GetNumRaidMembers() do
    if name == (UnitName(raidUnit[i])) then
      return true
    end
  end
  return false
end

-- Loot utility: Check if player is loot master
function GuildRoll:lootMaster()
  local method, lootmasterID = GetLootMethod()
  if method == "master" and lootmasterID == 0 then
    return true
  else
    return false
  end
end

-- Table utility: Find element in table
function GuildRoll:TFind(tbl, item)
  if not tbl then return nil end
  for i, v in ipairs(tbl) do
    if v == item then
      return i
    end
  end
  return nil
end

-- String utility: Strip realm/server suffix from player name
-- Example: "PlayerName-RealmName" -> "PlayerName"
-- Pattern %-[^%-]+$ matches a dash followed by any non-dash characters until end of string
-- @param name string|nil The player name to process
-- @return string|nil The name without realm suffix, or nil if input is nil
function GuildRoll:StripRealm(name)
  if not name then return nil end
  return string.gsub(name, "%-[^%-]+$", "")
end

-- Player utility: Get current player's name with fallback
function GuildRoll:GetAdminName()
  return UnitName("player") or "Unknown"
end

-- ========================================================================
-- DEBUG AND PRINT UTILITIES
-- ========================================================================

-- Debug utility: Print debug messages if debug mode is enabled
function GuildRoll:debugPrint(msg)
  if (self.debugchat or GuildRoll.debugchat) then
    local debugchat = self.debugchat or GuildRoll.debugchat
    debugchat:AddMessage(string.format(out,msg))
    self:flashFrame(debugchat)
  else
    self:defaultPrint(msg)
  end
end

-- Print utility: Print message to default channel
function GuildRoll:defaultPrint(msg)
  if not DEFAULT_CHAT_FRAME:IsVisible() then
    FCF_SelectDockFrame(DEFAULT_CHAT_FRAME)
  end
  DEFAULT_CHAT_FRAME:AddMessage(string.format(out,msg))
end

-- Say utility: Simple say message
function GuildRoll:simpleSay(msg)
  SendChatMessage(string.format("guildroll: %s",msg), GuildRoll_saychannel)
end

-- Admin utility: Send message to admin channel
function GuildRoll:adminSay(msg)
  -- API is broken on Elysium
  -- local g_listen, g_speak, officer_listen, officer_speak, g_promote, g_demote, g_invite, g_remove, set_gmotd, set_publicnote, view_officernote, edit_officernote, set_guildinfo = GuildControlGetRankFlags() 
  -- if (officer_speak) then
  SendChatMessage(string.format("guildroll: %s",msg),"OFFICER")
  -- end
end

-- ========================================================================
-- ADMIN AND PERMISSION CHECKS
-- ========================================================================

-- Admin check: Return true if player can edit officer notes
function GuildRoll:IsAdmin()
  -- Try CanEditOfficerNote first (wrapped in pcall)
  if CanEditOfficerNote then
    local ok, result = pcall(function() return CanEditOfficerNote() end)
    if ok and result then
      return true
    end
  end

  -- Fallback to IsGuildLeader (wrapped in pcall)
  if IsGuildLeader then
    local ok, result = pcall(function() return IsGuildLeader() end)
    if ok and result then
      return true
    end
  end

  -- No local forced override present anymore — only real permissions count
  return false
end

-- ========================================================================
-- NUMERIC UTILITIES
-- ========================================================================

-- Calculate CSR bonus based on input weeks
function GuildRoll:calculateBonus(input)
  local number = tonumber(input)
  if not number or number < 0 or number > 15 then
    return nil  -- Invalid input
  end
  if number == 0 or number == 1 then
    return 0
  end
  -- number is between 2 and 15
  return (number - 1) * GuildRoll.VARS.CSRWeekBonus
end

-- ========================================================================
-- NOTE SANITIZATION
-- ========================================================================

-- Sanitize note to fit within character limit
-- reserve 12 chars for the epgp pattern {xxxxx:yyyy} max public/officernote = 31
local sanitizeNote = function(prefix,epgp,postfix)
  local remainder = string.format("%s%s",prefix,postfix)
  local clip = math.min(31-12,string.len(remainder))
  local prepend = string.sub(remainder,1,clip)
  return string.format("%s%s",prepend,epgp)
end
GuildRoll.sanitizeNote = sanitizeNote

-- ========================================================================
-- ALT/MAIN PARSING
-- ========================================================================

-- Parse alt information from officer note
-- Returns main character name, class, rank, and officer note if found
function GuildRoll:parseAlt(name,officernote)
  if (officernote) then
    local _,_,_,main,_ = string.find(officernote or "","(.*){([%a][%a]%a*)}(.*)")
    if type(main)=="string" and (string.len(main) < 13) then
      main = self:camelCase(main)
      local g_name, g_class, g_rank, g_officernote = self:verifyGuildMember(main)
      if (g_name) then
        return g_name, g_class, g_rank, g_officernote
      else
        return nil
      end
    else
      return nil
    end
  else
    -- Strip realm suffix from input name for comparison
    local nameClean = name and string.gsub(name, "%-[^%-]+$", "") or ""
    
    for i=1,GetNumGuildMembers(1) do
      local g_name, _, _, _, g_class, _, g_note, g_officernote, _, _ = GetGuildRosterInfo(i)
      -- Strip realm suffix from guild member name for comparison
      local g_nameClean = g_name and string.gsub(g_name, "%-[^%-]+$", "") or ""
      
      if (nameClean == g_nameClean) then
        return self:parseAlt(g_name, g_officernote)
      end
    end
  end
  return nil
end

-- Check if current player is an alt and prompt to set main
function GuildRoll:CheckAltAndPromptSetMain()
  -- Safety check: ensure we're in a guild
  if not IsInGuild() then
    return
  end
  
  -- Get player level (prefer UnitLevel, fallback to roster level)
  local playerLevel = UnitLevel("player")
  
  -- Attempt to get guild roster info with pcall for safety
  local success, numMembers = pcall(GetNumGuildMembers, 1)
  if not success or not numMembers or numMembers == 0 then
    -- Roster not available yet
    return
  end
  
  -- Strip realm suffix from player name for comparison
  local playerName = string.gsub(self._playerName, "%-.*$", "")
  
  -- Search for the player in the guild roster
  local playerRank, playerOfficerNote, rosterLevel
  for i = 1, numMembers do
    local success2, name, rank, rankIndex, level, class, zone, note, officernote, online = pcall(GetGuildRosterInfo, i)
    if success2 and name then
      -- Strip realm suffix from roster name
      local rosterName = string.gsub(name, "%-.*$", "")
      if rosterName == playerName then
        playerRank = rank
        playerOfficerNote = officernote or ""
        rosterLevel = level
        break
      end
    end
  end
  
  -- If player not found in roster, exit
  if not playerRank then
    return
  end
  
  -- Use roster level as fallback if UnitLevel didn't work
  if not playerLevel or playerLevel == 0 then
    playerLevel = rosterLevel
  end
  
  -- Check condition 1: rank name equals "Alt" (case-sensitive)
  if playerRank ~= "Alt" then
    return
  end
  
  -- Check condition 2: player level >= 60
  -- Level 60 is the maximum level in Classic WoW
  local levelNum = tonumber(playerLevel) or 0
  if levelNum < 60 then
    return
  end
  
  -- Check condition 3: officer note does NOT contain a main tag {Name}
  -- Pattern {%a%a%a*} matches { followed by at least 2 letters then }
  if string.find(playerOfficerNote, "{%a%a%a*}") then
    return
  end
  
  -- All conditions met: show the prompt
  StaticPopup_Show("GUILDROLL_SET_MAIN_PROMPT")
end

-- ========================================================================
-- ROSTER BUILDING
-- ========================================================================

-- Build roster table from guild members
function GuildRoll:buildRosterTable()
  local g, r = { }, { }
  local numGuildMembers = GetNumGuildMembers(1)
  if (GuildRoll_memberlist_raidonly) and GetNumRaidMembers() > 0 then
    for i = 1, GetNumRaidMembers(true) do
      local name, rank, subgroup, level, class, fileName, zone, online, isDead = GetRaidRosterInfo(i) 
      if (name) then
        r[name] = true
      end
    end
  end
  GuildRoll.alts = {}
  for i = 1, numGuildMembers do
    local member_name,_,_,level,class,_,note,officernote,_,_ = GetGuildRosterInfo(i)
    if member_name and member_name ~= "" then
      local main, main_class, main_rank = self:parseAlt(member_name,officernote)
      local is_raid_level = tonumber(level) and level >= GuildRoll.VARS.minlevel
      if (main) then
        if ((self._playerName) and (member_name == self._playerName)) then
          if (not GuildRoll_main) or (GuildRoll_main and GuildRoll_main ~= main) then
            GuildRoll_main = main
            self:defaultPrint(string.format(L["Your main has been set to %s"],GuildRoll_main))
          end
        end
        main = C:Colorize(BC:GetHexColor(main_class), main)
        GuildRoll.alts[main] = GuildRoll.alts[main] or {}
        GuildRoll.alts[main][member_name] = class
      end
      if (GuildRoll_memberlist_raidonly) and next(r) then
        if r[member_name] and is_raid_level then
          table.insert(g,{["name"]=member_name,["class"]=class})
        end
      else
        if is_raid_level then
          table.insert(g,{["name"]=member_name,["class"]=class})
        end
      end
    end
  end
  return g
end

-- Build class member table for command menu
function GuildRoll:buildClassMemberTable(roster,epgp)
  local desc,usage
  if epgp == "MainStanding" then
    desc = L["Account MainStanding to %s."]
    usage = "<EP>"
  elseif epgp == "AuxStanding" then
    desc = L["Account AuxStanding to %s."]
    usage = "<EP>"
  end
  local c = { }
  for i,member in ipairs(roster) do
    local class,name = member.class, member.name
    if (class) and (c[class] == nil) then
      c[class] = { }
      c[class].type = "group"
      c[class].name = C:Colorize(BC:GetHexColor(class),class)
      c[class].desc = class .. " members"
      c[class].hidden = function() return not (admin()) end
      c[class].args = { }
    end
    if (name) and (c[class].args[name] == nil) then
      c[class].args[name] = { }
      if epgp == "MainStanding" then
        c[class].args[name].type = "execute"
        c[class].args[name].name = name
        c[class].args[name].desc = string.format(desc,name)
        c[class].args[name].func = function() GuildRoll:ShowGiveEPDialog(name) end
      elseif epgp == "AuxStanding" then
        c[class].args[name].type = "text"
        c[class].args[name].name = name
        c[class].args[name].desc = string.format(desc,name)
        c[class].args[name].usage = usage
        c[class].args[name].get = false
        c[class].args[name].set = function(v) GuildRoll:givename_ep(name, tonumber(v)) GuildRoll:refreshPRTablets() end
        c[class].args[name].validate = function(v) 
          local num = tonumber(v)
          return (type(v) == "number" or num) 
            and num >= GuildRoll.VARS.minAward 
            and num <= GuildRoll.VARS.maxAward 
        end
      end
    end
  end
  return c
end

-- ========================================================================
-- RAID/REWARD QUERIES
-- ========================================================================

-- Get reward information based on current zone
function GuildRoll:GetReward()
   local raw = string.gsub(string.gsub(GetGuildInfoText(),"\n","#")," ","")
   local Scores ={}
   local reward = GuildRoll.VARS.baseawardpoints
  for tier in string.gfind(raw,"(B[^:]:[^:]+:[^#]+#)") do
        local _,_,dungeons,rewards = string.find(tier,"B[^:]:([^:]+):([^#]+)#")
        local ds =  GuildRoll:strsplitT(",",dungeons)
        local ss =  GuildRoll:strsplitT(",",rewards)

        for i, key in ipairs(ds) do
		 local n= i
		    if (i>table.getn(ss)) then 
			     n = table.getn(ss)
		    end
		    
		    Scores[key]=ss[n]
           -- DEFAULT_CHAT_FRAME:AddMessage( key .."="..ss[n] )
	    end
         

  end

   

  local isMainStanding = false, zoneEN, zoneLoc,LocKey  
  local inInstance, instanceType = IsInInstance()
  if (inInstance == nil) or (instanceType ~= nil and instanceType == "none") then
        isMainStanding = false
  end
  if (inInstance) then --and (instanceType == "raid") then
    zoneLoc = GetRealZoneText()
   -- DEFAULT_CHAT_FRAME:AddMessage("zoneLoc:"..zoneLoc )
    if (BZ:HasReverseTranslation(zoneLoc)) then
      zoneEN = BZ:GetReverseTranslation(zoneLoc)
     -- DEFAULT_CHAT_FRAME:AddMessage("zoneEN:".. zoneEN)
      if zoneEN then
             if (zoneEN == "Tower of Karazhan") then
                local mapFileName, textureHeight, textureWidth, isMicrodungeon, microDungeonMapName = GetMapInfo();
                if mapFileName == "KarazhanUpper" then
                    zoneEN = "Upper Tower of Karazhan"
                end
            end
        LocKey = RaidKey[zoneEN]
        if LocKey then
          --  DEFAULT_CHAT_FRAME:AddMessage("LocKey:".. LocKey)

            if Scores[LocKey] =="main"then
                reward = 15
            else
                isMainStanding = true
                reward = tonumber (Scores[LocKey])
            end
            if reward then
            --    DEFAULT_CHAT_FRAME:AddMessage("reward:".. reward)
            
            end 
        end 
        end 
    end

    return isMainStanding , reward
  end

end

-- Get raid leader information
function GuildRoll:GetRaidLeader()
  for i = 1, GetNumRaidMembers() do
    local name, rank, _, _, _, _, _, online  = GetRaidRosterInfo(i);
    if (rank == 2) then return i,name,online end
  end
  return ""
end
