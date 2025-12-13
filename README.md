# GuildEP

EP rolls - Basic Effort Points manager for TurtleWoW

## Features

GuildEP (formerly GuildRoll) is a World of Warcraft addon for managing Effort Points (EP) in guilds. It provides:
- EP tracking and management
- Raid EP awards
- Guild standings and logs
- Admin controls for guild officers

## Local Guild Master Override

GuildEP includes a feature to grant admin permissions to specific characters locally, without requiring server-side guild permissions. This is useful for testing, development, or special scenarios where you need admin access without actual officer notes permissions.

### How to Use the Override

#### Method 1: Via SavedVariables (Persistent)

Add the following to your `SavedVariables.lua` file (located in `WTF/Account/YourAccount/SavedVariables/GuildRoll.lua`):

```lua
GuildRoll_ForcedGuildMasters = { ["YourCharacterName"] = true }
```

**Multiple characters:**
```lua
GuildRoll_ForcedGuildMasters = { ["CharName1"] = true, ["CharName2"] = true }
```

After editing the file, reload the game or use `/reload` in-game.

#### Method 2: Via In-Game Chat Command (Quick Test)

You can also set this variable directly in-game using a chat command:

```
/run GuildRoll_ForcedGuildMasters = { ["YourCharacterName"] = true }
```

Then reload the UI:
```
/reload
```

**Note:** This method requires you to `/reload` after setting the variable. If you don't reload, the change won't persist between sessions unless the SavedVariables file is written before you log out.

### Verifying the Override

After setting up the override and reloading, you can verify it's working:

```
/run print(GuildRoll:IsAdmin())
```

This should print `1` (true) if your character name is in the forced guild masters list.

### Important Notes

- **Case-insensitive matching**: Character names are compared case-insensitively, so "CharName", "charname", and "CHARNAME" are all treated the same.
- **Realm suffix stripping**: If you play on a server with realm suffixes (e.g., "CharName-RealmName"), the addon automatically strips the realm suffix before comparison. You can use either "CharName" or "CharName-RealmName" in the override table.
- **Default fallback**: If `GuildRoll_ForcedGuildMasters` is not defined, the addon defaults to `{ ["Lyrandel"] = true }` for backward compatibility.
- **Priority**: The addon first checks for actual guild permissions (`CanEditOfficerNote()` or `IsGuildLeader()`). The forced guild masters list is only used as a fallback.

### Quick Test Without Modifying SavedVariables

For a quick test without editing files:

1. In-game, type:
   ```
   /run GuildRoll_ForcedGuildMasters = { ["YourCharacterName"] = true }
   ```

2. Reload the UI:
   ```
   /reload
   ```

3. Verify admin status:
   ```
   /run print(GuildRoll:IsAdmin())
   ```

If it prints `1`, the override is working correctly!

## Credits

- **Author**: RollingSmile
- **Website**: https://github.com/RollingSmile/GuildEP
- **Credits**: Roadblock, Qcat, Excinerus

## License

This addon is provided as-is for use with World of Warcraft 1.12 (Vanilla).
