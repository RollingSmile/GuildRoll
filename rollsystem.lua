-- rollsystem.lua
-- Module for handling mob drops, roll sessions and loot assignment in raids (LootAdmin)
-- English comments and strings.
-- Compatibility: avoid '#' and '...'; added API compatibility wrappers and /grforce command.
-- Defensive checks added to avoid "attempt to index a string value" errors.

local RollSystem = {}
RollSystem.frame = CreateFrame("Frame", "GuildRoll_RollSystemFrame")
RollSystem.db = {
    softReserves = {},
    activeSession = nil,
    deBank = nil,
}
-- Feature flags
RollSystem._forceLootAdmin = false -- can be toggled with /grforce

-- Config
local MATCH_WINDOW = 6
local MAX_QUEUE_PER_PLAYER = 8
local CLEANUP_INTERVAL = 10
local ANNOUNCE_MIN_QUALITY = 2 -- announce items with quality >= this (2 = uncommon/green)

-- Buffers
RollSystem.announcements = {}
RollSystem.systemRolls = {}

-- Hooking state
RollSystem.hookedButtons = {}
RollSystem.buttonsHooked = false
RollSystem.masterLootFrame = nil

-- Roll type mapping & priorities
local ROLL_TYPE_MAP = {
    CSR = { type="SR", priority=4 }, SR  = { type="SR", priority=4 }, ["101"] = { type="SR", priority=4 },
    EP  = { type="MS", priority=3 }, ["100"] = { type="MS", priority=3 }, MS = { type="MS", priority=3},
    ["99"] = { type="OS", priority=2 }, ["98"] = { type="Tmog", priority=1 },
}
local TYPE_PRIORITY = { SR=4, MS=3, OS=2, Tmog=1 }

-- Compatibility wrappers (some private servers / environments may lack certain globals)
local function IsInRaidCompat()
    if type(IsInRaid) == "function" then return IsInRaid() end
    if type(UnitInRaid) == "function" then return UnitInRaid("player") or false end
    if type(GetNumRaidMembers) == "function" then return (GetNumRaidMembers() or 0) > 0 end
    if type(GetNumGroupMembers) == "function" then return (GetNumGroupMembers() or 0) > 5 end
    return false
end

local function IsInGuildCompat()
    if type(IsInGuild) == "function" then return IsInGuild() end
    if type(GetGuildInfo) == "function" then
        local n = GetGuildInfo("player")
        return n and n ~= ""
    end
    return false
end

local function UnitNameCompat(unit)
    if not unit then
        if type(UnitName) == "function" then return UnitName("player") end
        return nil
    end
    if type(UnitName) == "function" then return UnitName(unit) end
    return nil
end

local function UnitIsGroupLeaderCompat(unit)
    if type(UnitIsGroupLeader) == "function" then return UnitIsGroupLeader(unit) end
    return false
end

local function GetRaidRosterNameCompat(index)
    if type(GetRaidRosterInfo) == "function" then
        return GetRaidRosterInfo(index)
    end
    return nil
end

local function GetNumGroupMembersCompat()
    if type(GetNumGroupMembers) == "function" then return GetNumGroupMembers() end
    if type(GetNumRaidMembers) == "function" then return GetNumRaidMembers() end
    return 0
end

-- safe_getn: avoid '#' operator for compatibility
local function safe_getn(t)
    if not t then return 0 end
    if table.getn then return table.getn(t) end
    local count = 0
    for _ in ipairs(t) do count = count + 1 end
    return count
end

-- Utilities
local function pushQueue(tbl, entry, maxSize)
    if not tbl then tbl = {} end
    table.insert(tbl, 1, entry)
    while safe_getn(tbl) > (maxSize or 10) do table.remove(tbl) end
    return tbl
end

local function inferTypeFromRange(minv, maxv)
    if not minv or not maxv then return "SR" end
    minv = tonumber(minv); maxv = tonumber(maxv)
    if minv == 1 and maxv == 101 then return "101" end
    if minv == 1 and maxv == 100 then return "100" end
    if minv == 1 and maxv == 99 then return "99" end
    if minv == 1 and maxv == 98 then return "98" end
    if minv > 100 then return "CSR" end
    return "SR"
end

local function parseEPFromText(msg)
    if not msg then return nil end
    local ep = msg:match("[Ww]ith%s*(%d+)%s*[Ee][Pp]") or msg:match("(%d+)%s*[Ee][Pp]")
    if ep then return tonumber(ep) end
    return nil
end

-- Officer note parsing
function RollSystem:GetOfficerNoteEP(playerName)
    if not IsInGuildCompat() then return nil end
    if type(GuildRoster) == "function" then pcall(GuildRoster) end
    local num = (type(GetNumGuildMembers) == "function") and GetNumGuildMembers() or 0
    for i=1, num do
        if type(GetGuildRosterInfo) == "function" then
            local name, _, _, _, _, _, _, officernote = GetGuildRosterInfo(i)
            if name then
                local short = Ambiguate(name, "none")
                if short == playerName then
                    if officernote and officernote ~= "" then
                        local brace = officernote:match("%{%s*(%d+)%s*%}")
                        if brace then return tonumber(brace) end
                        local ep = officernote:match("[Ee][Pp]%s*[:%-]?%s*(%d+)")
                        if ep then return tonumber(ep) end
                        local any = officernote:match("(%d+)")
                        if any then return tonumber(any) end
                    end
                    return nil
                end
            end
        end
    end
    return nil
