local T = AceLibrary("Tablet-2.0")
local D = AceLibrary("Dewdrop-2.0")
local C = AceLibrary("Crayon-2.0")

local BC = AceLibrary("Babble-Class-2.2")
local L = AceLibrary("AceLocale-2.2"):new("guildroll")
local _G = getfenv(0)

GuildRoll_standings = GuildRoll:NewModule("GuildRoll_standings", "AceDB-2.0")
local groupings = {
  "GuildRoll_groupbyclass",
  "GuildRoll_groupbyarmor",
}
local PLATE, MAIL, LEATHER, CLOTH = 4,3,2,1
local DPS, CASTER, HEALER, TANK = 4,3,2,1
local class_to_armor = {
  PALADIN = PLATE,
  WARRIOR = PLATE,
  HUNTER = MAIL,
  SHAMAN = MAIL,
  DRUID = LEATHER,
  ROGUE = LEATHER,
  MAGE = CLOTH,
  PRIEST = CLOTH,
  WARLOCK = CLOTH,
}
local armor_text = {
  [CLOTH] = L["CLOTH"],
  [LEATHER] = L["LEATHER"],
  [MAIL] = L["MAIL"],
  [PLATE] = L["PLATE"],
}
local guildep_export = CreateFrame("Frame", "guildep_exportframe", UIParent)
guildep_export:SetWidth(250)
guildep_export:SetHeight(150)
guildep_export:SetPoint('TOP', UIParent, 'TOP', 0,-80)
guildep_export:SetFrameStrata('DIALOG')
guildep_export:Hide()
guildep_export:SetBackdrop({
  bgFile = [[Interface\Tooltips\UI-Tooltip-Background]],
  edgeFile = [[Interface\Tooltips\UI-Tooltip-Border]],
  tile = true,
  tileSize = 16,
  edgeSize = 16,
  insets = {left = 5, right = 5, top = 5, bottom = 5}
  })
guildep_export:SetBackdropBorderColor(TOOLTIP_DEFAULT_COLOR.r, TOOLTIP_DEFAULT_COLOR.g, TOOLTIP_DEFAULT_COLOR.b)
guildep_export:SetBackdropColor(TOOLTIP_DEFAULT_BACKGROUND_COLOR.r, TOOLTIP_DEFAULT_BACKGROUND_COLOR.g, TOOLTIP_DEFAULT_BACKGROUND_COLOR.b)
guildep_export.action = CreateFrame("Button","guildep_exportaction", guildep_export, "UIPanelButtonTemplate")
guildep_export.action:SetWidth(100)
guildep_export.action:SetHeight(22)
guildep_export.action:SetPoint("BOTTOM",0,-20)
guildep_export.action:SetText("Import")
guildep_export.action:Hide()
guildep_export.action:SetScript("OnClick",function() GuildRoll_standings.import() end)
guildep_export.title = guildep_export:CreateFontString(nil,"OVERLAY")
guildep_export.title:SetPoint("TOP",0,-5)
guildep_export.title:SetFont("Fonts\\ARIALN.TTF", 12)
guildep_export.title:SetWidth(200)
guildep_export.title:SetJustifyH("LEFT")
guildep_export.title:SetJustifyV("CENTER")
guildep_export.title:SetShadowOffset(1, -1)
guildep_export.edit = CreateFrame("EditBox", "guildep_exportedit", guildep_export)
guildep_export.edit:SetMultiLine(true)
guildep_export.edit:SetAutoFocus(true)
guildep_export.edit:EnableMouse(true)
guildep_export.edit:SetMaxLetters(0)
guildep_export.edit:SetHistoryLines(1)
guildep_export.edit:SetFont('Fonts\\ARIALN.ttf', 12, 'THINOUTLINE')
guildep_export.edit:SetWidth(290)
guildep_export.edit:SetHeight(190)
guildep_export.edit:SetScript("OnEscapePressed", function() 
    guildep_export.edit:SetText("")
    guildep_export:Hide() 
  end)
guildep_export.edit:SetScript("OnEditFocusGained", function()
  guildep_export.edit:HighlightText()
end)
guildep_export.edit:SetScript("OnCursorChanged", function() 
  guildep_export.edit:HighlightText()
end)
guildep_export.AddSelectText = function(txt)
  guildep_export.edit:SetText(txt)
  guildep_export.edit:HighlightText()
