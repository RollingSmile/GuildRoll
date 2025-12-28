-- RollWithEP.lua
-- Unified Roll / EP module for Turtle WoW (WoW 1.12)
-- Merges RollWithEP + RollForEP responsibilities and integrates robust bidirectional
-- matching between chat declarations (SR/CSR/MS/EP) and system roll lines (numeric result).
-- Only the loot manager (master looter / raid leader admin) processes detailed roll data;
-- public announcements are still sent to RAID/PARTY. Comments in English; prepared for localization (L).
-- Do NOT modify files inside Libs/.

-- Optional libraries loaded safely if present
local T, D, C, L
do
  local ok, res = pcall(function() return AceLibrary and AceLibrary("Tablet-2.0") end)
  if ok and res then T = res end
  ok, res = pcall(function() return AceLibrary and AceLibrary("Dewdrop-2.0") end)
  if ok and res then D = res end
  ok, res = pcall(function() return AceLibrary and AceLibrary("Crayon-2.0") end)
  if ok and res then C = res end
  ok, res = pcall(function() return AceLibrary and AceLibrary("AceLocale-2.2") end)
  if ok and res and type(res.new) == "function" then
    ok, res = pcall(function() return res:new("guildroll") end)
    if ok and res then L = res end
  end
end

-- Ensure main table exists
if not GuildRoll then GuildRoll = {} end

-- Saved data compatibility
GuildRoll_rollForEPCache = GuildRoll_rollForEPCache or {}
GuildRoll_rollForEPCache.lastImport = GuildRoll_rollForEPCache.lastImport or { timestamp = 0, srlist = {} }
GuildRoll_rollForEPCache._settings = GuildRoll_rollForEPCache._settings or {}
if GuildRoll_rollForEPCache._settings.useCustomLootFrame == nil then
  GuildRoll_rollForEPCache._settings.useCustomLootFrame = true
end

-- Module state
local RollMod = {
  lootSlots = {},           -- current loot slots
  currentSession = nil,     -- active roll session
  frames = {},              -- UI frames
  lastDeclaredRolls = {},   -- legacy single-declaration storage (kept for backward compat)
  _decl_buffer = {},        -- transient buffer: player -> declaration entry
  _sys_buffer = {},         -- transient buffer: player -> system roll entry
  _cleanup_frame = nil,     -- frame for cleanup onupdate
  _debug_matcher = false    -- set true to enable debug messages in chat
}

-- Helpers ---------------------------------------------------------------------
local function StripRealm(name)
  if not name then return nil end
  return string.gsub(name, "%-[^%-]+$", "")
end

local function IsMasterLooter()
  local method, partyIndex, raidIndex = GetLootMethod()
  if method ~= "master" then return false, nil end
  local player = StripRealm(UnitName("player"))
  if GetNumRaidMembers() > 0 then
    if raidIndex and raidIndex > 0 then
      local ml = StripRealm(UnitName("raid"..raidIndex))
      return ml == player, ml
    end
  elseif GetNumPartyMembers() > 0 then
    if partyIndex and partyIndex > 0 then
      local ml = StripRealm(UnitName("party"..partyIndex))
      return ml == player, ml
    elseif partyIndex == 0 then
      return true, player
    end
  end
  return false, nil
end

local function CanUseLootAdmin()
  local ok, isAdmin = pcall(function() return GuildRoll and GuildRoll:IsAdmin() end)
  if not ok or not isAdmin then return false end
  local method = nil
  pcall(function() method = (select(1, GetLootMethod())) end)
  if method == "master" then
    local ml = IsMasterLooter()
    return ml
  else
    local ok2, isRL = pcall(IsRaidLeader)
    return ok2 and isRL
  end
end

local function AnnounceToChannel(text)
  if not text then return end
  if GetNumRaidMembers() > 0 then
    pcall(function() SendChatMessage(text, "RAID") end)
  else
    pcall(function() SendChatMessage(text, "PARTY") end)
  end
end

-- PRIORITY map
local PRIORITY_MAP = {
  CSR = 4,
  SR  = 4,
  ["101"] = 4,
  EP  = 3,
  ["100"] = 3,
  ["99"] = 1,
  ["98"] = 0,
  INVALID = -1
}

-- CSV parser (RaidRes) and legacy parser (kept)
local function splitCSVLine(line)
  local fields = {}
  local i = 1
  local len = string.len(line)
  while i <= len do
    local c = string.sub(line, i, i)
    if c == '"' then
      local j = i + 1
      local field = ""
      while j <= len do
        local ch = string.sub(line, j, j)
        if ch == '"' then
          local nextch = string.sub(line, j+1, j+1)
          if nextch == '"' then
            field = field .. '"'
            j = j + 2
          else
            j = j + 1
            break
          end
        else
          field = field .. ch
          j = j + 1
        end
      end
      if string.sub(line, j, j) == "," then j = j + 1 end
      table.insert(fields, field)
      i = j
    else
      local j = i
      local field = ""
      while j <= len do
        local ch = string.sub(line, j, j)
        if ch == "," then break end
        field = field .. ch
        j = j + 1
      end
      if string.sub(line, j, j) == "," then j = j + 1 end
      table.insert(fields, field)
      i = j
    end
  end
  return fields
end