end

local function validateEP(playerName, epDeclared)
    if not epDeclared then return true, nil end
    local epOfficer = RollSystem:GetOfficerNoteEP(playerName)
    if not epOfficer then return true, nil end
    if tonumber(epDeclared) == tonumber(epOfficer) then
        return true, epOfficer
    else
        return false, epOfficer
    end
end

-- Add roll to session
function RollSystem:AddRoll(playerName, typeCode, value, epDeclared, epVerified)
    local session = self.db.activeSession
    if not session or session.closed then return end
    local map = ROLL_TYPE_MAP[typeCode] or { type=typeCode, priority=1 }
    local entry = {
        player = playerName,
        type = map.type,
        typeCode = typeCode,
        priority = map.priority or TYPE_PRIORITY[map.type] or 1,
        value = tonumber(value) or 0,
        epDeclared = epDeclared,
        epOfficer = epVerified,
        suspicious = (epDeclared ~= nil and epVerified ~= nil and tonumber(epDeclared) ~= tonumber(epVerified))
    }
    table.insert(session.rolls, entry)
    if self.rollFrame then self:RefreshRollTable() end
end

-- Matching announcements <-> system rolls
function RollSystem:TryMatchForPlayer(player)
    local annQ = self.announcements[player]
    local sysQ = self.systemRolls[player]
    if not annQ or not sysQ then return end

    local i = safe_getn(sysQ)
    while i >= 1 do
        local sys = sysQ[i]
        local bestAnnIdx, bestAnn, bestDt
        for j = 1, safe_getn(annQ) do
            local ann = annQ[j]
            if ann.min and ann.max and sys.min and sys.max and tonumber(ann.min) == tonumber(sys.min) and tonumber(ann.max) == tonumber(sys.max) then
                local dt = math.abs((sys.ts or 0) - (ann.ts or 0))
                if not bestDt or dt < bestDt then bestDt = dt; bestAnn = ann; bestAnnIdx = j end
            end
        end
        if not bestAnn then
            for j = 1, safe_getn(annQ) do
                local ann = annQ[j]
                local dt = math.abs((sys.ts or 0) - (ann.ts or 0))
                if dt <= MATCH_WINDOW then
                    if not bestDt or dt < bestDt then bestDt = dt; bestAnn = ann; bestAnnIdx = j end
                end
            end
        end

        if bestAnn then
            local chosenType = bestAnn.typeCode or inferTypeFromRange(sys.min, sys.max)
            local epDeclared = bestAnn.epDeclared
            local valid, epOfficer = validateEP(player, epDeclared)
            self:AddRoll(player, chosenType, sys.value, epDeclared, epOfficer)
            table.remove(sysQ, i)
            table.remove(annQ, bestAnnIdx)
        else
            i = i - 1
        end
    end

    if annQ and safe_getn(annQ) == 0 then self.announcements[player] = nil end
    if sysQ and safe_getn(sysQ) == 0 then self.systemRolls[player] = nil end
end

-- Cleanup old entries
local lastCleanup = 0
local function cleanupOld()
    local now = GetTime()
    if now - lastCleanup < CLEANUP_INTERVAL then return end
    lastCleanup = now
    for player, q in pairs(RollSystem.announcements) do
        local newq = {}
        for _, v in ipairs(q) do if now - (v.ts or 0) <= (MATCH_WINDOW*3) then table.insert(newq, v) end end
        if safe_getn(newq) == 0 then RollSystem.announcements[player] = nil else RollSystem.announcements[player] = newq end
    end
    for player, q in pairs(RollSystem.systemRolls) do
        local newq = {}
        for _, v in ipairs(q) do if now - (v.ts or 0) <= (MATCH_WINDOW*3) then table.insert(newq, v) end end
        if safe_getn(newq) == 0 then RollSystem.systemRolls[player] = nil else RollSystem.systemRolls[player] = newq end
    end
end

-- Store announcement
function RollSystem:StoreAnnouncement(player, msg, chan)
    local ts = GetTime()
    local minv, maxv = msg:match("(%d+)%s*[%-%–]%s*(%d+)")
    local ep = parseEPFromText(msg)
    local detected = nil
    if msg:match("[Cc]umulative%s+[Ss][Rr]") or msg:match("[Cc][Ss][Rr]") then detected = "CSR"
    elseif msg:match("[Ss][Rr]") and not msg:match("[Mm][Ss]") then detected = "SR"
    elseif msg:match("[Mm][Ss]") and not msg:match("[Ss][Rr]") then detected = "MS" end

    local entry = { typeCode = detected, min = minv and tonumber(minv) or nil, max = maxv and tonumber(maxv) or nil, epDeclared = ep, ts = ts, raw = msg, chan = chan }
    self.announcements[player] = pushQueue(self.announcements[player], entry, MAX_QUEUE_PER_PLAYER)
    self:TryMatchForPlayer(player)
end

-- Store system roll
function RollSystem:StoreSystemRoll(player, value, minv, maxv, raw)
    local ts = GetTime()
    local entry = { value = tonumber(value), min = tonumber(minv), max = tonumber(maxv), ts = ts, raw = raw }
    self.systemRolls[player] = pushQueue(self.systemRolls[player], entry, MAX_QUEUE_PER_PLAYER)
    self:TryMatchForPlayer(player)
end

