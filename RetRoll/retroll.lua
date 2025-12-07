RetRoll = AceLibrary("AceAddon-2.0"):new("AceConsole-2.0", "AceHook-2.1", "AceDB-2.0", "AceDebug-2.0", "AceEvent-2.0", "AceModuleCore-2.0", "FuBarPlugin-2.0")
RetRoll:SetModuleMixins("AceDebug-2.0")
local D = AceLibrary("Dewdrop-2.0")-- Standings table
local BZ = AceLibrary("Babble-Zone-2.2")
local C = AceLibrary("Crayon-2.0") -- chat color
local BC = AceLibrary("Babble-Class-2.2") 
--local DF = AceLibrary("Deformat-2.0")
--local G = AceLibrary("Gratuity-2.0")
local T = AceLibrary("Tablet-2.0") -- tooltips
local L = AceLibrary("AceLocale-2.2"):new("retroll")
RetRoll.VARS = {
  baseAE = 0,
  AERollCap = 50,
  OSPenalty = 50,
  minPE = 0,
  baseawardpoints = 10,
  decay = 0.5,
  max = 1000,
  timeout = 60,
  minlevel = 1,
  maxloglines = 500,
  prefix = "RRG_",
  inRaid = false,
  reservechan = "Reserves",
  reserveanswer = "^(%+)(%a*)$",
  bop = C:Red("BoP"),
  boe = C:Yellow("BoE"),
  nobind = C:White("NoBind"), 
  bankde = "Bank-D/E",
  reminder = C:Red("Unassigned"), 
  HostGuildName = "!",
  HostLeadName = "!" 
}

RetRollMSG = {
	delayedinit = false,
	dbg= false,
	prefix = "RR_",
	RequestHostInfoUpdate = "RequestHostInfoUpdate",
	RequestHostInfoUpdateTS = 0,
	HostInfoUpdate = "HostInfoUpdate",
	PugStandingUpdate = "PugStandingUpdate"

}
RetRoll._playerName = (UnitName("player"))
local out = "|cff9664c8retroll:|r %s"
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
local admincmd, membercmd = {type = "group", handler = RetRoll, args = {

    show = {
      type = "execute",
      name = L["Standings"],
      desc = L["Show Standings Table."],
      func = function()
        RetRoll_standings:Toggle()
      end,
      order = 1,
    },
    resetButton = {
      type = "execute",
      name = "Reset Button",
      desc = "Reset Button",
      func = function()
        RetRoll:ResetButton()  
      end,
      order = 2,
    },      
    restart = {
      type = "execute",
      name = L["Restart"],
      desc = L["Restart retroll if having startup problems."],
      func = function() 
        RetRoll:OnEnable()
        RetRoll:defaultPrint(L["Restarted"])
      end,
      order = 7,
    },
    ms = {
      type = "execute",
      name = "Roll MainSpec",
      desc = "Roll MainSpec with your standing",
      func = function() 
        RetRoll:RollCommand(false,false,false,0)
      end,
      order = 8,
    },
    os = {
      type = "execute",
      name = "Roll Offspec",
      desc = "Roll Offspec with your standing",
      func = function() 
        RetRoll:RollCommand(false,false,true,0)
      end,
      order = 8,
    },
    sr = {
      type = "execute",
      name = "Roll SR",
      desc = "Roll Soft Reserve with your standing",
      func = function() 
        RetRoll:RollCommand(true,false,false,0)
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
      local bonus = RetRoll:calculateBonus(input)
      RetRoll:RollCommand(true, false,false, bonus)
      end,
      order = 10,
    },
  -- dsr = {
  --   type = "execute",
  --   name = "Roll Double SR",
  --   desc = "Roll Double Soft Reserve with your standing",
  --   func = function() 
  --     RetRoll:RollCommand(true,true,false,0)
  --   end,
  --   order = 11,
  -- },
    ep = {
      type = "execute",
      name = "Check your pug Standing",
      desc = "Checks your pug Standing",
      func = function() 
        RetRoll:CheckPugStanding()
      end,
      order = 12,
    },
  }},
{type = "group", handler = RetRoll, args = {
    show = {
      type = "execute",
      name = L["Standings"],
      desc = L["Show Standings Table."],
      func = function()
        RetRoll_standings:Toggle()
      end,
      order = 1,
    },
    resetButton = {
      type = "execute",
      name = "Reset Button",
      desc = "Reset Button",
      func = function()
        RetRoll:ResetButton()  
      end,
      order = 2,
    }, 
    restart = {
      type = "execute",
      name = L["Restart"],
      desc = L["Restart retroll if having startup problems."],
      func = function() 
        RetRoll:OnEnable()
        RetRoll:defaultPrint(L["Restarted"])
      end,
      order = 4,
    },
    ms = {
      type = "execute",
      name = "Roll MainSpec",
      desc = "Roll with your standing",
      func = function() 
        RetRoll:RollCommand(false,false,false,0)
      end,
      order = 5,
    },
    os = {
      type = "execute",
      name = "Roll OffSpec",
      desc = "Roll OffSpec with your standing",
      func = function() 
        RetRoll:RollCommand(false,false,true,0)
      end,
      order = 6,
    },
    sr = {
      type = "execute",
      name = "Roll SR",
      desc = "Roll Soft Reserve with your standing",
      func = function() 
        RetRoll:RollCommand(true,false,false,0)
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
      local bonus = RetRoll:calculateBonus(input)
      RetRoll:RollCommand(true, false,false, bonus)
      end,
      order = 8,
    },
  -- dsr = {
  --   type = "execute",
  --   name = "Roll Double SR",
  --   desc = "Roll Double Soft Reserve with your standing",
  --   func = function() 
  --     RetRoll:RollCommand(true,true,false,0)
  --   end,
  --   order = 9,
  -- },
    ep = {
      type = "execute",
      name = "Check your pug Standing",
      desc = "Checks your pug Standing",
      func = function() 
        RetRoll:CheckPugStanding()
      end,
      order = 10,
    },
  }}
RetRoll.cmdtable = function() 
  if (admin()) then
    return admincmd
  else
    return membercmd
  end
