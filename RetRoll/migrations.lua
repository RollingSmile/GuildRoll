local L = AceLibrary("AceLocale-2.2"):new("retroll")
function RetRoll:v2tov3()
  local count = 0
  for i = 1, GetNumGuildMembers(1) do
    local name, _, _, _, class, _, note, officernote, _, _ = GetGuildRosterInfo(i)
    local epv2 = RetRoll:get_ep_v2(name,note)
    local gpv2 = RetRoll:get_gp_v2(name,officernote)
    local epv3 = RetRoll:get_ep_v3(name,officernote)
    local gpv3 = RetRoll:get_gp_v3(name,officernote)
    if (epv3 and gpv3) then
      -- do nothing, we've migrated already
    elseif (epv2 and gpv2) and (epv2 > 0 and gpv2 >= RetRoll.VARS.baseAE) then
      count = count + 1
      -- self:defaultPrint(string.format("MainStandingv2:%s,gpv2:%s,i:%s,n:%s,o:%s",epv2,gpv2,i,name,officernote))
      RetRoll:update_epgp_v3(epv2,gpv2,i,name,officernote)
    end
  end
  self:defaultPrint(string.format(L["Updated %d members to v3 storage."],count))
  RetRoll_dbver = 3
end

-- GLOBALS: RetRoll_saychannel,RetRoll_groupbyclass,RetRoll_groupbyarmor,RetRoll_groupbyrole,RetRoll_raidonly,RetRoll_decay,RetRoll_minPE,RetRoll_reservechannel,RetRoll_main,RetRoll_progress,RetRoll_discount,RetRoll_log,RetRoll_dbver,RetRoll_looted
-- GLOBALS: RetRoll,RetRoll_prices,RetRoll_standings,RetRoll_bids,RetRoll_loot,RetRoll_reserves,RetRollAlts,RetRoll_logs