-- CSV parsing
local function parseCSVLine(line)
    local res = {}
    local i = 1
    local len = string.len(line)
    while i <= len do
        if line:sub(i,i) == '"' then
            local j = i+1
            local field = ""
            while j <= len do
                local c = line:sub(j,j)
                if c == '"' and line:sub(j+1,j+1) == '"' then
                    field = field .. '"'
                    j = j + 2
                elseif c == '"' then
                    break
                else
                    field = field .. c
                    j = j + 1
                end
            end
            table.insert(res, field)
            i = j + 2
        else
            local j = line:find(",", i) or (len+1)
            local field = line:sub(i, j-1)
            table.insert(res, field)
            i = j + 1
        end
    end
    return res
end

function RollSystem.ImportSoftReservesFromText(csvText)
    RollSystem.db.softReserves = {}
    for line in csvText:gmatch("[^\r\n]+") do
        if line:match("%S") then
            local fields = parseCSVLine(line)
            local id = fields[1] and tonumber(fields[1])
            local item = fields[2] or ""
            local attendee = fields[3] or ""
            local comment = fields[4] or ""
            local srplus = fields[5] or ""
            local key = tostring(id or item)
            RollSystem.db.softReserves[key] = RollSystem.db.softReserves[key] or {}
            table.insert(RollSystem.db.softReserves[key], { attendee=attendee, comment=comment, srplus=srplus, item=item, id=id })
        end
    end
    print("GuildRoll: SoftReserves imported.")
end

function RollSystem.GetSoftReservesForItem(itemID, itemName)
    local keyId = tostring(itemID)
    if RollSystem.db.softReserves[keyId] then return RollSystem.db.softReserves[keyId] end
    if itemName then
        local keyName = tostring(itemName)
        if RollSystem.db.softReserves[keyName] then return RollSystem.db.softReserves[keyName] end
    end
    return nil
end

-- DE/Bank
function RollSystem:SetDEBank(name)
    RollSystem.db.deBank = name
    print("GuildRoll: DE/Bank set to: "..tostring(name))
end
function RollSystem:GetDEBank()
    if RollSystem.db.deBank and RollSystem.db.deBank ~= "" then return RollSystem.db.deBank end
    return UnitNameCompat("player")
end

-- Admin checks
function RollSystem.IsPlayerAddonAdmin()
    if IsInGuildCompat() then return true end
    return false
end

-- IsLootAdmin: robust detection with force override (RollFor-style)
function RollSystem.IsLootAdmin()
    if RollSystem._forceLootAdmin then return true end

    if type(GetLootMethod) ~= "function" then return false end
    local lootMethod, masterUnit = GetLootMethod()
    if not lootMethod then return false end

    -- only handle master looter mode
    if lootMethod ~= "master" then return false end

    local playerName = UnitNameCompat("player")

    -- masterUnit may be nil or 0 on some servers -> treat raid leader as master
    if masterUnit == nil or masterUnit == 0 then
        if UnitIsGroupLeaderCompat("player") then return true end
    end

    if type(masterUnit) == "string" then
        local masterName = nil
        if masterUnit:match("^raid") or masterUnit:match("^party") or masterUnit == "player" then
            masterName = UnitNameCompat(masterUnit)
        else
            masterName = masterUnit
        end
        if masterName and masterName == playerName then return true end
    elseif type(masterUnit) == "number" then
        local index = masterUnit
        if index == 0 then
            if UnitIsGroupLeaderCompat("player") then return true end
        else
            local name = GetRaidRosterNameCompat(index)
            if name and Ambiguate(name, "none") == playerName then return true end
        end
    end

    if UnitIsGroupLeaderCompat("player") then return true end
    return false
end

-- Build loot items from APIs
local function BuildLootItemsFromGame()
    local items = {}
    local num = 0
    if GetNumLootItems then
        num = GetNumLootItems()
    elseif C_Loot and C_Loot.GetNumLootItems then
        num = C_Loot.GetNumLootItems()
    end
    for slot = 1, num do
        local itemLink = nil
        if GetLootSlotLink then itemLink = GetLootSlotLink(slot)
        elseif C_Loot and C_Loot.GetLootSlotLink then itemLink = C_Loot.GetLootSlotLink(slot) end
        local quality = nil
        if GetLootSlotInfo then
            local _, _, _, q = GetLootSlotInfo(slot)
            quality = q
        elseif C_Loot and C_Loot.GetLootSlotInfo then
            local info = { C_Loot.GetLootSlotInfo(slot) }
            quality = info[4]
        end
        table.insert(items, { slot = slot, itemLink = itemLink, itemID = nil, quality = quality })
    end
    return items
end

-- Announce loots (LOOT FOUND)
local function AnnounceLootFound(lootItems)
    if not lootItems or safe_getn(lootItems) == 0 then return end
    local sendChannel = IsInRaidCompat() and "RAID" or "SAY"
    SendChatMessage("LOOT FOUND:", sendChannel)
    for _, it in ipairs(lootItems) do
        if it.itemLink then
            local q = it.quality or 0
            if tonumber(q) and tonumber(q) >= ANNOUNCE_MIN_QUALITY then
                SendChatMessage(tostring(it.itemLink), sendChannel)
            end
        end
    end
end

-- Hide default loot frame (best-effort)
local function HideDefaultLootFrame()
    if InCombatLockdown and InCombatLockdown() then return end
    if HideUIPanel and _G.LootFrame and _G.LootFrame:IsShown() then
        pcall(HideUIPanel, _G.LootFrame)
    elseif _G.LootFrame and _G.LootFrame:IsShown() then
        pcall(_G.LootFrame.Hide, _G.LootFrame)
    end