local function ImportSRCsvRaidRes(text)
  if not text or text == "" then return {} end
  local lines = {}
  for line in string.gmatch(text, "[^\r\n]+") do table.insert(lines, line) end
  if #lines == 0 then return {} end

  local idxStart = 1
  do
    local header = lines[1]
    local sampleFields = splitCSVLine(header)
    local likelyHeader = false
    if sampleFields and #sampleFields >= 3 then
      local h0 = string.lower(sampleFields[1] or "")
      if string.find(h0, "id") or string.find(h0, "item") or string.find(h0, "attendee") then likelyHeader = true end
    end
    if likelyHeader then idxStart = 2 end
  end

  local srmap = {}
  for i = idxStart, #lines do
    local line = lines[i]
    if line and line ~= "" then
      local f = splitCSVLine(line)
      local id = tonumber(f[1]) or nil
      local itemName = f[2] and (f[2] ~= "" and f[2] or nil) or nil
      local attendee = f[3] and (f[3] ~= "" and f[3] or nil) or nil
      if attendee and (id or itemName) then
        local cleanName = StripRealm(attendee)
        if not srmap[cleanName] then srmap[cleanName] = {} end
        table.insert(srmap[cleanName], { itemID = id, itemName = itemName })
      end
    end
  end

  GuildRoll_rollForEPCache.lastImport = { timestamp = time(), srlist = srmap }
  return srmap
end

local function ParseSRCSV_Legacy(text)
  if not text or text == "" then return {} end
  local srdata = {}
  for line in string.gmatch(text, "[^\r\n]+") do
    local name, sr, weeks = string.match(line, "^%s*([^:]+):(%d+):(%d+)%s*$")
    if name and sr then
      name = StripRealm(name)
      srdata[name] = { sr = tonumber(sr) or 0, weeks = tonumber(weeks) or 0 }
    end
  end
  GuildRoll_rollForEPCache.lastImport = { timestamp = time(), srlist = srdata }
  return srdata
end

function RollWithEP_ImportCSV(text)
  if not text or text == "" then
    if GuildRoll and GuildRoll.defaultPrint then GuildRoll:defaultPrint(L and L["No CSV data provided."] or "No CSV data provided.") end
    return
  end
  local firstLine = string.match(text, "([^\r\n]+)")
  if firstLine and string.find(firstLine, ",") then
    local ok, sr = pcall(function() return ImportSRCsvRaidRes(text) end)
    if ok and sr then
      if GuildRoll and GuildRoll.defaultPrint then
        local count = 0 for _ in pairs(sr) do count = count + 1 end
        GuildRoll:defaultPrint(string.format(L and L["CSV imported successfully! %d players with soft reserves."] or "Imported SR data for %d players.", count))
      end
      return sr
    end
  end
  pcall(function() ParseSRCSV_Legacy(text) end)
end

-- SR helpers
local function GetSRListForItem(itemID, itemName)
  local srlist = {}
  local found = {}
  if GuildRoll and GuildRoll._RollForEP_currentLoot and GuildRoll._RollForEP_currentLoot.srlist then
    local sessionSR = GuildRoll._RollForEP_currentLoot.srlist
    for player, items in pairs(sessionSR) do
      if type(items) == "table" then
        for _, item in ipairs(items) do
          local match = false
          if type(item) == "table" then
            if item.itemID and itemID and tonumber(item.itemID) == tonumber(itemID) then match = true
            elseif item.itemName and itemName and item.itemName == itemName then match = true
            end
          end
          if match then
            local clean = StripRealm(player)
            if clean and clean ~= "" and not found[clean] then table.insert(srlist, clean); found[clean] = true end
          end
        end
      end
    end
  end

  if table.getn(srlist) == 0 and GuildRoll_rollForEPCache and GuildRoll_rollForEPCache.lastImport and GuildRoll_rollForEPCache.lastImport.srlist then
    local cacheSR = GuildRoll_rollForEPCache.lastImport.srlist
    for player, items in pairs(cacheSR) do
      if type(items) == "table" then
        for _, item in ipairs(items) do
          local match = false
          if type(item) == "table" then
            if item.itemID and itemID and tonumber(item.itemID) == tonumber(itemID) then match = true
            elseif item.itemName and itemName and item.itemName == itemName then match = true
            end
          end
          if match then
            local clean = StripRealm(player)
            if clean and clean ~= "" and not found[clean] then table.insert(srlist, clean); found[clean] = true end
          end
        end
      end
    end
  end
  return srlist
end

local function HasSR(playerName, srlist)
  if not srlist or table.getn(srlist) == 0 then return false end
  local clean = StripRealm(playerName)
  for _, n in ipairs(srlist) do if StripRealm(n) == clean then return true end end
  return false
end

