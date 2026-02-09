-- epgp.lua: EP/GP system for GuildRoll
-- Contains all EP/GP-related logic including:
-- - Core EP get/set functions (get_ep_v3, update_epgp_v3)
-- - Bulk operations (decay_ep_v3, reset_ep_v3, give_ep_to_raid)
-- - Award functions (give_ep_to_member)
-- - Announce functions (my_epgp, my_epgp_announce)
-- - Export/Import functions (ExportEPCSV, ImportEPCSV)
-- - Main character management (set_main, get_main)

-- Debug: Print when epgp.lua starts loading
local loadOk, loadErr = pcall(function()
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[EPGP] epgp.lua loading...|r")
  end
end)
if not loadOk and DEFAULT_CHAT_FRAME then
  DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[EPGP] Error in initial debug: " .. tostring(loadErr) .. "|r")
end

-- ========================================================================
-- LIBRARY IMPORTS
-- ========================================================================

-- Import Ace libraries needed by EP/GP functions
-- Use the same pattern as other modules (standings.lua, adminlog.lua, etc.)
local L, C
do
  local libraryLoadOk, libraryLoadErr = pcall(function()
    -- Get AceLocale library and create/get locale instance
    local ok, aceLocale = pcall(function() return AceLibrary("AceLocale-2.2") end)
    if ok and aceLocale and type(aceLocale.new) == "function" then
      ok, L = pcall(function() return aceLocale:new("guildroll") end)
      if not ok and DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[EPGP] Error calling aceLocale:new: " .. tostring(L) .. "|r")
        L = nil
      end
    end
    if not L then
      L = {} -- Fallback to empty table if locale fails
      setmetatable(L, {__index = function(t, k) return k end}) -- Return key as value if not found
    end
    
    -- Get Crayon library
    ok, C = pcall(function() return AceLibrary("Crayon-2.0") end)
    if not ok or not C then
      C = {} -- Fallback
      -- Provide stub functions
      C.Colorize = function(color, text) return text end
      C.Green = function(text) return text end
      C.Red = function(text) return text end
    end
  end)
  
  if not libraryLoadOk and DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[EPGP] Error loading libraries: " .. tostring(libraryLoadErr) .. "|r")
    -- Provide fallback values
    if not L then
      L = {}
      setmetatable(L, {__index = function(t, k) return k end})
    end
    if not C then
      C = {}
      C.Colorize = function(color, text) return text end
      C.Green = function(text) return text end
      C.Red = function(text) return text end
    end
  end
end

if DEFAULT_CHAT_FRAME then
  DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[EPGP] Libraries loaded successfully|r")
end

-- ========================================================================
-- CONSTANTS
-- ========================================================================
local MAX_NOTE_LEN = 31
local MIGRATION_THROTTLE_SECONDS = 30
local MIGRATION_AUTO_DELAY_SECONDS = 5

-- Helper: trim public note with tag to ensure it fits within max length
-- existing: current public note
-- tag: tag to append
-- maxlen: maximum allowed length (default MAX_NOTE_LEN)
-- Returns: trimmed note with tag appended
local function _trim_public_with_tag(existing, tag, maxlen)
  maxlen = maxlen or MAX_NOTE_LEN
  existing = existing or ""
  tag = tag or ""
  
  local tagLen = string.len(tag)
  local availableLen = maxlen - tagLen
  
  if availableLen < 0 then
    -- Tag itself is too long; return just the tag truncated
    return string.sub(tag, 1, maxlen)
  end
  
  if string.len(existing) <= availableLen then
    -- Existing note fits; append tag
    return existing .. tag
  else
    -- Trim existing to fit
    return string.sub(existing, 1, availableLen) .. tag
  end
end

