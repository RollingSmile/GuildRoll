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

-- Configuration: Minimum required consumables per player
local CONSUMABLE_MIN_REQUIRED = 4

-- Configuration: Minimum required flasks per player
local FLASK_MIN_REQUIRED = 1

-- Configuration: Number of distinct priest buff types required
local PRIEST_BUFF_TYPES_REQUIRED = 3

-- Buff requirements by provider class (name-based matching)
local BUFF_REQUIREMENTS = {
  PRIEST = {
    "Power Word: Fortitude",
    "Prayer of Fortitude",
    "Divine Spirit",
    "Prayer of Spirit",
    "Shadow Protection",
    "Prayer of Shadow Protection"
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
    "Blessing of Sanctuary",
  },
}

-- Role-based consumable requirements (name-based matching)
-- Consumables are organized by role rather than class to reduce duplication
local ROLE_CONSUMABLES = {
  TANK = {
    "Spirit of Zanza",
    "Swiftness of Zanza",
    "Danonzo's Tel'Abim Medley",
    "Elixir of the Mongoose",
    "Juju Might",
    "Juju Power",
    "Elixir of Giants",
    "Elixir of Fortitude",
    "Elixir of Superior Defense",
    "Greater Stoneshield Potion",
    "Gurubashi Gumbo",
    "Le Fishe Au Chocolat",
    "Grilled Squid",
    "Sour Mountain Berry",
    "Flask of Titans",
    "Major Troll's Blood Potion",
    "Hardened Mushroom",
    "Winterfall Firewater",
    "Rumsey Rum Black Label",
    "R.O.I.D.S.",
    "Elemental Sharpening Stone",
    "Mighty Rage Potion",
  },
  PHYSICAL = {
    "Spirit of Zanza",
    "Swiftness of Zanza",
    "Danonzo's Tel'Abim Medley",
    "Elixir of the Mongoose",
    "Juju Might",
    "Ground Scorpok Assay",
    "Strike of the Scorpok",
    "Le Fishe Au Chocolat",
    "Grilled Squid",
    "Sour Mountain Berry",
    "Elemental Sharpening Stone",
    "R.O.I.D.S.",
    "Mighty Rage Potion",
  },
  CASTER = {
    "Spirit of Zanza",
    "Swiftness of Zanza",
    "Danonzo's Tel'Abim Medley",
    "Cerebral Cortex Compound",
    "Mageblood Potion",
    "Greater Arcane Elixir",
    "Arcane Elixir",
    "Dreamshard Elixir",
    "Brilliant Wizard Oil",
    "Brilliant Mana Oil",
    "Major Mana Potion",
    "Nightfin Soup",
    "Fizzy Energy Drink",
    "Herbal Tea",
    "Kreeg's Stout Beatdown",
    "Merlot Blue",
    "Danonzo's Tel'Abim Delight",
  },
  HEALER = {
    "Spirit of Zanza",
    "Swiftness of Zanza",
    "Danonzo's Tel'Abim Medley",
    "Cerebral Cortex Compound",
    "Mageblood Potion",
    "Major Mana Potion",
    "Flask of Distilled Wisdom",
    "Herbal Tea",
    "Nightfin Soup",
  }
}

-- Class to role mapping (upper-case class tokens)
-- Each class can have multiple roles
local CLASS_ROLES = {
  DRUID = { "TANK", "PHYSICAL", "CASTER", "HEALER" },
  PALADIN = { "TANK", "PHYSICAL", "HEALER" },
  WARRIOR = { "TANK", "PHYSICAL" },
  HUNTER = { "PHYSICAL" },
  ROGUE = { "PHYSICAL" },
  MAGE = { "CASTER" },
  PRIEST = { "CASTER", "HEALER" },
  WARLOCK = { "CASTER" },
}

-- Flask requirements (name-based matching)
local FLASKS = {
  "Flask of Distilled Wisdom",
  "Flask of Supreme Power",
  "Flask of the Titans",
}

-- Localized name maps (populated by resolveIDLists)
local localizedBuffs = {}      -- [className] = {[localizedName] = true}
local localizedConsumables = {} -- [className] = {[localizedName] = true}
local localizedFlasks = {}      -- {[localizedName] = true}
local localizedBuffTextures = {} -- [className] = {[textureName] = true} for texture-based matching
local PALADIN_BLESSING_PATTERNS = {} -- Cached paladin blessing patterns
local localizedNamesResolved = false -- Cache flag to avoid re-resolving on every check