-- UI: Create custom loot frame
local function CreateLootFrame()
  if RollMod.frames.loot then return RollMod.frames.loot end
  local f = CreateFrame("Frame", "GuildRoll_LootFrame", UIParent, "BasicFrameTemplate")
  f:SetSize(340, 240)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  f:Hide()

  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  f.title:SetPoint("TOP", 0, -6)
  f.title:SetText(L and L["RollWithEP - Loot Session"] or "Loot")

  f.content = CreateFrame("Frame", nil, f)
  f.content:SetPoint("TOPLEFT", 10, -30)
  f.content:SetPoint("BOTTOMRIGHT", -10, 10)
  f.rows = {}

  local function createRow(i)
    local row = CreateFrame("Frame", "GuildRoll_LootRow"..i, f.content)
    row:SetWidth(320); row:SetHeight(28)
    if i == 1 then row:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, 0)
    else row:SetPoint("TOPLEFT", f.rows[i-1], "BOTTOMLEFT", 0, -4) end

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(24, 24); row.icon:SetPoint("LEFT", 2, 0)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0); row.text:SetWidth(210); row.text:SetJustifyH("LEFT")
    row.menuBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.menuBtn:SetSize(86, 20); row.menuBtn:SetPoint("RIGHT", -2, 0); row.menuBtn:SetText(L and L["Open"] or "Open")
    return row
  end

  f.Update = function(self)
    local num = #RollMod.lootSlots
    for i = 1, num do
      local r = self.rows[i]
      if not r then r = createRow(i); self.rows[i] = r end
      local data = RollMod.lootSlots[i]
      r.text:SetText(data.itemLink or data.itemName or "<unknown>")
      if data.texture then r.icon:SetTexture(data.texture) else r.icon:SetTexture(nil) end

      r.menuBtn:SetScript("OnClick", function()
        if D then
          pcall(function()
            D:Open(UIParent,
              "children", function()
                D:AddLine("text", data.itemLink or data.itemName or "Item", "isTitle", true)
                D:AddLine()
                D:AddLine("text", L and L["Start Rolls"] or "Start session",
                  "func", function()
                    if CanUseLootAdmin() then RollMod:StartSessionForItem(data) else if GuildRoll and GuildRoll.defaultPrint then GuildRoll:defaultPrint(L and L["Only master looter or raid leader admin can use this feature."] or "No permission.") end end
                    pcall(function() D:Close() end)
                  end
                )
                D:AddLine("text", L and L["Give to DE/Bank"] or "Give to DE/Bank",
                  "func", function() if CanUseLootAdmin() then RollMod:GiveToDEBank(data) end; pcall(function() D:Close() end) end)
                D:AddLine("text", L and L["Give to Player"] or "Give to Member",
                  "func", function()
                    if CanUseLootAdmin() then
                      if GetNumRaidMembers() > 0 then
                        local members = {}
                        for ii = 1, GetNumRaidMembers() do local nm = UnitName("raid"..ii) if nm then table.insert(members, StripRealm(nm)) end end
                        table.sort(members)
                        D:Open(UIParent, "children", function()
                          D:AddLine("text", L and L["Select Player"] or "Select Player", "isTitle", true)
                          for _,nm in ipairs(members) do D:AddLine("text", nm, "func", function() RollMod:GiveToPlayer(nm, data); pcall(function() D:Close() end) end) end
                        end)
                      else
                        StaticPopupDialogs["GUILDROLL_GIVE_PLAYER"] = {
                          text = L and L["Choose a raid member:"] or "Give to player:",
                          button1 = L and L["Confirm"] or "Confirm",
                          button2 = L and L["Cancel"] or "Cancel",
                          hasEditBox = true,
                          OnAccept = function() local name = this:GetParent().editBox:GetText(); RollMod:GiveToPlayer(name, data) end,
                          timeout = 0, whileDead = true, hideOnEscape = true
                        }
                        StaticPopup_Show("GUILDROLL_GIVE_PLAYER")
                      end
                    end
                    pcall(function() D:Close() end)
                  end)
              end
            )
          end)
        else
          StaticPopupDialogs["GUILDROLL_LOOT_MENU"] = {
            text = "Choose action for: ".. (data.itemLink or data.itemName or "item"),
            button1 = L and L["Start Rolls"] or "Start session",
            button2 = L and L["Give to Player"] or "Give to Member",
            OnAccept = function() if CanUseLootAdmin() then RollMod:StartSessionForItem(data) end end,
            OnCancel = function() if CanUseLootAdmin() then RollMod:GiveToPlayer(nil, data) end end,
            timeout = 0, whileDead = true, hideOnEscape = true
          }
          StaticPopup_Show("GUILDROLL_LOOT_MENU")
        end
      end)

      r:SetShown(true)
    end
    for i = num + 1, #self.rows do self.rows[i]:Hide() end
  end

  RollMod.frames.loot = f
  return f
end

