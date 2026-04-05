--[[
AdminLog Module for GuildRoll
Provides persistent, LOCAL-ONLY admin log.

Entry structure (new format):
  id      - unique string identifier (timestamp_random)
  ts      - Unix timestamp (number)
  action  - short action type: "RAID", "GIVE", "DECAY", "RESET", "MANUAL", etc.
  actor   - name of the officer/admin who performed the action
  target  - primary target (player name, "Raid", "All", etc.)
  details - human-readable description of what happened
  raid_details (optional) - for RAID entries:
    { ep, players, counts, alt_sources }

Backward compatible: old entries with {author, action} fields are displayed gracefully.
--]]

-- Guard: Check if required libraries are available before proceeding
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
local adminLogRuntime = {}      -- runtime cache indexed by entry id
local filterAuthor = nil        -- for UI filtering by actor/author
local filterTarget = nil        -- for UI filtering by target player
local searchText = nil          -- for UI search
local expandedRaidEntries = {}  -- track which entries are expanded (key = entry.id)
local ALOG_SYNC_PREFIX = "GR_ALOG"  -- prefix for AdminLog officer sync messages
local pendingChunks = {}        -- for reassembly of multi-chunk sync messages

-- Helper: Debug print (protected by GuildRoll.DEBUG)
local function debugPrint(msg)
  if GuildRoll and GuildRoll.DEBUG and msg then
    pcall(function()
      if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("[AdminLog Debug] " .. tostring(msg))
      elseif GuildRoll and GuildRoll.defaultPrint then
        GuildRoll:defaultPrint("[AdminLog Debug] " .. tostring(msg))
      end
    end)
  end
end

-- Helper: Generate unique ID for log entry
local function generateEntryId()
  local timestamp = time()
  local random = math.random(1000, 9999)
  return string.format("%d_%d", timestamp, random)
end

-- Per-type maximum entry counts
local maxEntriesByType = {
  GIVE    = 1000,
  PENALTY = 1000,
  RAID    = 160,
  DECAY   = 60,
  RESET   = 5,
  DEFAULT = 200,
}

-- Apply an admin log entry locally (deduplicates by id)
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

  -- Per-type trimming: enforce separate limits for each tracked action type
  local trackedTypes = {"GIVE", "PENALTY", "RAID", "DECAY", "RESET"}
  for _, actionType in ipairs(trackedTypes) do
    local limit = maxEntriesByType[actionType]
    local typeIds = {}
    for i = 1, table.getn(GuildRoll_adminLogOrder) do
      local id = GuildRoll_adminLogOrder[i]
      local e = adminLogRuntime[id]
      if e and e.action == actionType then
        table.insert(typeIds, id)
      end
    end
    if table.getn(typeIds) > limit then
      local toRemove = table.getn(typeIds) - limit
      local removeSet = {}
      for i = 1, toRemove do
        removeSet[typeIds[i]] = true
      end
      local newOrder = {}
      for i = 1, table.getn(GuildRoll_adminLogOrder) do
        local id = GuildRoll_adminLogOrder[i]
        if removeSet[id] then
          GuildRoll_adminLogSaved[id] = nil
          adminLogRuntime[id] = nil
        else
          table.insert(newOrder, id)
        end
      end
      GuildRoll_adminLogOrder = newOrder
    end
  end

  -- Default type trimming: all action types not in the tracked list share DEFAULT limit
  local defaultLimit = maxEntriesByType.DEFAULT
  local defaultIds = {}
  for i = 1, table.getn(GuildRoll_adminLogOrder) do
    local id = GuildRoll_adminLogOrder[i]
    local e = adminLogRuntime[id]
    if e then
      local t = e.action or ""
      if t ~= "GIVE" and t ~= "PENALTY" and t ~= "RAID" and t ~= "DECAY" and t ~= "RESET" then
        table.insert(defaultIds, id)
      end
    end
  end
  if table.getn(defaultIds) > defaultLimit then
    local toRemove = table.getn(defaultIds) - defaultLimit
    local removeSet = {}
    for i = 1, toRemove do
      removeSet[defaultIds[i]] = true
    end
    local newOrder = {}
    for i = 1, table.getn(GuildRoll_adminLogOrder) do
      local id = GuildRoll_adminLogOrder[i]
      if removeSet[id] then
        GuildRoll_adminLogSaved[id] = nil
        adminLogRuntime[id] = nil
      else
        table.insert(newOrder, id)
      end
    end
    GuildRoll_adminLogOrder = newOrder
  end
end

