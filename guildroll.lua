GuildRoll = AceLibrary("AceAddon-2.0"):new("AceConsole-2.0", "AceHook-2.1", "AceDB-2.0", "AceDebug-2.0", "AceEvent-2.0", "AceModuleCore-2.0", "FuBarPlugin-2.0")
GuildRoll:SetModuleMixins("AceDebug-2.0")
local D = AceLibrary("Dewdrop-2.0")-- Standings table
local BZ = AceLibrary("Babble-Zone-2.2")
local C = AceLibrary("Crayon-2.0") -- chat color
local BC = AceLibrary("Babble-Class-2.2") 
--local DF = AceLibrary("Deformat-2.0")
--local G = AceLibrary("Gratuity-2.0")
local T = AceLibrary("Tablet-2.0") -- tooltips
local L = AceLibrary("AceLocale-2.2"):new("guildroll")
GuildRoll.VARS = {
  baseAE = 0,
  AERollCap = 50,
  CSRWeekBonus = 10,  -- Bonus per week for CSR (weeks 2-15: (weeks-1)*10)
  minPE = 0,
  baseawardpoints = 10,
  decay = 0.5,
  max = 1000,
  timeout = 60,
  minlevel = 1,
  maxloglines = 500,
  prefix = "RRG_",
  inRaid = false,
  bop = C:Red("BoP"),
  boe = C:Yellow("BoE"),
  nobind = C:White("NoBind"), 
  bankde = "Bank-D/E",
  reminder = C:Red("Unassigned"), 
  HostGuildName = "!",
  HostLeadName = "!" 
}