end
RetRoll.reserves = {}
RetRoll.alts = {} 
function RetRoll:buildMenu()
  if not (options) then
    options = {
    type = "group",
    desc = L["retroll options"],
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
      type = "text",
      name = L["+MainStanding to Raid"],
      desc = L["Award MainStanding to all raid members."],
      order = 20,
      get = "suggestedAwardMainStanding",
      set = function(v) RetRoll:award_raid_ep(tonumber(v)) end,
      usage = "<EP>",
      hidden = function() return not (admin()) end,
      validate = function(v)
        local n = tonumber(v)
        return n and n >= 0 and n < RetRoll.VARS.max
      end
    }
    options.args["AuxStanding"] = {
      type = "group",
      name = L["+AuxStanding to Member"],
      desc = L["Account AuxStanding for member."],
      order = 30,
      hidden = function() return not (admin()) end,
    }
	options.args["AuxStanding_raid"] = {
      type = "text",
      name = L["+AuxStanding to Raid"],
      desc = L["Award AuxStanding to all raid members."],
      order = 35,
      get = "suggestedAwardAuxStanding",
      set = function(v) RetRoll:award_raid_gp(tonumber(v)) end,
      usage = "<GP>",
      hidden = function() return not (admin()) end,
      validate = function(v)
        local n = tonumber(v)
        return n and n >= 0 and n < RetRoll.VARS.max
      end
    }
 
    options.args["updatePugs"] = {
      type = "execute",
      name = "Update Pug Standing",
      desc = "Update Pug Standing",
      order = 62,
      hidden = function() return not (admin()) end,
      func = function() RetRoll:updateAllPugStanding(false) end
    }
    options.args["alts"] = {
      type = "toggle",
      name = L["Enable Alts"],
      desc = L["Allow Alts to use Main\'s Standing."],
      order = 63,
      hidden = function() return not (admin()) end,
      disabled = function() return not (IsGuildLeader()) end,
      get = function() return not not RetRollAltspool end,
      set = function(v) 
        RetRollAltspool = not RetRollAltspool
        if (IsGuildLeader()) then
          RetRoll:shareSettings(true)
        end
      end,
    }
    options.args["alts_percent"] = {
      type = "range",
      name = L["Alts MainStanding %"],
      desc = L["Set the % MainStanding Alts can earn."],
      order = 66,
      hidden = function() return (not RetRollAltspool) or (not IsGuildLeader()) end,
      get = function() return RetRoll_altpercent end,
      set = function(v) 
        RetRoll_altpercent = v
        if (IsGuildLeader()) then
          RetRoll:shareSettings(true)
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
      desc = L["Set your Main Character for Reserve List."],
      order = 70,
      usage = "<MainChar>",
      get = function() return RetRoll_main end,
      set = function(v) RetRoll_main = (RetRoll:verifyGuildMember(v)) end,
    }    
    options.args["raid_only"] = {
      type = "toggle",
      name = L["Raid Only"],
      desc = L["Only show members in raid."],
      order = 80,
      get = function() return not not RetRoll_raidonly end,
      set = function(v) 
        RetRoll_raidonly = not RetRoll_raidonly
        RetRoll:SetRefresh(true)
      end,
    }
    options.args["report_channel"] = {
      type = "text",
      name = L["Reporting channel"],
      desc = L["Channel used by reporting functions."],
      order = 95,
      hidden = function() return not (admin()) end,
      get = function() return RetRoll_saychannel end,
      set = function(v) RetRoll_saychannel = v end,
      validate = { "PARTY", "RAID", "GUILD", "OFFICER" },
    }    
    options.args["decay"] = {
      type = "execute",
      name = L["Decay Standing"],
      desc = string.format(L["Decays all Standing by %s%%"],(1-(RetRoll_decay or RetRoll.VARS.decay))*100),
      order = 100,
      hidden = function() return not (admin()) end,
      func = function() RetRoll:decay_epgp_v3() end 
    }    
    options.args["set_decay"] = {
      type = "range",
      name = L["Set Decay %"],
      desc = L["Set Decay percentage (Admin only)."],
      order = 110,
      usage = "<Decay>",
      get = function() return (1.0-RetRoll_decay) end,
      set = function(v) 
        RetRoll_decay = (1 - v)
        options.args["decay"].desc = string.format(L["Decays all Standing by %s%%"],(1-RetRoll_decay)*100)
        if (IsGuildLeader()) then
          RetRoll:shareSettings(true)
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
      name = string.format(L["Minimum MainStanding: %s"],RetRoll_minPE),
      order = 117,
      hidden = function() return admin() end,
    }
    options.args["set_min_ep"] = {
      type = "text",
      name = L["Minimum MainStanding"],
      desc = L["Set Minimum MainStanding"],
      usage = "<minPE>",
      order = 118,
      get = function() return RetRoll_minPE end,
      set = function(v) 
        RetRoll_minPE = tonumber(v)
        RetRoll:refreshPRTablets()
        if (IsGuildLeader()) then
          RetRoll:shareSettings(true)
        end        
      end,
      validate = function(v) 
        local n = tonumber(v)
        return n and n >= 0 and n <= RetRoll.VARS.max
      end,
      hidden = function() return not admin() end,
    }
    options.args["reset"] = {
     type = "execute",
     name = L["Reset Standing"],
     desc = string.format(L["Resets everyone\'s Standing to 0/%d (Admin only)."],RetRoll.VARS.baseAE),
     order = 120,
     hidden = function() return not (IsGuildLeader()) end,
     func = function() StaticPopup_Show("RET_EP_CONFIRM_RESET") end
    }
    options.args["resetAuxStanding"] = {
     type = "execute",
     name = L["Reset AuxStanding"],
     desc = string.format(L["Resets everyone\'s AuxStanding to 0/%d (Admin only)."],RetRoll.VARS.baseAE),
     order = 122,
     hidden = function() return not (IsGuildLeader()) end,
     func = function() StaticPopup_Show("RET_GP_CONFIRM_RESET") end
    }

  end
  if (needInit) or (needRefresh) then
    local members = RetRoll:buildRosterTable()
    self:debugPrint(string.format(L["Scanning %d members for Standing data. (%s)"],table.getn(members),(RetRoll_raidonly and "Raid" or "Full")))
    options.args["MainStanding"].args = RetRoll:buildClassMemberTable(members,"MainStanding")
    options.args["AuxStanding"].args = RetRoll:buildClassMemberTable(members,"AuxStanding")
    if (needInit) then needInit = false end
    if (needRefresh) then needRefresh = false end
  end
  return options
end

function RetRoll:OnInitialize() -- ADDON_LOADED (1) unless LoD
  if RetRoll_saychannel == nil then RetRoll_saychannel = "GUILD" end
  if RetRoll_decay == nil then RetRoll_decay = RetRoll.VARS.decay end
  if RetRoll_minPE == nil then RetRoll_minPE = RetRoll.VARS.minPE end
 -- if RetRoll_progress == nil then RetRoll_progress = "T1" end
 -- if RetRoll_discount == nil then RetRoll_discount = 0.25 end
  if RetRollAltspool == nil then RetRollAltspool = true end
  if RetRoll_altpercent == nil then RetRoll_altpercent = 1.0 end
  if RetRoll_log == nil then RetRoll_log = {} end
  if RetRoll_looted == nil then RetRoll_looted = {} end
  if RetRoll_debug == nil then RetRoll_debug = {} end
  if RetRoll_pugCache == nil then RetRoll_pugCache = {} end 
  --if RetRoll_showRollWindow == nil then RetRoll_showRollWindow = true end
  self:RegisterDB("RetRoll_fubar")
  self:RegisterDefaults("char",{})
  --table.insert(RetRoll_debug,{[date("%b/%d %H:%M:%S")]="OnInitialize"})
end

