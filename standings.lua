-- FILE CONTENT START --
local T = AceLibrary("Tablet-2.0")
local D = AceLibrary("Dewdrop-2.0")
local C = AceLibrary("Crayon-2.0")

local BC = AceLibrary("Babble-Class-2.2")
local L = AceLibrary("AceLocale-2.2"):new("retroll")
local _G = getfenv(0)

RetRoll_standings = RetRoll:NewModule("RetRoll_standings", "AceDB-2.0")
local groupings = {
  "RetRoll_groupbyclass",
  "RetRoll_groupbyarmor",
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
local shooty_export = CreateFrame("Frame", "shooty_exportframe", UIParent)
shooty_export:SetWidth(250)
shooty_export:SetHeight(150)
shooty_export:SetPoint('TOP', UIParent, 'TOP', 0,-80)
shooty_export:SetFrameStrata('DIALOG')
shooty_export:Hide()
shooty_export:SetBackdrop({
  bgFile = [[Interface\Tooltips\UI-Tooltip-Background]],
  edgeFile = [[Interface\Tooltips\UI-Tooltip-Border]],
  tile = true,
  tileSize = 16,
  edgeSize = 16,
  insets = {left = 5, right = 5, top = 5, bottom = 5}
  })
shooty_export:SetBackdropBorderColor(TOOLTIP_DEFAULT_COLOR.r, TOOLTIP_DEFAULT_COLOR.g, TOOLTIP_DEFAULT_COLOR.b)
shooty_export:SetBackdropColor(TOOLTIP_DEFAULT_BACKGROUND_COLOR.r, TOOLTIP_DEFAULT_BACKGROUND_COLOR.g, TOOLTIP_DEFAULT_BACKGROUND_COLOR.b)
shooty_export.action = CreateFrame("Button","shooty_exportaction", shooty_export, "UIPanelButtonTemplate")
shooty_export.action:SetWidth(100)
shooty_export.action:SetHeight(22)
shooty_export.action:SetPoint("BOTTOM",0,-20)
shooty_export.action:SetText("Import")
shooty_export.action:Hide()
shooty_export.action:SetScript("OnClick",function() RetRoll_standings.import() end)
shooty_export.title = shooty_export:CreateFontString(nil,"OVERLAY")
shooty_export.title:SetPoint("TOP",0,-5)
shooty_export.title:SetFont("Fonts\\ARIALN.TTF", 12)
shooty_export.title:SetWidth(200)
shooty_export.title:SetJustifyH("LEFT")
shooty_export.title:SetJustifyV("CENTER")
shooty_export.title:SetShadowOffset(1, -1)
shooty_export.edit = CreateFrame("EditBox", "shooty_exportedit", shooty_export)
shooty_export.edit:SetMultiLine(true)
shooty_export.edit:SetAutoFocus(true)
shooty_export.edit:EnableMouse(true)
shooty_export.edit:SetMaxLetters(0)
shooty_export.edit:SetHistoryLines(1)
shooty_export.edit:SetFont('Fonts\\ARIALN.ttf', 12, 'THINOUTLINE')
shooty_export.edit:SetWidth(290)
shooty_export.edit:SetHeight(190)
shooty_export.edit:SetScript("OnEscapePressed", function() 
    shooty_export.edit:SetText("")
    shooty_export:Hide() 
  end)
shooty_export.edit:SetScript("OnEditFocusGained", function()
  shooty_export.edit:HighlightText()
end)
shooty_export.edit:SetScript("OnCursorChanged", function() 
  shooty_export.edit:HighlightText()
end)
shooty_export.AddSelectText = function(txt)
  shooty_export.edit:SetText(txt)
  shooty_export.edit:HighlightText()
end
shooty_export.scroll = CreateFrame("ScrollFrame", "shooty_exportscroll", shooty_export, 'UIPanelScrollFrameTemplate')
shooty_export.scroll:SetPoint('TOPLEFT', shooty_export, 'TOPLEFT', 8, -30)
shooty_export.scroll:SetPoint('BOTTOMRIGHT', shooty_export, 'BOTTOMRIGHT', -30, 8)
shooty_export.scroll:SetScrollChild(shooty_export.edit)
RetRoll:make_escable("shooty_exportframe","add")

function RetRoll_standings:Export()
  shooty_export.action:Hide()
  shooty_export.title:SetText(C:Gold(L["Ctrl-C to copy. Esc to close."]))
  local t = {}
  for i = 1, GetNumGuildMembers(1) do
    local name, _, _, _, class, _, note, officernote, _, _ = GetGuildRosterInfo(i)
    local ep = (RetRoll:get_ep_v3(name,officernote) or 0) 
    local gp = (RetRoll:get_gp_v3(name,officernote) or RetRoll.VARS.baseAE) 
    if ep > 0 then
      table.insert(t,{name,ep,gp,ep+math.min(50,gp)})
    end
  end 
  table.sort(t, function(a,b)
      return tonumber(a[4]) > tonumber(b[4])
    end)
  shooty_export:Show()
  local txt = "Name;EP;GP;PR\n"
  for i,val in ipairs(t) do
    txt = string.format("%s%s;%d;%d;%d\n",txt,val[1],val[2],val[3],val[4])
  end
  shooty_export.AddSelectText(txt)
end

function RetRoll_standings:Import()
  if not IsGuildLeader() then return end
  shooty_export.action:Show()
  shooty_export.title:SetText(C:Red("Ctrl-V to paste data. Esc to close."))
  shooty_export.AddSelectText(L.IMPORT_WARNING)
  shooty_export:Show()
end

function RetRoll_standings.import()
  if not IsGuildLeader() then return end
  local text = shooty_export.edit:GetText()
  local t = {}
  local found
  for line in string.gfind(text,"[^\r\n]+") do
    local name,ep,gp,pr = RetRoll:strsplit(";",line)
    ep,gp = tonumber(ep),tonumber(gp)--,tonumber(pr)
    if (name) and (ep) and (gp) and (pr) then
      t[name]={ep,gp}
      found = true
    end
  end
  if (found) then
    local count = 0
    shooty_export.edit:SetText("")
    for i=1,GetNumGuildMembers(1) do
      local name, _, _, _, class, _, note, officernote, _, _ = GetGuildRosterInfo(i)
      local name_epgp = t[name]
      if (name_epgp) then
        count = count + 1
        --RetRoll:debugPrint(string.format("%s {%s:%s}",name,name_epgp[1],name_epgp[2])) -- Debug
        RetRoll:update_epgp_v3(name_epgp[1],name_epgp[2],i,name,officernote)
        t[name]=nil
      end
    end
    RetRoll:defaultPrint(string.format(L["Imported %d members."],count))
    local report = string.format(L["Imported %d members.\n"],count)
    report = string.format(L["%s\nFailed to import:"],report)
    for name,epgp in pairs(t) do
      report = string.format("%s%s {%s:%s}\n",report,name,t[1],t[2])
    end
    shooty_export.AddSelectText(report)
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
function RetRoll_standings:getArmorClass(class)
  class = class_cache[class]
  return class_to_armor[class] or 0
end

function RetRoll_standings:OnEnable()
  if not T:IsRegistered("RetRoll_standings") then
    T:Register("RetRoll_standings",
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
          "checked", RetRoll_raidonly,
          "func", function() RetRoll_standings:ToggleRaidOnly() end
        )      
        D:AddLine(
          "text", L["Group by class"],
          "tooltipText", L["Group members by class."],
          "checked", RetRoll_groupbyclass,
          "func", function() RetRoll_standings:ToggleGroupBy("RetRoll_groupbyclass") end
        )
        D:AddLine(
          "text", L["Group by armor"],
          "tooltipText", L["Group members by armor."],
          "checked", RetRoll_groupbyarmor,
          "func", function() RetRoll_standings:ToggleGroupBy("RetRoll_groupbyarmor") end
        )
        D:AddLine(
          "text", L["Refresh"],
          "tooltipText", L["Refresh window"],
          "func", function() RetRoll_standings:Refresh() end
        )
        D:AddLine(
          "text", L["Export"],
          "tooltipText", L["Export standings to csv."],
          "func", function() RetRoll_standings:Export() end
        )
        if IsGuildLeader() then
          D:AddLine(
          "text", L["Import"],
          "tooltipText", L["Import standings from csv."],
          "func", function() RetRoll_standings:Import() end
        )
        end
       	end
    )
  end
  if not T:IsAttached("RetRoll_standings") then
    T:Open("RetRoll_standings")
  end
