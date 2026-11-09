-- Note Pad: main window (frame, text box, move/resize, minimize, Escape)
local _, NP = ...

local MIN_W, MIN_H = 260, 180
local MAX_W, MAX_H = 1200, 900
local TITLE_BAR_H = 24       -- double-click area at the top of the window
local DOUBLE_CLICK_TIME = 0.3

local frame, editBox
local modernBox, classicScroll -- whichever editor was built
local grip, minButton
local lastTitleClick -- GetTime() of the last single click on the title bar

local function TemplateExists(name)
    if C_XMLUtil and C_XMLUtil.GetTemplateInfo then
        return C_XMLUtil.GetTemplateInfo(name) ~= nil
    end
    return true -- can't tell; pcall around CreateFrame catches a miss
end
NP.TemplateExists = TemplateExists

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

-- The text box is bound to one note TABLE (editorNote): whatever is in the box is only
-- ever written back into the note it was loaded from, never into "the current index".
-- So a stale or failed text swap can't copy one note's text into another.
local editorNote

function NP.EditorNote() return editorNote end

function NP.SaveText()
    if editBox and editorNote then
        editorNote.text = editBox:GetText() or ""
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
        if userInput and editorNote then
            editorNote.text = self:GetText() or ""
        end
    end)
    eb:HookScript("OnEscapePressed", function(self) self:ClearFocus() end)
    -- Ctrl+Tab / Ctrl+Shift+Tab: next / previous note (only while typing here)
    eb:HookScript("OnTabPressed", function()
        if IsControlKeyDown() and NP.CycleNote then
            NP.CycleNote(IsShiftKeyDown() and -1 or 1)
        end
    end)
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
    editorNote = NP.CurrentNote()
    local text = editorNote.text
    if box.SetText then box:SetText(text) else eb:SetText(text) end
    if (eb:GetText() or "") ~= text then eb:SetText(text) end
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
    editorNote = NP.CurrentNote()
    eb:SetText(editorNote.text)
    classicScroll = scroll
    return eb
end

-- Load `note` into the text box and bind the box to it.
local function LoadNoteIntoEditor(note)
    local text = note.text or ""
    editorNote = note -- bind first: anything the box reports from now on belongs to this note
    if modernBox and modernBox.SetText then
        modernBox:SetText(text)
    else
        editBox:SetText(text)
    end
    -- The scrolling box's own SetText path may skip the swap (e.g. for an empty
    -- text it can leave the old one in place); check and set it directly if so.
    if (editBox:GetText() or "") ~= text then
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

-- Open note `index`: the box, the title and the tabs always end up showing the same note.
-- skipSave: the text box holds a note that no longer exists (deleted).
function NP.ShowNote(index, skipSave)
    local db = NP.db
    if not db.notes[index] then index = 1 end
    if not skipSave then NP.SaveText() end -- into the note the box was loaded from
    db.current = index
    if editBox then LoadNoteIntoEditor(db.notes[index]) end
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
    bgFile = NP.Art.tooltipBg,
    edgeFile = NP.Art.tooltipBorder,
    tile = true, tileSize = 16, edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local function ColorFolded(f)
    if f.SetBackdropColor then
        f:SetBackdropColor(unpack(NP.Color.barBg))
        f:SetBackdropBorderColor(unpack(NP.Color.barBorder))
    end
end

