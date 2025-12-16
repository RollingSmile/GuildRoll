-- Guard: Check if required libraries are available before proceeding
local T, D, C, L, BC
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
  
  -- Optional: Babble-Class-2.2 for class name normalization
  ok, result = pcall(function() return AceLibrary("Babble-Class-2.2") end)
  if ok and result then
    BC = result
  end
end

GuildRoll_BuffCheck = GuildRoll:NewModule("GuildRoll_BuffCheck", "AceDB-2.0")

-- Configuration: Missing buff severity threshold for color coding
local BUFF_MISSING_SEVERITY_THRESHOLD = 2

-- Spell ID tables for buffs by provider class (Turtle WoW 1.12)
-- WARRIOR intentionally removed - Battle Shout is not checked
local BUFF_IDS = {
  -- Power Word: Fortitude (10933, 27681), Divine Spirit (14782, 27683), Shadow Protection (27685, 27687)
  PRIEST = {10933, 27681, 14782, 27683, 27685, 27687},
  -- Arcane Intellect (1459), Arcane Brilliance (23028)
  MAGE   = {1459, 23028},
  -- Mark of the Wild (8907), Gift of the Wild (21850)
  DRUID  = {8907, 21850},
  -- Blessings: Might (10442, 25780), Wisdom (10308, 25895), Kings (25782, 25899), Light (19978, 25916), Salvation (1038, 25898)
  PALADIN= {10442, 25780, 10308, 25895, 25782, 25899, 19978, 25916, 1038, 25898},
}

-- Legacy name-based buff requirements (kept for reference only)
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
  -- WARRIOR removed - Battle Shout no longer checked
  PALADIN = {
    -- Special handling: count number of paladins and require min(N, #blessing_types) distinct blessings
    "Blessing of Might",
    "Blessing of Wisdom",
    "Blessing of Kings",
    "Blessing of Light",
    "Blessing of Salvation",
  },
}

-- Spell ID tables for consumables by class (Turtle WoW 1.12)
-- Mongoose=17528, Giants=17551, Firewater=18125, Juju Power=17539, Juju Might=17540, Dumplings=24045, Sunfruit=10706, Stoneshield=17565
-- Greater Agility=9188, Greater Firepower=17562, Shadow Power=17560, Arcane Elixir=17556, Greater Arcane=17557, Frost Power=17563, Cerebral=9030, Runn Tum=18141
local CONSUMABLE_IDS = {
  WARRIOR = {17528, 17551, 18125, 17539, 17540, 24045, 10706, 17565},
  ROGUE   = {17528, 9188, 18125, 17539, 17540, 10706, 24045},
  HUNTER  = {17528, 9188, 18125, 17539, 10706, 24045},
  MAGE    = {17562, 17560, 17556, 17557, 17563, 9030, 18141},
  WARLOCK = {17562, 17560, 17556, 17557, 9030, 18141},
  PRIEST  = {17562, 17560, 17556, 17557, 9030, 18141},
  DRUID   = {17562, 17560, 17556, 17557, 9030, 18141, 17528, 9188},
  PALADIN = {17551, 17528, 17562, 17560, 17556, 17557, 9030, 18141},
  -- SHAMAN intentionally omitted
}

-- Keyword fallback for consumables (for servers with custom buff names)
local CONSUMABLE_BUFF_KEYWORDS = {
  "Mongoose", "Giants",      -- Elixir of the Mongoose, Elixir of Giants
  "Firewater",               -- Winterfall Firewater
  "Juju",                    -- Juju Power, Juju Might
  "Stoneshield",             -- Greater Stoneshield Potion
  "Sunfruit", "Dumplings",   -- Blessed Sunfruit Juice, Smoked Desert Dumplings
  "Agility",                 -- Elixir of Greater Agility
  "Firepower", "Shadow Power", -- Elixir of Greater Firepower, Elixir of Shadow Power
  "Arcane Elixir",           -- Arcane Elixir, Greater Arcane Elixir
  "Frost Power",             -- Elixir of Frost Power
  "Cerebral", "Runn Tum"     -- Cerebral Cortex Compound, Runn Tum Tuber Surprise
}

