--[[
AdminLog Module for GuildRoll
Provides persistent, guild-wide synchronized admin log with delta broadcast and snapshot sync.

TESTING INSTRUCTIONS:
1. After adding this file, update guildroll.toc:
   - Add GuildRoll_adminLogSaved, GuildRoll_adminLogOrder to SavedVariables line
   - Add adminlog.lua to file list
   Then /reload

2. Test with two admin clients online:
   - Client A: /gadminlog add "Test entry from A"
   - Client B: Should automatically receive the entry (check with /gadminlog or UI)
   - Verify both clients show the same entry

3. Test snapshot sync:
   - Client A adds several entries while Client B is offline
   - Client B comes back online and runs: /gadminlog sync
   - Verify Client B receives only the entries added while offline

4. Verify persistence:
   - Add entries, then /reload
   - Entries should still be present after reload

NOTES:
- Only admins (with CanEditOfficerNote or IsGuildLeader) can add entries and request snapshots
- Throttling is conservative; for very large logs, consider limiting snapshots to last N entries
- This module is isolated and does not modify existing logs.lua
--]]

--[[
AdminLog Module for GuildRoll
Provides persistent, guild-wide synchronized admin log with delta broadcast and snapshot sync.
...
-- (intentionally unchanged header/training text)
--]]

-- Guard: Check if required libraries are available
local T, D, C, CP, L
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
  
  ok, result = pcall(function() return AceLibrary("Compost-2.0") end)
  if not ok or not result then return end
  CP = result
  
  ok, result = pcall(function() return AceLibrary("AceLocale-2.2") end)
  if not ok or not result or type(result.new) ~= "function" then return end
  ok, L = pcall(function() return result:new("guildroll") end)
  if not ok or not L then return end
end

-- Initialize saved variables
GuildRoll_adminLogSaved = GuildRoll_adminLogSaved or {}
GuildRoll_adminLogOrder = GuildRoll_adminLogOrder or {}

-- Module definition
GuildRoll_AdminLog = GuildRoll:NewModule("GuildRoll_AdminLog", "AceDB-2.0", "AceEvent-2.0")

-- Local state
local adminLogRuntime = {} -- runtime cache indexed by entry id
local snapshotInProgress = false
local snapshotBuffer = {}
local snapshotMaxTS = 0 -- track max timestamp during snapshot reception
local latestRemoteTS = 0 -- track latest remote timestamp seen
local filterAuthor = nil -- for UI filtering
local searchText = nil -- for UI search
local expandedRaidEntries = {} -- track which raid entries are expanded (key = entry.id)

-- Constants
local PROTOCOL_VERSION = 1
local CHUNK_SIZE = 10 -- entries per SNAP message
local SYNC_THROTTLE_SEC = 5 -- minimum seconds between sync requests

local lastSyncRequest = 0

-- Helper: Get local latest timestamp
local function getLocalLatestTS()
  local maxTS = 0
  for i = 1, table.getn(GuildRoll_adminLogOrder) do
    local id = GuildRoll_adminLogOrder[i]
    local entry = adminLogRuntime[id]
    if entry and entry.ts and entry.ts > maxTS then
      maxTS = entry.ts
    end
  end
  return maxTS
end

-- Helper: Generate unique ID for log entry
local function generateEntryId()
  local timestamp = time()
  local random = math.random(1000, 9999)
  return string.format("%d_%d", timestamp, random)
end

-- Helper: Serialize entry for transmission
local function serializeEntry(entry)
  -- Format: id|ts|author|action[|RAID_DATA if raid entry]
  local id = entry.id or ""
  local ts = entry.ts or 0
  local author = entry.author or ""
  local action = entry.action or ""
  
  -- Escape pipe characters in action
  action = string.gsub(action, "|", "||")
  
  local baseStr = string.format("%s|%d|%s|%s", id, ts, author, action)
  
  -- If this is a raid entry, append raid_details
  if entry.raid_details then
    local rd = entry.raid_details
    -- Format: RAID|ep|player_count|player1:old:new,player2:old:new,...
    local playerList = {}
    for i = 1, table.getn(rd.players or {}) do
      local player = rd.players[i]
      local counts = rd.counts[player] or {old=0, new=0}
      table.insert(playerList, string.format("%s:%d:%d", player, counts.old, counts.new))
    end
    local playersStr = table.concat(playerList, ",")
    -- Escape pipes in player data
    playersStr = string.gsub(playersStr, "|", "||")
    local raidData = string.format("RAID|%d|%d|%s", rd.ep or 0, table.getn(rd.players or {}), playersStr)
    baseStr = baseStr .. "|" .. raidData
  end
  
  return baseStr