-- Load saved entries into runtime cache on startup
local function loadSavedEntries()
  adminLogRuntime = {}
  for i = 1, table.getn(GuildRoll_adminLogOrder) do
    local id = GuildRoll_adminLogOrder[i]
    local entry = GuildRoll_adminLogSaved[id]
    if entry then
      adminLogRuntime[id] = entry
    end
  end
end

-- Helper: check whether entry involves the named player
local function entryInvolvesPlayer(entry, name)
  if not entry or not name or name == "" then return false end

  -- GIVE/PENALTY: direct target match
  if entry.target == name then return true end

  -- RAID: search in raid_details.players
  if entry.raid_details and entry.raid_details.players then
    for i = 1, table.getn(entry.raid_details.players) do
      if entry.raid_details.players[i] == name then return true end
    end
  end

  -- DECAY: search in affected table (keys are player names)
  if entry.affected then
    if entry.affected[name] then return true end
  end

  -- RESET: never match by player (no per-player data stored)
  return false
end

-- Case-insensitive partial match version (used by Search, Filter by Author, Filter by Target)
local function entryInvolvesPlayerPartial(entry, searchLower)
  if not entry or not searchLower or searchLower == "" then return false end

  -- GIVE/PENALTY: direct target match
  if entry.target and string.find(string.lower(entry.target), searchLower, 1, true) then
    return true
  end

  -- RAID: search in raid_details.players
  if entry.raid_details and entry.raid_details.players then
    for i = 1, table.getn(entry.raid_details.players) do
      local p = entry.raid_details.players[i]
      if p and string.find(string.lower(p), searchLower, 1, true) then
        return true
      end
    end
  end

  -- DECAY: search in affected table (keys are player names)
  if entry.affected then
    for name, _ in pairs(entry.affected) do
      if name and string.find(string.lower(name), searchLower, 1, true) then
        return true
      end
    end
  end

  return false
end

-- ── Serialization helpers for officer sync ──────────────────────────────────

local FIELD_SEP = "\t"  -- tab between serialized fields
local CHUNK_SIZE = 235  -- max bytes per sync message chunk (255 limit minus ~20 bytes protocol overhead)
local EM_DASH = "\226\128\148"  -- UTF-8 em dash used in player detail display lines

-- Split str on tab characters; handles empty fields correctly
local function splitTab(str)
  local t = {}
  local pos = 1
  local len = string.len(str)
  while pos <= len do
    local s = string.find(str, "\t", pos, true)
    if s then
      table.insert(t, string.sub(str, pos, s - 1))
      pos = s + 1
    else
      table.insert(t, string.sub(str, pos))
      break
    end
  end
  return t
end

-- Serialize an entry to a tab-delimited string for sync
local function serializeEntry(entry)
  local parts = {
    tostring(entry.id      or ""),
    tostring(entry.ts      or 0),
    tostring(entry.action  or "LOG"),
    tostring(entry.actor   or ""),
    tostring(entry.target  or ""),
    tostring(entry.details or ""),
  }

  if entry.raid_details then
    table.insert(parts, "RAID_DETAILS")
    table.insert(parts, tostring(entry.raid_details.ep or 0))
    if entry.raid_details.players then
      for i = 1, table.getn(entry.raid_details.players) do
        local player = entry.raid_details.players[i]
        local counts = (entry.raid_details.counts and entry.raid_details.counts[player]) or {old=0,new=0}
        local altsrc = (entry.raid_details.alt_sources and entry.raid_details.alt_sources[player]) or ""
        table.insert(parts, player)
        table.insert(parts, tostring(counts.old or 0))
        table.insert(parts, tostring(counts.new or 0))
        table.insert(parts, (altsrc ~= "") and altsrc or "_")
      end
    end
  end

  if entry.affected then
    table.insert(parts, "AFFECTED")
    for name, data in pairs(entry.affected) do
      table.insert(parts, name)
      table.insert(parts, tostring(data.old or 0))
      table.insert(parts, tostring(data.new or 0))
    end
  end

  return table.concat(parts, FIELD_SEP)
end

