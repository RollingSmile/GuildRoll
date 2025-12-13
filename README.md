# GuildEP

EP rolls - Basic Effort Points manager for TurtleWoW

## Features

GuildEP (formerly GuildRoll) is a World of Warcraft addon for managing Effort Points (EP) in guilds. It provides:
- EP tracking and management
- Raid EP awards
- Guild standings and logs
- Admin controls for guild officers

## Admin Permissions

GuildEP determines admin permissions exclusively from server-side guild permissions. Admin access is granted if you have either:
- **Officer Note Edit Permission**: Can edit officer notes (`CanEditOfficerNote()`)
- **Guild Leader**: Are the guild leader (`IsGuildLeader()`)

### Verifying Admin Status

You can check your current admin status in-game:

```
/run print(GuildRoll:IsAdmin())
```

This will print `1` (true) if you have admin permissions, or `nil`/`false` otherwise.

**Note**: Admin permissions are determined solely by your actual guild permissions on the server. There are no local overrides or forced permissions.

## Credits

- **Author**: RollingSmile
- **Website**: https://github.com/RollingSmile/GuildEP
- **Credits**: Roadblock, Qcat, Excinerus

## License

This addon is provided as-is for use with World of Warcraft 1.12 (Vanilla).