end

-- Helper: Deserialize entry from transmission
local function deserializeEntry(data)
  if not data then return nil end
  
  -- Split by pipe, handling escaped pipes (||)
  local parts = {}
  local current = ""
  local i = 1
  
  while i <= string.len(data) do
    local char = string.sub(data, i, i)
    local nextChar = string.sub(data, i + 1, i + 1)
    
    if char == "|" and nextChar == "|" then
      -- Escaped pipe: add single pipe to current part
      current = current .. "|"
      i = i + 2
    elseif char == "|" then
      -- Unescaped pipe: delimiter between parts
      table.insert(parts, current)
      current = ""
      i = i + 1
    else
      -- Regular character
      current = current .. char
      i = i + 1
    end
  end
  
  table.insert(parts, current)
  
  if table.getn(parts) < 4 then return nil end
  
  local entry = {
    id = parts[1],
    ts = tonumber(parts[2]) or 0,
    author = parts[3],
    action = parts[4]
  }
  
  -- Check if this is a raid entry (part 5 starts with "RAID")
  if table.getn(parts) >= 5 and parts[5] == "RAID" then
    local ep = tonumber(parts[6]) or 0
    local playerCount = tonumber(parts[7]) or 0
    local playersStr = parts[8] or ""
    
    local players = {}
    local counts = {}
    
    -- Parse player list: player1:old:new,player2:old:new,...
    if playersStr ~= "" then
      local playerEntries = {}
      local currentEntry = ""
      for j = 1, string.len(playersStr) do
        local c = string.sub(playersStr, j, j)
        if c == "," then
          table.insert(playerEntries, currentEntry)
          currentEntry = ""
        else
          currentEntry = currentEntry .. c
        end
      end
      if currentEntry ~= "" then
        table.insert(playerEntries, currentEntry)
      end
      
      for k = 1, table.getn(playerEntries) do
        local pEntry = playerEntries[k]
        -- Split by :
        local pParts = {}
        local pCurrent = ""
        for m = 1, string.len(pEntry) do
          local c = string.sub(pEntry, m, m)
          if c == ":" then
            table.insert(pParts, pCurrent)
            pCurrent = ""
          else
            pCurrent = pCurrent .. c
          end
        end
        if pCurrent ~= "" then
          table.insert(pParts, pCurrent)
        end
        
        if table.getn(pParts) >= 3 then
          local playerName = pParts[1]
          local oldEP = tonumber(pParts[2]) or 0
          local newEP = tonumber(pParts[3]) or 0
          table.insert(players, playerName)
          counts[playerName] = {old = oldEP, new = newEP}
        end
      end
    end
    
    entry.raid_details = {
      ep = ep,
      players = players,
      counts = counts
    }
  end
  
  return entry
end

-- Apply an admin log entry locally
local function applyAdminLogEntry(entry)
  if not entry or not entry.id then return end
  
  -- Check if already exists
  if adminLogRuntime[entry.id] then
    return -- duplicate, skip
  end
  
  -- Add to runtime cache
  adminLogRuntime[entry.id] = entry
  
  -- Add to saved variables
  GuildRoll_adminLogSaved[entry.id] = entry
  
  -- Add to order array if not present
  local found = false
  for i = 1, table.getn(GuildRoll_adminLogOrder) do
    if GuildRoll_adminLogOrder[i] == entry.id then
      found = true
      break
    end
  end
  
  if not found then
    table.insert(GuildRoll_adminLogOrder, entry.id)
  end
  
  -- Trim order array to last 500 entries
  local maxEntries = 500
  if table.getn(GuildRoll_adminLogOrder) > maxEntries then
    local toRemove = table.getn(GuildRoll_adminLogOrder) - maxEntries
    for i = 1, toRemove do
      local oldId = GuildRoll_adminLogOrder[1]
      table.remove(GuildRoll_adminLogOrder, 1)
      -- Remove from saved and runtime
      GuildRoll_adminLogSaved[oldId] = nil
      adminLogRuntime[oldId] = nil
    end
  end