-- Folded bar edges, measured from in-game screenshots (v0.0.3-beta.1, buttons as the
-- reference, ~1.15 screen px per UI unit): the metal's visible outline is about 5 units
-- above the frame top, 2 right of its right edge and 3 inside its left edge. The layout puts the corner pieces at
-- x -8 / +4, y +16 from the frame, so the margins inside the corner art are:
local FOLD_EDGE_LEFT  = 11 -- corner left edge -> visible metal left edge (8 + 3)
local FOLD_EDGE_TOP   = 11 -- corner top edge  -> visible metal top edge (16 - 5)
local FOLD_EDGE_RIGHT = 1  -- corner right edge -> visible metal right edge (4 - 2), +1 px of air for the close button
local FOLD_EDGE_BOTTOM = 3 -- bar bottom this far above the frame bottom: same room below the buttons as above
local LAYOUT_CORNER_TOP = 16 -- ButtonFrameTemplateNoPortrait: corner y offset (used if it can't be measured)
-- No metal pieces (fallback): the beta.5 pads around the frame.
local FALLBACK_PAD_LEFT, FALLBACK_PAD_TOP, FALLBACK_PAD_RIGHT = 2, 4, 5

-- A 1 px line of `color` along one side of `bar`, `inset` px in from the edge.
local function EdgeLine(bar, side, inset, color)
    local t = bar:CreateTexture(nil, "BORDER")
    t:SetColorTexture(unpack(color))
    if side == "TOP" or side == "BOTTOM" then
        local y = (side == "TOP") and -inset or inset
        t:SetPoint(side .. "LEFT", bar, side .. "LEFT", inset, y)
        t:SetPoint(side .. "RIGHT", bar, side .. "RIGHT", -inset, y)
        if PixelUtil and PixelUtil.SetHeight then PixelUtil.SetHeight(t, 1) else t:SetHeight(1) end
    else
        local x = (side == "LEFT") and inset or -inset
        t:SetPoint("TOP" .. side, bar, "TOP" .. side, x, -inset)
        t:SetPoint("BOTTOM" .. side, bar, "BOTTOM" .. side, x, inset)
        if PixelUtil and PixelUtil.SetWidth then PixelUtil.SetWidth(t, 1) else t:SetWidth(1) end
    end
    return t
end

-- The folded bar: dark centre + own thin 2 px edge (1 px black outside, 1 px bronze
-- inside), plain colour textures. Thin on purpose: the gap between the metal's outer
-- edge and the title-bar buttons is only 2-3 px, so a thick border would run under them.
local function CreateFoldedBg(f)
    local bar = CreateFrame("Frame", nil, f)
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", 1, -1)
    bg:SetPoint("BOTTOMRIGHT", -1, 1)
    bg:SetColorTexture(unpack(NP.Color.barBg))
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        EdgeLine(bar, side, 0, NP.Color.edgeOuter)
        EdgeLine(bar, side, 1, NP.Color.edgeInner)
    end
    -- Same visible outer edges as the unfolded metal border: anchored to the metal's
    -- own corner pieces (hidden textures still have positions), minus the see-through
    -- margin inside the corner art. Fallback: fixed pads around the frame.
    local ns = f.NineSlice
    local tl = type(ns) == "table" and ns.TopLeftCorner
    local tr = type(ns) == "table" and ns.TopRightCorner
    if type(tl) == "table" and type(tr) == "table" then
        bar:SetPoint("TOPLEFT", tl, "TOPLEFT", FOLD_EDGE_LEFT, -FOLD_EDGE_TOP)
        bar:SetPoint("TOPRIGHT", tr, "TOPRIGHT", -FOLD_EDGE_RIGHT, -FOLD_EDGE_TOP)
        bar.NPCorner = tl
    else
        bar:SetPoint("TOPLEFT", f, "TOPLEFT", -FALLBACK_PAD_LEFT, FALLBACK_PAD_TOP)
        bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", FALLBACK_PAD_RIGHT, FALLBACK_PAD_TOP)
    end
    bar:SetHeight(1) -- real height set when folding (UpdateFoldedBarHeight)
    bar:SetFrameLevel(f:GetFrameLevel()) -- below the title and buttons
    bar:Hide()
    return bar
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

-- The folded bar's top follows the metal corner; its bottom sits FOLD_EDGE_BOTTOM
-- above the frame bottom, so its height = (how far its top is above the frame) + folded height - that.
local function UpdateFoldedBarHeight(foldedH)
    local bar = frame.NPFoldedBg
    if not bar then return end
    local above, bottomUp
    if bar.NPCorner then
        local cornerTop, frameTop = bar.NPCorner:GetTop(), frame:GetTop()
        local cornerAbove = (cornerTop and frameTop) and (cornerTop - frameTop) or 0
        if cornerAbove <= 0 then cornerAbove = LAYOUT_CORNER_TOP end -- not laid out yet
        above, bottomUp = cornerAbove - FOLD_EDGE_TOP, FOLD_EDGE_BOTTOM
    else
        above, bottomUp = FALLBACK_PAD_TOP, 0
    end
    bar:SetHeight(math.max(1, above + foldedH - bottomUp))
end

local function SetFoldedLook(on)
    if frame.NPFoldedBg then -- styled frame: swap the metal border for the plain bar
        for _, part in ipairs(frame.NPBorderParts) do part:SetShown(not on) end
        frame.NPFoldedBg:SetShown(on)
    elseif frame.NPDialogBackdrop then -- fallback frame: swap its own backdrop
        if on then
            frame:SetBackdrop(FOLDED_BACKDROP)
            ColorFolded(frame)
        else
            frame:SetBackdrop(frame.NPDialogBackdrop)
            frame:SetBackdropColor(unpack(NP.Color.white))
            frame:SetBackdropBorderColor(unpack(NP.Color.white))
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
        if NP.FinishRename then NP.FinishRename(true) end
        inset:Hide()
        if NP.tabRow then NP.tabRow:Hide() end
        if grip then grip:Hide() end
        local foldedH = FoldedHeight()
        frame:SetResizeBounds(MIN_W, foldedH, MAX_W, MAX_H)
        frame:SetHeight(foldedH)
        UpdateFoldedBarHeight(foldedH)
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
        bgFile = NP.Art.dialogBg,
        edgeFile = NP.Art.dialogBorder,
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
    f.NPFoldedBg = CreateFoldedBg(f)
    return f
end

-- Make room for the tab row between the title bar and the inset: the styled
-- frame's inset already starts 60 px down (enough room); the fallback one needs moving.
local function MakeRoomForTabs(f, inset, needed)
    local titleH = f.NPTitleH or 24
    for i = 1, inset:GetNumPoints() do
        local p, rel, rp, x, y = inset:GetPoint(i)
        if p == "TOPLEFT" or p == "TOP" or p == "TOPRIGHT" then
            local gap = -(y or 0) - titleH
            local shift = math.max(0, needed - gap)
            if shift > 0 then inset:SetPoint(p, rel, rp, x, y - shift) end
        end
    end
end

local function CreateResizeGrip(f)
    local g = CreateFrame("Button", nil, f)
    g:SetSize(16, 16)
    g:SetPoint("BOTTOMRIGHT", -4, 4)
    g:SetFrameLevel(f:GetFrameLevel() + 10)
    g:SetNormalTexture(NP.Art.gripUp)
    g:SetPushedTexture(NP.Art.gripDown)
    g:SetHighlightTexture(NP.Art.gripHighlight)
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
    b:SetHighlightTexture(NP.Art.minimizeHighlight, "ADD")
    b:SetScript("OnClick", function() NP.SetMinimized(not NP.db.window.minimized) end)
    function b:UpdateLook(on)
        self:SetNormalTexture(on and NP.Art.biggerUp or NP.Art.smallerUp)
        self:SetPushedTexture(on and NP.Art.biggerDown or NP.Art.smallerDown)
    end
    b:UpdateLook(false)
    return b
end

-- Title at the left of the title bar (folded too: same text, same anchors), one line,
-- cut with "..." before the fold button. Styled: the template's own TitleText keeps
-- its height; fallback: our NPTitle. If neither exists, nothing changes.
local TITLE_LEFT_STYLED, TITLE_LEFT_FALLBACK, TITLE_GAP_RIGHT = 12, 16, 4
local TITLE_RIGHT_DEFAULT = 60 -- until the fold button can be measured (first show)

-- Both title anchors are TOP points on the same strip (a mixed TOPLEFT + RIGHT pair
-- would give the text two different vertical anchors), so the right edge is an offset
-- from the strip's right: measured as "strip right -> fold button left + gap".
local function SetTitleRight(text, rel, y, inset)
    text:SetPoint("TOPRIGHT", rel, "TOPRIGHT", -inset, y)
end

local function MeasureTitleRight(f)
    local t = f.NPTitleText
    if not t then return end
    local r, l = t.rel:GetRight(), t.mm and t.mm:GetLeft()
    if type(r) == "number" and type(l) == "number" and r > l then
        SetTitleRight(t.text, t.rel, t.y, r - l + TITLE_GAP_RIGHT)
    end
end

local function PlaceTitleLeft(f, mm)
    local text, rel, x, y
    if type(f.NPTitle) == "table" then
        text, rel, x, y = f.NPTitle, f, TITLE_LEFT_FALLBACK, -16
    else
        local tc = f.TitleContainer
        text = type(tc) == "table" and tc.TitleText
        if type(text) ~= "table" or not text.SetPoint then return end
        rel, x, y = tc, TITLE_LEFT_STYLED, nil
        -- keep the template's height: its vertical offset from the strip's top
        for i = 1, (text.GetNumPoints and text:GetNumPoints() or 0) do
            local p, _, rp, _, py = text:GetPoint(i)
            if type(p) == "string" and p:find("TOP") and type(rp) == "string" and rp:find("TOP") and type(py) == "number" then
                y = py break
            end
        end
        y = y or -5
    end
    text:ClearAllPoints()
    text:SetPoint("TOPLEFT", rel, "TOPLEFT", x, y)
    SetTitleRight(text, rel, y, TITLE_RIGHT_DEFAULT)
    if text.SetJustifyH then text:SetJustifyH("LEFT") end
    if text.SetWordWrap then text:SetWordWrap(false) end
    if text.SetMaxLines then text:SetMaxLines(1) end
    f.NPTitleText = { text = text, rel = rel, y = y, mm = type(mm) == "table" and mm or nil }
    MeasureTitleRight(f)
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
    frame:SetScript("OnDragStart", function(self)
        self.NPDragged = true -- this press is a drag, not a click
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if self.SetUserPlaced then self:SetUserPlaced(false) end
        SavePosition()
    end)
    -- Double-click on the title bar folds / unfolds (frames have no OnDoubleClick).
    frame:HookScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then self.NPDragged = false end
    end)
    frame:HookScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" then return end
        if self.NPDragged or not NP.IsCursorOnTitleBar() then
            lastTitleClick = nil
            return
        end
        local now = GetTime()
        if lastTitleClick and now - lastTitleClick <= DOUBLE_CLICK_TIME then
            lastTitleClick = nil
            NP.SetMinimized(not NP.db.window.minimized)
        else
            lastTitleClick = now
        end
    end)
    frame:HookScript("OnShow", function(self)
        -- measure the metal corner again now that the window is laid out
        if NP.db.window.minimized then UpdateFoldedBarHeight(self:GetHeight()) end
        MeasureTitleRight(self) -- the fold button's real position is known now
    end)
    frame:HookScript("OnHide", function(self)
        self:StopMovingOrSizing()
        if NP.FinishRename then NP.FinishRename(true) end
        if editBox then
            editBox:ClearFocus()
            NP.SaveText()
        end
    end)

    local inset = frame.NPInset
    local tabRowH = NP.TabRowHeight and NP.TabRowHeight() or 24
    MakeRoomForTabs(frame, inset, tabRowH + 2)

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
        NP.CreateTabs(frame, inset, tabRowH)
    end

    grip = CreateResizeGrip(frame)
    minButton = CreateMinimizeButton(frame)
    PlaceTitleLeft(frame, minButton)
    ApplyPosition()
    if NP.db.window.minimized then ApplyMinimized(true) end
    NP.UpdateTitle()

    -- Escape closes the window (when the text box doesn't have focus).
    tinsert(UISpecialFrames, "NotePadFrame")
end

-- Is the cursor in the top TITLE_BAR_H px of the window?
function NP.IsCursorOnTitleBar()
    if not frame then return false end
    local top = frame:GetTop()
    if not top then return false end
    local _, y = GetCursorPosition()
    y = y / frame:GetEffectiveScale()
    return y <= top and y >= top - TITLE_BAR_H
end

-- Show the window unfolded.
function NP.OpenWindow()
    if not frame then return end
    frame:Show()
    if NP.db.window.minimized then NP.SetMinimized(false) end
end

-- /np and minimap left-click: closed -> open unfolded; open but folded -> unfold; open -> close.
function NP.ToggleWindow()
    if not frame then return end
    if not frame:IsShown() or NP.db.window.minimized then
        NP.OpenWindow()
    else
        frame:Hide()
    end
end

-- Minimap right-click: closed -> open folded; open -> fold / unfold.
function NP.ToggleFold()
    if not frame then return end
    if not frame:IsShown() then
        frame:Show()
        if not NP.db.window.minimized then NP.SetMinimized(true) end
        return
    end
    NP.SetMinimized(not NP.db.window.minimized)
end
