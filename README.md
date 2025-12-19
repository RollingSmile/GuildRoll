# GuildRoll

EP rolls - Basic Effort Points manager for TurtleWoW

## Features

GuildRoll is a World of Warcraft addon for managing Effort Points (EP) in guilds. It provides:
- EP tracking and management
- Guild member/Raid EP awards
- Guild standings, personal Log and AdminsLog
- Admin controls are given to Guild Officers and Guild Leader

## EP Format Migration

GuildRoll now supports migrating from the legacy `{EP:GP}` format to the new EP-only `{EP}` format.

### Admin Command: `/groll nogp`

Officers and Guild Leaders can migrate all officer notes from `{EP:GP}` to `{EP}` format using:

```
/groll nogp
```

This command will:
1. Show a confirmation popup
2. Scan all guild member officer notes
3. Migrate notes from `{EP:GP}` → `{EP}` format
4. Backup GP values to `GuildRoll_oldGP` SavedVariable
5. Use throttled writes (0.25s between updates) to avoid API limits
6. Show migration progress and completion status

### GP Backup

All GP values removed during migration are backed up to the `GuildRoll_oldGP` SavedVariable with:
- GP value
- Timestamp
- Original officer note
- New officer note

This allows for future rollback or analysis if needed.

### Backward Compatibility

The parser continues to read both formats:
- `{EP:GP}` - Legacy format with GP tracking
- `{EP}` - New EP-only format

All new writes use the `{EP}` format exclusively.
