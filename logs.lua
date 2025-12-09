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
  GuildRoll_personalLogs[name] = GuildRoll_personalLogs[name] or {}
  table.insert(GuildRoll_personalLogs[name], {ts, action})
  GuildRoll_personalLogSaved[name] = GuildRoll_personalLogSaved[name] or {}
  table.insert(GuildRoll_personalLogSaved[name], {ts, action})
  local max_keep = 500
  if #GuildRoll_personalLogSaved[name] > max_keep then
    for i = 1, (#GuildRoll_personalLogSaved[name] - max_keep) do
      table.remove(GuildRoll_personalLogSaved[name], 1)
    end
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
  if not T:IsAttached("GuildRoll_logs") then
    T:Open("GuildRoll_logs")
  end
end

function GuildRoll_logs:OnDisable()
  T:Close("GuildRoll_logs")
end

function GuildRoll_logs:Refresh()
  T:Refresh("GuildRoll_logs")
end

function GuildRoll_logs:setHideScript()
  local i = 1
  local tablet = getglobal(string.format("Tablet20DetachedFrame%d",i))
  while (tablet) and i<100 do
    if tablet.owner ~= nil and tablet.owner == "GuildRoll_logs" then
      GuildRoll:make_escable(string.format("Tablet20DetachedFrame%d",i),"add")
      tablet:SetScript("OnHide",nil)
      tablet:SetScript("OnHide",function()
          if not T:IsAttached("GuildRoll_logs") then
            T:Attach("GuildRoll_logs")
            this:SetScript("OnHide",nil)
          end
        end)
      break
    end    
    i = i+1
    tablet = getglobal(string.format("Tablet20DetachedFrame%d",i))
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
    T:Detach("GuildRoll_logs") -- show
    if (T:IsLocked("GuildRoll_logs")) then
      T:ToggleLocked("GuildRoll_logs")
    end
    self:setHideScript()
  else
    if (forceShow) then
      GuildRoll_logs:Refresh()
    else
      T:Attach("GuildRoll_logs") -- hide
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
  local isOfficer = CanEditOfficerNote()
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

-- Helper function to show personal log
function GuildRoll:ShowPersonalLog(name)
  name = name or UnitName("player")
  local logs = GuildRoll_personalLogs[name] or GuildRoll_personalLogSaved[name] or {}
  
  -- Try to use guildep_export frame from standings.lua if available
  if guildep_export and guildep_export.title and guildep_export.edit then
    guildep_export.title:SetText("Personal Log: " .. name)
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
    DEFAULT_CHAT_FRAME:AddMessage("=== Personal Log for " .. name .. " ===")
    for i = table.getn(logs), 1, -1 do
      local entry = logs[i]
      if entry and entry[1] and entry[2] then
        DEFAULT_CHAT_FRAME:AddMessage(entry[1] .. " - " .. entry[2])
      end
    end
    DEFAULT_CHAT_FRAME:AddMessage("=== End of Log ===")
  end
end

-- Helper function to save personal log to chat for copy-paste
function GuildRoll:SavePersonalLog(name)
  name = name or UnitName("player")
  local logs = GuildRoll_personalLogs[name] or GuildRoll_personalLogSaved[name] or {}
  
  -- Try to use guildep_export frame from standings.lua if available
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

-- GLOBALS: GuildRoll_saychannel,GuildRoll_groupbyclass,GuildRoll_groupbyarmor,GuildRoll_groupbyrole,GuildRoll_raidonly,GuildRoll_decay,GuildRoll_minPE,GuildRoll_main,GuildRoll_progress,GuildRoll_discount,GuildRoll_log,GuildRoll_dbver,GuildRoll_looted
-- GLOBALS: GuildRoll,GuildRoll_prices,GuildRoll_standings,GuildRoll_bids,GuildRoll_loot,GuildRollAlts,GuildRoll_logs,GuildRoll_personalLogSaved,GuildRoll_personalLogs
