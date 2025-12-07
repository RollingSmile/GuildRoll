local T = AceLibrary("Tablet-2.0")
local D = AceLibrary("Dewdrop-2.0")
local C = AceLibrary("Crayon-2.0")

local BC = AceLibrary("Babble-Class-2.2")
local L = AceLibrary("AceLocale-2.2"):new("retroll")

RetRoll_reserves = RetRoll:NewModule("RetRoll_reserves", "AceDB-2.0")

function RetRoll_reserves:OnEnable()
  if not T:IsRegistered("RetRoll_reserves") then
    T:Register("RetRoll_reserves",
      "children", function()
        T:SetTitle(L["retroll reserves"])
        self:OnTooltipUpdate()
      end,
      "showTitleWhenDetached", true,
      "showHintWhenDetached", true,
      "cantAttach", true,
      "menu", function()
        D:AddLine(
          "text", L["Refresh"],
          "tooltipText", L["Refresh window"],
          "func", function() RetRoll_reserves:Refresh() end
        )
      end      
    )
  end
  if not T:IsAttached("RetRoll_reserves") then
    T:Open("RetRoll_reserves")
  end
end

function RetRoll_reserves:OnDisable()
  T:Close("RetRoll_reserves")
end

function RetRoll_reserves:Refresh()
  T:Refresh("RetRoll_reserves")
end

function RetRoll_reserves:setHideScript()
  local i = 1
  local tablet = getglobal(string.format("Tablet20DetachedFrame%d",i))
  while (tablet) and i<100 do
    if tablet.owner ~= nil and tablet.owner == "RetRoll_reserves" then
      RetRoll:make_escable(string.format("Tablet20DetachedFrame%d",i),"add")
      tablet:SetScript("OnHide",nil)
      tablet:SetScript("OnHide",function()
          if not T:IsAttached("RetRoll_reserves") then
            T:Attach("RetRoll_reserves")
            this:SetScript("OnHide",nil)
          end
        end)
      break
    end    
    i = i+1
    tablet = getglobal(string.format("Tablet20DetachedFrame%d",i))
  end  
end

function RetRoll_reserves:Top()
  if T:IsRegistered("RetRoll_reserves") and (T.registry.RetRoll_reserves.tooltip) then
    T.registry.RetRoll_reserves.tooltip.scroll=0
  end  
end

function RetRoll_reserves:Toggle(forceShow)
  self:Top()
  if T:IsAttached("RetRoll_reserves") then
    T:Detach("RetRoll_reserves") -- show
    if (T:IsLocked("RetRoll_reserves")) then
      T:ToggleLocked("RetRoll_reserves")
    end
    self:setHideScript()
  else
    if (forceShow) then
      RetRoll_reserves:Refresh()
    else
      T:Attach("RetRoll_reserves") -- hide
    end
  end  
end

function RetRoll_reserves:OnClickItem(name)
  ChatFrame_SendTell(name)
end

function RetRoll_reserves:BuildReservesTable()
  --{name,class,rank,alt}
  table.sort(RetRoll.reserves, function(a,b)
    if (a[2] ~= b[2]) then return a[2] > b[2]
    else return a[1] > b[1] end
  end)
  return RetRoll.reserves
end

function RetRoll_reserves:OnTooltipUpdate()
  local cdcat = T:AddCategory(
      "columns", 2
    )
  cdcat:AddLine(
      "text", C:Orange(L["Countdown"]),
      "text2", RetRoll.timer.cd_text
    )
  local cat = T:AddCategory(
      "columns", 3,
      "text",  C:Orange(L["Name"]),   "child_textR",    1, "child_textG",    1, "child_textB",    1, "child_justify",  "LEFT",
      "text2", C:Orange(L["Rank"]),     "child_text2R",   1, "child_text2G",   1, "child_text2B",   0, "child_justify2", "RIGHT",
      "text3", C:Orange(L["OnAlt"]),  "child_text3R",   0, "child_text3G",   1, "child_text3B",   0, "child_justify3", "RIGHT"
    )
  local t = self:BuildReservesTable()
  for i = 1, table.getn(t) do
    local name, class, rank, alt = unpack(t[i])
    cat:AddLine(
      "text", C:Colorize(BC:GetHexColor(class), name),
      "text2", rank,
      "text3", alt or "",
      "func", "OnClickItem", "arg1", self, "arg2", alt or name
    )
  end
end

-- GLOBALS: RetRoll_saychannel,RetRoll_groupbyclass,RetRoll_groupbyarmor,RetRoll_groupbyrole,RetRoll_raidonly,RetRoll_decay,RetRoll_minPE,RetRoll_reservechannel,RetRoll_main,RetRoll_progress,RetRoll_discount,RetRoll_log,RetRoll_dbver,RetRoll_looted
-- GLOBALS: RetRoll,RetRoll_prices,RetRoll_standings,RetRoll_bids,RetRoll_loot,RetRoll_reserves,RetRollAlts,RetRoll_logs
