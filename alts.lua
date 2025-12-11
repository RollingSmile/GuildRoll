-- Guard: Check if required libraries are available before proceeding
-- This prevents runtime errors if Ace/Tablet/Dewdrop/Crayon are not loaded
local T, D, C, BC, L
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
  
  ok, result = pcall(function() return AceLibrary("Babble-Class-2.2") end)
  if not ok or not result then return end
  BC = result
  
  ok, result = pcall(function() return AceLibrary("AceLocale-2.2") end)
  if not ok or not result or type(result.new) ~= "function" then return end
  ok, L = pcall(function() return result:new("guildroll") end)
  if not ok or not L then return end
end

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
    
    -- Ensure tooltip has a valid owner to prevent "Detached tooltip has no owner" error
    -- This is required for Tablet-2.0 compatibility when detaching tooltips
    pcall(function()
      if T and T.registry and T.registry.GuildRollAlts and T.registry.GuildRollAlts.tooltip then
        if not T.registry.GuildRollAlts.tooltip.owner then
          T.registry.GuildRollAlts.tooltip.owner = GuildRoll:EnsureTabletOwner()
        end
      end
    end)
  end
  if not T:IsAttached("GuildRollAlts") then
    pcall(function() T:Open("GuildRollAlts") end)
  end
end

function GuildRollAlts:OnDisable()
  pcall(function() T:Close("GuildRollAlts") end)
end

function GuildRollAlts:Refresh()
  pcall(function() T:Refresh("GuildRollAlts") end)
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
    pcall(function() T:Detach("GuildRollAlts") end) -- show
    if (T.IsLocked and T:IsLocked("GuildRollAlts")) then
      pcall(function() T:ToggleLocked("GuildRollAlts") end)
    end
    self:setHideScript()
  else
    if (forceShow) then
      GuildRollAlts:Refresh()
    else
      pcall(function() T:Attach("GuildRollAlts") end) -- hide
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