end
guildep_export.scroll = CreateFrame("ScrollFrame", "guildep_exportscroll", guildep_export, 'UIPanelScrollFrameTemplate')
guildep_export.scroll:SetPoint('TOPLEFT', guildep_export, 'TOPLEFT', 8, -30)
guildep_export.scroll:SetPoint('BOTTOMRIGHT', guildep_export, 'BOTTOMRIGHT', -30, 8)
guildep_export.scroll:SetScrollChild(guildep_export.edit)
GuildRoll:make_escable("guildep_exportframe","add")

function GuildRoll_standings:Export()
  -- Evita dipendere dalla funzione globale admin(); usa direttamente l'API
  if not (CanEditOfficerNote and CanEditOfficerNote()) then return end
  guildep_export.action:Hide()
  guildep_export.title:SetText(C:Gold(L["Ctrl-C to copy. Esc to close."]))
  local t = {}
  for i = 1, GetNumGuildMembers(1) do
    local name, _, _, _, class, _, note, officernote, _, _ = GetGuildRosterInfo(i)
    local ep = (GuildRoll:get_ep_v3(name,officernote) or 0) 
    if ep > 0 then
      table.insert(t,{name,ep})
    end
  end 
  table.sort(t, function(a,b)
      return tonumber(a[2]) > tonumber(b[2])
    end)
  guildep_export:Show()
  local txt = "Name;EP\n"
  for i,val in ipairs(t) do
    txt = string.format("%s%s;%d\n",txt,val[1],val[2])
  end
  guildep_export.AddSelectText(txt)
end

function GuildRoll_standings:Import()
  -- Import richiede essere leader della gilda
  if not IsGuildLeader() then return end
  guildep_export.action:Show()
  guildep_export.title:SetText(C:Red("Ctrl-V to paste data. Esc to close."))
  guildep_export.AddSelectText(L.IMPORT_WARNING)
  guildep_export:Show()
end

function GuildRoll_standings.import()
  if not IsGuildLeader() then return end
  local text = guildep_export.edit:GetText()
  local t = {}
  local found
  for line in string.gfind(text,"[^\r\n]+") do
    local name,ep,gp,pr = GuildRoll:strsplit(";",line)
    ep,gp = tonumber(ep),tonumber(gp)--,tonumber(pr)
    if (name) and (ep) and (gp) and (pr) then
      t[name]={ep,gp}
      found = true
    end
  end
  if (found) then
    local count = 0
    guildep_export.edit:SetText("")
    for i=1,GetNumGuildMembers(1) do
      local name, _, _, _, class, _, note, officernote, _, _ = GetGuildRosterInfo(i)
      local name_epgp = t[name]
      if (name_epgp) then
        count = count + 1
        --GuildRoll:debugPrint(string.format("%s {%s:%s}",name,name_epgp[1],name_epgp[2])) -- Debug
        GuildRoll:update_epgp_v3(name_epgp[1],name_epgp[2],i,name,officernote)
        t[name]=nil
      end
    end
    GuildRoll:defaultPrint(string.format(L["Imported %d members."],count))
    local report = string.format(L["Imported %d members.\n"],count)
    report = string.format(L["%s\nFailed to import:"],report)
    for name,epgp in pairs(t) do
      report = string.format("%s%s {%s:%s}\n",report,name,t[1],t[2])
    end
    guildep_export.AddSelectText(report)
  end
end

local class_cache = setmetatable({},{__index = function(t,k)
  local class
  if BC:HasReverseTranslation(k) then
    class = string.upper(BC:GetReverseTranslation(k))
  else
    class = string.upper(k)
  end
  if (class) then
    rawset(t,k,class)
    return class
  end
  return k
end})
function GuildRoll_standings:getArmorClass(class)
  class = class_cache[class]
  return class_to_armor[class] or 0
end

