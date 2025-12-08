local L = AceLibrary("AceLocale-2.2"):new("guildroll")

-- Migration 0003: Strip GP from officer notes
-- Converts officer note format from {EP:GP} to {EP}
-- Only runs when executed by Lyrandel

GuildRoll_migration_backup = GuildRoll_migration_backup or {}

function GuildRoll:migration_0003_preview()
  local changes = {}
  local count = 0
  
  for i = 1, GetNumGuildMembers(1) do
    local name, _, _, _, _, _, _, officernote, _, _ = GetGuildRosterInfo(i)
    if officernote then
      -- Match the {EP:GP} pattern (allowing negative numbers)
      local prefix, ep, gp, postfix = string.match(officernote, "^(.-){(%-?%d+):(%-?%d+)}(.*)$")
      if ep and gp then
        local newNote = prefix .. "{" .. ep .. "}" .. postfix
        table.insert(changes, {
          name = name,
          oldNote = officernote,
          newNote = newNote,
          ep = ep,
          gp = gp
        })
        count = count + 1
      end
    end
  end
  
  return changes, count
end

function GuildRoll:migration_0003_apply()
  -- Only Lyrandel can apply this migration
  if UnitName("player") ~= "Lyrandel" then
    self:defaultPrint(L["Migration can only be applied by Lyrandel."])
    return false
  end
  
  if not CanEditOfficerNote() then
    self:defaultPrint(L["You do not have permission to edit officer notes."])
    return false
  end
  
  -- Clear old backups and create new backup
  GuildRoll_migration_backup = {}
  
  local changes, count = self:migration_0003_preview()
  
  if count == 0 then
    self:defaultPrint(L["No officer notes need to be migrated."])
    return true
  end
  
  -- Build a map of changes by name for safer lookup
  local changesByName = {}
  for _, change in ipairs(changes) do
    changesByName[change.name] = change
  end
  
  -- Apply changes by looking up each member by name
  local applied = 0
  for i = 1, GetNumGuildMembers(1) do
    local name, _, _, _, _, _, _, officernote, _, _ = GetGuildRosterInfo(i)
    local change = changesByName[name]
    if change then
      -- Verify the officer note hasn't changed since preview
      if officernote == change.oldNote then
        -- Save backup
        GuildRoll_migration_backup[name] = change.oldNote
        
        -- Apply new note
        GuildRosterSetOfficerNote(i, change.newNote, true)
        applied = applied + 1
      end
    end
  end
  
  self:defaultPrint(string.format(L["Migrated %d officer notes from {EP:GP} to {EP} format."], applied))
  self:defaultPrint(L["Backup saved. Use /gpmigrate rollback to restore."])
  
  return true
end

function GuildRoll:migration_0003_rollback()
  -- Only Lyrandel can rollback
  if UnitName("player") ~= "Lyrandel" then
    self:defaultPrint(L["Migration rollback can only be performed by Lyrandel."])
    return false
  end
  
  if not CanEditOfficerNote() then
    self:defaultPrint(L["You do not have permission to edit officer notes."])
    return false
  end
  
  if not GuildRoll_migration_backup or not next(GuildRoll_migration_backup) then
    self:defaultPrint(L["No migration backup found."])
    return false
  end
  
  local count = 0
  
  for i = 1, GetNumGuildMembers(1) do
    local name, _, _, _, _, _, _, officernote, _, _ = GetGuildRosterInfo(i)
    -- Verify the name matches before applying the backup
    if name and GuildRoll_migration_backup[name] then
      GuildRosterSetOfficerNote(i, GuildRoll_migration_backup[name], true)
      count = count + 1
    end
  end
  
  -- Clear backup after rollback
  GuildRoll_migration_backup = {}
  
  self:defaultPrint(string.format(L["Rolled back %d officer notes to previous state."], count))
  
  return true
end

function GuildRoll:migration_0003_handler(args)
  local command = string.lower(args or "")
  
  if command == "apply" then
    self:migration_0003_apply()
  elseif command == "rollback" then
    self:migration_0003_rollback()
  else
    -- Default: dry-run preview
    local changes, count = self:migration_0003_preview()
    
    if count == 0 then
      self:defaultPrint(L["No officer notes need to be migrated."])
    else
      self:defaultPrint(string.format(L["Migration Preview: %d officer notes would be changed:"], count))
      for i, change in ipairs(changes) do
        if i <= 10 then -- Show first 10 examples
          self:defaultPrint(string.format("  %s: {%s:%s} -> {%s}", change.name, change.ep, change.gp, change.ep))
        end
      end
      if count > 10 then
        self:defaultPrint(string.format(L["  ... and %d more"], count - 10))
      end
      self:defaultPrint(L["Run '/gpmigrate apply' to apply changes (Lyrandel only)."])
    end
  end
end