-- Deserialize a tab-delimited string back into an entry table
local function deserializeEntry(str)
  if not str or str == "" then return nil end
  local fields = splitTab(str)
  if table.getn(fields) < 6 then return nil end

  local entry = {
    id      = fields[1],
    ts      = tonumber(fields[2]) or 0,
    action  = fields[3],
    actor   = fields[4],
    target  = fields[5],
    details = fields[6],
  }
  if not entry.id or entry.id == "" then return nil end

  local i = 7
  local n = table.getn(fields)
  while i <= n do
    local marker = fields[i]
    if marker == "RAID_DETAILS" then
      i = i + 1
      local ep = tonumber(fields[i] or "") or 0
      i = i + 1
      entry.raid_details = {ep=ep, players={}, counts={}, alt_sources={}}
      while i + 3 <= n do
        local player = fields[i]
        if player == "AFFECTED" or player == "RAID_DETAILS" then break end
        local old_  = tonumber(fields[i+1] or "") or 0
        local new_  = tonumber(fields[i+2] or "") or 0
        local altsrc = fields[i+3] or "_"
        if altsrc == "_" then altsrc = "" end
        table.insert(entry.raid_details.players, player)
        entry.raid_details.counts[player] = {old=old_, new=new_}
        if altsrc ~= "" then
          entry.raid_details.alt_sources[player] = altsrc
        end
        i = i + 4
      end
    elseif marker == "AFFECTED" then
      i = i + 1
      entry.affected = {}
      while i + 2 <= n do
        local player = fields[i]
        if player == "RAID_DETAILS" or player == "AFFECTED" then break end
        local old_ = tonumber(fields[i+1] or "") or 0
        local new_ = tonumber(fields[i+2] or "") or 0
        entry.affected[player] = {old=old_, new=new_}
        i = i + 3
      end
    else
      i = i + 1
    end
  end

  return entry
end

-- Parse the protocol header from a sync message (Lua-5.0-compatible; no string.match)
-- Returns: msgType ("S" or "C"), id, number, data  — or nil on parse failure
local function parseProtocolMsg(message)
  local pipe1 = string.find(message, "|", 1, true)
  if not pipe1 then return nil end
  local msgType = string.sub(message, 1, pipe1 - 1)
  if msgType ~= "S" and msgType ~= "C" then return nil end

  local pipe2 = string.find(message, "|", pipe1 + 1, true)
  if not pipe2 then return nil end
  local id = string.sub(message, pipe1 + 1, pipe2 - 1)

  local pipe3 = string.find(message, "|", pipe2 + 1, true)
  if not pipe3 then return nil end
  local num = tonumber(string.sub(message, pipe2 + 1, pipe3 - 1))
  if not num then return nil end

  local data = string.sub(message, pipe3 + 1)
  return msgType, id, num, data
end

-- Send an entry to other officers via chunked addon messages
local function sendAdminLogSync(entry)
  if not entry or not entry.id then return end
  if not GuildRoll or not GuildRoll.IsAdmin or not GuildRoll:IsAdmin() then return end

  local serialized = serializeEntry(entry)
  if not serialized then return end

  local len = string.len(serialized)
  if len <= CHUNK_SIZE then
    local msg = "S|" .. entry.id .. "|1|" .. serialized
    pcall(function() SendAddonMessage(ALOG_SYNC_PREFIX, msg, "OFFICER") end)
  else
    local chunks = {}
    local pos = 1
    while pos <= len do
      table.insert(chunks, string.sub(serialized, pos, pos + CHUNK_SIZE - 1))
      pos = pos + CHUNK_SIZE
    end
    local total = table.getn(chunks)
    for ci = 1, total do
      local msg
      if ci == 1 then
        msg = "S|" .. entry.id .. "|" .. total .. "|" .. chunks[ci]
      else
        msg = "C|" .. entry.id .. "|" .. ci .. "|" .. chunks[ci]
      end
      pcall(function() SendAddonMessage(ALOG_SYNC_PREFIX, msg, "OFFICER") end)
    end
  end
end

-- Public API: Add a structured admin log entry (local only, no network)
-- entry must be a table with fields: ts, action, actor, target, details
-- raid_details (optional) for RAID entries; affected (optional) for DECAY entries.
function GuildRoll:AdminLogAdd(entry)
  if not self:IsAdmin() then return end
  if not entry or type(entry) ~= "table" then return end

  local e = {
    id      = generateEntryId(),
    ts      = entry.ts or time(),
    action  = entry.action or "LOG",
    actor   = entry.actor  or (UnitName("player") or "Unknown"),
    target  = entry.target  or "",
    details = entry.details or "",
  }

  -- Preserve optional raid_details if present
  if entry.raid_details then
    e.raid_details = entry.raid_details
  end

  -- Preserve optional affected if present (for DECAY entries)
  if entry.affected then
    e.affected = entry.affected
  end

  applyAdminLogEntry(e)

  -- Broadcast to other online officers for sync
  pcall(function() sendAdminLogSync(e) end)

  if T and T:IsRegistered("GuildRoll_AdminLog") then
    pcall(function() T:Refresh("GuildRoll_AdminLog") end)
  end
