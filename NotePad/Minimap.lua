-- Note Pad: minimap button (own code, no libraries)
local _, NP = ...

local button

-- Place the button on the minimap edge at the saved angle (degrees).
-- Round minimap: on the circle. Square minimap (if an addon reports one): on the square edge.
local function UpdatePosition()
    local angle = math.rad(NP.db.minimap.angle or 225)
    local x, y = math.cos(angle), math.sin(angle)
    local w = (Minimap:GetWidth() / 2) + 5
    local h = (Minimap:GetHeight() / 2) + 5
    local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
    if shape == "SQUARE" then
        local m = math.max(math.abs(x), math.abs(y))
        if m > 0 then x, y = x / m, y / m end
    end
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x * w, y * h)
end

local function OnDragUpdate()
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    px, py = px / scale, py / scale
    NP.db.minimap.angle = math.deg(math.atan2(py - my, px - mx)) % 360
    UpdatePosition()
end

function NP.CreateMinimapButton()
    if button or not Minimap then return end
    button = CreateFrame("Button", "NotePadMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture(NP.Art.minimapHighlight)

    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetTexture(NP.Art.minimapBg)
    bg:SetPoint("TOPLEFT", 7, -5)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17)
    icon:SetTexture(NP.Art.icon)
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    icon:SetPoint("TOPLEFT", 7, -6)
    button.icon = icon

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetTexture(NP.Art.minimapBorder)
    border:SetPoint("TOPLEFT")

    -- Left-click: open (unfolded) / close. Right-click: fold / unfold (opens folded if closed).
    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            NP.ToggleFold()
        else
            NP.ToggleWindow()
        end
    end)
    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", OnDragUpdate)
        GameTooltip:Hide()
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Note Pad")
        local w, h = NP.Color.white, NP.Color.hint
        local note, count = NP.CurrentNote(), #NP.db.notes
        GameTooltip:AddLine(("%s (%d %s)"):format(note.title, count, count == 1 and "note" or "notes"), w[1], w[2], w[3])
        GameTooltip:AddLine("Left-click: open / close", h[1], h[2], h[3])
        GameTooltip:AddLine("Right-click: fold / unfold", h[1], h[2], h[3])
        GameTooltip:AddLine("Drag: move this button", h[1], h[2], h[3])
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    UpdatePosition()
    if NP.db.minimap.hide then button:Hide() end
end

function NP.ToggleMinimapButton()
    if not button then return end
    local mm = NP.db.minimap
    mm.hide = not mm.hide
    if mm.hide then
        button:Hide()
        NP.Print("Minimap button hidden. /np minimap shows it again.")
    else
        button:Show()
        UpdatePosition()
        NP.Print("Minimap button shown.")
    end
end