-- Roll Table
local function CreateRollTable()
  if RollMod.frames.rollTable then return RollMod.frames.rollTable end
  local f = CreateFrame("Frame", "GuildRoll_RollTable", UIParent, "BasicFrameTemplate")
  f:SetSize(520, 420)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  f:Hide()

  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  f.title:SetPoint("TOP", 0, -6)
  f.title:SetText(L and L["RollWithEP - Loot Session"] or "Roll Session")

  f.closeRollsBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.closeRollsBtn:SetSize(120, 22); f.closeRollsBtn:SetPoint("TOPLEFT", 12, -30)
  f.closeRollsBtn:SetText(L and L["Close Rolls"] or "Close rolls")
  f.closeRollsBtn:SetScript("OnClick", function() RollMod:CloseSession() end)

  f.giveDEBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.giveDEBtn:SetSize(140,22); f.giveDEBtn:SetPoint("LEFT", f.closeRollsBtn, "RIGHT", 8, 0)
  f.giveDEBtn:SetText(L and L["Give to DE/Bank"] or "Give to DE/Bank")
  f.giveDEBtn:SetScript("OnClick", function() if RollMod.currentSession then RollMod:GiveToDEBank({ itemLink = RollMod.currentSession.itemLink }) end end)

  f.giveMemberBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.giveMemberBtn:SetSize(140,22); f.giveMemberBtn:SetPoint("LEFT", f.giveDEBtn, "RIGHT", 8, 0)
  f.giveMemberBtn:SetText(L and L["Give to Player"] or "Give to Member")
  f.giveMemberBtn:SetScript("OnClick", function()
    if RollMod.currentSession then
      if GetNumRaidMembers() > 0 and D then
        local members = {}
        for ii=1,GetNumRaidMembers() do local nm = UnitName("raid"..ii) if nm then table.insert(members, StripRealm(nm)) end end
        table.sort(members)
        D:Open(UIParent, "children", function()
          D:AddLine("text", L and L["Select Player"] or "Select Player", "isTitle", true)
          for _, nm in ipairs(members) do D:AddLine("text", nm, "func", function() RollMod:GiveToPlayer(nm, { itemLink = RollMod.currentSession.itemLink }); pcall(function() D:Close() end) end) end
        end)
      else
        StaticPopupDialogs["GUILDROLL_GIVE_PLAYER2"] = {
          text = L and L["Choose a raid member:"] or "Give to player:",
          button1 = L and L["Confirm"] or "Confirm",
          button2 = L and L["Cancel"] or "Cancel",
          hasEditBox = true,
          OnAccept = function() local name = this:GetParent().editBox:GetText(); RollMod:GiveToPlayer(name, { itemLink = RollMod.currentSession.itemLink }) end,
          timeout = 0, whileDead = true, hideOnEscape = true
        }
        StaticPopup_Show("GUILDROLL_GIVE_PLAYER2")
      end
    end
  end)

  f.askTieBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.askTieBtn:SetSize(120,22); f.askTieBtn:SetPoint("LEFT", f.giveMemberBtn, "RIGHT", 8, 0)
  f.askTieBtn:SetText(L and L["Ask Tie Roll"] or "Ask Tie Roll")
  f.askTieBtn:SetScript("OnClick", function() RollMod:AskTieRoll() end)

  local header = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  header:SetPoint("TOPLEFT", 12, -68)
  header:SetText((L and L["Player"] or "Player").."   "..(L and L["SR"] or "SR").."   "..(L and L["Type"] or "Type").."   "..(L and L["Roll"] or "Roll"))

  f.rows = {}
  local function createRow(i)
    local row = {}
    row.frame = CreateFrame("Frame", nil, f)
    row.frame:SetWidth(480); row.frame:SetHeight(18)
    row.frame:SetPoint("TOPLEFT", 12, -90 - ((i-1)*20))
    row.player = row.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.player:SetPoint("LEFT", 0, 0); row.player:SetWidth(180)
    row.sr = row.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.sr:SetPoint("LEFT", 190, 0); row.sr:SetWidth(50)
    row.type = row.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.type:SetPoint("LEFT", 260, 0); row.type:SetWidth(120)
    row.roll = row.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.roll:SetPoint("LEFT", 390, 0); row.roll:SetWidth(80)
    return row
  end

  f.UpdateRows = function(self)
    local rolls = RollMod.currentSession and RollMod.currentSession.rolls or {}
    for i = 1, 40 do
      if not self.rows[i] then self.rows[i] = createRow(i) end
      local r = self.rows[i]
      if rolls[i] then
        r.player:SetText(rolls[i].player)
        r.sr:SetText(rolls[i].sr and "YES" or "")
        r.type:SetText(rolls[i].type or "")
        r.roll:SetText(rolls[i].roll and tostring(rolls[i].roll) or "")
        r.frame:Show()
      else
        r.frame:Hide()
      end
    end
    if not self.winnerText then
      self.winnerText = self:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
      self.winnerText:SetPoint("BOTTOM", 0, 12)
    end
    local winner = (RollMod.currentSession and RollMod.currentSession.winner) or "-"
    self.winnerText:SetText((L and L["Winner"] or "Winner")..": "..winner)
  end

  RollMod.frames.rollTable = f
  return f
end

-- Helpers: find slot & candidate index to attempt GiveMasterLoot
local function FindSlotIndexForItem(itemLink, itemID)
  if RollMod.lootSlots then
    for _, it in ipairs(RollMod.lootSlots) do
      if it.itemLink and itemLink and it.itemLink == itemLink then return it.slot end
      if it.itemID and itemID and it.itemID == itemID then return it.slot end
    end
  end
  for i=1, GetNumLootItems() do
    local link = GetLootSlotLink(i)
    if link and itemLink and link == itemLink then return i end
  end
  return nil
end

local function GetCandidateIndexForPlayer(slotIndex, playerName)
  if not slotIndex or not playerName then return nil end
  playerName = StripRealm(playerName)
  if GetMasterLootCandidate then
    for i = 1, 40 do
      local name = GetMasterLootCandidate(slotIndex, i)
      if not name then break end
      if StripRealm(name) == playerName then return i end
    end
  end
  return nil
end

-- Start a roll session (pre-populate SR players)
function RollMod:StartSessionForItem(itemData)
  if not CanUseLootAdmin() then if GuildRoll and GuildRoll.defaultPrint then GuildRoll:defaultPrint(L and L["Only master looter or raid leader admin can use this feature."] or "No permission.") end return end
  local itemLink = itemData and (itemData.itemLink or itemData.itemName) or "Unknown"
  local itemID = itemData and itemData.itemID
  local itemName = nil
  if itemLink then itemName = string.match(itemLink, "%[(.-)%]") or itemData.itemName end

  local srlist = GetSRListForItem(itemID, itemName) or {}
  local session = {
    itemLink = itemLink,
    itemID = itemID,
    itemName = itemName,
    srlist = srlist,
    rolls = {},
    winner = nil,
    tieState = nil,
    closed = false,
    startTime = GetTime(),
    slotIndex = itemData and itemData.slot or nil
  }

  for _, player in ipairs(srlist) do
    local clean = StripRealm(player)
    table.insert(session.rolls, { player = clean, sr = true, type = "", roll = "" })
  end

  self.currentSession = session
  GuildRoll._RollForEP_currentLoot = session

  AnnounceToChannel(string.format(L and L["Start rolling for %s"] or "Start rolling for %s", itemLink))
  if GuildRoll and GuildRoll.VARS and GuildRoll.VARS.prefix then
    pcall(function() SendAddonMessage(GuildRoll.VARS.prefix, "ROLL_START:" .. (itemLink or "unknown"), GetNumRaidMembers()>0 and "RAID" or "PARTY") end)
  end

  local rt = CreateRollTable()
  rt:Show()
  rt:UpdateRows()
end

