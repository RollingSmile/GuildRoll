local T = AceLibrary("Tablet-2.0")
local D = AceLibrary("Dewdrop-2.0")
local C = AceLibrary("Crayon-2.0")

local BC = AceLibrary("Babble-Class-2.2")
local L = AceLibrary("AceLocale-2.2"):new("guildroll")

GuildRollAlts = GuildRoll:NewModule("GuildRollAlts", "AceDB-2.0")

function GuildRollAlts:OnEnable()
  if not T:IsRegistered("GuildRollAlts") then
    T:Register("GuildRollAlts",
      "children", function()
        T:SetTitle(L["guildroll alts"])
        self:OnTooltipUpdate()
      end,
      "showTitleWhenDetached", true,
      "showHintWhenDetached", true,
      "cantAttach", true,
      "menu", function()
        D:AddLine(
          "text", L["Refresh"],
          "tooltipText", L["Refresh window"],
          "func", function() GuildRollAlts:Refresh() end
        )
      end      
    )
  end
  if not T:IsAttached("GuildRollAlts") then
    T:Open("GuildRollAlts")
  end
end

function GuildRollAlts:OnDisable()
  T:Close("GuildRollAlts")
end

function GuildRollAlts:Refresh()
  T:Refresh("GuildRollAlts")
end

function GuildRollAlts:setHideScript()
  local frame = GuildRoll:FindDetachedFrame("GuildRollAlts")
  if frame then
    GuildRoll:make_escable(frame:GetName(), "add")
    if frame.SetScript then
      frame:SetScript("OnHide", nil)
      frame:SetScript("OnHide", function(f)
          pcall(function()
            if T and T.IsAttached and not T:IsAttached("GuildRollAlts") then
              T:Attach("GuildRollAlts")
            end
            if f and f.SetScript then
              f:SetScript("OnHide", nil)
            end
          end)
        end)
    end
  end
end

function GuildRollAlts:Top()
  if T:IsRegistered("GuildRollAlts") and (T.registry.GuildRollAlts.tooltip) then
    T.registry.GuildRollAlts.tooltip.scroll=0
  end  
end

function GuildRollAlts:Toggle(forceShow)
  self:Top()
  if T:IsAttached("GuildRollAlts") then
    T:Detach("GuildRollAlts") -- show
    if (T:IsLocked("GuildRollAlts")) then
      T:ToggleLocked("GuildRollAlts")
    end
    self:setHideScript()
  else
    if (forceShow) then
      GuildRollAlts:Refresh()
    else
      T:Attach("GuildRollAlts") -- hide
    end
  end
end

function GuildRollAlts:OnClickItem(name)
  --ChatFrame_SendTell(name)
end

function GuildRollAlts:BuildAltsTable()
  return GuildRoll.alts
end

function GuildRollAlts:OnTooltipUpdate()
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

-- GLOBALS: GuildRoll_saychannel,GuildRoll_groupbyclass,GuildRoll_groupbyarmor,GuildRoll_groupbyrole,GuildRoll_raidonly,GuildRoll_decay,GuildRoll_minPE,GuildRoll_main,GuildRoll_progress,GuildRoll_discount,GuildRoll_log,GuildRoll_dbver,GuildRoll_looted
-- GLOBALS: GuildRoll,GuildRoll_prices,GuildRoll_standings,GuildRoll_bids,GuildRoll_loot,GuildRollAlts,GuildRoll_logs