end

-- Public API: Add a raid admin log entry with player details (local only)
function GuildRoll:AdminLogAddRaid(ep, raid_data)
  if not self:IsAdmin() then return end
  if not raid_data or not raid_data.players or table.getn(raid_data.players) == 0 then return end

  local playerCount = table.getn(raid_data.players)
  local adminName   = UnitName("player") or "Unknown"
  local detailsText
  if ep < 0 then
    detailsText = string.format("%d EP Penalty (%d players)", ep, playerCount)
  else
    detailsText = string.format("+%d EP (%d players)", ep, playerCount)
  end

  local entry = {
    id      = generateEntryId(),
    ts      = time(),
    action  = "RAID",
    actor   = adminName,
    target  = "Raid",
    details = detailsText,
    raid_details = {
      ep          = ep,
      players     = raid_data.players,
      counts      = raid_data.counts,
      alt_sources = raid_data.alt_sources
    }
  }

  applyAdminLogEntry(entry)

  -- Broadcast to other online officers for sync
  pcall(function() sendAdminLogSync(entry) end)

  if T and T:IsRegistered("GuildRoll_AdminLog") then
    pcall(function() T:Refresh("GuildRoll_AdminLog") end)
  end
end

-- Module initialization
function GuildRoll_AdminLog:OnEnable()
  -- Load saved entries into runtime cache
  loadSavedEntries()

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
        -- Search
        GuildRoll:SafeDewdropAddLine(
          "text", "Search",
          "tooltipText", "Search admin log entries",
          "func", function()
            StaticPopup_Show("GUILDROLL_ADMINLOG_SEARCH")
          end
        )

        -- Clear Search (only when active)
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

        -- Filter by Author
        GuildRoll:SafeDewdropAddLine(
          "text", "Filter by Author",
          "tooltipText", "Filter log by officer name",
          "func", function()
            StaticPopup_Show("GUILDROLL_ADMINLOG_FILTER_AUTHOR")
          end
        )

        -- Remove Author Filter (only when active)
        if filterAuthor then
          GuildRoll:SafeDewdropAddLine(
            "text", "Remove Author Filter",
            "tooltipText", string.format("Remove author filter (%s)", filterAuthor),
            "func", function()
              filterAuthor = nil
              pcall(function() T:Refresh("GuildRoll_AdminLog") end)
            end
          )
        end

        -- Filter by Target
        GuildRoll:SafeDewdropAddLine(
          "text", "Filter by Target",
          "tooltipText", "Filter log by target player name",
          "func", function()
            StaticPopup_Show("GUILDROLL_ADMINLOG_FILTER_TARGET")
          end
        )

        -- Remove Target Filter (only when active)
        if filterTarget then
          GuildRoll:SafeDewdropAddLine(
            "text", "Remove Target Filter",
            "tooltipText", string.format("Remove target filter (%s)", filterTarget),
            "func", function()
              filterTarget = nil
              pcall(function() T:Refresh("GuildRoll_AdminLog") end)
            end
          )
        end

        -- Spacer (non-clickable)
        GuildRoll:SafeDewdropAddLine(
          "text", " ",
          "isTitle", true
        )

        -- Reset Log
        GuildRoll:SafeDewdropAddLine(
          "text", "Reset Log",
          "tooltipText", "Clear all local admin log data",
          "func", function()
            StaticPopup_Show("GUILDROLL_ADMINLOG_CLEAR_CONFIRM")
          end
        )

        -- Spacer
        GuildRoll:SafeDewdropAddLine(
          "text", " ",
          "isTitle", true
        )

        -- Close window
        GuildRoll:SafeDewdropAddLine(
          "text", L["Close window"],
          "tooltipText", L["Close this window"],
          "func", function()
            pcall(function() D:Close() end)
            local frame = GuildRoll:FindDetachedFrame("GuildRoll_AdminLog")
            if frame and frame.Hide then frame:Hide() end
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

  pcall(function() GuildRoll_AdminLog:setHideScript() end)
end

function GuildRoll_AdminLog:OnDisable()
  pcall(function() T:Close("GuildRoll_AdminLog") end)
end

-- Ensure detached frame owner and ESC handling
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
            if T and T.IsAttached and not T:IsAttached("GuildRoll_AdminLog") then
              T:Attach("GuildRoll_AdminLog")
            end
            if f and f.SetScript then
              f:SetScript("OnHide", nil)
            end
          end)
        end)
    end
  end
