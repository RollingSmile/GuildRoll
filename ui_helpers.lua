-- ui_helpers.lua: UI helper functions for GuildRoll
-- Contains utilities for managing Tablet tooltips, frames, and UI interactions

-- Constant for maximum number of detached frames to scan
local MAX_DETACHED_FRAMES = 100

-- Cached dummy owner frame for Tablet tooltips
-- This prevents "Detached tooltip has no owner" errors from Tablet-2.0
local _guildroll_tablet_owner = nil

-- Get local reference to Dewdrop library (required for SafeDewdropAddLine)
-- Use pcall to safely get library reference
local D
pcall(function() D = AceLibrary("Dewdrop-2.0") end)

-- Centralized function to ensure Tablet tooltips have a valid owner
-- This prevents Tablet-2.0 from asserting when detaching tooltips without an owner
-- Call this after T:Register() to set tooltip.owner if it's missing
-- Returns the dummy owner frame (or UIParent as fallback)
function GuildRoll:EnsureTabletOwner()
  local owner = nil
  pcall(function()
    -- Create or reuse the cached dummy owner frame
    if not _guildroll_tablet_owner then
      local ok, f = pcall(function() 
        return CreateFrame and CreateFrame("Frame", "GuildRoll_TabletOwner") 
      end)
      if ok and f then
        _guildroll_tablet_owner = f
      else
        -- Fallback to UIParent if frame creation fails
        _guildroll_tablet_owner = UIParent
      end
    end
    owner = _guildroll_tablet_owner
  end)
  return owner or UIParent
end

-- Shared method: find an existing detached Tablet frame by owner name
function GuildRoll:FindDetachedFrame(ownerName)
  if not ownerName then return nil end
  for i = 1, MAX_DETACHED_FRAMES do
    local f = _G[string.format("Tablet20DetachedFrame%d", i)]
    if f and f.owner and f.owner == ownerName then
      return f
    end
  end
  return nil
end

-- SafeDewdropAddLine: Centralized safe wrapper for Dewdrop:AddLine usage
-- Prevents Dewdrop crashes by wrapping D:AddLine with pcall + unpack(arg)
-- Note: In Lua 5.0 (WoW 1.12), varargs (...) cannot be passed directly to pcall.
-- We must use unpack(arg) to forward the arguments.
function GuildRoll:SafeDewdropAddLine(...)
  if D and D.AddLine then
    pcall(D.AddLine, D, unpack(arg))
  end
end

-- Make frame escapable: Add or remove frame from UISpecialFrames table
function GuildRoll:make_escable(framename,operation)
  local found
  for i,f in ipairs(UISpecialFrames) do
    if f==framename then
      found = i
    end
  end
  if not found and operation=="add" then
    table.insert(UISpecialFrames,framename)
  elseif found and operation=="remove" then
    table.remove(UISpecialFrames,found)
  end
end

-- Reset detached frames to default visible positions
function GuildRoll:ResetFrames()
  -- Default visible positions for detached frames
  local defaultPositions = {
    ["GuildRoll_standings"] = {x = 400, y = 350},
    ["GuildRollAlts"] = {x = 650, y = 300},
    ["GuildRoll_logs"] = {x = 800, y = 300},
    ["GuildRoll_personal_logs"] = {x = 500, y = 200},
    ["GuildRoll_AdminLog"] = {x = 900, y = 300}
  }
  
  local resetCount = 0
  for ownerName, pos in pairs(defaultPositions) do
    local frame = self:FindDetachedFrame(ownerName)
    if frame then
      pcall(function()
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", pos.x, pos.y)
        resetCount = resetCount + 1
      end)
    end
  end
  
  if resetCount > 0 then
    self:defaultPrint(string.format("Reset %d detached frame(s) to visible positions.", resetCount))
  else
    self:defaultPrint("No detached frames found to reset.")
  end
end
