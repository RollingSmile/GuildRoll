-- Guard: Check if required libraries are available before proceeding
local T, D, C, L
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
  
  ok, result = pcall(function() return AceLibrary("AceLocale-2.2") end)
  if not ok or not result or type(result.new) ~= "function" then return end
  ok, L = pcall(function() return result:new("guildroll") end)
  if not ok or not L then return end
end

GuildRoll_BuffCheck = GuildRoll:NewModule("GuildRoll_BuffCheck", "AceDB-2.0")

-- Buff definitions by provider class
local BUFF_REQUIREMENTS = {
  PRIEST = {
    "Power Word: Fortitude",
    "Prayer of Fortitude",
    "Divine Spirit",
    "Prayer of Spirit",
    "Shadow Protection",
  },
  MAGE = {
    "Arcane Intellect",
    "Arcane Brilliance",
  },
  DRUID = {
    "Mark of the Wild",
    "Gift of the Wild",
  },
  WARRIOR = {
    "Battle Shout",
  },
  PALADIN = {
    -- Special handling: count number of paladins and require min(N, #blessing_types) distinct blessings
    "Blessing of Might",
    "Blessing of Wisdom",
    "Blessing of Kings",
    "Blessing of Light",
    "Blessing of Salvation",
  },
}

-- Consumables by class (min = 4)
local CONSUMABLES = {
  WARRIOR = {
    "Elixir of the Mongoose",
    "Elixir of Giants",
    "Winterfall Firewater",
    "Juju Power",
    "Juju Might",
    "Smoked Desert Dumplings",
    "Blessed Sunfruit Juice",
    "Greater Stoneshield Potion",
  },
  ROGUE = {
    "Elixir of the Mongoose",
    "Elixir of Greater Agility",
    "Winterfall Firewater",
    "Juju Power",
    "Juju Might",
    "Blessed Sunfruit Juice",
    "Smoked Desert Dumplings",
  },
  HUNTER = {
    "Elixir of the Mongoose",
    "Elixir of Greater Agility",
    "Winterfall Firewater",
    "Juju Power",
    "Blessed Sunfruit Juice",
    "Smoked Desert Dumplings",
  },
  MAGE = {
    "Elixir of Greater Firepower",
    "Elixir of Shadow Power",
    "Arcane Elixir",
    "Greater Arcane Elixir",
    "Elixir of Frost Power",
    "Cerebral Cortex Compound",
    "Runn Tum Tuber Surprise",
  },
  WARLOCK = {
    "Elixir of Greater Firepower",
    "Elixir of Shadow Power",
    "Arcane Elixir",
    "Greater Arcane Elixir",
    "Cerebral Cortex Compound",
    "Runn Tum Tuber Surprise",
  },
  PRIEST = {
    "Elixir of Greater Firepower",
    "Elixir of Shadow Power",
    "Arcane Elixir",
    "Greater Arcane Elixir",
    "Cerebral Cortex Compound",
    "Runn Tum Tuber Surprise",
  },
  DRUID = {
    "Elixir of Greater Firepower",
    "Elixir of Shadow Power",
    "Arcane Elixir",
    "Greater Arcane Elixir",
    "Cerebral Cortex Compound",
    "Runn Tum Tuber Surprise",
    "Elixir of the Mongoose",
    "Elixir of Greater Agility",
  },
  PALADIN = {
    "Elixir of Giants",
    "Elixir of the Mongoose",
    "Winterfall Firewater",
    "Juju Power",
    "Juju Might",
    "Blessed Sunfruit Juice",
    "Smoked Desert Dumplings",
    "Greater Stoneshield Potion",
  },
}

-- Common flasks (min = 1)
local FLASKS = {
  "Flask of Distilled Wisdom",
  "Flask of Supreme Power",
  "Flask of the Titans",
}

-- StaticPopup dialogs (defined once at module initialization)
StaticPopupDialogs["GUILDROLL_CONSUMES_AWARD_EP"] = {
  text = "",  -- Will be set dynamically via L[] lookup
  button1 = TEXT(OKAY),
  button2 = TEXT(CANCEL),
  OnAccept = function()
    -- User must manually award EP - this just confirms readiness
    GuildRoll:defaultPrint(L["ConsumesCheck_ReadyToAward"] or "All members ready. Use +EP to Raid to award points.")
  end,
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 1,
}

StaticPopupDialogs["GUILDROLL_FLASKS_AWARD_EP"] = {
  text = "",  -- Will be set dynamically via L[] lookup
  button1 = TEXT(OKAY),
  button2 = TEXT(CANCEL),
  OnAccept = function()
    -- User must manually award EP - this just confirms readiness
    GuildRoll:defaultPrint(L["FlasksCheck_ReadyToAward"] or "All members ready. Use +EP to Raid to award points.")
  end,
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 1,
}

-- Helper: substring match for buff names (case-insensitive)
local function MatchBuff(buffName, pattern)
  if not buffName or not pattern then return false end
  return string.find(string.lower(buffName), string.lower(pattern), 1, true) ~= nil
end

-- Helper: Get buff name from texture using tooltip scan
local function GetBuffName(unit, buffIndex)
  if not unit or not buffIndex then return nil end
  
  -- Create a hidden tooltip for scanning
  if not GuildRoll_BuffCheck._scanTooltip then
    GuildRoll_BuffCheck._scanTooltip = CreateFrame("GameTooltip", "GuildRollBuffCheckTooltip", UIParent, "GameTooltipTemplate")
    GuildRoll_BuffCheck._scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
  end
  
  local tooltip = GuildRoll_BuffCheck._scanTooltip
  tooltip:ClearLines()
  tooltip:SetUnitBuff(unit, buffIndex)
  
  local tooltipText = getglobal("GuildRollBuffCheckTooltipTextLeft1")
  if tooltipText then
    return tooltipText:GetText()
  end
  return nil
end

-- Helper: Check if player has any buff from a list using tooltip scan
local function HasAnyBuffByName(unit, buffList)
  for i = 1, 32 do
    local buffTexture = UnitBuff(unit, i)
    if not buffTexture then break end
    
    local buffName = GetBuffName(unit, i)
    if buffName then
      for _, pattern in ipairs(buffList) do
        if MatchBuff(buffName, pattern) then
          return true, pattern
        end
      end
    end
  end
  return false
end

-- Helper: Count distinct paladin blessings on a unit
local function CountPaladinBlessings(unit)
  local blessings = {}
  local blessingTypes = {
    ["Might"] = true,
    ["Wisdom"] = true,
    ["Kings"] = true,
    ["Light"] = true,
    ["Salvation"] = true,
  }
  
  for i = 1, 32 do
    local buffTexture = UnitBuff(unit, i)
    if not buffTexture then break end
    
    local buffName = GetBuffName(unit, i)
    if buffName and string.find(buffName, "Blessing of") then
      -- Extract blessing type (Might, Wisdom, etc.)
      for bType, _ in pairs(blessingTypes) do
        if string.find(buffName, bType) then
          blessings[bType] = true
          break
        end
      end
    end
  end
  
  local count = 0
  for _, _ in pairs(blessings) do
    count = count + 1
  end
  return count
end

-- Helper: Check if class is present in raid
local function IsClassInRaid(className)
  local numRaid = GetNumRaidMembers()
  if numRaid == 0 then return false end
  
  for i = 1, numRaid do
    local _, _, _, _, class = GetRaidRosterInfo(i)
    if class == className then
      return true
    end
  end
  return false
end

-- Helper: Count members of a class in raid
local function CountClassInRaid(className)
  local numRaid = GetNumRaidMembers()
  if numRaid == 0 then return 0 end
  
  local count = 0
  for i = 1, numRaid do
    local _, _, _, _, class = GetRaidRosterInfo(i)
    if class == className then
      count = count + 1
    end
  end
  return count
end

-- Main check functions
function GuildRoll_BuffCheck:CheckBuffs()
  local numRaid = GetNumRaidMembers()
  if numRaid == 0 then
    GuildRoll:defaultPrint(L["BuffCheck_NotInRaid"] or "You are not in a raid.")
    return
  end
  
  local report = {}
  local allOk = true
  
  -- Check which provider classes are present
  local providers = {}
  for class, buffs in pairs(BUFF_REQUIREMENTS) do
    if IsClassInRaid(class) then
      providers[class] = buffs
    end
  end
  
  -- Special handling for Paladins
  local numPaladins = CountClassInRaid("PALADIN")
  local requiredBlessings = math.min(numPaladins, 5) -- 5 blessing types
  
  -- Scan each raid member
  for i = 1, numRaid do
    local name, _, _, _, class = GetRaidRosterInfo(i)
    local unit = "raid" .. i
    
    -- Check regular buffs (non-paladin)
    for providerClass, buffList in pairs(providers) do
      if providerClass ~= "PALADIN" then
        local hasBuff, matchedBuff = HasAnyBuffByName(unit, buffList)
        if not hasBuff then
          allOk = false
          table.insert(report, {
            player = name,
            class = class,
            missing = providerClass .. " buff",
            type = "buff"
          })
        end
      end
    end
    
    -- Check paladin blessings
    if providers["PALADIN"] and requiredBlessings > 0 then
      local blessingCount = CountPaladinBlessings(unit)
      if blessingCount < requiredBlessings then
        allOk = false
        table.insert(report, {
          player = name,
          class = class,
          missing = string.format("Paladin blessings (%d/%d)", blessingCount, requiredBlessings),
          type = "paladin"
        })
      end
    end
  end
  
  -- Show results in Tablet
  self:ShowReport(report, "Buff Check", allOk)
end

function GuildRoll_BuffCheck:CheckConsumes()
  local numRaid = GetNumRaidMembers()
  if numRaid == 0 then
    GuildRoll:defaultPrint(L["BuffCheck_NotInRaid"] or "You are not in a raid.")
    return
  end
  
  local report = {}
  local allOk = true
  local minRequired = 4
  
  for i = 1, numRaid do
    local name, _, _, _, class = GetRaidRosterInfo(i)
    local unit = "raid" .. i
    
    local consumableList = CONSUMABLES[class]
    if consumableList then
      local count = 0
      local found = {}
      
      for j = 1, 32 do
        local buffTexture = UnitBuff(unit, j)
        if not buffTexture then break end
        
        local buffName = GetBuffName(unit, j)
        if buffName then
          for _, consumable in ipairs(consumableList) do
            if MatchBuff(buffName, consumable) and not found[consumable] then
              count = count + 1
              found[consumable] = true
              break
            end
          end
        end
      end
      
      if count < minRequired then
        allOk = false
        table.insert(report, {
          player = name,
          class = class,
          missing = string.format("Consumables (%d/%d)", count, minRequired),
          type = "consume"
        })
      end
    end
  end
  
  if allOk then
    -- Show confirmation popup
    StaticPopupDialogs["GUILDROLL_CONSUMES_AWARD_EP"].text = L["All members have required consumes. Award EP to raid?"] or "All members have required consumes. Award EP to raid?"
    StaticPopup_Show("GUILDROLL_CONSUMES_AWARD_EP")
  else
    -- Show report in Tablet
    self:ShowReport(report, "Consumables Check", allOk)
  end
end

function GuildRoll_BuffCheck:CheckFlasks()
  local numRaid = GetNumRaidMembers()
  if numRaid == 0 then
    GuildRoll:defaultPrint(L["BuffCheck_NotInRaid"] or "You are not in a raid.")
    return
  end
  
  local report = {}
  local allOk = true
  local minRequired = 1
  
  for i = 1, numRaid do
    local name, _, _, _, class = GetRaidRosterInfo(i)
    local unit = "raid" .. i
    
    local hasFlask, matchedFlask = HasAnyBuffByName(unit, FLASKS)
    if not hasFlask then
      allOk = false
      table.insert(report, {
        player = name,
        class = class,
        missing = "Flask",
        type = "flask"
      })
    end
  end
  
  if allOk then
    -- Show confirmation popup
    StaticPopupDialogs["GUILDROLL_FLASKS_AWARD_EP"].text = L["All members have required flasks. Award EP to raid?"] or "All members have required flasks. Award EP to raid?"
    StaticPopup_Show("GUILDROLL_FLASKS_AWARD_EP")
  else
    -- Show report in Tablet
    self:ShowReport(report, "Flasks Check", allOk)
  end
end

-- Show report in Tablet
function GuildRoll_BuffCheck:ShowReport(report, title, allOk)
  -- Store report for display
  self._currentReport = report
  self._reportTitle = title
  self._reportAllOk = allOk
  
  -- Toggle Tablet display
  self:Toggle(true)
end

-- Tablet integration
function GuildRoll_BuffCheck:OnEnable()
  if not T:IsRegistered("GuildRoll_BuffCheck") then
    -- Safe wrapper for D:AddLine
    local function safeAddLine(...)
      pcall(D.AddLine, D, unpack(arg))
    end
    
    T:Register("GuildRoll_BuffCheck",
      "children", function()
        self:OnTooltipUpdate()
      end,
      "showTitleWhenDetached", true,
      "showHintWhenDetached", true,
      "cantAttach", true,
      "menu", function()
        safeAddLine(
          "text", L["Refresh"],
          "tooltipText", L["Refresh window"],
          "func", function() self:Refresh() end
        )
      end
    )
    
    -- Ensure tooltip has a valid owner
    pcall(function()
      if T and T.registry and T.registry.GuildRoll_BuffCheck and T.registry.GuildRoll_BuffCheck.tooltip then
        if not T.registry.GuildRoll_BuffCheck.tooltip.owner then
          T.registry.GuildRoll_BuffCheck.tooltip.owner = GuildRoll:EnsureTabletOwner()
        end
      end
    end)
  end
  if not T:IsAttached("GuildRoll_BuffCheck") then
    pcall(function() T:Open("GuildRoll_BuffCheck") end)
  end
end

function GuildRoll_BuffCheck:OnDisable()
  pcall(function() T:Close("GuildRoll_BuffCheck") end)
end

function GuildRoll_BuffCheck:Refresh()
  pcall(function() T:Refresh("GuildRoll_BuffCheck") end)
end

function GuildRoll_BuffCheck:Toggle(forceShow)
  if T:IsAttached("GuildRoll_BuffCheck") then
    pcall(function() T:Detach("GuildRoll_BuffCheck") end)
    if (T.IsLocked and T:IsLocked("GuildRoll_BuffCheck")) then
      pcall(function() T:ToggleLocked("GuildRoll_BuffCheck") end)
    end
    self:setHideScript()
  else
    if (forceShow) then
      self:Refresh()
    else
      pcall(function() T:Attach("GuildRoll_BuffCheck") end)
    end
  end
end

function GuildRoll_BuffCheck:setHideScript()
  local frame = GuildRoll:FindDetachedFrame("GuildRoll_BuffCheck")
  if frame then
    if not frame.owner then
      frame.owner = "GuildRoll_BuffCheck"
    end
    GuildRoll:make_escable(frame:GetName(), "add")
    if frame.SetScript then
      frame:SetScript("OnHide", nil)
      frame:SetScript("OnHide", function(f)
          pcall(function()
            if T and T.IsAttached and not T:IsAttached("GuildRoll_BuffCheck") then
              T:Attach("GuildRoll_BuffCheck")
            end
            if f and f.SetScript then
              f:SetScript("OnHide", nil)
            end
          end)
        end)
    end
  end
end

function GuildRoll_BuffCheck:OnTooltipUpdate()
  local report = self._currentReport or {}
  local title = self._reportTitle or "Buff Check"
  local allOk = self._reportAllOk
  
  T:SetTitle(title)
  
  if allOk then
    local cat = T:AddCategory("columns", 1)
    cat:AddLine("text", C:Green(L["BuffCheck_AllOk"] or "All members have required buffs/consumables!"))
  elseif table.getn(report) == 0 then
    local cat = T:AddCategory("columns", 1)
    cat:AddLine("text", L["BuffCheck_Header"] or "Run a check to see results.")
  else
    local cat = T:AddCategory(
      "columns", 3,
      "text", L["Name"] or "Name",
      "text2", "Class",
      "text3", "Missing"
    )
    
    for _, entry in ipairs(report) do
      local missingText = entry.missing
      if entry.type == "paladin" then
        missingText = C:Orange(missingText)
      else
        missingText = C:Red(missingText)
      end
      
      cat:AddLine(
        "text", entry.player,
        "text2", entry.class,
        "text3", missingText
      )
    end
  end
end
