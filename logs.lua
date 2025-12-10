local T = AceLibrary("Tablet-2.0")
local D = AceLibrary("Dewdrop-2.0")
local C = AceLibrary("Crayon-2.0")
local CP = AceLibrary("Compost-2.0")
local L = AceLibrary("AceLocale-2.2"):new("guildroll")

GuildRoll_logs = GuildRoll:NewModule("GuildRoll_logs", "AceDB-2.0")
GuildRoll_logs.tmp = CP:Acquire()

-- Persistent per-character saved-personal logs
GuildRoll_personalLogSaved = GuildRoll_personalLogSaved or {} -- saved between sessions (SavedVariable if added to .toc)
GuildRoll_personalLogs = GuildRoll_personalLogs or {} -- runtime cache

function GuildRoll:personalLogAdd(target, action)
  if not target or not action then return end
  local name = target
  local ts = date("%Y-%m-%d %H:%M:%S")
  
  -- Add to runtime cache
  GuildRoll_personalLogs[name] = GuildRoll_personalLogs[name] or {}
  table.insert(GuildRoll_personalLogs[name], {ts, action})
  
  -- Add to persistent storage
  GuildRoll_personalLogSaved[name] = GuildRoll_personalLogSaved[name] or {}
  table.insert(GuildRoll_personalLogSaved[name], {ts, action})
  
  -- Trim to last 200 entries efficiently
  local max_keep = 200
  if table.getn(GuildRoll_personalLogSaved[name]) > max_keep then
    local newLog = {}
    local startIdx = table.getn(GuildRoll_personalLogSaved[name]) - max_keep + 1
    for i = startIdx, table.getn(GuildRoll_personalLogSaved[name]) do
      table.insert(newLog, GuildRoll_personalLogSaved[name][i])
    end
    GuildRoll_personalLogSaved[name] = newLog
  end
end

function GuildRoll_logs:OnEnable()
  if not T:IsRegistered("GuildRoll_logs") then
    T:Register("GuildRoll_logs",
      "children", function()
        T:SetTitle(L["guildroll logs"])
        self:OnTooltipUpdate()
      end,
      "showTitleWhenDetached", true,
      "showHintWhenDetached", true,
      "cantAttach", true,
      "menu", function()
        D:AddLine(
          "text", L["Refresh"],
          "tooltipText", L["Refresh window"],
          "func", function() GuildRoll_logs:Refresh() end
        )
        D:AddLine(
          "text", L["Clear"],
          "tooltipText", L["Clear Logs."],
          "func", function() GuildRoll_log = {} GuildRoll_logs:Refresh() end
        )
      end      
    )
  end
  -- apri solo se non è già attached (coerente con gli altri moduli)
  if not T:IsAttached("GuildRoll_logs") then
    pcall(function() T:Open("GuildRoll_logs") end)
  end
end

function GuildRoll_logs:OnDisable()
  pcall(function() T:Close("GuildRoll_logs") end)
end

function GuildRoll_logs:Refresh()
  pcall(function() T:Refresh("GuildRoll_logs") end)
end

-- helper: find an existing detached Tablet20DetachedFrame owned by 'ownerName'
local function findDetachedFrame(ownerName)
  for i = 1, 100 do
    local name = string.format("Tablet20DetachedFrame%d", i)
    local f = _G[name]
    if f then
      -- some Tablet detached frames might exist without owner field; guard
      if f.owner and f.owner == ownerName then
        return f
      end
    end
  end
  return nil
end

function GuildRoll_logs:setHideScript()
  for i = 1, 100 do
    local tablet = _G[string.format("Tablet20DetachedFrame%d", i)]
    if (tablet) then
      if tablet.owner ~= nil and tablet.owner == "GuildRoll_logs" then
        GuildRoll:make_escable(string.format("Tablet20DetachedFrame%d",i),"add")
        -- rimuoviamo qualsiasi handler precedente e aggiungiamo uno robusto che usa il parametro frame
        tablet:SetScript("OnHide", nil)
        tablet:SetScript("OnHide", function(frame)
            -- protegge la chiamata con pcall per evitare errori da Tablet
            pcall(function()
              if not T:IsAttached("GuildRoll_logs") then
                T:Attach("GuildRoll_logs")
                frame:SetScript("OnHide", nil)
              end
            end)
          end)
        break
      end
    end
  end
end

function GuildRoll_logs:Top()
  if T:IsRegistered("GuildRoll_logs") and (T.registry.GuildRoll_logs.tooltip) then
    T.registry.GuildRoll_logs.tooltip.scroll=0
  end  
end

function GuildRoll_logs:Toggle(forceShow)
  self:Top()
  if T:IsAttached("GuildRoll_logs") then
    pcall(function() T:Detach("GuildRoll_logs") end) -- show
    if (T:IsLocked and T:IsLocked("GuildRoll_logs")) then
      pcall(function() T:ToggleLocked("GuildRoll_logs") end)
    end
    self:setHideScript()
  else
    if (forceShow) then
      GuildRoll_logs:Refresh()
    else
      pcall(function() T:Attach("GuildRoll_logs") end) -- hide
    end
  end  