function RetRoll:OnEnable() -- PLAYER_LOGIN (2)
  --table.insert(RetRoll_debug,{[date("%b/%d %H:%M:%S")]="OnEnable"})
  RetRoll._playerLevel = UnitLevel("player")
  --RetRoll.extratip = (RetRoll.extratip) or CreateFrame("GameTooltip","retroll_tooltip",UIParent,"GameTooltipTemplate")
  RetRoll._versionString = GetAddOnMetadata("retroll","Version")
  RetRoll._websiteString = GetAddOnMetadata("retroll","X-Website")
  
  if (IsInGuild()) then
    if (GetNumGuildMembers()==0) then
      GuildRoster()
    end
  end

 
  
  
 
  self:RegisterEvent("GUILD_ROSTER_UPDATE",function() 
      if (arg1) then -- member join /leave
        RetRoll:SetRefresh(true)
      end
    end)
 
  self:RegisterEvent("CHAT_MSG_ADDON",function() 
        RetRollMSG:OnCHAT_MSG_ADDON( arg1, arg2, arg3, arg4)
    end)
  self:RegisterEvent("RAID_ROSTER_UPDATE",function()
      RetRoll:SetRefresh(true)
	  RetRoll:UpdateHostInfo()
     -- RetRoll:testLootPrompt()
    end)
  self:RegisterEvent("PARTY_MEMBERS_CHANGED",function()
      RetRoll:SetRefresh(true)
     -- RetRoll:testLootPrompt()
    end)
  self:RegisterEvent("PLAYER_ENTERING_WORLD",function()
      RetRoll:SetRefresh(true)
	  RetRoll:UpdateHostInfo()
     -- RetRoll:testLootPrompt()
    end)
  if RetRoll._playerLevel and RetRoll._playerLevel < MAX_PLAYER_LEVEL then
    self:RegisterEvent("PLAYER_LEVEL_UP", function()
        if (arg1) then
          RetRoll._playerLevel = tonumber(arg1)
          if RetRoll._playerLevel == MAX_PLAYER_LEVEL then
            RetRoll:UnregisterEvent("PLAYER_LEVEL_UP")
          end
          if RetRoll._playerLevel and RetRoll._playerLevel >= RetRoll.VARS.minlevel then
            RetRoll:testMain()
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

function RetRoll:OnDisable()

--DEFAULT_CHAT_FRAME:AddMessage("RetRoll:OnDisable()") 
  --table.insert(RetRoll_debug,{[date("%b/%d %H:%M:%S")]="OnDisable"})
  self:UnregisterAllEvents()
end

function RetRoll:AceEvent_FullyInitialized() -- SYNTHETIC EVENT, later than PLAYER_LOGIN, PLAYER_ENTERING_WORLD (3)
  --table.insert(RetRoll_debug,{[date("%b/%d %H:%M:%S")]="AceEvent_FullyInitialized"})
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
  if not self:IsEventScheduled("retrollChannelInit") then
    self:ScheduleEvent("retrollChannelInit",self.delayedInit,delay,self)
  end

  -- if pfUI loaded, skin the extra tooltip
 --if not IsAddOnLoaded("pfUI-addonskins") then
 --  if (pfUI) and pfUI.api and pfUI.api.CreateBackdrop and pfUI_config and pfUI_config.tooltip and pfUI_config.tooltip.alpha then
 --    pfUI.api.CreateBackdrop(RetRoll.extratip,nil,nil,tonumber(pfUI_config.tooltip.alpha))
 --  end
 --end

  self._hasInitFull = true
end

RetRoll._lastRosterRequest = false
function RetRoll:OnMenuRequest()
  local now = GetTime()
  if not self._lastRosterRequest or (now - self._lastRosterRequest > 2) then
    self._lastRosterRequest = now
    self:SetRefresh(true)
    GuildRoster()
  end
  self._options = self:buildMenu()
  D:FeedAceOptionsTable(self._options)
end

 
function RetRoll:delayedInit()
  --table.insert(RetRoll_debug,{[date("%b/%d %H:%M:%S")]="delayedInit"})
  RetRoll.VARS.GuildName  =""
  if (IsInGuild()) then
    RetRoll.VARS.GuildName  = (GetGuildInfo("player"))
    if (RetRoll.VARS.GuildName ) and RetRoll.VARS.GuildName  ~= "" then
      RetRoll_reservechannel = string.format("%sReserves",(string.gsub(RetRoll.VARS.GuildName ," ",""))) 
    --  RetRoll.VARS.GuildPugBroadCastCN  = RetRoll:GetGuildPugChannelName(RetRoll.VARS.GuildName)
     -- if (admin()) then JoinChannelByName(RetRoll.VARS.GuildPugBroadCastCN) end
    end
  end
  if RetRoll_reservechannel == nil then RetRoll_reservechannel = RetRoll.VARS.reservechan end  
  local reservesChannelID = tonumber((GetChannelName(RetRoll_reservechannel)))
  if (reservesChannelID) and (reservesChannelID ~= 0) then
    self:reservesToggle(true)
  end
  -- migrate Standing storage if needed
  
 
--  self:parseVersion(RetRoll._versionString)
   
  local major_ver = 0 --self._version.major or 0
 -- if IsGuildLeader() and ( (RetRoll_dbver == nil) or (major_ver > RetRoll_dbver) ) then
 --   RetRoll[string.format("v%dtov%d",(RetRoll_dbver or 2),major_ver)](RetRoll)
 -- end
 
  -- init options and comms
  self._options = self:buildMenu()
  self:RegisterChatCommand({"/RetRoll","/retroll","/ret"},self.cmdtable())
  function RetRoll:calculateBonus(input)
    local number = tonumber(input)
    if number and number >= 2 and number <= 15 then
        return number * 20
    end
    return 20  -- Return 20 for first week if input is invalid
  end
  
  self:RegisterChatCommand({"/retcsr"}, function(input)
    local bonus = RetRoll:calculateBonus(input)
    self:RollCommand(true, false,false, bonus)
  end) 
  self:RegisterChatCommand({"/updatepugs"}, function() RetRoll:updateAllPugStanding(false) end)
  --self:RegisterEvent("CHAT_MSG_ADDON","addonComms")  
  -- broadcast our version
  local addonMsg = string.format("RetRollVERSION;%s;%d",RetRoll._versionString,major_ver or 0)
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
  RetRollMSG.delayedinit = true
  self:defaultPrint(string.format(L["v%s Loaded."],RetRoll._versionString))
end


function RetRoll:OnUpdate(elapsed)
  RetRoll.timer.count_down = RetRoll.timer.count_down - elapsed
  lastUpdate = lastUpdate + elapsed

  if lastUpdate > 0.5 then
    lastUpdate = 0
    RetRoll_reserves:Refresh()
  end
end

function RetRoll:GuildRosterSetOfficerNote(index,note,fromAddon)
  if (fromAddon) then
    self.hooks["GuildRosterSetOfficerNote"](index,note)
  else
    local name, _, _, _, _, _, _, prevnote, _, _ = GetGuildRosterInfo(index)
    local _,_,_,oldepgp,_ = string.find(prevnote or "","(.*)({%d+:%d+})(.*)")
    local _,_,_,epgp,_ = string.find(note or "","(.*)({%d+:%d+})(.*)")
    if (RetRollAltspool) then
      local oldmain = self:parseAlt(name,prevnote)
      local main = self:parseAlt(name,note)
      if oldmain ~= nil then
        if main == nil or main ~= oldmain then 
		 local isbnk, pugname = RetRoll:isBank(name)
			if isbnk then
				RetRoll:ReportPugManualEdit(pugname , epgp )
			end
          self:adminSay(string.format(L["Manually modified %s\'s note. Previous main was %s"],name,oldmain))
          self:defaultPrint(string.format(L["|cffff0000Manually modified %s\'s note. Previous main was %s|r"],name,oldmain))
        end
      end
    end    
    if oldepgp ~= nil then
      if epgp == nil or epgp ~= oldepgp then
		 local isbnk, pugname = RetRoll:isBank(name)
			if isbnk then
				RetRoll:ReportPugManualEdit(pugname , epgp )
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
function RetRoll:flashFrame(frame)
  local tabFlash = getglobal(frame:GetName().."TabFlash")
  if ( not frame.isDocked or (frame == SELECTED_DOCK_FRAME) or UIFrameIsFlashing(tabFlash) ) then
    return
  end
  tabFlash:Show()
  UIFrameFlash(tabFlash, 0.25, 0.25, 60, nil, 0.5, 0.5)
end

function RetRoll:debugPrint(msg)
  if (shooty_debugchat) then
    shooty_debugchat:AddMessage(string.format(out,msg))
    self:flashFrame(shooty_debugchat)
  else
    self:defaultPrint(msg)
  end
end

function RetRoll:defaultPrint(msg)
  if not DEFAULT_CHAT_FRAME:IsVisible() then
    FCF_SelectDockFrame(DEFAULT_CHAT_FRAME)
  end
  DEFAULT_CHAT_FRAME:AddMessage(string.format(out,msg))
end


function RetRoll:simpleSay(msg)
  SendChatMessage(string.format("retroll: %s",msg), RetRoll_saychannel)
end

function RetRoll:adminSay(msg)
  -- API is broken on Elysium
  -- local g_listen, g_speak, officer_listen, officer_speak, g_promote, g_demote, g_invite, g_remove, set_gmotd, set_publicnote, view_officernote, edit_officernote, set_guildinfo = GuildControlGetRankFlags() 
  -- if (officer_speak) then
  SendChatMessage(string.format("retroll: %s",msg),"OFFICER")
  -- end
end

function RetRoll:widestAudience(msg)
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

function RetRoll:addonMessage(message,channel,sender)
  SendAddonMessage(self.VARS.prefix,message,channel,sender)
end

function RetRoll:addonComms(prefix,message,channel,sender)
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
    local for_main = (RetRoll_main and (who == RetRoll_main))
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
    elseif who == "RESERVES" and what == "AWARD" then
      msg = string.format(L["%d AuxStanding awarded to Reserves."],amount)
    elseif who == "RetRollVERSION" then
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
        --if progress and progress ~= RetRoll_progress then
        --  RetRoll_progress = progress
        --  settings_notice = L["New raid progress"]
        --end
        --if discount and discount ~= RetRoll_discount then
        --  RetRoll_discount = discount
        --  if (settings_notice) then
        --    settings_notice = settings_notice..L[", offspec price %"]
        --  else
        --    settings_notice = L["New offspec price %"]
        --  end
        --end
        if minPE and minPE ~= RetRoll_minPE then
          RetRoll_minPE = minPE
          settings_notice = L["New Minimum MainStanding"]
          RetRoll:refreshPRTablets()
        end
        if decay and decay ~= RetRoll_decay then
          RetRoll_decay = decay
          if (admin()) then
            if (settings_notice) then
              settings_notice = settings_notice..L[", decay %"]
            else
              settings_notice = L["New decay %"]
            end
          end
        end
        if alts ~= nil and alts ~= RetRollAltspool then
          RetRollAltspool = alts
          if (admin()) then
            if (settings_notice) then
              settings_notice = settings_notice..L[", alts"]
            else
              settings_notice = L["New Alts"]
            end
          end          
        end
        if altspct and altspct ~= RetRoll_altpercent then
          RetRoll_altpercent = altspct
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
         -- self._options.args["RollValueogress_tier_header"].name = string.format(L["Progress Setting: %s"],RetRoll_progress)
         -- self._options.args["set_discount_header"].name = string.format(L["Offspec Price: %s%%"],RetRoll_discount*100)
          self._options.args["set_min_ep_header"].name = string.format(L["Minimum MainStanding: %s"],RetRoll_minPE)
        end
      end
    end
    if msg and msg~="" then
      self:defaultPrint(msg)
      self:my_epgp(for_main)
    end
  end
end

function RetRoll:shareSettings(force)
  local now = GetTime()
  if self._lastSettingsShare == nil or (now - self._lastSettingsShare > 30) or (force) then
    self._lastSettingsShare = now
    local addonMsg = string.format("SETTINGS;%s:%s:%s:%s:%s:%s;1",0,0,RetRoll_decay,RetRoll_minPE,tostring(RetRollAltspool),RetRoll_altpercent)
    self:addonMessage(addonMsg,"GUILD")
  end
end

function RetRoll:refreshPRTablets()
  --if not T:IsAttached("RetRoll_standings") then
  RetRoll_standings:Refresh()
  --end
 
end

---------------------
-- Standing Operations
---------------------


function RetRoll:init_notes_v3(guild_index,name,officernote)
  local ep,gp = self:get_ep_v3(name,officernote), self:get_gp_v3(name,officernote)
  if  (ep ==nil or gp==nil) then
    local initstring = string.format("{%d:%d}",0,RetRoll.VARS.baseAE)
    local newnote = string.format("%s%s",officernote,initstring)
    newnote = string.gsub(newnote,"(.*)({%d+:%d+})(.*)",sanitizeNote)
    officernote = newnote
  else
    officernote = string.gsub(officernote,"(.*)({%d+:%d+})(.*)",sanitizeNote)
  end
  GuildRosterSetOfficerNote(guild_index,officernote,true)
  return officernote
end

function RetRoll:update_epgp_v3(ep,gp,guild_index,name,officernote,special_action)
  officernote = self:init_notes_v3(guild_index,name,officernote)
  local newnote
  if ( ep ~= nil) then 
   -- ep = math.max(0,ep)
    newnote = string.gsub(officernote,"(.*{)(%-?%d+)(:)(%-?%d+)(}.*)",function(head,oldep,divider,oldgp,tail) 
      return string.format("%s%s%s%s%s",head,ep,divider,oldgp,tail)
      end)
  end
  if (gp~= nil) then 
   -- gp =  math.max(RetRoll.VARS.baseAE,gp)
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



function RetRoll:update_ep_v3(getname,ep)
  for i = 1, GetNumGuildMembers(1) do
    local name, _, _, _, class, _, note, officernote, _, _ = GetGuildRosterInfo(i)
    if (name==getname) then 
      self:update_epgp_v3(ep,nil,i,name,officernote)
    end
  end  
end


function RetRoll:update_gp_v3(getname,gp)
  for i = 1, GetNumGuildMembers(1) do
    local name, _, _, _, class, _, note, officernote, _, _ = GetGuildRosterInfo(i)
    if (name==getname) then 
      self:update_epgp_v3(nil,gp,i,name,officernote) 
    end
  end  
end


function RetRoll:get_ep_v3(getname,officernote) -- gets ep by name or note
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

function RetRoll:get_gp_v3(getname,officernote) -- gets gp by name or officernote
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

function RetRoll:award_raid_ep(ep) -- awards ep to raid members in zone
  if GetNumRaidMembers()>0 then
	local award = {}
    for i = 1, GetNumRaidMembers(true) do
      local name, rank, subgroup, level, class, fileName, zone, online, isDead = GetRaidRosterInfo(i)
      if level >= RetRoll.VARS.minlevel then
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
function RetRoll:award_raid_gp(gp) -- awards gp to raid members in zone
  if GetNumRaidMembers()>0 then
	local award = {}
    for i = 1, GetNumRaidMembers(true) do
      local name, rank, subgroup, level, class, fileName, zone, online, isDead = GetRaidRosterInfo(i)
      if level >= RetRoll.VARS.minlevel then
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

function RetRoll:award_reserve_ep(ep) -- awards ep to reserve list
  if table.getn(RetRoll.reserves) > 0 then
	local award = {}
    for i, reserve in ipairs(RetRoll.reserves) do
      local name, class, rank, alt = unpack(reserve)
		local _,mName =  self:givename_ep(name,ep,award)
		 table.insert (award, mName)
    end
    self:simpleSay(string.format(L["Giving %d MainStanding to active reserves"],ep))
    self:addToLog(string.format(L["Giving %d MainStanding to active reserves"],ep))
    local addonMsg = string.format("RESERVES;AWARD;%s",ep)
    self:addonMessage(addonMsg,"GUILD")
    RetRoll.reserves = {}
    reserves_blacklist = {}
    self:refreshPRTablets()
  end
end
function RetRoll:givename_ep(getname,ep) 
	
 return RetRoll:givename_ep(getname,ep,nil)  
end
function RetRoll:givename_ep(getname,ep,block) -- awards ep to a single character
  if not (admin()) then return end
  local isPug, playerNameInGuild = self:isPug(getname)
  local postfix, alt = ""
  if isPug then
    -- Update MainStanding for the level 1 character in the guild
    alt = getname
    getname = playerNameInGuild
    ep = self:num_round(RetRoll_altpercent*ep)
    postfix = string.format(", %s\'s Pug MainStanding Bank.",alt)
  elseif (RetRollAltspool) then
    local main = self:parseAlt(getname)
    if (main) then
      alt = getname
      getname = main
      ep = self:num_round(RetRoll_altpercent*ep)
      postfix = string.format(L[", %s\'s Main."],alt)
    end
  end
  if RetRoll:TFind(block, getname) then
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


function RetRoll:givename_gp(getname,gp) 
 return RetRoll:givename_gp(getname,gp,nil) 
end


function RetRoll:TFind ( t, e) 
if not t then return nil end
    for i, item in ipairs(t) do 
		if item == e then 
			return i 
		end
    end
return nil
end

function RetRoll:givename_gp(getname,gp,block) -- awards gp to a single character
  if not (admin()) then return end
  local isPug, playerNameInGuild = self:isPug(getname)
  local postfix, alt = ""
  if isPug then
    -- Update gp for the level 1 character in the guild
    alt = getname
    getname = playerNameInGuild
    gp = self:num_round(RetRoll_altpercent*gp)
    postfix = string.format(", %s\'s Pug MainStanding Bank.",alt)
  elseif (RetRollAltspool) then
    local main = self:parseAlt(getname)
    if (main) then
      alt = getname
      getname = main
      gp = self:num_round(RetRoll_altpercent*gp)
      postfix = string.format(L[", %s\'s Main."],alt)
    end
  end 
	if RetRoll:TFind (block, getname) then
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


function RetRoll:decay_epgp_v3()
  if not (admin()) then return end
  for i = 1, GetNumGuildMembers(1) do
    local name,_,_,_,class,_,note,officernote,_,_ = GetGuildRosterInfo(i)
    local ep,gp = self:get_ep_v3(name,officernote), self:get_gp_v3(name,officernote)
    if (ep~=nil and gp~=nil) then
      ep = self:num_round(ep*RetRoll_decay)
      gp = self:num_round(gp*RetRoll_decay)
      self:update_epgp_v3(ep,gp,i,name,officernote)
    end
  end
  local msg = string.format(L["All Standing decayed by %s%%"],(1-RetRoll_decay)*100)
  self:simpleSay(msg)
  if not (RetRoll_saychannel=="OFFICER") then self:adminSay(msg) end
  local addonMsg = string.format("ALL;DECAY;%s",(1-(RetRoll_decay or RetRoll.VARS.decay))*100)
  self:addonMessage(addonMsg,"GUILD")
  self:addToLog(msg)
  self:refreshPRTablets() 
end


function RetRoll:gp_reset_v3()
  if (IsGuildLeader()) then
    for i = 1, GetNumGuildMembers(1) do
      local name,_,_,_,class,_,note,officernote,_,_ = GetGuildRosterInfo(i)
      local ep,gp = self:get_ep_v3(name,officernote), self:get_gp_v3(name,officernote)
      if (ep and gp) then
        self:update_epgp_v3(0,RetRoll.VARS.baseAE,i,name,officernote)
      end
    end
    local msg = L["All Standing has been reset to 0/%d."]
    self:debugPrint(string.format(msg,RetRoll.VARS.baseAE))
    self:adminSay(string.format(msg,RetRoll.VARS.baseAE))
    self:addToLog(string.format(msg,RetRoll.VARS.baseAE))
  end
end

function RetRoll:ClearGP_v3()
  if (IsGuildLeader()) then
    for i = 1, GetNumGuildMembers(1) do
      local name,_,_,_,class,_,note,officernote,_,_ = GetGuildRosterInfo(i)
      local ep,gp = self:get_ep_v3(name,officernote), self:get_gp_v3(name,officernote)
      if (ep and gp) then
        self:update_epgp_v3(ep,RetRoll.VARS.baseAE,i,name,officernote)
      end
    end
    local msg = L["All AuxStanding has been reset to %d."]
    self:debugPrint(string.format(msg,RetRoll.VARS.baseAE))
    self:adminSay(string.format(msg,RetRoll.VARS.baseAE))
    self:addToLog(string.format(msg,RetRoll.VARS.baseAE))
  end
end



function RetRoll:my_epgp_announce(use_main)
  local ep,gp
  if (use_main) then
    ep,gp = (self:get_ep_v3(RetRoll_main) or 0), (self:get_gp_v3(RetRoll_main) or RetRoll.VARS.baseAE)
  else
    ep,gp = (self:get_ep_v3(self._playerName) or 0), (self:get_gp_v3(self._playerName) or RetRoll.VARS.baseAE)
  end
  local baseRoll = RetRoll:GetBaseRollValue(ep,gp)
  local msg = string.format(L["You now have: %d MainStanding %d AuxStanding + (%d)"], ep,gp,baseRoll)
  self:defaultPrint(msg)
end

function RetRoll:my_epgp(use_main)
  GuildRoster()
  self:ScheduleEvent("retrollRosterRefresh",self.my_epgp_announce,3,self,use_main)
end

---------
-- Menu
---------
RetRoll.hasIcon = "Interface\\Icons\\INV_Misc_ArmorKit_19"
RetRoll.title = "retroll"
RetRoll.defaultMinimapPosition = 180
RetRoll.defaultPosition = "RIGHT"
RetRoll.cannotDetachTooltip = true
RetRoll.tooltipHiddenWhenEmpty = false
RetRoll.independentProfile = true

function RetRoll:OnTooltipUpdate()
  local hint = L["|cffffff00Click|r to toggle Standings.%s \n|cffffff00Right-Click|r for Options."]
  if (admin()) then
    hint = string.format(hint,L[" \n|cffffff00Ctrl+Click|r to toggle Reserves. \n|cffffff00Alt+Click|r to toggle Bids. \n|cffffff00Shift+Click|r to toggle Loot. \n|cffffff00Ctrl+Alt+Click|r to toggle Alts. \n|cffffff00Ctrl+Shift+Click|r to toggle Logs."])
  else
    hint = string.format(hint,"")
  end
  T:SetHint(hint)
end

function RetRoll:OnClick()
  local is_admin = admin()
  if (IsControlKeyDown() and IsShiftKeyDown() and is_admin) then
    RetRoll_logs:Toggle()
  elseif (IsControlKeyDown() and IsAltKeyDown() and is_admin) then
    RetRollAlts:Toggle()
  elseif (IsControlKeyDown() and is_admin) then
    RetRoll_reserves:Toggle()
  elseif (IsShiftKeyDown() and is_admin) then
   -- RetRoll_loot:Toggle()      
  elseif (IsAltKeyDown() and is_admin) then
  --  RetRoll_bids:Toggle()
  else
    RetRoll_standings:Toggle()
  end
end

function RetRoll:SetRefresh(flag)
  needRefresh = flag
  if (flag) then
    self:refreshPRTablets()
  end
end

function RetRoll:buildRosterTable()
  local g, r = { }, { }
  local numGuildMembers = GetNumGuildMembers(1)
  if (RetRoll_raidonly) and GetNumRaidMembers() > 0 then
    for i = 1, GetNumRaidMembers(true) do
      local name, rank, subgroup, level, class, fileName, zone, online, isDead = GetRaidRosterInfo(i) 
      if (name) then
        r[name] = true
      end
    end
  end
  RetRoll.alts = {}
  for i = 1, numGuildMembers do
    local member_name,_,_,level,class,_,note,officernote,_,_ = GetGuildRosterInfo(i)
    if member_name and member_name ~= "" then
      local main, main_class, main_rank = self:parseAlt(member_name,officernote)
      local is_raid_level = tonumber(level) and level >= RetRoll.VARS.minlevel
      if (main) then
        if ((self._playerName) and (name == self._playerName)) then
          if (not RetRoll_main) or (RetRoll_main and RetRoll_main ~= main) then
            RetRoll_main = main
            self:defaultPrint(L["Your main has been set to %s"],RetRoll_main)
          end
        end
        main = C:Colorize(BC:GetHexColor(main_class), main)
        RetRoll.alts[main] = RetRoll.alts[main] or {}
        RetRoll.alts[main][member_name] = class
      end
      if (RetRoll_raidonly) and next(r) then
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

function RetRoll:buildClassMemberTable(roster,epgp)
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
        c[class].args[name].set = function(v) RetRoll:givename_ep(name, tonumber(v)) RetRoll:refreshPRTablets() end
      elseif epgp == "AuxStanding" then
        c[class].args[name].get = false
        c[class].args[name].set = function(v) RetRoll:givename_gp(name, tonumber(v)) RetRoll:refreshPRTablets() end
      end
      c[class].args[name].validate = function(v) return (type(v) == "number" or tonumber(v)) and tonumber(v) < RetRoll.VARS.max end
    end
  end
  return c
end

---------------
-- Alts
---------------
function RetRoll:parseAlt(name,officernote)
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


---------------
-- Reserves
---------------
function RetRoll:reservesToggle(flag)
  local reservesChannelID = tonumber((GetChannelName(RetRoll_reservechannel)))
  if (flag) then -- we want in
    if (reservesChannelID) and reservesChannelID ~= 0 then
      RetRoll.reservesChannelID = reservesChannelID
      if not self:IsEventRegistered("CHAT_MSG_CHANNEL") then
        self:RegisterEvent("CHAT_MSG_CHANNEL","captureReserveChatter")
      end
      return true
    else
      self:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE","reservesChannelChange")
      JoinChannelByName(RetRoll_reservechannel)
      return
    end
  else -- we want out
    if (reservesChannelID) and reservesChannelID ~= 0 then
      self:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE","reservesChannelChange")
      LeaveChannelByName(RetRoll_reservechannel)
      return
    else
      if self:IsEventRegistered("CHAT_MSG_CHANNEL") then
        self:UnregisterEvent("CHAT_MSG_CHANNEL")
      end      
      return false
    end
  end
end

function RetRoll:reservesChannelChange(msg,_,_,_,_,_,_,_,channel)
  if (msg) and (channel) and (channel == RetRoll_reservechannel) then
    if msg == "YOU_JOINED" then
      RetRoll.reservesChannelID = tonumber((GetChannelName(RetRoll_reservechannel)))
      RemoveChatWindowChannel(DEFAULT_CHAT_FRAME:GetID(), RetRoll_reservechannel)
      self:RegisterEvent("CHAT_MSG_CHANNEL","captureReserveChatter")
    elseif msg == "YOU_LEFT" then
      RetRoll.reservesChannelID = nil 
      if self:IsEventRegistered("CHAT_MSG_CHANNEL") then
        self:UnregisterEvent("CHAT_MSG_CHANNEL")
      end
    end
    self:UnregisterEvent("CHAT_MSG_CHANNEL_NOTICE")
    D:Close()
  end
end

function RetRoll:afkcheck_reserves()
  if (running_check) then return end
  if RetRoll.reservesChannelID ~= nil and ((GetChannelName(RetRoll.reservesChannelID)) == RetRoll.reservesChannelID) then
    reserves_blacklist = {}
    RetRoll.reserves = {}
    running_check = true
    RetRoll.timer.count_down = RetRoll.VARS.timeout
    RetRoll.timer:Show()
    SendChatMessage(RetRoll.VARS.reservecall,"CHANNEL",nil,RetRoll.reservesChannelID)
    RetRoll_reserves:Toggle(true)
  end
end

function RetRoll:sendReserverResponce()
  if RetRoll.reservesChannelID ~= nil then
    if (RetRoll_main) then
      if RetRoll_main == self._playerName then
        SendChatMessage("+","CHANNEL",nil,RetRoll.reservesChannelID)
      else
        SendChatMessage(string.format("+%s",RetRoll_main),"CHANNEL",nil,RetRoll.reservesChannelID)
      end
    end
  end
end

function RetRoll:captureReserveChatter(text, sender, _, _, _, _, _, _, channel)
  if not (channel) or not (channel == RetRoll_reservechannel) then return end
  local reserve, reserve_class, reserve_rank, reserve_alt = nil,nil,nil,nil
  local r,_,rdy,name = string.find(text,RetRoll.VARS.reserveanswer)
  if (r) and (running_check) then
    if (rdy) then
      if (name) and (name ~= "") then
        if (not self:inRaid(name)) then
          reserve, reserve_class, reserve_rank = self:verifyGuildMember(name)
          if reserve ~= sender then
            reserve_alt = sender
          end
        end
      else
        if (not self:inRaid(sender)) then
          reserve, reserve_class, reserve_rank = self:verifyGuildMember(sender)    
        end
      end
      if reserve and reserve_class and reserve_rank then
        if reserve_alt then
          if not reserves_blacklist[reserve_alt] then
            reserves_blacklist[reserve_alt] = true
            table.insert(RetRoll.reserves,{reserve,reserve_class,reserve_rank,reserve_alt})
          else
            self:defaultPrint(string.format(L["|cffff0000%s|r trying to add %s to Reserves, but has already added a member. Discarding!"],reserve_alt,reserve))
          end
        else
          if not reserves_blacklist[reserve] then
            reserves_blacklist[reserve] = true
            table.insert(RetRoll.reserves,{reserve,reserve_class,reserve_rank})
          else
            self:defaultPrint(string.format(L["|cffff0000%s|r has already been added to Reserves. Discarding!"],reserve))
          end
        end
      end
    end
    return
  end
  local q = string.find(text,L["^{retroll}Type"])
  if (q) and not (running_check) then
    if --[[(not UnitInRaid("player")) or]] (not self:inRaid(sender)) then
      StaticPopup_Show("RET_EP_RESERVE_AFKCHECK_RESPONCE")
    end
  end
end

------------
-- Logging
------------
function RetRoll:addToLog(line,skipTime)
  local over = table.getn(RetRoll_log)-RetRoll.VARS.maxloglines+1
  if over > 0 then
    for i=1,over do
      table.remove(RetRoll_log,1)
    end
  end
  local timestamp
  if (skipTime) then
    timestamp = ""
  else
    timestamp = date("%b/%d %H:%M:%S")
  end
  table.insert(RetRoll_log,{timestamp,line})
end

------------
-- Utility 
------------
function RetRoll:num_round(i)
  return math.floor(i+0.5)
end

function RetRoll:strsplit(delimiter, subject)
  local delimiter, fields = delimiter or ":", {}
  local pattern = string.format("([^%s]+)", delimiter)
  string.gsub(subject, pattern, function(c) fields[table.getn(fields)+1] = c end)
  return unpack(fields)
end

function RetRoll:strsplitT(delimiter, subject)
 local tbl = {RetRoll:strsplit(delimiter, subject)}
 return tbl
end

 function RetRoll:verifyGuildMember(name,silent)
	RetRoll:verifyGuildMember(name,silent,false)
 end
function RetRoll:verifyGuildMember(name,silent,ignorelevel)
  for i=1,GetNumGuildMembers(1) do
    local g_name, g_rank, g_rankIndex, g_level, g_class, g_zone, g_note, g_officernote, g_online = GetGuildRosterInfo(i)
    if (string.lower(name) == string.lower(g_name)) and (ignorelevel or tonumber(g_level) >= RetRoll.VARS.minlevel) then 
    -- == MAX_PLAYER_LEVEL]]
      return g_name, g_class, g_rank, g_officernote
    end
  end
  if (name) and name ~= "" and not (silent) then
    self:defaultPrint(string.format(L["%s not found in the guild or not max level!"],name))
  end
  return