end

-- Load saved entries into runtime cache
local function loadSavedEntries()
  adminLogRuntime = {}
  
  -- Load from saved order
  for i = 1, table.getn(GuildRoll_adminLogOrder) do
    local id = GuildRoll_adminLogOrder[i]
    local entry = GuildRoll_adminLogSaved[id]
    if entry then
      adminLogRuntime[id] = entry
    end
  end
end

-- Broadcast a new admin log entry to guild
local function broadcastAdminLogEntry(entry)
  if not GuildRoll or not GuildRoll.IsAdmin or not GuildRoll:IsAdmin() then
    return
  end
  
  local serialized = serializeEntry(entry)
  local message = string.format("ADMINLOG;ADD;%d;%s", PROTOCOL_VERSION, serialized)
  
  pcall(function()
    GuildRoll:addonMessage(message, "GUILD")
  end)
end

-- Request admin log snapshot from other admins
local function requestAdminLogSnapshot(since_ts)
  if not GuildRoll or not GuildRoll.IsAdmin or not GuildRoll:IsAdmin() then
    return
  end
  
  local now = time()
  if now - lastSyncRequest < SYNC_THROTTLE_SEC then
    GuildRoll:defaultPrint(string.format("Sync throttled. Wait %d seconds.", SYNC_THROTTLE_SEC - (now - lastSyncRequest)))
    return
  end
  lastSyncRequest = now
  
  -- Set snapshot in progress flag
  snapshotInProgress = true
  
  since_ts = since_ts or 0
  local message = string.format("ADMINLOG;REQ;%d;%d", PROTOCOL_VERSION, since_ts)
  
  pcall(function()
    GuildRoll:addonMessage(message, "GUILD")
  end)
  
  GuildRoll:defaultPrint("Admin log sync requested...")
  
  -- Refresh UI to update menu state
  if T and T:IsRegistered("GuildRoll_AdminLog") then
    pcall(function() T:Refresh("GuildRoll_AdminLog") end)
  end
end

-- Send snapshot response in chunks
local function sendSnapshot(target, since_ts)
  if not GuildRoll or not GuildRoll.IsAdmin or not GuildRoll:IsAdmin() then
    return
  end
  
  since_ts = since_ts or 0
  local entries = {}
  
  -- Collect entries newer than since_ts
  for i = 1, table.getn(GuildRoll_adminLogOrder) do
    local id = GuildRoll_adminLogOrder[i]
    local entry = adminLogRuntime[id]
    if entry and entry.ts > since_ts then
      table.insert(entries, entry)
    end
  end
  
  if table.getn(entries) == 0 then
    -- Send empty snapshot end
    local message = string.format("ADMINLOG;SNAP_END;%d;0", PROTOCOL_VERSION)
    pcall(function()
      GuildRoll:addonMessage(message, "WHISPER", target)
    end)
    return
  end
  
  -- Send in chunks
  local chunkCount = 0
  for i = 1, table.getn(entries), CHUNK_SIZE do
    local chunk = {}
    for j = i, math.min(i + CHUNK_SIZE - 1, table.getn(entries)) do
      table.insert(chunk, entries[j])
    end
    
    -- Serialize chunk
    local chunkData = {}
    for k = 1, table.getn(chunk) do
      table.insert(chunkData, serializeEntry(chunk[k]))
    end
    local chunkStr = table.concat(chunkData, ";;")
    
    local message = string.format("ADMINLOG;SNAP;%d;%s", PROTOCOL_VERSION, chunkStr)
    pcall(function()
      GuildRoll:addonMessage(message, "WHISPER", target)
    end)
    
    chunkCount = chunkCount + 1
  end
  
  -- Send snapshot end
  local message = string.format("ADMINLOG;SNAP_END;%d;%d", PROTOCOL_VERSION, table.getn(entries))
  pcall(function()
    GuildRoll:addonMessage(message, "WHISPER", target)
  end)
end

