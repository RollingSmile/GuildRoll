-- Guard: Check if required libraries are available before proceeding
-- This prevents runtime errors if Ace/Tablet/Dewdrop/Crayon/Compost are not loaded
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
          "func", function() GuildRoll_logs:ConfirmClear() end
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

function GuildRoll_logs:ConfirmClear()
  -- Define StaticPopupDialog if not already defined
  if not StaticPopupDialogs["GUILDROLL_CLEAR_LOGS_CONFIRM"] then
    StaticPopupDialogs["GUILDROLL_CLEAR_LOGS_CONFIRM"] = {
      text = "This will permanently delete all Admin Log entries. Continue?",
      button1 = TEXT(ACCEPT),
      button2 = TEXT(CANCEL),
      OnAccept = function()
        GuildRoll_log = {}
        GuildRoll_logs:Refresh()
      end,
      timeout = 0,
      whileDead = 1,
      hideOnEscape = 1
    }
  end
  StaticPopup_Show("GUILDROLL_CLEAR_LOGS_CONFIRM")
end

function GuildRoll_logs:Refresh()
  pcall(function() T:Refresh("GuildRoll_logs") end)
end

function GuildRoll_logs:setHideScript()
  local frame = GuildRoll:FindDetachedFrame("GuildRoll_logs")
  if frame then
    GuildRoll:make_escable(frame:GetName(), "add")
    if frame.SetScript then
      frame:SetScript("OnHide", nil)
      frame:SetScript("OnHide", function(f)
          -- Protect call with pcall to avoid Tablet errors
          pcall(function()
            if T and T.IsAttached and not T:IsAttached("GuildRoll_logs") then
              T:Attach("GuildRoll_logs")
            end
            if f and f.SetScript then
              f:SetScript("OnHide", nil)
            end
          end)
        end)
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
    if (T.IsLocked and T:IsLocked("GuildRoll_logs")) then
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
  local isOfficer = false
  if CanEditOfficerNote then
    -- call safely in case the API throws; pcall returns (ok, result)
    local ok, res = pcall(CanEditOfficerNote)
    if ok and res then
      isOfficer = true
    end
  end

  if isOfficer then
    -- {timestamp,line}
    return self:reverse(GuildRoll_log)
  else
    -- Show personal log for current player
    local playerName = UnitName("player") or UnitName("player") or "player"
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
  local frame = GuildRoll:FindDetachedFrame("GuildRoll_personal_logs")
  if frame then
    GuildRoll:make_escable(frame:GetName(), "add")
    if frame.SetScript then
      frame:SetScript("OnHide", nil)
      frame:SetScript("OnHide", function(f)
          pcall(function()
            if T and T.IsAttached and not T:IsAttached("GuildRoll_personal_logs") then
              T:Attach("GuildRoll_personal_logs")
            end
            if f and f.SetScript then
              f:SetScript("OnHide", nil)
            end
          end)
        end)
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
    if (T.IsLocked and T:IsLocked("GuildRoll_personal_logs")) then
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

-- Helper function to show personal log with robust toggle behavior
function GuildRoll:ShowPersonalLog()
  local name = UnitName("player")

  -- Fallback if logs/tablet not available
  if not GuildRoll_logs or not GuildRoll_logs.registerPersonalTablet then
    if GuildRoll and GuildRoll.SavePersonalLog then
      GuildRoll:SavePersonalLog(name)
    end
    return
  end

  -- Ensure the personal tablet is registered
  GuildRoll_logs:registerPersonalTablet()

  -- Find any existing detached frame for the personal tablet
  local detached = GuildRoll:FindDetachedFrame("GuildRoll_personal_logs")
  local detachedVisible = (detached and detached:IsShown())

  -- If there's a visible detached frame
  if detachedVisible then
    if lastPersonalShown == name then
      pcall(function() detached:Hide() end)
      pcall(function()
        if T and T.IsAttached and T.Attach then
          T:Attach("GuildRoll_personal_logs")
        end
      end)
      lastPersonalShown = nil
      currentPersonalName = nil
      return
    else
      currentPersonalName = name
      lastPersonalShown = name
      pcall(function() GuildRoll_logs:RefreshPersonal() end)
      return
    end
  end

  -- Not visible: set current name
  currentPersonalName = name
  lastPersonalShown = name

  local isAttached = false
  if T and T.IsAttached then
    local ok, result = pcall(function() return T:IsAttached("GuildRoll_personal_logs") end)
    if ok then
      isAttached = result
    end
  end

  if isAttached then
    pcall(function() T:Open("GuildRoll_personal_logs") end)
    pcall(function() GuildRoll_logs:RefreshPersonal() end)

    local alreadyDetached = GuildRoll:FindDetachedFrame("GuildRoll_personal_logs")
    if alreadyDetached then
      pcall(function() if alreadyDetached.Show then alreadyDetached:Show() end end)
    else
      pcall(function() T:Detach("GuildRoll_personal_logs") end)
    end

    pcall(function() GuildRoll_logs:setHideScriptPersonal() end)
    return
  end

  pcall(function() T:Open("GuildRoll_personal_logs") end)
  pcall(function() GuildRoll_logs:RefreshPersonal() end)

  local alreadyDetached = GuildRoll:FindDetachedFrame("GuildRoll_personal_logs")
  if not alreadyDetached then
    pcall(function() T:Detach("GuildRoll_personal_logs") end)
  else
    pcall(function() if alreadyDetached.Show then alreadyDetached:Show() end end)
  end

  pcall(function() GuildRoll_logs:setHideScriptPersonal() end)
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

-- GLOBALS: GuildRoll_saychannel,GuildRoll_groupbyclass,GuildRoll_groupbyarmor,GuildRoll_groupbyrole,GuildRoll_raidonly,GuildRoll_decay,GuildRoll_minPE,GuildRoll_main,GuildRoll_progress,GuildRoll_disc[...[...]
-- GLOBALS: GuildRoll,GuildRoll_prices,GuildRoll_standings,GuildRoll_bids,GuildRoll_loot,GuildRollAlts,GuildRoll_logs,GuildRoll_personalLogSaved,GuildRoll_personalLogs
