local T = AceLibrary("Tablet-2.0")
local D = AceLibrary("Dewdrop-2.0")
local C = AceLibrary("Crayon-2.0")
local CP = AceLibrary("Compost-2.0")
local L = AceLibrary("AceLocale-2.2"):new("retroll")

RetRoll_logs = RetRoll:NewModule("RetRoll_logs", "AceDB-2.0")
RetRoll_logs.tmp = CP:Acquire()

function RetRoll_logs:OnEnable()
  if not T:IsRegistered("RetRoll_logs") then
    T:Register("RetRoll_logs",
      "children", function()
        T:SetTitle(L["retroll logs"])
        self:OnTooltipUpdate()
      end,
      "showTitleWhenDetached", true,
      "showHintWhenDetached", true,
      "cantAttach", true,
      "menu", function()
        D:AddLine(
          "text", L["Refresh"],
          "tooltipText", L["Refresh window"],
          "func", function() RetRoll_logs:Refresh() end
        )
        D:AddLine(
          "text", L["Clear"],
          "tooltipText", L["Clear Logs."],
          "func", function() RetRoll_log = {} RetRoll_logs:Refresh() end
        )
      end      
    )
  end
  if not T:IsAttached("RetRoll_logs") then
    T:Open("RetRoll_logs")
  end
end

function RetRoll_logs:OnDisable()
  T:Close("RetRoll_logs")
end

function RetRoll_logs:Refresh()
  T:Refresh("RetRoll_logs")
end

function RetRoll_logs:setHideScript()
  local i = 1
  local tablet = getglobal(string.format("Tablet20DetachedFrame%d",i))
  while (tablet) and i<100 do
    if tablet.owner ~= nil and tablet.owner == "RetRoll_logs" then
      RetRoll:make_escable(string.format("Tablet20DetachedFrame%d",i),"add")
      tablet:SetScript("OnHide",nil)
      tablet:SetScript("OnHide",function()
          if not T:IsAttached("RetRoll_logs") then
            T:Attach("RetRoll_logs")
            this:SetScript("OnHide",nil)
          end
        end)
      break
    end    
    i = i+1
    tablet = getglobal(string.format("Tablet20DetachedFrame%d",i))
  end  
end

function RetRoll_logs:Top()
  if T:IsRegistered("RetRoll_logs") and (T.registry.RetRoll_logs.tooltip) then
    T.registry.RetRoll_logs.tooltip.scroll=0
  end  
end

function RetRoll_logs:Toggle(forceShow)
  self:Top()
  if T:IsAttached("RetRoll_logs") then
    T:Detach("RetRoll_logs") -- show
    if (T:IsLocked("RetRoll_logs")) then
      T:ToggleLocked("RetRoll_logs")
    end
    self:setHideScript()
  else
    if (forceShow) then
      RetRoll_logs:Refresh()
    else
      T:Attach("RetRoll_logs") -- hide
    end
  end  
end

function RetRoll_logs:reverse(arr)
  CP:Recycle(RetRoll_logs.tmp)
  for _,val in ipairs(arr) do
    table.insert(RetRoll_logs.tmp,val)
  end
  local i, j = 1, table.getn(RetRoll_logs.tmp)
  while i < j do
    RetRoll_logs.tmp[i], RetRoll_logs.tmp[j] = RetRoll_logs.tmp[j], RetRoll_logs.tmp[i]
    i = i + 1
    j = j - 1
  end
  return RetRoll_logs.tmp
end

function RetRoll_logs:BuildLogsTable()
  -- {timestamp,line}
  return self:reverse(RetRoll_log)
end

function RetRoll_logs:OnTooltipUpdate()
  local cat = T:AddCategory(
      "columns", 2,
      "text",  C:Orange(L["Time"]),   "child_textR",    1, "child_textG",    1, "child_textB",    1, "child_justify",  "LEFT",
      "text2", C:Orange(L["Action"]),     "child_text2R",   1, "child_text2G",   1, "child_text2B",   1, "child_justify2", "RIGHT"
    )
  local t = RetRoll_logs:BuildLogsTable()
  for i = 1, table.getn(t) do
    local timestamp, line = unpack(t[i])
    cat:AddLine(
      "text", C:Silver(timestamp),
      "text2", line
    )
  end  
end

-- GLOBALS: RetRoll_saychannel,RetRoll_groupbyclass,RetRoll_groupbyarmor,RetRoll_groupbyrole,RetRoll_raidonly,RetRoll_decay,RetRoll_minPE,RetRoll_reservechannel,RetRoll_main,RetRoll_progress,RetRoll_discount,RetRoll_log,RetRoll_dbver,RetRoll_looted
-- GLOBALS: RetRoll,RetRoll_prices,RetRoll_standings,RetRoll_bids,RetRoll_loot,RetRoll_reserves,RetRollAlts,RetRoll_logs