-- Legacy name-based consumables (kept for reference only)
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

-- Spell ID tables for flasks (Turtle WoW 1.12)
-- Flask of Distilled Wisdom (13506), Flask of Supreme Power (13508), Flask of the Titans (13507)
local FLASK_IDS = {13506, 13508, 13507}

-- Legacy name-based flasks (kept for reference only)
-- Common flasks (min = 1)
local FLASKS = {
  "Flask of Distilled Wisdom",
  "Flask of Supreme Power",
  "Flask of the Titans",
}

-- Localized name maps (populated by resolveIDLists)
local localizedBuffs = {}      -- [className] = {[localizedName] = true}
local localizedConsumables = {} -- [className] = {[localizedName] = true}
local localizedFlasks = {}      -- {[localizedName] = true}
local localizedNamesResolved = false -- Cache flag to avoid re-resolving on every check

-- Helper: Compatibility wrapper for GetSpellInfo (1.12 uses GetSpellName)
local function GetSpellNameByID(spellID)
  -- Try GetSpellInfo first (TBC+)
  if GetSpellInfo then
    local name = GetSpellInfo(spellID)
    return name
  end
  
  -- Fallback: In 1.12, GetSpellName only works for spells in player's spellbook.
  -- For cross-class buffs, we rely on detecting the buff when it's active on units.
  -- The spell ID will be resolved when we scan actual buffs from raid members.
  -- As a fallback, we'll return nil here and rely on CONSUMABLE_BUFF_KEYWORDS
  -- for partial matching when spell IDs can't be resolved.
  if GetSpellName then
    local name = GetSpellName(spellID, BOOKTYPE_SPELL)
    if name then return name end
  end
  
  return nil
end

-- Helper: Populate localized name maps from spell IDs
local function resolveIDLists()
  -- Skip if already resolved (cache optimization)
  if localizedNamesResolved then
    return
  end
  
  -- Clear previous maps
  localizedBuffs = {}
  localizedConsumables = {}
  localizedFlasks = {}
  
  -- Resolve BUFF_IDS
  for className, idList in pairs(BUFF_IDS) do
    if not localizedBuffs[className] then
      localizedBuffs[className] = {}
    end
    for _, spellID in ipairs(idList) do
      local ok, spellName = pcall(GetSpellNameByID, spellID)
      if ok and spellName then
        localizedBuffs[className][spellName] = true
      end
    end
  end
  
  -- Resolve CONSUMABLE_IDS
  for className, idList in pairs(CONSUMABLE_IDS) do
    if not localizedConsumables[className] then
      localizedConsumables[className] = {}
    end
    for _, spellID in ipairs(idList) do
      local ok, spellName = pcall(GetSpellNameByID, spellID)
      if ok and spellName then
        localizedConsumables[className][spellName] = true
      end
    end
  end
  
  -- Resolve FLASK_IDS
  for _, spellID in ipairs(FLASK_IDS) do
    local ok, spellName = pcall(GetSpellNameByID, spellID)
    if ok and spellName then
      localizedFlasks[spellName] = true
    end
  end
  
  -- Mark as resolved
  localizedNamesResolved = true
end

-- StaticPopup dialogs (defined once at module initialization)
StaticPopupDialogs["GUILDROLL_CONSUMES_AWARD_EP"] = {
  text = "",  -- Will be set dynamically via L[] lookup
  button1 = TEXT(ACCEPT),
  button2 = TEXT(CANCEL),
  OnAccept = function()
    -- Call the existing Give EP flow
    pcall(function()
      GuildRoll:PromptAwardRaidEP()
    end)
  end,
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 1,
}