-- Helper: Extract texture file name from full texture path
local function TextureNameFromPath(texturePath)
  if not texturePath then return nil end
  -- Convert to string if needed
  local path = tostring(texturePath)
  -- Extract filename from path (e.g., "Interface\\Icons\\Spell_Holy_PowerWordFortitude" -> "Spell_Holy_PowerWordFortitude")
  -- Handle both backslashes and forward slashes (Lua pattern: any char except / or \)
  local filename = string.match(path, "([^/\\]+)$")
  if filename then
    return string.lower(filename)
  end
  return string.lower(path)
end

-- Helper: Get spell icon/texture by spell ID
local function GetSpellIconByID(spellID)
  -- Try GetSpellTexture if available (TBC+)
  -- On Turtle WoW / 1.12, GetSpellTexture exists but expects different parameters.
  -- Use pcall to guard against runtime errors when calling with spell ID.
  if GetSpellTexture then
    local ok, texture = pcall(GetSpellTexture, spellID)
    if ok and texture and type(texture) == "string" then
      return texture
    end
  end
  
  -- In 1.12, GetSpellTexture is not available and we would need to scan
  -- the spellbook to find the texture. However, this won't work for cross-class
  -- spells that aren't in the player's spellbook, so we simply return nil
  -- and rely on scanning actual buffs on units to build the texture map.
  return nil
end

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
-- For consumables, this now primarily uses pattern/keyword matching instead of spell IDs
local function resolveIDLists()
  -- Skip if already resolved (cache optimization)
  if localizedNamesResolved then
    return
  end

  -- Clear previous maps
  localizedBuffs = {}
  localizedConsumables = {}
  localizedFlasks = {}
  localizedBuffTextures = {} -- keep empty: we drop texture-based matching
  PALADIN_BLESSING_PATTERNS = {}

  -- Populate buffs from legacy BUFF_REQUIREMENTS only (exact-name matching)
  for className, buffList in pairs(BUFF_REQUIREMENTS) do
    localizedBuffs[className] = localizedBuffs[className] or {}
    for _, buffName in ipairs(buffList) do
      localizedBuffs[className][buffName] = true
    end
  end

  -- Build paladin blessing patterns from BUFF_REQUIREMENTS (cached globally)
  if BUFF_REQUIREMENTS["PALADIN"] then
    for _, buffName in ipairs(BUFF_REQUIREMENTS["PALADIN"]) do
      table.insert(PALADIN_BLESSING_PATTERNS, buffName)
    end
  end

  -- Populate consumables from role-based ROLE_CONSUMABLES (exact-name matching)
  -- Build a merged set of consumables for each class based on their roles
  for className, roles in pairs(CLASS_ROLES) do
    localizedConsumables[className] = localizedConsumables[className] or {}
    for _, role in ipairs(roles) do
      if ROLE_CONSUMABLES[role] then
        for _, consumeName in ipairs(ROLE_CONSUMABLES[role]) do
          localizedConsumables[className][consumeName] = true
        end
      end
    end
  end

  -- Populate flasks from legacy FLASKS only (exact-name matching)
  for _, flaskName in ipairs(FLASKS) do
    localizedFlasks[flaskName] = true
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
-- buffMap is {[pattern] = true} where pattern can be exact name or substring
-- Uses substring matching for robust detection on servers with custom names
local function HasAnyBuffByMap(unit, buffMap)
  if not buffMap then return false end
  
  for i = 1, 32 do
    local buffTexture = UnitBuff(unit, i)
    if not buffTexture then break end
    
    local buffName = GetBuffName(unit, i)
    if buffName then
      -- Try exact match first (faster)
      if buffMap[buffName] then
        return true, buffName
      end
      
      -- Fall back to substring matching for each pattern in the map
      for pattern, _ in pairs(buffMap) do
        if MatchBuff(buffName, pattern) then
          return true, buffName
        end
      end
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

