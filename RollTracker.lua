-- RollTracker.lua
-- Central storage for rolls and sorting by priority

GuildRoll_RollTracker = {}
GuildRoll_RollTracker.__index = GuildRoll_RollTracker

local defaultPriority = { SR = 1, MS = 2, OS = 3, Tmog = 4, Unknown = 5 }

function GuildRoll_RollTracker:new(priority)
  local o = {
    rolls = {}, -- list of {player, value, type, timestamp, flags}
    priority = priority or defaultPriority
  }
  setmetatable(o, self)
  return o
end

function GuildRoll_RollTracker:add(roll)
  roll.timestamp = roll.timestamp or time()
  table.insert(self.rolls, roll)
  self:sort()
end

function GuildRoll_RollTracker:clear()
  self.rolls = {}
end

function GuildRoll_RollTracker:getAll()
  return self.rolls
end

function GuildRoll_RollTracker:sort()
  table.sort(self.rolls, function(a,b)
    local pa = self.priority[a.type] or self.priority.Unknown
    local pb = self.priority[b.type] or self.priority.Unknown
    if pa ~= pb then
      return pa < pb -- smaller priority value -> higher precedence
    end
    if a.value ~= b.value then
      return a.value > b.value -- higher roll first
    end
    return a.timestamp < b.timestamp
  end)
end