end

-- Custom loot frame (anchored) creation
function RollSystem:OpenCustomLootFrame(lootItems, mobGUID)
    if not RollSystem.IsLootAdmin() then return end
    if not self.lootFrame then
        local f = CreateFrame("Frame", "GuildRoll_CustomLootFrame", UIParent, "BackdropTemplate")
        f:SetSize(360, 260)
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        f:SetBackdrop({ bgFile="Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", edgeSize=16 })
        f:Hide()
        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        f.title:SetPoint("TOP", 0, -8)
        f.title:SetText("GuildRoll Loot")
        f.items = {}
        local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -40)
        scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -30, 40)
        f.scroll = scroll
        local content = CreateFrame("Frame", nil, scroll)
        content:SetSize(320, 1)
        scroll:SetScrollChild(content)
        f.content = content
        self.lootFrame = f
    end

    local f = self.lootFrame
    local content = f.content
    for i,v in ipairs(f.items) do if v and v.Hide then v:Hide() end end
    f.items = {}

    for idx,item in ipairs(lootItems) do
        local btn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
        btn:SetSize(320, 32)
        btn:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(idx-1)*36)
        btn.itemLink = item.itemLink
        btn.slot = item.slot
        btn.itemID = item.itemID
        btn:SetText(item.itemLink or ("item "..tostring(item.itemID)))
        btn:SetNormalFontObject("GameFontNormalSmall")
        btn:Show()

        local sr = RollSystem.GetSoftReservesForItem(item.itemID, item.itemLink and tostring(item.itemLink))
        if sr and safe_getn(sr) > 0 then
            local txt = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            local names = {}
            for _,r in ipairs(sr) do table.insert(names, r.attendee) end
            txt:SetPoint("LEFT", btn, "RIGHT", 4, 0)
            txt:SetText("SR: "..table.concat(names, ", "))
            txt:SetJustifyH("LEFT")
            txt:SetWidth(320)
        end

        btn:SetScript("OnClick", function(selfButton, button)
            RollSystem:OnLootItemClicked(btn)
        end)
        table.insert(f.items, btn)
    end

    AnnounceLootFound(lootItems)
    f:Show()
end

-- Item click menu
function RollSystem:OnLootItemClicked(btn)
    if not btn then return end
    if not self._itemMenu then
        self._itemMenu = CreateFrame("Frame", "GuildRoll_ItemMenu", UIParent, "UIDropDownMenuTemplate")
    end

    local itemLink = btn.itemLink
    local slot = btn.slot
    local itemID = btn.itemID

    local dropdown = {
        { text = "Start Rolls", func = function() RollSystem:StartRollSession(itemLink, itemID, slot) end },
        { text = "Give to Member", func = function() RollSystem:OpenGiveToMemberDialog(itemLink, itemID, slot) end },
    }

    EasyMenu(dropdown, self._itemMenu, "cursor", 0 , 0, "MENU")
end

-- Start roll session
function RollSystem:StartRollSession(itemLink, itemID, slot)
    self.db.activeSession = {
        itemLink = itemLink,
        itemID = itemID,
        slot = slot,
        rolls = {},
        closed = false,
        winner = nil,
    }

    local announceText = "ROLL START: "..tostring(itemLink).." - Use your roll keys (CSR/SR/EP/101/100/99/98)"
    if IsInRaidCompat() then
        SendChatMessage(announceText, "RAID")
        pcall(SendChatMessage, announceText, "RAID_WARNING")
    else
        SendChatMessage(announceText, "SAY")
    end

    RollSystem:OpenRollTableFrame()
end

-- Roll table UI
function RollSystem:OpenRollTableFrame()
    local session = self.db.activeSession
    if not session then return end

    if not self.rollFrame then
        local f = CreateFrame("Frame", "GuildRoll_RollTable", UIParent, "BackdropTemplate")
        f:SetSize(560, 380)
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        f:SetBackdrop({ bgFile="Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", edgeSize=16 })
        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        f.title:SetPoint("TOP", 0, -8)
        f.title:SetText("Rolls")
        f.closeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        f.closeBtn:SetSize(120, 26)
        f.closeBtn:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -36)
        f.closeBtn:SetText("Close Rolls")
        f.closeBtn:SetScript("OnClick", function() RollSystem:CloseRolls() end)
        f.giveWinnerBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        f.giveWinnerBtn:SetSize(140, 26)
        f.giveWinnerBtn:SetPoint("LEFT", f.closeBtn, "RIGHT", 8, 0)
        f.giveWinnerBtn:SetText("Give to Winner")
        f.giveWinnerBtn:Disable()
        f.giveWinnerBtn:SetScript("OnClick", function() RollSystem:PromptGiveToWinner() end)
        f.giveMemberBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        f.giveMemberBtn:SetSize(140, 26)
        f.giveMemberBtn:SetPoint("LEFT", f.giveWinnerBtn, "RIGHT", 8, 0)
        f.giveMemberBtn:SetText("Give to Member")
        f.giveMemberBtn:Disable()
        f.giveMemberBtn:SetScript("OnClick", function()
            local session = RollSystem.db.activeSession
            if session then RollSystem:OpenGiveToMemberDialog(session.itemLink, session.itemID, session.slot) end
        end)

        local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -72)
        scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -30, 12)
        f.scroll = scroll
        local content = CreateFrame("Frame", nil, scroll)
        content:SetSize(510, 1)
        scroll:SetScrollChild(content)
        f.content = content
        f.rows = {}
        self.rollFrame = f
    end

    self.rollFrame.title:SetText("Rolls for: "..tostring(session.itemLink))
    self:RefreshRollTable()
    self.rollFrame:Show()