-- Helper: Check if unit has any buff from a given class provider
-- Uses both localized name patterns and texture-name matches
local function HasAnyBuffByClass(unit, className)
  if not className then return false end
  
  local buffMap = localizedBuffs[className]
  local textureMap = localizedBuffTextures[className]
  
  if not buffMap and not textureMap then return false end
  
  for i = 1, 32 do
    local buffTexture = UnitBuff(unit, i)
    if not buffTexture then break end
    
    -- Check texture-based match
    if textureMap then
      local textureName = TextureNameFromPath(buffTexture)
      if textureName and textureMap[textureName] then
        return true, textureName
      end
    end
    
    -- Check name-based match
    if buffMap then
      local buffName = GetBuffName(unit, i)
      if buffName then
        -- Try exact match first (faster)
        if buffMap[buffName] then
          return true, buffName
        end
        
        -- Fall back to substring matching for each pattern in the map
        for pattern, _ in pairs(buffMap) do
          if MatchBuff(buffName, pattern) then
            return true, buffName
          end
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
    ["Sanctuary"] = true,
  }
  
  for i = 1, 32 do
    local buffTexture = UnitBuff(unit, i)
    if not buffTexture then break end
    
    local buffName = GetBuffName(unit, i)
    if buffName then
      -- Check if this is a paladin blessing using cached patterns
      local isBlessing = false
      for _, pattern in ipairs(PALADIN_BLESSING_PATTERNS) do
        if MatchBuff(buffName, pattern) then
          isBlessing = true
          break
        end
      end
      
      if isBlessing then
        -- Extract blessing type (Might, Wisdom, etc.)
        for bType, _ in pairs(blessingTypes) do
          if string.find(string.lower(buffName), string.lower(bType), 1, true) then
            blessings[bType] = true
            break
          end
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