end

function RetRoll_standings:OnDisable()
  T:Close("RetRoll_standings")
end

function RetRoll_standings:Refresh()
  T:Refresh("RetRoll_standings")
end

function RetRoll_standings:setHideScript()
  local i = 1
  local tablet = getglobal(string.format("Tablet20DetachedFrame%d",i))
  while (tablet) and i<100 do
    if tablet.owner ~= nil and tablet.owner == "RetRoll_standings" then
      RetRoll:make_escable(string.format("Tablet20DetachedFrame%d",i),"add")
      tablet:SetScript("OnHide",nil)
      tablet:SetScript("OnHide",function()
          if not T:IsAttached("RetRoll_standings") then
            T:Attach("RetRoll_standings")
            this:SetScript("OnHide",nil)
          end
        end)
      break
    end    
    i = i+1
    tablet = getglobal(string.format("Tablet20DetachedFrame%d",i))
  end  
end

function RetRoll_standings:Top()
  if T:IsRegistered("RetRoll_standings") and (T.registry.RetRoll_standings.tooltip) then
    T.registry.RetRoll_standings.tooltip.scroll=0
  end  
end

function RetRoll_standings:Toggle(forceShow)
  self:Top()
  if T:IsAttached("RetRoll_standings") then -- hidden
    T:Detach("RetRoll_standings") -- show
    if (T:IsLocked("RetRoll_standings")) then
      T:ToggleLocked("RetRoll_standings")
    end
    self:setHideScript()
  else
    if (forceShow) then
      RetRoll_standings:Refresh()
    else
      T:Attach("RetRoll_standings") -- hide
    end
  end  
