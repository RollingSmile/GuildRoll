local T = AceLibrary("Tablet-2.0")
local D = AceLibrary("Dewdrop-2.0")
local C = AceLibrary("Crayon-2.0")

local BC = AceLibrary("Babble-Class-2.2")
local L = AceLibrary("AceLocale-2.2"):new("guildroll")

GuildRoll_reserves = GuildRoll:NewModule("GuildRoll_reserves", "AceDB-2.0")

function GuildRoll_reserves:OnEnable()
  if not T:IsRegistered("GuildRoll_reserves") then
    T:Register("GuildRoll_reserves",
      "children", function()
        T:SetTitle(L["guildroll reserves"])
        self:OnTooltipUpdate()
      end,
      "showTitleWhenDetached", true,
      "showHintWhenDetached", true,
      "cantAttach", true,
      "menu", function()
        D:AddLine(
          "text", L["Refresh"],
          "tooltipText", L["Refresh window"],
          "func", function() GuildRoll_reserves:Refresh() end
        )
      end      
    )
  end
  if not T:IsAttached("GuildRoll_reserves") then
    T:Open("GuildRoll_reserves")
  end
end

function GuildRoll_reserves:OnDisable()
  T:Close("GuildRoll_reserves")
end

function GuildRoll_reserves:Refresh()
  T:Refresh("GuildRoll_reserves")
end

function GuildRoll_reserves:setHideScript()
  local i = 1
  local tablet = getglobal(string.format("Tablet20DetachedFrame%d",i))
  while (tablet) and i<100 do
    if tablet.owner ~= nil and tablet.owner == "GuildRoll_reserves" then
      GuildRoll:make_escable(string.format("Tablet20DetachedFrame%d",i),"add")
      tablet:SetScript("OnHide",nil)
      tablet:SetScript("OnHide",function()
          if not T:IsAttached("GuildRoll_reserves") then
            T:Attach("GuildRoll_reserves")
            this:SetScript("OnHide",nil)
          end
        end)
      break
    end    
    i = i+1
    tablet = getglobal(string.format("Tablet20DetachedFrame%d",i))
  end  
end

function GuildRoll_reserves:Top()
  if T:IsRegistered("GuildRoll_reserves") and (T.registry.GuildRoll_reserves.tooltip) then
    T.registry.GuildRoll_reserves.tooltip.scroll=0
  end  
end

function GuildRoll_reserves:Toggle(forceShow)
  self:Top()
  if T:IsAttached("GuildRoll_reserves") then
    T:Detach("GuildRoll_reserves") -- show
    if (T:IsLocked("GuildRoll_reserves")) then
      T:ToggleLocked("GuildRoll_reserves")
    end
    self:setHideScript()
  else
    if (forceShow) then
      GuildRoll_reserves:Refresh()
    else
      T:Attach("GuildRoll_reserves") -- hide
    end
  end  
end

function GuildRoll_reserves:OnClickItem(name)
  ChatFrame_SendTell(name)
end

function GuildRoll_reserves:BuildReservesTable()
  --{name,class,rank,alt}
  table.sort(GuildRoll.reserves, function(a,b)
    if (a[2] ~= b[2]) then return a[2] > b[2]
    else return a[1] > b[1] end
  end)
  return GuildRoll.reserves
end

function GuildRoll_reserves:OnTooltipUpdate()
  local cdcat = T:AddCategory(
      "columns", 2
    )
  cdcat:AddLine(
      "text", C:Orange(L["Countdown"]),
      "text2", GuildRoll.timer.cd_text
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

-- GLOBALS: GuildRoll_saychannel,GuildRoll_groupbyclass,GuildRoll_groupbyarmor,GuildRoll_groupbyrole,GuildRoll_raidonly,GuildRoll_decay,GuildRoll_minPE,GuildRoll_reservechannel,GuildRoll_main,GuildRoll_progress,GuildRoll_discount,GuildRoll_log,GuildRoll_dbver,GuildRoll_looted
-- GLOBALS: GuildRoll,GuildRoll_prices,GuildRoll_standings,GuildRoll_bids,GuildRoll_loot,GuildRoll_reserves,GuildRollAlts,GuildRoll_logs