-- Handle incoming admin log messages
local function handleAdminLogMessage(prefix, message, channel, sender)
  if not prefix or prefix ~= GuildRoll.VARS.prefix then return end
  if not message or not string.find(message, "^ADMINLOG;") then return end
  
  -- Normalize sender: remove realm suffix (e.g., Name-Realm -> Name)
  local sender_norm = sender and string.gsub(sender, "%-.*$", "") or sender
  
  -- Verify sender is guild member
  local name_g = GuildRoll:verifyGuildMember(sender_norm, true)
  if not name_g then return end
  
  -- Parse message
  local parts = {}
  local current = ""
  for i = 1, string.len(message) do
    local char = string.sub(message, i, i)
    if char == ";" then
      table.insert(parts, current)
      current = ""
    else
      current = current .. char
    end
  end
  table.insert(parts, current)
  
  if table.getn(parts) < 3 then return end
  
  local msgType = parts[2]
  local version = tonumber(parts[3]) or 0
  
  if version ~= PROTOCOL_VERSION then
    return -- version mismatch
  end
  
  if msgType == "ADD" then
    -- ADMINLOG;ADD;version;serialized_entry
    if table.getn(parts) < 4 then return end
    local entryData = parts[4]
    local entry = deserializeEntry(entryData)
    if entry then
      applyAdminLogEntry(entry)
      -- Update latestRemoteTS if this entry is newer
      if entry.ts and entry.ts > latestRemoteTS then
        latestRemoteTS = entry.ts
      end
      -- Refresh UI if open
      if T and T:IsRegistered("GuildRoll_AdminLog") then
        pcall(function() T:Refresh("GuildRoll_AdminLog") end)
      end
    end
    
  elseif msgType == "REQ" then
    -- ADMINLOG;REQ;version;since_ts
    if not GuildRoll:IsAdmin() then return end
    
    if table.getn(parts) < 4 then return end
    local since_ts = tonumber(parts[4]) or 0
    
    -- Send snapshot to requester
    sendSnapshot(sender, since_ts)
    
  elseif msgType == "SNAP" then
    -- ADMINLOG;SNAP;version;chunk_data
    if table.getn(parts) < 4 then return end
    local chunkData = parts[4]
    
    -- Split by ;;
    local entries = {}
    local currentEntry = ""
    local i = 1
    while i <= string.len(chunkData) do
      local char = string.sub(chunkData, i, i)
      local nextChar = string.sub(chunkData, i + 1, i + 1)
      
      if char == ";" and nextChar == ";" then
        if currentEntry ~= "" then
          table.insert(entries, currentEntry)
          currentEntry = ""
        end
        i = i + 2
      else
        currentEntry = currentEntry .. char
        i = i + 1
      end
    end
    if currentEntry ~= "" then
      table.insert(entries, currentEntry)
    end
    
    -- Apply entries and track max timestamp
    for j = 1, table.getn(entries) do
      local entry = deserializeEntry(entries[j])
      if entry then
        table.insert(snapshotBuffer, entry)
        -- Track max timestamp during snapshot
        if entry.ts and entry.ts > snapshotMaxTS then
          snapshotMaxTS = entry.ts
        end
      end
    end
    
  elseif msgType == "SNAP_END" then
    -- ADMINLOG;SNAP_END;version;total_count
    if table.getn(parts) < 4 then return end
    local totalCount = tonumber(parts[4]) or 0
    
    -- Apply buffered entries
    for i = 1, table.getn(snapshotBuffer) do
      applyAdminLogEntry(snapshotBuffer[i])
    end
    
    GuildRoll:defaultPrint(string.format("Admin log sync complete: %d new entries received.", table.getn(snapshotBuffer)))
    
    -- Update latestRemoteTS with snapshotMaxTS
    if snapshotMaxTS > latestRemoteTS then
      latestRemoteTS = snapshotMaxTS
    end
    
    -- Reset snapshot state
    snapshotInProgress = false
    snapshotMaxTS = 0
    snapshotBuffer = {}
    
    -- Refresh UI
    if T and T:IsRegistered("GuildRoll_AdminLog") then
      pcall(function() T:Refresh("GuildRoll_AdminLog") end)
    end
  end
end

