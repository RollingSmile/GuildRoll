# GuildRoll Debugging Guide

## Recent Changes

We've added extensive debug messages to help diagnose loading issues with the refactored addon.

## What to Look For When Loading the Addon

When you load into the game with GuildRoll enabled, you should see these messages in your chat window:

### Success Messages (Green)
1. **"epgp.lua loading..."** - Indicates epgp.lua file started loading
2. **"epgp.lua: get_ep_v3 defined"** - Confirms the get_ep_v3 function was successfully defined
3. **"[GuildRoll] standings.lua libraries loaded successfully"** - All required libraries for standings loaded
4. **"[GuildRoll] GuildRoll_standings module created successfully"** - The standings module was created

If you see all 4 green messages, the addon loaded successfully!

### Error Messages (Red)
If you see any red error messages, they will tell you exactly what failed:

- **"ERROR: Tablet-2.0 not loaded in standings.lua"** - Missing Tablet library
- **"ERROR: Dewdrop-2.0 not loaded in standings.lua"** - Missing Dewdrop library
- **"ERROR: Crayon-2.0 not loaded in standings.lua"** - Missing Crayon library
- **"ERROR: Babble-Class-2.2 not loaded in standings.lua"** - Missing Babble-Class library
- **"ERROR: AceLocale-2.2 not loaded in standings.lua"** - Missing AceLocale library
- **"ERROR: Localization not initialized in standings.lua"** - Locale initialization failed

## Testing the Fixes

### 1. Test Standing Frame
Try opening the Standing frame with:
- Click the GuildRoll FuBar icon (left-click)
- Type `/groll standings` in chat
- Use the menu: Right-click icon → Show Standings

**Expected**: Standing frame should open
**If it fails**: You'll see a red error message telling you which module is missing

### 2. Test EP Commands
Try using the CSR, SR, or EP buttons/commands.

**Expected**: They should work without the `attempt to call method 'get_ep_v3' (a nil value)` error
**If it fails**: You should see an error message earlier in the loading process

## What Changed

### Fix 1: Library Import Pattern (Commits 49e8729)
- Changed how epgp.lua and utils.lua import Ace libraries
- Now uses the same two-step pattern as other working modules:
  1. Get the library object
  2. Check if it exists and has required methods
  3. Call methods with proper error handling
- This prevents failures when calling `:new()` on already-initialized locales

### Fix 2: Better Error Messages (Commit 2c3c6a7)
- standings.lua now uses DEFAULT_CHAT_FRAME for error messages (more reliable)
- Added debug messages to show loading progress
- Added error messages when trying to open standings if module isn't available
- Shows diagnostic info (whether module is nil or Toggle method is nil)

## Troubleshooting

If you still get errors after these fixes:

1. **Check the exact error messages** - They now tell you exactly what's wrong
2. **Take a screenshot** of the chat window showing all messages from addon load
3. **Share the screenshot** so we can see which step is failing
4. **Check your Libs folder** - Make sure all the Ace2 libraries are present:
   - Libs/Tablet-2.0/
   - Libs/Dewdrop-2.0/
   - Libs/Crayon-2.0/
   - Libs/Babble-Class-2.2/
   - Libs/AceLocale-2.2/
   - etc.

## Expected Behavior

After these fixes:
- ✅ All files should load without errors
- ✅ `get_ep_v3` function should be defined and callable
- ✅ Standing frame should open when requested
- ✅ CSR, SR, EP buttons should work
- ✅ Debug messages will clearly indicate what's working or broken
