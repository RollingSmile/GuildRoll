# Conservative Root-Only Cleanup Plan

**Branch:** `cleanup/root-conservative`  
**Target:** `main`  
**Date:** 2025-12-08  
**Status:** Draft PR - Ready for Review

---

## Scope

This is a **conservative, root-only cleanup** effort with the following constraints:

### Included
- **Root files only**: guildroll.lua, alts.lua, logs.lua, standings.lua, roll.lua, migrations.lua, localization.lua, guildroll.toc
- **Documentation only**: Adding CLEANUP_PLAN.md and LEGACY.md
- **Archive legacy code**: Document existing commented/legacy code blocks (see LEGACY.md)

### Explicitly Excluded
- ❌ **Libs directory** - completely untouched
- ❌ **Functional code removals** - no active code is removed
- ❌ **Localization strings** - preserved as-is (internal log strings must be kept)
- ❌ **Migrations** - preserved as-is
- ❌ **Event registrations** - no changes to active event handlers

---

## Changes Made

### Files Added
1. **CLEANUP_PLAN.md** (this file) - documents the cleanup approach, testing, and rollback
2. **LEGACY.md** - archives large commented/legacy code blocks for reference

### Files Modified
- **None** - this is a documentation-only PR

---

## Test Plan

Before merging this PR, perform the following tests:

### 1. Static Analysis
```bash
# Run luacheck on root files only, excluding Libs
luacheck *.lua --exclude-files 'Libs/**'
```

**Expected:** No new errors or warnings compared to main branch

### 2. In-Game Testing

#### Basic Functionality Tests
1. **Load addon**
   - `/console reloadui` or restart WoW
   - Verify addon loads without Lua errors
   
2. **OnEnable/OnDisable**
   - Test addon enable: `/guildroll restart`
   - Verify no Lua errors in chat or error frames

3. **Tablet Windows** (verify all windows open without errors)
   - Standings window: `/guildroll show`
   - Alts window: Verify alts tracking works
   - Logs window: Verify logs display correctly

4. **Event Handlers** (verify critical events fire correctly)
   - `CHAT_MSG_ADDON` - test addon communication (if in guild)
   - `GUILD_ROSTER_UPDATE` - test guild roster refresh
   - Verify no event handler errors in logs

5. **Core Features** (smoke test only)
   - Verify standings display
   - Verify EP/GP tracking (if applicable)
   - Verify roll functionality (basic test)

**Expected:** All features work identically to main branch. No new Lua errors.

### 3. Comparison Test
```bash
# Verify only documentation files were added
git diff main..cleanup/root-conservative --name-only
```

**Expected Output:**
```
CLEANUP_PLAN.md
LEGACY.md
```

---

## Rollback Steps

If issues are discovered after merge:

### Option 1: Revert the Merge Commit
```bash
git revert -m 1 <merge-commit-sha>
git push origin main
```

### Option 2: Remove Documentation Files
```bash
git checkout main
git rm CLEANUP_PLAN.md LEGACY.md
git commit -m "Rollback: Remove cleanup documentation"
git push origin main
```

**Impact:** Minimal - only documentation files are affected. No functional code changes to roll back.

---

## Next Recommended Steps

After this PR is merged, the following cleanup steps are recommended for future iterations:

### 1. Make pfUI Handling Conditional
**File:** guildroll.lua, lines 544-549  
**Action:** Convert commented pfUI code to conditional loading:
```lua
if IsAddOnLoaded("pfUI") and not IsAddOnLoaded("pfUI-addonskins") then
  if pfUI and pfUI.api and pfUI.api.CreateBackdrop and pfUI_config and pfUI_config.tooltip and pfUI_config.tooltip.alpha then
    pfUI.api.CreateBackdrop(GuildRoll.extratip, nil, nil, tonumber(pfUI_config.tooltip.alpha))
  end
end
```
**Risk:** Low - makes existing commented code active only when pfUI is present  
**Testing:** Test with and without pfUI addon loaded

### 2. Add Small Placeholder TODOs in alts.lua
**File:** alts.lua, lines 86, 112-113  
**Action:** Add TODO comments for click handler functionality:
```lua
-- TODO: Consider re-enabling click-to-whisper functionality
-- function GuildRollAlts:OnClickItem(name)
--   ChatFrame_SendTell(name)
-- end
```
**Risk:** None - documentation only  
**Testing:** Not required

### 3. Small logs.lua Clarification
**File:** logs.lua  
**Action:** Add comment clarifying the reverse() function purpose:
```lua
-- Reverse the log array so newest entries appear first in the display
function GuildRoll_logs:reverse(arr)
  -- ... existing code ...
end
```
**Risk:** None - documentation only  
**Testing:** Not required

### 4. Consider Zone Multiplier Removal (Future)
**Files:** guildroll.lua, lines 1419-1443 and 1454-1478  
**Action:** If zone multipliers are permanently disabled, fully remove the commented blocks  
**Risk:** Medium - requires confirmation that feature won't be re-enabled  
**Testing:** Extended in-game testing of award point calculations  
**Prerequisite:** Team decision on whether zone multipliers will be re-enabled

---

## Success Criteria

This PR is ready to merge when:

- [x] CLEANUP_PLAN.md created and reviewed
- [x] LEGACY.md created with accurate code block references
- [ ] Code review completed
- [ ] No new luacheck errors introduced
- [ ] In-game testing completed (OnEnable/OnDisable, Tablet windows, event handlers)
- [ ] No Lua errors detected during testing
- [ ] Verification that only documentation files were added

---

## Notes

- **Conservative approach:** This PR intentionally does NOT remove any code, even commented code
- **Safety first:** Documentation changes only minimize risk of introducing bugs
- **Iterative cleanup:** Future PRs can tackle actual code cleanup with this documentation as reference
- **Team review:** This PR should be reviewed by team before merging to ensure approach is acceptable

---

## References

- **Issue:** Add conservative cleanup artifacts and prepare for review
- **Related PRs:** None (first cleanup PR)
- **Documentation:** See LEGACY.md for archived code block details
