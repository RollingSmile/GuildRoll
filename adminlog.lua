-- Guard: Check if required libraries are available before proceeding
local L
do
  local ok, result = pcall(function() return AceLibrary("AceLocale-2.2") end)
  if not ok or not result or type(result.new) ~= "function" then return end
  ok, L = pcall(function() return result:new("guildroll") end)
  if not ok or not L then return end
end

------------
-- Admin Log Synchronization Module
------------

-- Zone name to code mapping for admin log
local ZoneCodeMap = {
  [L["Molten Core"]] = "MC",
  [L["Onyxia's Lair"]] = "ONY",
  [L["Blackwing Lair"]] = "BWL",
  [L["Zul'Gurub"]] = "ZG",
  [L["Ahn'Qiraj"]] = "AQ40",
  ["Ruins of Ahn'Qiraj"] = "AQ20",
  [L["Naxxramas"]] = "NAX",
  ["Tower of Karazhan"] = "K10",
  ["Upper Tower of Karazhan"] = "K40"
}

-- Get zone code from zone name
function GuildRoll:getZoneCode(zoneName)
  if not zoneName or zoneName == "" then return "UNKNOWN" end
  local code = ZoneCodeMap[zoneName]
  if code then return code end
  -- Try partial matching for fallback
  for zname, zcode in pairs(ZoneCodeMap) do
    if string.find(zoneName, zname) then
      return zcode
    end
  end
  return "OTHER"
end

-- Generate unique ID for admin log entry
function GuildRoll:generateLogId()
  local ts = time()
  local random = math.random(1000, 9999)
  return string.format("%d_%d", ts, random)
end

-- Create structured admin log entry
-- entry: {admin, target, ep, zone, action, raw}
function GuildRoll:createAdminLogEntry(entry)
  if not entry then return nil end
  
  local logEntry = {
    id = self:generateLogId(),
    ts = date("%Y-%m-%dT%H:%M:%SZ"),
    admin = entry.admin or UnitName("player"),
    target = entry.target or "UNKNOWN",
    ep = entry.ep or 0,
    zone = entry.zone or "UNKNOWN",
    action = entry.action or "UNKNOWN",
    raw = entry.raw or ""
  }
  
  return logEntry
end

-- Add structured entry to adminLog and maintain FIFO limit
function GuildRoll:addStructuredLogEntry(entry)
  if not entry then return end
  
  -- Initialize adminLog if needed (safety check)
  if not GuildRoll_adminLog then
    GuildRoll_adminLog = {}
  end
  
  -- Initialize legacy log if needed
  if not GuildRoll_log then
    GuildRoll_log = {}
  end
  
  -- Check for duplicate by id
  for _, existing in ipairs(GuildRoll_adminLog) do
    if existing.id == entry.id then
      return -- Already exists
    end
  end
  
  -- Add new entry
  table.insert(GuildRoll_adminLog, entry)
  
  -- Maintain FIFO limit
  local maxLines = GuildRoll.VARS.maxloglines or 500
  while table.getn(GuildRoll_adminLog) > maxLines do
    table.remove(GuildRoll_adminLog, 1)
  end
  
  -- Also update legacy GuildRoll_log for UI compatibility
  if entry.raw and entry.raw ~= "" then
    self:addToLog(entry.raw, false)
  end
  
  -- Update personal log for target if applicable
  if entry.target and entry.target ~= "ALL" and entry.target ~= "UNKNOWN" then
    local personalMsg = entry.raw
    if not personalMsg or personalMsg == "" then
      if entry.action == "ADD_EP" then
        personalMsg = string.format("%s awarded %d EP", entry.admin or "Admin", entry.ep or 0)
      elseif entry.action == "DECAY" then
        personalMsg = string.format("Decay applied by %s", entry.admin or "Admin")
      else
        personalMsg = string.format("%s: %s", entry.action or "Action", entry.admin or "Admin")
      end
    end
    self:personalLogAdd(entry.target, personalMsg)
  end
end