StaticPopupDialogs["GUILDROLL_FLASKS_AWARD_EP"] = {
  text = "",  -- Will be set dynamically via L[] lookup
  button1 = TEXT(ACCEPT),
  button2 = TEXT(CANCEL),
  OnAccept = function()
    -- Call the existing Give EP flow
    pcall(function()
      GuildRoll:PromptAwardRaidEP()
    end)
  end,
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 1,
}

-- Helper: Normalize class token to English uppercase (e.g. "Krieger" -> "WARRIOR")
-- Falls back to uppercase if Babble-Class not available
local function NormalizeClassToken(classString)
  if not classString then return nil end
  
  -- Try Babble-Class reverse translation if available
  if BC and BC.HasReverseTranslation and BC.GetReverseTranslation then
    local ok, hasReverse = pcall(BC.HasReverseTranslation, BC, classString)
    if ok and hasReverse then
      local ok2, reversed = pcall(BC.GetReverseTranslation, BC, classString)
      if ok2 and reversed then
        return string.upper(reversed)
      end
    end
  end
  
  -- Fallback: uppercase the provided string
  return string.upper(classString)
end

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

-- Helper: Check if player has any buff from a localized map
-- buffMap is {[localizedName] = true}
local function HasAnyBuffByMap(unit, buffMap)
  if not buffMap then return false end
  
  for i = 1, 32 do
    local buffTexture = UnitBuff(unit, i)
    if not buffTexture then break end
    
    local buffName = GetBuffName(unit, i)
    if buffName and buffMap[buffName] then
      return true, buffName
    end
  end
  return false
end

-- Helper: Check if player has any buff from a list using tooltip scan (legacy)
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
    if class and NormalizeClassToken(class) == className then
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
    if class and NormalizeClassToken(class) == className then
      count = count + 1
    end
  end
  return count
end

-- Helper: Clear report state
local function ClearReportState(self)
  self._currentReport = nil
  self._reportTitle = nil
  self._reportAllOk = nil
end

-- Main check functions
function GuildRoll_BuffCheck:CheckBuffs()
  -- Clear previous state
  ClearReportState(self)
  
  local numRaid = GetNumRaidMembers()
  if numRaid == 0 then
    GuildRoll:defaultPrint(L["BuffCheck_NotInRaid"] or "You are not in a raid.")
    return
  end
  
  -- Resolve spell IDs to localized names
  resolveIDLists()
  
  local report = {}
  local allOk = true
  
  -- Dynamic buff requirement calculation based on raid composition
  local providers = {}
  for class, _ in pairs(BUFF_IDS) do
    if IsClassInRaid(class) then
      providers[class] = true
    end
  end
  
  -- Calculate required buffs dynamically
  local numPaladins = CountClassInRaid("PALADIN")
  local requiredBlessings = math.min(numPaladins, 5) -- Up to 5 blessing types
  
  -- Calculate total required buffs for each player
  local totalRequired = 0
  for providerClass, _ in pairs(providers) do
    if providerClass ~= "PALADIN" then
      totalRequired = totalRequired + 1
    end
  end
  -- Add Paladin blessings to total if applicable
  if providers["PALADIN"] and requiredBlessings > 0 then
    totalRequired = totalRequired + requiredBlessings
  end
  
  -- Scan each raid member
  for i = 1, numRaid do
    local name, _, _, _, class = GetRaidRosterInfo(i)
    local unit = "raid" .. i
    
    local missingBuffs = {}
    local missingCount = 0
    
    -- Check regular buffs (non-paladin) using localized maps
    for providerClass, _ in pairs(providers) do
      if providerClass ~= "PALADIN" then
        local buffMap = localizedBuffs[providerClass]
        local hasBuff, matchedBuff = HasAnyBuffByMap(unit, buffMap)
        if not hasBuff then
          table.insert(missingBuffs, providerClass)
          missingCount = missingCount + 1
        end
      end
    end
    
    -- Check paladin blessings
    if providers["PALADIN"] and requiredBlessings > 0 then
      local blessingCount = CountPaladinBlessings(unit)
      if blessingCount < requiredBlessings then
        local missingBlessings = requiredBlessings - blessingCount
        table.insert(missingBuffs, string.format("Paladin(%d)", missingBlessings))
        missingCount = missingCount + missingBlessings
      end
    end
    
    -- Only add to report if player has missing buffs
    if missingCount > 0 then
      allOk = false
      table.insert(report, {
        player = name,
        class = class,
        missingCount = missingCount,
        totalRequired = totalRequired,
        missingList = table.concat(missingBuffs, ";")
      })
    end
  end
  
  -- Sort report by number of missing buffs (descending)
  table.sort(report, function(a, b)
    return a.missingCount > b.missingCount
  end)
  
  -- Show results in Tablet
  self:ShowReport(report, "Buff Check", allOk)
  
  -- Refresh Tablet window in-place
  self:Refresh()