end

-- Refresh roll table
function RollSystem:RefreshRollTable()
    local session = self.db.activeSession
    if not session or not self.rollFrame then return end
    local content = self.rollFrame.content

    for i,row in ipairs(self.rollFrame.rows) do if row and row.Hide then row:Hide() end end
    self.rollFrame.rows = {}

    for idx,entry in ipairs(session.rolls) do
        local r = CreateFrame("Frame", nil, content)
        r:SetSize(510, 22)
        r:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(idx-1)*24)
        r.playerText = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.playerText:SetPoint("LEFT", r, "LEFT", 4, 0)
        r.playerText:SetText(entry.player)
        r.rollText = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.rollText:SetPoint("LEFT", r, "LEFT", 180, 0)
        r.rollText:SetText(entry.type)
        r.valueText = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.valueText:SetPoint("LEFT", r, "LEFT", 260, 0)
        r.valueText:SetText(tostring(entry.value))

        local epinfo = ""
        if entry.epDeclared then epinfo = epinfo .. "EP:"..tostring(entry.epDeclared) end
        if entry.epOfficer then epinfo = epinfo .. " (officer:"..tostring(entry.epOfficer)..")" end
        if epinfo ~= "" then
            r.epText = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            r.epText:SetPoint("LEFT", r, "LEFT", 340, 0)
            r.epText:SetText(epinfo)
        end

        if entry.suspicious then
            r.playerText:SetTextColor(1,0.2,0.2)
            r.rollText:SetText(r.rollText:GetText().." (EP mismatch)")
        end

        r:Show()
        table.insert(self.rollFrame.rows, r)
    end
end

-- Determine winner
function RollSystem:DetermineWinner()
    local session = self.db.activeSession
    if not session then return nil end
    if safe_getn(session.rolls) == 0 then return nil end
    table.sort(session.rolls, function(a,b)
        if a.priority ~= b.priority then return a.priority > b.priority
        elseif a.value ~= b.value then return a.value > b.value
        else return false end
    end)
    return session.rolls[1]
end

-- Close rolls
function RollSystem:CloseRolls()
    local session = self.db.activeSession
    if not session or session.closed then return end
    local winner = self:DetermineWinner()
    session.winner = winner
    session.closed = true

    local text
    if winner then
        text = "ROLLS CLOSED for "..tostring(session.itemLink)..". Winner: "..winner.player.." ("..(winner.type or "")..", "..tostring(winner.value)..")"
    else
        text = "ROLLS CLOSED for "..tostring(session.itemLink)..". No rolls."
    end

    if IsInRaidCompat() then
        SendChatMessage(text, "RAID")
        pcall(SendChatMessage, text, "RAID_WARNING")
    else
        SendChatMessage(text, "SAY")
    end

    if self.rollFrame then
        self.rollFrame.giveWinnerBtn:Enable()
        self.rollFrame.giveMemberBtn:Enable()
    end
end

local function StaticPopup_ShowConfirm(title, text, acceptFunc)
    StaticPopupDialogs["GUILDROLL_CONFIRM"] = StaticPopupDialogs["GUILDROLL_CONFIRM"] or {
        text = text or "",
        button1 = ACCEPT,
        button2 = CANCEL,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        OnAccept = function() if acceptFunc then pcall(acceptFunc) end end,
    }
    StaticPopup_Show("GUILDROLL_CONFIRM")
end

function RollSystem:PromptGiveToWinner()
    local session = self.db.activeSession
    if not session or not session.winner then print("No winner to give to.") return end
    local name = session.winner.player
    StaticPopup_ShowConfirm("Give to Winner", "Give "..tostring(session.itemLink).." to "..name.."?", function()
        RollSystem:GiveItemToPlayer(session.itemLink, session.itemID, name)
    end)
end

-- Give to Member dialog and functions (unchanged)...

-- Anchored candidate UI
local function EnsureMasterLootFrame()
    if RollSystem.masterLootFrame then return RollSystem.masterLootFrame end
    local container = CreateFrame("Frame", "GuildRoll_MasterLootFrame", UIParent, "BackdropTemplate")
    container:SetSize(220, 40)
    container:SetBackdrop({ bgFile="Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", edgeSize=16 })
    container:Hide()
    container.title = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    container.title:SetPoint("TOPLEFT", 8, -6)
    container.title:SetText("Assign item")
    container.candidateButtons = {}

    function container.create_candidate_frames(candidates)
        for i, b in ipairs(container.candidateButtons) do if b and b.Hide then b:Hide() end end
        container.candidateButtons = {}
        for idx, c in ipairs(candidates) do
            local btn = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
            btn:SetSize(200, 22)
            btn:SetPoint("TOPLEFT", container, "TOPLEFT", 10, -20 - (idx-1)*26)
            btn:SetText(c.name)
            btn:SetNormalFontObject("GameFontNormalSmall")
            btn:SetScript("OnClick", function()
                if container._onSelect then container._onSelect(c) end
            end)
            btn:Show()
            table.insert(container.candidateButtons, btn)
        end
        local height = 24 + (safe_getn(candidates) * 26)
        container:SetHeight(math.max(40, height))
    end

    function container.anchor(button)
        container:ClearAllPoints()
        container:SetPoint("TOPLEFT", button, "TOPRIGHT", 8, 0)
    end
    function container.show() container:Show() end
    function container.hide() container:Hide() end
    function container.set_onselect(fn) container._onSelect = fn end

    RollSystem.masterLootFrame = container
    return container
