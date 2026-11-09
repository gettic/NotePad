-- Note Pad: main window (frame, text box, move/resize, Escape)
local _, NP = ...

local MIN_W, MIN_H = 260, 180
local MAX_W, MAX_H = 1200, 900

local frame, editBox

local function TemplateExists(name)
    if C_XMLUtil and C_XMLUtil.GetTemplateInfo then
        return C_XMLUtil.GetTemplateInfo(name) ~= nil
    end
    return true -- can't tell; pcall around CreateFrame catches a miss
end

local function TryCreateFrame(frameType, name, parent, template)
    if not TemplateExists(template) then return nil end
    local ok, f = pcall(CreateFrame, frameType, name, parent, template)
    if ok then return f end
    return nil
end

local function Clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- Save / restore ---------------------------------------------------------

function NP.SaveText()
    if editBox and NP.db then
        NP.db.text = editBox:GetText() or ""
    end
end

local function SavePosition()
    local win = NP.db.window
    local point, _, relPoint, x, y = frame:GetPoint(1)
    if point then
        win.point, win.relPoint, win.x, win.y = point, relPoint, x, y
    end
    win.w, win.h = frame:GetWidth(), frame:GetHeight()
end

local function ApplyPosition()
    local win = NP.db.window
    local screenW, screenH = UIParent:GetWidth(), UIParent:GetHeight()
    local w = Clamp(win.w, MIN_W, math.min(MAX_W, math.max(MIN_W, screenW)))
    local h = Clamp(win.h, MIN_H, math.min(MAX_H, math.max(MIN_H, screenH)))
    frame:SetSize(w, h)
    frame:ClearAllPoints()
    frame:SetPoint(win.point, UIParent, win.relPoint, win.x, win.y)
end

function NP.ResetWindow()
    local d = NP.defaults.window
    local win = NP.db.window
    win.point, win.relPoint, win.x, win.y = d.point, d.relPoint, d.x, d.y
    win.w, win.h = d.w, d.h
    if frame then ApplyPosition() end
end

-- Text box -----------------------------------------------------------------

local function SetupEditBoxScripts(eb)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(0)
    if eb.SetMaxBytes then eb:SetMaxBytes(0) end
    eb:SetFontObject(ChatFontNormal)
    eb:HookScript("OnTextChanged", function(self, userInput)
        if userInput then NP.db.text = self:GetText() or "" end
    end)
    eb:HookScript("OnEscapePressed", function(self) self:ClearFocus() end)
end

-- Preferred: Blizzard's ScrollingEditBoxTemplate + MinimalScrollBar.
local function CreateModernEditor(parent)
    local box = TryCreateFrame("Frame", nil, parent, "ScrollingEditBoxTemplate")
    if not box or not box.GetEditBox then return nil end
    box:SetPoint("TOPLEFT", 6, -6)
    box:SetPoint("BOTTOMRIGHT", -22, 6)

    local bar = TryCreateFrame("EventFrame", nil, parent, "MinimalScrollBar")
    if bar and ScrollUtil and ScrollUtil.RegisterScrollBoxWithScrollBar and box.GetScrollBox then
        bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 6, 0)
        bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 6, 0)
        ScrollUtil.RegisterScrollBoxWithScrollBar(box:GetScrollBox(), bar)
    end

    local eb = box:GetEditBox()
    SetupEditBoxScripts(eb)
    local text = NP.db.text
    if box.SetText then box:SetText(text) else eb:SetText(text) end
    return eb
end

