# Legacy Code Archive

This document archives large commented/legacy code blocks extracted from root files during the conservative cleanup effort. These code blocks are preserved here for reference but have been identified as no longer active in the codebase.

**Scope:** Root files only (Libs excluded)  
**Date:** 2025-12-08

---

## 1. Unused Library Imports (guildroll.lua, lines 7-8)

These libraries were commented out, indicating they are no longer used:

```lua
--local DF = AceLibrary("Deformat-2.0")
--local G = AceLibrary("Gratuity-2.0")
```

**Context:** These appear to be unused Ace library imports that were previously commented out.

---

## 2. Removed Reserve Feature (guildroll.lua, lines 24-25)

The reserve channel feature was removed:

```lua
-- reservechan = "Reserves", -- Feature removed
-- reserveanswer = "^(%+)(%a*)$", -- Feature removed
```

**Context:** This was part of the VARS table and explicitly marked as "Feature removed".

---

## 3. pfUI Skin Integration (guildroll.lua, lines 544-549)

Legacy pfUI tooltip skinning code:

```lua
-- if pfUI loaded, skin the extra tooltip
--if not IsAddOnLoaded("pfUI-addonskins") then
--  if (pfUI) and pfUI.api and pfUI.api.CreateBackdrop and pfUI_config and pfUI_config.tooltip and pfUI_config.tooltip.alpha then
--    pfUI.api.CreateBackdrop(GuildRoll.extratip,nil,nil,tonumber(pfUI_config.tooltip.alpha))
--  end
--end
```

**Context:** This code attempted to apply pfUI skinning to the extra tooltip. It's commented out, likely because pfUI handling should be conditional or handled differently.

**Recommendation:** This is a candidate for conditional pfUI handling in future cleanup iterations.

---

## 4. Zone-based Award Multipliers (guildroll.lua, lines 1419-1443)

Large commented block for zone-based award point calculations in `suggestedAwardMainStanding()`:

```lua
-- local currentTier, zoneEN, zoneLoc, checkTier, multiplier
-- local inInstance, instanceType = IsInInstance()
-- if (inInstance == nil) or (instanceType ~= nil and instanceType == "none") then
--   currentTier = "T1.5"   
-- end
-- if (inInstance) and (instanceType == "raid") then
--   zoneLoc = GetRealZoneText()
--   if (BZ:HasReverseTranslation(zoneLoc)) then
--     zoneEN = BZ:GetReverseTranslation(zoneLoc)
--     checkTier = raidZones[zoneEN]
--     if (checkTier) then
--       currentTier = checkTier
--     end
--   end
-- end
-- if not currentTier then 
--   return GuildRoll.VARS.baseawardpoints
-- else
--   multiplier = zone_multipliers[GuildRoll_progress][currentTier]
-- end
-- if (multiplier) then
--   return multiplier*GuildRoll.VARS.baseawardpoints
-- else
--   return GuildRoll.VARS.baseawardpoints
-- end
```

**Context:** This code calculated award points based on the raid zone tier. The function now simply returns `GuildRoll.VARS.baseawardpoints`.

**Note:** The referenced tables (`raidZones` and `zone_multipliers`) are still active in the codebase and would be needed if this code were to be re-enabled.

---

## 5. Zone-based Award Multipliers (Duplicate) (guildroll.lua, lines 1454-1478)

Identical commented block in `suggestedAwardAuxStanding()`:

```lua
-- local currentTier, zoneEN, zoneLoc, checkTier, multiplier
-- local inInstance, instanceType = IsInInstance()
-- if (inInstance == nil) or (instanceType ~= nil and instanceType == "none") then
--   currentTier = "T1.5"   
-- end
-- if (inInstance) and (instanceType == "raid") then
--   zoneLoc = GetRealZoneText()
--   if (BZ:HasReverseTranslation(zoneLoc)) then
--     zoneEN = BZ:GetReverseTranslation(zoneLoc)
--     checkTier = raidZones[zoneEN]
--     if (checkTier) then
--       currentTier = checkTier
--     end
--   end
-- end
-- if not currentTier then 
--   return GuildRoll.VARS.baseawardpoints
-- else
--   multiplier = zone_multipliers[GuildRoll_progress][currentTier]
-- end
-- if (multiplier) then
--   return multiplier*GuildRoll.VARS.baseawardpoints
-- else
--   return GuildRoll.VARS.baseawardpoints
-- end
```

**Context:** Same zone multiplier logic, duplicated in the auxiliary standing award function.

---

## 6. Commented Function Call (alts.lua, line 86)

```lua
--ChatFrame_SendTell(name)
```

**Context:** A commented-out click handler in `OnClickItem()` function that would have initiated a tell/whisper to the clicked player.

---

## 7. Commented Function Parameters (alts.lua, lines 112-113)

```lua
"text2", altstring--,
--"func", "OnClickItem", "arg1", self, "arg2", main
```

**Context:** The click function registration was commented out in the tooltip line addition.

---

## Notes

- **No functional code was removed** - these are all pre-existing commented blocks
- All code blocks listed here were already commented out or marked as removed
- This archive preserves historical context without impacting functionality
- Localization strings and migrations are NOT included in this cleanup (per plan)