-- Public API: Add a new admin log entry
function GuildRoll:AdminLogAdd(text)
  if not self:IsAdmin() then
    self:defaultPrint("Only admins can add admin log entries.")
    return
  end
  
  if not text or text == "" then
    self:defaultPrint("Usage: /gadminlog add <text>")
    return
  end
  
  local entry = {
    id = generateEntryId(),
    ts = time(),
    author = UnitName("player") or "Unknown",
    action = text
  }
  
  -- Apply locally
  applyAdminLogEntry(entry)
  
  -- Broadcast to guild
  broadcastAdminLogEntry(entry)
  
  -- Refresh UI
  if T and T:IsRegistered("GuildRoll_AdminLog") then
    pcall(function() T:Refresh("GuildRoll_AdminLog") end)
  end
end

-- Public API: Add a raid admin log entry with player details
function GuildRoll:AdminLogAddRaid(ep, raid_data)
  if not self:IsAdmin() then
    return
  end
  
  if not raid_data or not raid_data.players or table.getn(raid_data.players) == 0 then
    return
  end
  
  local playerCount = table.getn(raid_data.players)
  local adminName = UnitName("player") or "Unknown"
  local actionText
  if ep < 0 then
    actionText = string.format("[RAID] %d EP Penalty (%d players)", ep, playerCount)
  else
    actionText = string.format("[RAID] Giving %d EP (%d players)", ep, playerCount)
  end
  
  local entry = {
    id = generateEntryId(),
    ts = time(),
    author = adminName,
    action = actionText,
    raid_details = {
      ep = ep,
      players = raid_data.players,
      counts = raid_data.counts
    }
  }
  
  -- Apply locally
  applyAdminLogEntry(entry)
  
  -- Broadcast to guild
  broadcastAdminLogEntry(entry)
  
  -- Refresh UI
  if T and T:IsRegistered("GuildRoll_AdminLog") then
    pcall(function() T:Refresh("GuildRoll_AdminLog") end)
  end
end

-- Public API: Request admin log snapshot
function GuildRoll:RequestAdminLogSnapshot(since_ts)
  requestAdminLogSnapshot(since_ts)
end

