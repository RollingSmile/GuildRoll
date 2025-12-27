-- ChatParser.lua
-- Parse /roll messages and addon button messages, return normalized roll entry

GuildRoll_ChatParser = {}
GuildRoll_ChatParser.__index = GuildRoll_ChatParser

-- WoW built-in roll: "Player rolls 42 (1-100)"
local rollPattern = "(.+) rolls (%d+) %(%d+%-%d+%)"

-- Example addon patterns (customize):
local addonPatterns = {
  -- "[S] [Player]: I rolled Cumulative SR 169 - 268 with 48 EP + 100 from SR +20 for 3 consecutive weeks"
  { pattern = "%[S%]%s*%[([^%]]+)%]:%s*I rolled Cumulative SR (%d+)%s*%-%s*(%d+)", map = function(p,v1,v2) return p, tonumber(v1), "SR" end },
  { pattern = "%[S%]%s*%[([^%]]+)%]:%s*I rolled SR \"(%d+)%s*%-%s*(%d+)\"", map = function(p,v1,v2) return p, tonumber(v1), "SR" end },
  { pattern = "%[S%]%s*%[([^%]]+)%]:%s*I rolled MS \"(%d+)%s*%-%s*(%d+)\"", map = function(p,v1,v2) return p, tonumber(v1), "MS" end },
  { pattern = "%[S%]%s*%[([^%]]+)%]:%s*I rolled OS \"(%d+)%s*%-%s*(%d+)\"", map = function(p,v1,v2) return p, tonumber(v1), "OS" end },
  { pattern = "%[S%]%s*%[([^%]]+)%]:%s*I rolled EP \"(%d+)%s*%-%s*(%d+)\"", map = function(p,v1,v2) return p, tonumber(v1), "EP" end },
  { pattern = "%[S%]%s*%[([^%]]+)%]:%s*I rolled Tmog \"(%d+)%s*%-%s*(%d+)\"", map = function(p,v1,v2) return p, tonumber(v1), "Tmog" end },
  -- Numeric button labels 101, 100, 99, 98
  { pattern = "%[S%]%s*%[([^%]]+)%]:%s*I rolled \"?101\"? \"(%d+)%s*%-%s*(%d+)\"", map = function(p,v1,v2) return p, tonumber(v1), "SR" end },
  { pattern = "%[S%]%s*%[([^%]]+)%]:%s*I rolled \"?100\"? \"(%d+)%s*%-%s*(%d+)\"", map = function(p,v1,v2) return p, tonumber(v1), "EP" end },
  { pattern = "%[S%]%s*%[([^%]]+)%]:%s*I rolled \"?99\"? \"(%d+)%s*%-%s*(%d+)\"", map = function(p,v1,v2) return p, tonumber(v1), "MS" end },
  { pattern = "%[S%]%s*%[([^%]]+)%]:%s*I rolled \"?98\"? \"(%d+)%s*%-%s*(%d+)\"", map = function(p,v1,v2) return p, tonumber(v1), "OS" end },
}

function GuildRoll_ChatParser:parse(msg)
  -- builtin /roll
  local player, value = string.match(msg, rollPattern)
  if player and value then
    return { player = player, value = tonumber(value), type = "Unknown", timestamp = time() }
  end

  for _,pat in ipairs(addonPatterns) do
    local p, v1, v2 = string.match(msg, pat.pattern)
    if p and v1 then
      local _p, _v, _t = pat.map(p, v1, v2)
      return { player = _p, value = _v, type = _t or "Unknown", timestamp = time() }
    end
  end

  return nil
end
