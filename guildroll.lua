GuildRoll = AceLibrary("AceAddon-2.0"):new("AceConsole-2.0", "AceHook-2.1", "AceDB-2.0", "AceDebug-2.0", "AceEvent-2.0", "AceModuleCore-2.0", "FuBarPlugin-2.0")
GuildRoll:SetModuleMixins("AceDebug-2.0")

-- Global debug flag: set to true to enable debug output
GuildRoll.DEBUG = false
local D = AceLibrary("Dewdrop-2.0")-- Standings table
local BZ = AceLibrary("Babble-Zone-2.2")
local C = AceLibrary("Crayon-2.0") -- chat color
local BC = AceLibrary("Babble-Class-2.2") 
--local DF = AceLibrary("Deformat-2.0")
--local G = AceLibrary("Gratuity-2.0")
local T = AceLibrary("Tablet-2.0") -- tooltips
local L = AceLibrary("AceLocale-2.2"):new("guildroll")
GuildRoll.VARS = {
  CSRWeekBonus = 10,  -- Bonus per week for CSR (weeks 2-15: (weeks-1)*10)
  minPE = 0,
  baseawardpoints = 10,
  decay = 0.5,
  max = 1000,
  minAward = -100,
  maxAward = 100,
  timeout = 60,
  minlevel = 1,
  maxloglines = 500,
  prefix = "RRG_"
}

GuildRollMSG = {
	delayedinit = false,
	dbg= false,
	prefix = "RR_",
	RequestHostInfoUpdate = "RequestHostInfoUpdate",
	RequestHostInfoUpdateTS = 0,
	HostInfoUpdate = "HostInfoUpdate"

}
GuildRoll._playerName = (UnitName("player"))
local out = "|cff9664c8guildroll:|r %s"
local raidStatus,lastRaidStatus
local lastUpdate = 0
local needInit,needRefresh = true
local admin,sanitizeNote
local guildep_debugchat
local running_check,running_bid
local partyUnit,raidUnit = {},{}
local hexColorQuality = {}
local RaidKey = {}
-- Forward-declare handler for SHARE: admin settings so addonComms can call it early
local handleSharedSettings

-- Constants for note length and migration timing
local MAX_NOTE_LEN = 31
local MIGRATION_THROTTLE_SECONDS = 30
local MIGRATION_AUTO_DELAY_SECONDS = 5

-- Helper: trim public note with tag to ensure it fits within max length
-- existing: current public note
-- tag: tag to append
-- maxlen: maximum allowed length (default MAX_NOTE_LEN)
-- Returns: trimmed note with tag appended
local function _trim_public_with_tag(existing, tag, maxlen)
  maxlen = maxlen or MAX_NOTE_LEN
  existing = existing or ""
  tag = tag or ""
  
  local tagLen = string.len(tag)
  local availableLen = maxlen - tagLen
  
  if availableLen < 0 then
    -- Tag itself is too long; return just the tag truncated
    return string.sub(tag, 1, maxlen)
  end
  
  if string.len(existing) <= availableLen then
    -- Existing note fits; append tag
    return existing .. tag
  else
    -- Trim existing to fit
    return string.sub(existing, 1, availableLen) .. tag
  end
end