end

function RetRoll:inRaid(name)
  for i=1,GetNumRaidMembers() do
    if name == (UnitName(raidUnit[i])) then
      return true
    end
  end
  return false
end

function RetRoll:lootMaster()
  local method, lootmasterID = GetLootMethod()
  if method == "master" and lootmasterID == 0 then
    return true
  else
    return false
  end
end

function RetRoll:testMain()
  if (RetRoll_main == nil) or (RetRoll_main == "") then
    if (IsInGuild()) then
      StaticPopup_Show("RET_EP_SET_MAIN")
    end
  end
end

function RetRoll:make_escable(framename,operation)
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
function RetRoll:suggestedAwardMainStanding()


    local isMainStanding , reward = RetRoll.GetReward()
    if not isMainStanding and reward then
        return reward
    end


return RetRoll.VARS.baseawardpoints
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
--   return RetRoll.VARS.baseawardpoints
-- else
--   multiplier = zone_multipliers[RetRoll_progress][currentTier]
-- end
-- if (multiplier) then
--   return multiplier*RetRoll.VARS.baseawardpoints
-- else
--   return RetRoll.VARS.baseawardpoints
-- end
end
function RetRoll:suggestedAwardAuxStanding()

    local isMainStanding , reward = RetRoll.GetReward()
    if ( isMainStanding) and reward then
        return reward
    end