-- Core: process incoming roll (called after matching decl+system)
function RollMod:ProcessIncomingRoll(player, rollType, rollValue)
  if not self.currentSession then return end
  player = StripRealm(player)
  rollType = tostring(rollType or "SYS")
  local numericRoll = tonumber(rollValue) or rollValue

  local priority = PRIORITY_MAP[rollType] or PRIORITY_MAP.INVALID
  if rollType == "SYS" and tonumber(numericRoll) then priority = 2 end

  local isSRMember = false
  if self.currentSession and self.currentSession.srlist then isSRMember = HasSR(player, self.currentSession.srlist) end
  if rollType == "SR" or rollType == "CSR" then isSRMember = true end

  local found = nil
  for _, r in ipairs(self.currentSession.rolls) do if r.player == player then found = r; break end end
  if not found then
    found = { player = player, type = rollType, roll = numericRoll, priority = priority, sr = isSRMember }
    table.insert(self.currentSession.rolls, found)
  else
    found.type = rollType
    found.roll = numericRoll
    found.priority = priority
    found.sr = isSRMember
  end

  table.sort(self.currentSession.rolls, function(a,b)
    if (a.priority or -999) ~= (b.priority or -999) then return (a.priority or -999) > (b.priority or -999) end
    local ra = tonumber(a.roll) or -math.huge
    local rb = tonumber(b.roll) or -math.huge
    return ra > rb
  end)

  local top = self.currentSession.rolls[1]
  if not top then
    self.currentSession.winner = nil; self.currentSession.tieState = nil
  else
    local ties = {}
    for i, rr in ipairs(self.currentSession.rolls) do
      if rr.priority == top.priority and (tonumber(rr.roll) or rr.roll) == (tonumber(top.roll) or top.roll) then table.insert(ties, rr.player) else break end
    end
    if #ties == 1 then self.currentSession.winner = top.player; self.currentSession.tieState = nil
    else self.currentSession.winner = "Tie"; self.currentSession.tieState = { players = ties, itemLink = self.currentSession.itemLink, ts = GetTime() } end
  end

  if RollMod.frames.rollTable then RollMod.frames.rollTable:UpdateRows() end
end

-- Ask tie roll
function RollMod:AskTieRoll()
  if not CanUseLootAdmin() then return end
  if not self.currentSession or not self.currentSession.tieState then return end
  local tiedPlayers = self.currentSession.tieState.players
  local playerList = table.concat(tiedPlayers, ", ")
  local channel = GetNumRaidMembers() > 0 and "RAID" or "SAY"
  local message = string.format(L and L["Tie roll for %s - Roll now!"] or "Tie roll for %s - Roll now!", self.currentSession.itemLink) .. " (" .. playerList .. ")"
  SendChatMessage(message, channel)
  -- prepare for tie-break: clear previous numeric rolls, keep tieState for reference
  self.currentSession.rolls = {}
  self.currentSession.tieState = nil
  self.currentSession.winner = nil
  if RollMod.frames.rollTable then RollMod.frames.rollTable:UpdateRows() end
end

-- Close session
function RollMod:CloseSession()
  if not CanUseLootAdmin() then return end
  if not self.currentSession then if GuildRoll and GuildRoll.defaultPrint then GuildRoll:defaultPrint(L and L["No active loot session."] or "No active loot session.") end return end
  self.currentSession.closed = true
  local channel = GetNumRaidMembers() > 0 and "RAID" or "SAY"
  if self.currentSession.winner and self.currentSession.winner ~= "Tie" then
    local message = string.format(L and L["Winner: %s"] or "Winner: %s", self.currentSession.winner) .. " - " .. (self.currentSession.itemLink or "")
    SendChatMessage(message, channel)
  end
  if GuildRoll and GuildRoll.defaultPrint then GuildRoll:defaultPrint(L and L["Roll session closed."] or "Roll session closed.") end
  self.currentSession = nil
  GuildRoll._RollForEP_currentLoot = nil
  if RollMod.frames.rollTable then RollMod.frames.rollTable:Hide() end
end

-- Give to winner (attempt GiveMasterLoot if ML)
function RollMod:GiveToWinner()
  if not CanUseLootAdmin() then return end
  if not self.currentSession or not self.currentSession.winner or self.currentSession.winner == "Tie" then return end
  local winner = self.currentSession.winner
  local itemLink = self.currentSession.itemLink

  StaticPopupDialogs["ROLLWITHEP_CONFIRM_GIVE"] = {
    text = string.format(L and L["Confirm award %s to %s?"] or "Confirm award %s to %s?", itemLink, winner),
    button1 = L and L["Confirm"] or "Confirm",
    button2 = L and L["Cancel"] or "Cancel",
    OnAccept = function()
      local ch = GetNumRaidMembers()>0 and "RAID" or "SAY"
      SendChatMessage(string.format(L and L["%s receives %s"] or "%s receives %s", winner, itemLink), ch)
      local isML = IsMasterLooter()
      local slot = self.currentSession.slotIndex or FindSlotIndexForItem(itemLink, self.currentSession.itemID)
      if isML and slot then
        local candIdx = GetCandidateIndexForPlayer(slot, winner)
        if candIdx then
          pcall(function() GiveMasterLoot(slot, candIdx) end)
          if GuildRoll and GuildRoll.defaultPrint then GuildRoll:defaultPrint(L and L["Award confirmed"] or "Award confirmed") end
        else
          if GuildRoll and GuildRoll.defaultPrint then GuildRoll:defaultPrint(string.format(L and L["Item given to: %s"] or "Item given to: %s", winner)) end
        end
      else
        if GuildRoll and GuildRoll.defaultPrint then GuildRoll:defaultPrint(string.format(L and L["Item given to: %s"] or "Item given to: %s", winner)) end
      end
      self.currentSession = nil
      GuildRoll._RollForEP_currentLoot = nil
      if RollMod.frames.rollTable then RollMod.frames.rollTable:Hide() end
    end,
    OnCancel = function() if GuildRoll and GuildRoll.defaultPrint then GuildRoll:defaultPrint(L and L["Award cancelled"] or "Award cancelled") end end,
    timeout = 0, whileDead = true, hideOnEscape = true
  }
  StaticPopup_Show("ROLLWITHEP_CONFIRM_GIVE")
