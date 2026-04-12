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
local BUFF_MISSING_SEVERITY_THRESHOLD = 1

-- Configuration: Minimum required consumables per player
local CONSUMABLE_MIN_REQUIRED = 3

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

-- Mapping of buff names to short display names
local BUFF_SHORT_NAMES = {
  -- Mage buffs
  ["Arcane Intellect"] = "Int",
  ["Arcane Brilliance"] = "Int",
  
  -- Priest buffs
  ["Power Word: Fortitude"] = "Stam",
  ["Prayer of Fortitude"] = "Stam",
  ["Divine Spirit"] = "Spirit",
  ["Prayer of Spirit"] = "Spirit",
  ["Shadow Protection"] = "ShadowProt",
  ["Prayer of Shadow Protection"] = "ShadowProt",
  
  -- Druid buffs
  ["Mark of the Wild"] = "MotW",
  ["Gift of the Wild"] = "MotW",
  
  -- Paladin buffs
  ["Blessing of Might"] = "Might",
  ["Blessing of Wisdom"] = "Wisdom",
  ["Blessing of Kings"] = "Kings",
  ["Blessing of Light"] = "Lights",
  ["Blessing of Salvation"] = "Salv",
  ["Blessing of Sanctuary"] = "Sanc",
}

-- Provider class colors for buff column labels
local PROVIDER_CLASS_COLORS = {
  PRIEST  = {1.0,  1.0,  0.6},
  DRUID   = {1.0,  0.49, 0.04},
  MAGE    = {0.41, 0.8,  0.94},
  PALADIN = {0.96, 0.55, 0.73},
}

-- Full WoW class colors for player name coloring
local CLASS_COLORS = {
  WARRIOR = {0.78, 0.61, 0.43},
  PALADIN = {0.96, 0.55, 0.73},
  HUNTER  = {0.67, 0.83, 0.45},
  ROGUE   = {1.0,  0.96, 0.41},
  PRIEST  = {1.0,  1.0,  1.0},
  SHAMAN  = {0.0,  0.44, 0.87},
  MAGE    = {0.41, 0.8,  0.94},
  WARLOCK = {0.58, 0.51, 0.79},
  DRUID   = {1.0,  0.49, 0.04},
}

-- Reverse lookup: buff short name -> provider class (uppercase)
local BUFF_SHORT_TO_CLASS = {
  ["Stam"]       = "PRIEST",
  ["Spirit"]     = "PRIEST",
  ["ShadowProt"] = "PRIEST",
  ["MotW"]       = "DRUID",
  ["Int"]        = "MAGE",
  ["Might"]      = "PALADIN",
  ["Wisdom"]     = "PALADIN",
  ["Kings"]      = "PALADIN",
  ["Lights"]     = "PALADIN",
  ["Salv"]       = "PALADIN",
  ["Sanc"]       = "PALADIN",
}

-- Display name (title case) for each provider class token
local PROVIDER_CLASS_DISPLAY = {
  PRIEST  = "Priest",
  DRUID   = "Druid",
  MAGE    = "Mage",
  PALADIN = "Paladin",
}

-- Maximum raid size constant
local MAX_RAID_SIZE = 40

-- Configuration: Maximum number of players shown per buff row in the tooltip
local BUFF_PLAYER_DISPLAY_LIMIT = 10