return RetRoll.VARS.baseawardpoints
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
--   return RetRoll.VARS.baseawardpoints
-- else
--   multiplier = zone_multipliers[RetRoll_progress][currentTier]
-- end
-- if (multiplier) then
--   return multiplier*RetRoll.VARS.baseawardpoints
-- else
--   return RetRoll.VARS.baseawardpoints
-- end
end
function RetRoll:parseVersion(version,otherVersion)
	if   version then  
  if not RetRoll._version then
      RetRoll._version = {  
		major = 0,
		minor = 0,
		patch = 0
	}
  
  end
  for major,minor,patch in string.gfind(version,"(%d+)[^%d]?(%d*)[^%d]?(%d*)") do
    RetRoll._version.major = tonumber(major)
    RetRoll._version.minor = tonumber(minor)
    RetRoll._version.patch = tonumber(patch)
  end
  end
  if (otherVersion) then
    if not RetRoll._otherversion then RetRoll._otherversion = {} end
    for major,minor,patch in string.gfind(otherVersion,"(%d+)[^%d]?(%d*)[^%d]?(%d*)") do
      RetRoll._otherversion.major = tonumber(major)
      RetRoll._otherversion.minor = tonumber(minor)
      RetRoll._otherversion.patch = tonumber(patch)      
    end
    if (RetRoll._otherversion.major ~= nil and RetRoll._version ~= nil and RetRoll._version.major ~= nil) then
      if (RetRoll._otherversion.major < RetRoll._version.major) then -- we are newer
        return
      elseif (RetRoll._otherversion.major > RetRoll._version.major) then -- they are newer
        return true, "major"        
      else -- tied on major, go minor
        if (RetRoll._otherversion.minor ~= nil and RetRoll._version.minor ~= nil) then
          if (RetRoll._otherversion.minor < RetRoll._version.minor) then -- we are newer
            return
          elseif (RetRoll._otherversion.minor > RetRoll._version.minor) then -- they are newer
            return true, "minor"
          else -- tied on minor, go patch
            if (RetRoll._otherversion.patch ~= nil and RetRoll._version.patch ~= nil) then
              if (RetRoll._otherversion.patch < RetRoll._version.patch) then -- we are newer
                return
              elseif (RetRoll._otherversion.patch > RetRoll._version.patch) then -- they are newwer
                return true, "patch"
              end
            elseif (RetRoll._otherversion.patch ~= nil and RetRoll._version.patch == nil) then -- they are newer
              return true, "patch"
            end
          end    
        elseif (RetRoll._otherversion.minor ~= nil and RetRoll._version.minor == nil) then -- they are newer
          return true, "minor"
        end
      end
    end
  end
 
