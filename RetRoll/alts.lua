local T = AceLibrary("Tablet-2.0")
local D = AceLibrary("Dewdrop-2.0")
local C = AceLibrary("Crayon-2.0")

local BC = AceLibrary("Babble-Class-2.2")
local L = AceLibrary("AceLocale-2.2"):new("retroll")

RetRollAlts = RetRoll:NewModule("RetRollAlts", "AceDB-2.0")

function RetRollAlts:OnEnable()
  if not T:IsRegistered("RetRollAlts") then
    T:Register("RetRollAlts",
      "children", function()
        T:SetTitle(L["retroll alts"])
        self:OnTooltipUpdate()
      end,
      "showTitleWhenDetached", true,
      "showHintWhenDetached", true,
      "cantAttach", true,
      "menu", function()
        D:AddLine(
          "text", L["Refresh"],
          "tooltipText", L["Refresh window"],
          "func", function() RetRollAlts:Refresh() end
        )
      end      
    )
  end
  if not T:IsAttached("RetRollAlts") then
    T:Open("RetRollAlts")
  end
end

function RetRollAlts:OnDisable()
  T:Close("RetRollAlts")
end

function RetRollAlts:Refresh()
  T:Refresh("RetRollAlts")
end

function RetRollAlts:setHideScript()
  local i = 1
  local tablet = getglobal(string.format("Tablet20DetachedFrame%d",i))
  while (tablet) and i<100 do
    if tablet.owner ~= nil and tablet.owner == "RetRollAlts" then
      RetRoll:make_escable(string.format("Tablet20DetachedFrame%d",i),"add")
      tablet:SetScript("OnHide",nil)
      tablet:SetScript("OnHide",function()
          if not T:IsAttached("RetRollAlts") then
            T:Attach("RetRollAlts")
            this:SetScript("OnHide",nil)
          end
        end)
      break
    end    
    i = i+1
    tablet = getglobal(string.format("Tablet20DetachedFrame%d",i))
  end
end

function RetRollAlts:Top()
  if T:IsRegistered("RetRollAlts") and (T.registry.RetRollAlts.tooltip) then
    T.registry.RetRollAlts.tooltip.scroll=0
  end  
end

function RetRollAlts:Toggle(forceShow)
  self:Top()
  if T:IsAttached("RetRollAlts") then
    T:Detach("RetRollAlts") -- show
    if (T:IsLocked("RetRollAlts")) then
      T:ToggleLocked("RetRollAlts")
    end
    self:setHideScript()
  else
    if (forceShow) then
      RetRollAlts:Refresh()
    else
      T:Attach("RetRollAlts") -- hide
    end
  end
end

function RetRollAlts:OnClickItem(name)
  --ChatFrame_SendTell(name)
end

function RetRollAlts:BuildAltsTable()
  return RetRoll.alts
end

function RetRollAlts:OnTooltipUpdate()
  local cat = T:AddCategory(
      "columns", 2,
      "text",  C:Orange(L["Main"]),   "child_textR",    1, "child_textG",    1, "child_textB",    1, "child_justify",  "LEFT",
      "text2", C:Orange(L["Alts"]),  "child_text2R",   0, "child_text2G",   1, "child_text2B",   0, "child_justify2", "RIGHT"
    )
  local t = self:BuildAltsTable()
  for main, alts in pairs(t) do
    local altstring = ""
    for alt,class in pairs(alts) do
      local coloredalt = C:Colorize(BC:GetHexColor(class), alt)
      if altstring == "" then
        altstring = coloredalt
      else
        altstring = string.format("%s, %s",altstring,coloredalt)
      end
    end
    cat:AddLine(
      "text", main,
      "text2", altstring--,
      --"func", "OnClickItem", "arg1", self, "arg2", main
    )
  end
end

-- GLOBALS: RetRoll_saychannel,RetRoll_groupbyclass,RetRoll_groupbyarmor,RetRoll_groupbyrole,RetRoll_raidonly,RetRoll_decay,RetRoll_minPE,RetRoll_reservechannel,RetRoll_main,RetRoll_progress,RetRoll_discount,RetRoll_log,RetRoll_dbver,RetRoll_looted
-- GLOBALS: RetRoll,RetRoll_prices,RetRoll_standings,RetRoll_bids,RetRoll_loot,RetRoll_reserves,RetRollAlts,RetRoll_logs
