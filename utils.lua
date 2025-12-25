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