-- Role-based consumable requirements (name-based matching)
-- Consumables are organized by role rather than class to reduce duplication
local ROLE_CONSUMABLES = {
  TANK = {
    "Spirit of Zanza",
    "Elixir of the Mongoose",
    "Greater Armor", --Elixir of Superior Defense
    "Regeneration", --Major Troll's Blood Potion
    "Dreamshard Elixir",
    "Greater Intellect",
    "Increased Stamina", -- Hardened Mushroom
    "Juju Might",
    "Juju Power",
    "Winterfall Firewater",
    "Rumsey Rum Black Label",
    "Medivh's Merlot", --Stamina Merlot
    "Elixir of the Giants",
    "Health II", --Elixir of Fortitude
    "Gurubashi Gumbo",
    "Le Fishe Au Chocolat",
    "Grilled Squid",
    "Sour Mountain Berry",
    "Rage of Ages", --R.O.I.D.S.
    "Strike of the Scorpok",
    "Infallible Mind", --Cerebral Cortex Compound
    "Elemental Sharpening Stone",
    "Well Fed";
  },
  PHYSICAL = {
    "Spirit of Zanza",
    "Health II", --Elixir of Fortitude
    "Rumsey Rum Black Label",
    "Elixir of the Mongoose",
    "Elixir of the Giants",
    "Greater Agility", --Elixir of Agility
    "Juju Power",
    "Winterfall Firewater",
    "Juju Might",
    "Rage of Ages",
    "Strike of the Scorpok",
    "Le Fishe Au Chocolat",
    "Grilled Squid",
    "Increased Strength", -- Power Mushroom
    "Elemental Sharpening Stone",
    "Mana Regeneration", --Mageblood Potion
    "Increased Agility", --Sour Mountain Berry
    "Infallible Mind", --Cerebral Cortex Compound
    "Well Fed"
  },
  CASTER = {
    "Spirit of Zanza",
    "Health II", --Elixir of Fortitude
    "Rumsey Rum Black Label",
    "Medivh's Merlot Blue Label",
    "Infallible Mind", --Cerebral Cortex Compound
    "Mana Regeneration", --Mageblood Potion
    "Greater Arcane Elixir",
    "Arcane Elixir",
    "Greater Intellect",
    "Dreamshard Elixir",
    "Greater Firepower"; --Elixir of Greater Firepower
    "Greater Arcane Power"; --Elixir of Greater Arcane Power
    "Greater Frost Power";
    "Greater Arcane Power";
    "Frost Power"; --Elixir of Frost Power
    "Shadow Power"; --Elixir of Shadow Power
    "Dreamtonic";
    "Brilliant Wizard Oil",
    "Brilliant Mana Oil",
    "Nightfin Soup",
    "Fizzy Energy Drink",
    "Kreeg's Stout Beatdown",
    "Medivh's Merlot Blue Label",
    "Danonzo's Tel'Abim Delight",
    "Well Fed";
  },
  HEALER = {
    "Spirit of Zanza",
    "Rumsey Rum Black Label",
    "Kreeg's Stout Beatdown",
    "Health II", --Elixir of Fortitude
    "Greater Intellect",
    "Dreamshard Elixir",
    "Medivh's Merlot Blue Label",
    "Danonzo's Tel'Abim Medley",
    "Infallible Mind", --Cerebral Cortex Compound
    "Mana Regeneration", --Mageblood Potion
    "Nightfin Soup",
    "Brilliant Mana Oil",
    "Well Fed";
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
  "Distilled Wisdom", --Flask of Distilled Wisdom
  "Supreme Power", --Flask of Supreme Power
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
  -- Handle both backslashes and forward slashes (Lua 5.0 compatible: string.find + string.sub)
  local s, e = string.find(path, "[^/\\]+$")
  local filename = s and string.sub(path, s, e)
  if filename then
    return string.lower(filename)
  end
  return string.lower(path)
end

-- Helper: Get spell icon/texture by spell ID
-- On Turtle WoW 1.12 there is no reliable cross-class spell icon lookup.
-- Texture-based detection is handled elsewhere by scanning active buffs on units.
local function GetSpellIconByID(spellID)
  return nil
end

-- Helper: Compatibility wrapper for spell name lookup (1.12 path only)
-- GetSpellName only works for spells in the player's own spellbook.
-- Cross-class buffs are resolved when they appear active on raid units.
local function GetSpellNameByID(spellID)
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

-- Public method: force re-resolution of localized name lists on next check.
-- Useful if BUFF_REQUIREMENTS or ROLE_CONSUMABLES are modified at runtime.
function GuildRoll_BuffCheck:InvalidateResolvedLists()
  localizedNamesResolved = false
end

-- Module-level cache for buff-tag-to-provider-class lookup (used by BuildBuffTagProviderClass)
local buffTagProvider = nil

-- Module-level raid class lookup (reset at the start of each OnTooltipUpdate call)
local raidClassByName = nil

-- Helper: return class-colored player name using Babble-Class (BC) for color lookup.
-- BC is optional; if unavailable, player names are returned uncolored.
-- raidClassByName must be reset before each full tooltip rebuild.
local function coloredPlayer(entry)
  local playerName = tostring(entry.player or "<unknown>")
  if not BC then return playerName end
  local class = entry.class
  if not class then
    if not raidClassByName then
      raidClassByName = {}
      for i = 1, GetNumRaidMembers() do
        local rname, _, _, _, rclass = GetRaidRosterInfo(i)
        if rname then raidClassByName[rname] = rclass end
      end
    end
    class = raidClassByName[entry.player]
  end
  if class then
    return C:Colorize(BC:GetHexColor(class), playerName)
  end
  return playerName
end

-- Helper: build a map from short tag -> providerClass, derived from BUFF_REQUIREMENTS and BUFF_SHORT_NAMES
local function BuildBuffTagProviderClass()
  if buffTagProvider then return buffTagProvider end
  buffTagProvider = {}
  for providerClass, buffList in pairs(BUFF_REQUIREMENTS) do
    for _, buffName in ipairs(buffList) do
      local shortTag = BUFF_SHORT_NAMES[buffName]
      if shortTag and not buffTagProvider[shortTag] then
        buffTagProvider[shortTag] = providerClass
      end
    end
  end
  return buffTagProvider
end

-- Helper: colorize each semicolon-separated tag in missingList by its provider class color
local function ColorizeMissingTags(missingList)
  if not BC then return missingList end
  local tagMap = BuildBuffTagProviderClass()
  local parts = {}
  for tag in string.gmatch(missingList, "([^;]+)") do
    tag = string.gsub(tag, "^%s*(.-)%s*$", "%1")
    local providerClass = tagMap[tag]
    if providerClass then
      table.insert(parts, C:Colorize(BC:GetHexColor(providerClass), tag))
    else
      table.insert(parts, tag)
    end
  end
  if table.getn(parts) == 0 then return missingList end
  return table.concat(parts, ";")
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

-- Helper: Get short name for a missing buff from a provider class
-- Returns the short name of the first buff in that class's buff list
local function GetShortNameForClass(className)
  if not className or not BUFF_REQUIREMENTS[className] then
    return className
  end
  
  local buffList = BUFF_REQUIREMENTS[className]
  if buffList and buffList[1] then
    local firstBuffName = buffList[1]
    return BUFF_SHORT_NAMES[firstBuffName] or firstBuffName
  end
  
  return className
end

-- Helper: Get list of missing paladin blessings for a unit
-- Returns the short names of missing blessings based on required count
local function GetMissingPaladinBlessings(unit, requiredBlessings)
  local blessings = {}
  local blessingTypes = {
    ["Might"] = "Might",
    ["Wisdom"] = "Wisdom",
    ["Kings"] = "Kings",
    ["Light"] = "Lights",
    ["Salvation"] = "Salv",
    ["Sanctuary"] = "Sanc",
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
  
  -- Count how many blessings the player has
  local hasCount = 0
  for _, _ in pairs(blessings) do
    hasCount = hasCount + 1
  end
  
  -- If player has enough blessings, return empty list
  if hasCount >= requiredBlessings then
    return {}
  end
  
  -- Otherwise, return list of missing blessing types (up to the required amount)
  local missing = {}
  for bType, shortName in pairs(blessingTypes) do
    if not blessings[bType] then
      table.insert(missing, shortName)
    end
  end
  
  return missing
end

-- Helper: Get priest buff info for a unit.
-- Returns count (number of distinct buff types present) and missingList (array of short names for missing types).
-- Priest has 3 buff types: Fortitude (Stam), Spirit, Shadow Protection (ShadowProt).
local function GetPriestBuffInfo(unit)
  local priestBuffCategories = {
    ["Fortitude"] = "Stam",
    ["Spirit"] = "Spirit",
    ["Shadow Protection"] = "ShadowProt",
  }
  local buffTypes = {}

  for i = 1, 32 do
    local buffTexture = UnitBuff(unit, i)
    if not buffTexture then break end

    local buffName = GetBuffName(unit, i)
    if buffName then
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
  local missing = {}
  for buffType, shortName in pairs(priestBuffCategories) do
    if buffTypes[buffType] then
      count = count + 1
    else
      table.insert(missing, shortName)
    end
  end
  return count, missing
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
    local name, _, subgroup, _, class = GetRaidRosterInfo(i)
    local unit = "raid" .. i
    
    local missingBuffs = {}
    local missingCount = 0
    
    -- Check priest buffs (requires all 3 buff types)
    if providers["PRIEST"] then
      local _, missingPriestBuffs = GetPriestBuffInfo(unit)
      for _, shortName in ipairs(missingPriestBuffs) do
        table.insert(missingBuffs, shortName)
        missingCount = missingCount + 1
      end
    end
    
    -- Check regular buffs (non-paladin, non-priest) using HasAnyBuffByClass
    for providerClass, _ in pairs(providers) do
      if providerClass ~= "PALADIN" and providerClass ~= "PRIEST" then
        local hasBuff, matchedBuff = HasAnyBuffByClass(unit, providerClass)
        if not hasBuff then
          local shortName = GetShortNameForClass(providerClass)
          table.insert(missingBuffs, shortName)
          missingCount = missingCount + 1
        end
      end
    end
    
    -- Check paladin blessings
    if providers["PALADIN"] and requiredBlessings > 0 then
      local missingBlessings = GetMissingPaladinBlessings(unit, requiredBlessings)
      for _, shortName in ipairs(missingBlessings) do
        table.insert(missingBuffs, shortName)
        missingCount = missingCount + 1
      end
    end
    
    -- Only add to report if player has missing buffs
    if missingCount > 0 then
      allOk = false
      table.insert(report, {
        player = name,
        class = class,
        group = subgroup or 0,
        missingCount = missingCount,
        totalRequired = totalRequired,
        missingList = table.concat(missingBuffs, ";")
      })
    end
  end
  
  table.sort(report, function(a, b)
    if a.group ~= b.group then
      return a.group < b.group
    end
    return (a.player or "") < (b.player or "")
  end)
  
  self:ShowReport(report, "Buff Check", allOk)
  self:Refresh()
end

function GuildRoll_BuffCheck:CheckConsumes()
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
    StaticPopupDialogs["GUILDROLL_CONSUMES_AWARD_EP"].text = L["All members have required consumes. Award EP to raid?"] or "All members have required consumes. Award EP to raid?"
    StaticPopup_Show("GUILDROLL_CONSUMES_AWARD_EP")
  else
    self:ShowReport(report, "Consumables Check", allOk)
  end

  self:Refresh()
end

function GuildRoll_BuffCheck:CheckFlasks()
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
        missing = "No Flask",
        type = "flask"
      })
    end
  end
  
  if allOk then
    StaticPopupDialogs["GUILDROLL_FLASKS_AWARD_EP"].text = L["All members have required flasks. Award EP to raid?"] or "All members have required flasks. Award EP to raid?"
    StaticPopup_Show("GUILDROLL_FLASKS_AWARD_EP")
  else
    self:ShowReport(report, "Flasks Check", allOk)
  end

  self:Refresh()
end

function GuildRoll_BuffCheck:ShowReport(report, title, allOk)
  self._currentReport = report
  self._reportTitle = title
  self._reportAllOk = allOk
  -- Toggle(true) with forceShow=true calls Refresh() instead of re-attaching the tablet,
  -- so the detached window updates in-place. This was intentionally kept after PR #213 was
  -- reverted: calling Detach+Refresh directly caused the window to re-open unexpectedly
  -- when the tablet was already attached. Toggle(true) handles the attached/detached
  -- distinction correctly.
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

-- AddSpellIDs removed: use BUFF_REQUIREMENTS table directly.

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
  -- Create the scan tooltip eagerly so it's ready before any buff scan
  if not self._scanTooltip then
    self._scanTooltip = CreateFrame("GameTooltip", "GuildRollBuffCheckTooltip", UIParent, "GameTooltipTemplate")
    self._scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
  end
  if not T:IsRegistered("GuildRoll_BuffCheck") then
    T:Register("GuildRoll_BuffCheck",
      "children", function()
        self:OnTooltipUpdate()
      end,
      "showTitleWhenDetached", true,
      "showHintWhenDetached", true,
      "cantAttach", true,
      "menu", function()
        GuildRoll:SafeDewdropAddLine(
          "text", L["Refresh"],
          "tooltipText", L["Refresh window"],
          "func", function() self:Refresh() end
        )
        GuildRoll:SafeDewdropAddLine(
          "text", L["Close window"],
          "tooltipText", L["Close this window"],
          "func", function()
            pcall(function() D:Close() end)
            local frame = GuildRoll:FindDetachedFrame("GuildRoll_BuffCheck")
            if frame and frame.Hide then frame:Hide() end
          end
        )
      end
    )
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

  -- Reset the per-call raid roster cache for coloredPlayer
  raidClassByName = nil

  if isBuffFormat then
    local cat = T:AddCategory(
      "columns", 3,
      "text",  C:Orange(L["Buff"] or "Buff"),          "child_justify",  "LEFT",
      "text2", C:Orange(L["Missing"] or "Missing"),    "child_justify2", "CENTER",
      "text3", C:Orange(L["PlayerGroup"] or "Player(group)"), "child_justify3", "LEFT"
    )

    if allOk or table.getn(report) == 0 then
      cat:AddLine("text", C:Green(L["BuffCheck_AllOk"] or "All members have all buffs!"), "text2", "", "text3", "")
      T:SetHint(L["BuffCheck_AllOkHint"] or "Buff Check: all OK")
      return
    end

    -- Build pivot: buffShortName -> {count, players[], providerClass}
    local buffRows = {}
    local buffOrder = {}

    for i = 1, table.getn(report) do
      local entry = report[i]
      if entry.missingList and entry.missingList ~= "" then
        local list = entry.missingList
        local pos = 1
        local len = string.len(list)
        while pos <= len do
          local sep = string.find(list, ";", pos, true)
          local buffName
          if sep then
            buffName = string.sub(list, pos, sep - 1)
            pos = sep + 1
          else
            buffName = string.sub(list, pos)
            pos = len + 1
          end
          if buffName and buffName ~= "" then
            if not buffRows[buffName] then
              buffRows[buffName] = {
                count = 0,
                players = {},
                providerClass = BUFF_SHORT_TO_CLASS[buffName] or "UNKNOWN",
              }
              table.insert(buffOrder, buffName)
            end
            buffRows[buffName].count = buffRows[buffName].count + 1
            table.insert(buffRows[buffName].players, {
              name  = entry.player,
              group = entry.group or 0,
              class = NormalizeClassToken(entry.class or ""),
            })
          end
        end
      end
    end

    -- Sort buffOrder by count descending, then alphabetically
    table.sort(buffOrder, function(a, b)
      local ca = buffRows[a] and buffRows[a].count or 0
      local cb = buffRows[b] and buffRows[b].count or 0
      if ca ~= cb then return ca > cb end
      return a < b
    end)

    local numRaid = GetNumRaidMembers()
    local halfRaid = math.floor((numRaid > 0 and numRaid or MAX_RAID_SIZE) / 2)

    for i = 1, table.getn(buffOrder) do
      local buffLabel = buffOrder[i]
      local row = buffRows[buffLabel]

      -- Column 1: [ClassName] BuffLabel, colored by provider class
      local provClass = row.providerClass
      local col = PROVIDER_CLASS_COLORS[provClass]
      local buffText
      if col then
        local displayClass = PROVIDER_CLASS_DISPLAY[provClass] or provClass
        local label = string.format("[%s] %s", displayClass, buffLabel)
        buffText = string.format("|cff%02x%02x%02x%s|r",
          math.floor(col[1] * 255),
          math.floor(col[2] * 255),
          math.floor(col[3] * 255),
          label)
      else
        buffText = string.format("[%s] %s", provClass, buffLabel)
      end

      -- Column 2: count, red if > half raid, orange otherwise
      local countText
      if row.count > halfRaid then
        countText = C:Red(tostring(row.count))
      else
        countText = C:Orange(tostring(row.count))
      end

      -- Column 3: "Name(G) Name(G) ..." sorted by group then name, each colored by class
      table.sort(row.players, function(a, b)
        if a.group ~= b.group then return a.group < b.group end
        return (a.name or "") < (b.name or "")
      end)

      local playerParts = {}
      local totalPlayers = table.getn(row.players)
      local displayCount = totalPlayers
      if displayCount > BUFF_PLAYER_DISPLAY_LIMIT then
        displayCount = BUFF_PLAYER_DISPLAY_LIMIT
      end
      for j = 1, displayCount do
        local p = row.players[j]
        local pColor = CLASS_COLORS[p.class]
        local shortName = (p.name and p.name ~= "" and string.sub(p.name, 1, 3)) or "?"
        local pText = string.format("%s(%d)", shortName, p.group)
        if pColor then
          pText = string.format("|cff%02x%02x%02x%s|r",
            math.floor(pColor[1] * 255),
            math.floor(pColor[2] * 255),
            math.floor(pColor[3] * 255),
            pText)
        end
        table.insert(playerParts, pText)
      end
      if totalPlayers > BUFF_PLAYER_DISPLAY_LIMIT then
        local overflow = totalPlayers - BUFF_PLAYER_DISPLAY_LIMIT
        table.insert(playerParts, string.format("|cffaaaaaa+%d more|r", overflow))
      end

      local playerStr = table.concat(playerParts, "  ")

      cat:AddLine(
        "text",  buffText,
        "text2", countText,
        "text3", playerStr
      )
    end

    local missingPlayers = table.getn(report)
    T:SetHint(string.format(L["BuffCheck_Hint"] or "Buff Check: %d player(s) missing buffs", missingPlayers))
    return
  end
  
  -- Consumables report format
  if isConsumeFormat then
    local cat = T:AddCategory(
      "columns", 2,
      "text", C:Yellow(L["Name"] or "Name"),
      "text2", C:Yellow(L["Details"] or "Details")
    )
    for _, entry in ipairs(report) do
      local status = tostring(entry.missing or "")
      local statusColor = C:Red(status)
      -- Use yellow when partial (contains "/") or contains number less than required
      if string.find(status, "/") or string.find(status, "%d") then
        statusColor = C:Orange(status)
      end
      cat:AddLine(
        "text", coloredPlayer(entry),
        "text2", statusColor
      )
    end
    return
  end
  
  -- Flasks report format (fallback generic)
  if isFlaskFormat then
    local cat = T:AddCategory(
      "columns", 2,
      "text", C:Yellow(L["Name"] or "Name"),
      "text2", C:Yellow(L["Details"] or "Details")
    )
    for _, entry in ipairs(report) do
      local status = tostring(entry.missing or "Flask")
      local statusColor = C:Red(status)
      cat:AddLine(
        "text", coloredPlayer(entry),
        "text2", statusColor
      )
    end
    return
  end
  
  -- Generic fallback: show whatever fields exist
  local cat = T:AddCategory("columns", 2, "text", C:Yellow(L["Name"] or "Name"), "text2", C:Yellow(L["Info"] or "Info"))
  for _, entry in ipairs(report) do
    local info = entry.missingList or entry.missing or tostring(entry.missingCount or "")
    cat:AddLine("text", coloredPlayer(entry), "text2", tostring(info))
  end
end