end

function RetRoll:camelCase(word)
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
  text = L["Set your main to be able to participate in Reserve List Standing Checks."],
  button1 = TEXT(ACCEPT),
  button2 = TEXT(CANCEL),
  hasEditBox = 1,
  maxLetters = 12,
  OnAccept = function()
    local editBox = getglobal(this:GetParent():GetName().."EditBox")
    local name = RetRoll:camelCase(editBox:GetText())
    RetRoll_main = RetRoll:verifyGuildMember(name)
  end,
  OnShow = function()
    getglobal(this:GetName().."EditBox"):SetText(RetRoll_main or "")
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
    RetRoll_main = RetRoll:verifyGuildMember(editBox:GetText())
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
StaticPopupDialogs["RET_EP_RESERVE_AFKCHECK_RESPONCE"] = {
  text = " ",
  button1 = TEXT(YES),
  button2 = TEXT(NO),
  OnShow = function()
    this._timeout = RetRoll.VARS.timeout-1
  end,
  OnUpdate = function(elapsed,dialog)
    this._timeout = this._timeout - elapsed
    getglobal(dialog:GetName().."Text"):SetText(string.format(L["Reserves AFKCheck. Are you available? |cff00ff00%0d|rsec."],this._timeout))
    if (this._timeout<=0) then
      this._timeout = 0
      dialog:Hide()
    end
  end,
  OnAccept = function()
    this._timeout = 0
    RetRoll:sendReserverResponce()
  end,
  timeout = 0,--RetRoll.VARS.timeout,
  exclusive = 1,
  showAlert = 1,
  whileDead = 1,
  hideOnEscape = 1  
}
StaticPopupDialogs["RET_EP_CONFIRM_RESET"] = {
  text = L["|cffff0000Are you sure you want to Reset ALL Standing?|r"],
  button1 = TEXT(OKAY),
  button2 = TEXT(CANCEL),
  OnAccept = function()
    RetRoll:gp_reset_v3()
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
    RetRoll:ClearGP_v3()
  end,
  timeout = 0,
  whileDead = 1,
  exclusive = 1,
  showAlert = 1,
  hideOnEscape = 1
}


function RetRoll:EasyMenu_Initialize(level, menuList)
  for i, info in ipairs(menuList) do
    if (info.text) then
      info.index = i
      UIDropDownMenu_AddButton( info, level )
    end
  end
end
function RetRoll:EasyMenu(menuList, menuFrame, anchor, x, y, displayMode, level)
  if ( displayMode == "MENU" ) then
    menuFrame.displayMode = displayMode
  end
  UIDropDownMenu_Initialize(menuFrame, function() RetRoll:EasyMenu_Initialize(level, menuList) end, displayMode, level)
  ToggleDropDownMenu(1, nil, menuFrame, anchor, x, y)
end
function RetRoll:GetRollingGP(gp)

    return math.max(-1 * RetRoll.VARS.AERollCap , math.min(RetRoll.VARS.AERollCap,gp) )
end
function RetRoll:GetBaseRollValue(ep,gp)

    return  ep + RetRoll:GetRollingGP(gp)

end

function RetRoll:RollCommand(isSRRoll,isDSRRoll,isOS,bonus)
  local playerName = UnitName("player")
  local ep = 0 
  local gp = 0
  local desc = ""  
  local hostG= RetRoll:GetGuildName()
	if (IsPugInHostedRaid()) then
		hostG = RetRoll.VARS.HostGuildName
		local key = RetRoll:GetGuildKey(RetRoll.VARS.HostGuildName)
		if RetRoll_pugCache[key] and RetRoll_pugCache[key][playerName] then
		-- Player is a Pug, use stored EP
			ep = RetRoll_pugCache[key][playerName][1] 
			
			
			gp = RetRoll_pugCache[key][playerName][2]
			local inguildn = RetRoll_pugCache[key][playerName][3] or ""
			desc = string.format("PUG(%s)",inguildn)
		else
			ep = 0
			gp = 0
			desc = "Unregistered PUG"
		end
	  -- Check if the player is an alt
	elseif RetRollAltspool then
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
  local baseRoll = RetRoll:GetBaseRollValue(ep,gp)
  if isOS then
    baseRoll= baseRoll - RetRoll.VARS.OSPenalty
  end
  if isSRRoll then
    minRoll = 101 + baseRoll
    maxRoll = 200 + baseRoll
    if isDSRRoll then
      minRoll = 101 + 20 +baseRoll
      maxRoll = 200 + 20 +baseRoll
    end
  else
    minRoll = 1   + baseRoll
    maxRoll = 100 + baseRoll
  end
  minRoll = minRoll + bonus
  maxRoll = maxRoll + bonus
	
  if maxRoll < 0 then maxRoll = 0 end
  if minRoll < 0 then minRoll = 0 end
  if minRoll > maxRoll then minRoll = maxRoll end

  RandomRoll(minRoll, maxRoll)
  local cappedGP =  RetRoll:GetRollingGP(gp)
  -- Prepare the announcement message
  local bonusText = " as "..desc.." of "..hostG
  local message = string.format("I rolled Main Spec %d - %d with %d "..L["MainStanding"].." +%d "..L["AuxStanding"].." (%d)%s", minRoll, maxRoll, ep ,cappedGP, gp,  bonusText)
  
  if(isOS) then
    message = string.format("I rolled Off Spec %d - %d with %d "..L["MainStanding"].." +%d "..L["AuxStanding"].." (%d)%s", minRoll, maxRoll, ep ,cappedGP, gp,  bonusText)
  end
  if(isSRRoll) then
    message = string.format("I rolled SR %d - %d with %d "..L["MainStanding"].." +%d "..L["AuxStanding"].." (%d)%s", minRoll, maxRoll, ep ,cappedGP, gp, bonusText)
  end
  if(isDSRRoll) then
    message = string.format("I rolled Double SR %d - %d with %d "..L["MainStanding"].." +%d "..L["AuxStanding"].." (%d)%s", minRoll, maxRoll, ep ,cappedGP, gp, bonusText)
  end

  if bonus > 0 then
    local weeks = math.floor(bonus / 20)
    bonusText = string.format(" +%d for %d weeks", bonus, weeks)..bonusText
    message = string.format("I rolled Cumulative SR %d - %d with %d "..L["MainStanding"].." +%d(%d"..L["AuxStanding"]..")%s", minRoll, maxRoll, ep ,cappedGP, gp, bonusText)
  end
  -- Determine the chat channel
  local chatType = UnitInRaid("player") and "RAID" or "SAY"
  
  -- Send the message
  SendChatMessage(message, chatType)
