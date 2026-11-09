-- Note Pad: main window (frame, text box, move/resize, minimize, Escape)
local _, NP = ...

local MIN_W, MIN_H = 260, 180
local MAX_W, MAX_H = 1200, 900
local TAB_H = 26 -- room for the tab row above the text box

local frame, editBox
local modernBox, classicScroll -- whichever editor was built
local grip, minButton

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
NP.TryCreateFrame = TryCreateFrame

local function Clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- Save / restore ---------------------------------------------------------

function NP.SaveText()
    if editBox and NP.db then
        local note = NP.CurrentNote()
        if note then note.text = editBox:GetText() or "" end
    end
end

-- Anchor by the top-left corner, so folding the window keeps the title bar in place.
local function AnchorTopLeft()
    local left, top = frame:GetLeft(), frame:GetTop()
    if not left or not top then return end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
end

local function SavePosition()
    local win = NP.db.window
    AnchorTopLeft()
    local point, _, relPoint, x, y = frame:GetPoint(1)
    if point then
        win.point, win.relPoint, win.x, win.y = point, relPoint, x, y
    end
    win.w = frame:GetWidth()
    if not win.minimized then win.h = frame:GetHeight() end
end

local function FullSize()
    local win = NP.db.window
    local screenW, screenH = UIParent:GetWidth(), UIParent:GetHeight()
    local w = Clamp(win.w, MIN_W, math.min(MAX_W, math.max(MIN_W, screenW)))
    local h = Clamp(win.h, MIN_H, math.min(MAX_H, math.max(MIN_H, screenH)))
    return w, h
end

local function ApplyPosition()
    local win = NP.db.window
    local w, h = FullSize()
    frame:SetSize(w, h) -- callers fold it again with ApplyMinimized when needed
    frame:ClearAllPoints()
    frame:SetPoint(win.point, UIParent, win.relPoint, win.x, win.y)
end

-- Text box -----------------------------------------------------------------