-- Helper: Count distinct priest buff types on a unit
-- Priest has 3 buff types: Fortitude, Spirit, Shadow Protection (each in short/long version)
local function CountPriestBuffTypes(unit)
  local buffTypes = {}
  local priestBuffCategories = {
    ["Fortitude"] = true,
    ["Spirit"] = true,
    ["Shadow Protection"] = true,
  }
  
  for i = 1, 32 do
    local buffTexture = UnitBuff(unit, i)
    if not buffTexture then break end
    
    local buffName = GetBuffName(unit, i)
    if buffName then
      -- Check if this is a priest buff using BUFF_REQUIREMENTS patterns
      local isPriestBuff = false
      if BUFF_REQUIREMENTS["PRIEST"] then
        for _, pattern in ipairs(BUFF_REQUIREMENTS["PRIEST"]) do
          if MatchBuff(buffName, pattern) then
            isPriestBuff = true
            break
          end
        end
      end
      
      if isPriestBuff then
        -- Extract buff type (Fortitude, Spirit, Shadow Protection)
        for buffType, _ in pairs(priestBuffCategories) do
          if string.find(string.lower(buffName), string.lower(buffType), 1, true) then
            buffTypes[buffType] = true
            break
          end
        end
      end
    end
  end
  
  local count = 0
  for _, _ in pairs(buffTypes) do
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
  for providerClass, _ in pairs(BUFF_REQUIREMENTS) do
    if IsClassInRaid(providerClass) then
      providers[providerClass] = true
    end
  end
  
  -- Calculate required buffs dynamically
  local numPaladins = CountClassInRaid("PALADIN")
  local requiredBlessings = math.min(numPaladins, 6) -- Up to 6 blessing types
  
  -- Calculate total required buffs for each player
  local totalRequired = 0
  for providerClass, _ in pairs(providers) do
    if providerClass == "PALADIN" then
      -- Paladins handled separately
    elseif providerClass == "PRIEST" then
      totalRequired = totalRequired + PRIEST_BUFF_TYPES_REQUIRED
    else
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
    
    -- Check priest buffs (requires all 3 buff types)
    if providers["PRIEST"] then
      local priestBuffCount = CountPriestBuffTypes(unit)
      if priestBuffCount < PRIEST_BUFF_TYPES_REQUIRED then
        local missingPriestBuffs = PRIEST_BUFF_TYPES_REQUIRED - priestBuffCount
        table.insert(missingBuffs, string.format("Priest(%d)", missingPriestBuffs))
        missingCount = missingCount + missingPriestBuffs
      end
    end
    
    -- Check regular buffs (non-paladin, non-priest) using HasAnyBuffByClass
    for providerClass, _ in pairs(providers) do
      if providerClass ~= "PALADIN" and providerClass ~= "PRIEST" then
        local hasBuff, matchedBuff = HasAnyBuffByClass(unit, providerClass)
        if not hasBuff then
          table.insert(missingBuffs, providerClass)
          missingCount = missingCount + 1
        end
      end
    end
    
    -- Check paladin blessings using improved CountPaladinBlessings
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
  
  -- Resolve patterns to localized consumables (now primarily pattern-based)
  resolveIDLists()
  
  local report = {}
  local allOk = true
  local minRequired = CONSUMABLE_MIN_REQUIRED
  
  for i = 1, numRaid do
    local name, _, _, _, class = GetRaidRosterInfo(i)
    local unit = "raid" .. i
    
    local normalizedClass = NormalizeClassToken(class)
    local consumablePatterns = localizedConsumables[normalizedClass]
    
    if consumablePatterns then
      local count = 0
      local foundBuffs = {}  -- Track which buffs we've already counted
      
      -- Scan all buffs on the unit
      for j = 1, 32 do
        local buffTexture = UnitBuff(unit, j)
        if not buffTexture then break end
        
        local buffName = GetBuffName(unit, j)
        if buffName and not foundBuffs[buffName] then
          -- Check if this buff matches any consumable pattern for this class
          for pattern, _ in pairs(consumablePatterns) do
            if MatchBuff(buffName, pattern) then
              count = count + 1
              foundBuffs[buffName] = true
              break  -- Only count each buff once
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
  
  -- Resolve patterns to localized flasks (now primarily pattern-based)
  resolveIDLists()
  
  local report = {}
  local allOk = true
  local minRequired = FLASK_MIN_REQUIRED
  
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
    local textureName = TextureNameFromPath(buffTexture)
    
    if buffName then
      local matched = {}
      
      -- Check if it matches any buff category (exact or pattern match for buffs)
      for providerClass, buffMap in pairs(localizedBuffs) do
        if buffMap[buffName] then
          table.insert(matched, "BUFF:" .. providerClass)
        else
          -- Try pattern matching
          for pattern, _ in pairs(buffMap) do
            if MatchBuff(buffName, pattern) then
              table.insert(matched, "BUFF:" .. providerClass .. " (pattern: " .. pattern .. ")")
              break
            end
          end
        end
      end
      
      -- Check if it matches texture-based buff detection
      for providerClass, textureMap in pairs(localizedBuffTextures) do
        if textureName and textureMap[textureName] then
          table.insert(matched, "BUFF:" .. providerClass .. " (texture: " .. textureName .. ")")
        end
      end
      
      -- Check if it matches consumables (pattern matching)
      if localizedConsumables[normalizedClass] then
        for pattern, _ in pairs(localizedConsumables[normalizedClass]) do
          if MatchBuff(buffName, pattern) then
            table.insert(matched, "CONSUME:" .. normalizedClass .. " (pattern: " .. pattern .. ")")
            break  -- Only show first matching pattern
          end
        end
      end
      
      -- Check if it matches flasks (pattern matching)
      for pattern, _ in pairs(localizedFlasks) do
        if MatchBuff(buffName, pattern) then
          table.insert(matched, "FLASK (pattern: " .. pattern .. ")")
          break  -- Only show first matching pattern
        end
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
-- NOTE: This function is no longer supported after simplifying resolveIDLists()
-- to use only text/name-based matching. Spell ID-based matching has been removed.
function GuildRoll_BuffCheck:AddSpellIDs(kind, idlist)
  GuildRoll:defaultPrint("AddSpellIDs is no longer supported.")
  GuildRoll:defaultPrint("The addon now uses only text/name-based matching from BUFF_REQUIREMENTS, CONSUMABLES, and FLASKS tables.")
  GuildRoll:defaultPrint("Please modify those tables directly in buffcheck.lua if you need to add custom buffs.")
end

-- Slash command handler for /dumpbuffs
local function SlashCommandHandler(msg)
  -- Parse the argument
  local arg = string.lower(string.gsub(msg or "", "^%s*(.-)%s*$", "%1"))
  
  if arg == "" or arg == "help" then
    GuildRoll:defaultPrint("Usage: /dumpbuffs <unit>")
    GuildRoll:defaultPrint("  Examples:")
    GuildRoll:defaultPrint("    /dumpbuffs player - Dump buffs on yourself")
    GuildRoll:defaultPrint("    /dumpbuffs target - Dump buffs on your target")
    GuildRoll:defaultPrint("    /dumpbuffs raid - Dump buffs on entire raid")
    GuildRoll:defaultPrint("    /dumpbuffs raid1 - Dump buffs on raid member 1")
    GuildRoll:defaultPrint("    /dumpbuffs raid5 - Dump buffs on raid member 5")
    return
  end
  
  -- Handle 'raid' - dump all raid members
  if arg == "raid" then
    local numRaid = GetNumRaidMembers()
    if numRaid == 0 then
      GuildRoll:defaultPrint("You are not in a raid.")
      return
    end
    for i = 1, numRaid do
      GuildRoll_BuffCheck:DumpBuffs("raid" .. i)
    end
    return
  end
  
  -- Handle specific unit (player, target, raid1, etc.)
  GuildRoll_BuffCheck:DumpBuffs(arg)