end

function GuildRoll_BuffCheck:CheckConsumes()
  -- Clear previous state
  ClearReportState(self)
  
  local numRaid = GetNumRaidMembers()
  if numRaid == 0 then
    GuildRoll:defaultPrint(L["BuffCheck_NotInRaid"] or "You are not in a raid.")
    return
  end
  
  -- Resolve spell IDs to localized names
  resolveIDLists()
  
  local report = {}
  local allOk = true
  local minRequired = 4
  
  for i = 1, numRaid do
    local name, _, _, _, class = GetRaidRosterInfo(i)
    local unit = "raid" .. i
    
    local normalizedClass = NormalizeClassToken(class)
    local consumableMap = localizedConsumables[normalizedClass]
    if consumableMap then
      local count = 0
      local found = {}
      
      for j = 1, 32 do
        local buffTexture = UnitBuff(unit, j)
        if not buffTexture then break end
        
        local buffName = GetBuffName(unit, j)
        if buffName then
          -- Try exact match from localized map first
          if consumableMap[buffName] and not found[buffName] then
            count = count + 1
            found[buffName] = true
          else
            -- Fallback to keyword matching for custom server buffs
            for _, keyword in ipairs(CONSUMABLE_BUFF_KEYWORDS) do
              if MatchBuff(buffName, keyword) and not found[buffName] then
                count = count + 1
                found[buffName] = true
                break
              end
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
  
  -- Refresh Tablet window in-place
  self:Refresh()
end

function GuildRoll_BuffCheck:CheckFlasks()
  -- Clear previous state
  ClearReportState(self)
  
  local numRaid = GetNumRaidMembers()
  if numRaid == 0 then
    GuildRoll:defaultPrint(L["BuffCheck_NotInRaid"] or "You are not in a raid.")
    return
  end
  
  -- Resolve spell IDs to localized names
  resolveIDLists()
  
  local report = {}
  local allOk = true
  local minRequired = 1
  
  for i = 1, numRaid do
    local name, _, _, _, class = GetRaidRosterInfo(i)
    local unit = "raid" .. i
    
    local hasFlask, matchedFlask = HasAnyBuffByMap(unit, localizedFlasks)
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
  
  -- Refresh Tablet window in-place
  self:Refresh()
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