end

-- 4-column display: Date | Action | Officer | Details
function GuildRoll_AdminLog:OnTooltipUpdate()
  local cat = T:AddCategory(
    "columns", 4,
    "text",  C:Orange("Date"),
    "child_textR", 1, "child_textG", 1, "child_textB", 1,
    "child_justify", "LEFT",
    "text2", C:Orange("Action"),
    "child_text2R", 0.5, "child_text2G", 1, "child_text2B", 0.5,
    "child_justify2", "LEFT",
    "text3", C:Orange("Officer"),
    "child_text3R", 0.8, "child_text3G", 0.8, "child_text3B", 1,
    "child_justify3", "LEFT",
    "text4", C:Orange("Details"),
    "child_text4R", 1, "child_text4G", 1, "child_text4B", 0.5,
    "child_justify4", "RIGHT"
  )

  -- Helper: colorize numeric deltas in text
  local function colorizeText(txt)
    if not txt then return "" end
    local result = txt
    result = string.gsub(result, "(%+%d+)", function(m) return C:Green(m) end)
    result = string.gsub(result, "(-%d+)",  function(m) return C:Red(m) end)
    return result
  end

  -- Pre-compute lowercase filter values once outside the loop
  local filterAuthorLower = filterAuthor and string.lower(filterAuthor) or nil
  local filterTargetLower = filterTarget and string.lower(filterTarget) or nil
  local searchLower = (searchText and searchText ~= "") and string.lower(searchText) or nil

  -- Build filtered entry list
  local displayEntries = {}
  for i = 1, table.getn(GuildRoll_adminLogOrder) do
    local id = GuildRoll_adminLogOrder[i]
    local entry = adminLogRuntime[id]

    if entry then
      local include = true

      -- Apply author/actor filter
      if filterAuthorLower then
        local entryActor = string.lower(entry.actor or entry.author or "")
        if not string.find(entryActor, filterAuthorLower, 1, true) then
          include = false
        end
      end

      -- Apply target filter using entryInvolvesPlayerPartial helper
      if include and filterTargetLower then
        if not entryInvolvesPlayerPartial(entry, filterTargetLower) then
          include = false
        end
      end

      -- Apply search filter: check text fields plus all player names via entryInvolvesPlayerPartial
      if include and searchLower then
        local actionLower  = string.lower(entry.action  or "")
        local detailsLower = string.lower(entry.details or "")
        local targetLower  = string.lower(entry.target  or "")
        local actorLower   = string.lower(entry.actor or entry.author or "")
        local found = string.find(actionLower, searchLower, 1, true)
          or string.find(detailsLower, searchLower, 1, true)
          or string.find(targetLower, searchLower, 1, true)
          or string.find(actorLower, searchLower, 1, true)
          or entryInvolvesPlayerPartial(entry, searchLower)
        if not found then
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
      "text",  "No entries",
      "text2", "",
      "text3", "",
      "text4", ""
    )
  else
    for i = 1, table.getn(displayEntries) do
      local entry = displayEntries[i]
      local timeStr = date("%Y-%m-%d %H:%M", entry.ts)

      -- Resolve fields with backward-compat for old-format entries
      local actionStr, actorStr, detailsStr
      if entry.details ~= nil then
        -- New structured format
        actionStr  = entry.action or "LOG"
        actorStr   = entry.actor  or "Unknown"
        -- Combine target + details for the Details column
        if entry.target and entry.target ~= "" then
          detailsStr = entry.target .. " - " .. (entry.details or "")
        else
          detailsStr = entry.details or ""
        end
      else
        -- Old format: entry.author + entry.action (full text)
        actorStr = entry.author or "Unknown"
        -- Try to extract tag like [DECAY], [GIVE], [RESET], [RAID]
        local _, _, captured = string.find(entry.action or "", "^%[([%w]+)%]")
        actionStr  = captured or "LOG"
        detailsStr = entry.action or ""
      end

      -- Expandable entries: RAID (raid_details) and DECAY with affected data
      if entry.raid_details then
        local isExpanded = expandedRaidEntries[entry.id]
        local expandIcon = isExpanded and "[-] " or "[+] "

        cat:AddLine(
          "text",  timeStr,
          "text2", actionStr,
          "text3", actorStr,
          "text4", expandIcon .. colorizeText(detailsStr),
          "func", function()
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
          local subcat = cat:AddCategory(
            "columns", 1,
            "hideBlankLine", true,
            "noInherit", true,
            "child_justify", "RIGHT"
          )

          for j = 1, table.getn(entry.raid_details.players) do
            local player = entry.raid_details.players[j]
            local counts = entry.raid_details.counts[player] or {old=0, new=0}
            local delta = counts.new - counts.old
            local alt_source = entry.raid_details.alt_sources and entry.raid_details.alt_sources[player]

            local deltaColored
            if delta >= 0 then
              deltaColored = C:Green(string.format("(+%d)", delta))
            else
              deltaColored = C:Red(string.format("(%d)", delta))
            end

            local displayText
            if alt_source and alt_source ~= "" then
              displayText = string.format("  %s (%s's main) " .. EM_DASH .. " Prev: %d, New: %d %s",
                player, alt_source, counts.old, counts.new, deltaColored)
            else
              displayText = string.format("  %s " .. EM_DASH .. " Prev: %d, New: %d %s",
                player, counts.old, counts.new, deltaColored)
            end

            subcat:AddLine("text", displayText)
          end
        end
      elseif entry.affected then
        -- DECAY entry with per-player data (expandable)
        local isExpanded = expandedRaidEntries[entry.id]
        local expandIcon = isExpanded and "[-] " or "[+] "

        cat:AddLine(
          "text",  timeStr,
          "text2", actionStr,
          "text3", actorStr,
          "text4", expandIcon .. colorizeText(detailsStr),
          "func", function()
            if expandedRaidEntries[entry.id] then
              expandedRaidEntries[entry.id] = nil
            else
              expandedRaidEntries[entry.id] = true
            end
            pcall(function() T:Refresh("GuildRoll_AdminLog") end)
          end
        )

        -- If expanded, show per-player decay data sorted alphabetically
        if isExpanded then
          local subcat = cat:AddCategory(
            "columns", 1,
            "hideBlankLine", true,
            "noInherit", true,
            "child_justify", "RIGHT"
          )

          local playerNames = {}
          for name, _ in pairs(entry.affected) do
            table.insert(playerNames, name)
          end
          table.sort(playerNames)

          for _, player in ipairs(playerNames) do
            local data = entry.affected[player]
            local delta = (data.new or 0) - (data.old or 0)
            local deltaColored
            if delta >= 0 then
              deltaColored = C:Green(string.format("(+%d)", delta))
            else
              deltaColored = C:Red(string.format("(%d)", delta))
            end
            local displayText = string.format("  %s " .. EM_DASH .. " Prev: %d, New: %d %s",
              player, data.old or 0, data.new or 0, deltaColored)
            subcat:AddLine("text", displayText)
          end
        end
      else
        -- Regular (non-expandable) entry
        cat:AddLine(
          "text",  timeStr,
          "text2", actionStr,
          "text3", actorStr,
          "text4", colorizeText(detailsStr)
        )
      end
    end
  end

  -- Show filter/search status hint
  if filterAuthor or filterTarget or searchText then
    local statusParts = {}
    if filterAuthor then
      table.insert(statusParts, string.format("Actor: %s", filterAuthor))
    end
    if filterTarget then
      table.insert(statusParts, string.format("Target: %s", filterTarget))
    end
    if searchText then
      table.insert(statusParts, string.format("Search: %s", searchText))
    end
    T:SetHint(string.format("Filter active - %s", table.concat(statusParts, ", ")))
  else
    T:SetHint(string.format("%d total entries", table.getn(GuildRoll_adminLogOrder)))
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

-- Public API: open AdminLog with target filter pre-set to the given player name
function GuildRoll_AdminLog:OpenForPlayer(name)
  if not name or name == "" then return end
  filterTarget = name
  filterAuthor = nil
  searchText = nil

  if not T:IsRegistered("GuildRoll_AdminLog") then return end

  if T:IsAttached("GuildRoll_AdminLog") then
    pcall(function() T:Detach("GuildRoll_AdminLog") end)
    if T.IsLocked and T:IsLocked("GuildRoll_AdminLog") then
      pcall(function() T:ToggleLocked("GuildRoll_AdminLog") end)
    end
    self:setHideScript()
  end
  pcall(function() T:Refresh("GuildRoll_AdminLog") end)
end

-- Receive and reassemble sync messages sent by other officers via GR_ALOG prefix
function GuildRoll_AdminLog:handleSyncMessage(message, sender)
  if not message then return end

  local msgType, id, num, data = parseProtocolMsg(message)
  if not msgType or not id or not num or data == nil then return end

  if msgType == "S" then
    local total = num
    if total == 1 then
      -- Single-chunk entry: process immediately
      local entry = deserializeEntry(data)
      if entry then
        applyAdminLogEntry(entry)
        if T and T:IsRegistered("GuildRoll_AdminLog") then
          pcall(function() T:Refresh("GuildRoll_AdminLog") end)
        end
      end
    else
      -- First chunk of a multi-chunk entry
      pendingChunks[id] = {total=total, chunks={}, received=0}
      pendingChunks[id].chunks[1] = data
      pendingChunks[id].received = 1
    end
  elseif msgType == "C" then
    -- Subsequent chunk
    if not pendingChunks[id] then return end
    local chunkIdx = num
    pendingChunks[id].chunks[chunkIdx] = data
    pendingChunks[id].received = (pendingChunks[id].received or 0) + 1

    if pendingChunks[id].received == pendingChunks[id].total then
      -- All chunks received: assemble and process
      local assembled = ""
      for ci = 1, pendingChunks[id].total do
        assembled = assembled .. (pendingChunks[id].chunks[ci] or "")
      end
      pendingChunks[id] = nil

      local entry = deserializeEntry(assembled)
      if entry then
        applyAdminLogEntry(entry)
        if T and T:IsRegistered("GuildRoll_AdminLog") then
          pcall(function() T:Refresh("GuildRoll_AdminLog") end)
        end
      end
    end
  end
end

-- Helper function to safely get EditBox from StaticPopup dialog
local function GetVisibleStaticPopupEditBox(dialog)
  if dialog and dialog.GetName then
    local name = dialog:GetName()
    if name and _G[name .. "EditBox"] then
      return _G[name .. "EditBox"]
    end
  end
  local num = STATICPOPUP_NUMDIALOGS or 4
  for i = 1, num do
    local dlg = _G["StaticPopup" .. i]
    if dlg and dlg:IsShown() then
      local name = (dlg and dlg.GetName) and dlg:GetName()
      if name then
        local eb = _G[name .. "EditBox"]
        if eb then return eb end
      end
    end
  end
  return nil
end

-- Static popup for search
StaticPopupDialogs["GUILDROLL_ADMINLOG_SEARCH"] = {
  text = "Search Admin Log:",
  button1 = TEXT(ACCEPT),
  button2 = TEXT(CANCEL),
  hasEditBox = 1,
  maxLetters = 50,
  OnAccept = function(self)
    local editBox = GetVisibleStaticPopupEditBox(self)
    local text = editBox and editBox.GetText and editBox:GetText() or nil
    if text and text ~= "" then
      searchText = text
      pcall(function() if T and T:IsRegistered("GuildRoll_AdminLog") then T:Refresh("GuildRoll_AdminLog") end end)
    end
  end,
  OnShow = function(self)
    local editBox = GetVisibleStaticPopupEditBox(self)
    if editBox and editBox.SetText then
      editBox:SetText(searchText or "")
      if editBox.SetFocus then editBox:SetFocus() end
    end
  end,
  OnHide = function(self)
    if ChatFrameEditBox and ChatFrameEditBox.IsVisible and ChatFrameEditBox:IsVisible() then
      ChatFrameEditBox:SetFocus()
    end
    local editBox = GetVisibleStaticPopupEditBox(self)
    if editBox and editBox.SetText then editBox:SetText("") end
  end,
  EditBoxOnEnterPressed = function(editBox)
    local text = editBox and editBox.GetText and editBox:GetText() or nil
    if text and text ~= "" then
      searchText = text
      pcall(function() if T and T:IsRegistered("GuildRoll_AdminLog") then T:Refresh("GuildRoll_AdminLog") end end)
    end
    local parent = editBox and editBox.GetParent and editBox:GetParent()
    if parent and parent.Hide then parent:Hide() end
  end,
  EditBoxOnEscapePressed = function(editBox)
    local parent = editBox and editBox.GetParent and editBox:GetParent()
    if parent and parent.Hide then parent:Hide() end
  end,
  timeout = 0,
  exclusive = 1,
  whileDead = 1,
  hideOnEscape = 1
}

-- Static popup for filter by author
StaticPopupDialogs["GUILDROLL_ADMINLOG_FILTER_AUTHOR"] = {
  text = "Filter by Author:",
  button1 = TEXT(ACCEPT),
  button2 = TEXT(CANCEL),
  hasEditBox = 1,
  maxLetters = 50,
  OnAccept = function(self)
    local editBox = GetVisibleStaticPopupEditBox(self)
    local text = editBox and editBox.GetText and editBox:GetText() or nil
    if text and text ~= "" then
      filterAuthor = text
    else
      filterAuthor = nil
    end
    pcall(function() if T and T:IsRegistered("GuildRoll_AdminLog") then T:Refresh("GuildRoll_AdminLog") end end)
  end,
  OnShow = function(self)
    local editBox = GetVisibleStaticPopupEditBox(self)
    if editBox and editBox.SetText then
      editBox:SetText(filterAuthor or "")
      if editBox.SetFocus then editBox:SetFocus() end
    end
  end,
  OnHide = function(self)
    if ChatFrameEditBox and ChatFrameEditBox.IsVisible and ChatFrameEditBox:IsVisible() then
      ChatFrameEditBox:SetFocus()
    end
    local editBox = GetVisibleStaticPopupEditBox(self)
    if editBox and editBox.SetText then editBox:SetText("") end
  end,
  EditBoxOnEnterPressed = function(editBox)
    local text = editBox and editBox.GetText and editBox:GetText() or nil
    if text and text ~= "" then
      filterAuthor = text
    else
      filterAuthor = nil
    end
    pcall(function() if T and T:IsRegistered("GuildRoll_AdminLog") then T:Refresh("GuildRoll_AdminLog") end end)
    local parent = editBox and editBox.GetParent and editBox:GetParent()
    if parent and parent.Hide then parent:Hide() end
  end,
  EditBoxOnEscapePressed = function(editBox)
    local parent = editBox and editBox.GetParent and editBox:GetParent()
    if parent and parent.Hide then parent:Hide() end
  end,
  timeout = 0,
  exclusive = 1,
  whileDead = 1,
  hideOnEscape = 1
}

-- Static popup for filter by target
StaticPopupDialogs["GUILDROLL_ADMINLOG_FILTER_TARGET"] = {
  text = "Filter by Target Player:",
  button1 = TEXT(ACCEPT),
  button2 = TEXT(CANCEL),
  hasEditBox = 1,
  maxLetters = 50,
  OnAccept = function(self)
    local editBox = GetVisibleStaticPopupEditBox(self)
    local text = editBox and editBox.GetText and editBox:GetText() or nil
    if text and text ~= "" then
      filterTarget = text
    else
      filterTarget = nil
    end
    pcall(function() if T and T:IsRegistered("GuildRoll_AdminLog") then T:Refresh("GuildRoll_AdminLog") end end)
  end,
  OnShow = function(self)
    local editBox = GetVisibleStaticPopupEditBox(self)
    if editBox and editBox.SetText then
      editBox:SetText(filterTarget or "")
      if editBox.SetFocus then editBox:SetFocus() end
    end
  end,
  OnHide = function(self)
    if ChatFrameEditBox and ChatFrameEditBox.IsVisible and ChatFrameEditBox:IsVisible() then
      ChatFrameEditBox:SetFocus()
    end
    local editBox = GetVisibleStaticPopupEditBox(self)
    if editBox and editBox.SetText then editBox:SetText("") end
  end,
  EditBoxOnEnterPressed = function(editBox)
    local text = editBox and editBox.GetText and editBox:GetText() or nil
    if text and text ~= "" then
      filterTarget = text
    else
      filterTarget = nil
    end
    pcall(function() if T and T:IsRegistered("GuildRoll_AdminLog") then T:Refresh("GuildRoll_AdminLog") end end)
    local parent = editBox and editBox.GetParent and editBox:GetParent()
    if parent and parent.Hide then parent:Hide() end
  end,
  EditBoxOnEscapePressed = function(editBox)
    local parent = editBox and editBox.GetParent and editBox:GetParent()
    if parent and parent.Hide then parent:Hide() end
  end,
  timeout = 0,
  exclusive = 1,
  whileDead = 1,
  hideOnEscape = 1
}

-- Static popup for clear confirmation (local only)
StaticPopupDialogs["GUILDROLL_ADMINLOG_CLEAR_CONFIRM"] = {
  text = "Permanently delete all local Admin Log entries? This cannot be undone.",
  button1 = TEXT(ACCEPT),
  button2 = TEXT(CANCEL),
  OnAccept = function()
    GuildRoll_adminLogSaved = {}
    GuildRoll_adminLogOrder = {}
    adminLogRuntime = {}
    expandedRaidEntries = {}
    pcall(function() T:Refresh("GuildRoll_AdminLog") end)
    GuildRoll:defaultPrint("Admin log cleared (local).")
  end,
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 1
}