local function SetupEditBoxScripts(eb)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(0)
    if eb.SetMaxBytes then eb:SetMaxBytes(0) end
    eb:SetFontObject(ChatFontNormal)
    eb:HookScript("OnTextChanged", function(self, userInput)
        if userInput then
            local note = NP.CurrentNote()
            if note then note.text = self:GetText() or "" end
        end
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
    local text = NP.CurrentNote().text
    if box.SetText then box:SetText(text) else eb:SetText(text) end
    return eb, box
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
    eb:SetText(NP.CurrentNote().text)
    classicScroll = scroll
    return eb
end

local function SetEditorText(text)
    if modernBox and modernBox.SetText then
        modernBox:SetText(text)
    else
        editBox:SetText(text)
    end
    editBox:SetCursorPosition(0)
    if modernBox and modernBox.GetScrollBox then
        local sb = modernBox:GetScrollBox()
        if sb and sb.ScrollToBegin then sb:ScrollToBegin() end
    end
    if classicScroll then classicScroll:SetVerticalScroll(0) end
end

-- Notes ----------------------------------------------------------------------

function NP.UpdateTitle()
    if not frame then return end
    local note = NP.CurrentNote()
    local text = "Note Pad"
    if note and note.title ~= "" then text = "Note Pad - " .. note.title end
    if frame.NPTitle then
        frame.NPTitle:SetText(text)
    elseif frame.SetTitle then
        frame:SetTitle(text)
    elseif frame.TitleText then
        frame.TitleText:SetText(text)
    end
end

-- Open note `index`. skipSave: the text box holds a note that no longer exists (deleted).
function NP.ShowNote(index, skipSave)
    local db = NP.db
    if not db.notes[index] then index = 1 end
    if not skipSave then NP.SaveText() end
    db.current = index
    if editBox then SetEditorText(db.notes[index].text) end
    NP.UpdateTitle()
    if NP.RefreshTabs then NP.RefreshTabs(true) end
end

function NP.FocusText()
    if editBox and frame and frame:IsShown() and not NP.db.window.minimized then
        editBox:SetFocus()
    end
end

-- Minimize -----------------------------------------------------------------

-- Simple dark title-bar look while folded (the metal border / dialog border
-- has fixed-size corners that overlap when the frame is this short).
local FOLDED_BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

-- Styled window: how far the plain folded bar reaches past the frame edges.
local FOLD_PAD_LEFT, FOLD_PAD_TOP, FOLD_PAD_RIGHT = 2, 4, 5

local function ColorFolded(f)
    if f.SetBackdropColor then
        f:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
        f:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    end
end

local function CreateFoldedBg(f)
    local bg = TryCreateFrame("Frame", nil, f, "BackdropTemplate")
    if bg and bg.SetBackdrop then
        bg:SetBackdrop(FOLDED_BACKDROP)
        ColorFolded(bg)
    else
        bg = CreateFrame("Frame", nil, f)
        local tex = bg:CreateTexture(nil, "BACKGROUND")
        tex:SetAllPoints()
        tex:SetColorTexture(0.05, 0.05, 0.05, 0.95)
    end
    -- reaches past the frame like the metal border did, around the buttons
    local pad = f.NPFoldPad
    bg:SetPoint("TOPLEFT", f, "TOPLEFT", -pad.left, pad.top)
    bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", pad.right, 0)
    bg:SetFrameLevel(f:GetFrameLevel()) -- below the title and buttons
    bg:Hide()
    return bg
end

-- Folding never moves the frame, the buttons or the title. The frame gets just
-- tall enough for its title-bar buttons and title + FOLD_MARGIN below
-- (styled window: close button at the top edge, 24 px -> 28 px).
local FOLD_MARGIN = 4

local function RegionHeight(region, default)
    local h = region:GetHeight()
    if (not h or h <= 0) and region.GetStringHeight then h = region:GetStringHeight() end
    if not h or h <= 0 then h = default end
    return h
end

-- How far below the frame's top edge a region anchored to the top ends.
local function BottomBelowTop(region, default)
    local h = RegionHeight(region, default)
    local p, _, rp, _, y = region:GetPoint(1)
    if p and rp and p:sub(1, 3) == "TOP" and rp:sub(1, 3) == "TOP" then
        return -(y or 0) + h
    end
    return h
end

local function FoldedHeight()
    local bottom = 0
    local close = frame.NPClose
    if close then
        bottom = BottomBelowTop(close, 24)
        if minButton then -- centred on the close button
            local closeH = RegionHeight(close, 24)
            bottom = math.max(bottom, bottom - closeH / 2 + RegionHeight(minButton, 24) / 2)
        end
    elseif minButton then
        bottom = RegionHeight(minButton, 24)
    end
    if frame.NPTitle then bottom = math.max(bottom, BottomBelowTop(frame.NPTitle, 12)) end
    if type(frame.TitleContainer) == "table" then bottom = math.max(bottom, BottomBelowTop(frame.TitleContainer, 20)) end
    if bottom <= 0 then bottom = 24 end
    return math.ceil(bottom + FOLD_MARGIN)
end

-- While folded the plain bar reaches past the frame (NPFoldPad); widen the
-- screen clamp by the same amount so the bar can't go off-screen.
-- SetClampRectInsets: negative left / positive right / positive top extend the clamp area.
local function SetFoldClamp(on)
    if not frame.SetClampRectInsets then return end
    if on then
        if frame.NPClampSaved then return end
        local l, r, t, b = 0, 0, 0, 0
        if frame.GetClampRectInsets then l, r, t, b = frame:GetClampRectInsets() end
        frame.NPClampSaved = { l or 0, r or 0, t or 0, b or 0 }
        local pad = frame.NPFoldPad
        if pad then
            local s = frame.NPClampSaved
            frame:SetClampRectInsets(s[1] - pad.left, s[2] + pad.right, s[3] + pad.top, s[4])
        end
    elseif frame.NPClampSaved then
        local s = frame.NPClampSaved
        frame.NPClampSaved = nil
        frame:SetClampRectInsets(s[1], s[2], s[3], s[4])
    end
end

local function SetFoldedLook(on)
    SetFoldClamp(on)
    if frame.NPFoldedBg then -- styled frame: swap the metal border for the plain bar
        for _, part in ipairs(frame.NPBorderParts) do part:SetShown(not on) end
        frame.NPFoldedBg:SetShown(on)
    elseif frame.NPDialogBackdrop then -- fallback frame: swap its own backdrop
        if on then
            frame:SetBackdrop(FOLDED_BACKDROP)
            ColorFolded(frame)
        else
            frame:SetBackdrop(frame.NPDialogBackdrop)
            frame:SetBackdropColor(1, 1, 1, 1)
            frame:SetBackdropBorderColor(1, 1, 1, 1)
        end
    end
end

local function ApplyMinimized(on)
    local inset = frame.NPInset
    SetFoldedLook(on)
    if on then
        if editBox then
            editBox:ClearFocus()
            NP.SaveText()
        end
        if NP.CancelRename then NP.CancelRename() end
        inset:Hide()
        if NP.tabRow then NP.tabRow:Hide() end
        if grip then grip:Hide() end
        local foldedH = FoldedHeight()
        frame:SetResizeBounds(MIN_W, foldedH, MAX_W, MAX_H)
        frame:SetHeight(foldedH)
    else
        local _, h = FullSize()
        frame:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
        frame:SetHeight(h)
        inset:Show()
        if NP.tabRow then NP.tabRow:Show() end
        if grip then grip:Show() end
    end
    if minButton then minButton:UpdateLook(on) end
end

function NP.SetMinimized(on)
    on = not not on
    local win = NP.db.window
    if frame and not win.minimized then SavePosition() end -- keep the full height
    win.minimized = on
    if not frame then return end
    AnchorTopLeft()
    ApplyMinimized(on)
    SavePosition()
end

function NP.ResetWindow()
    local d = NP.defaults.window
    local win = NP.db.window
    win.point, win.relPoint, win.x, win.y = d.point, d.relPoint, d.x, d.y
    win.w, win.h = d.w, d.h
    win.minimized = false
    if frame then
        ApplyPosition()
        ApplyMinimized(false)
    end
end

-- Window -----------------------------------------------------------------

local function CreateFallbackFrame()
    local f = CreateFrame("Frame", "NotePadFrame", UIParent, "BackdropTemplate")
    f.NPDialogBackdrop = BACKDROP_DIALOG_32_32 or {
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    }
    f:SetBackdrop(f.NPDialogBackdrop)
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -16)
    title:SetPoint("LEFT", 40, 0)
    title:SetPoint("RIGHT", -60, 0)
    title:SetWordWrap(false)
    title:SetText("Note Pad")
    f.NPTitle = title
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)
    f.NPClose = close
    local inset = CreateFrame("Frame", nil, f)
    inset:SetPoint("TOPLEFT", 14, -36)
    inset:SetPoint("BOTTOMRIGHT", -14, 18)
    f.NPInset = inset
    f.NPTitleH = 34
    return f