end

-- Register slash commands
SLASH_DUMPBUFFS1 = "/dumpbuffs"
SLASH_DUMPBUFFS2 = "/dbuffs"
SlashCmdList["DUMPBUFFS"] = SlashCommandHandler

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

-- UPDATED OnTooltipUpdate: robust handling for buff/consumes/flasks report formats
function GuildRoll_BuffCheck:OnTooltipUpdate()
  local report = self._currentReport or {}
  local title = self._reportTitle or "Buff Check"
  local allOk = self._reportAllOk
  
  T:SetTitle(title)
  
  if allOk then
    local cat = T:AddCategory("columns", 1)
    cat:AddLine("text", C:Green(L["BuffCheck_AllOk"] or "All members have all possible class buffs!"))
    return
  end
  
  if table.getn(report) == 0 then
    local cat = T:AddCategory("columns", 1)
    cat:AddLine("text", L["BuffCheck_Header"] or "Run a check to see results.")
    return
  end
  
  -- Detect report format (buff-style has missingCount/totalRequired; consumes use .type == "consume"; flasks .type == "flask")
  local sample = report[1]
  local isBuffFormat = sample and (sample.missingCount ~= nil)
  local isConsumeFormat = sample and (sample.type == "consume")
  local isFlaskFormat = sample and (sample.type == "flask")
  
  if isBuffFormat then
    local cat = T:AddCategory(
      "columns", 3,
      "text", L["Name"] or "Name",
      "text2", "Missing",
      "text3", "Details"
    )
    
    for _, entry in ipairs(report) do
      local missingCount = tonumber(entry.missingCount) or 0
      local totalReq = tonumber(entry.totalRequired) or 0
      local missingList = tostring(entry.missingList or "")
      
      local countText = string.format("%d/%d", missingCount, totalReq)
      
      local countColor = C:Red(countText)
      if missingCount <= BUFF_MISSING_SEVERITY_THRESHOLD then
        countColor = C:Orange(countText)
      end
      
      local detailsColor = C:Red(missingList)
      
      cat:AddLine(
        "text", tostring(entry.player or "<unknown>"),
        "text2", countColor,
        "text3", detailsColor
      )
    end
    return
  end
  
  -- Consumables report format
  if isConsumeFormat then
    local cat = T:AddCategory(
      "columns", 2,
      "text", L["Name"] or "Name",
      "text2", "Details"
    )
    for _, entry in ipairs(report) do
      local status = tostring(entry.missing or "")
      local statusColor = C:Red(status)
      -- Use yellow when partial (contains "/") or contains number less than required
      if string.find(status, "/") or string.find(status, "%d") then
        statusColor = C:Orange(status)
      end
      cat:AddLine(
        "text", tostring(entry.player or "<unknown>"),
        "text2", statusColor
      )
    end
    return
  end
  
  -- Flasks report format (fallback generic)
  if isFlaskFormat then
    local cat = T:AddCategory(
      "columns", 2,
      "text", L["Name"] or "Name",
      "text2", "Details"
    )
    for _, entry in ipairs(report) do
      local status = tostring(entry.missing or "Flask")
      local statusColor = C:Red(status)
      cat:AddLine(
        "text", tostring(entry.player or "<unknown>"),
        "text2", statusColor
      )
    end
    return
  end
  
  -- Generic fallback: show whatever fields exist
  local cat = T:AddCategory("columns", 2, "text", L["Name"] or "Name", "text2", "Info")
  for _, entry in ipairs(report) do
    local info = entry.missingList or entry.missing or tostring(entry.missingCount or "")
    cat:AddLine("text", tostring(entry.player or "<unknown>"), "text2", tostring(info))
  end
end
