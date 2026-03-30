-- Add line - admins get click-to-menu functionality and Rank column
if isAdmin then
  -- Admin: clicking opens a mini-menu with Give EP and Show Personal Log options
  local capturedName = originalName
  cat:AddLine(
    "text", text,
    "text2", text2,
    "text3", text3,
    "func", function()
      local name = capturedName
      -- Lazily create a 1x1 anchor frame for Dewdrop:Open() (requires a real frame, not a string)
      if not GuildRoll_standings._menuAnchor then
        GuildRoll_standings._menuAnchor = CreateFrame("Frame", nil, UIParent)
        GuildRoll_standings._menuAnchor:SetWidth(1)
        GuildRoll_standings._menuAnchor:SetHeight(1)
      end
      -- Position anchor at cursor so menu appears near the click
      local anchor = GuildRoll_standings._menuAnchor
      local scale = UIParent:GetScale()
      local cx, cy = GetCursorPosition()
      anchor:ClearAllPoints()
      anchor:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", cx / scale, cy / scale)
      D:Open(anchor,
        "children", function()
          D:AddLine(
            "text", L["Give EP..."],
            "tooltipText", L["Award EP to this player"],
            "func", function()
              if GuildRoll and GuildRoll.ShowGiveEPDialog then
                GuildRoll:ShowGiveEPDialog(name)
              end
            end
          )
          D:AddLine(
            "text", L["Show Personal Log"],
            "tooltipText", L["Show personal EP log for this player"],
            "func", function()
              if GuildRoll and GuildRoll.ShowPersonalLog then
                GuildRoll:ShowPersonalLog(name)
              end
            end
          )
        end
      )
    end
  )
else
  -- Non-admin: just display the line without rank
  cat:AddLine(
    "text", text,
    "text2", text2
  )
end
