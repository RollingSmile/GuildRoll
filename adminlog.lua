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
local filterAuthor = nil        -- for UI filtering
local searchText = nil          -- for UI search
local expandedRaidEntries = {}  -- track which raid entries are expanded (key = entry.id)

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

  -- Trim order array to last 400 entries
  local maxEntries = 400
  if table.getn(GuildRoll_adminLogOrder) > maxEntries then
    local toRemove = table.getn(GuildRoll_adminLogOrder) - maxEntries
    for i = 1, toRemove do
      local oldId = GuildRoll_adminLogOrder[1]
      table.remove(GuildRoll_adminLogOrder, 1)
      GuildRoll_adminLogSaved[oldId] = nil
      adminLogRuntime[oldId] = nil
    end
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

-- Public API: Add a structured admin log entry (local only, no network)
-- entry must be a table with fields: ts, action, actor, target, details
-- raid_details (optional) for RAID entries.
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

  applyAdminLogEntry(e)

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
        -- Filter by author
        GuildRoll:SafeDewdropAddLine(
          "text", "Filter by Author",
          "hasArrow", true,
          "hasSlider", false
        )
        GuildRoll:SafeDewdropAddLine(
          "text", "All Authors",
          "tooltipText", "Show all admin log entries",
          "func", function()
            filterAuthor = nil
            pcall(function() T:Refresh("GuildRoll_AdminLog") end)
          end,
          "level", 2
        )

        -- Build unique actor/author list
        local authors = {}
        for i = 1, table.getn(GuildRoll_adminLogOrder) do
          local id = GuildRoll_adminLogOrder[i]
          local entry = adminLogRuntime[id]
          if entry then
            local a = entry.actor or entry.author
            if a then authors[a] = true end
          end
        end

        for author, _ in pairs(authors) do
          GuildRoll:SafeDewdropAddLine(
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
        GuildRoll:SafeDewdropAddLine(
          "text", "Search",
          "tooltipText", "Search admin log entries",
          "func", function()
            StaticPopup_Show("GUILDROLL_ADMINLOG_SEARCH")
          end
        )

        -- Clear search
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
          "func", function()
            pcall(function() T:Refresh("GuildRoll_AdminLog") end)
          end
        )

        -- Clear Local (admins only)
        GuildRoll:SafeDewdropAddLine(
          "text", "Clear Local",
          "tooltipText", "Clear local admin log data",
          "func", function()
            GuildRoll_adminLogSaved = {}
            GuildRoll_adminLogOrder = {}
            adminLogRuntime = {}
            expandedRaidEntries = {}
            pcall(function() T:Refresh("GuildRoll_AdminLog") end)
            GuildRoll:defaultPrint("Admin log cleared (local).")
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

  -- Build filtered entry list
  local displayEntries = {}
  for i = 1, table.getn(GuildRoll_adminLogOrder) do
    local id = GuildRoll_adminLogOrder[i]
    local entry = adminLogRuntime[id]

    if entry then
      local include = true

      -- Apply author/actor filter
      if filterAuthor then
        local entryActor = entry.actor or entry.author
        if entryActor ~= filterAuthor then
          include = false
        end
      end

      -- Apply search filter
      if include and searchText and searchText ~= "" then
        local searchLower = string.lower(searchText)
        local actionLower  = string.lower(entry.action  or "")
        local detailsLower = string.lower(entry.details or "")
        local targetLower  = string.lower(entry.target  or "")
        local actorLower   = string.lower(entry.actor or entry.author or "")
        if not string.find(actionLower, searchLower, 1, true)
           and not string.find(detailsLower, searchLower, 1, true)
           and not string.find(targetLower, searchLower, 1, true)
           and not string.find(actorLower, searchLower, 1, true) then
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
        -- Combine target + details for the Dettagli column
        if entry.target and entry.target ~= "" then
          detailsStr = entry.target .. " - " .. (entry.details or "")
        else
          detailsStr = entry.details or ""
        end
      else
        -- Old format: entry.author + entry.action (full text)
        actorStr = entry.author or "Unknown"
        -- Try to extract tag like [DECAY], [GIVE], [RESET], [RAID]
        local tag = string.match(entry.action or "", "^%[([%w]+)%]")
        actionStr  = tag or "LOG"
        detailsStr = entry.action or ""
      end

      -- Check if this is a raid entry (expandable)
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
              displayText = string.format("  %s (%s's main) — Prev: %d, New: %d %s",
                player, alt_source, counts.old, counts.new, deltaColored)
            else
              displayText = string.format("  %s — Prev: %d, New: %d %s",
                player, counts.old, counts.new, deltaColored)
            end

            subcat:AddLine("text", displayText)
          end
        end
      else
        -- Regular (non-raid) entry
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
  if filterAuthor or searchText then
    local statusParts = {}
    if filterAuthor then
      table.insert(statusParts, string.format("Actor: %s", filterAuthor))
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