end

function GuildRoll_logs:reverse(arr)
  CP:Recycle(GuildRoll_logs.tmp)
  for _,val in ipairs(arr) do
    table.insert(GuildRoll_logs.tmp,val)
  end
  local i, j = 1, table.getn(GuildRoll_logs.tmp)
  while i < j do
    GuildRoll_logs.tmp[i], GuildRoll_logs.tmp[j] = GuildRoll_logs.tmp[j], GuildRoll_logs.tmp[i]
    i = i + 1
    j = j - 1
  end
  return GuildRoll_logs.tmp
end

function GuildRoll_logs:BuildLogsTable()
  -- Check if user is officer - show global log
  -- Otherwise show personal log
  local isOfficer = (CanEditOfficerNote and CanEditOfficerNote()) or false
  if isOfficer then
    -- {timestamp,line}
    return self:reverse(GuildRoll_log)
  else
    -- Show personal log for current player
    local playerName = UnitName("player")
    local personalLog = GuildRoll_personalLogs[playerName] or {}
    return self:reverse(personalLog)
  end
end

function GuildRoll_logs:OnTooltipUpdate()
  local cat = T:AddCategory(
      "columns", 2,
      "text",  C:Orange(L["Time"]),   "child_textR",    1, "child_textG",    1, "child_textB",    1, "child_justify",  "LEFT",
      "text2", C:Orange(L["Action"]),     "child_text2R",   1, "child_text2G",   1, "child_text2B",   1, "child_justify2", "RIGHT"
    )
  local t = GuildRoll_logs:BuildLogsTable()
  for i = 1, table.getn(t) do
    local timestamp, line = unpack(t[i])
    cat:AddLine(
      "text", C:Silver(timestamp),
      "text2", line
    )
  end  
end

-- Personal log Tablet support
local personalTabletRegistered = false
local currentPersonalName = nil
local lastPersonalShown = nil -- track the name currently being shown in the detached personal window

function GuildRoll_logs:registerPersonalTablet()
  if personalTabletRegistered then return end
  personalTabletRegistered = true

  T:Register("GuildRoll_personal_logs",
    "children", function()
      if currentPersonalName then
        T:SetTitle("Personal Log: " .. currentPersonalName)
      else
        T:SetTitle("Personal Log")
      end
      GuildRoll_logs:OnTooltipUpdatePersonal()
    end,
    "showTitleWhenDetached", true,
    "showHintWhenDetached", true,
    "cantAttach", true
    -- menu intentionally removed: personal tablet has no menu or commands
  )
end

function GuildRoll_logs:RefreshPersonal()
  if not personalTabletRegistered then return end
  pcall(function() T:Refresh("GuildRoll_personal_logs") end)
end

function GuildRoll_logs:setHideScriptPersonal()
  for i = 1, 100 do
    local tablet = _G[string.format("Tablet20DetachedFrame%d", i)]
    if (tablet) then
      if tablet.owner ~= nil and tablet.owner == "GuildRoll_personal_logs" then
        GuildRoll:make_escable(string.format("Tablet20DetachedFrame%d",i),"add")
        tablet:SetScript("OnHide", nil)
        tablet:SetScript("OnHide", function(frame)
            pcall(function()
              if not T:IsAttached("GuildRoll_personal_logs") then
                T:Attach("GuildRoll_personal_logs")
                frame:SetScript("OnHide", nil)
              end
            end)
          end)
        break
      end
    end
  end
end

function GuildRoll_logs:TopPersonal()
  if T:IsRegistered("GuildRoll_personal_logs") and (T.registry.GuildRoll_personal_logs.tooltip) then
    T.registry.GuildRoll_personal_logs.tooltip.scroll=0
  end  
end

function GuildRoll_logs:TogglePersonal(forceShow)
  self:TopPersonal()
  if T:IsAttached("GuildRoll_personal_logs") then
    pcall(function() T:Detach("GuildRoll_personal_logs") end) -- show
    if (T:IsLocked and T:IsLocked("GuildRoll_personal_logs")) then
      pcall(function() T:ToggleLocked("GuildRoll_personal_logs") end)
    end
    self:setHideScriptPersonal()
  else
    if (forceShow) then
      GuildRoll_logs:RefreshPersonal()
    else
      pcall(function() T:Attach("GuildRoll_personal_logs") end) -- hide
    end
  end  
end