end

function RollMod:GiveToPlayer(playerName, itemData)
  if not CanUseLootAdmin() then if GuildRoll and GuildRoll.defaultPrint then GuildRoll:defaultPrint(L and L["Only master looter or raid leader admin can use this feature."] or "No permission.") end return end
  playerName = playerName and StripRealm(playerName) or "Unknown"
  local item = itemData and (itemData.itemLink or itemData.itemName) or (self.currentSession and self.currentSession.itemLink) or "Unknown"
  StaticPopupDialogs["ROLLWITHEP_CONFIRM_GIVE_PLAYER"] = {
    text = string.format(L and L["Confirm award %s to %s?"] or "Confirm award %s to %s?", item, playerName),
    button1 = L and L["Confirm"] or "Confirm",
    button2 = L and L["Cancel"] or "Cancel",
    OnAccept = function()
      local ch = GetNumRaidMembers()>0 and "RAID" or "SAY"
      SendChatMessage(string.format(L and L["%s receives %s"] or "%s receives %s", playerName, item), ch)
      local isML = IsMasterLooter()
      local slot = itemData and itemData.slot or (self.currentSession and self.currentSession.slotIndex) or FindSlotIndexForItem(item, self.currentSession and self.currentSession.itemID)
      if isML and slot then
        local candIdx = GetCandidateIndexForPlayer(slot, playerName)
        if candIdx then pcall(function() GiveMasterLoot(slot, candIdx) end) end
      end
      if RollMod.frames.loot then RollMod.frames.loot:Hide() end
      if RollMod.frames.rollTable then RollMod.frames.rollTable:Hide() end
      self.currentSession = nil
      GuildRoll._RollForEP_currentLoot = nil
      if GuildRoll and GuildRoll.defaultPrint then GuildRoll:defaultPrint(string.format(L and L["Item given to: %s"] or "Item given to: %s", playerName)) end
    end,
    OnCancel = function() if GuildRoll and GuildRoll.defaultPrint then GuildRoll:defaultPrint(L and L["Award cancelled"] or "Award cancelled") end end,
    timeout = 0, whileDead = true, hideOnEscape = true
  }
  StaticPopup_Show("ROLLWITHEP_CONFIRM_GIVE_PLAYER")
end

-- Bidirectional matcher: declarations (chat) <-> system numeric lines
local DECLARE_TTL = 5         -- seconds to wait for matching counterpart
local CLEANUP_INTERVAL = 1.0  -- on-update cleanup interval

local function now() return GetTime() end

local function dbg(...)
  if RollMod._debug_matcher then DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[GUILDROLL match]|r "..strjoin(" ", tostringall(...))) end
end

local function store_player_declaration(player, dtype, ep, rangeMin, rangeMax)
  if not player or not dtype then return end
  player = StripRealm(player)
  RollMod._decl_buffer[player] = { type = dtype, ep = ep, rangeMin = rangeMin, rangeMax = rangeMax, ts = now() }
  dbg("decl stored", player, dtype, ep, rangeMin, rangeMax)
  -- try match with existing system entry
  local sys = RollMod._sys_buffer[player]
  if sys and (now() - sys.ts) <= DECLARE_TTL then
    dbg("immediate match (sys existed) for", player, dtype, sys.roll)
    pcall(function() RollMod:ProcessIncomingRoll(player, dtype, sys.roll) end)
    RollMod._decl_buffer[player] = nil
    RollMod._sys_buffer[player] = nil
    return
  end
end

local function store_system_roll(player, numericRoll, rangeMin, rangeMax)
  if not player or not numericRoll then return end
  player = StripRealm(player)
  RollMod._sys_buffer[player] = { roll = numericRoll, rangeMin = rangeMin, rangeMax = rangeMax, ts = now() }
  dbg("sys stored", player, numericRoll, rangeMin, rangeMax)
  -- try match with existing declaration
  local decl = RollMod._decl_buffer[player]
  if decl and (now() - decl.ts) <= DECLARE_TTL then
    dbg("immediate match (decl existed) for", player, decl.type, numericRoll)
    pcall(function() RollMod:ProcessIncomingRoll(player, decl.type, numericRoll) end)
    RollMod._decl_buffer[player] = nil
    RollMod._sys_buffer[player] = nil
    return
  end
end

-- Cleanup frame to process TTL expirations and fallbacks
if not RollMod._cleanup_frame then
  local cf = CreateFrame("Frame")
  RollMod._cleanup_frame = cf
  local last = 0
  cf:SetScript("OnUpdate", function(self, elapsed)
    last = last + (elapsed or 0)
    if last < CLEANUP_INTERVAL then return end
    last = 0
    local t = now()
    -- process expired system entries -> fallback to SYS if no declaration matched
    for player, sys in pairs(RollMod._sys_buffer) do
      if t - sys.ts > DECLARE_TTL then
        dbg("sys expired, processing as SYS for", player, sys.roll)
        pcall(function() RollMod:ProcessIncomingRoll(player, "SYS", sys.roll) end)
        RollMod._sys_buffer[player] = nil
        RollMod._decl_buffer[player] = nil
      end
    end
    -- purge stale declarations older than TTL (no numeric arrived)
    for player, decl in pairs(RollMod._decl_buffer) do
      if t - decl.ts > DECLARE_TTL then
        dbg("decl expired (no sys) for", player, decl.type)
        -- drop the declaration silently (we rely on SYS fallback)
        RollMod._decl_buffer[player] = nil
      end
    end
  end)
end