end

-- Candidate list builder
local function BuildCandidateList()
    local candidates = {}
    if IsInRaidCompat() then
        local num = GetNumGroupMembersCompat()
        for i=1, num do
            local name = GetRaidRosterNameCompat(i)
            if name and name ~= "" then table.insert(candidates, { name = Ambiguate(name, "none"), index = i }) end
        end
    else
        -- Also include party members and self as fallback (helps "raid of 1" cases)
        table.insert(candidates, { name = UnitNameCompat("player"), index = 0 })
        if type(GetNumGroupMembers) == "function" then
            for i=1, GetNumGroupMembers() do
                local unit = "party"..i
                if UnitExists(unit) then
                    local nm = UnitNameCompat(unit)
                    if nm and nm ~= "" then table.insert(candidates, { name = Ambiguate(nm, "none"), index = i }) end
                end
            end
        end
    end
    return candidates
end

-- Robust button discovery & hooking with defensive checks
local function find_and_hook_buttons(self)
    local hookedCount = 0
    local function safeHandleOriginalClick(orig, selfButton, button)
        if type(orig) == "function" then
            pcall(function() orig(selfButton, button) end)
        end
    end

    if _G.LootFrame then
        for _, child in ipairs({ _G.LootFrame:GetChildren() }) do
            if child and type(child.GetID) == "function" then
                local slot = nil
                -- try to get slot safely
                local ok, s = pcall(function() return child:GetID() end)
                if ok then slot = s end
                if slot and slot > 0 and not self.hookedButtons[child] then
                    local orig = child:GetScript("OnClick")
                    self.hookedButtons[child] = { originalOnClick = orig, slot = slot }
                    child:SetScript("OnClick", function(selfButton, button)
                        -- Defensive: ensure selfButton is a frame-like object
                        if type(selfButton) ~= "table" then
                            print("GuildRoll: unexpected button type on click:", type(selfButton))
                            safeHandleOriginalClick(orig, selfButton, button)
                            return
                        end

                        if not RollSystem.IsLootAdmin() then
                            safeHandleOriginalClick(orig, selfButton, button)
                            return
                        end

                        local candidates = BuildCandidateList()
                        if safe_getn(candidates) == 0 then
                            safeHandleOriginalClick(orig, selfButton, button)
                            return
                        end

                        local mlf = EnsureMasterLootFrame()
                        mlf.create_candidate_frames(candidates)
                        mlf.anchor(selfButton)
                        mlf.set_onselect(function(candidate)
                            -- get slot id robustly
                            local slotId = nil
                            if type(selfButton) == "table" then
                                local hb = self.hookedButtons[selfButton]
                                if hb and hb.slot then slotId = hb.slot end
                            end
                            if not slotId and type(selfButton.GetID) == "function" then
                                local ok2, idv = pcall(function() return selfButton:GetID() end)
                                if ok2 then slotId = idv end
                            end
                            if not slotId then
                                print("GuildRoll: Cannot determine slot id for GiveMasterLoot.")
                                mlf.hide()
                                return
                            end
                            StaticPopup_ShowConfirm("Confirm Give", "Give item in slot "..tostring(slotId).." to "..tostring(candidate.name).."?", function()
                                if type(GiveMasterLoot) == "function" then
                                    pcall(function() GiveMasterLoot(slotId, candidate.index) end)
                                    print("GuildRoll: Assigned slot "..tostring(slotId).." to "..tostring(candidate.name))
                                else
                                    print("GuildRoll: GiveMasterLoot not available; perform manual assignment.")
                                end
                                mlf.hide()
                            end)
                        end)
                        mlf.show()
                    end)
                    hookedCount = hookedCount + 1
                end
            end
        end
    end

    -- fallback: global LootButton1..N
    local maxGlobal = 20
    for i=1, maxGlobal do
        local name = "LootButton"..i
        local btn = _G[name]
        if btn and type(btn.GetID) == "function" then
            local ok, slot = pcall(function() return btn:GetID() end)
            slot = (ok and slot) or i
            if slot and not self.hookedButtons[btn] then
                local orig = btn:GetScript("OnClick")
                self.hookedButtons[btn] = { originalOnClick = orig, slot = slot }
                btn:SetScript("OnClick", function(selfButton, button)
                    if type(selfButton) ~= "table" then
                        print("GuildRoll: unexpected global button type on click:", type(selfButton))
                        safeHandleOriginalClick(orig, selfButton, button)
                        return
                    end

                    if not RollSystem.IsLootAdmin() then
                        safeHandleOriginalClick(orig, selfButton, button)
                        return
                    end

                    local candidates = BuildCandidateList()
                    if safe_getn(candidates) == 0 then
                        safeHandleOriginalClick(orig, selfButton, button)
                        return
                    end

                    local mlf = EnsureMasterLootFrame()
                    mlf.create_candidate_frames(candidates)
                    mlf.anchor(selfButton)
                    mlf.set_onselect(function(candidate)
                        local slotId = nil
                        if type(selfButton) == "table" then
                            local hb = self.hookedButtons[selfButton]
                            if hb and hb.slot then slotId = hb.slot end
                        end
                        if not slotId and type(selfButton.GetID) == "function" then
                            local ok2, idv = pcall(function() return selfButton:GetID() end)
                            if ok2 then slotId = idv end
                        end
                        if not slotId then
                            print("GuildRoll: Cannot determine slot id for GiveMasterLoot.")
                            mlf.hide()
                            return
                        end
                        StaticPopup_ShowConfirm("Confirm Give", "Give item in slot "..tostring(slotId).." to "..tostring(candidate.name).."?", function()
                            if type(GiveMasterLoot) == "function" then
                                pcall(function() GiveMasterLoot(slotId, candidate.index) end)
                                print("GuildRoll: Assigned slot "..tostring(slotId).." to "..tostring(candidate.name))
                            else
                                print("GuildRoll: GiveMasterLoot not available; perform manual assignment.")
                            end
                            mlf.hide()
                        end)
                    end)
                    mlf.show()
                end)
                hookedCount = hookedCount + 1
            end
        end
    end

    return hookedCount
