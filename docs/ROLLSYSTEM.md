# Roll System Documentation

## Overview

This document describes the new roll tracking system skeleton introduced in the LootSystemFix branch. This is the first iteration that provides the infrastructure for enhanced roll management.

## New Modules

### RollTracker.lua
Central storage and sorting logic for rolls.

**API:**
- `RollTracker:new(priority)` - Create new tracker instance with optional custom priority map
- `RollTracker:add(roll)` - Add a roll entry and auto-sort
- `RollTracker:getAll()` - Get all rolls in sorted order
- `RollTracker:clear()` - Clear all rolls
- `RollTracker:sort()` - Re-sort rolls by priority, value, and timestamp

**Default Priority:**
1. SR (Soft Reserve)
2. MS (Main Spec)
3. OS (Off Spec)
4. Tmog (Transmog)
5. Unknown

### ChatParser.lua
Parses chat messages and normalizes roll data.

**API:**
- `ChatParser:parse(msg)` - Parse a chat message and return normalized roll entry or nil

**Supported Patterns:**
- Built-in WoW rolls: "Player rolls 42 (1-100)"
- Addon SR rolls: "[S] [Player]: I rolled Cumulative SR 169 - 268 with 48 EP + 100 from SR +20 for 3 consecutive weeks"
- Addon SR rolls: "[S] [Player]: I rolled SR "169 - 268""
- Addon MS rolls: "[S] [Player]: I rolled MS "101 - 200""

### RollTableUI.lua
UI frame displaying rolls in a table format.

**API:**
- `RollTableUI:create()` - Create the frame (lazy init)
- `RollTableUI:show()` - Show the roll table
- `RollTableUI:hide()` - Hide the roll table
- `RollTableUI:refresh(rolls, srLookup)` - Update the table with new roll data

**Columns:**
- Player - Player name
- SR - SR flag if player has soft reserve
- Roll - Roll value
- Type - Roll type (SR, MS, OS, etc.)

### CsvSRLoader.lua
Minimal CSV parser for soft reserve data.

**API:**
- `CsvSRLoader:parse(csvText)` - Parse CSV text and return lookup table

**Format:**
```
PlayerName,Item1|Item2|Item3
AnotherPlayer,ItemA|ItemB
```

## Integration Points

### RollWithEP.lua
The main integration points added:
- Tracker initialization: `RollWithEP.tracker = RollTracker:new()`
- Parser integration: `RollWithEP.parser = ChatParser`
- UI hook: `RollWithEP.ShowRollTable()` function to open the new UI
- Chat event registration for parsing rolls

### announce_loot.lua
Modified to call `GuildRoll.RollTableUI_ShowLootUI(lootItems)` if available.

## Testing the Skeleton

### Slash Command
Use the command `/gr rolltable` to manually open the roll table UI (if implemented).

### Test Messages
Try these sample messages in chat to verify parsing:

1. **Built-in roll:**
   ```
   Lyrandel rolls 42 (1-100)
   ```

2. **Cumulative SR roll:**
   ```
   [S] [Lyrandel]: I rolled Cumulative SR 169 - 268 with 48 EP + 100 from SR +20 for 3 consecutive weeks
   ```

3. **Simple SR roll:**
   ```
   [S] [Lyrandel]: I rolled SR "169 - 268"
   ```

4. **MS roll:**
   ```
   [S] [Lyrandel]: I rolled MS "101 - 200"
   ```

### Verification Steps
1. Load the addon in WoW
2. Check for Lua errors on load
3. Send test messages in chat
4. Verify rolls are captured by the tracker
5. Open the RollTable UI to see parsed rolls
6. Verify sorting by priority and roll value

## Known Limitations (This PR)

This is a skeleton implementation. The following features are NOT yet complete:
- Full addon button pattern parsing (only basic patterns included)
- Complete menu integration (Clear roll/Tie roll removal is partial)
- CSV import UI
- Polish and error handling
- Complete soft reserve integration
- Tie-breaking with new system

## Next Steps

Future PRs will:
1. Complete removal of "Clear roll" and "Ask Tie Roll" menu entries
2. Implement full "Request rolls" menu opening the new RollTable
3. Add Members menu structure with "DE/Bank" in Special options
4. Enhance ChatParser with all addon button patterns
5. Add CSV import UI for soft reserves
6. Polish RollTableUI with better formatting and interactivity
7. Add comprehensive error handling
8. Integrate roll tracking with existing EP system

## Development Notes

### Module Loading Pattern
In WoW 1.12 (Turtle WoW), there's no require() function. Modules use the return pattern:
```lua
-- Module file
local Module = {}
-- ... module code ...
return Module
```

Loading is done via:
```lua
-- In main file or init
local Module = dofile("path/to/Module.lua")
```

However, in this addon structure, we use a simpler pattern where modules are loaded by the TOC file order and assign to global namespace or addon namespace.

### Testing Locally
To test changes locally:
1. Copy addon to WoW AddOns folder
2. Restart WoW or reload UI with `/reload`
3. Check for errors with `/console scriptErrors 1`
4. Use debug prints to verify module loading