-- Helper: insert tag before {EP} pattern in officer note
-- officernote: current officer note
-- tag: tag to insert
-- Returns: new officer note with tag inserted before {EP} pattern
local function _insertTagBeforeEP(officernote, tag)
  -- Ensure inputs are strings
  if type(officernote) ~= "string" then officernote = "" end
  if type(tag) ~= "string" then tag = "" end
  
  -- Return early if tag is empty
  if tag == "" then
    return officernote
  end
  
  -- Remove any existing occurrences of this tag from the officer note
  -- Escape pattern characters in the tag for safe pattern matching
  local escapedTag = string.gsub(tag, "([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
  officernote = string.gsub(officernote, escapedTag, "")
  
  -- Try to find new {EP} pattern first (e.g., {123})
  local _, _, prefix, ep, postfix = string.find(officernote, "^(.-)({%d+})(.*)$")
  
  if ep then
    -- Found new {EP} pattern; insert tag before it
    return prefix .. tag .. ep .. postfix
  end
  
  -- Try to find legacy {EP:GP} pattern (e.g., {123:456})
  _, _, prefix, epgp, postfix = string.find(officernote, "^(.-)({%d+:%d+})(.*)$")
  
  if epgp then
    -- Found legacy pattern; insert tag before it
    return prefix .. tag .. epgp .. postfix
  else
    -- No pattern found; append tag to end
    return officernote .. tag
  end
end

-- Helper: attempt to run main tag migration with throttle check
-- Returns true if migration was attempted, false if throttled
local function _attemptThrottledMigration(self)
  -- Check throttle: don't run more often than once every 30 seconds
  local now = GetTime()
  if self._lastMigrateRun and (now - self._lastMigrateRun) < MIGRATION_THROTTLE_SECONDS then
    return false
  end
  
  -- Set timestamp before attempting to prevent rapid retries on failure
  -- This ensures we don't spam attempts when guild roster isn't available yet
  self._lastMigrateRun = now
  
  -- Verify guild roster is available
  local ok, numMembers = pcall(function()
    if not IsInGuild() then return 0 end
    return GetNumGuildMembers(1) or 0
  end)
  
  if ok and numMembers > 0 then
    -- Run migration
    pcall(function()
      GuildRoll:MovePublicMainTagsToOfficerNotes()
    end)
    return true
  end
  
  return false
end

-- Initialize officer notes to {EP} format
function GuildRoll:init_notes_v3(guild_index,name,officernote)
  local ep = self:get_ep_v3(name,officernote)
  if ep == nil then
    -- Initialize with {EP} format
    local initstring = string.format("{%d}",0)
    local newnote = string.format("%s%s",officernote,initstring)
    -- Remove any legacy {EP:GP} patterns
    newnote = string.gsub(newnote,"(.*)({%d+:%-?%d+})(.*)",function(prefix,tag,postfix)
      return string.format("%s%s",prefix,postfix)
    end)
    -- Ensure new tag fits within note length
    if string.len(newnote) > MAX_NOTE_LEN then
      local tagLen = string.len(initstring)
      local availableLen = MAX_NOTE_LEN - tagLen
      local trimmed = string.sub(officernote, 1, availableLen)
      newnote = trimmed .. initstring
    end
    officernote = newnote
  else
    -- Note already has EP value, ensure proper format
    -- If it has legacy {EP:GP}, convert to {EP}
    local hasLegacy = string.find(officernote,"{%d+:%-?%d+}")
    if hasLegacy then
      -- Convert legacy {EP:GP} to {EP}
      -- Pattern captures: prefix, fullTag, epVal, gpVal, postfix (5 total)
      local _, _, prefix, fullTag, epVal, gpVal, postfix = string.find(officernote, "^(.-)({(%d+):(%-?%d+)})(.*)$")
      if epVal then
        -- Convert to new format
        local newTag = string.format("{%d}", tonumber(epVal))
        local newNote = (prefix or "") .. newTag .. (postfix or "")
        if string.len(newNote) <= MAX_NOTE_LEN then
          officernote = newNote
        end
      end
    end
  end
  GuildRosterSetOfficerNote(guild_index,officernote,true)
  return officernote
end

-- Update EP value in officer note (v3 - EP-only implementation)
function GuildRoll:update_epgp_v3(ep,guild_index,name,officernote,special_action)
  -- EP-only implementation: initialize notes to {EP} format, update EP value
  
  -- Initialize notes if needed (ensures {EP} format)
  officernote = self:init_notes_v3(guild_index,name,officernote)
  
  -- Get previous EP value for logging (after note initialization)
  local prevEP = self:get_ep_v3(name,officernote) or 0
  
  local newnote
  if ep ~= nil then 
    -- Try to match legacy {EP:GP} format first
    local _, _, prefix, fullTag, oldEP, oldGP, postfix = string.find(officernote, "^(.-)({(%d+):(%-?%d+)})(.*)$")
    if oldEP then
      -- Has legacy format - convert to new {EP} format
      newnote = string.gsub(officernote,"(.-)({%d+:%-?%d+})(.*)",function(prefix,tag,postfix)
        return string.format("%s{%d}%s",prefix,ep,postfix)
      end)
    else
      -- Update {EP} format
      newnote = string.gsub(officernote,"(.-)({%d+})(.*)",function(prefix,tag,postfix)
        return string.format("%s{%d}%s",prefix,ep,postfix)
      end)
    end
  end
  
  if newnote then 
    -- Write officer note with pcall for defensiveness
    local success, err = pcall(function()
      GuildRosterSetOfficerNote(guild_index,newnote,true)
    end)
    
    if not success then
      self:debugPrint(string.format("Error updating officer note for %s: %s", name or "unknown", tostring(err)))
    end
    
    -- Add personal logging for EP changes only with compact colorized format
    if ep ~= nil then
      local actor = UnitName("player")
      local changeEP = ep - prevEP
      
      -- Get Crayon library for coloring (with fallback if not available)
      local C
      pcall(function() C = AceLibrary("Crayon-2.0") end)
      
      -- Colorize delta: green for positive, red for negative
      local deltaStr
      if C and changeEP >= 0 then
        deltaStr = C:Green(string.format("+%d", changeEP))
      elseif C then
        deltaStr = C:Red(string.format("%d", changeEP))
      else
        -- Fallback if Crayon not available
        deltaStr = string.format("%+d", changeEP)
      end
      
      -- Build suffix based on special_action
      local suffix = ""
      if special_action == "RAID" then
        suffix = " (Raid)"
      elseif special_action == "DECAY" then
        suffix = " (Decay)"
      end
      
      -- Compact format: EP: Prev -> New (±N) by AdminName[ (Raid)|(Decay)]
      local logMsg = string.format("EP: %d -> %d (%s) by %s%s", prevEP, ep, deltaStr, actor, suffix)
      self:personalLogAdd(name, logMsg)
    end
  end
end

-- Update EP value by player name
function GuildRoll:update_ep_v3(getname,ep)
  for i = 1, GetNumGuildMembers(1) do
    local name, _, _, _, class, _, note, officernote, _, _ = GetGuildRosterInfo(i)
    if (name==getname) then 
      self:update_epgp_v3(ep,i,name,officernote)
    end
  end  
end

-- Get EP value from officer note or by player name
function GuildRoll:get_ep_v3(getname,officernote)
  if (officernote) then
    -- Try new {EP} format first
    local _,_,ep = string.find(officernote,".*{(%d+)}.*")
    if ep then
      return tonumber(ep)
    end
    -- Fall back to legacy {EP:GP} format
    local _,_,ep_legacy = string.find(officernote,".*{(%d+):%-?%d+}.*")
    return tonumber(ep_legacy)
  end
  for i = 1, GetNumGuildMembers(1) do
    local name, _, _, _, class, _, note, officernote, _, _ = GetGuildRosterInfo(i)
    -- Try new {EP} format first
    local _,_,ep = string.find(officernote,".*{(%d+)}.*")
    if ep and (name==getname) then
      return tonumber(ep)
    end
    -- Fall back to legacy {EP:GP} format
    local _,_,ep_legacy = string.find(officernote,".*{(%d+):%-?%d+}.*")
    if (name==getname) then return tonumber(ep_legacy) end
  end
  return
end

-- Debug: Confirm get_ep_v3 was defined
if DEFAULT_CHAT_FRAME then
  DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[EPGP] get_ep_v3 function defined successfully|r")
end


-- MovePublicMainTagsToOfficerNotes: Admin function to migrate main tags from public to officer notes
-- Requires admin permission (GuildRoll:IsAdmin)
-- Iterates through guild roster and moves {MainName} tags from public note to officer note
-- Returns: number of tags moved
function GuildRoll:MovePublicMainTagsToOfficerNotes()
  if not GuildRoll:IsAdmin() then
    self:defaultPrint("You do not have permission to edit officer notes.")
    return 0
  end
  
  local movedCount = 0
  local numMembers = GetNumGuildMembers(1)
  
  -- Validate numMembers is a valid number
  if not numMembers or type(numMembers) ~= "number" or numMembers < 1 then
    return 0
  end
  
  for i = 1, numMembers do
    -- Wrap GetGuildRosterInfo in pcall for safety
    local success, name, r2, r3, r4, r5, r6, publicNote, officerNote, r9, r10 = pcall(function()
      return GetGuildRosterInfo(i)
    end)
    
    -- Process only if GetGuildRosterInfo succeeded and returned valid data
    if success and name then
      publicNote = publicNote or ""
      officerNote = officerNote or ""
      
      -- Ensure publicNote and officerNote are strings
      if type(publicNote) == "string" and type(officerNote) == "string" then
        -- Check if public note contains a main tag pattern {name} (min 2 chars)
        local _, _, mainTag = string.find(publicNote, "({%a%a%a*})")
        if mainTag and type(mainTag) == "string" and string.len(mainTag) > 2 then
          -- Insert main tag before {EP} in officer note first (to avoid data loss)
          local newOfficer = _insertTagBeforeEP(officerNote, mainTag)
          
          -- Validate newOfficer is a string before writing
          if type(newOfficer) == "string" then
            -- Write officer note first (wrapped in pcall for safety)
            local successOfficer = pcall(function()
              GuildRosterSetOfficerNote(i, newOfficer, true)
            end)
            
            -- Only remove from public note if officer note write succeeded
            if successOfficer then
              movedCount = movedCount + 1
              
              -- Escape pattern characters for safe replacement
              local escapedTag = string.gsub(mainTag, "([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
              -- Remove only first occurrence of the main tag from public note
              local newPublic = string.gsub(publicNote, escapedTag, "", 1)
              
              -- Trim leading and trailing whitespace
              newPublic = string.gsub(newPublic, "^%s*(.-)%s*$", "%1")
              
              -- If empty, use a single space to ensure server accepts it
              if newPublic == "" then
                newPublic = " "
              end
              
              -- Attempt to write public note (removal is best-effort)
              pcall(function()
                GuildRosterSetPublicNote(i, newPublic)
              end)
            end
          end
        end
      end
    end
  end
  
  -- Only print summary if at least one tag was moved
  if movedCount > 0 then
    self:defaultPrint(string.format("Migration complete. Moved %d main tags from public to officer notes.", movedCount))
  end
  
  return movedCount
end

-- ========================================================================
-- BULK EP OPERATIONS
-- ========================================================================

-- Award EP to entire raid
function GuildRoll:give_ep_to_raid(ep) -- awards ep to raid members in zone
  -- Validate input
  if type(ep) ~= "number" then
    UIErrorsFrame:AddMessage("Invalid EP value entered.", 1.0, 0.0, 0.0, 1.0)
    return
  end
  if ep < GuildRoll.VARS.minAward or ep > GuildRoll.VARS.maxAward then
    UIErrorsFrame:AddMessage("EP value out of range (" .. GuildRoll.VARS.minAward .. " to " .. GuildRoll.VARS.maxAward .. ")", 1.0, 0.0, 0.0, 1.0)
    return
  end
  
  if GetNumRaidMembers()>0 then
    local award = {}
    local adminName = UnitName("player")
    local raid_data = {
      players = {},
      counts = {},
      alt_sources = {}  -- Track which alt triggered each main's award (main_name -> alt_name mapping)
    }
    
    for i = 1, GetNumRaidMembers(true) do
      local name, rank, subgroup, level, class, fileName, zone, online, isDead = GetRaidRosterInfo(i)
      if level >= GuildRoll.VARS.minlevel then
        local actualName = name
        local actualEP = ep
        local postfix = ""
        local sourceAlt = nil  -- Track if this award came from an alt
        
        -- Handle alt -> main mapping if Altspool enabled
        if (GuildRollAltspool) then
          local main = self:parseAlt(name)
          if (main) then
            local alt = name
            actualName = main
            actualEP = self:num_round(GuildRoll_altpercent*ep)
            postfix = string.format(L[", %s\'s Main."],alt)
            sourceAlt = alt  -- Remember the alt that triggered this award
          end
        end
        
        -- Skip if already awarded in this call (check the actual target name)
        if not GuildRoll:TFind(award, actualName) then
          -- Get old EP and calculate new EP
          local old = (self:get_ep_v3(actualName) or 0)
          local newep = actualEP + old
          
          -- Update EP with special_action="RAID" for local personal log
          for j = 1, GetNumGuildMembers(1) do
            local gname, _, _, _, gclass, _, gnote, gofficernote, _, _ = GetGuildRosterInfo(j)
            if gname == actualName then
              self:update_epgp_v3(newep, j, gname, gofficernote, "RAID")
              break
            end
          end
          
          -- Send addon message to individual player with RAID flag
          local addonMsg = string.format("%s;%s;%s;RAID", actualName, "MainStanding", actualEP)
          self:addonMessage(addonMsg, "GUILD")
          
          -- Add player to raid_data for consolidated log entry
          table.insert(raid_data.players, actualName)
          raid_data.counts[actualName] = {old = old, new = newep}
          if sourceAlt then
            raid_data.alt_sources[actualName] = self:StripRealm(sourceAlt)
          end
          
          table.insert(award, actualName)
        end
      end
    end
    
    -- Create a single consolidated raid entry in AdminLog
    if self:IsAdmin() and table.getn(raid_data.players) > 0 then
      if GuildRoll.AdminLogAddRaid then
        pcall(function()
          GuildRoll:AdminLogAddRaid(ep, raid_data)
        end)
      end
    end
    
    -- Send single public message about raid award
    self:simpleSay(string.format(L["Giving %d MainStanding to all raidmembers"],ep))
    
    -- Immediate UI refresh after raid award
    self:refreshAllEPUI()
  else UIErrorsFrame:AddMessage(L["You aren't in a raid dummy"],1,0,0)end
end

-- Backward-compatible wrapper for award_raid_ep
function GuildRoll:award_raid_ep(ep)
  return self:give_ep_to_raid(ep)
end

-- Award EP to single member
function GuildRoll:give_ep_to_member(getname,ep,block) -- awards ep to a single character
  if not (admin()) then return end

  -- Validate EP value
  if type(ep) ~= "number" then
    self:defaultPrint(L["Invalid EP value entered."])
    return false, getname
  end
  if ep < GuildRoll.VARS.minAward or ep > GuildRoll.VARS.maxAward then
    self:defaultPrint(string.format(L["EP value out of range (%s to %s)"], GuildRoll.VARS.minAward, GuildRoll.VARS.maxAward))
    return false, getname
  end

  -- PUG support removed: do not call self:isPug
  local postfix, alt = ""

  -- Keep alt -> main handling if Altspool is enabled
  if (GuildRollAltspool) then
    local main = self:parseAlt(getname)
    if (main) then
      alt = getname
      getname = main
      ep = self:num_round(GuildRoll_altpercent*ep)
      postfix = string.format(L[", %s\'s Main."],alt)
    end
  end

  if GuildRoll:TFind(block, getname) then
    self:debugPrint(string.format("Skipping %s, already awarded.",getname))
    return false, getname
  end
  local old =  (self:get_ep_v3(getname) or 0)
  local newep = ep + old
  self:update_ep_v3(getname,newep)
  self:debugPrint(string.format(L["Giving %d MainStanding to %s%s. (Previous: %d, New: %d)"],ep,getname,postfix,old, newep))
  
  -- Always announce, log, and send addon message for both positive and negative EP
  local msg
  local logMsg
  
  -- Build compact AdminLog format: PlayerName - EP: Prev -> New (±N)
  local deltaStr
  if ep >= 0 then
    deltaStr = string.format("+%d", ep)
  else
    deltaStr = string.format("%d", ep)
  end
  logMsg = string.format("%s - EP: %d -> %d (%s)", getname, old, newep, deltaStr)
  
  -- Build announcement message
  if ep < 0 then
    msg = string.format(L["%s MainStanding Penalty to %s%s. (Previous: %d, New: %d)"],ep,getname,postfix,old, newep)
  else
    msg = string.format(L["Giving %d MainStanding to %s%s. (Previous: %d, New: %d)"],ep,getname,postfix,old, newep)
  end
  
  self:adminSay(msg)
  self:addToLog(logMsg)
  local addonMsg = string.format("%s;%s;%s",getname,"MainStanding",ep)
  self:addonMessage(addonMsg,"GUILD")
  
  -- Add AdminLog and personal log entries with alt tag if alt-pooling was applied
  if alt then
    -- Alt-pooling was applied: add tagged AdminLog and personal logs
    local altNameClean = self:StripRealm(alt)
    local mainNameClean = self:StripRealm(getname)
    
    -- AdminLog entry: "[GIVE] %d EP given to %s (%s) by %s"
    if self.AdminLogAdd then
      pcall(function()
        local adminLogText = string.format("[GIVE] %d EP given to %s (%s) by %s", ep, mainNameClean, altNameClean, self:GetAdminName())
        self:AdminLogAdd(adminLogText)
      end)
    end
    
    -- Personal log for main: "EP received via alt AltName: +%d EP (Prev: %d, New: %d)"
    if self.personalLogAdd then
      pcall(function()
        local mainLogText = string.format("EP received via alt %s: %s EP (Prev: %d, New: %d)", altNameClean, deltaStr, old, newep)
        self:personalLogAdd(getname, mainLogText)
      end)
    end
    
    -- Personal log for alt: "EP awarded to main MainName (redirect): +%d EP (Prev: %d, New: %d)"
    if self.personalLogAdd then
      pcall(function()
        local altLogText = string.format("EP awarded to main %s (redirect): %s EP (Prev: %d, New: %d)", mainNameClean, deltaStr, old, newep)
        self:personalLogAdd(alt, altLogText)
      end)
    end
  end
  
  -- Immediate UI refresh
  self:refreshAllEPUI()
  
  return false, getname
end

-- Backward-compatible wrappers for givename_ep
function GuildRoll:givename_ep(getname,ep,block)
  return self:give_ep_to_member(getname,ep,block)
end

-- Apply decay to all members
function GuildRoll:decay_ep_v3()
  if not (admin()) then return end
  local memberCount = 0
  for i = 1, GetNumGuildMembers(1) do
    local name,_,_,_,class,_,note,officernote,_,_ = GetGuildRosterInfo(i)
    local prevEP = self:get_ep_v3(name,officernote)
    if (prevEP~=nil) then
      local newEP = self:num_round(prevEP*GuildRoll_decay)
      local changeEP = newEP - prevEP
      self:update_epgp_v3(newEP,i,name,officernote,"DECAY")
      
      -- Send addon message to notify the player of decay
      local addonMsg = string.format("%s;%s;%s;%s",name,"MainStanding",changeEP,"DECAY")
      self:addonMessage(addonMsg,"GUILD")
      
      memberCount = memberCount + 1
    end
  end
  local decayPercent = (1 - (GuildRoll_decay or GuildRoll.VARS.decay)) * 100
  local msg = string.format(L["DecayAnnounce"], decayPercent)
  self:simpleSay(msg)
  if not (GuildRoll_saychannel=="OFFICER") then self:adminSay(msg) end
  local addonMsg = string.format("ALL;DECAY;%s",decayPercent)
  self:addonMessage(addonMsg,"GUILD")
  self:addToLog(msg)
  
  -- Add single AdminLog summary entry for decay
  if self.AdminLogAdd then
    pcall(function()
      local adminLogText = string.format("[DECAY] Applied %.0f%% decay to %d members by %s", decayPercent, memberCount, self:GetAdminName())
      self:AdminLogAdd(adminLogText)
    end)
  end
  
  -- Immediate UI refresh after decay
  self:refreshAllEPUI()
end

-- Reset all EP to 0
function GuildRoll:reset_ep_v3()
  if (IsGuildLeader()) then
    for i = 1, GetNumGuildMembers(1) do
      local name,_,_,_,class,_,note,officernote,_,_ = GetGuildRosterInfo(i)
      local ep = self:get_ep_v3(name,officernote)
      if ep then
        self:update_epgp_v3(0,i,name,officernote)
      end
    end
    local msg = "All EP has been reset to 0."
    self:debugPrint(msg)
    self:adminSay(msg)
    self:addToLog(msg)
    
    -- Add single AdminLog summary entry for reset
    if self.AdminLogAdd then
      pcall(function()
        local adminLogText = string.format("[RESET] Standing reset by %s", self:GetAdminName())
        self:AdminLogAdd(adminLogText)
      end)
    end
    
    -- Immediate UI refresh after reset
    self:refreshAllEPUI()
  end
end

-- Backward-compatible wrapper for ep_reset_v3
function GuildRoll:ep_reset_v3()
  return self:reset_ep_v3()
end

-- ========================================================================
-- EP ANNOUNCE FUNCTIONS
-- ========================================================================

-- Announce player's EP (internal function)
function GuildRoll:my_epgp_announce(use_main)
  local ep
  if (use_main) then
    ep = self:get_ep_v3(GuildRoll_main) or 0
  else
    ep = self:get_ep_v3(self._playerName) or 0
  end
  local msg = string.format(L["You now have: %d MainStanding"], ep)
  self:defaultPrint(msg)
end

-- Announce player's EP (public function)
function GuildRoll:my_epgp(use_main)
  GuildRoster()
  self:ScheduleEvent("guildrollRosterRefresh",self.my_epgp_announce,3,self,use_main)
end

-- ========================================================================
-- MAIN CHARACTER MANAGEMENT
-- ========================================================================

-- Set main character
function GuildRoll:set_main(inputMain)
  if not inputMain or inputMain == "" then
    self:defaultPrint("Usage: /groll setmain <MainCharacterName>")
    return
  end
  
  -- Normalize the input name
  inputMain = self:camelCase(inputMain)
  
  -- Verify the main character exists in guild
  local mainName, mainClass, mainRank, mainOfficerNote = self:verifyGuildMember(inputMain, false, false)
  if not mainName then
    return
  end
  
  -- Set the main character
  GuildRoll_main = mainName
  self:defaultPrint(string.format("Main character set to: %s", mainName))
end

-- Get main character
function GuildRoll:get_main()
  if GuildRoll_main and GuildRoll_main ~= "" then
    return GuildRoll_main
  end
  return nil
end

-- ========================================================================
-- EXPORT/IMPORT FUNCTIONS
-- ========================================================================

-- Export EP standings as CSV
function GuildRoll:ExportEPCSV()
  if not self:IsAdmin() then
    self:defaultPrint("You do not have permission to export EP standings.")
    return
  end
  
  local csv = "Name,Class,EP\n"
  
  for i = 1, GetNumGuildMembers(1) do
    local name, _, _, _, class, _, _, officernote, _, _ = GetGuildRosterInfo(i)
    local ep = self:get_ep_v3(name, officernote) or 0
    csv = csv .. string.format("%s,%s,%d\n", name, class, ep)
  end
  
  return csv
end

-- Import EP standings from CSV
function GuildRoll:ImportEPCSV(text)
  if not self:IsAdmin() then
    self:defaultPrint("You do not have permission to import EP standings.")
    return
  end
  
  if not IsGuildLeader() then
    self:defaultPrint("Only the guild leader can import EP standings.")
    return
  end
  
  if not text or text == "" then
    self:defaultPrint("No CSV data provided.")
    return
  end
  
  local lines = self:strsplitT("\n", text)
  local imported = 0
  
  for i, line in ipairs(lines) do
    -- Skip header line
    if i > 1 and line ~= "" then
      local parts = self:strsplitT(",", line)
      if table.getn(parts) >= 3 then
        local name = parts[1]
        local ep = tonumber(parts[3])
        
        if name and ep then
          -- Find the member in guild roster
          for j = 1, GetNumGuildMembers(1) do
            local gname, _, _, _, _, _, _, gofficernote, _, _ = GetGuildRosterInfo(j)
            if gname == name then
              self:update_epgp_v3(ep, j, gname, gofficernote)
              imported = imported + 1
              break
            end
          end
        end
      end
    end
  end
  
  self:defaultPrint(string.format("Imported EP for %d members.", imported))
  self:refreshAllEPUI()
end

-- Export helper functions for use by other modules
GuildRoll._attemptThrottledMigration = _attemptThrottledMigration
GuildRoll._trim_public_with_tag = _trim_public_with_tag
GuildRoll._insertTagBeforeEP = _insertTagBeforeEP

-- Debug: Confirm epgp.lua loaded completely
if DEFAULT_CHAT_FRAME then
  DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[EPGP] epgp.lua loaded completely!|r")
end
