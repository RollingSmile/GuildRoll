--[[
AdminLog Module for GuildRoll (v2)
Provides persistent, guild-wide synchronized admin log for officers and guild leader.

ENTRY TYPES:
  AWARD        - EP awarded to a single player
  PENALTY      - EP penalty applied to a single player
  AWARD_RAID   - EP awarded to raid (expandable, shows per-player list)
  PENALTY_RAID - EP penalty applied to raid (expandable)
  DECAY        - EP decay applied globally
  RESET        - All EP reset to zero
  IMPORT       - EP standings imported
  MANUAL       - Officer note manually modified

SERIALIZATION FORMAT:
  New entries:    id|ts|author||TYPE|field1|field2|...
  Legacy entries: id|ts|author|action_text[|RAID|ep|count|players]
  Pipe characters inside fields are escaped as ||

SYNC PROTOCOL:
  ADMINLOG;ADD;version;serialized_entry   - broadcast new entry
  ADMINLOG;REQ;version;since_ts           - request snapshot
  ADMINLOG;SNAP;version;chunk_data        - snapshot chunk
  ADMINLOG;SNAP_END;version;total_count   - snapshot complete
  ADMINLOG;CLEAR;version                  - clear all entries (GuildMaster only)
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
local adminLogRuntime = {}       -- runtime cache indexed by entry id
local snapshotInProgress = false
local snapshotBuffer = {}
local snapshotMaxTS = 0
local latestRemoteTS = 0
local expandedRaidEntries = {}   -- which raid entries are expanded (key = entry.id)
local filterAuthor = nil
local searchText = nil

-- Pending messages queue for roster timing tolerance
local pending_messages = {}
local pending_retry_scheduled = false
local lastSyncRequest = 0

-- Constants
local PROTOCOL_VERSION = 1
local CHUNK_SIZE = 10
local SYNC_THROTTLE_SEC = 5
local SNAPSHOT_TIMEOUT_SEC = 10
local RETRY_INTERVAL_SEC = 2
local MAX_RETRIES = 5
local AUTO_SYNC_DELAY_SEC = 5

-- WoW color codes used for action string rendering
local CLR_GREEN  = "|cff00ff00"
local CLR_RED    = "|cffff0000"
local CLR_YELLOW = "|cffffff00"
local CLR_WHITE  = "|cffffffff"
local CLR_END    = "|r"

-- ============================================================
-- Helper utilities
-- ============================================================

local function debugPrint(msg)
  if GuildRoll and GuildRoll.DEBUG and msg then
    pcall(function()
      if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("[AdminLog Debug] " .. tostring(msg))
      end
    end)
  end
end

local function sendAdminSyncMessage(message, channel, target)
  channel = channel or "GUILD"
  local prefix = (GuildRoll and GuildRoll.ADDON_SYNC_PREFIX) or "GR_SYNC"
  debugPrint(string.format("sendAdminSyncMessage: prefix=%s channel=%s msg=%s",
    prefix, channel, string.sub(message, 1, 80)))
  pcall(function() SendAddonMessage(prefix, message, channel, target) end)
end

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

local function generateEntryId()
  return string.format("%d_%d", time(), math.random(1000, 9999))
end

-- ============================================================
-- Pending message queue (for roster timing tolerance)
-- ============================================================

-- Forward-declare so processPendingMessages can reference handleAdminLogMessage
local handleAdminLogMessage

local function processPendingMessages()
  pending_retry_scheduled = false
  if table.getn(pending_messages) == 0 then return end

  local remaining = {}
  local now = time()

  for i = 1, table.getn(pending_messages) do
    local pending = pending_messages[i]
    local sender_norm = pending.sender and string.gsub(pending.sender, "%-.*$", "") or pending.sender
    local name_g = nil
    if GuildRoll and GuildRoll.verifyGuildMember then
      pcall(function() name_g = GuildRoll:verifyGuildMember(sender_norm, true) end)
    end

    if name_g then
      pcall(function()
        handleAdminLogMessage(pending.prefix, pending.message, pending.channel, pending.sender)
      end)
    else
      pending.attempts = (pending.attempts or 0) + 1
      if pending.attempts < MAX_RETRIES then
        table.insert(remaining, pending)
      else
        debugPrint(string.format("Dropped pending message from %s after %d retries",
          sender_norm, pending.attempts))
      end
    end
  end

  pending_messages = remaining

  if table.getn(pending_messages) > 0 then
    if GuildRoll and GuildRoll.ScheduleEvent then
      local ok = pcall(function()
        GuildRoll:ScheduleEvent("GuildRoll_AdminLog_RetryPending",
          processPendingMessages, RETRY_INTERVAL_SEC)
        pending_retry_scheduled = true
      end)
      if not ok then pending_retry_scheduled = false end
    end
  end
end

-- ============================================================
-- Serialization helpers
-- ============================================================

local function escPipe(s)
  return string.gsub(tostring(s or ""), "|", "||")
end

-- Split data by unescaped pipe characters; || becomes a literal |
local function splitByPipe(data)
  local parts = {}
  local current = ""
  local i = 1
  while i <= string.len(data) do
    local c  = string.sub(data, i, i)
    local nc = string.sub(data, i + 1, i + 1)
    if c == "|" and nc == "|" then
      current = current .. "|"
      i = i + 2
    elseif c == "|" then
      table.insert(parts, current)
      current = ""
      i = i + 1
    else
      current = current .. c
      i = i + 1
    end
  end
  table.insert(parts, current)
  return parts
end

-- Serialize raid player list to "name:old:new:alt,..." format
local function serializeRaidPlayers(rd)
  local items = {}
  for i = 1, table.getn(rd.players or {}) do
    local p   = rd.players[i]
    local c   = rd.counts[p] or {old = 0, new = 0}
    local alt = (rd.alt_sources and rd.alt_sources[p]) or ""
    table.insert(items, string.format("%s:%d:%d:%s", p, c.old, c.new, alt))
  end
  return table.concat(items, ",")
end

-- Deserialize raid player list; returns players, counts, alt_sources
local function deserializeRaidPlayers(playersStr)
  local players     = {}
  local counts      = {}
  local alt_sources = {}
  if not playersStr or playersStr == "" then return players, counts, alt_sources end

  local entries = {}
  local cur = ""
  for j = 1, string.len(playersStr) do
    local c = string.sub(playersStr, j, j)
    if c == "," then
      table.insert(entries, cur)
      cur = ""
    else
      cur = cur .. c
    end
  end
  if cur ~= "" then table.insert(entries, cur) end

  for _, pEntry in ipairs(entries) do
    local pp = {}
    local pc = ""
    for m = 1, string.len(pEntry) do
      local c = string.sub(pEntry, m, m)
      if c == ":" then table.insert(pp, pc); pc = ""
      else pc = pc .. c end
    end
    if pc ~= "" then table.insert(pp, pc) end

    if table.getn(pp) >= 3 then
      local pName = pp[1]
      local oldEP = tonumber(pp[2]) or 0
      local newEP = tonumber(pp[3]) or 0
      table.insert(players, pName)
      counts[pName] = {old = oldEP, new = newEP}
      if pp[4] and pp[4] ~= "" then
        alt_sources[pName] = pp[4]
      end
    end
  end

  return players, counts, alt_sources
end

local function serializeEntry(entry)
  local id     = entry.id     or ""
  local ts     = entry.ts     or 0
  local author = entry.author or ""
  local at     = entry.action_type

  -- New structured format: id|ts|author||TYPE|data...
  -- (4th field is intentionally empty for backward compat with old clients)
  if at then
    local base = string.format("%s|%d|%s||%s", id, ts, author, at)

    if at == "AWARD" or at == "PENALTY" then
      return base
        .. "|" .. (entry.ep or 0)
        .. "|" .. escPipe(entry.player or "")
        .. "|" .. escPipe(entry.main   or "")

    elseif at == "AWARD_RAID" or at == "PENALTY_RAID" then
      local rd   = entry.raid_details or {players = {}, counts = {}, alt_sources = {}}
      local pStr = escPipe(serializeRaidPlayers(rd))
      return base .. "|" .. (entry.ep or 0) .. "|" .. pStr

    elseif at == "DECAY" then
      return base
        .. "|" .. (entry.decay_pct    or 0)
        .. "|" .. (entry.member_count or 0)

    elseif at == "RESET" then
      return base

    elseif at == "IMPORT" then
      return base .. "|" .. (entry.member_count or 0)

    elseif at == "MANUAL" then
      return base
        .. "|" .. escPipe(entry.player   or "")
        .. "|" .. escPipe(entry.old_note or "")
        .. "|" .. escPipe(entry.new_note or "")
    end
    -- Unknown type: fall through to legacy format below
  end

  -- Legacy format: id|ts|author|action_text[|RAID|ep|count|players]
  local action = escPipe(entry.action or "")
  local base   = string.format("%s|%d|%s|%s", id, ts, author, action)
  if entry.raid_details then
    local rd   = entry.raid_details
    local pStr = escPipe(serializeRaidPlayers(rd))
    base = base
      .. "|RAID|" .. (rd.ep or 0)
      .. "|"      .. table.getn(rd.players or {})
      .. "|"      .. pStr
  end
  return base
end

local function deserializeEntry(data)
  if not data then return nil end

  local parts = splitByPipe(data)
  if table.getn(parts) < 4 then return nil end

  local entry = {
    id     = parts[1],
    ts     = tonumber(parts[2]) or 0,
    author = parts[3],
  }

  local field4 = parts[4]  -- empty string for new format
  local field5 = parts[5]  -- TYPE keyword for new format, "RAID" for old raid

  -- New structured format: field4 == "" and field5 is a non-RAID keyword
  if field4 == "" and field5 and field5 ~= "" and field5 ~= "RAID" then
    local at = field5
    entry.action_type = at

    if at == "AWARD" or at == "PENALTY" then
      entry.ep     = tonumber(parts[6]) or 0
      entry.player = parts[7] or ""
      entry.main   = (parts[8] and parts[8] ~= "") and parts[8] or nil

    elseif at == "AWARD_RAID" or at == "PENALTY_RAID" then
      entry.ep = tonumber(parts[6]) or 0
      local players, counts, alt_sources = deserializeRaidPlayers(parts[7] or "")
      entry.raid_details = {
        ep          = entry.ep,
        players     = players,
        counts      = counts,
        alt_sources = alt_sources,
      }

    elseif at == "DECAY" then
      entry.decay_pct    = tonumber(parts[6]) or 0
      entry.member_count = tonumber(parts[7]) or 0

    elseif at == "RESET" then
      -- no extra fields

    elseif at == "IMPORT" then
      entry.member_count = tonumber(parts[6]) or 0

    elseif at == "MANUAL" then
      entry.player   = parts[6] or ""
      entry.old_note = parts[7] or ""
      entry.new_note = parts[8] or ""

    else
      -- Unknown type: degrade to raw display
      entry.action_type = nil
      entry.action      = ""
    end

    return entry
  end

  -- Old RAID format: field5 == "RAID"
  if field5 == "RAID" then
    local ep                          = tonumber(parts[6]) or 0
    local playersStr                  = parts[8] or ""
    local players, counts, alt_sources = deserializeRaidPlayers(playersStr)
    entry.action      = field4
    entry.ep          = ep
    entry.action_type = ep < 0 and "PENALTY_RAID" or "AWARD_RAID"
    entry.raid_details = {
      ep          = ep,
      players     = players,
      counts      = counts,
      alt_sources = alt_sources,
    }
    return entry
  end

  -- Legacy plain text format
  entry.action = field4
  return entry
end

-- ============================================================
-- Entry storage helpers
-- ============================================================

local function applyAdminLogEntry(entry)
  if not entry or not entry.id then return end
  if adminLogRuntime[entry.id] then return end  -- duplicate

  adminLogRuntime[entry.id]         = entry
  GuildRoll_adminLogSaved[entry.id] = entry

  local found = false
  for i = 1, table.getn(GuildRoll_adminLogOrder) do
    if GuildRoll_adminLogOrder[i] == entry.id then found = true; break end
  end
  if not found then
    table.insert(GuildRoll_adminLogOrder, entry.id)
  end

  -- Trim to last 400 entries
  local maxEntries = 400
  while table.getn(GuildRoll_adminLogOrder) > maxEntries do
    local oldId = GuildRoll_adminLogOrder[1]
    table.remove(GuildRoll_adminLogOrder, 1)
    GuildRoll_adminLogSaved[oldId] = nil
    adminLogRuntime[oldId]         = nil
  end
end

local function loadSavedEntries()
  adminLogRuntime = {}
  for i = 1, table.getn(GuildRoll_adminLogOrder) do
    local id    = GuildRoll_adminLogOrder[i]
    local entry = GuildRoll_adminLogSaved[id]
    if entry then adminLogRuntime[id] = entry end
  end
end

-- ============================================================
-- Network broadcast / snapshot
-- ============================================================

local function broadcastAdminLogEntry(entry)
  if not GuildRoll or not GuildRoll.IsAdmin or not GuildRoll:IsAdmin() then return end
  local msg = string.format("ADMINLOG;ADD;%d;%s", PROTOCOL_VERSION, serializeEntry(entry))
  sendAdminSyncMessage(msg)
end

local function requestAdminLogSnapshot(since_ts)
  if not GuildRoll or not GuildRoll.IsAdmin or not GuildRoll:IsAdmin() then return end

  local now = time()
  if now - lastSyncRequest < SYNC_THROTTLE_SEC then
    GuildRoll:defaultPrint(string.format("Sync throttled. Wait %d seconds.",
      SYNC_THROTTLE_SEC - (now - lastSyncRequest)))
    return
  end
  lastSyncRequest    = now
  snapshotInProgress = true

  since_ts = since_ts or 0
  sendAdminSyncMessage(string.format("ADMINLOG;REQ;%d;%d", PROTOCOL_VERSION, since_ts))
  GuildRoll:defaultPrint("Admin log sync requested...")

  if T and T:IsRegistered("GuildRoll_AdminLog") then
    pcall(function() T:Refresh("GuildRoll_AdminLog") end)
  end
end

local function sendSnapshot(target, since_ts)
  if not GuildRoll or not GuildRoll.IsAdmin or not GuildRoll:IsAdmin() then return end

  since_ts = since_ts or 0
  local entries = {}

  for i = 1, table.getn(GuildRoll_adminLogOrder) do
    local id    = GuildRoll_adminLogOrder[i]
    local entry = adminLogRuntime[id]
    if entry and entry.ts > since_ts then
      table.insert(entries, entry)
    end
  end

  if table.getn(entries) == 0 then
    sendAdminSyncMessage(string.format("ADMINLOG;SNAP_END;%d;0", PROTOCOL_VERSION),
      "WHISPER", target)
    return
  end

  for i = 1, table.getn(entries), CHUNK_SIZE do
    local chunkParts = {}
    for j = i, math.min(i + CHUNK_SIZE - 1, table.getn(entries)) do
      table.insert(chunkParts, serializeEntry(entries[j]))
    end
    sendAdminSyncMessage(
      string.format("ADMINLOG;SNAP;%d;%s", PROTOCOL_VERSION, table.concat(chunkParts, ";;")),
      "WHISPER", target)
  end

  sendAdminSyncMessage(
    string.format("ADMINLOG;SNAP_END;%d;%d", PROTOCOL_VERSION, table.getn(entries)),
    "WHISPER", target)
end

-- handleAdminLogMessage is assigned here so processPendingMessages can call it
handleAdminLogMessage = function(prefix, message, channel, sender)
  local syncPrefix   = (GuildRoll and GuildRoll.ADDON_SYNC_PREFIX) or "GR_SYNC"
  local legacyPrefix = (GuildRoll and GuildRoll.VARS and GuildRoll.VARS.prefix) or "RRG_"

  if not prefix or (prefix ~= syncPrefix and prefix ~= legacyPrefix) then return end
  if not message or not string.find(message, "^ADMINLOG;") then return end

  local sender_norm = sender and string.gsub(sender, "%-.*$", "") or sender
  local name_g = nil
  pcall(function() name_g = GuildRoll:verifyGuildMember(sender_norm, true) end)

  if not name_g then
    table.insert(pending_messages, {
      prefix = prefix, message = message, channel = channel, sender = sender,
      attempts = 0, queued_at = time()
    })
    if not pending_retry_scheduled then
      local ok = pcall(function()
        GuildRoll:ScheduleEvent("GuildRoll_AdminLog_RetryPending",
          processPendingMessages, RETRY_INTERVAL_SEC)
        pending_retry_scheduled = true
      end)
      if not ok then pending_retry_scheduled = false end
    end
    return
  end

  -- Parse semicolon-separated header
  local parts = {}
  local cur   = ""
  for i = 1, string.len(message) do
    local c = string.sub(message, i, i)
    if c == ";" then table.insert(parts, cur); cur = ""
    else cur = cur .. c end
  end
  table.insert(parts, cur)

  if table.getn(parts) < 3 then return end

  local msgType = parts[2]
  local version = tonumber(parts[3]) or 0

  if version ~= PROTOCOL_VERSION then
    debugPrint(string.format("Protocol version mismatch (got %d, expected %d)", version, PROTOCOL_VERSION))
    return
  end

  if msgType == "ADD" then
    if table.getn(parts) < 4 then return end
    local entry = deserializeEntry(parts[4])
    if entry then
      applyAdminLogEntry(entry)
      if entry.ts and entry.ts > latestRemoteTS then latestRemoteTS = entry.ts end
      if T and T:IsRegistered("GuildRoll_AdminLog") then
        pcall(function() T:Refresh("GuildRoll_AdminLog") end)
      end
    end

  elseif msgType == "REQ" then
    if not GuildRoll:IsAdmin() then return end
    if table.getn(parts) < 4 then return end
    sendSnapshot(sender, tonumber(parts[4]) or 0)

  elseif msgType == "SNAP" then
    if table.getn(parts) < 4 then return end
    local chunkData = parts[4]

    -- Split by ;; (chunk separator)
    local entryStrings = {}
    local ecur = ""
    local i = 1
    while i <= string.len(chunkData) do
      local c  = string.sub(chunkData, i, i)
      local nc = string.sub(chunkData, i + 1, i + 1)
      if c == ";" and nc == ";" then
        if ecur ~= "" then table.insert(entryStrings, ecur); ecur = "" end
        i = i + 2
      else
        ecur = ecur .. c
        i = i + 1
      end
    end
    if ecur ~= "" then table.insert(entryStrings, ecur) end

    for _, eStr in ipairs(entryStrings) do
      local entry = deserializeEntry(eStr)
      if entry then
        table.insert(snapshotBuffer, entry)
        if entry.ts and entry.ts > snapshotMaxTS then snapshotMaxTS = entry.ts end
      end
    end

  elseif msgType == "SNAP_END" then
    for i = 1, table.getn(snapshotBuffer) do
      applyAdminLogEntry(snapshotBuffer[i])
    end

    GuildRoll:defaultPrint(string.format("Admin log sync complete: %d new entries received.",
      table.getn(snapshotBuffer)))

    if snapshotMaxTS > latestRemoteTS then latestRemoteTS = snapshotMaxTS end

    snapshotInProgress = false
    snapshotMaxTS      = 0
    snapshotBuffer     = {}

    if T and T:IsRegistered("GuildRoll_AdminLog") then
      pcall(function() T:Refresh("GuildRoll_AdminLog") end)
    end

  elseif msgType == "CLEAR" then
    GuildRoll_adminLogSaved = {}
    GuildRoll_adminLogOrder = {}
    adminLogRuntime         = {}
    expandedRaidEntries     = {}

    if T and T:IsRegistered("GuildRoll_AdminLog") then
      pcall(function() T:Refresh("GuildRoll_AdminLog") end)
    end
    GuildRoll:defaultPrint(string.format("Admin log cleared by %s.", sender_norm))
  end
end

-- ============================================================
-- Internal: create + broadcast a structured entry
-- ============================================================

local function _addEntry(entry)
  applyAdminLogEntry(entry)
  broadcastAdminLogEntry(entry)
  if T and T:IsRegistered("GuildRoll_AdminLog") then
    pcall(function() T:Refresh("GuildRoll_AdminLog") end)
  end
end

-- ============================================================
-- Public API
-- ============================================================

-- Award EP to a single player.
-- ep:         positive integer
-- playerName: character who receives EP (main when alt-pooling applies)
-- mainName:   alt character whose main received the award (nil if not applicable)
function GuildRoll:AdminLogAddAward(ep, playerName, mainName)
  if not self:IsAdmin() then return end
  _addEntry({
    id          = generateEntryId(),
    ts          = time(),
    author      = UnitName("player") or "Unknown",
    action_type = "AWARD",
    ep          = math.abs(ep or 0),
    player      = playerName or "",
    main        = (mainName and mainName ~= "") and mainName or nil,
  })
end

-- Penalty EP to a single player.
-- ep:         integer (absolute value is used; stored negative)
-- playerName: character penalized (main when alt-pooling applies)
-- mainName:   alt character name (nil if not applicable)
function GuildRoll:AdminLogAddPenalty(ep, playerName, mainName)
  if not self:IsAdmin() then return end
  _addEntry({
    id          = generateEntryId(),
    ts          = time(),
    author      = UnitName("player") or "Unknown",
    action_type = "PENALTY",
    ep          = -math.abs(ep or 0),
    player      = playerName or "",
    main        = (mainName and mainName ~= "") and mainName or nil,
  })
end

-- Award or penalty EP to raid.
-- ep:        integer (positive = award, negative = penalty)
-- raid_data: { players={}, counts={player={old,new}}, alt_sources={player=altName} }
function GuildRoll:AdminLogAddRaid(ep, raid_data)
  if not self:IsAdmin() then return end
  if not raid_data or not raid_data.players or table.getn(raid_data.players) == 0 then return end

  _addEntry({
    id          = generateEntryId(),
    ts          = time(),
    author      = UnitName("player") or "Unknown",
    action_type = (ep < 0) and "PENALTY_RAID" or "AWARD_RAID",
    ep          = ep,
    raid_details = {
      ep          = ep,
      players     = raid_data.players,
      counts      = raid_data.counts,
      alt_sources = raid_data.alt_sources or {},
    },
  })
end

-- EP decay applied globally.
-- decayPct:    percentage decayed (e.g. 10 for 10%)
-- memberCount: number of members affected
function GuildRoll:AdminLogAddDecay(decayPct, memberCount)
  if not self:IsAdmin() then return end
  _addEntry({
    id           = generateEntryId(),
    ts           = time(),
    author       = UnitName("player") or "Unknown",
    action_type  = "DECAY",
    decay_pct    = decayPct or 0,
    member_count = memberCount or 0,
  })
end

-- All EP reset to zero.
function GuildRoll:AdminLogAddReset()
  if not self:IsAdmin() then return end
  _addEntry({
    id          = generateEntryId(),
    ts          = time(),
    author      = UnitName("player") or "Unknown",
    action_type = "RESET",
  })
end

-- EP standings imported.
-- memberCount: number of members imported
function GuildRoll:AdminLogAddImport(memberCount)
  if not self:IsAdmin() then return end
  _addEntry({
    id           = generateEntryId(),
    ts           = time(),
    author       = UnitName("player") or "Unknown",
    action_type  = "IMPORT",
    member_count = memberCount or 0,
  })
end

-- Officer note manually modified.
-- playerName: character whose note changed
-- oldNote:    previous officer note string
-- newNote:    new officer note string
function GuildRoll:AdminLogAddManualModify(playerName, oldNote, newNote)
  if not self:IsAdmin() then return end
  _addEntry({
    id          = generateEntryId(),
    ts          = time(),
    author      = UnitName("player") or "Unknown",
    action_type = "MANUAL",
    player      = playerName or "",
    old_note    = oldNote or "",
    new_note    = newNote or "",
  })
end

-- Backward-compatible legacy method.
-- Stores a free-form text entry (no action_type; displayed as plain text).
function GuildRoll:AdminLogAdd(text)
  if not self:IsAdmin() then return end
  if not text or text == "" then return end
  _addEntry({
    id     = generateEntryId(),
    ts     = time(),
    author = UnitName("player") or "Unknown",
    action = text,
  })
end

-- Request a delta or full snapshot from other admins online.
function GuildRoll:RequestAdminLogSnapshot(since_ts)
  requestAdminLogSnapshot(since_ts)
end

-- ============================================================
-- Module lifecycle
-- ============================================================

function GuildRoll_AdminLog:OnEnable()
  loadSavedEntries()

  -- Register CHAT_MSG_ADDON handler
  if not self.addonHandlerRegistered then
    self:RegisterEvent("CHAT_MSG_ADDON", function(prefix, message, channel, sender)
      handleAdminLogMessage(prefix, message, channel, sender)
    end)
    self.addonHandlerRegistered = true
  end

  -- Auto-sync: request missing entries after guild roster becomes available
  if GuildRoll and GuildRoll.IsAdmin and GuildRoll:IsAdmin() then
    pcall(function()
      GuildRoll:ScheduleEvent("GuildRoll_AdminLog_AutoSync", function()
        requestAdminLogSnapshot(getLocalLatestTS())
      end, AUTO_SYNC_DELAY_SEC)
    end)
  end

  -- Register Tablet UI
  if not T:IsRegistered("GuildRoll_AdminLog") then
    T:Register("GuildRoll_AdminLog",
      "children", function()
        T:SetTitle("Admin Log")
        GuildRoll_AdminLog:OnTooltipUpdate()
      end,
      "showTitleWhenDetached", true,
      "showHintWhenDetached", true,
      "cantAttach", true,
      "menu", function()
        -- Snapshot state indicator
        if snapshotInProgress then
          GuildRoll:SafeDewdropAddLine("text", "Snapshot in progress...", "isTitle", true)
        end

        -- Last remote timestamp (informational)
        local tsText
        if latestRemoteTS > 0 then
          tsText = "Last remote TS: " .. date("%Y-%m-%d %H:%M:%S", latestRemoteTS)
        else
          tsText = "Last remote TS: Never synced"
        end
        GuildRoll:SafeDewdropAddLine("text", tsText, "isTitle", true)

        -- Request full sync (from ts=0)
        GuildRoll:SafeDewdropAddLine(
          "text", "Request full sync",
          "tooltipText", "Request complete snapshot from peers",
          "func", function()
            snapshotInProgress = true
            requestAdminLogSnapshot(0)
            pcall(function()
              GuildRoll:ScheduleEvent("GuildRoll_AdminLog_ClearSnapshotFlag", function()
                snapshotInProgress = false
                if T and T:IsRegistered("GuildRoll_AdminLog") then
                  pcall(function() T:Refresh("GuildRoll_AdminLog") end)
                end
              end, SNAPSHOT_TIMEOUT_SEC)
            end)
            if T and T:IsRegistered("GuildRoll_AdminLog") then
              pcall(function() T:Refresh("GuildRoll_AdminLog") end)
            end
          end,
          "disabled", function()
            return snapshotInProgress or (time() - lastSyncRequest < SYNC_THROTTLE_SEC)
          end
        )

        -- Delta sync (from local latest)
        GuildRoll:SafeDewdropAddLine(
          "text", "Sync",
          "tooltipText", "Request delta sync (missing entries only)",
          "func", function()
            requestAdminLogSnapshot(getLocalLatestTS())
          end,
          "disabled", function()
            if snapshotInProgress then return true end
            if latestRemoteTS == 0 then return false end
            return latestRemoteTS <= getLocalLatestTS()
          end
        )

        -- Filter by author
        GuildRoll:SafeDewdropAddLine("text", "Filter by Author", "hasArrow", true)
        GuildRoll:SafeDewdropAddLine(
          "text", "All Authors",
          "tooltipText", "Show all entries",
          "func", function()
            filterAuthor = nil
            pcall(function() T:Refresh("GuildRoll_AdminLog") end)
          end,
          "level", 2
        )
        local authors = {}
        for i = 1, table.getn(GuildRoll_adminLogOrder) do
          local id    = GuildRoll_adminLogOrder[i]
          local entry = adminLogRuntime[id]
          if entry and entry.author then authors[entry.author] = true end
        end
        for author in pairs(authors) do
          GuildRoll:SafeDewdropAddLine(
            "text", author,
            "tooltipText", "Show only entries by " .. author,
            "func", function()
              filterAuthor = author
              pcall(function() T:Refresh("GuildRoll_AdminLog") end)
            end,
            "level", 2
          )
        end

        -- Search
        GuildRoll:SafeDewdropAddLine(
          "text", "Search",
          "tooltipText", "Search admin log entries",
          "func", function() StaticPopup_Show("GUILDROLL_ADMINLOG_SEARCH") end
        )
        if searchText then
          GuildRoll:SafeDewdropAddLine(
            "text", "Clear Search",
            "tooltipText", "Clear search filter",
            "func", function()
              searchText = nil
              pcall(function() T:Refresh("GuildRoll_AdminLog") end)
            end
          )
        end

        -- Refresh
        GuildRoll:SafeDewdropAddLine(
          "text", "Refresh",
          "tooltipText", "Refresh admin log display",
          "func", function() pcall(function() T:Refresh("GuildRoll_AdminLog") end) end
        )

        -- Clear Local
        GuildRoll:SafeDewdropAddLine(
          "text", "Clear Local",
          "tooltipText", "Clear local admin log (does not affect other clients)",
          "func", function()
            GuildRoll_adminLogSaved = {}
            GuildRoll_adminLogOrder = {}
            adminLogRuntime         = {}
            expandedRaidEntries     = {}
            pcall(function() T:Refresh("GuildRoll_AdminLog") end)
            GuildRoll:defaultPrint("Admin log cleared (local).")
          end
        )

        -- Clear globally (GuildMaster only)
        GuildRoll:SafeDewdropAddLine(
          "text", "Clear",
          "tooltipText", "Clear all admin log entries globally (GuildMaster only)",
          "func", function() StaticPopup_Show("GUILDROLL_ADMINLOG_CLEAR_CONFIRM") end,
          "disabled", function()
            if IsGuildLeader then
              local ok, result = pcall(function() return IsGuildLeader() end)
              if ok and result then return false end
            end
            return true
          end
        )
      end
    )

    pcall(function()
      if T and T.registry and T.registry.GuildRoll_AdminLog
          and T.registry.GuildRoll_AdminLog.tooltip
          and not T.registry.GuildRoll_AdminLog.tooltip.owner then
        T.registry.GuildRoll_AdminLog.tooltip.owner = GuildRoll:EnsureTabletOwner()
      end
    end)
  end

  if not T:IsAttached("GuildRoll_AdminLog") then
    pcall(function() T:Open("GuildRoll_AdminLog") end)
  end

  pcall(function() GuildRoll_AdminLog:setHideScript() end)
end

function GuildRoll_AdminLog:OnDisable()
  pcall(function() T:Close("GuildRoll_AdminLog") end)
end

function GuildRoll_AdminLog:setHideScript()
  local frame = GuildRoll:FindDetachedFrame("GuildRoll_AdminLog")
  if frame then
    if not frame.owner then frame.owner = "GuildRoll_AdminLog" end
    GuildRoll:make_escable(frame:GetName(), "add")
    if frame.SetScript then
      frame:SetScript("OnHide", nil)
      frame:SetScript("OnHide", function(f)
        pcall(function()
          if T and T.IsAttached and not T:IsAttached("GuildRoll_AdminLog") then
            T:Attach("GuildRoll_AdminLog")
          end
          if f and f.SetScript then f:SetScript("OnHide", nil) end
        end)
      end)
    end
  end
end

function GuildRoll_AdminLog:Toggle()
  if not T:IsRegistered("GuildRoll_AdminLog") then return end
  if T:IsAttached("GuildRoll_AdminLog") then
    pcall(function() T:Detach("GuildRoll_AdminLog") end)
    if T.IsLocked and T:IsLocked("GuildRoll_AdminLog") then
      pcall(function() T:ToggleLocked("GuildRoll_AdminLog") end)
    end
    self:setHideScript()
  else
    pcall(function() T:Attach("GuildRoll_AdminLog") end)
  end
end

-- ============================================================
-- UI rendering
-- ============================================================

-- Build the colored action string for a given entry.
-- Returns: actionStr (string with WoW color codes), isExpandable (bool)
local function buildActionLine(entry)
  local author = entry.author or "Unknown"
  local at     = entry.action_type

  local function w(s)
    return CLR_WHITE .. tostring(s or "") .. CLR_END
  end

  local function expandIcon(id)
    if expandedRaidEntries[id] then
      return "  " .. CLR_YELLOW .. "[-]" .. CLR_END
    else
      return "  " .. CLR_YELLOW .. "[+]" .. CLR_END
    end
  end

  if at == "AWARD" then
    local player = entry.player or ""
    local main   = entry.main
    local target = main and (player .. " (main: " .. main .. ")") or player
    local msg    = string.format("%s: %d EP to %s", author, entry.ep or 0, target)
    return CLR_GREEN .. "+" .. CLR_END .. " " .. w(msg), false

  elseif at == "PENALTY" then
    local player = entry.player or ""
    local main   = entry.main
    local target = main and (player .. " (main: " .. main .. ")") or player
    local msg    = string.format("%s: %d EP to %s", author, math.abs(entry.ep or 0), target)
    return CLR_RED .. "-" .. CLR_END .. " " .. w(msg), false

  elseif at == "AWARD_RAID" then
    local msg = string.format("%s: %d EP to Raid", author, math.abs(entry.ep or 0))
    return CLR_GREEN .. "+" .. CLR_END .. " " .. w(msg) .. expandIcon(entry.id), true

  elseif at == "PENALTY_RAID" then
    local msg = string.format("%s: %d EP to Raid", author, math.abs(entry.ep or 0))
    return CLR_RED .. "-" .. CLR_END .. " " .. w(msg) .. expandIcon(entry.id), true

  elseif at == "DECAY" then
    local msg = string.format("%s: Decayed all standings by %.0f%%",
      author, entry.decay_pct or 0)
    return w(msg), false

  elseif at == "RESET" then
    return w(author .. ": Reset all EP to 0"), false

  elseif at == "IMPORT" then
    local msg = string.format("%s: Imported EP standings for %d members",
      author, entry.member_count or 0)
    return w(msg), false

  elseif at == "MANUAL" then
    local msg = string.format('%s: Manually modified %s OLD: "%s" NEW: "%s"',
      author, entry.player or "", entry.old_note or "", entry.new_note or "")
    return w(msg), false

  else
    -- Legacy / raw text entry
    return w(author .. ": " .. (entry.action or "")), false
  end
end

-- Build per-player sub-entry line for an expanded raid view.
-- mainName: main player who received EP
-- altName:  alt character name (displayed as primary; nil if direct award)
-- delta:    EP delta (new - old)
local function buildPlayerSubLine(mainName, altName, delta)
  local displayName = altName or mainName
  local annotation  = altName and (" (main: " .. mainName .. ")") or ""

  local deltaStr
  if delta >= 0 then
    deltaStr = CLR_GREEN .. "+" .. delta .. CLR_END
  else
    deltaStr = CLR_RED .. tostring(delta) .. CLR_END
  end

  return CLR_WHITE .. "  " .. displayName .. ": " .. CLR_END
    .. deltaStr
    .. CLR_WHITE .. annotation .. CLR_END
end

function GuildRoll_AdminLog:OnTooltipUpdate()
  -- Two-column layout: Time | Action
  local cat = T:AddCategory(
    "columns", 2,
    "text",          "Time",
    "child_textR",   0.6, "child_textG", 0.6, "child_textB", 0.6,
    "child_justify", "LEFT",
    "text2",         "Action",
    "child_text2R",  1,   "child_text2G", 1,  "child_text2B", 1,
    "child_justify2", "LEFT"
  )

  -- Build filtered, sorted entry list (newest first)
  local displayEntries = {}
  for i = 1, table.getn(GuildRoll_adminLogOrder) do
    local id    = GuildRoll_adminLogOrder[i]
    local entry = adminLogRuntime[id]
    if entry then
      local include = true

      if filterAuthor and entry.author ~= filterAuthor then
        include = false
      end

      if include and searchText and searchText ~= "" then
        local needle   = string.lower(searchText)
        local haystack = string.lower(
          (entry.author or "")      .. " " ..
          (entry.action or "")      .. " " ..
          (entry.player or "")      .. " " ..
          (entry.action_type or "")
        )
        if not string.find(haystack, needle, 1, true) then include = false end
      end

      if include then table.insert(displayEntries, entry) end
    end
  end

  table.sort(displayEntries, function(a, b)
    return (a.ts or 0) > (b.ts or 0)
  end)

  if table.getn(displayEntries) == 0 then
    cat:AddLine("text", "No entries", "text2", "")
  else
    for i = 1, table.getn(displayEntries) do
      local entry     = displayEntries[i]
      local timeStr   = date("%Y-%m-%d %H:%M", entry.ts)
      local actionStr, isExpandable = buildActionLine(entry)

      if isExpandable then
        local capturedId = entry.id

        -- Main raid line (clickable to toggle expansion)
        cat:AddLine(
          "text",  timeStr,
          "text2", actionStr,
          "func",  function()
            if expandedRaidEntries[capturedId] then
              expandedRaidEntries[capturedId] = nil
            else
              expandedRaidEntries[capturedId] = true
            end
            pcall(function() T:Refresh("GuildRoll_AdminLog") end)
          end
        )

        -- Expanded sub-entries (per-player details)
        if expandedRaidEntries[entry.id] and entry.raid_details then
          local rd     = entry.raid_details
          local subcat = cat:AddCategory(
            "columns",      1,
            "hideBlankLine", true,
            "noInherit",    true,
            "child_justify", "LEFT"
          )

          for j = 1, table.getn(rd.players or {}) do
            local mainName = rd.players[j]
            local counts   = rd.counts[mainName] or {old = 0, new = 0}
            local delta    = counts.new - counts.old
            local altName  = rd.alt_sources and rd.alt_sources[mainName]

            subcat:AddLine("text", buildPlayerSubLine(mainName, altName, delta))
          end
        end

      else
        cat:AddLine("text", timeStr, "text2", actionStr)
      end
    end
  end

  -- Status hint
  if filterAuthor or searchText then
    local statusParts = {}
    if filterAuthor then table.insert(statusParts, "Author: " .. filterAuthor) end
    if searchText   then table.insert(statusParts, "Search: " .. searchText)   end
    T:SetHint("Filtered - " .. table.concat(statusParts, ", "))
  else
    T:SetHint(string.format("%d total entries", table.getn(GuildRoll_adminLogOrder)))
  end
end

-- ============================================================
-- Static popups
-- ============================================================

local function GetVisibleStaticPopupEditBox(dialog)
  if dialog and dialog.GetName then
    local name = dialog:GetName()
    if name and _G[name .. "EditBox"] then return _G[name .. "EditBox"] end
  end
  local num = STATICPOPUP_NUMDIALOGS or 4
  for i = 1, num do
    local dlg = _G["StaticPopup" .. i]
    if dlg and dlg:IsShown() then
      local name = dlg:GetName()
      if name then
        local eb = _G[name .. "EditBox"]
        if eb then return eb end
      end
    end
  end
  return nil
end

StaticPopupDialogs["GUILDROLL_ADMINLOG_SEARCH"] = {
  text        = "Search Admin Log:",
  button1     = TEXT(ACCEPT),
  button2     = TEXT(CANCEL),
  hasEditBox  = 1,
  maxLetters  = 50,
  OnAccept = function(self)
    local eb   = GetVisibleStaticPopupEditBox(self)
    local text = eb and eb.GetText and eb:GetText() or nil
    if text and text ~= "" then
      searchText = text
      pcall(function()
        if T and T:IsRegistered("GuildRoll_AdminLog") then
          T:Refresh("GuildRoll_AdminLog")
        end
      end)
    end
  end,
  OnShow = function(self)
    local eb = GetVisibleStaticPopupEditBox(self)
    if eb then
      if eb.SetText  then eb:SetText(searchText or "") end
      if eb.SetFocus then eb:SetFocus() end
    end
  end,
  OnHide = function(self)
    if ChatFrameEditBox and ChatFrameEditBox.IsVisible
        and ChatFrameEditBox:IsVisible() then
      ChatFrameEditBox:SetFocus()
    end
    local eb = GetVisibleStaticPopupEditBox(self)
    if eb and eb.SetText then eb:SetText("") end
  end,
  EditBoxOnEnterPressed = function(editBox)
    local text = editBox and editBox.GetText and editBox:GetText() or nil
    if text and text ~= "" then
      searchText = text
      pcall(function()
        if T and T:IsRegistered("GuildRoll_AdminLog") then
          T:Refresh("GuildRoll_AdminLog")
        end
      end)
    end
    local parent = editBox and editBox.GetParent and editBox:GetParent()
    if parent and parent.Hide then parent:Hide() end
  end,
  EditBoxOnEscapePressed = function(editBox)
    local parent = editBox and editBox.GetParent and editBox:GetParent()
    if parent and parent.Hide then parent:Hide() end
  end,
  timeout      = 0,
  exclusive    = 1,
  whileDead    = 1,
  hideOnEscape = 1,
}

StaticPopupDialogs["GUILDROLL_ADMINLOG_CLEAR_CONFIRM"] = {
  text    = "This will permanently delete all Admin Log entries and broadcast the clear to all admins. Only the GuildMaster can do this. Continue?",
  button1 = TEXT(ACCEPT),
  button2 = TEXT(CANCEL),
  OnAccept = function()
    local isGuildMaster = false
    if IsGuildLeader then
      local ok, result = pcall(function() return IsGuildLeader() end)
      if ok and result then isGuildMaster = true end
    end
    if isGuildMaster then
      local broadcastOk = pcall(function()
        sendAdminSyncMessage(string.format("ADMINLOG;CLEAR;%d", PROTOCOL_VERSION))
      end)
      GuildRoll_adminLogSaved = {}
      GuildRoll_adminLogOrder = {}
      adminLogRuntime         = {}
      expandedRaidEntries     = {}
      pcall(function() T:Refresh("GuildRoll_AdminLog") end)
      if broadcastOk then
        GuildRoll:defaultPrint("Admin log cleared (global).")
      else
        GuildRoll:defaultPrint("Admin log cleared (local only - broadcast failed).")
      end
    else
      GuildRoll:defaultPrint("Only the GuildMaster can clear the admin log.")
    end
  end,
  timeout      = 0,
  whileDead    = 1,
  hideOnEscape = 1,
}
