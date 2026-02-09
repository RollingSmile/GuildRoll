# GuildRoll Debugging Guide

## Recent Changes - Enhanced Debug Output

We've added comprehensive debug messages to track every step of addon loading and standings opening.

## What to Look For When Loading the Addon

### Success Messages (Green) - In Order

When you load into the game, you should see these messages in your chat window:

1. **"[EPGP] epgp.lua loading..."** - epgp.lua file started loading
2. **"[EPGP] Libraries loaded successfully"** - All libraries for epgp.lua loaded
3. **"[EPGP] get_ep_v3 function defined successfully"** - The critical function is defined
4. **"[EPGP] epgp.lua loaded completely!"** - epgp.lua finished loading
5. **"[GuildRoll] standings.lua libraries loaded successfully"** - All libraries for standings loaded
6. **"[GuildRoll] GuildRoll_standings module created successfully"** - Standings module created

If you see all 6 green messages, all modules loaded successfully!

### When You Click to Open Standings

You should then see:
1. **"[GuildRoll] OnClick: Attempting to toggle standings..."** - Click was detected
2. **"[GuildRoll] GuildRoll_standings and Toggle exist, calling..."** - Module and function exist
3. **"[Standings] Toggle called, forceShow=..."** - Toggle function started
4. **"[Standings] Currently attached/Not attached..."** - Current state
5. Action taken (detaching/attaching/refreshing)

### Error Messages (Red)

If you see red error messages, they will tell you exactly what failed:

**epgp.lua loading errors:**
- **"[EPGP] Error in initial debug: ..."** - Problem with initial message
- **"[EPGP] Error calling aceLocale:new: ..."** - Locale initialization failed
- **"[EPGP] Error loading libraries: ..."** - General library loading failure

**standings.lua loading errors:**
- **"ERROR: Tablet-2.0 not loaded in standings.lua"** - Missing Tablet library
- **"ERROR: Dewdrop-2.0 not loaded in standings.lua"** - Missing Dewdrop library
- **"ERROR: Crayon-2.0 not loaded in standings.lua"** - Missing Crayon library
- **"ERROR: Babble-Class-2.2 not loaded in standings.lua"** - Missing Babble-Class library
- **"ERROR: AceLocale-2.2 not loaded in standings.lua"** - Missing AceLocale library
- **"ERROR: Localization not initialized in standings.lua"** - Locale initialization failed

**Standings opening errors:**
- **"[GuildRoll] ERROR: GuildRoll_standings module not available"** - Module doesn't exist
- **"[Standings] Error in Toggle: ..."** - Error during Toggle execution

## Diagnostic Scenarios

### Scenario 1: No [EPGP] messages appear
**Meaning:** epgp.lua is not being loaded at all
**Possible causes:**
- .toc file is incorrect
- File name is wrong
- File has syntax error preventing any execution

**What to check:**
- Look for ANY error messages about epgp.lua
- Check if epgp.lua exists in Interface/AddOns/guildroll/
- Check guildroll.toc to ensure epgp.lua is listed

### Scenario 2: [EPGP] messages show errors
**Meaning:** epgp.lua started loading but hit an error
**Action:** Read the error message - it tells you exactly what failed
**Common issues:**
- Library not available (missing Libs folder)
- Permission issue
- Conflicting addon

### Scenario 3: All [EPGP] messages green, but get_ep_v3 still nil
**Meaning:** Function is defined but not accessible
**Possible causes:**
- Scope issue (function defined in wrong scope)
- GuildRoll object not initialized
- Load order problem

**What to try:**
- Take screenshot of ALL messages
- Share the exact error line number
- Check if other GuildRoll functions work

### Scenario 4: Standings module created but doesn't show
**Meaning:** Module loaded but Toggle isn't working
**Check for:**
- "[GuildRoll] OnClick: Attempting to toggle standings..." message when you click
- "[Standings] Toggle called..." message
- "[Standings] Error in Toggle: ..." error message

**If Toggle is called but nothing shows:**
- Tablet-2.0 attach/detach may be failing
- Frame may be created but hidden
- Frame may be off-screen

## Testing Steps

1. **Load the addon** - Watch for the 6 green success messages
2. **Take a screenshot** of all messages that appear
3. **Try opening Standing frame**:
   - Click FuBar icon (left-click)
   - Watch for OnClick and Toggle debug messages
   - Take screenshot of any error messages
4. **Try EP buttons** - Watch for get_ep_v3 error
5. **Share screenshots** with all messages visible

## What Changed

### Latest Changes (This Version)

**epgp.lua debug enhancements:**
- Wrapped ALL operations in error handlers
- Added message at start, middle, and end of loading
- [EPGP] prefix on all messages
- Specific error messages for each failure point

**standings.lua debug enhancements:**
- Added debug messages in Toggle function
- Shows what Toggle is doing step-by-step
- Shows current attach state
- Error reporting for Toggle failures

**guildroll.lua debug enhancements:**
- Added messages when clicking icon
- Shows if module/Toggle exist before calling
- Clear error messages if module not available

## Expected Successful Output

```
[EPGP] epgp.lua loading...
[EPGP] Libraries loaded successfully
[EPGP] get_ep_v3 function defined successfully
[EPGP] epgp.lua loaded completely!
[GuildRoll] standings.lua libraries loaded successfully
[GuildRoll] GuildRoll_standings module created successfully

(When you click the icon:)
[GuildRoll] OnClick: Attempting to toggle standings...
[GuildRoll] GuildRoll_standings and Toggle exist, calling...
[Standings] Toggle called, forceShow=nil
[Standings] Currently attached, detaching (showing)...
```

After this, the standings frame should appear!

## Still Having Issues?

If you still get errors after these changes:

1. **Take screenshots** showing:
   - All messages when addon loads
   - All messages when you click to open standings
   - The exact error message with line number
2. **Note what you DON'T see**:
   - Missing [EPGP] messages?
   - No OnClick message when you click?
   - Toggle called but no follow-up messages?
3. **Check your addon folder**:
   - Is epgp.lua present?
   - Are all Libs subfolders present?
4. **Share all information** so we can pinpoint the exact issue