GuildRollMSG = {
	delayedinit = false,
	dbg= false,
	prefix = "RR_",
	RequestHostInfoUpdate = "RequestHostInfoUpdate",
	RequestHostInfoUpdateTS = 0,
	HostInfoUpdate = "HostInfoUpdate",
	PugStandingUpdate = "PugStandingUpdate"

}
GuildRoll._playerName = (UnitName("player"))
local out = "|cff9664c8guildroll:|r %s"
local raidStatus,lastRaidStatus
local lastUpdate = 0
local needInit,needRefresh = true
local admin,sanitizeNote
local shooty_debugchat
local running_check,running_bid
local partyUnit,raidUnit = {},{}
local hexColorQuality = {}

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
    options.args["MainStanding"] = {
      type = "group",
      name = L["+MainStanding to Member"],
      desc = L["Account MainStanding for member."],
      order = 10,
      hidden = function() return not (admin()) end,
    }
    options.args["MainStanding_raid"] = {
      type = "execute",
      name = L["+MainStanding to Raid"],
      desc = L["Award MainStanding to all raid members."],
      order = 20,
      func = function() GuildRoll:PromptAwardRaidEP() end,
      hidden = function() return not (admin()) end,
    }
 
    options.args["alts"] = {
      type = "toggle",
      name = L["Enable Alts"],
      desc = L["Allow Alts to use Main\'s Standing."],
      order = 63,
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
    options.args["alts_percent"] = {
      type = "range",
      name = L["Alts MainStanding %"],
      desc = L["Set the % MainStanding Alts can earn."],
      order = 66,
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
    options.args["set_main"] = {
      type = "text",
      name = L["Set Main"],
      desc = L["Set your Main Character."],
      order = 70,
      usage = "<MainChar>",
      get = function() return GuildRoll_main end,
      set = function(v) GuildRoll_main = (GuildRoll:verifyGuildMember(v)) end,
    }    
    options.args["raid_only"] = {
      type = "toggle",
      name = L["Raid Only"],
      desc = L["Only show members in raid."],
      order = 80,
      get = function() return not not GuildRoll_raidonly end,
      set = function(v) 
        GuildRoll_raidonly = not GuildRoll_raidonly
        GuildRoll:SetRefresh(true)
      end,
    }
    options.args["report_channel"] = {
      type = "text",
      name = L["Reporting channel"],
      desc = L["Channel used by reporting functions."],
      order = 95,
      hidden = function() return not (admin()) end,
      get = function() return GuildRoll_saychannel end,
      set = function(v) GuildRoll_saychannel = v end,
      validate = { "PARTY", "RAID", "GUILD", "OFFICER" },
    }    
    options.args["decay"] = {
      type = "execute",
      name = L["Decay Standing"],
      desc = string.format(L["Decays all Standing by %s%%"],(1-(GuildRoll_decay or GuildRoll.VARS.decay))*100),
      order = 100,
      hidden = function() return not (admin()) end,
      func = function() GuildRoll:decay_epgp_v3() end 
    }    
    options.args["set_decay"] = {
      type = "range",
      name = L["Set Decay %"],
      desc = L["Set Decay percentage (Admin only)."],
      order = 110,
      usage = "<Decay>",
      get = function() return (1.0-GuildRoll_decay) end,
      set = function(v) 
        GuildRoll_decay = (1 - v)
        options.args["decay"].desc = string.format(L["Decays all Standing by %s%%"],(1-GuildRoll_decay)*100)
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

    options.args["set_min_ep_header"] = {
      type = "header",
      name = string.format(L["Minimum MainStanding: %s"],GuildRoll_minPE),
      order = 117,
      hidden = function() return not admin() end,
    }
		
		
    options.args["set_min_ep"] = {
      type = "text",
      name = L["Minimum MainStanding"],
      desc = L["Set Minimum MainStanding"],
      usage = "<minPE>",
      order = 118,
      get = function() return GuildRoll_minPE end,
      set = function(v) 
        GuildRoll_minPE = tonumber(v)
        GuildRoll:refreshPRTablets()
        if (IsGuildLeader()) then
          GuildRoll:shareSettings(true)
        end        
      end,
      validate = function(v) 
        local n = tonumber(v)
        return n and n >= 0 and n <= GuildRoll.VARS.max
      end,
      hidden = function() return not admin() end,
    }
    options.args["reset"] = {
     type = "execute",
     name = L["Reset Standing"],
     desc = string.format(L["Resets everyone\'s Standing to 0/%d (Admin only)."],GuildRoll.VARS.baseAE),
     order = 120,
     hidden = function() return not (IsGuildLeader()) end,
     func = function() StaticPopup_Show("RET_EP_CONFIRM_RESET") end
    }
    -- options.args["resetAuxStanding"] = {
    -- type = "execute",
    -- name = L["Reset AuxStanding"],
    -- desc = string.format(L["Resets everyone\'s AuxStanding to 0/%d (Admin only)."],GuildRoll.VARS.baseAE),
    -- order = 122,
    -- hidden = function() return not (IsGuildLeader()) end,
    -- func = function() StaticPopup_Show("RET_GP_CONFIRM_RESET") end
    -- }

  end
  if (needInit) or (needRefresh) then
    local members = GuildRoll:buildRosterTable()
    self:debugPrint(string.format(L["Scanning %d members for Standing data. (%s)"],table.getn(members),(GuildRoll_raidonly and "Raid" or "Full")))
    options.args["MainStanding"].args = GuildRoll:buildClassMemberTable(members,"MainStanding")
    if (needInit) then needInit = false end
    if (needRefresh) then needRefresh = false end
  end
  return options
end

function GuildRoll:OnInitialize() -- ADDON_LOADED (1) unless LoD
  if GuildRoll_saychannel == nil then GuildRoll_saychannel = "GUILD" end
  if GuildRoll_decay == nil then GuildRoll_decay = GuildRoll.VARS.decay end
  if GuildRoll_minPE == nil then GuildRoll_minPE = GuildRoll.VARS.minPE end
 -- if GuildRoll_progress == nil then GuildRoll_progress = "T1" end
 -- if GuildRoll_discount == nil then GuildRoll_discount = 0.25 end
  if GuildRollAltspool == nil then GuildRollAltspool = true end
  if GuildRoll_altpercent == nil then GuildRoll_altpercent = 1.0 end
  if GuildRoll_log == nil then GuildRoll_log = {} end
  if GuildRoll_looted == nil then GuildRoll_looted = {} end
  if GuildRoll_debug == nil then GuildRoll_debug = {} end
  if GuildRoll_pugCache == nil then GuildRoll_pugCache = {} end 
  --if GuildRoll_showRollWindow == nil then GuildRoll_showRollWindow = true end
  self:RegisterDB("GuildRoll_fubar")
  self:RegisterDefaults("char",{})
  --table.insert(GuildRoll_debug,{[date("%b/%d %H:%M:%S")]="OnInitialize"})
end

function GuildRoll:OnEnable() -- PLAYER_LOGIN (2)
  --table.insert(GuildRoll_debug,{[date("%b/%d %H:%M:%S")]="OnEnable"})
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
     -- GuildRoll:testLootPrompt()
    end)
  self:RegisterEvent("PARTY_MEMBERS_CHANGED",function()
      GuildRoll:SetRefresh(true)
     -- GuildRoll:testLootPrompt()
    end)
  self:RegisterEvent("PLAYER_ENTERING_WORLD",function()
      GuildRoll:SetRefresh(true)
     -- GuildRoll:testLootPrompt()
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
 -- self:RegisterEvent("CHAT_MSG_RAID","captureLootCall")
 -- self:RegisterEvent("CHAT_MSG_RAID_LEADER","captureLootCall")
 -- self:RegisterEvent("CHAT_MSG_RAID_WARNING","captureLootCall")
 -- self:RegisterEvent("CHAT_MSG_WHISPER","captureBid")
 -- self:RegisterEvent("CHAT_MSG_LOOT","captureLoot")
 -- self:RegisterEvent("TRADE_PLAYER_ITEM_CHANGED","tradeLoot")
 -- self:RegisterEvent("TRADE_ACCEPT_UPDATE","tradeLoot")

  if AceLibrary("AceEvent-2.0"):IsFullyInitialized() then
    self:AceEvent_FullyInitialized()
  else
    self:RegisterEvent("AceEvent_FullyInitialized")
  end
end

function GuildRoll:OnDisable()

--DEFAULT_CHAT_FRAME:AddMessage("GuildRoll:OnDisable()") 
  --table.insert(GuildRoll_debug,{[date("%b/%d %H:%M:%S")]="OnDisable"})
  self:UnregisterAllEvents()
end

function GuildRoll:AceEvent_FullyInitialized() -- SYNTHETIC EVENT, later than PLAYER_LOGIN, PLAYER_ENTERING_WORLD (3)
  --table.insert(GuildRoll_debug,{[date("%b/%d %H:%M:%S")]="AceEvent_FullyInitialized"})
  if self._hasInitFull then return end
  
  for i=1,NUM_CHAT_WINDOWS do
    local tab = getglobal("ChatFrame"..i.."Tab")
    local cf = getglobal("ChatFrame"..i)
    local tabName = tab:GetText()
    if tab ~= nil and (string.lower(tabName) == "debug") then
      shooty_debugchat = cf
      ChatFrame_RemoveAllMessageGroups(shooty_debugchat)
      shooty_debugchat:SetMaxLines(1024)
      break
    end
  end

  self:testMain()

  local delay = 2
  if self:IsEventRegistered("AceEvent_FullyInitialized") then
    self:UnregisterEvent("AceEvent_FullyInitialized")
    delay = 3
  end  
  if not self:IsEventScheduled("guildrollChannelInit") then
    self:ScheduleEvent("guildrollChannelInit",self.delayedInit,delay,self)
  end

  -- if pfUI loaded, skin the extra tooltip
 --if not IsAddOnLoaded("pfUI-addonskins") then
 --  if (pfUI) and pfUI.api and pfUI.api.CreateBackdrop and pfUI_config and pfUI_config.tooltip and pfUI_config.tooltip.alpha then
 --    pfUI.api.CreateBackdrop(GuildRoll.extratip,nil,nil,tonumber(pfUI_config.tooltip.alpha))
 --  end
 --end

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
  --table.insert(GuildRoll_debug,{[date("%b/%d %H:%M:%S")]="delayedInit"})
  GuildRoll.VARS.GuildName  =""
  if (IsInGuild()) then
    GuildRoll.VARS.GuildName  = (GetGuildInfo("player"))
  end
   
  local major_ver = 0 --self._version.major or 0
 -- if IsGuildLeader() and ( (GuildRoll_dbver == nil) or (major_ver > GuildRoll_dbver) ) then
 --   GuildRoll[string.format("v%dtov%d",(GuildRoll_dbver or 2),major_ver)](GuildRoll)
 -- end
 
  -- init options and comms
  self._options = self:buildMenu()
  self:RegisterChatCommand({"/GuildRoll","/guildroll","/ret"},self.cmdtable())
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
  
  self:RegisterChatCommand({"/retcsr"}, function(input)
    local bonus = GuildRoll:calculateBonus(input)
    if bonus == nil then
      self:defaultPrint("Invalid CSR input. Please enter a number between 0 and 15.")
      return
    end
    self:RollCommand(true, bonus)
  end)
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
  end
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
    local _,_,_,oldepgp,_ = string.find(prevnote or "","(.*)({%d+:%d+})(.*)")
    local _,_,_,epgp,_ = string.find(note or "","(.*)({%d+:%d+})(.*)")
    if (GuildRollAltspool) then
      local oldmain = self:parseAlt(name,prevnote)
      local main = self:parseAlt(name,note)
      if oldmain ~= nil then
        if main == nil or main ~= oldmain then 
		 local isbnk, pugname = GuildRoll:isBank(name)
			if isbnk then
				GuildRoll:ReportPugManualEdit(pugname , epgp )
			end
          self:adminSay(string.format(L["Manually modified %s\'s note. Previous main was %s"],name,oldmain))
          self:defaultPrint(string.format(L["|cffff0000Manually modified %s\'s note. Previous main was %s|r"],name,oldmain))
        end
      end
    end    
    if oldepgp ~= nil then
      if epgp == nil or epgp ~= oldepgp then
		 local isbnk, pugname = GuildRoll:isBank(name)
			if isbnk then
				GuildRoll:ReportPugManualEdit(pugname , epgp )
			end
        self:adminSay(string.format(L["Manually modified %s\'s note. Standing was %s"],name,oldepgp))
        self:defaultPrint(string.format(L["|cffff0000Manually modified %s\'s note. Standing was %s|r"],name,oldepgp))
      end
    end
    local safenote = string.gsub(note,"(.*)({%d+:%d+})(.*)",sanitizeNote)
    return self.hooks["GuildRosterSetOfficerNote"](index,safenote)    
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
  if (shooty_debugchat) then
    shooty_debugchat:AddMessage(string.format(out,msg))
    self:flashFrame(shooty_debugchat)
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
  if not prefix == self.VARS.prefix then return end -- we don't care for messages from other addons
  if sender == self._playerName then return end -- we don't care for messages from ourselves
  local name_g,class,rank = self:verifyGuildMember(sender,true)
  if not (name_g) then return end -- only accept messages from guild members
  local who,what,amount
  for name,epgp,change in string.gfind(message,"([^;]+);([^;]+);([^;]+)") do
    who=name
    what=epgp
    amount=tonumber(change)
  end
  if (who) and (what) and (amount) then
    local msg
    local for_main = (GuildRoll_main and (who == GuildRoll_main))
    if (who == self._playerName) or (for_main) then
      if what == "MainStanding" then
        if amount < 0 then
          msg = string.format(L["You have received a %d MainStanding penalty."],amount)
        else
          msg = string.format(L["You have been awarded %d MainStanding."],amount)
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
        --if progress and progress ~= GuildRoll_progress then
        --  GuildRoll_progress = progress
        --  settings_notice = L["New raid progress"]
        --end
        --if discount and discount ~= GuildRoll_discount then
        --  GuildRoll_discount = discount
        --  if (settings_notice) then
        --    settings_notice = settings_notice..L[", offspec price %"]
        --  else
        --    settings_notice = L["New offspec price %"]
        --  end
        --end
        if minPE and minPE ~= GuildRoll_minPE then
          GuildRoll_minPE = minPE
          settings_notice = L["New Minimum MainStanding"]
          GuildRoll:refreshPRTablets()
        end
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
          local sender_rank = string.format("%s(%s)",C:Colorize(BC:GetHexColor(class),sender),rank)
          settings_notice = settings_notice..string.format(L[" settings accepted from %s"],sender_rank)
          self:defaultPrint(settings_notice)
         -- self._options.args["RollValueogress_tier_header"].name = string.format(L["Progress Setting: %s"],GuildRoll_progress)
         -- self._options.args["set_discount_header"].name = string.format(L["Offspec Price: %s%%"],GuildRoll_discount*100)
          self._options.args["set_min_ep_header"].name = string.format(L["Minimum MainStanding: %s"],GuildRoll_minPE)
        end
      end
    end
    if msg and msg~="" then
      self:defaultPrint(msg)
      self:my_epgp(for_main)
    end
  end
end

function GuildRoll:shareSettings(force)
  local now = GetTime()
  if self._lastSettingsShare == nil or (now - self._lastSettingsShare > 30) or (force) then
    self._lastSettingsShare = now
    local addonMsg = string.format("SETTINGS;%s:%s:%s:%s:%s:%s;1",0,0,GuildRoll_decay,GuildRoll_minPE,tostring(GuildRollAltspool),GuildRoll_altpercent)
    self:addonMessage(addonMsg,"GUILD")
  end
end

function GuildRoll:refreshPRTablets()
  --if not T:IsAttached("GuildRoll_standings") then
  GuildRoll_standings:Refresh()
  --end
 
end

---------------------
-- Standing Operations
---------------------


function GuildRoll:init_notes_v3(guild_index,name,officernote)
  local ep,gp = self:get_ep_v3(name,officernote), self:get_gp_v3(name,officernote)
  if  (ep ==nil or gp==nil) then
    local initstring = string.format("{%d:%d}",0,GuildRoll.VARS.baseAE)
    local newnote = string.format("%s%s",officernote,initstring)
    newnote = string.gsub(newnote,"(.*)({%d+:%d+})(.*)",sanitizeNote)
    officernote = newnote
  else
    officernote = string.gsub(officernote,"(.*)({%d+:%d+})(.*)",sanitizeNote)
  end
  GuildRosterSetOfficerNote(guild_index,officernote,true)
  return officernote
end

function GuildRoll:update_epgp_v3(ep,gp,guild_index,name,officernote,special_action)
  officernote = self:init_notes_v3(guild_index,name,officernote)
  local newnote
  if ( ep ~= nil) then 
   -- ep = math.max(0,ep)
    newnote = string.gsub(officernote,"(.*{)(%-?%d+)(:)(%-?%d+)(}.*)",function(head,oldep,divider,oldgp,tail) 
      return string.format("%s%s%s%s%s",head,ep,divider,oldgp,tail)
      end)
  end
  if (gp~= nil) then 
   -- gp =  math.max(GuildRoll.VARS.baseAE,gp)
    if (newnote) then
     
      newnote = string.gsub(newnote,"(.*{)(%-?%d+)(:)(%-?%d+)(}.*)",function(head,oldep,divider,oldgp,tail) 
        return string.format("%s%s%s%s%s",head,oldep,divider,gp,tail)
        end)
    else 
      newnote = string.gsub(officernote,"(.*{)(%-?%d+)(:)(%-?%d+)(}.*)",function(head,oldep,divider,oldgp,tail)
      
        return string.format("%s%s%s%s%s",head,oldep,divider,gp,tail)
        end)
    end
  end
  if (newnote) then 
    GuildRosterSetOfficerNote(guild_index,newnote,true)
  end
end



function GuildRoll:update_ep_v3(getname,ep)
  for i = 1, GetNumGuildMembers(1) do
    local name, _, _, _, class, _, note, officernote, _, _ = GetGuildRosterInfo(i)
    if (name==getname) then 
      self:update_epgp_v3(ep,nil,i,name,officernote)
    end
  end  
end


function GuildRoll:update_gp_v3(getname,gp)
  for i = 1, GetNumGuildMembers(1) do
    local name, _, _, _, class, _, note, officernote, _, _ = GetGuildRosterInfo(i)
    if (name==getname) then 
      self:update_epgp_v3(nil,gp,i,name,officernote) 
    end
  end  
end


function GuildRoll:get_ep_v3(getname,officernote) -- gets ep by name or note
  if (officernote) then
    local _,_,ep = string.find(officernote,".*{(%d+):%-?%d+}.*")
    return tonumber(ep)
  end
  for i = 1, GetNumGuildMembers(1) do
    local name, _, _, _, class, _, note, officernote, _, _ = GetGuildRosterInfo(i)
    local _,_,ep = string.find(officernote,".*{(%d+):%-?%d+}.*")
    if (name==getname) then return tonumber(ep) end
  end
  return
end

function GuildRoll:get_gp_v3(getname,officernote) -- gets gp by name or officernote
  if (officernote) then
    local _,_,gp = string.find(officernote,".*{%d+:(%-?%d+)}.*")
    return tonumber(gp)
  end
  for i = 1, GetNumGuildMembers(1) do
    local name, _, _, _, class, _, note, officernote, _, _ = GetGuildRosterInfo(i)
    local _,_,gp = string.find(officernote,".*{%d+:(%-?%d+)}.*")
    if (name==getname) then return tonumber(gp) end
  end
  return
end

function GuildRoll:award_raid_ep(ep) -- awards ep to raid members in zone
  if GetNumRaidMembers()>0 then
	local award = {}
    for i = 1, GetNumRaidMembers(true) do
      local name, rank, subgroup, level, class, fileName, zone, online, isDead = GetRaidRosterInfo(i)
      if level >= GuildRoll.VARS.minlevel then
		local _,mName =  self:givename_ep(name,ep,award)
		 table.insert (award, mName)
      end
    end
    self:simpleSay(string.format(L["Giving %d MainStanding to all raidmembers"],ep))
    self:addToLog(string.format(L["Giving %d MainStanding to all raidmembers"],ep))    
    local addonMsg = string.format("RAID;AWARD;%s",ep)
    self:addonMessage(addonMsg,"RAID")
    self:refreshPRTablets() 
  else UIErrorsFrame:AddMessage(L["You aren't in a raid dummy"],1,0,0)end
end
function GuildRoll:award_raid_gp(gp) -- awards gp to raid members in zone
  if not (IsGuildLeader()) then return end
  if GetNumRaidMembers()>0 then
	local award = {}
    for i = 1, GetNumRaidMembers(true) do
      local name, rank, subgroup, level, class, fileName, zone, online, isDead = GetRaidRosterInfo(i)
      if level >= GuildRoll.VARS.minlevel then
		local _,mName =  self:givename_gp(name,gp,award)
		 table.insert (award, mName)
      end
    end
    self:simpleSay(string.format(L["Giving %d AuxStanding to all raidmembers"],gp))
    self:addToLog(string.format(L["Giving %d AuxStanding to all raidmembers"],gp))    
    local addonMsg = string.format("RAID;AWARDGP;%s",gp)
    self:addonMessage(addonMsg,"RAID")
    self:refreshPRTablets() 
  else UIErrorsFrame:AddMessage(L["You aren't in a raid dummy"],1,0,0)end
end

function GuildRoll:PromptAwardRaidEP()
  if not (IsGuildLeader() or CanEditOfficerNote()) then
    self:defaultPrint("You don't have permission to award EP.")
    return
  end
  StaticPopup_Show("GUILDROLL_AWARD_EP_RAID_HELP")
end

function GuildRoll:givename_ep(getname,ep) 
	
 return GuildRoll:givename_ep(getname,ep,nil)  
end
function GuildRoll:givename_ep(getname,ep,block) -- awards ep to a single character
  if not (admin()) then return end
  local isPug, playerNameInGuild = self:isPug(getname)
  local postfix, alt = ""
  if isPug then
    -- Update MainStanding for the level 1 character in the guild
    alt = getname
    getname = playerNameInGuild
    ep = self:num_round(GuildRoll_altpercent*ep)
    postfix = string.format(", %s\'s Pug MainStanding Bank.",alt)
  elseif (GuildRollAltspool) then
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
		return isPug, getname 
  end
  local old =  (self:get_ep_v3(getname) or 0) 
  local newep = ep +old
  self:update_ep_v3(getname,newep) 
  self:debugPrint(string.format(L["Giving %d MainStanding to %s%s. (Previous: %d, New: %d)"],ep,getname,postfix,old, newep))
  if ep < 0 then -- inform admins and victim of penalties
    local msg = string.format(L["%s MainStanding Penalty to %s%s. (Previous: %d, New: %d)"],ep,getname,postfix,old, newep)
    self:adminSay(msg)
    self:addToLog(msg)
    local addonMsg = string.format("%s;%s;%s",getname,"MainStanding",ep)
    self:addonMessage(addonMsg,"GUILD")
  end  
  return isPug, getname
end


function GuildRoll:givename_gp(getname,gp) 
 return GuildRoll:givename_gp(getname,gp,nil) 
end


function GuildRoll:TFind ( t, e) 
if not t then return nil end
    for i, item in ipairs(t) do 
		if item == e then 
			return i 
		end
    end
return nil
end

function GuildRoll:givename_gp(getname,gp,block) -- awards gp to a single character
  if not (IsGuildLeader()) then return end
  local isPug, playerNameInGuild = self:isPug(getname)
  local postfix, alt = ""
  if isPug then
    -- Update gp for the level 1 character in the guild
    alt = getname
    getname = playerNameInGuild
    gp = self:num_round(GuildRoll_altpercent*gp)
    postfix = string.format(", %s\'s Pug MainStanding Bank.",alt)
  elseif (GuildRollAltspool) then
    local main = self:parseAlt(getname)
    if (main) then
      alt = getname
      getname = main
      gp = self:num_round(GuildRoll_altpercent*gp)
      postfix = string.format(L[", %s\'s Main."],alt)
    end
  end 
	if GuildRoll:TFind (block, getname) then
		self:debugPrint(string.format("Skipping %s%s, already awarded.",getname,postfix)) 
		return isPug, getname
	end
 
  local old = (self:get_gp_v3(getname) or 0) 
  local newgp = gp + old
  self:update_gp_v3(getname,newgp) 
  self:debugPrint(string.format(L["Giving %d AuxStanding to %s%s. (Previous: %d, New: %d)"],gp,getname,postfix,old, newgp))
  if gp < 0 then -- inform admins and victim of penalties
    local msg = string.format(L["%s AuxStanding Penalty to %s%s. (Previous: %d, New: %d)"],gp,getname,postfix,old, newgp)
    self:adminSay(msg)
    self:addToLog(msg)
    local addonMsg = string.format("%s;%s;%s",getname,"AuxStanding",gp)
    self:addonMessage(addonMsg,"GUILD")
  end  
  return isPug, getname
end


function GuildRoll:decay_epgp_v3()
  if not (admin()) then return end
  for i = 1, GetNumGuildMembers(1) do
    local name,_,_,_,class,_,note,officernote,_,_ = GetGuildRosterInfo(i)
    local ep,gp = self:get_ep_v3(name,officernote), self:get_gp_v3(name,officernote)
    if (ep~=nil and gp~=nil) then
      ep = self:num_round(ep*GuildRoll_decay)
      gp = self:num_round(gp*GuildRoll_decay)
      self:update_epgp_v3(ep,gp,i,name,officernote)
    end
  end
  local msg = string.format(L["All Standing decayed by %s%%"],(1-GuildRoll_decay)*100)
  self:simpleSay(msg)
  if not (GuildRoll_saychannel=="OFFICER") then self:adminSay(msg) end
  local addonMsg = string.format("ALL;DECAY;%s",(1-(GuildRoll_decay or GuildRoll.VARS.decay))*100)
  self:addonMessage(addonMsg,"GUILD")
  self:addToLog(msg)
  self:refreshPRTablets() 
end


function GuildRoll:gp_reset_v3()
  if (IsGuildLeader()) then
    for i = 1, GetNumGuildMembers(1) do
      local name,_,_,_,class,_,note,officernote,_,_ = GetGuildRosterInfo(i)
      local ep,gp = self:get_ep_v3(name,officernote), self:get_gp_v3(name,officernote)
      if (ep and gp) then
        self:update_epgp_v3(0,GuildRoll.VARS.baseAE,i,name,officernote)
      end
    end
    local msg = L["All Standing has been reset to 0/%d."]
    self:debugPrint(string.format(msg,GuildRoll.VARS.baseAE))
    self:adminSay(string.format(msg,GuildRoll.VARS.baseAE))
    self:addToLog(string.format(msg,GuildRoll.VARS.baseAE))
  end
end

function GuildRoll:ClearGP_v3()
  if (IsGuildLeader()) then
    for i = 1, GetNumGuildMembers(1) do
      local name,_,_,_,class,_,note,officernote,_,_ = GetGuildRosterInfo(i)
      local ep,gp = self:get_ep_v3(name,officernote), self:get_gp_v3(name,officernote)
      if (ep and gp) then
        self:update_epgp_v3(ep,GuildRoll.VARS.baseAE,i,name,officernote)
      end
    end
    local msg = L["All AuxStanding has been reset to %d."]
    self:debugPrint(string.format(msg,GuildRoll.VARS.baseAE))
    self:adminSay(string.format(msg,GuildRoll.VARS.baseAE))
    self:addToLog(string.format(msg,GuildRoll.VARS.baseAE))
  end
end



function GuildRoll:my_epgp_announce(use_main)
  local ep,gp
  if (use_main) then
    ep,gp = (self:get_ep_v3(GuildRoll_main) or 0), (self:get_gp_v3(GuildRoll_main) or GuildRoll.VARS.baseAE)
  else
    ep,gp = (self:get_ep_v3(self._playerName) or 0), (self:get_gp_v3(self._playerName) or GuildRoll.VARS.baseAE)
  end
  local baseRoll = GuildRoll:GetBaseRollValue(ep,gp)
  local msg = string.format(L["You now have: %d MainStanding %d AuxStanding + (%d)"], ep,gp,baseRoll)
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

function GuildRoll:OnTooltipUpdate()
  local hint = L["|cffffff00Click|r to toggle Standings.%s \n|cffffff00Right-Click|r for Options."]
  if (admin()) then
    hint = string.format(hint,L[" \n|cffffff00Alt+Click|r to toggle Bids. \n|cffffff00Shift+Click|r to toggle Loot. \n|cffffff00Ctrl+Alt+Click|r to toggle Alts. \n|cffffff00Ctrl+Shift+Click|r to toggle Logs."])
  else
    hint = string.format(hint,"")
  end
  T:SetHint(hint)
end

function GuildRoll:OnClick()
  local is_admin = admin()
  if (IsControlKeyDown() and IsShiftKeyDown() and is_admin) then
    GuildRoll_logs:Toggle()
  elseif (IsControlKeyDown() and IsAltKeyDown() and is_admin) then
    GuildRollAlts:Toggle()
  elseif (IsShiftKeyDown() and is_admin) then
   -- GuildRoll_loot:Toggle()      
  elseif (IsAltKeyDown() and is_admin) then
  --  GuildRoll_bids:Toggle()
  else
    GuildRoll_standings:Toggle()
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
  if (GuildRoll_raidonly) and GetNumRaidMembers() > 0 then
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
        if ((self._playerName) and (name == self._playerName)) then
          if (not GuildRoll_main) or (GuildRoll_main and GuildRoll_main ~= main) then
            GuildRoll_main = main
            self:defaultPrint(L["Your main has been set to %s"],GuildRoll_main)
          end
        end
        main = C:Colorize(BC:GetHexColor(main_class), main)
        GuildRoll.alts[main] = GuildRoll.alts[main] or {}
        GuildRoll.alts[main][member_name] = class
      end
      if (GuildRoll_raidonly) and next(r) then
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
    usage = "<GP>"
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
      c[class].args[name].type = "text"
      c[class].args[name].name = name
      c[class].args[name].desc = string.format(desc,name)
      c[class].args[name].usage = usage
      if epgp == "MainStanding" then
        c[class].args[name].get = "suggestedAwardMainStanding"
        c[class].args[name].set = function(v) GuildRoll:givename_ep(name, tonumber(v)) GuildRoll:refreshPRTablets() end
      elseif epgp == "AuxStanding" then
        c[class].args[name].get = false
        c[class].args[name].set = function(v) GuildRoll:givename_gp(name, tonumber(v)) GuildRoll:refreshPRTablets() end
      end
      c[class].args[name].validate = function(v) return (type(v) == "number" or tonumber(v)) and tonumber(v) < GuildRoll.VARS.max end
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
    for i=1,GetNumGuildMembers(1) do
      local g_name, _, _, _, g_class, _, g_note, g_officernote, _, _ = GetGuildRosterInfo(i)
      if (name == g_name) then
        return self:parseAlt(g_name, g_officernote)
      end
    end
  end
  return nil
end


------------
-- Logging
------------
function GuildRoll:addToLog(line,skipTime)
  local over = table.getn(GuildRoll_log)-GuildRoll.VARS.maxloglines+1
  if over > 0 then
    for i=1,over do
      table.remove(GuildRoll_log,1)
    end
  end
  local timestamp
  if (skipTime) then
    timestamp = ""
  else
    timestamp = date("%b/%d %H:%M:%S")
  end
  table.insert(GuildRoll_log,{timestamp,line})
end

------------
-- Utility 
------------
function GuildRoll:num_round(i)
  return math.floor(i+0.5)
end

function GuildRoll:strsplit(delimiter, subject)
  local delimiter, fields = delimiter or ":", {}
  local pattern = string.format("([^%s]+)", delimiter)
  string.gsub(subject, pattern, function(c) fields[table.getn(fields)+1] = c end)
  return unpack(fields)
end

function GuildRoll:strsplitT(delimiter, subject)
 local tbl = {GuildRoll:strsplit(delimiter, subject)}
 return tbl
end

 function GuildRoll:verifyGuildMember(name,silent)
	GuildRoll:verifyGuildMember(name,silent,false)
 end
function GuildRoll:verifyGuildMember(name,silent,ignorelevel)
  for i=1,GetNumGuildMembers(1) do
    local g_name, g_rank, g_rankIndex, g_level, g_class, g_zone, g_note, g_officernote, g_online = GetGuildRosterInfo(i)
    if (string.lower(name) == string.lower(g_name)) and (ignorelevel or tonumber(g_level) >= GuildRoll.VARS.minlevel) then 
    -- == MAX_PLAYER_LEVEL]]
      return g_name, g_class, g_rank, g_officernote
    end
  end
  if (name) and name ~= "" and not (silent) then
    self:defaultPrint(string.format(L["%s not found in the guild or not max level!"],name))
  end
  return
end

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
  if (GuildRoll_main == nil) or (GuildRoll_main == "") then
    if (IsInGuild()) then
      StaticPopup_Show("RET_EP_SET_MAIN")
    end
  end
end

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

local raidZones = {[L["Molten Core"]]="T1",[L["Onyxia\'s Lair"]]="T1.5",[L["Blackwing Lair"]]="T2",[L["Ahn\'Qiraj"]]="T2.5",[L["Naxxramas"]]="T3"}
local zone_multipliers = {
  ["T3"] =   {["T3"]=1,["T2.5"]=0.75,["T2"]=0.5,["T1.5"]=0.25,["T1"]=0.25},
  ["T2.5"] = {["T3"]=1,["T2.5"]=1,   ["T2"]=0.7,["T1.5"]=0.4, ["T1"]=0.4},
  ["T2"] =   {["T3"]=1,["T2.5"]=1,   ["T2"]=1,  ["T1.5"]=0.5, ["T1"]=0.5},
  ["T1"] =   {["T3"]=1,["T2.5"]=1,   ["T2"]=1,  ["T1.5"]=1,   ["T1"]=1}
}
function GuildRoll:suggestedAwardMainStanding()


    local isMainStanding , reward = GuildRoll.GetReward()
    if not isMainStanding and reward then
        return reward
    end


return GuildRoll.VARS.baseawardpoints
-- local currentTier, zoneEN, zoneLoc, checkTier, multiplier
-- local inInstance, instanceType = IsInInstance()
-- if (inInstance == nil) or (instanceType ~= nil and instanceType == "none") then
--   currentTier = "T1.5"   
-- end
-- if (inInstance) and (instanceType == "raid") then
--   zoneLoc = GetRealZoneText()
--   if (BZ:HasReverseTranslation(zoneLoc)) then
--     zoneEN = BZ:GetReverseTranslation(zoneLoc)
--     checkTier = raidZones[zoneEN]
--     if (checkTier) then
--       currentTier = checkTier
--     end
--   end
-- end
-- if not currentTier then 
--   return GuildRoll.VARS.baseawardpoints
-- else
--   multiplier = zone_multipliers[GuildRoll_progress][currentTier]
-- end
-- if (multiplier) then
--   return multiplier*GuildRoll.VARS.baseawardpoints
-- else
--   return GuildRoll.VARS.baseawardpoints
-- end
end
function GuildRoll:suggestedAwardAuxStanding()

    local isMainStanding , reward = GuildRoll.GetReward()
    if ( isMainStanding) and reward then
        return reward
    end


return GuildRoll.VARS.baseawardpoints
-- local currentTier, zoneEN, zoneLoc, checkTier, multiplier
-- local inInstance, instanceType = IsInInstance()
-- if (inInstance == nil) or (instanceType ~= nil and instanceType == "none") then
--   currentTier = "T1.5"   
-- end
-- if (inInstance) and (instanceType == "raid") then
--   zoneLoc = GetRealZoneText()
--   if (BZ:HasReverseTranslation(zoneLoc)) then
--     zoneEN = BZ:GetReverseTranslation(zoneLoc)
--     checkTier = raidZones[zoneEN]
--     if (checkTier) then
--       currentTier = checkTier
--     end
--   end
-- end
-- if not currentTier then 
--   return GuildRoll.VARS.baseawardpoints
-- else
--   multiplier = zone_multipliers[GuildRoll_progress][currentTier]
-- end
-- if (multiplier) then
--   return multiplier*GuildRoll.VARS.baseawardpoints
-- else
--   return GuildRoll.VARS.baseawardpoints
-- end
end
function GuildRoll:parseVersion(version,otherVersion)
	if   version then  
  if not GuildRoll._version then
      GuildRoll._version = {  
		major = 0,
		minor = 0,
		patch = 0
	}
  
  end
  for major,minor,patch in string.gfind(version,"(%d+)[^%d]?(%d*)[^%d]?(%d*)") do
    GuildRoll._version.major = tonumber(major)
    GuildRoll._version.minor = tonumber(minor)
    GuildRoll._version.patch = tonumber(patch)
  end
  end
  if (otherVersion) then
    if not GuildRoll._otherversion then GuildRoll._otherversion = {} end
    for major,minor,patch in string.gfind(otherVersion,"(%d+)[^%d]?(%d*)[^%d]?(%d*)") do
      GuildRoll._otherversion.major = tonumber(major)
      GuildRoll._otherversion.minor = tonumber(minor)
      GuildRoll._otherversion.patch = tonumber(patch)      
    end
    if (GuildRoll._otherversion.major ~= nil and GuildRoll._version ~= nil and GuildRoll._version.major ~= nil) then
      if (GuildRoll._otherversion.major < GuildRoll._version.major) then -- we are newer
        return
      elseif (GuildRoll._otherversion.major > GuildRoll._version.major) then -- they are newer
        return true, "major"        
      else -- tied on major, go minor
        if (GuildRoll._otherversion.minor ~= nil and GuildRoll._version.minor ~= nil) then
          if (GuildRoll._otherversion.minor < GuildRoll._version.minor) then -- we are newer
            return
          elseif (GuildRoll._otherversion.minor > GuildRoll._version.minor) then -- they are newer
            return true, "minor"
          else -- tied on minor, go patch
            if (GuildRoll._otherversion.patch ~= nil and GuildRoll._version.patch ~= nil) then
              if (GuildRoll._otherversion.patch < GuildRoll._version.patch) then -- we are newer
                return
              elseif (GuildRoll._otherversion.patch > GuildRoll._version.patch) then -- they are newwer
                return true, "patch"
              end
            elseif (GuildRoll._otherversion.patch ~= nil and GuildRoll._version.patch == nil) then -- they are newer
              return true, "patch"
            end
          end    
        elseif (GuildRoll._otherversion.minor ~= nil and GuildRoll._version.minor == nil) then -- they are newer
          return true, "minor"
        end
      end
    end
  end
 
end

function GuildRoll:camelCase(word)
  return string.gsub(word,"(%a)([%w_']*)",function(head,tail) 
    return string.format("%s%s",string.upper(head),string.lower(tail)) 
    end)
end

admin = function()
  return (CanEditOfficerNote() --[[and CanEditPublicNote()]])
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

StaticPopupDialogs["RET_EP_SET_MAIN"] = {
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
StaticPopupDialogs["RET_EP_CONFIRM_RESET"] = {
  text = L["|cffff0000Are you sure you want to Reset ALL Standing?|r"],
  button1 = TEXT(OKAY),
  button2 = TEXT(CANCEL),
  OnAccept = function()
    GuildRoll:gp_reset_v3()
  end,
  timeout = 0,
  whileDead = 1,
  exclusive = 1,
  showAlert = 1,
  hideOnEscape = 1
}
StaticPopupDialogs["RET_GP_CONFIRM_RESET"] = {
  text = L["|cffff0000Are you sure you want to Reset ALL AuxStanding?|r"],
  button1 = TEXT(OKAY),
  button2 = TEXT(CANCEL),
  OnAccept = function()
    GuildRoll:ClearGP_v3()
  end,
  timeout = 0,
  whileDead = 1,
  exclusive = 1,
  showAlert = 1,
  hideOnEscape = 1
}

StaticPopupDialogs["GUILDROLL_AWARD_EP_RAID_HELP"] = {
  text = "Enter EP to award to raid members:",
  button1 = TEXT(ACCEPT),
  button2 = TEXT(CANCEL),
  hasEditBox = 1,
  maxLetters = 10,
  OnShow = function()
    local zoneHelp = {
      NAX = {prefill = 7, text = "Naxx - 7 EP for using FLASK + 7 EP for attendance."},
      AQ40 = {prefill = 5, text = "AQ40 - 5 EP for using FLASK + 5 EP for attendance."},
      BWL = {prefill = 3, text = "BWL - 3 EP for using more than 3 types of CONSUMMS + 3 EP for attendance."},
      ES = {prefill = 3, text = "ES  - 3 EP for using more than 3 types of CONSUMMS + 3 EP for attendance."},
      MC = {prefill = 2, text = "MC  - 2 EP for using more than 3 types of CONSUMMS + 2 EP for attendance."}
    }
    
    local suggested = GuildRoll.VARS.baseawardpoints
    local success, result = pcall(function() return GuildRoll:suggestedAwardMainStanding() end)
    if success and result then
      suggested = result
    end
    
    local helpText = "Enter EP to award to raid members:"
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
      GuildRoll:defaultPrint("Invalid EP value entered.")
      return
    end
    if epValue < 0 or epValue >= GuildRoll.VARS.max then
      GuildRoll:defaultPrint("EP value must be between 0 and " .. GuildRoll.VARS.max)
      return
    end
    if not (IsGuildLeader() or CanEditOfficerNote()) then
      GuildRoll:defaultPrint("You don't have permission to award EP.")
      return
    end
    GuildRoll:award_raid_ep(epValue)
  end,
  EditBoxOnEnterPressed = function()
    local parent = this:GetParent()
    local editBox = getglobal(parent:GetName().."EditBox")
    local epValue = tonumber(editBox:GetText())
    if epValue and epValue >= 0 and epValue < GuildRoll.VARS.max and (IsGuildLeader() or CanEditOfficerNote()) then
      GuildRoll:award_raid_ep(epValue)
      parent:Hide()
    end
  end,
  EditBoxOnEscapePressed = function()
    this:GetParent():Hide()
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
-- NOTE: This function is kept for compatibility but is no longer used in roll calculations.
-- Rolls now use only EP (MainStanding) + CSR bonus.
function GuildRoll:GetRollingGP(gp)

    return math.max(-1 * GuildRoll.VARS.AERollCap , math.min(GuildRoll.VARS.AERollCap,gp) )
end
-- Returns the base roll value for the player.
-- Now returns only EP (MainStanding). GP (AuxStanding) is no longer included in roll calculations.
function GuildRoll:GetBaseRollValue(ep,gp)

    return  ep

end

function GuildRoll:RollCommand(isSRRoll, bonus)
  local playerName = UnitName("player")
  local ep = 0 
  local gp = 0
  local desc = ""  
  -- Check if the player is an alt
  if GuildRollAltspool then
    local main = self:parseAlt(playerName)
    if main then
      -- If the player is an alt, use the main's EP
      ep = self:get_ep_v3(main) or 0
      gp = self:get_gp_v3(main) or 0
      desc = "Alt of "..main
    else
      -- If not an alt, use the player's own EP
      ep = self:get_ep_v3(playerName) or 0
      gp = self:get_gp_v3(playerName) or 0
      desc = "Main"
    end
  else
    -- If alt pooling is not enabled, just use the player's EP
    ep = self:get_ep_v3(playerName) or 0
    gp = self:get_gp_v3(playerName) or 0
    desc = "Main"
  end
  
  -- Calculate the roll range based on whether it's an SR roll or not
  local minRoll, maxRoll
  local baseRoll = GuildRoll:GetBaseRollValue(ep,gp)
  -- New EP-aware roll ranges
  if isSRRoll then
    -- SR: 100 + baseRoll to 200 + baseRoll
    minRoll = 100 + baseRoll
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
    -- Calculate weeks: bonus = (weeks - 1) * CSRWeekBonus, so weeks = (bonus / CSRWeekBonus) + 1
    local weeks = math.floor(bonus / GuildRoll.VARS.CSRWeekBonus) + 1
    local csrBonusText = string.format("%d weeks", weeks)
    message = string.format("I rolled SR \"%d - %d\" with %d "..L["MainStanding"].." + \"%s\"%s", minRoll, maxRoll, ep, csrBonusText, bonusText)
  end
  -- Determine the chat channel
  local chatType = UnitInRaid("player") and "RAID" or "SAY"
  
  -- Send the message
  SendChatMessage(message, chatType)
end

local RaidKey = {[L["Molten Core"]]="MC",[L["Onyxia\'s Lair"]]="ONY",[L["Blackwing Lair"]]="BWL",[L["Ahn\'Qiraj"]]="AQ40",[L["Naxxramas"]]="NAX",["Tower of Karazhan"]="K10",["Upper Tower of Karazhan"]="K40",["???"]="K40"}
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

function GuildRoll:Status()
DEFAULT_CHAT_FRAME:AddMessage("Host LeadName " .. GuildRoll.VARS.HostLeadName )
DEFAULT_CHAT_FRAME:AddMessage("Host GuildName " .. GuildRoll.VARS.HostGuildName ) 
end

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

-- GLOBALS: GuildRoll_saychannel,GuildRoll_groupbyclass,GuildRoll_groupbyarmor,GuildRoll_groupbyrole,GuildRoll_raidonly,GuildRoll_decay,GuildRoll_minPE,GuildRoll_main,GuildRoll_progress,GuildRoll_discount,GuildRollAltspool,GuildRoll_altpercent,GuildRoll_log,GuildRoll_dbver,GuildRoll_looted,GuildRoll_debug,GuildRoll_fubar,GuildRoll_showRollWindow
-- GLOBALS: GuildRoll,GuildRoll_prices,GuildRoll_standings,GuildRoll_bids,GuildRoll_loot,GuildRollAlts,GuildRoll_logs,GuildRoll_pugCache