end

local function CreateStyledFrame()
    local f = TryCreateFrame("Frame", "NotePadFrame", UIParent, "ButtonFrameTemplate")
    if not f or not f.Inset then return nil end
    if ButtonFrameTemplate_HidePortrait then ButtonFrameTemplate_HidePortrait(f) end
    if ButtonFrameTemplate_HideButtonBar then ButtonFrameTemplate_HideButtonBar(f) end
    f.NPInset = f.Inset
    f.NPClose = f.CloseButton
    f.NPTitleH = 24
    -- Border/background pieces hidden while folded (only the ones that exist).
    f.NPBorderParts = {}
    for _, key in ipairs({ "NineSlice", "Bg", "TopTileStreaks", "Background" }) do
        local part = f[key]
        if type(part) == "table" and part.SetShown then
            f.NPBorderParts[#f.NPBorderParts + 1] = part
        end
    end
    -- How far the folded bar reaches past the frame: the close button sits on the
    -- top edge (TOPRIGHT +1, 0), so 4 px above it and 4 px right of it; 2 px on the left.
    f.NPFoldPad = { left = FOLD_PAD_LEFT, top = FOLD_PAD_TOP, right = FOLD_PAD_RIGHT }
    f.NPFoldedBg = CreateFoldedBg(f)
    return f
end

-- Make room for the tab row between the title bar and the inset: the styled
-- frame's inset already starts 60 px down (enough room); the fallback one needs moving.
local function MakeRoomForTabs(f, inset)
    local titleH = f.NPTitleH or 24
    for i = 1, inset:GetNumPoints() do
        local p, rel, rp, x, y = inset:GetPoint(i)
        if p == "TOPLEFT" or p == "TOP" or p == "TOPRIGHT" then
            local gap = -(y or 0) - titleH
            local shift = math.max(0, TAB_H - gap)
            if shift > 0 then inset:SetPoint(p, rel, rp, x, y - shift) end
        end
    end
end

local function CreateResizeGrip(f)
    local g = CreateFrame("Button", nil, f)
    g:SetSize(16, 16)
    g:SetPoint("BOTTOMRIGHT", -4, 4)
    g:SetFrameLevel(f:GetFrameLevel() + 10)
    g:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    g:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    g:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    g:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then f:StartSizing("BOTTOMRIGHT") end
    end)
    g:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        SavePosition()
    end)
    return g
