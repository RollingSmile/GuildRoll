-- RollTableUI.lua
-- Simple RollTable frame showing Player | SR | Roll | Type

local RollTableUI = {}
RollTableUI.__index = RollTableUI

function RollTableUI:create()
  if self.frame then return self.frame end
  local f = CreateFrame("Frame", "GuildRoll_RollTable", UIParent)
  f:SetWidth(520)
  f:SetHeight(320)
  f:SetPoint("CENTER")
  f:SetBackdrop({bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background"})
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function() f:StartMoving() end)
  f:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

  -- header labels
  local headers = {"Player", "SR", "Roll", "Type"}
  for i,h in ipairs(headers) do
    local hl = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hl:SetPoint("TOPLEFT", f, "TOPLEFT", 10 + (i-1)*120, -10)
    hl:SetText(h)
  end

  self.frame = f
  self.rows = {}

  return f
end

function RollTableUI:show()
  self:create()
  self.frame:Show()
end

function RollTableUI:hide()
  if self.frame then self.frame:Hide() end
end

function RollTableUI:refresh(rolls, srLookup)
  self:create()
  -- clear previous rows
  for _,r in ipairs(self.rows) do r:Hide() end
  self.rows = {}

  for i,roll in ipairs(rolls) do
    local row = self.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 10, -30 - (i-1)*16)
    local srFlag = srLookup and srLookup[roll.player] and "SR" or ""
    row:SetText(string.format("%s\t%s\t%d\t%s", roll.player, srFlag, roll.value or 0, roll.type or ""))
    self.rows[#self.rows+1] = row
  end
end

return RollTableUI