end
function RetRoll:isPug(name)
  for i = 1, GetNumGuildMembers(1) do
    local guildMemberName, _, _, _, _, _, _, officerNote = GetGuildRosterInfo(i)
 
    if officerNote and officerNote ~= '' then
      local _,_,pugName = string.find(officerNote, "{pug:([^}]+)}")
        if pugName == name then
          return true, guildMemberName 
        end
    end
  end
  return false
end
function RetRoll:isBank(name)
  for i = 1, GetNumGuildMembers(1) do
    local guildMemberName, _, _, _, _, _, _, officerNote = GetGuildRosterInfo(i)
	
	if guildMemberName == name then
		if officerNote and officerNote ~= '' then
		  local _,_,pugName = string.find(officerNote, "{pug:([^}]+)}")
			if pugName then
			  return true,   pugName
			end
		end
	end
 
  end
  return false
end

function RetRoll:CheckPugStanding()
  local playerName = UnitName("player")
  local foundEP = false
  
  for guildName, guildData in pairs(RetRoll_pugCache) do
    if guildData[playerName] then
      self:defaultPrint(string.format("Your "..L["MainStanding"].." for %s: %d , %d", guildName, guildData[playerName][1],guildData[playerName][2]))
      foundEP = true
    end
  end
  
  if not foundEP then
    self:defaultPrint("No "..L["MainStanding"].." found for " .. playerName .. " in any guild")
  end
end
function RetRoll:getAllPugs()
  local pugs = {}
  for i = 1, GetNumGuildMembers(1) do
    local guildMemberName, _, _, guildMemberLevel, _, _, _, officerNote = GetGuildRosterInfo(i)
    if officerNote and officerNote ~= '' then
      local _, _, pugName = string.find(officerNote, "{pug:([^}]+)}")
      if pugName then
        pugs[guildMemberName] = pugName
      end
    end
  end
  return pugs
end
function RetRoll:updateAllPugStanding( force )
  if not admin() and not force then
    self:defaultPrint("You don't have permission to perform this action.")
    return
  end
  local pugs = self:getAllPugs()
  local count = 0

  local packet={}
  local pi = 0
  for guildMemberName, pugName in pairs(pugs) do
	if RetRoll:inRaid(pugName) then
		local ep = self:get_ep_v3(guildMemberName) or 0
		local gp = self:get_gp_v3(guildMemberName) or 0
		table.insert(packet,pugName..":"..guildMemberName..":"..ep..":"..gp)
		pi = pi + 1
		
		if pi >= 4 then
			self:sendPugEpUpdatePacket(packet)
			packet={}
			pi = 0
		end
		--self:sendPugEpUpdate(pugName, ep)
		count = count + 1
	end
  end
	if pi >0 then
		self:sendPugEpUpdatePacket(packet)
		packet={}
		pi = 0
	end
  self:defaultPrint(string.format("Updated "..L["MainStanding"].." for %d Pug player(s)", count))
end


function RetRoll:getPugName(name)
  for i = 1, GetNumGuildMembers(1) do
      local guildMemberName, _, _, _, _, _, _, officerNote = GetGuildRosterInfo(i)
      if guildMemberName == name then
          local _, _, pugName = string.find(officerNote or "", "{pug:([^}]+)}")
          return pugName
      end
  end
  return nil
end 
local RaidKey = {[L["Molten Core"]]="MC",[L["Onyxia\'s Lair"]]="ONY",[L["Blackwing Lair"]]="BWL",[L["Ahn\'Qiraj"]]="AQ40",[L["Naxxramas"]]="NAX",["Tower of Karazhan"]="K10",["Upper Tower of Karazhan"]="K40",["???"]="K40"}
function RetRoll:GetReward()

   local raw = string.gsub(string.gsub(GetGuildInfoText(),"\n","#")," ","")
   local Scores ={}
   local reward = RetRoll.VARS.baseawardpoints
  for tier in string.gfind(raw,"(B[^:]:[^:]+:[^#]+#)") do
        local _,_,dungeons,rewards = string.find(tier,"B[^:]:([^:]+):([^#]+)#")
        local ds =  RetRoll:strsplitT(",",dungeons)
        local ss =  RetRoll:strsplitT(",",rewards)

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

function RetRoll:UpdateHostInfo()
 
	
	local ownGuild =(GetGuildInfo("player"))
	local playerName = UnitName("player")
	local isInGuild = (guildName) and guildName ~= ""
	if (GetNumRaidMembers() > 0 ) then -- we entered a raid or raid updated

        if not inRaid then 
            inRaid = true
        end
		local _ ,raidlead = RetRoll:GetRaidLeader()
		if (RetRoll.VARS.HostLeadName ~= raidlead ) then --raid leadership changed or new raid
			
			if RetRoll.VARS.HostLeadName ~= "!" then
			--leadership changed
			
				if raidlead == playerName then
					RetRollMSG:DBGMSG("Leadership assigned to you, Sending host info")
					RetRoll.VARS.HostGuildName =  ownGuild 
					RetRoll.VARS.HostLeadName = playerName
					RetRoll:SendHostInfoUpdate(nil)
				else
					RetRollMSG:DBGMSG("Leadership changed, requesting host info")
					RetRoll.VARS.HostGuildName = "!"
					RetRoll.VARS.HostLeadName ="!"
					RetRoll:RequestHostInfo()
				end

			else
			
				if raidlead == UnitName("player") then
					RetRollMSG:DBGMSG("Raid Created, Sending host info")
					RetRoll.VARS.HostGuildName =  ownGuild 
					RetRoll.VARS.HostLeadName = playerName
					RetRoll:SendHostInfoUpdate(nil)

				else
					RetRollMSG:DBGMSG("Joined Raid, requesting host info")
					RetRoll:RequestHostInfo()
				end
				
				
			end
		end
  
	else -- we left raid
    if inRaid then
		RetRollMSG:DBGMSG("Leaving Raid")
        inRaid = false
    end
		RetRoll.VARS.HostGuildName = "!"
		RetRoll.VARS.HostLeadName ="!"
	end 

 
end

function RetRoll:GetGuildName()
	local guildName, _, _ = GetGuildInfo("player")
	return guildName
end


function IsPugInHostedRaid()
	local GuildName = RetRoll:GetGuildName()
	
	--DEFAULT_CHAT_FRAME:AddMessage("GuildName "..GuildName.." RetRoll.VARS.HostGuildName " .. RetRoll.VARS.HostGuildName  )
	
	return GuildName =="" or RetRoll.VARS.HostGuildName ~="!" and RetRoll.VARS.HostGuildName ~= GuildName
end
 
function RetRoll:GetRaidLeader()
for i = 1, GetNumRaidMembers() do
	local name, rank, _, _, _, _, _, online  = GetRaidRosterInfo(i);
	if (rank == 2) then return i,name,online end
end
	return ""
end

function RetRoll:GetRaidLeadGuild() 
	local guildName = nil
    local index,name,online = RetRoll:GetRaidLeader()
	
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
 
function RetRoll:GetGuildKey(g) 
	return (string.gsub(g ," ",""))
end
 

local lastHostInfoDispatch = 0
local HostInfoRequestsSinceLastDispatch = 0