function GuildRoll_logs:OnTooltipUpdatePersonal()
  local cat = T:AddCategory(
      "columns", 2,
      "text",  C:Orange(L["Time"]),   "child_textR",    1, "child_textG",    1, "child_textB",    1, "child_justify",  "LEFT",
      "text2", C:Orange(L["Action"]),     "child_text2R",   1, "child_text2G",   1, "child_text2B",   1, "child_justify2", "RIGHT"
    )
  local name = currentPersonalName or UnitName("player")
  local t = GuildRoll_personalLogs[name] or GuildRoll_personalLogSaved[name] or {}
  -- use reverse (show newest first)
  local rev = GuildRoll_logs:reverse(t)

  if table.getn(rev) == 0 then
    -- Show a friendly message when the personal log is empty
    cat:AddLine(
      "text", C:Yellow("Personal log is empty"),
      "text2", ""
    )
    return
  end

  for i = 1, table.getn(rev) do
    local timestamp, line = unpack(rev[i])
    cat:AddLine(
      "text", C:Silver(timestamp),
      "text2", line
    )
  end
end

-- Helper function to show personal log
function GuildRoll:ShowPersonalLog(name)
  -- If name not provided, use current player (this is the control+click behavior on the icon)
  name = name or UnitName("player")

  -- Ensure personal tablet registered
  GuildRoll_logs:registerPersonalTablet()

  -- Find any existing detached frame for this personal tablet
  local detached = findDetachedFrame("GuildRoll_personal_logs")
  local detachedVisible = (detached and detached:IsShown())

  -- If there's a visible detached frame
  if detachedVisible then
    -- If the visible frame is already showing same name => toggle close (attach)
    if lastPersonalShown == name then
      -- hide the detached frame and ensure tablet state is attached (docked)
      detached:Hide()
      pcall(function() T:Attach("GuildRoll_personal_logs") end)
      lastPersonalShown = nil
      currentPersonalName = nil
      return
    else
      -- visible but different name -> update contents
      currentPersonalName = name
      lastPersonalShown = name
      GuildRoll_logs:RefreshPersonal()
      return
    end
  end

  -- Not visible (either attached or no detached frame exists)
  currentPersonalName = name
  lastPersonalShown = name

  -- If it's currently attached (docked), detach (show)
  if T:IsAttached and T:IsAttached("GuildRoll_personal_logs") then
    pcall(function() T:Open("GuildRoll_personal_logs") end)
    GuildRoll_logs:RefreshPersonal()
    pcall(function() T:Detach("GuildRoll_personal_logs") end)
    GuildRoll_logs:setHideScriptPersonal()
    return
  end

  -- Otherwise, try to open and show a detached frame robustly
  pcall(function() T:Open("GuildRoll_personal_logs") end)
  GuildRoll_logs:RefreshPersonal()
  local alreadyDetached = findDetachedFrame("GuildRoll_personal_logs")
  if not alreadyDetached then
    pcall(function() T:Detach("GuildRoll_personal_logs") end)
    GuildRoll_logs:setHideScriptPersonal()
  else
    -- If there's a detached frame but it wasn't visible, show it
    pcall(function() alreadyDetached:Show() end)
    GuildRoll_logs:setHideScriptPersonal()
  end
end

-- Helper function to save personal log to chat for copy-paste (internal fallback only)
function GuildRoll:SavePersonalLog(name)
  name = name or UnitName("player")
  local logs = GuildRoll_personalLogs[name] or GuildRoll_personalLogSaved[name] or {}
  
  -- If Tablet personal window is available and shown, refresh that instead
  if personalTabletRegistered then
    currentPersonalName = name
    GuildRoll_logs:RefreshPersonal()
    return
  end

  -- Fallback: Try to use guildep_export frame from standings.lua if available
  if guildep_export and guildep_export.title and guildep_export.edit then
    guildep_export.title:SetText("Save Personal Log: " .. name)
    local text = ""
    for i = table.getn(logs), 1, -1 do
      local entry = logs[i]
      if entry and entry[1] and entry[2] then
        text = text .. entry[1] .. " - " .. entry[2] .. "\n"
      end
    end
    guildep_export.edit:SetText(text)
    guildep_export.edit:HighlightText()
    guildep_export:Show()
  else
    -- Fallback to chat frame
    DEFAULT_CHAT_FRAME:AddMessage("=== Personal Log for " .. name .. " (Copy from chat) ===")
    for i = table.getn(logs), 1, -1 do
      local entry = logs[i]
      if entry and entry[1] and entry[2] then
        DEFAULT_CHAT_FRAME:AddMessage(entry[1] .. " - " .. entry[2])
      end
    end
    DEFAULT_CHAT_FRAME:AddMessage("=== End of Log ===")
  end
end

-- GLOBALS: GuildRoll_saychannel,GuildRoll_groupbyclass,GuildRoll_groupbyarmor,GuildRoll_groupbyrole,GuildRoll_raidonly,GuildRoll_decay,GuildRoll_minPE,GuildRoll_main,GuildRoll_progress,GuildRoll_disc[...]
-- GLOBALS: GuildRoll,GuildRoll_prices,GuildRoll_standings,GuildRoll_bids,GuildRoll_loot,GuildRollAlts,GuildRoll_logs,GuildRoll_personalLogSaved,GuildRoll_personalLogs