-- Parsing chat "I rolled ..." style messages (returns type, ep, rangeMin, rangeMax)
local function parse_chat_rolled_line(msg)
  if not msg then return nil end
  -- Cumulative SR -> CSR
  local minv, maxv, ep = string.match(msg, "Cumulative%s+SR%s*(%d+)%s*%-%s*(%d+)%s*with%s*(%d+)")
  if minv and maxv then return "CSR", tonumber(ep), tonumber(minv), tonumber(maxv) end
  -- SR quoted range
  local minv2, maxv2, ep2 = string.match(msg, 'I rolled%s+SR%s*"?%s*(%d+)%s*%-%s*(%d+)%s*"?%s*with%s*(%d+)')
  if minv2 and maxv2 then return "SR", tonumber(ep2), tonumber(minv2), tonumber(maxv2) end
  -- MS quoted range -> map to EP
  local minv3, maxv3, ep3 = string.match(msg, 'I rolled%s+MS%s*"?%s*(%d+)%s*%-%s*(%d+)%s*"?%s*with%s*(%d+)')
  if minv3 and maxv3 then return "EP", tonumber(ep3), tonumber(minv3), tonumber(maxv3) end
  -- generic pattern with type and EP
  local typ4, minv4, maxv4, ep4 = string.match(msg, 'I rolled%s+([A-Za-z]+)%s*"?%s*(%d+)%s*%-%s*(%d+)%s*"?%s*with%s*(%d+)')
  if typ4 and maxv4 then
    local t = string.upper(typ4)
    if t == "MS" then t = "EP" end
    return t, tonumber(ep4), tonumber(minv4), tonumber(maxv4)
  end
  -- simple "I rolled 65" fallback
  local simple = string.match(msg, "^I rolled%s+(%d+)")
  if simple then return "SYS", tonumber(simple), nil, nil end
  -- fallback: find token and number
  local token = string.match(msg, "(CSR|SR|EP|MS)")
  local number = string.match(msg, "(%d+)")
  if token and number then
    local t = string.upper(token)
    if t == "MS" then t = "EP" end
    return t, tonumber(number), nil, nil
  end
  return nil
end

-- Parsing system "Player rolls N (min-max)" (returns player, numericRoll, rangeMin, rangeMax)
local function parse_system_roll_line(msg)
  if not msg then return nil end
  -- name can contain spaces; capture minimally up to ' rolls '
  local name, roll, minv, maxv = string.match(msg, "^(.-)%s+rolls%s+(%d+)%s*%(%s*(%d+)%s*%-%s*(%d+)%s*%)")
  if not name then
    name, roll, minv, maxv = string.match(msg, "^(%S+)%s+rolls%s+(%d+)%s*%(%s*(%d+)%s*%-%s*(%d+)%s*%)")
  end
  if name and roll then
    return StripRealm(name), tonumber(roll), tonumber(minv), tonumber(maxv)
  end
  return nil
end

-- Main incoming handler for chat/system events
local function OnIncomingRollMessage(event, msg, sender, ...)
  if not msg then return end
  -- Only ML/admin processes roll details
  if not CanUseLootAdmin() then return end

  -- System line handling
  if event == "CHAT_MSG_SYSTEM" or string.find(msg or "", " rolls ") then
    local pname, numericRoll, minv, maxv = parse_system_roll_line(msg)
    if pname and numericRoll then
      store_system_roll(pname, numericRoll, minv, maxv)
    end
    return
  end

  -- Chat "I rolled ..." handling (sender present)
  local parsedType, parsedEP, rmin, rmax = parse_chat_rolled_line(msg)
  if parsedType then
    local player = StripRealm(sender)
    store_player_declaration(player, parsedType, parsedEP, rmin, rmax)
    return
  end
end

-- Register chat/system handlers
local function register_roll_parsers()
  if GuildRoll and GuildRoll.RegisterEvent then
    pcall(function()
      GuildRoll:RegisterEvent("CHAT_MSG_RAID", function(self, msg, sender, ...) OnIncomingRollMessage("CHAT_MSG_RAID", msg, sender, ...) end)
      GuildRoll:RegisterEvent("CHAT_MSG_RAID_LEADER", function(self, msg, sender, ...) OnIncomingRollMessage("CHAT_MSG_RAID_LEADER", msg, sender, ...) end)
      GuildRoll:RegisterEvent("CHAT_MSG_PARTY", function(self, msg, sender, ...) OnIncomingRollMessage("CHAT_MSG_PARTY", msg, sender, ...) end)
      GuildRoll:RegisterEvent("CHAT_MSG_SAY", function(self, msg, sender, ...) OnIncomingRollMessage("CHAT_MSG_SAY", msg, sender, ...) end)
      GuildRoll:RegisterEvent("CHAT_MSG_SYSTEM", function(self, msg, ...) OnIncomingRollMessage("CHAT_MSG_SYSTEM", msg, nil, ...) end)
    end)
  else
    local f = RollMod._cleanup_frame or CreateFrame("Frame")
    RollMod._cleanup_frame = f
    f:RegisterEvent("CHAT_MSG_RAID")
    f:RegisterEvent("CHAT_MSG_RAID_LEADER")
    f:RegisterEvent("CHAT_MSG_PARTY")
    f:RegisterEvent("CHAT_MSG_SAY")
    f:RegisterEvent("CHAT_MSG_SYSTEM")
    f:SetScript("OnEvent", function(_, event, ...)
      local arg1, arg2 = ...
      OnIncomingRollMessage(event, arg1, arg2, ...)
    end)
  end
end

pcall(register_roll_parsers)