function GuildRoll_standings:OnEnable()
  if not T:IsRegistered("GuildRoll_standings") then
    T:Register("GuildRoll_standings",
      "children", function()
        T:SetTitle(L["Standings"])
        self:OnTooltipUpdate()
      end,
       	"showTitleWhenDetached", true,
       	"showHintWhenDetached", true,
       	"cantAttach", true,
       	"menu", function()
        D:AddLine(
          "text", L["Raid Only"],
          "tooltipText", L["Only show members in raid."],
          "checked", GuildRoll_raidonly,
          "func", function() GuildRoll_standings:ToggleRaidOnly() end
        )      
        D:AddLine(
          "text", L["Group by class"],
          "tooltipText", L["Group members by class."],
          "checked", GuildRoll_groupbyclass,
          "func", function() GuildRoll_standings:ToggleGroupBy("GuildRoll_groupbyclass") end
        )
        D:AddLine(
          "text", L["Group by armor"],
          "tooltipText", L["Group members by armor."],
          "checked", GuildRoll_groupbyarmor,
          "func", function() GuildRoll_standings:ToggleGroupBy("GuildRoll_groupbyarmor") end
        )
        D:AddLine(
          "text", L["Refresh"],
          "tooltipText", L["Refresh window"],
          "func", function() GuildRoll_standings:Refresh() end
        )
        -- Usa direttamente CanEditOfficerNote invece della globale admin() per robustezza
        if (CanEditOfficerNote and CanEditOfficerNote()) then
          D:AddLine(
            "text", L["Export"],
            "tooltipText", L["Export standings to csv."],
            "func", function() GuildRoll_standings:Export() end
          )
        end
        if IsGuildLeader() then
          D:AddLine(
          "text", L["Import"],
          "tooltipText", L["Import standings from csv."],
          "func", function() GuildRoll_standings:Import() end
        )
        end
       	end
    )
  end
  if not T:IsAttached("GuildRoll_standings") then
    T:Open("GuildRoll_standings")
  end
end

function GuildRoll_standings:OnDisable()
  T:Close("GuildRoll_standings")
end

function GuildRoll_standings:Refresh()
  T:Refresh("GuildRoll_standings")
end

function GuildRoll_standings:setHideScript()
  local frame = GuildRoll:FindDetachedFrame("GuildRoll_standings")
  if frame then
    GuildRoll:make_escable(frame:GetName(), "add")
    if frame.SetScript then
      frame:SetScript("OnHide", nil)
      frame:SetScript("OnHide", function(f)
          pcall(function()
            if T and T.IsAttached and not T:IsAttached("GuildRoll_standings") then
              T:Attach("GuildRoll_standings")
            end
            if f and f.SetScript then
              f:SetScript("OnHide", nil)
            end
          end)
        end)
    end
  end
end

function GuildRoll_standings:Top()
  if T:IsRegistered("GuildRoll_standings") and (T.registry.GuildRoll_standings.tooltip) then
    T.registry.GuildRoll_standings.tooltip.scroll=0
  end  
end

function GuildRoll_standings:Toggle(forceShow)
  self:Top()
  if T:IsAttached("GuildRoll_standings") then -- hidden
    T:Detach("GuildRoll_standings") -- show
    if (T:IsLocked("GuildRoll_standings")) then
      T:ToggleLocked("GuildRoll_standings")
    end
    self:setHideScript()
  else
    if (forceShow) then
      GuildRoll_standings:Refresh()
    else
      T:Attach("GuildRoll_standings") -- hide
    end
  end  
end

function GuildRoll_standings:ToggleGroupBy(setting)
  for _,value in ipairs(groupings) do
    if value ~= setting then
      _G[value] = false
    end
  end
  _G[setting] = not _G[setting]
  self:Top()
  self:Refresh()
end

function GuildRoll_standings:ToggleRaidOnly()
  GuildRoll_raidonly = not GuildRoll_raidonly
  self:Top()
  GuildRoll:SetRefresh(true)
end

local pr_sorter_standings = function(a,b)
    if a[6] ~= b[6] then
      return tonumber(a[6]) > tonumber(b[6])
    else
      return tonumber(a[4]) > tonumber(b[4])
    end
