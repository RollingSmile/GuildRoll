-- Complete modification of UpdateRollPopupVisibility function to show all buttons always but selectively disable them based on character type and CSR threshold.
function UpdateRollPopupVisibility(characterType, csrThreshold)
    local buttons = {"button1", "button2", "button3", "button4"}
    local enableRollButtonsOverride = true  -- Assuming this is provided elsewhere in your code

    for _, button in ipairs(buttons) do
        if enableRollButtonsOverride then
            EnableButton(button)  -- Function to enable button
        else
            if characterType == "ALT" then
                if button == "button1" or button == "button2" or button == "button3" then
                    EnableButton(button)
                else
                    DisableButton(button)
                end
            elseif characterType == "MAIN" then
                if csrThreshold < 100 then
                    if button ~= "button4" then
                        EnableButton(button)
                    else
                        DisableButton(button)
                    end
                else
                    EnableButton(button)
                end
            else
                DisableButton(button)  -- Disable for other character types
            end
        end
    end
end

-- RepositionRollButtons to maintain consistent positioning regardless of zone.
function RepositionRollButtons()
    local zone = GetCurrentZone()  -- Function to get current zone
    local positioning = GetButtonPositioning(zone)  -- Function to get position based on zone
    for _, button in ipairs(buttons) do  -- Assuming buttons are defined globally or passed in as needed
        PositionButton(button, positioning)  -- Function to set the button position
    end
end