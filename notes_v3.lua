-- notes_v3.lua: Note management and EP system for GuildRoll
-- Contains functions for managing officer notes in {EP} format and migration utilities

-- Constants for note length and migration timing
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
  
  -- Try to find new {EP} pattern first (e.g., {123})
  local prefix, ep, postfix = string.match(officernote, "^(.-)({%d+})(.*)$")
  
  if ep then
    -- Found new {EP} pattern; insert tag before it
    return prefix .. tag .. ep .. postfix
  end
  
  -- Try to find legacy {EP:GP} pattern (e.g., {123:456})
  prefix, epgp, postfix = string.match(officernote, "^(.-)({%d+:%d+})(.*)$")
  
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
    -- Initialize with new {EP} format (EP-only, no GP)
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
      -- Convert {EP:GP} to {EP}
      -- Pattern captures: prefix, fullTag, epVal, gpVal, postfix (5 total)
      local prefix, fullTag, epVal, gpVal, postfix = string.match(officernote, "^(.-)({(%d+):(%-?%d+)})(.*)$")
      if epVal then
        -- NO backup of GP value - just convert to new format
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

-- Update EP/GP values in officer note (v3 - EP-only implementation)
function GuildRoll:update_epgp_v3(ep,gp,guild_index,name,officernote,special_action)
  -- EP-only implementation: initialize notes to {EP} format, update EP value
  -- gp parameter is kept for compatibility but ignored
  
  -- Initialize notes if needed (ensures {EP} format)
  officernote = self:init_notes_v3(guild_index,name,officernote)
  
  -- Get previous EP value for logging (after note initialization)
  local prevEP = self:get_ep_v3(name,officernote) or 0
  
  local newnote
  if ep ~= nil then 
    -- Try to match legacy {EP:GP} format first
    local prefix, fullTag, oldEP, oldGP, postfix = string.match(officernote, "^(.-)({(%d+):(%-?%d+)})(.*)$")
    if oldEP then
      -- Has legacy format - NO backup, just convert to new {EP} format
      newnote = string.gsub(officernote,"(.-)({%d+:%-?%d+})(.*)",function(prefix,tag,postfix)
        return string.format("%s{%d}%s",prefix,ep,postfix)
      end)
    else
      -- Update new {EP} format
      newnote = string.gsub(officernote,"(.-)({%d+})(.*)",function(prefix,tag,postfix)
        return string.format("%s{%d}%s",prefix,ep,postfix)
      end)
    end
  end
  
  -- GP parameter is ignored (kept for compatibility only)
  if gp ~= nil then
    newnote = newnote or officernote
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
      self:update_epgp_v3(ep,nil,i,name,officernote)
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