-- OnAddonMessage legacy handler (kept for compatibility)
local function OnAddonMessage(prefix, message, channel, sender)
  if not prefix or not message or not sender then return end
  if not (GuildRoll and GuildRoll.VARS and GuildRoll.VARS.prefix) then return end
  if prefix ~= GuildRoll.VARS.prefix then return end
  sender = StripRealm(sender)

  if string.sub(message,1,5) == "ROLL:" then
    local payload = string.sub(message,6)
    local typ, val = string.match(payload, "^([^:]+):(.+)$")
    if typ and val then RollMod:ProcessIncomingRoll(sender, typ, tonumber(val) or val)
    else RollMod:ProcessIncomingRoll(sender, "SYS", tonumber(payload) or payload) end

  elseif string.sub(message,1,11) == "ROLL_START:" then
    local item = string.sub(message,12)
    if GuildRoll and GuildRoll.defaultPrint then GuildRoll:defaultPrint("Roll started for "..tostring(item)) end

  elseif string.sub(message,1,8) == "GIVE_REQ:" then
    local payload = string.sub(message,9)
    local winner, item = string.match(payload, "^([^:]+):(.+)$")
    if winner and item then
      local isML = IsMasterLooter()
      if not isML then return end
      StaticPopupDialogs["ROLLWITHEP_GIVE_REQ"] = {
        text = string.format("Admin %s requests to give %s to %s. Confirm?", sender, item, winner),
        button1 = L and L["Confirm"] or "Confirm",
        button2 = L and L["Cancel"] or "Cancel",
        OnAccept = function()
          if GuildRoll and GuildRoll.VARS and GuildRoll.VARS.prefix then pcall(function() SendAddonMessage(GuildRoll.VARS.prefix, "GIVE_CONF:" .. winner .. ":" .. item, "WHISPER", sender) end) end
          local ch = GetNumRaidMembers()>0 and "RAID" or "SAY"
          SendChatMessage(string.format(L and L["%s receives %s"] or "%s receives %s", winner, item), ch)
        end,
        OnCancel = function()
          if GuildRoll and GuildRoll.VARS and GuildRoll.VARS.prefix then pcall(function() SendAddonMessage(GuildRoll.VARS.prefix, "GIVE_CANC:" .. winner .. ":" .. item, "WHISPER", sender) end) end
        end,
        timeout = 0, whileDead = true, hideOnEscape = true
      }
      StaticPopup_Show("ROLLWITHEP_GIVE_REQ")
    end
  end
end

-- Event registration for CHAT_MSG_ADDON (legacy)
local eventFrame2 = CreateFrame("Frame")
eventFrame2:RegisterEvent("CHAT_MSG_ADDON")
eventFrame2:SetScript("OnEvent", function(self, event, ...)
  local prefix, msg, channel, sender = ...
  OnAddonMessage(prefix, msg, channel, sender)
end)

-- Show loot UI (integration point)
function RollMod:ShowLootUI(lootItems)
  if GuildRoll_rollForEPCache._settings.useCustomLootFrame == false then return end
  if not lootItems or #lootItems == 0 then
    lootItems = {}
    local n = GetNumLootItems()
    for i=1,n do
      local name, texture, quantity, quality, locked, isQuestItem, questId, isActive = GetLootSlotInfo(i)
      local link = GetLootSlotLink(i)
      local id
      if link then
        local s = string.find(link, "item:")
        if s then
          local idstr = ""
          for j = s+5, string.len(link) do
            local ch = string.sub(link, j, j)
            if ch >= "0" and ch <= "9" then idstr = idstr .. ch else break end
          end
          if idstr ~= "" then id = tonumber(idstr) end
        end
      end
      table.insert(lootItems, { slot = i, itemLink = link, itemID = id, itemName = name, rarity = quality, texture = texture })
    end
  end
  if not lootItems or #lootItems == 0 then return end
  self.lootSlots = lootItems
  local f = CreateLootFrame()
  f:Update()
  f:Show()
  for _, it in ipairs(lootItems) do pcall(function() if it.itemLink then SendChatMessage(it.itemLink, GetNumRaidMembers()>0 and "RAID" or "PARTY") end end) end
end

-- Backwards-compatible wrappers & exposure
function RollWithEP_ImportCSV_wrapper(text) pcall(function() RollWithEP_ImportCSV(text) end) end
function RollWithEP_SetDEBank(player) if player == nil then GuildRoll_rollForEPCache.DEPlayer = nil; if GuildRoll and GuildRoll.defaultPrint then GuildRoll:defaultPrint(L and L["DE/Bank player cleared."] or "DE/Bank cleared.") end else GuildRoll_rollForEPCache.DEPlayer = StripRealm(player); if GuildRoll and GuildRoll.defaultPrint then GuildRoll:defaultPrint(string.format(L and L["DE/Bank player set to: %s"] or "DE/Bank player set to: %s", GuildRoll_rollForEPCache.DEPlayer)) end end end

GuildRoll.RollWithEP_ShowLootUI = function(lootItems) pcall(function() RollMod:ShowLootUI(lootItems) end) end
GuildRoll.RollWithEP_ImportCSV = function(text) pcall(function() RollWithEP_ImportCSV(text) end) end
GuildRoll.RollWithEP_SetDEBank = function(player) pcall(function() RollWithEP_SetDEBank(player) end) end

GuildRoll.RollForEP_StartRollForItem = function(itemLink) pcall(function() RollMod:StartSessionForItem({ itemLink = itemLink, itemName = itemLink }) end) end
GuildRoll.RollForEP_SetDE = function() pcall(function() if RollMod.currentSession then RollMod:GiveToDEBank({ itemLink = RollMod.currentSession.itemLink }) end end) end
GuildRoll.RollForEP_GiveToPlayer = function(playerName) pcall(function() if RollMod.currentSession then RollMod:GiveToPlayer(playerName, { itemLink = RollMod.currentSession.itemLink }) end end) end

GuildRoll.RollWithEP = RollMod

-- End of RollWithEP.lua