-- Module initialization
function GuildRoll_AdminLog:OnEnable()
  -- Load saved entries
  loadSavedEntries()
  
  -- Register CHAT_MSG_ADDON handler
  if not self.addonHandlerRegistered then
    self:RegisterEvent("CHAT_MSG_ADDON", function()
      handleAdminLogMessage(arg1, arg2, arg3, arg4)
    end)
    self.addonHandlerRegistered = true
  end
  
  -- Register Tablet UI
  if not T:IsRegistered("GuildRoll_AdminLog") then

    -- Safe wrapper for D:AddLine to prevent Dewdrop crashes (same pattern as other modules)
    local function safeAddLine(...)
      pcall(D.AddLine, D, unpack(arg))
    end

    T:Register("GuildRoll_AdminLog",
      "children", function()
        T:SetTitle("Admin Log")
        GuildRoll_AdminLog:OnTooltipUpdate()
      end,
      "showTitleWhenDetached", true,
      "showHintWhenDetached", true,
      "cantAttach", true,
      "menu", function()
        -- Sync option
        safeAddLine(
          "text", "Sync",
          "tooltipText", "Request admin log sync from other admins",
          "func", function()
            local since_ts = 0
            -- Use timestamp of most recent entry as baseline
            if table.getn(GuildRoll_adminLogOrder) > 0 then
              local lastId = GuildRoll_adminLogOrder[table.getn(GuildRoll_adminLogOrder)]
              local lastEntry = adminLogRuntime[lastId]
              if lastEntry then
                since_ts = lastEntry.ts
              end
            end
            requestAdminLogSnapshot(since_ts)
          end,
          "disabled", function()
            -- Disable if snapshot in progress
            if snapshotInProgress then
              return true
            end
            -- If we haven't seen any remote timestamps yet, allow sync
            if latestRemoteTS == 0 then
              return false
            end
            -- Disable if already up-to-date (remote <= local)
            local localTS = getLocalLatestTS()
            return latestRemoteTS <= localTS
          end
        )
        
        -- Filter by author
        safeAddLine(
          "text", "Filter by Author",
          "hasArrow", true,
          "hasSlider", false
        )
        safeAddLine(
          "text", "All Authors",
          "tooltipText", "Show all admin log entries",
          "func", function()
            filterAuthor = nil
            pcall(function() T:Refresh("GuildRoll_AdminLog") end)
          end,
          "level", 2
        )
        
        -- Build unique author list
        local authors = {}
        for i = 1, table.getn(GuildRoll_adminLogOrder) do
          local id = GuildRoll_adminLogOrder[i]
          local entry = adminLogRuntime[id]
          if entry and entry.author then
            authors[entry.author] = true
          end
        end
        
        for author, _ in pairs(authors) do
          safeAddLine(
            "text", author,
            "tooltipText", string.format("Show only entries by %s", author),
            "func", function()
              filterAuthor = author
              pcall(function() T:Refresh("GuildRoll_AdminLog") end)
            end,
            "level", 2
          )
        end
        
        -- Search
        safeAddLine(
          "text", "Search",
          "tooltipText", "Search admin log entries",
          "func", function()
            StaticPopup_Show("GUILDROLL_ADMINLOG_SEARCH")
          end
        )
        
        -- Clear search
        if searchText then
          safeAddLine(
            "text", "Clear Search",
            "tooltipText", "Clear search filter",
            "func", function()
              searchText = nil
              pcall(function() T:Refresh("GuildRoll_AdminLog") end)
            end
          )
        end
        
        -- Refresh
        safeAddLine(
          "text", "Refresh",
          "tooltipText", "Refresh admin log display",
          "func", function()
            pcall(function() T:Refresh("GuildRoll_AdminLog") end)
          end
        )
        
        -- Clear (GuildMaster only)
        safeAddLine(
          "text", "Clear",
          "tooltipText", "Clear all admin log entries (GuildMaster only)",
          "func", function()
            StaticPopup_Show("GUILDROLL_ADMINLOG_CLEAR_CONFIRM")
          end,
          "disabled", function()
            local isGuildMaster = false
            if IsGuildLeader then
              local ok, result = pcall(function() return IsGuildLeader() end)
              if ok and result then
                isGuildMaster = true
              end
            end
            return not isGuildMaster
          end
        )
      end
    )
    
    -- Ensure tooltip has owner
    pcall(function()
      if T and T.registry and T.registry.GuildRoll_AdminLog and T.registry.GuildRoll_AdminLog.tooltip then
        if not T.registry.GuildRoll_AdminLog.tooltip.owner then
          T.registry.GuildRoll_AdminLog.tooltip.owner = GuildRoll:EnsureTabletOwner()
        end
      end
    end)
  end
  
  -- Open UI if not attached
  if not T:IsAttached("GuildRoll_AdminLog") then
    pcall(function() T:Open("GuildRoll_AdminLog") end)
  end

  -- Defensive: ensure detached frame owner & ESC behavior consistent with other modules
  pcall(function() GuildRoll_AdminLog:setHideScript() end)
end

function GuildRoll_AdminLog:OnDisable()
  pcall(function() T:Close("GuildRoll_AdminLog") end)
end

-- Ensure detached frame owner and ESC handling (coherent with other modules)
function GuildRoll_AdminLog:setHideScript()
  local frame = GuildRoll:FindDetachedFrame("GuildRoll_AdminLog")
  if frame then
    if not frame.owner then
      frame.owner = "GuildRoll_AdminLog"
    end
    GuildRoll:make_escable(frame:GetName(), "add")
    if frame.SetScript then
      frame:SetScript("OnHide", nil)
      frame:SetScript("OnHide", function(f)
          pcall(function()
            if f and f.SetScript then
              f:SetScript("OnHide", nil)
            end
          end)
        end)
    end
  end
end