-- migrateToEPOnly: Convert officer notes from {EP:GP} format to {EP} format
-- NO BACKUP of GP values - just converts to new format
-- Admin-only function with throttled updates to avoid server spam
function GuildRoll:migrateToEPOnly(throttleDelay)
  -- Admin permission check
  if not self:IsAdmin() then
    self:defaultPrint(L["You must be a guild officer or leader to run this migration."] or "You must be a guild officer or leader to run this migration.")
    return
  end
  
  -- Default throttle delay
  throttleDelay = tonumber(throttleDelay) or 0.25
  if throttleDelay < 0.1 then
    throttleDelay = 0.1  -- Minimum safety threshold
  end
  
  -- Scan roster and collect members needing migration
  local toMigrate = {}
  local ok, numMembers = pcall(function()
    if not IsInGuild() then return 0 end
    return GetNumGuildMembers(1) or 0
  end)
  
  if not ok or numMembers == 0 then
    self:defaultPrint("Guild roster not available. Please try again in a moment.")
    return
  end
  
  for i = 1, numMembers do
    local success, name, rank, rankIndex, level, class, zone, note, officernote = pcall(GetGuildRosterInfo, i)
    if success and name and officernote then
      -- Match {EP:GP} pattern (support optional negative GP)
      -- Pattern captures: prefix, fullTag, ep, gp, postfix (5 total)
      local prefix, fullTag, ep, gp, postfix = string.match(officernote, "^(.-)({(%d+):(%-?%d+)})(.*)$")
      if ep and gp then
        table.insert(toMigrate, {
          name = name,
          oldNote = officernote,
          prefix = prefix or "",
          ep = tonumber(ep),
          gp = tonumber(gp),
          postfix = postfix or ""
        })
      end
    end
  end
  
  if table.getn(toMigrate) == 0 then
    self:defaultPrint("No officer notes found with {EP:GP} format. Migration complete.")
    return
  end
  
  self:defaultPrint(string.format("Starting migration of %d member(s) from {EP:GP} to {EP} format...", table.getn(toMigrate)))
  
  -- Create frame for throttled updates
  local frame = CreateFrame("Frame")
  local currentIndex = 1
  local timeSinceLastUpdate = 0
  
  frame:SetScript("OnUpdate", function()
    local elapsed = arg1  -- Lua 5.0 uses arg1 for elapsed time
    timeSinceLastUpdate = timeSinceLastUpdate + elapsed
    
    if timeSinceLastUpdate >= throttleDelay and currentIndex <= table.getn(toMigrate) then
      timeSinceLastUpdate = 0
      
      local entry = toMigrate[currentIndex]
      
      -- Build new note with {EP} format
      local newTag = string.format("{%d}", entry.ep)
      local newNote = entry.prefix .. newTag .. entry.postfix
      
      -- Ensure note doesn't exceed MAX_NOTE_LEN (31 chars)
      if string.len(newNote) > MAX_NOTE_LEN then
        -- Trim prefix and postfix evenly to fit
        local tagLen = string.len(newTag)
        local availableLen = MAX_NOTE_LEN - tagLen
        local prefixLen = string.len(entry.prefix)
        local postfixLen = string.len(entry.postfix)
        local totalExtra = prefixLen + postfixLen
        
        if totalExtra > availableLen then
          -- Trim proportionally
          local prefixAllowed = math.floor((prefixLen / totalExtra) * availableLen)
          local postfixAllowed = availableLen - prefixAllowed
          
          entry.prefix = string.sub(entry.prefix, 1, prefixAllowed)
          entry.postfix = string.sub(entry.postfix, 1, postfixAllowed)
          newNote = entry.prefix .. newTag .. entry.postfix
        end
      end
      
      -- NO BACKUP of GP value - just convert to new format
      
      -- Find current roster index for this member (roster may have reordered)
      local foundIndex = nil
      for i = 1, GetNumGuildMembers(1) do
        local success, checkName = pcall(GetGuildRosterInfo, i)
        if success and checkName == entry.name then
          foundIndex = i
          break
        end
      end
      
      if foundIndex then
        -- Apply the note change
        local success, err = pcall(GuildRosterSetOfficerNote, foundIndex, newNote)
        if not success then
          GuildRoll:defaultPrint(string.format("Failed to update %s: %s", entry.name, tostring(err)))
        end
      end
      
      currentIndex = currentIndex + 1
      
      -- Cleanup when done
      if currentIndex > table.getn(toMigrate) then
        frame:SetScript("OnUpdate", nil)
        GuildRoll:defaultPrint(string.format("Migration complete! Converted %d member(s) to {EP} format.", table.getn(toMigrate)))
      end
    end
  end)
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
        local mainTag = string.match(publicNote, "({%a%a%a*})")
        if mainTag and type(mainTag) == "string" and string.len(mainTag) > 2 then
          -- Insert main tag before {EP:GP} in officer note first (to avoid data loss)
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

-- Export helper functions for use by other modules
GuildRoll._attemptThrottledMigration = _attemptThrottledMigration
GuildRoll._trim_public_with_tag = _trim_public_with_tag
GuildRoll._insertTagBeforeEP = _insertTagBeforeEP