end

function RetRoll_standings:ToggleGroupBy(setting)
  for _,value in ipairs(groupings) do
    if value ~= setting then
      _G[value] = false
    end
  end
  _G[setting] = not _G[setting]
  self:Top()
  self:Refresh()
end

function RetRoll_standings:ToggleRaidOnly()
  RetRoll_raidonly = not RetRoll_raidonly
  self:Top()
  RetRoll:SetRefresh(true)
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
function RetRoll_standings:BuildStandingsTable()
  local t = { }
  local r = { }
  if (RetRoll_raidonly) and GetNumRaidMembers() > 0 then
    for i = 1, GetNumRaidMembers(true) do
      local name, rank, subgroup, level, class, fileName, zone, online, isDead = GetRaidRosterInfo(i) 
      r[name] = true
    end
  end
  RetRoll.alts = {}
  for i = 1, GetNumGuildMembers(1) do
    local name, _, _, _, class, _, note, officernote, _, _ = GetGuildRosterInfo(i)
    local ep = (RetRoll:get_ep_v3(name,officernote) or 0) 
    local gp = (RetRoll:get_gp_v3(name,officernote) or RetRoll.VARS.baseAE)
    local main, main_class, main_rank = RetRoll:parseAlt(name,officernote)
    
    -- Check if the player is a pug
    local pugName = RetRoll:getPugName(name)
    local displayName = pugName and string.format("%s (%s)", pugName, name) or name

    if (main) then
      if ((RetRoll._playerName) and (name == RetRoll._playerName)) then
        if (not RetRoll_main) or (RetRoll_main and RetRoll_main ~= main) then
          RetRoll_main = main
          RetRoll:defaultPrint(L["Your main has been set to %s"],RetRoll_main)
        end
      end
      main = C:Colorize(BC:GetHexColor(main_class), main)
      RetRoll.alts[main] = RetRoll.alts[main] or {}
      RetRoll.alts[main][name] = class
    end
    local armor_class = self:getArmorClass(class)
    if ep > 0 then
      if (RetRoll_raidonly) and next(r) then
        if r[name] then
          table.insert(t,{displayName,class,armor_class,ep,gp,(ep+ math.min(RetRoll.VARS.AERollCap,gp)),name})
        end
      else
        table.insert(t,{displayName,class,armor_class,ep,gp,(ep+ math.min(RetRoll.VARS.AERollCap,gp)),name})
      end
    end
  end
  if (RetRoll_groupbyclass) then
    table.sort(t, function(a,b)
      if (a[2] ~= b[2]) then return a[2] > b[2]
      else return pr_sorter_standings(a,b) end
    end)
  elseif (RetRoll_groupbyarmor) then
    table.sort(t, function(a,b)
      if (a[3] ~= b[3]) then return a[3] > b[3]
      else return pr_sorter_standings(a,b) end
    end)
  else
    table.sort(t, pr_sorter_standings)
  end
  return t
end


function RetRoll_standings:OnTooltipUpdate()
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
    if (RetRoll_groupbyarmor) then
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
    if RetRoll_minPE > 0 and ep < RetRoll_minPE then
      text2 = C:Red(string.format("%.4g", ep))
    else
      text2 = string.format("%.4g", ep)
    end

    if ((RetRoll._playerName) and RetRoll._playerName == originalName) or ((RetRoll_main) and RetRoll_main == originalName) then
      text = string.format("(*)%s",text)
    end
    cat:AddLine(
      "text", text,
      "text2", text2
    )
  end
end

-- GLOBALS: RetRoll_saychannel,RetRoll_groupbyclass,RetRoll_groupbyarmor,RetRoll_raidonly,RetRoll_decay,RetRoll_minPE,RetRoll_reservechannel,RetRoll_main,RetRoll_progress,RetR[...]
-- GLOBALS: RetRoll,RetRoll_prices,RetRoll_standings,RetRoll_bids,RetRoll_loot,RetRoll_reserves,RetRollAlts,RetRoll_logs

-- FILE CONTENT END --
