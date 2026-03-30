-- notes_v3.lua: Note management and EP system for GuildRoll
-- Contains functions for managing officer notes in {EP} format

-- Constants for note length
local MAX_NOTE_LEN = 31

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

-- Initialize officer notes to {EP} format
function GuildRoll:init_notes_v3(guild_index,name,officernote)
  local ep = self:get_ep_v3(name,officernote)
  if ep == nil then
    -- Initialize with {EP} format
    local initstring = string.format("{%d}",0)
    local newnote
    if string.len(officernote) + string.len(initstring) > MAX_NOTE_LEN then
      local availableLen = MAX_NOTE_LEN - string.len(initstring)
      newnote = string.sub(officernote, 1, availableLen) .. initstring
    else
      newnote = officernote .. initstring
    end
    officernote = newnote
  end
  GuildRosterSetOfficerNote(guild_index,officernote,true)
  return officernote
end

-- Update EP value in officer note (EP-only implementation)
function GuildRoll:update_ep_v3(getname,ep)
  for i = 1, GetNumGuildMembers(1) do
    local name, _, _, _, class, _, note, officernote, _, _ = GetGuildRosterInfo(i)
    if (name==getname) then
      -- Initialize notes if needed (ensures {EP} format)
      officernote = self:init_notes_v3(i,name,officernote)

      -- Get previous EP value for logging (after note initialization)
      local prevEP = self:get_ep_v3(name,officernote) or 0

      local newnote
      if ep ~= nil then
        newnote = string.gsub(officernote,"(.-)({%d+})(.*)",function(prefix,tag,postfix)
          return string.format("%s{%d}%s",prefix,ep,postfix)
        end)
      end

      if newnote then
        local success, err = pcall(function()
          GuildRosterSetOfficerNote(i,newnote,true)
        end)

        if not success then
          self:debugPrint(string.format("Error updating officer note for %s: %s", name or "unknown", tostring(err)))
        end

        if ep ~= nil then
          local actor = UnitName("player")
          local changeEP = ep - prevEP

          local C
          pcall(function() C = AceLibrary("Crayon-2.0") end)

          local deltaStr
          if C and changeEP >= 0 then
            deltaStr = C:Green(string.format("+%d", changeEP))
          elseif C then
            deltaStr = C:Red(string.format("%d", changeEP))
          else
            deltaStr = string.format("%+d", changeEP)
          end

          local logMsg = string.format("EP: %d -> %d (%s) by %s", prevEP, ep, deltaStr, actor)
          self:personalLogAdd(name, logMsg)
        end
      end
    end
  end
end

-- Get EP value from officer note or by player name
function GuildRoll:get_ep_v3(getname,officernote)
  if (officernote) then
    local _,_,ep = string.find(officernote,".*{(%d+)}.*")
    return tonumber(ep)
  end
  for i = 1, GetNumGuildMembers(1) do
    local name, _, _, _, class, _, note, officernote, _, _ = GetGuildRosterInfo(i)
    local _,_,ep = string.find(officernote,".*{(%d+)}.*")
    if ep and (name==getname) then
      return tonumber(ep)
    end
  end
  return
end

-- Export helper functions for use by other modules
GuildRoll._trim_public_with_tag = _trim_public_with_tag
