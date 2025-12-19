local L = AceLibrary("AceLocale-2.2"):new("guildroll")
function GuildRoll:v2tov3()
  local count = 0
  for i = 1, GetNumGuildMembers(1) do
    local name, _, _, _, class, _, note, officernote, _, _ = GetGuildRosterInfo(i)
    local epv2 = GuildRoll:get_ep_v2(name,note)
    local gpv2 = GuildRoll:get_gp_v2(name,officernote)
    local epv3 = GuildRoll:get_ep_v3(name,officernote)
    local gpv3 = GuildRoll:get_gp_v3(name,officernote)
    if (epv3 and gpv3) then
      -- do nothing, we've migrated already
    elseif (epv2 and gpv2) and (epv2 > 0 and gpv2 >= GuildRoll.VARS.baseAE) then
      count = count + 1
      -- self:defaultPrint(string.format("MainStandingv2:%s,gpv2:%s,i:%s,n:%s,o:%s",epv2,gpv2,i,name,officernote))
      GuildRoll:update_epgp_v3(epv2,gpv2,i,name,officernote)
    end
  end
  self:defaultPrint(string.format(L["Updated %d members to v3 storage."],count))
  GuildRoll_dbver = 3
end

-- GLOBALS: GuildRoll_saychannel,GuildRoll_groupbyclass,GuildRoll_groupbyarmor,GuildRoll_groupbyrole,GuildRoll_decay,GuildRoll_minPE,GuildRoll_main,GuildRoll_progress,GuildRoll_discount,GuildRoll_log,GuildRoll_dbver
-- GLOBALS: GuildRoll,GuildRoll_prices,GuildRoll_standings,GuildRoll_bids,GuildRoll_loot,GuildRollAlts,GuildRoll_logs