function GuildRoll_AdminLog:OnTooltipUpdate()
  local cat = T:AddCategory(
    "columns", 3,
    "text", "Time",
    "child_textR", 1,
    "child_textG", 1,
    "child_textB", 1,
    "child_justify", "LEFT",
    "text2", "Author",
    "child_text2R", 0.5,
    "child_text2G", 1,
    "child_text2B", 0.5,
    "child_justify2", "LEFT",
    "text3", "Action",
    "child_text3R", 1,
    "child_text3G", 1,
    "child_text3B", 0.5,
    "child_justify3", "LEFT"
  )
  
  -- Build filtered entry list
  local displayEntries = {}
  for i = 1, table.getn(GuildRoll_adminLogOrder) do
    local id = GuildRoll_adminLogOrder[i]
    local entry = adminLogRuntime[id]
    
    if entry then
      -- Apply filters
      local include = true
      
      if filterAuthor and entry.author ~= filterAuthor then
        include = false
      end
      
      if searchText and searchText ~= "" then
        local searchLower = string.lower(searchText)
        local actionLower = string.lower(entry.action or "")
        if not string.find(actionLower, searchLower, 1, true) then
          include = false
        end
      end
      
      if include then
        table.insert(displayEntries, entry)
      end
    end
  end
  
  -- Sort by timestamp descending (newest first)
  table.sort(displayEntries, function(a, b)
    return (a.ts or 0) > (b.ts or 0)
  end)
  
  -- Display entries
  if table.getn(displayEntries) == 0 then
    cat:AddLine(
      "text", "No entries",
      "text2", "",
      "text3", ""
    )
  else
    for i = 1, table.getn(displayEntries) do
      local entry = displayEntries[i]
      local timeStr = date("%Y-%m-%d %H:%M:%S", entry.ts)
      
      -- Check if this is a raid entry
      if entry.raid_details then
        local isExpanded = expandedRaidEntries[entry.id]
        local expandIcon = isExpanded and "[-] " or "[+] "
        
        cat:AddLine(
          "text", timeStr,
          "text2", entry.author or "Unknown",
          "text3", expandIcon .. (entry.action or ""),
          "func", function()
            -- Toggle expansion
            if expandedRaidEntries[entry.id] then
              expandedRaidEntries[entry.id] = nil
            else
              expandedRaidEntries[entry.id] = true
            end
            pcall(function() T:Refresh("GuildRoll_AdminLog") end)
          end
        )
        
        -- If expanded, show player details
        if isExpanded and entry.raid_details.players then
          for j = 1, table.getn(entry.raid_details.players) do
            local player = entry.raid_details.players[j]
            local counts = entry.raid_details.counts[player] or {old=0, new=0}
            local countsText = string.format("Prev: %d, New: %d", counts.old, counts.new)
            
            cat:AddLine(
              "text", "",
              "text2", "  " .. player,
              "text3", countsText,
              "text2R", 0.7,
              "text2G", 0.7,
              "text2B", 0.7,
              "text3R", 0.7,
              "text3G", 0.7,
              "text3B", 0.7
            )
          end
        end
      else
        -- Regular entry (non-raid)
        cat:AddLine(
          "text", timeStr,
          "text2", entry.author or "Unknown",
          "text3", entry.action or ""
        )
      end
    end
  end
  
  -- Show filter/search status
  if filterAuthor or searchText then
    local statusParts = {}
    if filterAuthor then
      table.insert(statusParts, string.format("Author: %s", filterAuthor))
    end
    if searchText then
      table.insert(statusParts, string.format("Search: %s", searchText))
    end
    T:SetHint(string.format("Filtered - %s", table.concat(statusParts, ", ")))
  else
    T:SetHint(string.format("%d total entries", table.getn(GuildRoll_adminLogOrder)))
  end
end

function GuildRoll_AdminLog:Toggle()
  -- Defensive check: ensure Tablet is registered before checking if attached
  if not T:IsRegistered("GuildRoll_AdminLog") then
    return
  end
  
  if T:IsAttached("GuildRoll_AdminLog") then
    pcall(function() T:Detach("GuildRoll_AdminLog") end)
    if T.IsLocked and T:IsLocked("GuildRoll_AdminLog") then
      pcall(function() T:ToggleLocked("GuildRoll_AdminLog") end)
    end
  else
    pcall(function() T:Attach("GuildRoll_AdminLog") end)
  end
end