end

function RollSystem:HookLootButtons()
    if self.buttonsHooked then return end
    local num = GetNumLootItems and GetNumLootItems() or (C_Loot and C_Loot.GetNumLootItems and C_Loot.GetNumLootItems() or 0)
    if num <= 0 then
        -- nothing to hook right now; we'll try again on LOOT_OPENED
        return
    end
    local hooked = find_and_hook_buttons(self)
    if hooked > 0 then
        self.buttonsHooked = true
        print("GuildRoll: Hooked "..tostring(hooked).." loot buttons.")
    else
        print("GuildRoll: No loot buttons found to hook (will try fallback).")
    end
end

function RollSystem:RestoreLootButtons()
    if not self.buttonsHooked then
        -- restore any partial entries
        for btn, data in pairs(self.hookedButtons) do
            if btn and data and data.originalOnClick then
                pcall(function() btn:SetScript("OnClick", data.originalOnClick) end)
            end
        end
        self.hookedButtons = {}
        return
    end
    for btn, data in pairs(self.hookedButtons) do
        if btn and data and data.originalOnClick then
            pcall(function() btn:SetScript("OnClick", data.originalOnClick) end)
        else
            if btn then pcall(function() btn:SetScript("OnClick", nil) end) end
        end
    end
    self.hookedButtons = {}
    self.buttonsHooked = false
    if RollSystem.masterLootFrame and RollSystem.masterLootFrame.hide then RollSystem.masterLootFrame.hide() end
    print("GuildRoll: Restored loot button handlers.")
end

-- Register addon prefix (safe)
if C_ChatInfo and type(C_ChatInfo.RegisterAddonMessagePrefix) == "function" then
    pcall(function() C_ChatInfo.RegisterAddonMessagePrefix("GuildRoll") end)
end

-- Events
RollSystem.frame:RegisterEvent("CHAT_MSG_ADDON")
RollSystem.frame:RegisterEvent("CHAT_MSG_SYSTEM")
RollSystem.frame:RegisterEvent("CHAT_MSG_SAY")
RollSystem.frame:RegisterEvent("CHAT_MSG_RAID")
RollSystem.frame:RegisterEvent("LOOT_OPENED")
RollSystem.frame:RegisterEvent("LOOT_CLOSED")
RollSystem.frame:RegisterEvent("LOOT_SLOT_CLEARED")
RollSystem.frame:RegisterEvent("PLAYER_LOGIN")

-- Slash /grforce: toggle force LootAdmin (usage: /grforce on|off|status)
SLASH_GRFORCE1 = "/grforce"
SlashCmdList["GRFORCE"] = function(msg)
    local cmd = (msg or ""):lower():match("^(%S+)")
    if cmd == "on" then
        RollSystem._forceLootAdmin = true
        print("GuildRoll: forceLootAdmin = ON")
    elseif cmd == "off" then
        RollSystem._forceLootAdmin = false
        print("GuildRoll: forceLootAdmin = OFF")
    else
        print("GuildRoll /grforce usage: /grforce on | off | status")
        print("current:", RollSystem._forceLootAdmin and "ON" or "OFF")
    end
end