end

-- Minimize button left of the close button: Blizzard's red fold/unfold button
-- if the template exists, else our own button with the old smaller/bigger arrows.
local function CreateMinimizeButton(f)
    local close = f.NPClose
    local mm = TryCreateFrame("Frame", nil, f, "MaximizeMinimizeButtonFrameTemplate")
    if mm and mm.Minimize and mm.Maximize and mm.SetOnMinimizedCallback and mm.SetOnMaximizedCallback then
        if close then
            mm:SetPoint("RIGHT", close, "LEFT", 2, 0)
        else
            mm:SetPoint("TOPRIGHT", -30, -2)
        end
        mm:SetOnMinimizedCallback(function() NP.SetMinimized(true) end)
        mm:SetOnMaximizedCallback(function() NP.SetMinimized(false) end)
        function mm:UpdateLook(on)
            -- automatic action, no callback: only switches which arrow is shown
            if on then self:Minimize(true, true) else self:Maximize(true, true) end
        end
        return mm
    end

    local b = CreateFrame("Button", nil, f)
    b:SetSize(32, 32)
    if close then
        b:SetPoint("RIGHT", close, "LEFT", 8, 0)
    else
        b:SetPoint("TOPRIGHT", -36, -6)
    end
    b:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", "ADD")
    b:SetScript("OnClick", function() NP.SetMinimized(not NP.db.window.minimized) end)
    function b:UpdateLook(on)
        local state = on and "BiggerButton" or "SmallerButton"
        self:SetNormalTexture("Interface\\Buttons\\UI-Panel-" .. state .. "-Up")
        self:SetPushedTexture("Interface\\Buttons\\UI-Panel-" .. state .. "-Down")
    end
    b:UpdateLook(false)
    return b
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
        if NP.CancelRename then NP.CancelRename() end
        if editBox then
            editBox:ClearFocus()
            NP.SaveText()
        end
    end)

    local inset = frame.NPInset
    MakeRoomForTabs(frame, inset)

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

    local ok, eb, box = pcall(CreateModernEditor, inset)
    if ok and eb then
        modernBox = box
    else
        eb = CreateClassicEditor(inset)
    end
    editBox = eb

    if NP.CreateTabs then
        NP.CreateTabs(frame, inset, TAB_H - 2)
    end

    grip = CreateResizeGrip(frame)
    minButton = CreateMinimizeButton(frame)
    ApplyPosition()
    if NP.db.window.minimized then ApplyMinimized(true) end
    NP.UpdateTitle()

    -- Escape closes the window (when the text box doesn't have focus).
    tinsert(UISpecialFrames, "NotePadFrame")
end

function NP.ToggleWindow()
    if not frame then return end
    if frame:IsShown() then frame:Hide() else frame:Show() end
end