-- Broadcast admin log entry to other admins
function GuildRoll:broadcastAdminLogEntry(entry)
  if not entry then return end
  
  -- Only broadcast if we're an admin
  local ok, canEdit = pcall(CanEditOfficerNote)
  if not ok or not canEdit then return end
  
  -- Serialize entry: ADMINLOG;ADD;id;ts;admin;target;ep;zone;action;raw
  local raw = entry.raw or ""
  -- Escape semicolons in raw message
  raw = string.gsub(raw, ";", "\\;")
  
  local msg = string.format("ADMINLOG;ADD;%s;%s;%s;%s;%s;%s;%s;%s",
    entry.id or "",
    entry.ts or "",
    entry.admin or "",
    entry.target or "",
    tostring(entry.ep or 0),
    entry.zone or "",
    entry.action or "",
    raw
  )
  
  self:addonMessage(msg, "GUILD")
end

-- Request admin log from other admins
function GuildRoll:requestAdminLog()
  -- Only request if we're an admin
  local ok, canEdit = pcall(CanEditOfficerNote)
  if not ok or not canEdit then return end
  
  -- Send request: ADMINLOG;REQ;count
  local currentCount = table.getn(GuildRoll_adminLog or {})
  local msg = string.format("ADMINLOG;REQ;%d", currentCount)
  self:addonMessage(msg, "GUILD")
end

-- Debug function to print structured admin log entries
function GuildRoll:debugAdminLog()
  local ok, canEdit = pcall(CanEditOfficerNote)
  if not ok or not canEdit then
    self:defaultPrint("You must be an admin to view the structured log.")
    return
  end
  
  if not GuildRoll_adminLog or table.getn(GuildRoll_adminLog) == 0 then
    self:defaultPrint("No structured admin log entries found.")
    return
  end
  
  self:defaultPrint(string.format("=== Structured Admin Log (%d entries) ===", table.getn(GuildRoll_adminLog)))
  
  -- Show last 10 entries
  local startIdx = math.max(1, table.getn(GuildRoll_adminLog) - 9)
  for i = startIdx, table.getn(GuildRoll_adminLog) do
    local entry = GuildRoll_adminLog[i]
    if entry then
      local msg = string.format("[%s] %s: %s -> %s (%+d EP, %s, %s)",
        entry.ts or "?",
        entry.admin or "?",
        entry.action or "?",
        entry.target or "?",
        entry.ep or 0,
        entry.zone or "?",
        entry.id or "?"
      )
      self:defaultPrint(msg)
    end
  end
  
  self:defaultPrint("=== End of Admin Log ===")
end

-- Handle incoming admin log messages
function GuildRoll:handleAdminLogMessage(message, sender)
  -- Only admins should process admin log messages
  local ok, canEdit = pcall(CanEditOfficerNote)
  if not ok or not canEdit then return end
  
  -- Parse message type
  local msgType = string.match(message, "^ADMINLOG;([^;]+)")
  if not msgType then return end
  
  if msgType == "ADD" then
    -- ADMINLOG;ADD;id;ts;admin;target;ep;zone;action;raw
    -- Parse carefully since raw may contain escaped semicolons
    local pattern = "^ADMINLOG;ADD;([^;]*);([^;]*);([^;]*);([^;]*);([^;]*);([^;]*);([^;]*);(.*)$"
    local id, ts, admin, target, ep, zone, action, raw = string.match(message, pattern)
    
    if id and ts and admin and target and ep and zone and action then
      local entry = {
        id = id,
        ts = ts,
        admin = admin,
        target = target,
        ep = tonumber(ep) or 0,
        zone = zone,
        action = action,
        raw = raw or ""
      }
      -- Unescape semicolons in raw message
      entry.raw = string.gsub(entry.raw, "\\;", ";")
      
      -- Add to our log (will check for duplicates)
      self:addStructuredLogEntry(entry)
    end
    
  elseif msgType == "REQ" then
    -- ADMINLOG;REQ;count - sender is requesting log entries
    local senderCount = tonumber(string.match(message, "^ADMINLOG;REQ;(%d+)")) or 0
    local ourCount = table.getn(GuildRoll_adminLog or {})
    
    -- If we have more entries, send them
    if ourCount > senderCount then
      -- Send missing entries (limit to avoid spam)
      local maxToSend = 10
      local startIdx = math.max(1, ourCount - maxToSend + 1)
      
      for i = startIdx, ourCount do
        local entry = GuildRoll_adminLog[i]
        if entry then
          self:broadcastAdminLogEntry(entry)
        end
      end
    end
    
  elseif msgType == "BATCH" then
    -- ADMINLOG;BATCH;count - sender is sending batch of entries
    -- This would be followed by multiple ADD messages
    -- We just acknowledge the batch for now
  end
end