-- Central event handler
RollSystem.frame:SetScript("OnEvent", function(self, event, arg1, arg2, arg3, arg4, arg5)
    if event == "PLAYER_LOGIN" then
        print("GuildRoll: rollsystem loaded (PLAYER_LOGIN).")
        -- helper slash commands for testing
        SLASH_GUILDROLL1 = "/grhook"
        SlashCmdList["GUILDROLL"] = function()
            if _G.GuildRoll_RollSystem then
                _G.GuildRoll_RollSystem:HookLootButtons()
                print("GuildRoll: manual HookLootButtons() called.")
            end
        end
        SLASH_GUILDROLLMOCK1 = "/grmockloot"
        SlashCmdList["GUILDROLLMOCK"] = function()
            if _G.GuildRoll_RollSystem then
                _G.GuildRoll_RollSystem:OpenCustomLootFrame({{slot=1, itemLink="|cff1eff00|Hitem:12345:0:0:0|h[Test Item]|h|r", itemID=12345, quality=2}}, "mock")
                print("GuildRoll: opened mock loot for testing.")
            end
        end

    elseif event == "CHAT_MSG_ADDON" then
        local prefix, msg, channel, sender = arg1, arg2, arg3, arg4
        if prefix == "GuildRoll" and msg then
            local parts = {}
            for s in string.gmatch(msg, "([^:]+)") do table.insert(parts, s) end
            if parts[1] == "ROLL" and parts[2] and parts[3] then
                local typeCode = parts[2]
                local value = tonumber(parts[3]) or 0
                local sname = Ambiguate(sender, "none")
                RollSystem:AddRoll(sname, typeCode, value, nil, nil)
            end
        end

    elseif event == "CHAT_MSG_SYSTEM" then
        local msg = arg1
        local player, rolls, minStr, maxStr = msg:match("^(.+) rolls (%d+) %((%d+)%-(%d+)%)$")
        if player and rolls then
            player = Ambiguate(player, "none")
            RollSystem:StoreSystemRoll(player, tonumber(rolls), tonumber(minStr), tonumber(maxStr), msg)
        end

    elseif event == "CHAT_MSG_SAY" or event == "CHAT_MSG_RAID" then
        local msg, sender = arg1, arg2
        local sname = Ambiguate(sender, "none")
        if not msg or not sname then return end
        RollSystem:StoreAnnouncement(sname, msg, event)

    elseif event == "LOOT_OPENED" then
        print("GuildRoll: LOOT_OPENED event. IsLootAdmin:", tostring(RollSystem.IsLootAdmin()))
        if RollSystem.IsLootAdmin() then
            RollSystem:HookLootButtons()
            local items = BuildLootItemsFromGame()
            RollSystem:OpenCustomLootFrame(items, nil)
            if not InCombatLockdown or not InCombatLockdown() then HideDefaultLootFrame() end
        else
            RollSystem:RestoreLootButtons()
        end

    elseif event == "LOOT_CLOSED" then
        print("GuildRoll: LOOT_CLOSED")
        RollSystem:RestoreLootButtons()
        if RollSystem.lootFrame and RollSystem.lootFrame:IsShown() then RollSystem.lootFrame:Hide() end

    elseif event == "LOOT_SLOT_CLEARED" then
        local slot = arg1
        if RollSystem.lootFrame and RollSystem.lootFrame:IsShown() then
            local items = BuildLootItemsFromGame()
            RollSystem:OpenCustomLootFrame(items, nil)
        end
    end

    cleanupOld()
end)

-- Loot Options menu helper
function RollSystem.RegisterLootOptionsMenu(parentMenu)
    if not RollSystem.IsPlayerAddonAdmin() then return end
    local btn = CreateFrame("Button", "GuildRoll_LootOptionsButton", parentMenu, "UIPanelButtonTemplate")
    btn:SetSize(160, 22)
    btn:SetPoint("TOPLEFT", parentMenu, "TOPLEFT", 12, -12)
    btn:SetText("Loot Options")
    btn:SetScript("OnClick", function()
        if not RollSystem.lootOptionsFrame then
            local f = CreateFrame("Frame", "GuildRoll_LootOptions", UIParent, "BackdropTemplate")
            f:SetSize(420, 260)
            f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            f:SetBackdrop({ bgFile="Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", edgeSize=16 })
            f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            f.title:SetPoint("TOP", 0, -8)
            f.title:SetText("Loot Options")

            local importBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
            importBtn:SetSize(160, 26)
            importBtn:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -36)
            importBtn:SetText("Import SoftReserves")
            importBtn:SetScript("OnClick", function()
                StaticPopupDialogs["GUILDROLL_IMPORTSR"] = StaticPopupDialogs["GUILDROLL_IMPORTSR"] or {
                    text = "Paste CSV text:",
                    button1 = ACCEPT,
                    button2 = CANCEL,
                    timeout = 0,
                    whileDead = true,
                    hasEditBox = true,
                    editBoxWidth = 360,
                    OnAccept = function(self)
                        local txt = self.editBox:GetText() or ""
                        RollSystem.ImportSoftReservesFromText(txt)
                    end,
                }
                StaticPopup_Show("GUILDROLL_IMPORTSR")
            end)

            local debankBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
            debankBtn:SetSize(160, 26)
            debankBtn:SetPoint("LEFT", importBtn, "RIGHT", 8, 0)
            debankBtn:SetText("Set DE/Bank")
            debankBtn:SetScript("OnClick", function()
                StaticPopupDialogs["GUILDROLL_SETDEBANK"] = StaticPopupDialogs["GUILDROLL_SETDEBANK"] or {
                    text = "Set DE/Bank player name:",
                    button1 = ACCEPT,
                    button2 = CANCEL,
                    timeout = 0,
                    whileDead = true,
                    hasEditBox = true,
                    editBoxWidth = 200,
                    OnAccept = function(self)
                        local nm = self.editBox:GetText()
                        if nm and nm ~= "" then RollSystem:SetDEBank(nm) end
                    end,
                }
                StaticPopup_Show("GUILDROLL_SETDEBANK")
            end)

            f.debankInfo = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            f.debankInfo:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -76)
            f.debankInfo:SetText("DE/Bank: "..tostring(RollSystem:GetDEBank()))

            RollSystem.lootOptionsFrame = f
        end
        RollSystem.lootOptionsFrame.debankInfo:SetText("DE/Bank: "..tostring(RollSystem:GetDEBank()))
        RollSystem.lootOptionsFrame:Show()
    end)
end

-- Expose global
_G.GuildRoll_RollSystem = RollSystem

return RollSystem