-- Fallback: classic ScrollFrame + EditBox.
local function CreateClassicEditor(parent)
    local scroll = TryCreateFrame("ScrollFrame", "NotePadScrollFrame", parent, "UIPanelScrollFrameTemplate")
    if not scroll then
        scroll = CreateFrame("ScrollFrame", "NotePadScrollFrame", parent)
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel", function(self, delta)
            local cur, max = self:GetVerticalScroll(), self:GetVerticalScrollRange()
            self:SetVerticalScroll(Clamp(cur - delta * 40, 0, max))
        end)
    end
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -28, 6)

    local eb = CreateFrame("EditBox", "NotePadEditBox", scroll)
    eb:SetPoint("TOPLEFT")
    eb:SetWidth(math.max(1, scroll:GetWidth()))
    eb:SetHeight(1)
    scroll:SetScrollChild(eb)
    scroll:SetScript("OnSizeChanged", function(self, w) eb:SetWidth(math.max(1, w)) end)
    eb:SetScript("OnCursorChanged", function(self, x, y, w, h)
        -- keep the cursor line visible
        local top = -y
        local view = scroll:GetHeight()
        local cur = scroll:GetVerticalScroll()
        if top < cur then
            scroll:SetVerticalScroll(top)
        elseif top + h > cur + view then
            scroll:SetVerticalScroll(top + h - view)
        end
    end)
    SetupEditBoxScripts(eb)
    eb:SetText(NP.db.text)
    return eb
end

-- Window -----------------------------------------------------------------

local function CreateFallbackFrame()
    local f = CreateFrame("Frame", "NotePadFrame", UIParent, "BackdropTemplate")
    f:SetBackdrop(BACKDROP_DIALOG_32_32 or {
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -16)
    title:SetText("Note Pad")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)
    local inset = CreateFrame("Frame", nil, f)
    inset:SetPoint("TOPLEFT", 14, -36)
    inset:SetPoint("BOTTOMRIGHT", -14, 18)
    f.NPInset = inset
    return f
end

local function CreateStyledFrame()
    local f = TryCreateFrame("Frame", "NotePadFrame", UIParent, "ButtonFrameTemplate")
    if not f or not f.Inset then return nil end
    if ButtonFrameTemplate_HidePortrait then ButtonFrameTemplate_HidePortrait(f) end
    if ButtonFrameTemplate_HideButtonBar then ButtonFrameTemplate_HideButtonBar(f) end
    if f.SetTitle then
        f:SetTitle("Note Pad")
    elseif f.TitleText then
        f.TitleText:SetText("Note Pad")
    end
    f.NPInset = f.Inset
    return f
end

local function CreateResizeGrip(f)
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -4, 4)
    grip:SetFrameLevel(f:GetFrameLevel() + 10)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then f:StartSizing("BOTTOMRIGHT") end
    end)
    grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        SavePosition()
    end)
end

function NP.CreateWindow()
    if frame then return end
    frame = CreateStyledFrame() or CreateFallbackFrame()
    frame:Hide()
    frame:SetFrameStrata("MEDIUM")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)

    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if self.SetUserPlaced then self:SetUserPlaced(false) end
        SavePosition()
    end)
    frame:HookScript("OnHide", function(self)
        self:StopMovingOrSizing()
        if editBox then
            editBox:ClearFocus()
            NP.SaveText()
        end
    end)

    local inset = frame.NPInset

    -- Clicking empty space inside the text area puts the cursor at the end.
    local catcher = CreateFrame("Button", nil, inset)
    catcher:SetAllPoints(inset)
    catcher:SetFrameLevel(inset:GetFrameLevel()) -- stay below the text box
    catcher:SetScript("OnClick", function()
        if editBox then
            editBox:SetFocus()
            editBox:SetCursorPosition(#(editBox:GetText() or ""))
        end
    end)

    local ok, eb = pcall(CreateModernEditor, inset)
    if not ok or not eb then
        eb = CreateClassicEditor(inset)
    end
    editBox = eb

    CreateResizeGrip(frame)
    ApplyPosition()

    -- Escape closes the window (when the text box doesn't have focus).
    tinsert(UISpecialFrames, "NotePadFrame")
end

function NP.ToggleWindow()
    if not frame then return end
    if frame:IsShown() then frame:Hide() else frame:Show() end
end