-- Helper: insert tag before {EP} pattern in officer note
-- officernote: current officer note
-- tag: tag to insert
-- Returns: new officer note with tag inserted before {EP} pattern
local function _insertTagBeforeEP(officernote, tag)
  -- Ensure inputs are strings
  if type(officernote) ~= "string" then officernote = "" end
  if type(tag) ~= "string" then tag = "" end
  
  -- Return early if tag is empty
  if tag == "" then
    return officernote
  end
  
  -- Remove any existing occurrences of this tag from the officer note
  -- Escape pattern characters in the tag for safe pattern matching
  local escapedTag = string.gsub(tag, "([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
  officernote = string.gsub(officernote, escapedTag, "")
  
  -- Try to find new {EP} pattern first (e.g., {123})
  local prefix, ep, postfix = string.match(officernote, "^(.-)({%d+})(.*)$")
  
  if ep then
    -- Found new {EP} pattern; insert tag before it
    return prefix .. tag .. ep .. postfix
  end
  
  -- Try to find legacy {EP:GP} pattern (e.g., {123:456})
  prefix, epgp, postfix = string.match(officernote, "^(.-)({%d+:%d+})(.*)$")
  
  if epgp then
    -- Found legacy pattern; insert tag before it
    return prefix .. tag .. epgp .. postfix
  else
    -- No pattern found; append tag to end
    return officernote .. tag
  end
end

-- Helper: attempt to run main tag migration with throttle check
-- Returns true if migration was attempted, false if throttled
local function _attemptThrottledMigration(self)
  -- Check throttle: don't run more often than once every 30 seconds
  local now = GetTime()
  if self._lastMigrateRun and (now - self._lastMigrateRun) < MIGRATION_THROTTLE_SECONDS then
    return false
  end
  
  -- Set timestamp before attempting to prevent rapid retries on failure
  -- This ensures we don't spam attempts when guild roster isn't available yet
  self._lastMigrateRun = now
  
  -- Verify guild roster is available
  local ok, numMembers = pcall(function()
    if not IsInGuild() then return 0 end
    return GetNumGuildMembers(1) or 0
  end)
  
  if ok and numMembers > 0 then
    -- Run migration
    pcall(function()
      GuildRoll:MovePublicMainTagsToOfficerNotes()
    end)
    return true
  end
  
  return false
end

local options
do
  for i=1,40 do
    raidUnit[i] = "raid"..i
  end
  for i=1,4 do
    partyUnit[i] = "party"..i
  end
  for i=-1,6 do
    hexColorQuality[ITEM_QUALITY_COLORS[i].hex] = i
  end
end
local admincmd, membercmd = {type = "group", handler = GuildRoll, args = {

    show = {
      type = "execute",
      name = L["Standings"],
      desc = L["Show Standings Table."],
      func = function()
        GuildRoll_standings:Toggle()
      end,
      order = 1,
    },
    resetButton = {
      type = "execute",
      name = "Reset Button",
      desc = "Reset Button",
      func = function()
        GuildRoll:ResetButton()  
      end,
      order = 2,
    },      
    restart = {
      type = "execute",
      name = L["Restart"],
      desc = L["Restart guildroll if having startup problems."],
      func = function() 
        GuildRoll:OnEnable()
        GuildRoll:defaultPrint(L["Restarted"])
      end,
      order = 7,
    },
    ms = {
      type = "execute",
      name = "Roll MainSpec",
      desc = "Roll MainSpec with your standing",
      func = function() 
        GuildRoll:RollCommand(false, 0)
      end,
      order = 8,
    },
    sr = {
      type = "execute",
      name = "Roll SR",
      desc = "Roll Soft Reserve with your standing",
      func = function() 
        GuildRoll:RollCommand(true, 0)
      end,
      order = 9,
    },
    csr = {
      type = "range",
      name = "Roll Cumulative SR",
      desc = "Roll Cumulative Soft Reserve with your standing",
      get = "Roll Cumulative Soft Reserve with your standing",
      min = 1,
      max = 10,
      step = 1,
      isPercent = false,
      get = function(input)
        
      end,
      set = function(input) 
      local bonus = GuildRoll:calculateBonus(input)
      GuildRoll:RollCommand(true, bonus)
      end,
      order = 10,
    },
    rolltable = {
      type = "execute",
      name = "Show Roll Table",
      desc = "Open the roll tracking table UI",
      func = function()
        if GuildRoll and GuildRoll.RollWithEP_ShowRollTable then
          GuildRoll.RollWithEP_ShowRollTable()
        else
          GuildRoll:defaultPrint("Roll Table not available")
        end
      end,
      order = 11,
    },
    nogp = {
      type = "text",
      name = "Migrate to EP-only",
      desc = "Convert officer notes from {EP:GP} to {EP} format with GP backup. Usage: /groll nogp [throttleDelay]",
      usage = "[throttleDelay]",
      get = false,
      set = function(input)
        local throttleDelay = tonumber(input) or 0.25
        GuildRoll:migrateToEPOnly(throttleDelay)
      end,
      order = 11,
    },
  }},
{type = "group", handler = GuildRoll, args = {
    show = {
      type = "execute",
      name = L["Standings"],
      desc = L["Show Standings Table."],
      func = function()
        GuildRoll_standings:Toggle()
      end,
      order = 1,
    },
    resetButton = {
      type = "execute",
      name = "Reset Button",
      desc = "Reset Button",
      func = function()
        GuildRoll:ResetButton()  
      end,
      order = 2,
    }, 
    restart = {
      type = "execute",
      name = L["Restart"],
      desc = L["Restart guildroll if having startup problems."],
      func = function() 
        GuildRoll:OnEnable()
        GuildRoll:defaultPrint(L["Restarted"])
      end,
      order = 4,
    },
    ms = {
      type = "execute",
      name = "Roll MainSpec",
      desc = "Roll with your standing",
      func = function() 
        GuildRoll:RollCommand(false, 0)
      end,
      order = 5,
    },
    sr = {
      type = "execute",
      name = "Roll SR",
      desc = "Roll Soft Reserve with your standing",
      func = function() 
        GuildRoll:RollCommand(true, 0)
      end,
      order = 7,
    },
    csr = {
      type = "range",
      name = "Roll Cumulative SR",
      desc = "Roll Cumulative Soft Reserve with your standing",
      get = "Roll Cumulative Soft Reserve with your standing",
      min = 1,
      max = 10,
      step = 1,
      isPercent = false,
      get = function(input)
      
      end,
      set = function(input) 
      local bonus = GuildRoll:calculateBonus(input)
      GuildRoll:RollCommand(true, bonus)
      end,
      order = 8,
    },
    rolltable = {
      type = "execute",
      name = "Show Roll Table",
      desc = "Open the roll tracking table UI",
      func = function()
        if GuildRoll and GuildRoll.RollWithEP_ShowRollTable then
          GuildRoll.RollWithEP_ShowRollTable()
        else
          GuildRoll:defaultPrint("Roll Table not available")
        end
      end,
      order = 9,
    },
  }}
GuildRoll.cmdtable = function() 
  if (admin()) then
    return admincmd
  else
    return membercmd
  end
end
GuildRoll.alts = {} 
function GuildRoll:buildMenu()
  if not (options) then
    options = {
    type = "group",
    desc = L["guildroll options"],
    handler = self,
    args = { }
    }
    
    -- Quick Actions Group
    options.args["quick_actions"] = {
      type = "group",
      name = L["Quick Actions"],
      desc = "Quick access actions",
      order = 1,
      args = {}
    }
    
    options.args["quick_actions"].args["toggle_roll"] = {
      type = "execute",
      name = L["Toggle Roll Button"],
      desc = "Toggle Roll UI (same as Shift+Click)",
      order = 1,
      func = function()
        local f = _G["GuildEpRollFrame"]
        if f then
          pcall(function()
            if f:IsShown() then f:Hide() else f:Show() end
          end)
        else
          if GuildRoll and GuildRoll.defaultPrint then
            GuildRoll:defaultPrint("Roll frame not available.")
          end
        end
      end
    }
    
    options.args["quick_actions"].args["show_standings"] = {
      type = "execute",
      name = L["Show Standings"],
      desc = "Show Standings window (same as Click)",
      order = 2,
      func = function()
        if GuildRoll_standings and GuildRoll_standings.Toggle then
          pcall(function()
            GuildRoll:ToggleModuleActive("GuildRoll_standings", true)
            GuildRoll_standings:Toggle()
          end)
        end
      end
    }
    
    options.args["quick_actions"].args["show_personal_log"] = {
      type = "execute",
      name = L["Show Personal Log"],
      desc = "Show your personal EP log",
      order = 3,
      func = function()
        pcall(function()
          if GuildRoll and GuildRoll.ShowPersonalLog then
            GuildRoll:ShowPersonalLog()
          elseif GuildRoll_logs and GuildRoll_logs.ShowPersonalLog and GuildRoll and GuildRoll._playerName then
            GuildRoll_logs:ShowPersonalLog(GuildRoll._playerName)
          end
        end)
      end
    }
    
    options.args["quick_actions"].args["show_alts"] = {
      type = "execute",
      name = L["Show Alts"],
      desc = "Show Alts window (same as Alt+Click)",
      order = 4,
      hidden = function() return not admin() end,
      func = function()
        if GuildRollAlts and GuildRollAlts.Toggle then
          pcall(function()
            GuildRoll:ToggleModuleActive("GuildRollAlts", true)
            GuildRollAlts:Toggle()
          end)
        end
      end
    }
    
    options.args["quick_actions"].args["show_admin_log"] = {
      type = "execute",
      name = L["Show Admin Log"],
      desc = "Show Admin Log window (same as Ctrl+Shift+Click)",
      order = 5,
      hidden = function() return not admin() end,
      func = function()
        if GuildRoll_AdminLog and GuildRoll_AdminLog.Toggle then
          pcall(function()
            GuildRoll:ToggleModuleActive("GuildRoll_AdminLog", true)
            GuildRoll_AdminLog:Toggle()
          end)
        end
      end
    }
    
    -- Loot Settings Group (admin-only, raid-only)
    options.args["loot_settings"] = {
      type = "group",
      name = "Loot Settings",
      desc = "Configure loot management settings (Admin only, Raid only)",
      order = 2,
      hidden = function() return not admin() end,
      args = {}
    }
    
    options.args["loot_settings"].args["import_csv"] = {
      type = "execute",
      name = L["Import SR CSV"],
      desc = L["Import soft reserves from RaidRes CSV format"],
      order = 1,
      func = function()
        -- Check if in raid
        local numRaidMembers = GetNumRaidMembers()
        if numRaidMembers == 0 then
          if GuildRoll and GuildRoll.defaultPrint then
            GuildRoll:defaultPrint("You must be in a raid to import CSV.")
          end
          return
        end
        
        -- Show CSV import dialog
        StaticPopupDialogs["ROLLWITHEP_IMPORT_CSV"] = {
          text = L["Paste CSV"] .. "\n" .. L["Enter RaidRes CSV data:"],
          button1 = L["Import"],
          button2 = L["Cancel"],
          hasEditBox = true,
          hasWideEditBox = true,
          editBoxWidth = 350,
          OnAccept = function()
            local editBox = getglobal(this:GetParent():GetName().."WideEditBox") or getglobal(this:GetParent():GetName().."EditBox")
            if editBox then
              local csvData = editBox:GetText()
              if GuildRoll and GuildRoll.RollWithEP_ImportCSV then
                pcall(function() GuildRoll.RollWithEP_ImportCSV(csvData) end)
              end
            end
          end,
          timeout = 0,
          whileDead = true,
          hideOnEscape = true,
          preferredIndex = 3
        }
        StaticPopup_Show("ROLLWITHEP_IMPORT_CSV")
      end
    }
    
    -- Set De/Bank - group type like + EP to Member
    options.args["loot_settings"].args["set_de_bank"] = {
      type = "group",
      name = L["Set De/Bank"],
      desc = L["Select player to receive DE/Bank items"],
      order = 2,
    }
    
    -- EP Actions Group (admin-only)
    options.args["ep_actions"] = {
      type = "group",
      name = L["EP Actions"],
      desc = "EP management actions (admin only)",
      order = 4,
      hidden = function() return not admin() end,
      args = {}
    }
    
    -- 1. Raid Only (toggle) - first in EP Actions
    options.args["ep_actions"].args["raid_only"] = {
      type = "toggle",
      name = L["Raid Only"],
      desc = L["Only show members in raid."],
      order = 1,
      get = function() return not not GuildRoll_memberlist_raidonly end,
      set = function(v) 
        GuildRoll_memberlist_raidonly = not GuildRoll_memberlist_raidonly
        -- Trigger local UI refresh
        GuildRoll:SetRefresh(true)
      end,
    }
    
    -- 2. Set Min EP (text) - second in EP Actions, shows current value in name
    options.args["ep_actions"].args["set_min_ep"] = {
      type = "text",
      -- Dewdrop-2.0 requires 'name' to be a string, not a function.
      -- Compute the display string at menu-build time so the current value is visible.
      name = string.format(L["Set Min EP (Current: %s)"], GuildRoll_minPE),
      desc = L["Set Minimum MainStanding"],
      usage = "<minPE>",
      order = 2,
      get = function() return GuildRoll_minPE end,
      set = function(v) 
        GuildRoll_minPE = tonumber(v)
        -- The name will show updated value on next menu open (buildMenu is called each time)
        GuildRoll:refreshPRTablets()
        -- Removed shareSettings call: Minimum EP is now local to each admin
      end,
      validate = function(v) 
        local n = tonumber(v)
        return n and n >= 0 and n <= GuildRoll.VARS.max
      end,
    }
    
    -- 3. +EP to Member (MainStanding group) - third in EP Actions
    options.args["ep_actions"].args["MainStanding"] = {
      type = "group",
      name = L["+MainStanding to Member"],
      desc = L["Account MainStanding for member."],
      order = 3,
    }
    
    -- 4. +EP to Raid - fourth in EP Actions
    options.args["ep_actions"].args["MainStanding_raid"] = {
      type = "execute",
      name = L["+MainStanding to Raid"],
      desc = L["Award MainStanding to all raid members."],
      order = 4,
      func = function() GuildRoll:PromptAwardRaidEP() end,
    }
    
    -- 5. Decay Standing - fifth in EP Actions
    options.args["ep_actions"].args["decay"] = {
      type = "execute",
      name = L["Decay Standing"],
      desc = string.format(L["Decays all Standing by %s%%"],(1-(GuildRoll_decay or GuildRoll.VARS.decay))*100),
      order = 5,
      func = function() StaticPopup_Show("GUILDROLL_CONFIRM_DECAY") end 
    }
    
    -- 6. Export/Import - sixth in EP Actions
    options.args["ep_actions"].args["export_import"] = {
      type = "group",
      name = L["Export/Import"],
      desc = "Export/Import standings data",
      order = 6,
      args = {
        export = {
          type = "execute",
          name = L["Export"],
          desc = L["Export standings to csv."],
          order = 1,
          func = function() 
            if GuildRoll_standings then
              GuildRoll_standings:Export()
            end
          end
        },
        import = {
          type = "execute",
          name = L["Import"],
          desc = L["Import standings from csv."],
          order = 2,
          hidden = function() return not IsGuildLeader() end,
          func = function() 
            if GuildRoll_standings then
              GuildRoll_standings:Import()
            end
          end
        }
      }
    }
    
    -- 7. Reset Standing - last in EP Actions (GuildLeader-only)
    options.args["ep_actions"].args["reset"] = {
      type = "execute",
      name = L["Reset Standing"],
      desc = L["Resets everyone\'s Standing to 0 (Admin only)."],
      order = 7,
      hidden = function() return not (IsGuildLeader()) end,
      func = function() StaticPopup_Show("CONFIRM_RESET") end
    }
    
    -- Buff Checks Group (moved to root, admin-only)
    options.args["buff_checks"] = {
      type = "group",
      name = L["Buff Checks"],
      desc = L["Admin buff verification tools"],
      order = 3,
      hidden = function() return not admin() end,
      args = {
        check_buffs = {
          type = "execute",
          name = L["Check Buffs"],
          desc = L["Check raid-level buffs required (special paladin rule)."],
          order = 1,
          func = function() GuildRoll_BuffCheck:CheckBuffs() end
        },
        check_consumes = {
          type = "execute",
          name = L["Check Consumes"],
          desc = L["Check raid consumes per-class and propose awarding EP."],
          order = 2,
          func = function() GuildRoll_BuffCheck:CheckConsumes() end
        },
        check_flasks = {
          type = "execute",
          name = L["Check Flasks"],
          desc = L["Check raid flasks per-class."],
          order = 3,
          func = function() GuildRoll_BuffCheck:CheckFlasks() end
        }
      }
    }
    
    -- Options Group -> Admin Settings (reduced, moved items removed)
    options.args["options_group"] = {
      type = "group",
      name = L["Admin Settings"],
      desc = L["Admin configuration options"],
      order = 4,
      hidden = function() return not admin() end,
      args = {}
    }
 
    options.args["options_group"].args["report_channel"] = {
      type = "text",
      name = L["Reporting channel"],
      desc = L["Channel used by reporting functions."],
      order = 30,
      hidden = function() return not (admin()) end,
      get = function() return GuildRoll_saychannel end,
      set = function(v) 
        GuildRoll_saychannel = v
        -- Share settings to guild if admin
        if GuildRoll and GuildRoll.shareSettings then
          GuildRoll:shareSettings()
        end
      end,
      validate = { "PARTY", "RAID", "GUILD", "OFFICER" },
    }
    
    options.args["options_group"].args["alts"] = {
      type = "toggle",
      name = L["Toggle Alt pooling"],
      desc = L["Allow Alts to use Main\'s Standing."],
      order = 40,
      hidden = function() return not (admin()) end,
      disabled = function() return not (IsGuildLeader()) end,
      get = function() return not not GuildRollAltspool end,
      set = function(v) 
        GuildRollAltspool = not GuildRollAltspool
        if (IsGuildLeader()) then
          GuildRoll:shareSettings(true)
        end
      end,
    }
    options.args["options_group"].args["alts_percent"] = {
      type = "range",
      name = L["Set Alts %"],
      desc = L["Set the % MainStanding Alts can earn."],
      order = 50,
      hidden = function() return (not GuildRollAltspool) or (not IsGuildLeader()) end,
      get = function() return GuildRoll_altpercent end,
      set = function(v) 
        GuildRoll_altpercent = v
        if (IsGuildLeader()) then
          GuildRoll:shareSettings(true)
        end
      end,
      min = 0.5,
      max = 1,
      step = 0.05,
      isPercent = true
    }
    
    options.args["options_group"].args["set_decay"] = {
      type = "range",
      name = L["Set Decay %"],
      desc = L["Set Decay percentage (Admin only)."],
      order = 70,
      usage = "<Decay>",
      get = function() return (1.0-GuildRoll_decay) end,
      set = function(v) 
        GuildRoll_decay = (1 - v)
        if GuildRoll._options and GuildRoll._options.args and GuildRoll._options.args["ep_actions"] and GuildRoll._options.args["ep_actions"].args["decay"] then
          GuildRoll._options.args["ep_actions"].args["decay"].desc = string.format(L["Decays all Standing by %s%%"],(1-GuildRoll_decay)*100)
        end
        if (IsGuildLeader()) then
          GuildRoll:shareSettings(true)
        end
      end,
      min = 0.01,
      max = 0.75,
      step = 0.01,
      bigStep = 0.05,
      isPercent = true,
      hidden = function() return not (admin()) end,    
    }
    
    options.args["options_group"].args["share_settings"] = {
      type = "execute",
      name = L["Share Settings"],
      desc = "Share settings with guild (admin only)",
      order = 80,
      hidden = function() return not (admin()) end,
      func = function() 
        if GuildRoll and GuildRoll.shareSettings then
          GuildRoll:shareSettings(true)
        end
      end,
    }
    
    options.args["options_group"].args["migrate_main_tags"] = {
      type = "execute",
      name = "Migrate Main Tags",
      desc = "Move {MainCharacter} tags from public notes to officer notes (Admin only).",
      order = 110,
      hidden = function() return not admin() end,
      func = function() 
        GuildRoll:MovePublicMainTagsToOfficerNotes()
      end,
    }
    
    -- Reset Frames (moved to root level, visible to all)
    options.args["reset_frames"] = {
      type = "execute",
      name = "Reset Frames",
      desc = "Reset detached frames to visible positions.",
      order = 100,
      func = function() GuildRoll:ResetFrames() end
    }
    
    -- Set Main (moved to root level, visible to all)
    options.args["set_main"] = {
      type = "execute",
      name = L["Set Main"],
      desc = L["Set your Main Character."],
      order = 101,
      func = function()
        StaticPopup_Show("GUILDROLL_SET_MAIN_PROMPT")
      end,
    }
    
    -- Cumulative rank threshold selector for CSR
    -- Visual index 0 = "Select Rank:" (threshold nil)
    -- Visual index 1 = rankIndex 0 (Guild Master) → threshold 0
    -- Visual index 2 = rankIndex 1 (Officer) → threshold 1
    -- etc.
    -- Clicking visual index i sets threshold to i-1 and shows checkmarks on all visual indices 1..i
    local function BuildCSRRankRadioGroup(container)
      container.args = container.args or {}

      container.args["info"] = {
        type = "header",
        name = "Checked ranks will see CSR button",
      }

      -- Helper: Check if current player has permission to edit CSR settings
      local function hasCSREditPermission()
        return IsGuildLeader() or admin()
      end

      -- Helper: Apply threshold change and notify
      local function applyThresholdChange(newThreshold)
        -- Convert to number to ensure numeric storage
        local numericThreshold = tonumber(newThreshold)
        -- Ensure threshold is never negative (GM must always have access)
        if numericThreshold ~= nil and numericThreshold < 0 then
          numericThreshold = 0
        end
        GuildRoll_CSRThreshold = numericThreshold
        if GuildRoll and GuildRoll.RebuildRollOptions then GuildRoll:RebuildRollOptions() end
        -- Share settings to guild if admin (guild leader or officer with edit permissions)
        if hasCSREditPermission() then
          GuildRoll:shareSettings(true)
        end
      end

      -- Collect rank names from guild roster if available
      local ranks = {}
      local maxIndex = -1
      local num = GetNumGuildMembers and GetNumGuildMembers(1) or 0
      if num and num > 0 then
        for i = 1, num do
          local name, rank, rankIndex = GetGuildRosterInfo(i)
          if rank and rankIndex then
            ranks[rankIndex] = rank
            if rankIndex > maxIndex then maxIndex = rankIndex end
          end
        end
      end

      -- If roster not ready, use standard placeholders
      if maxIndex < 0 then
        maxIndex = 4
        ranks = { [0] = "Guild Master", [1] = "Officer", [2] = "Veteran", [3] = "Core Raider", [4] = "Raider" }
      end

      -- Rank items: starting from rank 0 (Guild Master)
      -- Use local variable per iteration to ensure proper closure capture
      for rankIdx = 0, maxIndex do
        local currentRankIdx = rankIdx  -- Local per-iteration binding for closure
        local rankName = ranks[currentRankIdx] or ("Rank " .. tostring(currentRankIdx))
        local visualIdx = currentRankIdx + 1  -- Visual index starts at 1
        local key = "rank_" .. tostring(currentRankIdx)
        
        local descText
        if currentRankIdx == 0 then
          descText = "Guild Master (always has CSR access, cannot be disabled)"
        else
          descText = string.format("Set threshold to %s.", rankName)
        end
        
        container.args[key] = {
          type = "toggle",
          name = rankName,
          desc = descText,
          -- Cumulative checkbox: checked if current threshold >= this rankIndex
          get = function()
            local threshold = tonumber(GuildRoll_CSRThreshold)
            return threshold ~= nil and threshold >= currentRankIdx
          end,
          set = function(v)
            if v then
              -- Set threshold to this rankIndex
              applyThresholdChange(currentRankIdx)
            else
              -- Unchecking: set threshold to next higher rank (lower rankIdx = higher rank)
              -- Note: Guild Master (rank 0) is disabled and should never reach here,
              -- but if it does, applyThresholdChange will clamp to 0 minimum
              applyThresholdChange(currentRankIdx - 1)
            end
          end,
          -- Disable rank 0 (Guild Master) so it cannot be unchecked
          disabled = currentRankIdx == 0,
          order = visualIdx,
        }
      end
    end

    -- Add the group to options (replaces the old csr_threshold in options.args)
    options.args["options_group"].args["csr_rank_selector"] = {
      type = "group",
      name = L["CSR Threshold"],
      desc = "Select the minimum rank to can use CSR:",
      args = {},
      hidden = function() return not admin() end,
      order = 65,
    }
    BuildCSRRankRadioGroup(options.args["options_group"].args["csr_rank_selector"])

    -- Dynamically update rank names when roster changes (create frame only once)
    if not self._csr_update_frame then
      self._csr_update_frame = CreateFrame("Frame")
      self._csr_update_frame:RegisterEvent("GUILD_ROSTER_UPDATE")
      self._csr_update_frame:SetScript("OnEvent", function()
        -- Rebuild toggles with updated names
        if options and options.args and options.args["options_group"] and options.args["options_group"].args["csr_rank_selector"] then
          BuildCSRRankRadioGroup(options.args["options_group"].args["csr_rank_selector"])
        end
        -- Refresh Dewdrop/Tablet menu if necessary
        if GuildRoll and GuildRoll.RebuildRollOptions then GuildRoll:RebuildRollOptions() end
      end)
    end
    
    options.args["options_group"].args["show_all_roll_buttons"] = {
      type = "toggle",
      name = L["Show all Roll Buttons"],
      desc = "When enabled, shows all roll buttons to everyone (Admin only).",
      order = 66,
      hidden = function() return not (admin()) end,
      get = function() return GuildRoll_showAllRollButtons == true end,
      set = function(v)
        GuildRoll_showAllRollButtons = v
        if GuildRoll and GuildRoll.RebuildRollOptions then GuildRoll:RebuildRollOptions() end
        if GuildRoll and GuildRoll.shareSettings then GuildRoll:shareSettings(true) end
      end,
    }

  end
  if (needInit) or (needRefresh) then
    local members = GuildRoll:buildRosterTable()
    
    -- Conditional scan message logging: reduce noise by only logging on errors,
    -- member count changes, mode changes, or when scanVerbose is enabled
    -- Ensure SavedVariables table and default for scanVerbose
    if GuildRoll_VARS == nil then GuildRoll_VARS = {} end
    if GuildRoll_VARS.scanVerbose == nil then GuildRoll_VARS.scanVerbose = false end

    local member_count = table.getn(members)
    local scan_mode = (GuildRoll_memberlist_raidonly and "Raid" or "Full")
    local scan_msg = string.format(L["Scanning %d members for Standing data. (%s)"], member_count, scan_mode)

    local is_first_scan = (self._last_scan_member_count == nil)
    local count_changed = (not is_first_scan) and (self._last_scan_member_count ~= member_count)
    local mode_changed = (not is_first_scan) and (self._last_scan_mode ~= scan_mode)

    -- Always print on error (no members)
    if member_count == 0 then
      self:debugPrint(scan_msg)
    else
      if GuildRoll_VARS.scanVerbose or count_changed or mode_changed or (is_first_scan and GuildRoll_VARS.scanVerbose) then
        self:debugPrint(scan_msg)
      end
    end

    -- Store transient session state
    self._last_scan_member_count = member_count
    self._last_scan_mode = scan_mode
    
    options.args["ep_actions"].args["MainStanding"].args = GuildRoll:buildClassMemberTable(members,"MainStanding")
    
    -- Populate Set De/Bank with raid members grouped by class
    if GetNumRaidMembers() > 0 then
      local raidMembers = {}
      for i = 1, GetNumRaidMembers(true) do
        local name, rank, subgroup, level, class = GetRaidRosterInfo(i)
        if name and class then
          -- Strip realm suffix
          local cleanName = string.gsub(name, "%-[^%-]+$", "")
          table.insert(raidMembers, {name = cleanName, class = class})
        end
      end
      options.args["loot_settings"].args["set_de_bank"].args = GuildRoll:buildDEBankMemberTable(raidMembers)
    else
      -- Not in raid - show empty or message
      options.args["loot_settings"].args["set_de_bank"].args = {
        no_raid = {
          type = "execute",
          name = "Not in raid",
          desc = "You must be in a raid to set DE/Bank player",
          order = 1,
          func = function()
            if GuildRoll and GuildRoll.defaultPrint then
              GuildRoll:defaultPrint("You must be in a raid to set DE/Bank player.")
            end
          end
        }
      }
    end
    
    if (needInit) then needInit = false end
    if (needRefresh) then needRefresh = false end
  end
  return options
end

function GuildRoll:OnInitialize() -- ADDON_LOADED (1) unless LoD
  if GuildRoll_saychannel == nil then GuildRoll_saychannel = "GUILD" end
  if GuildRoll_decay == nil then GuildRoll_decay = GuildRoll.VARS.decay end
  if GuildRoll_minPE == nil then GuildRoll_minPE = GuildRoll.VARS.minPE end
  if GuildRollAltspool == nil then GuildRollAltspool = true end
  if GuildRoll_altpercent == nil then GuildRoll_altpercent = 1.0 end
  if GuildRoll_debug == nil then GuildRoll_debug = {} end
  if GuildRoll_showAllRollButtons == nil then GuildRoll_showAllRollButtons = false end
  if GuildRoll_debugAdminLog == nil then GuildRoll_debugAdminLog = false end
  -- Initialize runtime-only raid filter flags (not saved to SavedVariables)
  GuildRoll_memberlist_raidonly = false
  GuildRoll_standings_raidonly = false
  self:RegisterDB("GuildRoll_fubar")
  self:RegisterDefaults("char",{})
end

function GuildRoll:OnEnable() -- PLAYER_LOGIN (2)
  GuildRoll._playerLevel = UnitLevel("player")
  --GuildRoll.extratip = (GuildRoll.extratip) or CreateFrame("GameTooltip","guildroll_tooltip",UIParent,"GameTooltipTemplate")
  GuildRoll._versionString = GetAddOnMetadata("guildroll","Version")
  GuildRoll._websiteString = GetAddOnMetadata("guildroll","X-Website")
  
  if (IsInGuild()) then
    if (GetNumGuildMembers()==0) then
      GuildRoster()
    end
  end

  self:RegisterEvent("GUILD_ROSTER_UPDATE",function() 
      if (arg1) then -- member join /leave
        GuildRoll:SetRefresh(true)
      end
    end)
 
  self:RegisterEvent("CHAT_MSG_ADDON",function() 
        GuildRollMSG:OnCHAT_MSG_ADDON( arg1, arg2, arg3, arg4)
    end)
  self:RegisterEvent("RAID_ROSTER_UPDATE",function()
      GuildRoll:SetRefresh(true)
    end)
  self:RegisterEvent("PARTY_MEMBERS_CHANGED",function()
      GuildRoll:SetRefresh(true)
    end)
  self:RegisterEvent("PLAYER_ENTERING_WORLD",function()
      GuildRoll:SetRefresh(true)
    end)
  if GuildRoll._playerLevel and GuildRoll._playerLevel < MAX_PLAYER_LEVEL then
    self:RegisterEvent("PLAYER_LEVEL_UP", function()
        if (arg1) then
          GuildRoll._playerLevel = tonumber(arg1)
          if GuildRoll._playerLevel == MAX_PLAYER_LEVEL then
            GuildRoll:UnregisterEvent("PLAYER_LEVEL_UP")
          end
          if GuildRoll._playerLevel and GuildRoll._playerLevel >= GuildRoll.VARS.minlevel then
            GuildRoll:testMain()
          end
        end
      end)
  end

  if AceLibrary("AceEvent-2.0"):IsFullyInitialized() then
    self:AceEvent_FullyInitialized()
  else
    self:RegisterEvent("AceEvent_FullyInitialized")
  end
end

function GuildRoll:OnDisable()
  self:UnregisterAllEvents()
end

function GuildRoll:AceEvent_FullyInitialized() -- SYNTHETIC EVENT, later than PLAYER_LOGIN, PLAYER_ENTERING_WORLD (3)
  if self._hasInitFull then return end
  
  for i=1,NUM_CHAT_WINDOWS do
    local tab = getglobal("ChatFrame"..i.."Tab")
    local cf = getglobal("ChatFrame"..i)
    local tabName = tab:GetText()
    if tab ~= nil and (string.lower(tabName) == "debug") then
      guildep_debugchat = cf
      ChatFrame_RemoveAllMessageGroups(guildep_debugchat)
      guildep_debugchat:SetMaxLines(1024)
      break
    end
  end

  self:testMain()

  -- Auto-enable AdminLog module for admins
  if self:IsAdmin() then
    pcall(function()
      self:ToggleModuleActive("GuildRoll_AdminLog", true)
    end)
  end

  local delay = 2
  if self:IsEventRegistered("AceEvent_FullyInitialized") then
    self:UnregisterEvent("AceEvent_FullyInitialized")
    delay = 3
  end  
  if not self:IsEventScheduled("guildrollChannelInit") then
    self:ScheduleEvent("guildrollChannelInit",self.delayedInit,delay,self)
  end

  self._hasInitFull = true
end

GuildRoll._lastRosterRequest = false
function GuildRoll:OnMenuRequest()
  local now = GetTime()
  if not self._lastRosterRequest or (now - self._lastRosterRequest > 2) then
    self._lastRosterRequest = now
    self:SetRefresh(true)
    GuildRoster()
  end
  self._options = self:buildMenu()
  D:FeedAceOptionsTable(self._options)
end


function GuildRoll:delayedInit()
  GuildRoll.VARS.GuildName  =""
  if (IsInGuild()) then
    GuildRoll.VARS.GuildName  = (GetGuildInfo("player"))
  end
   
  -- Migration helper: Copy legacy "shooty" frame names to new "guildep" names
  -- This ensures users who update without clearing saved variables don't lose functionality
  if _G["shooty_exportframe"] and not _G["guildep_exportframe"] then
    _G["guildep_exportframe"] = _G["shooty_exportframe"]
  end
  if _G["shooty_exportaction"] and not _G["guildep_exportaction"] then
    _G["guildep_exportaction"] = _G["shooty_exportaction"]
  end
  if _G["shooty_exportedit"] and not _G["guildep_exportedit"] then
    _G["guildep_exportedit"] = _G["shooty_exportedit"]
  end
  if _G["shooty_exportscroll"] and not _G["guildep_exportscroll"] then
    _G["guildep_exportscroll"] = _G["shooty_exportscroll"]
  end
  if _G["ShootyRollFrame"] and not _G["GuildEpRollFrame"] then
    _G["GuildEpRollFrame"] = _G["ShootyRollFrame"]
  end
  if _G["ShootyRollButton"] and not _G["GuildEpRollButton"] then
    _G["GuildEpRollButton"] = _G["ShootyRollButton"]
  end
   
  -- init options and comms
  self._options = self:buildMenu()
  self:RegisterChatCommand({"/groll"},self.cmdtable())
  
  -- Register standalone /grollnogp command for admin-only migration
  self:RegisterChatCommand({"/grollnogp"}, {
    type = "text",
    name = "Migrate to EP-only",
    desc = "Convert officer notes from {EP:GP} to {EP} format with GP backup",
    usage = "[throttleDelay]",
    get = false,
    set = function(input)
      local throttleDelay = tonumber(input) or 0.25
      GuildRoll:migrateToEPOnly(throttleDelay)
    end,
  })
  
  function GuildRoll:calculateBonus(input)
    local number = tonumber(input)
    if not number or number < 0 or number > 15 then
      return nil  -- Invalid input
    end
    if number == 0 or number == 1 then
      return 0
    end
    -- number is between 2 and 15
    return (number - 1) * GuildRoll.VARS.CSRWeekBonus
  end
  --self:RegisterEvent("CHAT_MSG_ADDON","addonComms")  
  -- broadcast our version
  local addonMsg = string.format("GuildRollVERSION;%s;%d",GuildRoll._versionString,major_ver or 0)
  self:addonMessage(addonMsg,"GUILD")
  if (IsGuildLeader()) then
    self:shareSettings()
  end
  -- safe officer note setting when we are admin
  if (admin()) then
    if not self:IsHooked("GuildRosterSetOfficerNote") then
      self:Hook("GuildRosterSetOfficerNote")
    end
    
    -- Auto-run migration 5 seconds after init for admins
    self:ScheduleEvent("guildroll_auto_migrate", function()
      _attemptThrottledMigration(self)
    end, MIGRATION_AUTO_DELAY_SECONDS)
  end
  
  -- Schedule alt main prompt check after a short delay to allow roster to populate
  self:ScheduleEvent("guildroll_check_alt_main", function()
    self:CheckAltAndPromptSetMain()
  end, 2)
  
  GuildRollMSG.delayedinit = true
  self:defaultPrint(string.format(L["v%s Loaded."],GuildRoll._versionString))
end


function GuildRoll:OnUpdate(elapsed)
  GuildRoll.timer.count_down = GuildRoll.timer.count_down - elapsed
  lastUpdate = lastUpdate + elapsed

  if lastUpdate > 0.5 then
    lastUpdate = 0
    -- GuildRoll_reserves:Refresh() removed (reserves feature removed)
  end
end

function GuildRoll:GuildRosterSetOfficerNote(index,note,fromAddon)
  if (fromAddon) then
    self.hooks["GuildRosterSetOfficerNote"](index,note)
  else
    local name, _, _, _, _, _, _, prevnote, _, _ = GetGuildRosterInfo(index)
    -- Check for both old {EP:GP} and new {EP} formats
    local _,_,_,oldepgp,_ = string.find(prevnote or "","(.*)({%d+:%-?%d+})(.*)")
    local _,_,_,oldep,_ = string.find(prevnote or "","(.-)({%d+})(.*)")
    local _,_,_,epgp,_ = string.find(note or "","(.*)({%d+:%-?%d+})(.*)")
    local _,_,_,ep,_ = string.find(note or "","(.-)({%d+})(.*)")
    
    if (GuildRollAltspool) then
      local oldmain = self:parseAlt(name,prevnote)
      local main = self:parseAlt(name,note)
      if oldmain ~= nil then
        if main == nil or main ~= oldmain then
          self:adminSay(string.format(L["Manually modified %s\'s note. Previous main was %s"],name,oldmain))
          self:defaultPrint(string.format(L["|cffff0000Manually modified %s\'s note. Previous main was %s|r"],name,oldmain))
        end
      end
    end    
    -- Check if EP/GP tag was modified (support both formats)
    local oldTag = oldepgp or oldep
    local newTag = epgp or ep
    if oldTag ~= nil then
      if newTag == nil or newTag ~= oldTag then
        -- legacy PUG/Bank handling removed: just report the modification to admins
        self:adminSay(string.format(L["Manually modified %s\'s note. Standing was %s"],name,oldTag))
        self:defaultPrint(string.format(L["|cffff0000Manually modified %s\'s note. Standing was %s|r"],name,oldTag))
      end
    end
    -- No need to sanitize with new {EP} format - it's already clean
    -- Just pass through the note as-is
    return self.hooks["GuildRosterSetOfficerNote"](index,note)    
  end
end


-------------------
-- Communication
-------------------
function GuildRoll:flashFrame(frame)
  local tabFlash = getglobal(frame:GetName().."TabFlash")
  if ( not frame.isDocked or (frame == SELECTED_DOCK_FRAME) or UIFrameIsFlashing(tabFlash) ) then
    return
  end
  tabFlash:Show()
  UIFrameFlash(tabFlash, 0.25, 0.25, 60, nil, 0.5, 0.5)
end

function GuildRoll:debugPrint(msg)
  if (guildep_debugchat) then
    guildep_debugchat:AddMessage(string.format(out,msg))
    self:flashFrame(guildep_debugchat)
  else
    self:defaultPrint(msg)
  end
end

function GuildRoll:defaultPrint(msg)
  if not DEFAULT_CHAT_FRAME:IsVisible() then
    FCF_SelectDockFrame(DEFAULT_CHAT_FRAME)
  end
  DEFAULT_CHAT_FRAME:AddMessage(string.format(out,msg))
end


function GuildRoll:simpleSay(msg)
  SendChatMessage(string.format("guildroll: %s",msg), GuildRoll_saychannel)
end

function GuildRoll:adminSay(msg)
  -- API is broken on Elysium
  -- local g_listen, g_speak, officer_listen, officer_speak, g_promote, g_demote, g_invite, g_remove, set_gmotd, set_publicnote, view_officernote, edit_officernote, set_guildinfo = GuildControlGetRankFlags() 
  -- if (officer_speak) then
  SendChatMessage(string.format("guildroll: %s",msg),"OFFICER")
  -- end
end

function GuildRoll:widestAudience(msg)
  local channel = "SAY"
  if UnitInRaid("player") then
    if (IsRaidLeader() or IsRaidOfficer()) then
      channel = "RAID_WARNING"
    else
      channel = "RAID"
    end
  elseif UnitExists("party1") then
    channel = "PARTY"
  end
  SendChatMessage(msg, channel)
end

function GuildRoll:addonMessage(message,channel,sender)
  SendAddonMessage(self.VARS.prefix,message,channel,sender)
end

function GuildRoll:addonComms(prefix,message,channel,sender)
  if prefix ~= self.VARS.prefix then return end -- we don't care for messages from other addons
  if sender == self._playerName then return end -- we don't care for messages from ourselves
  local name_g,class,rank = self:verifyGuildMember(sender,true)
  if not (name_g) then return end -- only accept messages from guild members
  
  -- Handle SHARE: messages (new admin settings broadcast)
  if message and string.find(message, "^SHARE:") then
    handleSharedSettings(message, sender)
    return
  end
  
  -- Handle MIGRATE_MAIN_TAG_REQUEST messages
  if message == "MIGRATE_MAIN_TAG_REQUEST" then
    -- Only admins process migration requests
    if not GuildRoll:IsAdmin() then
      return
    end
    
    -- Attempt throttled migration
    _attemptThrottledMigration(self)
    return
  end
  
  local who,what,amount,raidFlag
  -- Parse 3-field or 4-field message format for backward compatibility
  for name,epgp,change,flag in string.gfind(message,"([^;]+);([^;]+);([^;]+);?([^;]*)") do
    who=name
    what=epgp
    amount=tonumber(change)
    raidFlag=flag
  end
  if (who) and (what) and (amount) then
    local msg
    -- Improved main detection: use parseAlt as fallback to support alt pooling
    -- Note: parseAlt is called on each message rather than cached because the main
    -- character can be changed during the session via Set Main feature
    local playerMain = self:parseAlt(self._playerName)
    local for_main = (GuildRoll_main and (who == GuildRoll_main)) or (playerMain and (who == playerMain))
    
    if (who == self._playerName) or (for_main) then
      if what == "MainStanding" then
        -- Add personal log entry for EP changes with compact colorized format
        -- Note: Due to WoW's guild roster sync timing, get_ep_v3 usually returns the pre-change
        -- value, making prevEP accurate. In rare cases where roster has already synced, prevEP
        -- may reflect the post-change value, but this is unavoidable with the current API.
        local prevEP = self:get_ep_v3(who) or 0
        local newEP = prevEP + amount
        
        -- Colorize delta: green for positive, red for negative
        local deltaStr
        if amount >= 0 then
          deltaStr = C:Green(string.format("+%d", amount))
        else
          deltaStr = C:Red(string.format("%d", amount))
        end
        
        -- Build suffix based on raidFlag
        local suffix = ""
        if raidFlag and raidFlag == "RAID" then
          suffix = " (Raid)"
        end
        
        -- Compact format: EP: Prev -> New (±N) by AdminName[ (Raid)]
        local logMsg = string.format("EP: %d -> %d (%s) by %s%s", prevEP, newEP, deltaStr, sender, suffix)
        self:personalLogAdd(who, logMsg)
        
        -- User-facing message with admin name, old/new EP, and raid tag
        if amount < 0 then
          msg = string.format("EP penalty: %d -> %d (%d) by %s%s", prevEP, newEP, amount, sender, suffix)
        else
          msg = string.format("EP awarded: %d -> %d (+%d) by %s%s", prevEP, newEP, amount, sender, suffix)
        end
      elseif what == "AuxStanding" then
        msg = string.format(L["You have gained %d AuxStanding."],amount)
      end
    elseif who == "ALL" and what == "DECAY" then
      msg = string.format(L["%s%% decay to Standing."],amount)
    elseif who == "RAID" and what == "AWARD" then
      msg = string.format(L["%d MainStanding awarded to Raid."],amount)
    elseif who == "RAID" and what == "AWARDAuxStanding" then
      msg = string.format(L["%d MainStanding awarded to Raid."],amount)
    elseif who == "GuildRollVERSION" then
      local out_of_date, version_type = self:parseVersion(self._versionString,what)
      if (out_of_date) and self._newVersionNotification == nil then
        self._newVersionNotification = true -- only inform once per session
        self:defaultPrint(string.format(L["New %s version available: |cff00ff00%s|r"],version_type,what))
        self:defaultPrint(string.format(L["Visit %s to update."],self._websiteString))
      end
      if (IsGuildLeader()) then
        self:shareSettings()
      end
    elseif who == "SETTINGS" then
      for progress,discount,decay,minPE,alts,altspct in string.gfind(what, "([^:]+):([^:]+):([^:]+):([^:]+):([^:]+):([^:]+)") do
        discount = tonumber(discount)
        decay = tonumber(decay)
        minPE = tonumber(minPE)
        alts = (alts == "true") and true or false
        altspct = tonumber(altspct)
        local settings_notice
        if decay and decay ~= GuildRoll_decay then
          GuildRoll_decay = decay
          if (admin()) then
            if (settings_notice) then
              settings_notice = settings_notice..L[", decay %"]
            else
              settings_notice = L["New decay %"]
            end
          end
        end
        if alts ~= nil and alts ~= GuildRollAltspool then
          GuildRollAltspool = alts
          if (admin()) then
            if (settings_notice) then
              settings_notice = settings_notice..L[", alts"]
            else
              settings_notice = L["New Alts"]
            end
          end          
        end
        if altspct and altspct ~= GuildRoll_altpercent then
          GuildRoll_altpercent = altspct
          if (admin()) then
            if (settings_notice) then
              settings_notice = settings_notice..L[", alts MainStanding %"]
            else
              settings_notice = L["New Alts MainStanding %"]
            end
          end          
        end
        if (settings_notice) and settings_notice ~= "" then
          -- Defensive: Re-verify sender to get fresh class/rank info
          -- This prevents crashes when class/rank from outer scope are nil or stale
          local sender_name, sender_class, sender_rank = self:verifyGuildMember(sender, true)
          local sender_display
          
          -- Attempt to format sender with class color and rank, with robust fallbacks
          if sender_name and sender_class and sender_rank then
            local success, coloredSender = pcall(function() 
              return C:Colorize(BC:GetHexColor(sender_class), sender_name) 
            end)
            if success and coloredSender then
              sender_display = string.format("%s(%s)", coloredSender, sender_rank)
            else
              -- Fallback if colorization fails
              sender_display = string.format("%s(%s)", sender_name, sender_rank)
            end
          else
            -- Fallback if sender verification fails: use raw sender name
            sender_display = sender or "Unknown"
          end
          
          settings_notice = settings_notice..string.format(L[" settings accepted from %s"], sender_display)
          self:defaultPrint(settings_notice)
         -- self._options.args["RollValueogress_tier_header"].name = string.format(L["Progress Setting: %s"],GuildRoll_progress)
         -- self._options.args["set_discount_header"].name = string.format(L["Offspec Price: %s%%"],GuildRoll_discount*100)
         -- Minimum EP header update removed: now local to each admin and not updated from incoming messages
        end
      end
    end
    if msg and msg~="" then
      self:defaultPrint(msg)
    end
  end
end

-- Handler for SHARE: messages containing admin settings
-- Parses and applies received settings locally, triggers UI updates
-- message: payload like "SHARE:CSR=3;RO=1;DC=0.5;MIN=100;ALT=1.0;SC=GUILD"
-- sender: player name who sent the message
-- Handles SHARE messages from admins to synchronize settings across clients.
-- Uses defensive programming to handle environments where the global string table
-- may be partially overwritten or missing functions (e.g., due to addon conflicts).
-- This prevents crashes when parsing SHARE:CSR=...;RO=...;DC=...;MIN=...;ALT=...;SC=... payloads.
--
-- Testing: To verify this fix, apply it and /reload in a client that previously crashed.
-- Have an admin change CSR threshold and verify no errors occur and UI updates correctly.
-- Handler for SHARE: messages containing admin settings
-- Robust, defensive implementation compatible with Lua 5.0/5.1 environments
handleSharedSettings = function(message, sender)
  local gstring = (_G and _G.string) or string
  if not gstring then return end

  local find_func = gstring.find
  if not message or not find_func or not find_func(message, "^SHARE:") then return end
  if sender == GuildRoll._playerName then return end

  local sub_func = gstring.sub
  if not sub_func then return end
  local payload = sub_func(message, 7)

  local settings = {}
  local iterator_func = gstring.gmatch or gstring.gfind
  if iterator_func then
    for pair in iterator_func(payload, "([^;]+)") do
      local key, value
      local match_func = gstring.match
      if match_func then
        key, value = match_func(pair, "^([^=]+)=(.+)$")
      else
        local eq_pos = find_func and find_func(pair, "=", 1, true)
        if eq_pos and eq_pos > 1 and eq_pos < string.len(pair) then
          key = sub_func(pair, 1, eq_pos - 1)
          value = sub_func(pair, eq_pos + 1)
        end
      end
      if key and value then
        local gsub_func = gstring.gsub
        if gsub_func then
          value = gsub_func(value, "%%3D", "=")
          value = gsub_func(value, "%%3B", ";")
        end
        settings[key] = value
      end
    end
  else
    -- manual parse fallback using string.len instead of '#'
    local pos = 1
    local payload_len = string.len(payload)
    while pos <= payload_len do
      local semi_pos = find_func and find_func(payload, ";", pos, true)
      local pair_end = semi_pos or (payload_len + 1)
      local pair = sub_func(payload, pos, pair_end - 1)
      local eq_pos = find_func and find_func(pair, "=", 1, true)
      if eq_pos and eq_pos > 1 and eq_pos < string.len(pair) then
        local key = sub_func(pair, 1, eq_pos - 1)
        local value = sub_func(pair, eq_pos + 1)
        local gsub_func = gstring.gsub
        if gsub_func then
          value = gsub_func(value, "%%3D", "=")
          value = gsub_func(value, "%%3B", ";")
        end
        settings[key] = value
      end
      pos = pair_end + 1
    end
  end

  local changed = false
  if settings.CSR then
    local csr
    if settings.CSR == "NONE" then csr = nil else csr = tonumber(settings.CSR) end
    if csr ~= GuildRoll_CSRThreshold then GuildRoll_CSRThreshold = csr; changed = true end
  end
  -- RO removed: raid-only toggles are now local runtime-only flags, not shared
  if settings.DC then local dc = tonumber(settings.DC) if dc and dc ~= GuildRoll_decay then GuildRoll_decay = dc; changed = true end end
  -- MIN removed: Minimum EP is now local to each admin and not updated from incoming messages
  --if settings.MIN then local minep = tonumber(settings.MIN) if minep and minep ~= GuildRoll_minPE then GuildRoll_minPE = minep; changed = true end end
  if settings.ALT then local alt = tonumber(settings.ALT) if alt and alt ~= GuildRoll_altpercent then GuildRoll_altpercent = alt; changed = true end end
  if settings.SC then if settings.SC ~= GuildRoll_saychannel then GuildRoll_saychannel = settings.SC; changed = true end end
  if settings.SBR then
    local sbr = settings.SBR == "1"
    if sbr ~= GuildRoll_showAllRollButtons then GuildRoll_showAllRollButtons = sbr; changed = true end
  end

  if changed then
    pcall(function() GuildRoster() end)
    if GuildRoll.RebuildRollOptions then pcall(GuildRoll.RebuildRollOptions, GuildRoll) end
    if GuildRoll_standings and GuildRoll_standings.Refresh then pcall(GuildRoll_standings.Refresh, GuildRoll_standings) end
    if GuildRoll_logs and GuildRoll_logs.Refresh then pcall(GuildRoll_logs.Refresh, GuildRoll_logs) end
    if GuildRoll.SetRefresh then pcall(GuildRoll.SetRefresh, GuildRoll, true) end
    if GuildRoll.defaultPrint then 
      -- Defensive: safely format sender name, handle nil sender
      local senderName = sender or "Unknown"
      pcall(function() 
        GuildRoll:defaultPrint(("Admin settings updated from %s"):format(senderName)) 
      end)
    end
  end
end

-- Share admin settings to guild members via addon message
-- Broadcasts key admin settings (CSR threshold, raid_only, decay, min EP, alt percent, report channel)
-- force: if true, bypasses permission check and throttle
function GuildRoll:shareSettings(force)
  -- Check permission: only guild leader or officer can share (admin() checks CanEditOfficerNote)
  -- admin is forward-declared and will be available at runtime
  if not force and not IsGuildLeader() and not admin() then
    return
  end
  
  local now = GetTime()
  -- Throttle: don't send more than once every 30 seconds unless forced
  if self._lastSettingsShare == nil or (now - self._lastSettingsShare > 30) or (force) then
    self._lastSettingsShare = now
    
    -- Build compact payload with admin settings
    -- Format: SHARE:CSR=3;DC=0.5;ALT=1.0;SC=GUILD;SBR=0
    -- CSR can be nil (disabled), use "NONE" to represent this in the payload
    -- MIN removed: Minimum EP is now local to each admin and not shared
    -- RO removed: raid-only toggles are now local runtime-only flags, not shared
    local csr = GuildRoll_CSRThreshold
    local csrStr = csr and tostring(csr) or "NONE"
    local dc = GuildRoll_decay or self.VARS.decay
    local alt = GuildRoll_altpercent or 1.0
    local sc = GuildRoll_saychannel or "GUILD"
    local sbr = GuildRoll_showAllRollButtons and 1 or 0
    
    -- Escape special chars (= and ;) in string values if needed
    sc = string.gsub(sc, "=", "%%3D")
    sc = string.gsub(sc, ";", "%%3B")
    
    local payload = string.format("SHARE:CSR=%s;DC=%s;ALT=%s;SC=%s;SBR=%d",
      csrStr, tostring(dc), tostring(alt), sc, sbr)
    
    -- Send via existing addonMessage method for consistency
    self:addonMessage(payload, "GUILD")
    
    -- Also send legacy SETTINGS message for backwards compatibility
    -- Use neutral default for minPE to avoid leaking local admin preferences
    local addonMsg = string.format("SETTINGS;%s:%s:%s:%s:%s:%s;1",0,0,dc,self.VARS.minPE,tostring(GuildRollAltspool),alt)
    self:addonMessage(addonMsg,"GUILD")
  end
end

function GuildRoll:refreshPRTablets()
  --if not T:IsAttached("GuildRoll_standings") then
  GuildRoll_standings:Refresh()
  --end
 
end

-- Helper function to perform immediate UI refresh after EP-affecting actions
-- Refreshes standings, AdminLog, personal logs, and requests guild roster update
function GuildRoll:refreshAllEPUI()
  pcall(function() self:refreshPRTablets() end)
  if T then
    pcall(function()
      if T.IsRegistered and T:IsRegistered("GuildRoll_AdminLog") then
        T:Refresh("GuildRoll_AdminLog")
      end
    end)
    pcall(function()
      if T.IsRegistered and T:IsRegistered("GuildRoll_personal_logs") then
        T:Refresh("GuildRoll_personal_logs")
      end
    end)
  end
  -- Call GuildRoster() to request roster update from server
  pcall(function() GuildRoster() end)
end

---------------------
-- Standing Operations
---------------------



function GuildRoll:give_ep_to_raid(ep) -- awards ep to raid members in zone
  -- Validate input
  if type(ep) ~= "number" then
    UIErrorsFrame:AddMessage("Invalid EP value entered.", 1.0, 0.0, 0.0, 1.0)
    return
  end
  if ep < GuildRoll.VARS.minAward or ep > GuildRoll.VARS.maxAward then
    UIErrorsFrame:AddMessage("EP value out of range (" .. GuildRoll.VARS.minAward .. " to " .. GuildRoll.VARS.maxAward .. ")", 1.0, 0.0, 0.0, 1.0)
    return
  end
  
  if GetNumRaidMembers()>0 then
    local award = {}
    local adminName = UnitName("player")
    local raid_data = {
      players = {},
      counts = {},
      alt_sources = {}  -- Track which alt triggered each main's award (main_name -> alt_name mapping)
    }
    
    for i = 1, GetNumRaidMembers(true) do
      local name, rank, subgroup, level, class, fileName, zone, online, isDead = GetRaidRosterInfo(i)
      if level >= GuildRoll.VARS.minlevel then
        local actualName = name
        local actualEP = ep
        local postfix = ""
        local sourceAlt = nil  -- Track if this award came from an alt
        
        -- Handle alt -> main mapping if Altspool enabled
        if (GuildRollAltspool) then
          local main = self:parseAlt(name)
          if (main) then
            local alt = name
            actualName = main
            actualEP = self:num_round(GuildRoll_altpercent*ep)
            postfix = string.format(L[", %s\'s Main."],alt)
            sourceAlt = alt  -- Remember the alt that triggered this award
          end
        end
        
        -- Skip if already awarded in this call (check the actual target name)
        if not GuildRoll:TFind(award, actualName) then
          -- Get old EP and calculate new EP
          local old = (self:get_ep_v3(actualName) or 0)
          local newep = actualEP + old
          
          -- Update EP with special_action="RAID" for local personal log
          for j = 1, GetNumGuildMembers(1) do
            local gname, _, _, _, gclass, _, gnote, gofficernote, _, _ = GetGuildRosterInfo(j)
            if gname == actualName then
              self:update_epgp_v3(newep, nil, j, gname, gofficernote, "RAID")
              break
            end
          end
          
          -- Send addon message to individual player with RAID flag
          local addonMsg = string.format("%s;%s;%s;RAID", actualName, "MainStanding", actualEP)
          self:addonMessage(addonMsg, "GUILD")
          
          -- Add player to raid_data for consolidated log entry
          table.insert(raid_data.players, actualName)
          raid_data.counts[actualName] = {old = old, new = newep}
          if sourceAlt then
            raid_data.alt_sources[actualName] = self:StripRealm(sourceAlt)
          end
          
          table.insert(award, actualName)
        end
      end
    end
    
    -- Create a single consolidated raid entry in AdminLog
    if self:IsAdmin() and table.getn(raid_data.players) > 0 then
      if GuildRoll.AdminLogAddRaid then
        pcall(function()
          GuildRoll:AdminLogAddRaid(ep, raid_data)
        end)
      end
    end
    
    -- Send single public message about raid award
    self:simpleSay(string.format(L["Giving %d MainStanding to all raidmembers"],ep))
    
    -- Immediate UI refresh after raid award
    self:refreshAllEPUI()
  else UIErrorsFrame:AddMessage(L["You aren't in a raid dummy"],1,0,0)end
end

-- Backward-compatible wrapper for award_raid_ep
function GuildRoll:award_raid_ep(ep)
  return self:give_ep_to_raid(ep)
end


function GuildRoll:PromptAwardRaidEP()
  if not GuildRoll:IsAdmin() then
    self:defaultPrint(L["You don't have permission to award EP."])
    return
  end
  
  -- Check if player is in a raid
  local numRaid = GetNumRaidMembers()
  if numRaid == 0 then
    self:defaultPrint(L["BuffCheck_NotInRaid"] or "You are not in a raid.")
    return
  end
  
  StaticPopup_Show("GUILDROLL_AWARD_EP_RAID_HELP")
end

-- Helper function to update the GiveEP dialog content when target changes
-- Can be called on a visible dialog to refresh its content
function GuildRoll:UpdateGiveEPDialog(frame)
  if not frame then
    return
  end
  
  -- Read from frame.data with fallback to legacy field and pending variable
  local targetName = frame.data or frame.guildroll_target or GuildRoll._pendingGiveEPTarget
  
  -- Clear pending variable when consumed
  if targetName and targetName == GuildRoll._pendingGiveEPTarget then
    GuildRoll._pendingGiveEPTarget = nil
  end
  
  -- Get the text element for the dialog
  local textElement = getglobal(frame:GetName().."Text")
  local editBox = getglobal(frame:GetName().."EditBox")
  
  if not targetName then
    if textElement then
      textElement:SetText("Error: No target specified")
    end
    if editBox then
      editBox:SetText("")
    end
    return
  end
  
  -- Determine the effective recipient (main if alt, otherwise selected)
  local currentEP = 0
  local headerString = ""
  
  -- Try to parse alt -> main
  local mainName
  local parseSuccess, parseMain = pcall(function() return GuildRoll:parseAlt(targetName) end)
  if parseSuccess and parseMain then
    mainName = parseMain
  end
  
  if mainName then
    -- This is an alt with a main - show "Giving EP to MainName (main of AltName); current EP: X"
    local epSuccess, ep = pcall(function() return GuildRoll:get_ep_v3(mainName) end)
    if epSuccess and ep then
      currentEP = ep
    end
    headerString = string.format(L["GIVING_EP_MAIN_OF_ALT"], mainName, targetName, currentEP)
  else
    -- This is a main or alt without main found - show "Giving EP to CharName; current EP: X"
    local epSuccess, ep = pcall(function() return GuildRoll:get_ep_v3(targetName) end)
    if epSuccess and ep then
      currentEP = ep
    end
    headerString = string.format(L["GIVING_EP_TO_CHAR"], targetName, currentEP)
  end
  
  if textElement then
    textElement:SetText(headerString)
  end
  if editBox then
    editBox:SetText("")
    editBox:SetFocus()
  end
end

function GuildRoll:ShowGiveEPDialog(targetName)
  if not GuildRoll:IsAdmin() then
    return
  end
  if not targetName then
    return
  end

  -- Store target in pending variable before calling StaticPopup_Show to handle race conditions
  GuildRoll._pendingGiveEPTarget = targetName

  -- Pass targetName as the data parameter to avoid the OnShow race condition
  local ok, dialog = pcall(function()
    return StaticPopup_Show("GUILDROLL_GIVE_EP", nil, nil, targetName)
  end)

  if not ok then
    -- StaticPopup_Show failed for some reason; fail silently to avoid hard errors
    -- Schedule delayed clear of pending variable
    pcall(function()
      GuildRoll:ScheduleEvent("GuildRoll_ClearPendingGiveEP", function()
        GuildRoll._pendingGiveEPTarget = nil
      end, 1)
    end)
    return
  end

  if dialog then
    -- Defensive: ensure .data is set (older or modified clients may not set it)
    pcall(function()
      if not dialog.data then dialog.data = targetName end
      -- preserve legacy field for backward compatibility
      dialog.guildroll_target = targetName
    end)
    -- Clear pending variable (will be cleared again in UpdateGiveEPDialog, but do it early for safety)
    GuildRoll._pendingGiveEPTarget = nil
    -- Refresh dialog content immediately (handles case where dialog was already visible)
    pcall(function()
      GuildRoll:UpdateGiveEPDialog(dialog)
    end)
  else
    -- StaticPopup_Show returned nil (queued); attempt to locate existing frame
    local foundFrame = nil
    pcall(function()
      local maxDialogs = STATICPOPUP_NUMDIALOGS or 4
      for i = 1, maxDialogs do
        local frameName = "StaticPopup" .. i
        local frame = getglobal(frameName)
        if frame and frame.which == "GUILDROLL_GIVE_EP" then
          frame.data = targetName
          frame.guildroll_target = targetName
          foundFrame = frame
          break
        end
      end
    end)
    
    if foundFrame then
      -- Successfully set dialog fields on existing frame, clear pending and refresh content
      GuildRoll._pendingGiveEPTarget = nil
      pcall(function()
        GuildRoll:UpdateGiveEPDialog(foundFrame)
      end)
    else
      -- Unable to set dialog immediately; schedule delayed clear of pending variable
      pcall(function()
        GuildRoll:ScheduleEvent("GuildRoll_ClearPendingGiveEP", function()
          GuildRoll._pendingGiveEPTarget = nil
        end, 1)
      end)
    end
  end
end

function GuildRoll:give_ep_to_member(getname,ep,block) -- awards ep to a single character
  if not (admin()) then return end

  -- Validate EP value
  if type(ep) ~= "number" then
    self:defaultPrint(L["Invalid EP value entered."])
    return false, getname
  end
  if ep < GuildRoll.VARS.minAward or ep > GuildRoll.VARS.maxAward then
    self:defaultPrint(string.format(L["EP value out of range (%s to %s)"], GuildRoll.VARS.minAward, GuildRoll.VARS.maxAward))
    return false, getname
  end

  -- PUG support removed: do not call self:isPug
  local postfix, alt = ""

  -- Keep alt -> main handling if Altspool is enabled
  if (GuildRollAltspool) then
    local main = self:parseAlt(getname)
    if (main) then
      alt = getname
      getname = main
      ep = self:num_round(GuildRoll_altpercent*ep)
      postfix = string.format(L[", %s\'s Main."],alt)
    end
  end

  if GuildRoll:TFind(block, getname) then
    self:debugPrint(string.format("Skipping %s, already awarded.",getname))
    return false, getname
  end
  local old =  (self:get_ep_v3(getname) or 0)
  local newep = ep + old
  self:update_ep_v3(getname,newep)
  self:debugPrint(string.format(L["Giving %d MainStanding to %s%s. (Previous: %d, New: %d)"],ep,getname,postfix,old, newep))
  
  -- Always announce, log, and send addon message for both positive and negative EP
  local msg
  local logMsg
  
  -- Build compact AdminLog format: PlayerName - EP: Prev -> New (±N)
  local deltaStr
  if ep >= 0 then
    deltaStr = string.format("+%d", ep)
  else
    deltaStr = string.format("%d", ep)
  end
  logMsg = string.format("%s - EP: %d -> %d (%s)", getname, old, newep, deltaStr)
  
  -- Build announcement message
  if ep < 0 then
    msg = string.format(L["%s MainStanding Penalty to %s%s. (Previous: %d, New: %d)"],ep,getname,postfix,old, newep)
  else
    msg = string.format(L["Giving %d MainStanding to %s%s. (Previous: %d, New: %d)"],ep,getname,postfix,old, newep)
  end
  
  self:adminSay(msg)
  self:addToLog(logMsg)
  local addonMsg = string.format("%s;%s;%s",getname,"MainStanding",ep)
  self:addonMessage(addonMsg,"GUILD")
  
  -- Add AdminLog and personal log entries with alt tag if alt-pooling was applied
  if alt then
    -- Alt-pooling was applied: add tagged AdminLog and personal logs
    local altNameClean = self:StripRealm(alt)
    local mainNameClean = self:StripRealm(getname)
    
    -- AdminLog entry: "[GIVE] %d EP given to %s (%s) by %s"
    if self.AdminLogAdd then
      pcall(function()
        local adminLogText = string.format("[GIVE] %d EP given to %s (%s) by %s", ep, mainNameClean, altNameClean, self:GetAdminName())
        self:AdminLogAdd(adminLogText)
      end)
    end
    
    -- Personal log for main: "EP received via alt AltName: +%d EP (Prev: %d, New: %d)"
    if self.personalLogAdd then
      pcall(function()
        local mainLogText = string.format("EP received via alt %s: %s EP (Prev: %d, New: %d)", altNameClean, deltaStr, old, newep)
        self:personalLogAdd(getname, mainLogText)
      end)
    end
    
    -- Personal log for alt: "EP awarded to main MainName (redirect): +%d EP (Prev: %d, New: %d)"
    if self.personalLogAdd then
      pcall(function()
        local altLogText = string.format("EP awarded to main %s (redirect): %s EP (Prev: %d, New: %d)", mainNameClean, deltaStr, old, newep)
        self:personalLogAdd(alt, altLogText)
      end)
    end
  end
  
  -- Immediate UI refresh
  self:refreshAllEPUI()
  
  return false, getname
end

-- Backward-compatible wrappers for givename_ep
function GuildRoll:givename_ep(getname,ep,block)
  return self:give_ep_to_member(getname,ep,block)
end







function GuildRoll:decay_ep_v3()
  if not (admin()) then return end
  local memberCount = 0
  for i = 1, GetNumGuildMembers(1) do
    local name,_,_,_,class,_,note,officernote,_,_ = GetGuildRosterInfo(i)
    local ep = self:get_ep_v3(name,officernote)
    if (ep~=nil) then
      ep = self:num_round(ep*GuildRoll_decay)
      self:update_epgp_v3(ep,nil,i,name,officernote,"DECAY")
      memberCount = memberCount + 1
    end
  end
  local decayPercent = (1 - (GuildRoll_decay or GuildRoll.VARS.decay)) * 100
  local msg = string.format(L["DecayAnnounce"], decayPercent)
  self:simpleSay(msg)
  if not (GuildRoll_saychannel=="OFFICER") then self:adminSay(msg) end
  local addonMsg = string.format("ALL;DECAY;%s",decayPercent)
  self:addonMessage(addonMsg,"GUILD")
  self:addToLog(msg)
  
  -- Add single AdminLog summary entry for decay
  if self.AdminLogAdd then
    pcall(function()
      local adminLogText = string.format("[DECAY] Applied %.0f%% decay to %d members by %s", decayPercent, memberCount, self:GetAdminName())
      self:AdminLogAdd(adminLogText)
    end)
  end
  
  -- Immediate UI refresh after decay
  self:refreshAllEPUI()
end

-- Backward-compatible wrapper for decay_epgp_v3
function GuildRoll:decay_epgp_v3()
  return self:decay_ep_v3()
end



function GuildRoll:reset_ep_v3()
  if (IsGuildLeader()) then
    for i = 1, GetNumGuildMembers(1) do
      local name,_,_,_,class,_,note,officernote,_,_ = GetGuildRosterInfo(i)
      local ep = self:get_ep_v3(name,officernote)
      if ep then
        self:update_epgp_v3(0,nil,i,name,officernote)
      end
    end
    local msg = "All EP has been reset to 0."
    self:debugPrint(msg)
    self:adminSay(msg)
    self:addToLog(msg)
    
    -- Add single AdminLog summary entry for reset
    if self.AdminLogAdd then
      pcall(function()
        local adminLogText = string.format("[RESET] Standing reset by %s", self:GetAdminName())
        self:AdminLogAdd(adminLogText)
      end)
    end
    
    -- Immediate UI refresh after reset
    self:refreshAllEPUI()
  end
end

-- Backward-compatible wrapper for ep_reset_v3
function GuildRoll:ep_reset_v3()
  return self:reset_ep_v3()
end



function GuildRoll:my_epgp_announce(use_main)
  local ep
  if (use_main) then
    ep = self:get_ep_v3(GuildRoll_main) or 0
  else
    ep = self:get_ep_v3(self._playerName) or 0
  end
  local msg = string.format(L["You now have: %d MainStanding"], ep)
  self:defaultPrint(msg)
end

function GuildRoll:my_epgp(use_main)
  GuildRoster()
  self:ScheduleEvent("guildrollRosterRefresh",self.my_epgp_announce,3,self,use_main)
end

---------
-- Menu
---------
GuildRoll.hasIcon = "Interface\\Icons\\INV_Misc_ArmorKit_19"
GuildRoll.title = "guildroll"
GuildRoll.defaultMinimapPosition = 180
GuildRoll.defaultPosition = "RIGHT"
GuildRoll.cannotDetachTooltip = true
GuildRoll.tooltipHiddenWhenEmpty = false
GuildRoll.independentProfile = true

-- Constant for maximum number of detached frames to scan
local MAX_DETACHED_FRAMES = 100

function GuildRoll:OnTooltipUpdate()
  -- Build hint body (Tablet-2.0 adds "Hint:" label automatically)
  local hint = ""

  -- Common hints (one line per hint)
  local common = {
    "|cffffff00Click|r to toggle Standings.",
    "|cffffff00Shift+Click|r to toggle Roll UI.",
    "|cffffff00Right-Click|r for Options.",
    "|cffffff00Ctrl+Click|r to toggle Log.",
  }

  for _, line in ipairs(common) do
    if hint == "" then
      hint = line
    else
      hint = hint .. "\n" .. line
    end
  end

  -- Extra hints (shown only to admins)
  if admin() then
    hint = hint .. "\n" .. "|cffffff00Alt+Click|r to toggle Alts."
    hint = hint .. "\n" .. "|cffffff00Ctrl+Shift+Click|r to toggle Admin Log."
  end

  T:SetHint(hint)
end

function GuildRoll:OnClick(button)
  button = button or "LeftButton"
  if button == "RightButton" then
    self:OnMenuRequest()
    return
  end
  local alt = IsAltKeyDown()
  local ctrl = IsControlKeyDown()
  local shift = IsShiftKeyDown()
  local is_admin = admin()
  
  -- Ctrl+Shift+Click: Toggle Admin Log if admin, otherwise open Personal Log
  -- No permission denied messages for non-admin
  if ctrl and shift and not alt then
    if is_admin then
      -- Admin: toggle new AdminLog module
      -- Ensure module is enabled before calling Toggle (wrapped in pcall for safety)
      if GuildRoll_AdminLog and GuildRoll_AdminLog.Toggle then
        pcall(function()
          -- Enable module if not already active (triggers OnEnable which registers with Tablet)
          GuildRoll:ToggleModuleActive("GuildRoll_AdminLog", true)
          GuildRoll_AdminLog:Toggle()
        end)
      end
    else
      -- Not admin: open Personal Log as fallback (no error message)
      if GuildRoll and GuildRoll.ShowPersonalLog then
        pcall(function() GuildRoll:ShowPersonalLog() end)
      elseif GuildRoll and GuildRoll.SavePersonalLog then
        pcall(function() GuildRoll:SavePersonalLog() end)
      end
    end
    return
  end
  
  -- Ctrl+Click: Always toggle Personal Log (no duplicate checks)
  if ctrl and not shift and not alt then
    if GuildRoll and GuildRoll.ShowPersonalLog then
      pcall(function() GuildRoll:ShowPersonalLog() end)
    elseif GuildRoll and GuildRoll.SavePersonalLog then
      pcall(function() GuildRoll:SavePersonalLog() end)
    end
    return
  end

  -- Alt+Click: Toggle Alts (admin-only)
  if alt and not ctrl and not shift then
    if is_admin then
      if GuildRollAlts and GuildRollAlts.Toggle then
        pcall(function()
          GuildRoll:ToggleModuleActive("GuildRollAlts", true)
          GuildRollAlts:Toggle()
        end)
      end
    end
    return
  end
  if shift and not alt and not ctrl then
    local f = _G and _G["GuildEpRollFrame"]
    if f then
      if f:IsShown() then f:Hide() else f:Show() end
    end
    return
  end
  if GuildRoll_standings and GuildRoll_standings.Toggle then
    pcall(function() GuildRoll_standings:Toggle() end)
  end
end

function GuildRoll:SetRefresh(flag)
  needRefresh = flag
  if (flag) then
    self:refreshPRTablets()
  end
end

function GuildRoll:buildRosterTable()
  local g, r = { }, { }
  local numGuildMembers = GetNumGuildMembers(1)
  if (GuildRoll_memberlist_raidonly) and GetNumRaidMembers() > 0 then
    for i = 1, GetNumRaidMembers(true) do
      local name, rank, subgroup, level, class, fileName, zone, online, isDead = GetRaidRosterInfo(i) 
      if (name) then
        r[name] = true
      end
    end
  end
  GuildRoll.alts = {}
  for i = 1, numGuildMembers do
    local member_name,_,_,level,class,_,note,officernote,_,_ = GetGuildRosterInfo(i)
    if member_name and member_name ~= "" then
      local main, main_class, main_rank = self:parseAlt(member_name,officernote)
      local is_raid_level = tonumber(level) and level >= GuildRoll.VARS.minlevel
      if (main) then
        if ((self._playerName) and (member_name == self._playerName)) then
          if (not GuildRoll_main) or (GuildRoll_main and GuildRoll_main ~= main) then
            GuildRoll_main = main
            self:defaultPrint(string.format(L["Your main has been set to %s"],GuildRoll_main))
          end
        end
        main = C:Colorize(BC:GetHexColor(main_class), main)
        GuildRoll.alts[main] = GuildRoll.alts[main] or {}
        GuildRoll.alts[main][member_name] = class
      end
      if (GuildRoll_memberlist_raidonly) and next(r) then
        if r[member_name] and is_raid_level then
          table.insert(g,{["name"]=member_name,["class"]=class})
        end
      else
        if is_raid_level then
          table.insert(g,{["name"]=member_name,["class"]=class})
        end
      end
    end
  end
  return g
end

function GuildRoll:buildClassMemberTable(roster,epgp)
  local desc,usage
  if epgp == "MainStanding" then
    desc = L["Account MainStanding to %s."]
    usage = "<EP>"
  elseif epgp == "AuxStanding" then
    desc = L["Account AuxStanding to %s."]
    usage = "<EP>"
  end
  local c = { }
  for i,member in ipairs(roster) do
    local class,name = member.class, member.name
    if (class) and (c[class] == nil) then
      c[class] = { }
      c[class].type = "group"
      c[class].name = C:Colorize(BC:GetHexColor(class),class)
      c[class].desc = class .. " members"
      c[class].hidden = function() return not (admin()) end
      c[class].args = { }
    end
    if (name) and (c[class].args[name] == nil) then
      c[class].args[name] = { }
      if epgp == "MainStanding" then
        c[class].args[name].type = "execute"
        c[class].args[name].name = name
        c[class].args[name].desc = string.format(desc,name)
        c[class].args[name].func = function() GuildRoll:ShowGiveEPDialog(name) end
      elseif epgp == "AuxStanding" then
        c[class].args[name].type = "text"
        c[class].args[name].name = name
        c[class].args[name].desc = string.format(desc,name)
        c[class].args[name].usage = usage
        c[class].args[name].get = false
        c[class].args[name].set = function(v) GuildRoll:givename_ep(name, tonumber(v)) GuildRoll:refreshPRTablets() end
        c[class].args[name].validate = function(v) 
          local num = tonumber(v)
          return (type(v) == "number" or num) 
            and num >= GuildRoll.VARS.minAward 
            and num <= GuildRoll.VARS.maxAward 
        end
      end
    end
  end
  return c
end

-- Build class-grouped member table for DE/Bank selection
function GuildRoll:buildDEBankMemberTable(raidMembers)
  local c = {}
  
  -- Add "Clear" option at the top
  c["clear_de_bank"] = {
    type = "execute",
    name = L["Clear"],
    desc = "Clear DE/Bank player assignment",
    order = 1,
    func = function()
      if GuildRoll and GuildRoll.RollWithEP_SetDEBank then
        pcall(function() GuildRoll.RollWithEP_SetDEBank(nil) end)
      end
    end
  }
  
  -- Add "Members" submenu with class groups
  c["members"] = {
    type = "group",
    name = "Members",
    desc = "Select a raid member to receive DE/Bank items",
    order = 2,
    args = {}
  }
  
  -- Group members by class
  for i, member in ipairs(raidMembers) do
    local class, name = member.class, member.name
    if class and c["members"].args[class] == nil then
      c["members"].args[class] = {}
      c["members"].args[class].type = "group"
      c["members"].args[class].name = C:Colorize(BC:GetHexColor(class), class)
      c["members"].args[class].desc = class .. " members"
      c["members"].args[class].args = {}
    end
    if name and c["members"].args[class].args[name] == nil then
      c["members"].args[class].args[name] = {}
      c["members"].args[class].args[name].type = "execute"
      c["members"].args[class].args[name].name = name
      c["members"].args[class].args[name].desc = "Set " .. name .. " as DE/Bank player"
      c["members"].args[class].args[name].func = function()
        if GuildRoll and GuildRoll.RollWithEP_SetDEBank then
          pcall(function() GuildRoll.RollWithEP_SetDEBank(name) end)
        end
      end
    end
  end
  
  return c
end

---------------
-- Alts
---------------
function GuildRoll:parseAlt(name,officernote)
  if (officernote) then
    local _,_,_,main,_ = string.find(officernote or "","(.*){([%a][%a]%a*)}(.*)")
    if type(main)=="string" and (string.len(main) < 13) then
      main = self:camelCase(main)
      local g_name, g_class, g_rank, g_officernote = self:verifyGuildMember(main)
      if (g_name) then
        return g_name, g_class, g_rank, g_officernote
      else
        return nil
      end
    else
      return nil
    end
  else
    -- Strip realm suffix from input name for comparison
    local nameClean = name and string.gsub(name, "%-[^%-]+$", "") or ""
    
    for i=1,GetNumGuildMembers(1) do
      local g_name, _, _, _, g_class, _, g_note, g_officernote, _, _ = GetGuildRosterInfo(i)
      -- Strip realm suffix from guild member name for comparison
      local g_nameClean = g_name and string.gsub(g_name, "%-[^%-]+$", "") or ""
      
      if (nameClean == g_nameClean) then
        return self:parseAlt(g_name, g_officernote)
      end
    end
  end
  return nil
end

-- ProcessSetMainInput: Process user input for setting main character
-- inputMain: user-provided main character name
-- This function verifies the name, sets GuildRoll_main, and optionally
-- adds {MainName} tag to the public note of the current character if it's an alt.
function GuildRoll:ProcessSetMainInput(inputMain)
  if not inputMain or inputMain == "" then
    self:defaultPrint("Please provide a character name.")
    return
  end
  
  -- Verify the main character exists in guild
  local verified = self:verifyGuildMember(inputMain, true)
  if not verified then
    self:defaultPrint(string.format("'%s' not found in the guild or not at required level.", inputMain))
    return
  end
  
  -- Set GuildRoll_main
  GuildRoll_main = verified
  
  -- Check if this is the logged-in character
  if GuildRoll_main == self._playerName then
    self:defaultPrint("This is your Main.")
    return
  end
  
  -- Create the main tag with the actual main character name
  local mainTag = string.format("{%s}", verified)
  
  -- Find the logged-in player's guild roster index
  local playerIndex, playerPublicNote, playerOfficerNote
  for i = 1, GetNumGuildMembers(1) do
    local name, _, _, _, _, _, publicNote, officerNote, _, _ = GetGuildRosterInfo(i)
    if name == self._playerName then
      playerIndex = i
      playerPublicNote = publicNote or ""
      playerOfficerNote = officerNote or ""
      break
    end
  end
  
  if not playerIndex then
    self:defaultPrint("Could not find your character in the guild roster.")
    return
  end
  
  -- Check if officer note already contains a main tag (any {name} pattern, min 2 chars)
  if string.find(playerOfficerNote, "{%a%a%a*}") then
    self:defaultPrint("This is an Alt already.")
    return
  end
  
  -- Check if public note already contains the main tag
  if string.find(playerPublicNote, mainTag, 1, true) then
    self:defaultPrint("Alt setup ready (public note already contained tag).")
    return
  end
  
  -- Append main tag to public note
  local newPublic = _trim_public_with_tag(playerPublicNote, mainTag, MAX_NOTE_LEN)
  
  -- Write the new public note (wrapped in pcall for safety)
  local success, err = pcall(function()
    GuildRosterSetPublicNote(playerIndex, newPublic)
  end)
  
  if not success then
    self:defaultPrint("Failed to update public note. You may not have permission.")
    return
  end
  
  -- Notify admins to run migration
  self:addonMessage("MIGRATE_MAIN_TAG_REQUEST", "GUILD")
  
  self:defaultPrint("Alt setup ready.")
end

-- PromptSetMainIfMissing: Show popup if GuildRoll_main is not set
function GuildRoll:PromptSetMainIfMissing()
  if (GuildRoll_main == nil) or (GuildRoll_main == "") then
    if (IsInGuild()) then
      StaticPopup_Show("GUILDROLL_SET_MAIN_PROMPT")
    end
  end
end

-- CheckAltAndPromptSetMain: Check if player is an Alt (rank="Alt", level>=60, no main tag in officer note)
-- and prompt them to set their main character
function GuildRoll:CheckAltAndPromptSetMain()
  -- Safety check: ensure we're in a guild
  if not IsInGuild() then
    return
  end
  
  -- Get player level (prefer UnitLevel, fallback to roster level)
  local playerLevel = UnitLevel("player")
  
  -- Attempt to get guild roster info with pcall for safety
  local success, numMembers = pcall(GetNumGuildMembers, 1)
  if not success or not numMembers or numMembers == 0 then
    -- Roster not available yet
    return
  end
  
  -- Strip realm suffix from player name for comparison
  local playerName = string.gsub(self._playerName, "%-.*$", "")
  
  -- Search for the player in the guild roster
  local playerRank, playerOfficerNote, rosterLevel
  for i = 1, numMembers do
    local success2, name, rank, rankIndex, level, class, zone, note, officernote, online = pcall(GetGuildRosterInfo, i)
    if success2 and name then
      -- Strip realm suffix from roster name
      local rosterName = string.gsub(name, "%-.*$", "")
      if rosterName == playerName then
        playerRank = rank
        playerOfficerNote = officernote or ""
        rosterLevel = level
        break
      end
    end
  end
  
  -- If player not found in roster, exit
  if not playerRank then
    return
  end
  
  -- Use roster level as fallback if UnitLevel didn't work
  if not playerLevel or playerLevel == 0 then
    playerLevel = rosterLevel
  end
  
  -- Check condition 1: rank name equals "Alt" (case-sensitive)
  if playerRank ~= "Alt" then
    return
  end
  
  -- Check condition 2: player level >= 60
  -- Level 60 is the maximum level in Classic WoW
  local levelNum = tonumber(playerLevel) or 0
  if levelNum < 60 then
    return
  end
  
  -- Check condition 3: officer note does NOT contain a main tag {Name}
  -- Pattern {%a%a%a*} matches { followed by at least 2 letters then }
  if string.find(playerOfficerNote, "{%a%a%a*}") then
    return
  end
  
  -- All conditions met: show the prompt
  StaticPopup_Show("GUILDROLL_SET_MAIN_PROMPT")
end

-- MovePublicMainTagsToOfficerNotes: Admin function to migrate main tags from public to officer notes
-- Requires admin permission (GuildRoll:IsAdmin)
-- Iterates through guild roster and moves {MainName} tags from public note to officer note
-- Returns: number of tags moved
function GuildRoll:MovePublicMainTagsToOfficerNotes()
  if not GuildRoll:IsAdmin() then
    self:defaultPrint("You do not have permission to edit officer notes.")
    return 0
  end
  
  local movedCount = 0
  local numMembers = GetNumGuildMembers(1)
  
  -- Validate numMembers is a valid number
  if not numMembers or type(numMembers) ~= "number" or numMembers < 1 then
    return 0
  end
  
  for i = 1, numMembers do
    -- Wrap GetGuildRosterInfo in pcall for safety
    local success, name, r2, r3, r4, r5, r6, publicNote, officerNote, r9, r10 = pcall(function()
      return GetGuildRosterInfo(i)
    end)
    
    -- Process only if GetGuildRosterInfo succeeded and returned valid data
    if success and name then
      publicNote = publicNote or ""
      officerNote = officerNote or ""
      
      -- Ensure publicNote and officerNote are strings
      if type(publicNote) == "string" and type(officerNote) == "string" then
        -- Check if public note contains a main tag pattern {name} (min 2 chars)
        local mainTag = string.match(publicNote, "({%a%a%a*})")
        if mainTag and type(mainTag) == "string" and string.len(mainTag) > 2 then
          -- Insert main tag before {EP:GP} in officer note first (to avoid data loss)
          local newOfficer = _insertTagBeforeEP(officerNote, mainTag)
          
          -- Validate newOfficer is a string before writing
          if type(newOfficer) == "string" then
            -- Write officer note first (wrapped in pcall for safety)
            local successOfficer = pcall(function()
              GuildRosterSetOfficerNote(i, newOfficer, true)
            end)
            
            -- Only remove from public note if officer note write succeeded
            if successOfficer then
              movedCount = movedCount + 1
              
              -- Escape pattern characters for safe replacement
              local escapedTag = string.gsub(mainTag, "([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
              -- Remove only first occurrence of the main tag from public note
              local newPublic = string.gsub(publicNote, escapedTag, "", 1)
              
              -- Trim leading and trailing whitespace
              newPublic = string.gsub(newPublic, "^%s*(.-)%s*$", "%1")
              
              -- If empty, use a single space to ensure server accepts it
              if newPublic == "" then
                newPublic = " "
              end
              
              -- Attempt to write public note (removal is best-effort)
              pcall(function()
                GuildRosterSetPublicNote(i, newPublic)
              end)
            end
          end
        end
      end
    end
  end
  
  -- Only print summary if at least one tag was moved
  if movedCount > 0 then
    self:defaultPrint(string.format("Migration complete. Moved %d main tags from public to officer notes.", movedCount))
  end
  
  return movedCount
end


------------
-- Logging
------------
function GuildRoll:addToLog(line,skipTime)
  -- For admins: use the new synchronized AdminLog system only
  if self:IsAdmin() then
    -- Add to synchronized AdminLog (broadcasts to all admins)
    if GuildRoll.AdminLogAdd then
      pcall(function()
        GuildRoll:AdminLogAdd(line)
      end)
    end
  end
  -- For non-admins: do nothing (admin actions only recorded in AdminLog)
  -- Personal logs are maintained separately via personalLogAdd
end

------------
-- Utility 
------------

function GuildRoll:inRaid(name)
  for i=1,GetNumRaidMembers() do
    if name == (UnitName(raidUnit[i])) then
      return true
    end
  end
  return false
end

function GuildRoll:lootMaster()
  local method, lootmasterID = GetLootMethod()
  if method == "master" and lootmasterID == 0 then
    return true
  else
    return false
  end
end

function GuildRoll:testMain()
  self:PromptSetMainIfMissing()
end

-- suggestedAwardMainStanding: Returns suggested EP award for main standing
-- Calls GetReward() defensively with pcall and returns that value if present and numeric;
-- otherwise returns GuildRoll.VARS.baseawardpoints as a fallback.
function GuildRoll:suggestedAwardMainStanding()
  local success, isMainStanding, reward = pcall(function()
    return GuildRoll.GetReward()
  end)
  
  if success and not isMainStanding and reward and type(reward) == "number" then
    return reward
  end
  
  return GuildRoll.VARS.baseawardpoints
end

-- suggestedAwardAuxStanding: Returns suggested EP award for aux standing
-- Calls GetReward() defensively with pcall and returns that value if present and numeric;
-- otherwise returns GuildRoll.VARS.baseawardpoints as a fallback.
function GuildRoll:suggestedAwardAuxStanding()
  local success, isMainStanding, reward = pcall(function()
    return GuildRoll.GetReward()
  end)
  
  if success and isMainStanding and reward and type(reward) == "number" then
    return reward
  end
  
  return GuildRoll.VARS.baseawardpoints
end

-- IsAdmin: Unified admin permission check with fallback (NO local forced override)
-- Returns true if player can edit officer notes or is guild leader
-- Uses pcall for robustness in case APIs are missing or modified
function GuildRoll:IsAdmin()
  -- Try CanEditOfficerNote first (wrapped in pcall)
  if CanEditOfficerNote then
    local ok, result = pcall(function() return CanEditOfficerNote() end)
    if ok and result then
      return true
    end
  end

  -- Fallback to IsGuildLeader (wrapped in pcall)
  if IsGuildLeader then
    local ok, result = pcall(function() return IsGuildLeader() end)
    if ok and result then
      return true
    end
  end

  -- No local forced override present anymore — only real permissions count
  return false
end

-- Consolidate permission checks for roll management
-- Returns true if current player can manage rolls, false otherwise
-- Also returns a reason string for logging if false
function GuildRoll:CanManageRolls()
  -- Must be admin first
  if not self:IsAdmin() then
    return false, "Not an admin"
  end
  
  -- Get master looter and raid leader info
  local mlIndex = GetLootMethod()
  local mlPartyIndex, mlRaidIndex
  
  if mlIndex and mlIndex > 0 then
    if mlIndex <= 4 then
      mlPartyIndex = mlIndex
    else
      mlRaidIndex = mlIndex
    end
  end
  
  local playerName = UnitName("player")
  local masterLooterName = nil
  
  if mlPartyIndex then
    masterLooterName = UnitName("party"..mlPartyIndex)
  elseif mlRaidIndex then
    masterLooterName = UnitName("raid"..mlRaidIndex)
  end
  
  -- If there's a master looter set
  if masterLooterName and masterLooterName ~= "" then
    -- If ML is not the current player, only ML can manage rolls
    if masterLooterName ~= playerName then
      return false, "Master Looter is set and it's not you"
    end
    -- If ML is the current player, they can manage (and they're already admin)
    return true
  end
  
  -- No master looter set, check if player is raid leader
  local isRaidLeader = false
  if GetNumRaidMembers() > 0 then
    -- In a raid
    for i = 1, GetNumRaidMembers() do
      local name, rank = GetRaidRosterInfo(i)
      if name == playerName and rank == 2 then
        isRaidLeader = true
        break
      end
    end
  elseif GetNumPartyMembers() > 0 then
    -- In a party, check if leader
    if UnitIsPartyLeader("player") then
      isRaidLeader = true
    end
  else
    -- Solo, NOT allowed (requirement: only active when ML or RL in group/raid)
    return false, "Solo player cannot use RollWithEP"
  end
  
  if isRaidLeader then
    return true
  end
  
  return false, "Not Master Looter or Raid Leader"
end

-- admin: Local wrapper for backward compatibility
-- Calls GuildRoll:IsAdmin() to maintain existing code functionality
admin = function()
  return GuildRoll:IsAdmin()
end

sanitizeNote = function(prefix,epgp,postfix)
  -- reserve 12 chars for the epgp pattern {xxxxx:yyyy} max public/officernote = 31
  local remainder = string.format("%s%s",prefix,postfix)
  local clip = math.min(31-12,string.len(remainder))
  local prepend = string.sub(remainder,1,clip)
  return string.format("%s%s",prepend,epgp)
end

-------------
-- Dialogs
-------------

StaticPopupDialogs["SET_MAIN"] = {
  text = L["Set Main"],
  button1 = TEXT(ACCEPT),
  button2 = TEXT(CANCEL),
  hasEditBox = 1,
  maxLetters = 12,
  OnAccept = function()
    local editBox = getglobal(this:GetParent():GetName().."EditBox")
    local name = GuildRoll:camelCase(editBox:GetText())
    GuildRoll_main = GuildRoll:verifyGuildMember(name)
  end,
  OnShow = function()
    getglobal(this:GetName().."EditBox"):SetText(GuildRoll_main or "")
    getglobal(this:GetName().."EditBox"):SetFocus()
  end,
  OnHide = function()
    if ( ChatFrameEditBox:IsVisible() ) then
      ChatFrameEditBox:SetFocus()
    end
    getglobal(this:GetName().."EditBox"):SetText("")
  end,
  EditBoxOnEnterPressed = function()
    local editBox = getglobal(this:GetParent():GetName().."EditBox")
    GuildRoll_main = GuildRoll:verifyGuildMember(editBox:GetText())
    this:GetParent():Hide()
  end,
  EditBoxOnEscapePressed = function()
    this:GetParent():Hide()
  end,
  timeout = 0,
  exclusive = 1,
  whileDead = 1,
  hideOnEscape = 1  
}

StaticPopupDialogs["GUILDROLL_SET_MAIN_PROMPT"] = {
  text = L["Set Main"],
  button1 = TEXT(ACCEPT),
  button2 = TEXT(CANCEL),
  hasEditBox = 1,
  maxLetters = 12,
  OnAccept = function()
    local editBox = getglobal(this:GetParent():GetName().."EditBox")
    local text = editBox:GetText()
    if text and text ~= "" then
      GuildRoll:ProcessSetMainInput(text)
    end
  end,
  OnShow = function()
    getglobal(this:GetName().."EditBox"):SetText(GuildRoll_main or "")
    getglobal(this:GetName().."EditBox"):SetFocus()
  end,
  OnHide = function()
    if ( ChatFrameEditBox:IsVisible() ) then
      ChatFrameEditBox:SetFocus()
    end
    getglobal(this:GetName().."EditBox"):SetText("")
  end,
  EditBoxOnEnterPressed = function()
    local editBox = getglobal(this:GetParent():GetName().."EditBox")
    local text = editBox:GetText()
    if text and text ~= "" then
      GuildRoll:ProcessSetMainInput(text)
    end
    this:GetParent():Hide()
  end,
  EditBoxOnEscapePressed = function()
    this:GetParent():Hide()
  end,
  timeout = 0,
  exclusive = 1,
  whileDead = 1,
  hideOnEscape = 1  
}

-- StaticPopupDialogs keys must be unique. Double confirmation for EP reset:
-- First dialog warns about the action, second dialog requires final confirmation.
StaticPopupDialogs["CONFIRM_RESET"] = {
  text = L["|cffff0000Are you sure you want to Reset ALL Standing?|r"],
  button1 = TEXT(OKAY),
  button2 = TEXT(CANCEL),
  OnAccept = function()
    StaticPopup_Show("CONFIRM_RESET_FINAL")
  end,
  timeout = 0,
  whileDead = 1,
  exclusive = 1,
  showAlert = 1,
  hideOnEscape = 1
}

StaticPopupDialogs["CONFIRM_RESET_FINAL"] = {
  text = L["|cffff0000This will reset ALL player Standing to 0. This action cannot be undone!\n\nAre you ABSOLUTELY sure?|r"],
  button1 = TEXT(OKAY),
  button2 = TEXT(CANCEL),
  OnAccept = function()
    GuildRoll:reset_ep_v3()
  end,
  timeout = 0,
  whileDead = 1,
  exclusive = 1,
  showAlert = 1,
  hideOnEscape = 1
}

StaticPopupDialogs["GUILDROLL_AWARD_EP_RAID_HELP"] = {
  text = L["Enter EP to award to raid members:"],
  button1 = TEXT(ACCEPT),
  button2 = TEXT(CANCEL),
  hasEditBox = 1,
  maxLetters = 10,
  OnShow = function()
    local zoneHelp = {
      NAX = {prefill = 7, text = "Naxx - 7 EP for FLASK/attendance."},
      AQ40 = {prefill = 5, text = "AQ40 - 5 EP for FLASK/attendance."},
      BWL = {prefill = 3, text = "BWL - 3 EP for CONSUMMS/attendance."},
      ES = {prefill = 3, text = "ES  - 3 EP for CONSUMMS/attendance."},
      MC = {prefill = 2, text = "MC  - 2 EP for CONSUMMS/attendance."}
    }
    
    local suggested = GuildRoll.VARS.baseawardpoints
    local success, result = pcall(function() return GuildRoll:suggestedAwardMainStanding() end)
    if success and result then
      suggested = result
    end
    
    local helpText = L["Enter EP to award to raid members:"]
    local prefillValue = suggested
    
    local inInstance, instanceType = IsInInstance()
    if inInstance then
      local zoneLoc = GetRealZoneText()
      if BZ:HasReverseTranslation(zoneLoc) then
        local zoneEN = BZ:GetReverseTranslation(zoneLoc)
        if zoneEN then
          local LocKey = RaidKey[zoneEN]
          if LocKey and zoneHelp[LocKey] then
            helpText = zoneHelp[LocKey].text .. "\n\nEnter EP (editable):"
            prefillValue = zoneHelp[LocKey].prefill
          end
        end
      end
    end
    
    getglobal(this:GetName().."Text"):SetText(helpText)
    getglobal(this:GetName().."EditBox"):SetText(tostring(prefillValue))
    getglobal(this:GetName().."EditBox"):SetFocus()
  end,
  OnAccept = function()
    local editBox = getglobal(this:GetParent():GetName().."EditBox")
    local epValue = tonumber(editBox:GetText())
    if not epValue then
      UIErrorsFrame:AddMessage(L["Invalid EP value entered."], 1.0, 0.0, 0.0, 1.0)
      return
    end
    if epValue < GuildRoll.VARS.minAward or epValue > GuildRoll.VARS.maxAward then
      UIErrorsFrame:AddMessage(string.format(L["EP value out of range (%s to %s)"], GuildRoll.VARS.minAward, GuildRoll.VARS.maxAward), 1.0, 0.0, 0.0, 1.0)
      return
    end
    if not GuildRoll:IsAdmin() then
      GuildRoll:defaultPrint(L["You don't have permission to award EP."])
      return
    end
    GuildRoll:give_ep_to_raid(epValue)
  end,
  EditBoxOnEnterPressed = function()
    local parent = this:GetParent()
    local editBox = getglobal(parent:GetName().."EditBox")
    local epValue = tonumber(editBox:GetText())
    if not epValue then
      UIErrorsFrame:AddMessage(L["Invalid EP value entered."], 1.0, 0.0, 0.0, 1.0)
      return
    end
    if epValue < GuildRoll.VARS.minAward or epValue > GuildRoll.VARS.maxAward then
      UIErrorsFrame:AddMessage(string.format(L["EP value out of range (%s to %s)"], GuildRoll.VARS.minAward, GuildRoll.VARS.maxAward), 1.0, 0.0, 0.0, 1.0)
      return
    end
    if not GuildRoll:IsAdmin() then
      UIErrorsFrame:AddMessage(L["You don't have permission to award EP."], 1.0, 0.0, 0.0, 1.0)
      return
    end
    GuildRoll:give_ep_to_raid(epValue)
    parent:Hide()
  end,
  EditBoxOnEscapePressed = function()
    this:GetParent():Hide()
  end,
  timeout = 0,
  exclusive = 1,
  whileDead = 1,
  hideOnEscape = 1
}

StaticPopupDialogs["GUILDROLL_CLEAR_PERSONAL_LOG"] = {
  text = L["This will permanently delete your personal log. Continue?"],
  button1 = TEXT(ACCEPT),
  button2 = TEXT(CANCEL),
  OnAccept = function()
    local playerName = GuildRoll._playerName
    if playerName then
      -- Clear both saved and runtime personal logs
      GuildRoll_personalLogSaved[playerName] = nil
      GuildRoll_personalLogs[playerName] = nil
      -- Refresh the personal log view
      if GuildRoll_logs and GuildRoll_logs.RefreshPersonal then
        GuildRoll_logs:RefreshPersonal()
      end
      -- Show confirmation message
      if GuildRoll and GuildRoll.defaultPrint then
        GuildRoll:defaultPrint(L["Personal log cleared"])
      end
    end
  end,
  timeout = 0,
  exclusive = 1,
  whileDead = 1,
  hideOnEscape = 1
}

StaticPopupDialogs["GUILDROLL_CONFIRM_DECAY"] = {
  text = "",  -- Set dynamically based on current decay percentage
  button1 = TEXT(OKAY),
  button2 = TEXT(CANCEL),
  OnShow = function()
    -- Calculate decay percentage to display
    local decayPercent = (1 - (GuildRoll_decay or GuildRoll.VARS.decay)) * 100
    local message = string.format(L["Are you sure you want to decay all Standing by %s%%? This cannot be undone."], decayPercent)
    getglobal(this:GetName().."Text"):SetText(message)
  end,
  OnAccept = function()
    -- Extra safety check: verify user is admin before executing decay
    if not GuildRoll:IsAdmin() then
      return
    end
    
    -- Execute decay with pcall to avoid hard errors
    local success, err = pcall(function()
      GuildRoll:decay_ep_v3()
    end)
    if not success and err then
      if GuildRoll.debugPrint then
        GuildRoll:debugPrint("Error during decay: "..tostring(err))
      end
    end
  end,
  timeout = 0,
  exclusive = 1,
  whileDead = 1,
  hideOnEscape = 1
}

StaticPopupDialogs["GUILDROLL_GIVE_EP"] = {
  text = "",  -- Set dynamically in OnShow
  button1 = TEXT(ACCEPT),
  button2 = TEXT(CANCEL),
  hasEditBox = 1,
  maxLetters = 10,
  OnShow = function()
    -- Read from this.data (set by StaticPopup_Show) with fallback to legacy field and pending variable
    local targetName = this.data or this.guildroll_target or GuildRoll._pendingGiveEPTarget
    
    -- Clear pending variable when consumed
    if targetName and targetName == GuildRoll._pendingGiveEPTarget then
      GuildRoll._pendingGiveEPTarget = nil
    end
    
    if not targetName then
      getglobal(this:GetName().."Text"):SetText("Error: No target specified")
      return
    end
    
    -- Determine the effective recipient (main if alt, otherwise selected)
    local currentEP = 0
    local headerString = ""
    
    -- Try to parse alt -> main
    local mainName
    local parseSuccess, parseMain = pcall(function() return GuildRoll:parseAlt(targetName) end)
    if parseSuccess and parseMain then
      mainName = parseMain
    end
    
    if mainName then
      -- This is an alt with a main - show "Giving EP to MainName (main of AltName); current EP: X"
      local epSuccess, ep = pcall(function() return GuildRoll:get_ep_v3(mainName) end)
      if epSuccess and ep then
        currentEP = ep
      end
      headerString = string.format(L["GIVING_EP_MAIN_OF_ALT"], mainName, targetName, currentEP)
    else
      -- This is a main or alt without main found - show "Giving EP to CharName; current EP: X"
      local epSuccess, ep = pcall(function() return GuildRoll:get_ep_v3(targetName) end)
      if epSuccess and ep then
        currentEP = ep
      end
      headerString = string.format(L["GIVING_EP_TO_CHAR"], targetName, currentEP)
    end
    
    getglobal(this:GetName().."Text"):SetText(headerString)
    getglobal(this:GetName().."EditBox"):SetText("")
    getglobal(this:GetName().."EditBox"):SetFocus()
  end,
  OnAccept = function()
    local parent = this:GetParent()
    -- Read from parent.data (set by StaticPopup_Show) with fallback to legacy field
    local targetName = parent.data or parent.guildroll_target
    if not targetName then
      return
    end
    
    local editBox = getglobal(parent:GetName().."EditBox")
    local epValue = tonumber(editBox:GetText())
    if not epValue then
      UIErrorsFrame:AddMessage(L["Invalid EP value entered."], 1.0, 0.0, 0.0, 1.0)
      return
    end
    
    -- Call give_ep_to_member which handles validation, alt->main conversion, scaling, logging
    local success, err = pcall(function() GuildRoll:give_ep_to_member(targetName, epValue) end)
    if not success then
      UIErrorsFrame:AddMessage("Error awarding EP: " .. tostring(err), 1.0, 0.0, 0.0, 1.0)
      DEFAULT_CHAT_FRAME:AddMessage("|cffff0000Error awarding EP to " .. tostring(targetName) .. ": " .. tostring(err) .. "|r")
    else
      -- Request guild roster update from server
      pcall(function() GuildRoster() end)
      -- Schedule a delayed refresh to allow roster data to update (2 seconds delay)
      pcall(function()
        GuildRoll:ScheduleEvent("GuildRoll_RefreshAfterEPAward", function()
          GuildRoll:refreshPRTablets()
        end, 2)
      end)
    end
    
    -- Clear pending variables to prevent stale data on next dialog open
    pcall(function()
      GuildRoll._pendingGiveEPTarget = nil
      parent.data = nil
      parent.guildroll_target = nil
    end)
  end,
  EditBoxOnEnterPressed = function()
    local parent = this:GetParent()
    -- Read from parent.data (set by StaticPopup_Show) with fallback to legacy field
    local targetName = parent.data or parent.guildroll_target
    if not targetName then
      parent:Hide()
      return
    end
    
    local editBox = getglobal(parent:GetName().."EditBox")
    local epValue = tonumber(editBox:GetText())
    if not epValue then
      UIErrorsFrame:AddMessage(L["Invalid EP value entered."], 1.0, 0.0, 0.0, 1.0)
      parent:Hide()
      return
    end
    
    -- Call give_ep_to_member which handles validation, alt->main conversion, scaling, logging
    pcall(function() GuildRoll:give_ep_to_member(targetName, epValue) end)
    GuildRoll:refreshPRTablets()
    
    -- Clear pending variables to prevent stale data on next dialog open
    pcall(function()
      GuildRoll._pendingGiveEPTarget = nil
      parent.data = nil
      parent.guildroll_target = nil
    end)
    
    parent:Hide()
  end,
  EditBoxOnEscapePressed = function()
    this:GetParent():Hide()
  end,
  OnHide = function()
    if ( ChatFrameEditBox:IsVisible() ) then
      ChatFrameEditBox:SetFocus()
    end
    getglobal(this:GetName().."EditBox"):SetText("")
    
    -- Clear pending variables and dialog fields to prevent stale data on next dialog open
    pcall(function()
      GuildRoll._pendingGiveEPTarget = nil
      this.data = nil
      this.guildroll_target = nil
    end)
  end,
  timeout = 0,
  exclusive = 1,
  whileDead = 1,
  hideOnEscape = 1
}


function GuildRoll:EasyMenu_Initialize(level, menuList)
  for i, info in ipairs(menuList) do
    if (info.text) then
      info.index = i
      UIDropDownMenu_AddButton( info, level )
    end
  end
end
function GuildRoll:EasyMenu(menuList, menuFrame, anchor, x, y, displayMode, level)
  if ( displayMode == "MENU" ) then
    menuFrame.displayMode = displayMode
  end
  UIDropDownMenu_Initialize(menuFrame, function() GuildRoll:EasyMenu_Initialize(level, menuList) end, displayMode, level)
  ToggleDropDownMenu(1, nil, menuFrame, anchor, x, y)
end
-- Returns the base roll value for the player.
-- Now returns only EP (MainStanding). GP (AuxStanding) is no longer used.
function GuildRoll:GetBaseRollValue(ep)
    return ep
end

function GuildRoll:RollCommand(isSRRoll, bonus)
  local playerName = UnitName("player")
  local ep = 0 
  local desc = ""  
  -- Check if the player is an alt
  if GuildRollAltspool then
    local main = self:parseAlt(playerName)
    if main then
      -- If the player is an alt, use the main's EP
      ep = self:get_ep_v3(main) or 0
      desc = "Alt of "..main
    else
      -- If not an alt, use the player's own EP
      ep = self:get_ep_v3(playerName) or 0
      desc = "Main"
    end
  else
    -- If alt pooling is not enabled, just use the player's EP
    ep = self:get_ep_v3(playerName) or 0
    desc = "Main"
  end
  
  -- Calculate the roll range based on whether it's an SR roll or not
  local minRoll, maxRoll
  local baseRoll = GuildRoll:GetBaseRollValue(ep)
  -- New EP-aware roll ranges
  if isSRRoll then
    -- SR: 100 + baseRoll to 200 + baseRoll
    minRoll = 101 + baseRoll
    maxRoll = 200 + baseRoll
  else
    -- EP-aware MS: 1 + baseRoll to 100 + baseRoll
    minRoll = 1 + baseRoll
    maxRoll = 100 + baseRoll
  end
  
  -- Add bonus after range selection
  minRoll = minRoll + bonus
  maxRoll = maxRoll + bonus
	
  -- Clamp to >= 0 and ensure min <= max
  if minRoll < 0 then minRoll = 0 end
  if maxRoll < 0 then maxRoll = 0 end
  if minRoll > maxRoll then minRoll = maxRoll end

  RandomRoll(minRoll, maxRoll)
  
  -- Prepare the announcement message
  local bonusText = ""
  if string.find(desc, "^Alt of ") then
    -- Only append for alts
    bonusText = " as "..desc
  end
  local message = string.format("I rolled MS \"%d - %d\" with %d "..L["MainStanding"].."%s", minRoll, maxRoll, ep, bonusText)
  
  if(isSRRoll) then
    message = string.format("I rolled SR \"%d - %d\" with %d "..L["MainStanding"].."%s", minRoll, maxRoll, ep, bonusText)
  end

if bonus > 0 then
    local weeks = math.floor(bonus / 10)
    weeks = weeks+1
    bonusText = string.format(" +%d for %d consecutive weeks", bonus, weeks)
    message = string.format("I rolled Cumulative SR %d - %d with %d EP + 100 from SR%s", minRoll, maxRoll, ep, bonusText)
  end
	
  -- Determine the chat channel
  local chatType = UnitInRaid("player") and "RAID" or "SAY"
  
  -- Send the message
  SendChatMessage(message, chatType)
end

RaidKey = {[L["Molten Core"]]="MC",[L["Onyxia\'s Lair"]]="ONY",[L["Blackwing Lair"]]="BWL",[L["Ahn\'Qiraj"]]="AQ40",[L["Naxxramas"]]="NAX",["Tower of Karazhan"]="K10",["Upper Tower of Karazhan"]="K40",["???"]="K40"}
function GuildRoll:GetReward()

   local raw = string.gsub(string.gsub(GetGuildInfoText(),"\n","#")," ","")
   local Scores ={}
   local reward = GuildRoll.VARS.baseawardpoints
  for tier in string.gfind(raw,"(B[^:]:[^:]+:[^#]+#)") do
        local _,_,dungeons,rewards = string.find(tier,"B[^:]:([^:]+):([^#]+)#")
        local ds =  GuildRoll:strsplitT(",",dungeons)
        local ss =  GuildRoll:strsplitT(",",rewards)

        for i, key in ipairs(ds) do
		 local n= i
		    if (i>table.getn(ss)) then 
			     n = table.getn(ss)
		    end
		    
		    Scores[key]=ss[n]
           -- DEFAULT_CHAT_FRAME:AddMessage( key .."="..ss[n] )
	    end
         

  end

  
   

  local isMainStanding = false, zoneEN, zoneLoc,LocKey  
  local inInstance, instanceType = IsInInstance()
  if (inInstance == nil) or (instanceType ~= nil and instanceType == "none") then
        isMainStanding = false
  end
  if (inInstance) then --and (instanceType == "raid") then
    zoneLoc = GetRealZoneText()
   -- DEFAULT_CHAT_FRAME:AddMessage("zoneLoc:"..zoneLoc )
    if (BZ:HasReverseTranslation(zoneLoc)) then
      zoneEN = BZ:GetReverseTranslation(zoneLoc)
     -- DEFAULT_CHAT_FRAME:AddMessage("zoneEN:".. zoneEN)
      if zoneEN then
             if (zoneEN == "Tower of Karazhan") then
                local mapFileName, textureHeight, textureWidth, isMicrodungeon, microDungeonMapName = GetMapInfo();
                if mapFileName == "KarazhanUpper" then
                    zoneEN = "Upper Tower of Karazhan"
                end
            end
        LocKey = RaidKey[zoneEN]
        if LocKey then
          --  DEFAULT_CHAT_FRAME:AddMessage("LocKey:".. LocKey)

            if Scores[LocKey] =="main"then
                reward = 15
            else
                isMainStanding = true
                reward = tonumber (Scores[LocKey])
            end
            if reward then
            --    DEFAULT_CHAT_FRAME:AddMessage("reward:".. reward)
            
            end 
        end 
        end 
    end

    return isMainStanding , reward
  end

end

function GuildRoll:GetGuildName()
	local guildName, _, _ = GetGuildInfo("player")
	return guildName
end
 
function GuildRoll:GetRaidLeader()
for i = 1, GetNumRaidMembers() do
	local name, rank, _, _, _, _, _, online  = GetRaidRosterInfo(i);
	if (rank == 2) then return i,name,online end
end
	return ""
end

function GuildRoll:GetRaidLeadGuild() 
	local guildName = nil
    local index,name,online = GuildRoll:GetRaidLeader()
	
	if UnitExists("raid"..index) then
		 
	  local guildName, _, _ = GetGuildInfo("raid"..index)
		 
	  if guildName then
			if (guildName == "") then return "!" end
		 return guildName
	  else
		 return "!!"
	  end
	else
	  return "!!"
	end

end
 
function GuildRoll:GetGuildKey(g) 
	return (string.gsub(g ," ",""))
end
 

local lastHostInfoDispatch = 0
local HostInfoRequestsSinceLastDispatch = 0

function GuildRoll:SendMessage(subject, msg , prio)
	prio = prio or "BULK"
	GuildRollMSG:DBGMSG("--SendingAddonMSG["..subject.."]:"..msg , true) 
    if GetNumRaidMembers() == 0 then
       -- SendAddonMessage(GuildRollMSG.prefix..subject, msg, "PARTY", UnitName("player"));
		ChatThrottleLib:SendAddonMessage(prio, GuildRollMSG.prefix..subject, msg, "PARTY")
    else
		ChatThrottleLib:SendAddonMessage(prio, GuildRollMSG.prefix..subject, msg, "RAID")
    end
end
function GuildRollMSG:DBGMSG(msg)
		GuildRollMSG:DBGMSG(msg, false)
end
function GuildRollMSG:DBGMSG(msg, red)
	if GuildRollMSG.dbg then 
		if red then
			DEFAULT_CHAT_FRAME:AddMessage( msg ,0.5,0.5,0.8 )   
		else
			DEFAULT_CHAT_FRAME:AddMessage( msg ,0.9,0.5,0.5 ) 
		end
	end
end

function GuildRollMSG:OnCHAT_MSG_ADDON( prefix, text, channel, sender)
		
	
	if ( GuildRollMSG.delayedinit) then  GuildRoll:addonComms(prefix,text,channel,sender) end
	 
		if (channel == "RAID" or channel == "PARTY") then
		
		if (  string.find( prefix, GuildRollMSG.prefix) ) then  
			
			
				if ( sender == UnitName("player")) then 
					--GuildRollMSG:DBGMSG("sent a message" )   
					return 
				end
				--GuildRollMSG:DBGMSG("Recieved a message" )  
				
				local _ ,raidlead = GuildRoll:GetRaidLeader()
							
			end
		end
end

-- GLOBALS: GuildRoll_saychannel,GuildRoll_groupbyclass,GuildRoll_groupbyarmor,GuildRoll_groupbyrole,GuildRoll_decay,GuildRoll_minPE,GuildRoll_main,GuildRollAltspool,GuildRoll_altpercent,GuildRoll_log,GuildRoll_dbver,GuildRoll_debug,GuildRoll_fubar,GuildRoll_showRollWindow
-- GLOBALS: GuildRoll,GuildRoll_prices,GuildRoll_standings,GuildRoll_bids,GuildRoll_loot,GuildRollAlts,GuildRoll_logs
