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
        T:SetTitle(L["Alts"])
        self:OnTooltipUpdate()
      end,
      "showTitleWhenDetached", true,
      "showHintWhenDetached", true,
      "cantAttach", true,
      "menu", function()
        GuildRoll:SafeDewdropAddLine(
          "text", L["Refresh"],
          "tooltipText", L["Refresh window"],
          "func", function() GuildRollAlts:Refresh() end
        )
        if GuildRoll:IsAdmin() then
          GuildRoll:SafeDewdropAddLine(
            "text", L["Consolidate EP"],
            "tooltipText", L["Move alt EP to their mains"],
            "func", function()
              StaticPopup_Show("GUILDROLL_CONSOLIDATE_EP")
            end
          )
        end
        GuildRoll:SafeDewdropAddLine(
          "text", L["Close window"],
          "tooltipText", L["Close this window"],
          "func", function()
            pcall(function() D:Close() end)
            local frame = GuildRoll:FindDetachedFrame("GuildRollAlts")
            if frame and frame.Hide then frame:Hide() end
          end
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
    -- Defensive: Ensure frame.owner is set to prevent Tablet-2.0 assert
    if not frame.owner then
      frame.owner = "GuildRollAlts"
    end
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
  if T:IsRegistered("GuildRollAlts") and type(T.registry) == "table" and T.registry.GuildRollAlts and T.registry.GuildRollAlts.tooltip then
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

function GuildRollAlts:BuildAltsTable()
  local mainData = {}  -- mainName -> { mainName, mainClass, alts = {} }
  local numMembers = GetNumGuildMembers(1)

  -- Build a lookup of name -> class for main class resolution
  local memberClass = {}
  for i = 1, numMembers do
    local name, _, _, _, class = GetGuildRosterInfo(i)
    if name then
      memberClass[name] = class
    end
  end

  -- Find alts and register them under their mains
  for i = 1, numMembers do
    local name, _, _, _, class, _, _, officernote = GetGuildRosterInfo(i)
    if name then
      local mainName, mainClass = GuildRoll:parseAlt(name, officernote)
      if mainName then
        if not mainData[mainName] then
          local mClass = mainClass or memberClass[mainName] or "WARRIOR"
          mainData[mainName] = { mainName = mainName, mainClass = mClass, alts = {} }
        end
        table.insert(mainData[mainName].alts, { name = name, class = class })
      end
    end
  end

  -- Convert to list (only mains that have at least one alt)
  local result = {}
  for _, entry in pairs(mainData) do
    table.insert(result, entry)
  end
  return result
end

function GuildRollAlts:OnTooltipUpdate()
  local cat = T:AddCategory(
      "columns", 2,
      "text",  C:Yellow(L["Main"]),   "child_textR",    1, "child_textG",    1, "child_textB",    1, "child_justify",  "LEFT",
      "text2", C:Yellow(L["Alts"]),  "child_text2R",   0, "child_text2G",   1, "child_text2B",   0, "child_justify2", "RIGHT"
    )
  local t = self:BuildAltsTable()
  for _, entry in ipairs(t) do
    local mainEP = GuildRoll:get_ep_v3(entry.mainName) or 0
    local coloredMain = C:Colorize(BC:GetHexColor(entry.mainClass), entry.mainName)
    local mainStr = string.format("%s (%d)", coloredMain, mainEP)

    local altstring = ""
    for _, alt in ipairs(entry.alts) do
      local altEP = GuildRoll:get_ep_v3(alt.name) or 0
      local coloredalt = C:Colorize(BC:GetHexColor(alt.class), alt.name)
      local altStr = string.format("%s (%d)", coloredalt, altEP)
      if altstring == "" then
        altstring = altStr
      else
        altstring = string.format("%s, %s", altstring, altStr)
      end
    end
    cat:AddLine(
      "text", mainStr,
      "text2", altstring
    )
  end
end

function GuildRollAlts:ConsolidateEP()
  if not GuildRoll:IsAdmin() then return end

  local altsTable = self:BuildAltsTable()
  local transfers = 0

  -- Build a single name -> {index, officernote} lookup to avoid repeated roster scans
  local rosterLookup = {}
  local numMembers = GetNumGuildMembers(1)
  for i = 1, numMembers do
    local name, _, _, _, _, _, _, officernote = GetGuildRosterInfo(i)
    if name then
      rosterLookup[name] = { index = i, officernote = officernote }
    end
  end

  for _, entry in ipairs(altsTable) do
    local mainName = entry.mainName
    for _, alt in ipairs(entry.alts) do
      local altName = alt.name
      local altEP = GuildRoll:get_ep_v3(altName) or 0
      if altEP > 0 then
        -- Read main EP fresh each iteration to handle multiple alts sequentially
        local mainEP = GuildRoll:get_ep_v3(mainName) or 0
        local newMainEP = mainEP + altEP

        local mainEntry = rosterLookup[mainName]
        local altEntry  = rosterLookup[altName]

        if mainEntry then
          GuildRoll:update_epgp_v3(newMainEP, mainEntry.index, mainName, mainEntry.officernote)
        end
        if altEntry then
          GuildRoll:update_epgp_v3(0, altEntry.index, altName, altEntry.officernote)
        end

        -- AdminLog
        pcall(function()
          GuildRoll:AdminLogAdd({
            action  = "CONSOLIDATE",
            actor   = UnitName("player"),
            target  = mainName,
            details = string.format("Consolidated EP from alt %s: %d -> %d (+%d)", altName, mainEP, newMainEP, altEP)
          })
        end)

        -- Personal log for main
        pcall(function()
          GuildRoll:personalLogAdd(mainName, string.format("EP consolidated from alt %s: +%d EP (Prev: %d, New: %d)", altName, altEP, mainEP, newMainEP))
        end)

        -- Personal log for alt
        pcall(function()
          GuildRoll:personalLogAdd(altName, string.format("EP transferred to main %s: -%d EP (Prev: %d, New: 0)", mainName, altEP, altEP))
        end)

        transfers = transfers + 1
      end
    end
  end

  if transfers > 0 then
    GuildRoll:defaultPrint(string.format("Consolidation complete. %d transfer(s) performed.", transfers))
  else
    GuildRoll:defaultPrint("Consolidation complete. No EP to transfer.")
  end

  GuildRollAlts:Refresh()
  GuildRoll:refreshAllEPUI()
end


-- GLOBALS: GuildRoll_saychannel,GuildRoll_groupbyclass,GuildRoll_groupbyarmor,GuildRoll_groupbyrole,GuildRoll_decay,GuildRoll_minPE,GuildRoll_main,GuildRoll_log,GuildRoll_dbver
-- GLOBALS: GuildRoll,GuildRoll_prices,GuildRoll_standings,GuildRoll_bids,GuildRoll_loot,GuildRollAlts,GuildRoll_logs