end
-- Builds a standings table with record:
-- name, class, armor_class, roles, EP, GP, PR
-- and sorted by PR
function GuildRoll_standings:BuildStandingsTable()
  local t = { }
  local r = { }
  if (GuildRoll_raidonly) and GetNumRaidMembers() > 0 then
    for i = 1, GetNumRaidMembers(true) do
      local name, rank, subgroup, level, class, fileName, zone, online, isDead = GetRaidRosterInfo(i) 
      r[name] = true
    end
  end
  GuildRoll.alts = {}
  for i = 1, GetNumGuildMembers(1) do
    local name, _, _, _, class, _, note, officernote, _, _ = GetGuildRosterInfo(i)
    local ep = (GuildRoll:get_ep_v3(name,officernote) or 0) 
    local gp = (GuildRoll:get_gp_v3(name,officernote) or GuildRoll.VARS.baseAE)
    local main, main_class, main_rank = GuildRoll:parseAlt(name,officernote)
    
    -- NoPugs: Removed getPugName call - displayName is just name
    local displayName = name

    if (main) then
      if ((GuildRoll._playerName) and (name == GuildRoll._playerName)) then
        if (not GuildRoll_main) or (GuildRoll_main and GuildRoll_main ~= main) then
          GuildRoll_main = main
          GuildRoll:defaultPrint(L["Your main has been set to %s"],GuildRoll_main)
        end
      end
      main = C:Colorize(BC:GetHexColor(main_class), main)
      GuildRoll.alts[main] = GuildRoll.alts[main] or {}
      GuildRoll.alts[main][name] = class
    end
    local armor_class = self:getArmorClass(class)
    if ep > 0 then
      if (GuildRoll_raidonly) and next(r) then
        if r[name] then
          table.insert(t,{displayName,class,armor_class,ep,gp,(ep+ math.min(GuildRoll.VARS.AERollCap,gp)),name})
        end
      else
        table.insert(t,{displayName,class,armor_class,ep,gp,(ep+ math.min(GuildRoll.VARS.AERollCap,gp)),name})
      end
    end
  end
  if (GuildRoll_groupbyclass) then
    table.sort(t, function(a,b)
      if (a[2] ~= b[2]) then return a[2] > b[2]
      else return pr_sorter_standings(a,b) end
    end)
  elseif (GuildRoll_groupbyarmor) then
    table.sort(t, function(a,b)
      if (a[3] ~= b[3]) then return a[3] > b[3]
      else return pr_sorter_standings(a,b) end
    end)
  else
    table.sort(t, pr_sorter_standings)
  end
  return t
end


function GuildRoll_standings:OnTooltipUpdate()
  -- Create category with 2 columns: Name | EP
  local cat = T:AddCategory(
      "columns", 2,
      "text",  C:Orange(L["Name"]),   "child_textR",    1, "child_textG",    1, "child_textB",    1, "LEFT",  "LEFT",
      "text2", C:Orange(L["Main Standing"]),     "child_text2R",   1, "child_text2G",   1, "child_text2B",   1, "RIGHT", "RIGHT"
    )
  local t = self:BuildStandingsTable()
  local separator
  for i = 1, table.getn(t) do
    local displayName, class, armor_class, ep, gp, pr, originalName = unpack(t[i])
    if (GuildRoll_groupbyarmor) then
      if not (separator) then
        separator = armor_text[armor_class]
        if (separator) then
          cat:AddLine(
            "text", C:Green(separator),
            "text2", ""
          )
        end
      else
        local last_separator = separator
        separator = armor_text[armor_class]
        if (separator) and (separator ~= last_separator) then
          cat:AddLine(
            "text", C:Green(separator),
            "text2", ""
          )          
        end
      end
    end

    local text = C:Colorize(BC:GetHexColor(class), displayName)
    local text2
    if GuildRoll_minPE > 0 and ep < GuildRoll_minPE then
      text2 = C:Red(string.format("%.4g", ep))
    else
      text2 = string.format("%.4g", ep)
    end

    if ((GuildRoll._playerName) and GuildRoll._playerName == originalName) or ((GuildRoll_main) and GuildRoll_main == originalName) then
      text = string.format("(*)%s",text)
    end
    cat:AddLine(
      "text", text,
      "text2", text2
    )
  end
end

-- GLOBALS: GuildRoll_saychannel,GuildRoll_groupbyclass,GuildRoll_groupbyarmor,GuildRoll_raidonly,GuildRoll_decay,GuildRoll_minPE,GuildRoll_main,GuildRoll_progress,RetR[...]
-- GLOBALS: GuildRoll,GuildRoll_prices,GuildRoll_standings,GuildRoll_bids,GuildRoll_loot,GuildRollAlts,GuildRoll_logs