-- Static popup for search
StaticPopupDialogs["GUILDROLL_ADMINLOG_SEARCH"] = {
  text = "Search Admin Log:",
  button1 = TEXT(ACCEPT),
  button2 = TEXT(CANCEL),
  hasEditBox = 1,
  maxLetters = 50,
  OnAccept = function()
    local editBox = getglobal(this:GetParent():GetName().."EditBox")
    local text = editBox:GetText()
    if text and text ~= "" then
      searchText = text
      pcall(function() T:Refresh("GuildRoll_AdminLog") end)
    end
  end,
  OnShow = function()
    getglobal(this:GetName().."EditBox"):SetText(searchText or "")
    getglobal(this:GetName().."EditBox"):SetFocus()
  end,
  OnHide = function()
    if ChatFrameEditBox:IsVisible() then
      ChatFrameEditBox:SetFocus()
    end
    getglobal(this:GetParent():GetName().."EditBox"):SetText("")
  end,
  EditBoxOnEnterPressed = function()
    local editBox = getglobal(this:GetParent():GetName().."EditBox")
    local text = editBox:GetText()
    if text and text ~= "" then
      searchText = text
      pcall(function() T:Refresh("GuildRoll_AdminLog") end)
    end
    this:GetParent():Hide()
  end,
  EditBoxOnEscapePressed = function()
    this:GetParent():Hide()
  end,
  timeout = 0,
  exclusive = 1,
  whileDead = 1,
  hideOnEscape = 1
}

-- Static popup for clear confirmation
StaticPopupDialogs["GUILDROLL_ADMINLOG_CLEAR_CONFIRM"] = {
  text = "This will permanently delete all Admin Log entries. Only the GuildMaster can do this. Continue?",
  button1 = TEXT(ACCEPT),
  button2 = TEXT(CANCEL),
  OnAccept = function()
    -- Double-check GuildMaster status
    local isGuildMaster = false
    if IsGuildLeader then
      local ok, result = pcall(function() return IsGuildLeader() end)
      if ok and result then
        isGuildMaster = true
      end
    end
    
    if isGuildMaster then
      -- Clear all entries
      GuildRoll_adminLogSaved = {}
      GuildRoll_adminLogOrder = {}
      adminLogRuntime = {}
      expandedRaidEntries = {}
      
      -- Refresh UI
      pcall(function() T:Refresh("GuildRoll_AdminLog") end)
      
      GuildRoll:defaultPrint("Admin log cleared.")
    else
      GuildRoll:defaultPrint("Only the GuildMaster can clear the admin log.")
    end
  end,
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 1
}

-- Slash commands
SLASH_GADMINLOG1 = "/gadminlog"
SlashCmdList["GADMINLOG"] = function(msg)
  if not GuildRoll then
    DEFAULT_CHAT_FRAME:AddMessage("GuildRoll not loaded.")
    return
  end
  
  local cmd, rest = msg:match("^(%S*)%s*(.-)$")
  cmd = string.lower(cmd or "")
  
  if cmd == "add" then
    GuildRoll:AdminLogAdd(rest)
  elseif cmd == "sync" then
    local since_ts = 0
    if table.getn(GuildRoll_adminLogOrder) > 0 then
      local lastId = GuildRoll_adminLogOrder[table.getn(GuildRoll_adminLogOrder)]
      local lastEntry = adminLogRuntime[lastId]
      if lastEntry then
        since_ts = lastEntry.ts
      end
    end
    GuildRoll:RequestAdminLogSnapshot(since_ts)
  elseif cmd == "find" then
    searchText = rest
    if T and T:IsRegistered("GuildRoll_AdminLog") then
      pcall(function() T:Refresh("GuildRoll_AdminLog") end)
    end
    GuildRoll:defaultPrint(string.format("Search set to: %s", rest))
  elseif cmd == "show" then
    if T and T:IsRegistered("GuildRoll_AdminLog") then
      GuildRoll_AdminLog:Toggle()
    end
  elseif cmd == "info" then
    GuildRoll:defaultPrint(string.format("Admin log entries: %d", table.getn(GuildRoll_adminLogOrder)))
  else
    GuildRoll:defaultPrint("AdminLog commands:")
    GuildRoll:defaultPrint("/gadminlog add <text> - Add new admin log entry")
    GuildRoll:defaultPrint("/gadminlog sync - Request sync from other admins")
    GuildRoll:defaultPrint("/gadminlog find <text> - Search admin log")
    GuildRoll:defaultPrint("/gadminlog show - Toggle admin log UI")
    GuildRoll:defaultPrint("/gadminlog info - Show admin log stats")
  end
end