function RetRoll:SendHostInfoUpdate( member , epgp)

	local GuildName = RetRoll:GetGuildName()
	if GuildName == nil or GuildName == "" then DEFAULT_CHAT_FRAME:AddMessage("SendHostInfoUpdate : not in guild") return end
	 
	-- is raid a guild raid
	local GuildRules = true
	-- is the sender a pug
	
	local prio = "BULK"
	local message = string.format("%s:%s",GuildName,tostring(GuildRules))
	if (member) then
		local isPug,inGuildName =  RetRoll:isPug(member)
	
		if isPug then
			local ep,gp
			if epgp then
 
				_,_, ep,gp = string.find(epgp, "{(%d+):(%d+)}")
 
				--DEFAULT_CHAT_FRAME:AddMessage(string.format("MainStandinggp %s  %d %d", epgp,  ep,gp)) 
			else
				ep = self:get_ep_v3(inGuildName)  
				gp = self:get_gp_v3(inGuildName)  
			end
			prio = "ALERT"
			message = message ..":"..string.format("%s:%s:%d:%d",member,inGuildName,ep,gp)
		else
			if RetRoll:verifyGuildMember(member,true,true) then
			
			else
				message = message ..":"..string.format("%s:%s:%d:%d",member,"!!",0,0)
			end
		end
	end
	RetRoll:SendMessage(RetRollMSG.HostInfoUpdate,message,prio) 
end


function RetRoll:Status()
DEFAULT_CHAT_FRAME:AddMessage("Host LeadName " .. RetRoll.VARS.HostLeadName )
DEFAULT_CHAT_FRAME:AddMessage("Host GuildName " .. RetRoll.VARS.HostGuildName ) 
end

function RetRoll:ParseHostInfo(  sender , text )

	RetRollMSG:DBGMSG("Parsing HostInfo:"..text)
	local GuildName = RetRoll:GetGuildName()
	local fields = RetRoll:strsplitT(':', text)
	RetRoll.VARS.HostLeadName = sender or "!"
	local HostGuildName = fields[1]
	if HostGuildName then
		local oldHost = RetRoll.VARS.HostGuildName 
		RetRoll.VARS.HostGuildName =  fields[1] 
		
		if oldHost~=RetRoll.VARS.HostGuildName then
			self:defaultPrint(string.format("This Raid is hosted by %s.", HostGuildName))
		end
		if HostGuildName == GuildName then
			-- enable guildrules
		else
		--is message targetting us
			local TargetMember = fields[3]
				if TargetMember == UnitName("player") then
					-- pug
					local PugReg = fields[4]
					
					if PugReg and PugReg ~= "!!"  then
						-- registered

						local ep = tonumber(fields[5]) or 0
						local gp = tonumber(fields[6]) or 0
						-- update ep/gp cache
						local key = RetRoll:GetGuildKey(RetRoll.VARS.HostGuildName)
						if not RetRoll_pugCache[key] then
							RetRoll_pugCache[key] = {}
						end
						RetRoll_pugCache[key][fields[3]] = {ep,gp,PugReg}
						self:defaultPrint(string.format("Updated Standing for %s as %s in guild %s: %d : %d",  TargetMember, PugReg, HostGuildName, ep,gp))
					else
						-- announce unregistered
						self:defaultPrint(string.format("You don't have standing bank character in %s, contact one of their officers for that", HostGuildName))
					end
				end
		end
	else
		return
	end
	-- update guild ep cache
end
function RetRoll:RequestHostInfo() 
	if GetTime()-RetRollMSG.RequestHostInfoUpdateTS > 5 then
		RetRollMSG.RequestHostInfoUpdateTS = GetTime()
		RetRoll:SendMessage(RetRollMSG.RequestHostInfoUpdate,"RequestHostInfoUpdate","ALERT")
	end
end 


function RetRoll:sendPugEpUpdatePacket(packet)
	
	

	local updateline = string.format("%s{", RetRoll:GetGuildName())
	for i, ep in ipairs(packet) do
		updateline = updateline .. ep
		if (i<table.getn(packet)) then 
			updateline = updateline .. ","
		end
		
		
	end
	
		updateline = updateline .. "}"
	RetRollMSG:DBGMSG("Sending a packet")
	RetRoll:SendMessage(RetRollMSG.PugStandingUpdate,updateline,"BULK")
end

function RetRoll:parsePugEpUpdatePacket(message)

	
 local playerName = UnitName("player") 
 local _, _, guildName , packet = string.find(message,"([^{]+){([^}]+)}")
  local segs = RetRoll:strsplitT(',', packet)
  
  for i, seg in pairs(segs) do
  
	local _, _, name,inGuildName, ep, gp = string.find(seg, "(%S+):(%S+):(%d+):(%d+)")

	if playerName == name then
	 if playerName and inGuildName and ep and gp then
		
      if guildName then
		local key = RetRoll:GetGuildKey(guildName)
        if RetRoll_pugCache == nil then 
            RetRoll_pugCache = {}
        end
        if  RetRoll_pugCache[key] == nil then
          RetRoll_pugCache[key] = {}
        end
        RetRoll_pugCache[key][playerName] = {ep,gp}

        self:defaultPrint(string.format("Updated Standing for %s in guild %s as %s: %d : %d", playerName, guildName,inGuildName, ep,gp))
        end
      else
        self:defaultPrint("Could not parse guild name from broadcast "  )
      end

	end
 
  end
end


function RetRoll:ReportIfPugs()
	local GuildName = RetRoll:GetGuildName()
	if (GuildName and  GuildName == RetRoll.VARS.HostGuildName and RetRoll:inRaid(pug)) then
		RetRoll:SendHostInfoUpdate( pug)
	end
end

function RetRoll:ReportPugManualEdit(pug , epgp)
	local GuildName = RetRoll:GetGuildName()
	if (pug and epgp and GuildName and  GuildName == RetRoll.VARS.HostGuildName and RetRoll:inRaid(pug)) then
		RetRoll:SendHostInfoUpdate( pug, epgp)
	end
end

function RetRoll:SendMessage(subject, msg , prio)
	prio = prio or "BULK"
	RetRollMSG:DBGMSG("--SendingAddonMSG["..subject.."]:"..msg , true) 
    if GetNumRaidMembers() == 0 then
       -- SendAddonMessage(RetRollMSG.prefix..subject, msg, "PARTY", UnitName("player"));
		ChatThrottleLib:SendAddonMessage(prio, RetRollMSG.prefix..subject, msg, "PARTY")
    else
		ChatThrottleLib:SendAddonMessage(prio, RetRollMSG.prefix..subject, msg, "RAID")
    end
end
function RetRollMSG:DBGMSG(msg)
		RetRollMSG:DBGMSG(msg, false)
end
function RetRollMSG:DBGMSG(msg, red)
	if RetRollMSG.dbg then 
		if red then
			DEFAULT_CHAT_FRAME:AddMessage( msg ,0.5,0.5,0.8 )   
		else
			DEFAULT_CHAT_FRAME:AddMessage( msg ,0.9,0.5,0.5 ) 
		end
	end
end


function RetRollMSG:OnCHAT_MSG_ADDON( prefix, text, channel, sender)
		
	
	if ( RetRollMSG.delayedinit) then  RetRoll:addonComms(prefix,text,channel,sender) end
	 
		if (channel == "RAID" or channel == "PARTY") then
		
		if (  string.find( prefix, RetRollMSG.prefix) ) then  
			
			
				if ( sender == UnitName("player")) then 
					--RetRollMSG:DBGMSG("sent a message" )   
					return 
				end
				--RetRollMSG:DBGMSG("Recieved a message" )  
				
				local _ ,raidlead = RetRoll:GetRaidLeader()
				if (UnitName("player")==raidlead) then
				--	RetRollMSG:DBGMSG("as reaidleader" )  
					if ( string.find( prefix, RetRollMSG.RequestHostInfoUpdate) and  RetRoll:inRaid(sender)) then
						RetRollMSG:DBGMSG("Recieved a RequestHostInfoUpdate from " .. sender ) 
						 RetRoll:SendHostInfoUpdate(sender)
					end
				else
					--RetRollMSG:DBGMSG("as member" )  
					
					if (sender == raidlead) then
					RetRollMSG:DBGMSG("from raid leader: " .. sender )  
						if ( string.find( prefix, RetRollMSG.HostInfoUpdate)) then
							RetRollMSG:DBGMSG("Recieved a HostInfoUpdate from " .. sender ) 
							RetRoll:ParseHostInfo( sender, text ) 
						end
						if ( string.find( prefix,RetRollMSG.PugStandingUpdate)) then
							RetRollMSG:DBGMSG("Recieved a PugStandingUpdate from " .. sender ) 
							RetRoll:parsePugEpUpdatePacket( text )
						end
					end
				end 
				
			end
		end
end









-- GLOBALS: RetRoll_saychannel,RetRoll_groupbyclass,RetRoll_groupbyarmor,RetRoll_groupbyrole,RetRoll_raidonly,RetRoll_decay,RetRoll_minPE,RetRoll_reservechannel,RetRoll_main,RetRoll_progress,RetRoll_discount,RetRollAltspool,RetRoll_altpercent,RetRoll_log,RetRoll_dbver,RetRoll_looted,RetRoll_debug,RetRoll_fubar,RetRoll_showRollWindow
-- GLOBALS: RetRoll,RetRoll_prices,RetRoll_standings,RetRoll_bids,RetRoll_loot,RetRoll_reserves,RetRollAlts,RetRoll_logs,RetRoll_pugCache