-- Diagnostic helper: Dump buffs on a unit
function GuildRoll_BuffCheck:DumpBuffs(unit)
  if not unit then
    GuildRoll:defaultPrint("Usage: GuildRoll_BuffCheck:DumpBuffs(\"player\") or GuildRoll_BuffCheck:DumpBuffs(\"raid1\")")
    return
  end
  
  local ok, exists = pcall(UnitExists, unit)
  if not ok or not exists then
    GuildRoll:defaultPrint("Unit does not exist: " .. tostring(unit))
    return
  end
  
  -- Resolve spell IDs to check matches
  resolveIDLists()
  
  local _, class = UnitClass(unit)
  local normalizedClass = NormalizeClassToken(class)
  
  GuildRoll:defaultPrint("=== Buffs on " .. tostring(unit) .. " ===")
  
  for i = 1, 32 do
    local buffTexture = UnitBuff(unit, i)
    if not buffTexture then break end
    
    local buffName = GetBuffName(unit, i)
    if buffName then
      local matched = {}
      
      -- Check if it matches any buff category
      for providerClass, buffMap in pairs(localizedBuffs) do
        if buffMap[buffName] then
          table.insert(matched, "BUFF:" .. providerClass)
        end
      end
      
      -- Check if it matches consumables
      if localizedConsumables[normalizedClass] and localizedConsumables[normalizedClass][buffName] then
        table.insert(matched, "CONSUME:" .. normalizedClass)
      end
      
      -- Check if it matches flasks
      if localizedFlasks[buffName] then
        table.insert(matched, "FLASK")
      end
      
      local matchStr = ""
      if table.getn(matched) > 0 then
        matchStr = " [" .. table.concat(matched, ", ") .. "]"
      end
      
      GuildRoll:defaultPrint(i .. ". " .. buffName .. matchStr)
    end
  end
  
  GuildRoll:defaultPrint("=== End of buff dump ===")
end

-- Runtime helper: Add spell IDs to the configured lists
function GuildRoll_BuffCheck:AddSpellIDs(kind, idlist)
  if not kind or not idlist then
    GuildRoll:defaultPrint("Usage: GuildRoll_BuffCheck:AddSpellIDs(\"BUFF:PRIEST\", {12345, 67890})")
    GuildRoll:defaultPrint("       GuildRoll_BuffCheck:AddSpellIDs(\"CONSUME:WARRIOR\", {12345})")
    GuildRoll:defaultPrint("       GuildRoll_BuffCheck:AddSpellIDs(\"FLASK\", {12345})")
    return
  end
  
  if kind == "FLASK" then
    -- Add to FLASK_IDS
    for _, id in ipairs(idlist) do
      table.insert(FLASK_IDS, id)
    end
    GuildRoll:defaultPrint("Added " .. table.getn(idlist) .. " spell IDs to FLASK_IDS")
  elseif string.find(kind, "BUFF:") then
    -- Extract class name
    local className = string.sub(kind, 6)
    if not BUFF_IDS[className] then
      BUFF_IDS[className] = {}
    end
    for _, id in ipairs(idlist) do
      table.insert(BUFF_IDS[className], id)
    end
    GuildRoll:defaultPrint("Added " .. table.getn(idlist) .. " spell IDs to BUFF_IDS." .. className)
  elseif string.find(kind, "CONSUME:") then
    -- Extract class name
    local className = string.sub(kind, 9)
    if not CONSUMABLE_IDS[className] then
      CONSUMABLE_IDS[className] = {}
    end
    for _, id in ipairs(idlist) do
      table.insert(CONSUMABLE_IDS[className], id)
    end
    GuildRoll:defaultPrint("Added " .. table.getn(idlist) .. " spell IDs to CONSUMABLE_IDS." .. className)
  else
    GuildRoll:defaultPrint("Unknown kind: " .. kind)
    return
  end
  
  -- Invalidate cache and re-resolve localized names
  localizedNamesResolved = false
  resolveIDLists()
  GuildRoll:defaultPrint("Spell ID lists updated and localized names refreshed.")
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
      "text2", "Missing",
      "text3", "Details"
    )
    
    for _, entry in ipairs(report) do
      -- Format count as "X/Y" where X is missing and Y is total required
      local countText = string.format("%d/%d", entry.missingCount, entry.totalRequired)
      
      -- Highlight based on severity (more missing = more critical)
      local countColor = C:Red(countText)
      if entry.missingCount <= BUFF_MISSING_SEVERITY_THRESHOLD then
        countColor = C:Orange(countText)
      end
      
      -- Format missing buffs list with color
      local detailsColor = C:Red(entry.missingList)
      
      cat:AddLine(
        "text", entry.player,
        "text2", countColor,
        "text3", detailsColor
      )
    end
  end
end
