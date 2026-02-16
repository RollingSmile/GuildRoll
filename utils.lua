-- utils.lua: Utility functions for GuildRoll
-- Contains helper functions for string manipulation, numeric operations, and member verification

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

-- ui_helpers: UI helper functions for GuildRoll
-- Contains utilities for managing Tablet tooltips, frames, and UI interactions

-- Constant for maximum number of detached frames to scan
local MAX_DETACHED_FRAMES = 100

-- Cached dummy owner frame for Tablet tooltips
-- This prevents "Detached tooltip has no owner" errors from Tablet-2.0
local _guildroll_tablet_owner = nil

-- Get local reference to Dewdrop library (required for SafeDewdropAddLine)
-- Use pcall to safely get library reference
local D
pcall(function() D = AceLibrary("Dewdrop-2.0") end)

-- Centralized function to ensure Tablet tooltips have a valid owner
-- This prevents Tablet-2.0 from asserting when detaching tooltips without an owner
-- Call this after T:Register() to set tooltip.owner if it's missing
-- Returns the dummy owner frame (or UIParent as fallback)
function GuildRoll:EnsureTabletOwner()
  local owner = nil
  pcall(function()
    -- Create or reuse the cached dummy owner frame
    if not _guildroll_tablet_owner then
      local ok, f = pcall(function() 
        return CreateFrame and CreateFrame("Frame", "GuildRoll_TabletOwner") 
      end)
      if ok and f then
        _guildroll_tablet_owner = f
      else
        -- Fallback to UIParent if frame creation fails
        _guildroll_tablet_owner = UIParent
      end
    end
    owner = _guildroll_tablet_owner
  end)
  return owner or UIParent
end

-- Shared method: find an existing detached Tablet frame by owner name
function GuildRoll:FindDetachedFrame(ownerName)
  if not ownerName then return nil end
  for i = 1, MAX_DETACHED_FRAMES do
    local f = _G[string.format("Tablet20DetachedFrame%d", i)]
    if f and f.owner and f.owner == ownerName then
      return f
    end
  end
  return nil
end

-- SafeDewdropAddLine: Centralized safe wrapper for Dewdrop:AddLine usage
-- Prevents Dewdrop crashes by wrapping D:AddLine with pcall + unpack(arg)
-- Note: In Lua 5.0 (WoW 1.12), varargs (...) cannot be passed directly to pcall.
-- We must use unpack(arg) to forward the arguments.
function GuildRoll:SafeDewdropAddLine(...)
  if D and D.AddLine then
    pcall(D.AddLine, D, unpack(arg))
  end
end

-- Make frame escapable: Add or remove frame from UISpecialFrames table
function GuildRoll:make_escable(framename,operation)
  local found
  for i,f in ipairs(UISpecialFrames) do
    if f==framename then
      found = i
    end
  end
  if not found and operation=="add" then
    table.insert(UISpecialFrames,framename)
  elseif found and operation=="remove" then
    table.remove(UISpecialFrames,found)
  end
end

-- Reset detached frames to default visible positions
function GuildRoll:ResetFrames()
  -- Default visible positions for detached frames
  local defaultPositions = {
    ["GuildRoll_standings"] = {x = 400, y = 350},
    ["GuildRollAlts"] = {x = 650, y = 300},
    ["GuildRoll_logs"] = {x = 800, y = 300},
    ["GuildRoll_personal_logs"] = {x = 500, y = 200},
    ["GuildRoll_AdminLog"] = {x = 900, y = 300}
  }
  
  local resetCount = 0
  for ownerName, pos in pairs(defaultPositions) do
    local frame = self:FindDetachedFrame(ownerName)
    if frame then
      pcall(function()
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", pos.x, pos.y)
        resetCount = resetCount + 1
      end)
    end
  end
  
  if resetCount > 0 then
    self:defaultPrint(string.format("Reset %d detached frame(s) to visible positions.", resetCount))
  else
    self:defaultPrint("No detached frames found to reset.")
  end
end
