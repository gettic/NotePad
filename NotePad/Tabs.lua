-- Note Pad: tab row (one tab per note: add, switch, rename, move, delete)
local _, NP = ...

local TAB_MIN_W, TAB_PAD, GAP = 50, 20, 2
local PLUS_W = 32            -- [+] a bit wider than square: the red button art is drawn wide
local ART_ARROW_W, TEXT_ARROW_W = 24, 18
local BLIZZ_TAB_H, BOX_TAB_H = 32, 24
local MAX_TITLE = 24
local TOOLTIP_CHARS = 40     -- first line of the note shown in the tab tooltip
local TAB_TEMPLATE = "PanelTopTabButtonTemplate"
local TAB_PARTS = { "Text", "Left", "Middle", "Right", "LeftActive", "MiddleActive", "RightActive" }

local row, plusBtn, leftBtn, rightBtn, renameBox
local tabs = {}      -- tab buttons, reused
local first = 1      -- first tab shown when they don't all fit
local renaming       -- note table being renamed
local pendingDelete  -- note table waiting for the delete popup

local BACKDROP = {
    bgFile = NP.Art.tooltipBg,
    edgeFile = NP.Art.tooltipBorder,
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local function Clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function IndexOf(note)
    for i, n in ipairs(NP.db.notes) do
        if n == note then return i end
    end
end

-- Height of the tab row: Blizzard's top tabs are 32 px, our own boxes 24 px.
function NP.TabRowHeight()
    if PanelTemplates_TabResize and NP.TemplateExists(TAB_TEMPLATE) then return BLIZZ_TAB_H end
    return BOX_TAB_H
end

-- Look -------------------------------------------------------------------------

-- Own box look (fallback tabs, text arrows).
local function Style(b, selected, dimmed)
    local C = NP.Color
    if b.SetBackdropColor then
        b:SetBackdropColor(unpack(selected and C.tabSelBg or C.tabBg))
        b:SetBackdropBorderColor(unpack(selected and C.gold or C.tabBorder))
    elseif b.NPBg then
        b.NPBg:SetColorTexture(unpack(selected and C.tabPlainSel or C.tabPlainBg))
    end
    b.NPText:SetTextColor(unpack(selected and C.gold or C.tabText))
    b:SetAlpha(dimmed and 0.4 or 1)
end

-- Blizzard tab look without PanelTemplates_SelectTab: that one calls Disable(),
-- which would block double-click rename and the right-click menu on the open tab.
local function SetBlizzTabSelected(t, on)
    t.Left:SetShown(not on)
    t.Middle:SetShown(not on)
    t.Right:SetShown(not on)
    t.LeftActive:SetShown(on)
    t.MiddleActive:SetShown(on)
    t.RightActive:SetShown(on)
    t:SetNormalFontObject(on and GameFontHighlightSmall or GameFontNormalSmall)
    -- Label height as in PanelTemplates_SelectTab / DeselectTab for top tabs
    -- (selected -4, not selected -9), without disabling the tab.
    local text = t.Text or t:GetFontString()
    if type(text) == "table" and text.SetPoint then
        local function num(v, default) return type(v) == "number" and v or default end
        local y = on and num(t.selectedTextY, -3) or num(t.deselectedTextY, 2)
        if t.isTopTab ~= false then y = -y - 7 end -- our template is always a top tab
        local x = on and num(t.selectedTextX, 0) or num(t.deselectedTextX, 0)
        text:ClearAllPoints()
        text:SetPoint("CENTER", t, "CENTER", x, y)
    end
end

local function SetTabSelected(t, on)
    if t.NPBlizz then SetBlizzTabSelected(t, on) else Style(t, on) end
end

local function MakeButton(parent, label)
    local b = NP.TryCreateFrame("Button", nil, parent, "BackdropTemplate") or CreateFrame("Button", nil, parent)
    if b.SetBackdrop then
        b:SetBackdrop(BACKDROP)
    else
        local bg = b:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        b.NPBg = bg
    end
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    if label then
        fs:SetPoint("CENTER") -- small fixed buttons: < >
    else
        fs:SetPoint("LEFT", 6, 0) -- tabs: names that don't fit end in "..."
        fs:SetPoint("RIGHT", -6, 0)
    end
    fs:SetWordWrap(false)
    fs:SetJustifyH("CENTER")
    fs:SetText(label or "")
    b.NPText = fs
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", 3, -3)
    hl:SetPoint("BOTTOMRIGHT", -3, 3)
    hl:SetColorTexture(unpack(NP.Color.hover))
    Style(b, false)
    return b
end

-- Texture from NP.Art, or nil if the file is missing (SetTexture returns false).
local function ArtTexture(b, layer, path, texCoords)
    local t = b:CreateTexture(nil, layer)
    if t:SetTexture(path) == false then
        t:Hide()
        return nil
    end
    if texCoords then t:SetTexCoord(unpack(texCoords)) end
    t:SetAllPoints()
    return t
end

-- [+]: Blizzard's red panel button (UIPanelButtonTemplate) with a white "+";
-- else the same art by file; else a plain red button.
local function MakePlusButton(parent)
    local b = NP.TryCreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    if b then
        b:SetText("+")
        if b.SetNormalFontObject then
            b:SetNormalFontObject(GameFontHighlight)
            b:SetHighlightFontObject(GameFontHighlight)
        end
        local fs = b.GetFontString and b:GetFontString()
        if fs then fs:SetTextColor(unpack(NP.Color.white)) end
        return b
    end
    b = CreateFrame("Button", nil, parent)
    local coords = { 0, 0.625, 0, 0.6875 }
    local up = ArtTexture(b, "ARTWORK", NP.Art.redButtonUp, coords)
    if up then
        b:SetNormalTexture(up)
        local down = ArtTexture(b, "ARTWORK", NP.Art.redButtonDown, coords)
        if down then b:SetPushedTexture(down) end
        local hl = ArtTexture(b, "HIGHLIGHT", NP.Art.redButtonHighlight, coords)
        if hl then hl:SetBlendMode("ADD") end
    else
        local bg = b:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(unpack(NP.Color.red))
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.12)
    end
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("CENTER", 0, 1)
    fs:SetText("+")
    fs:SetTextColor(unpack(NP.Color.white))
    return b
end

-- Page-arrow button (spellbook prev/next art, disabled look at the ends); else text arrow.
local function MakeArrowButton(parent, which) -- which = "Prev" / "Next"
    local b = CreateFrame("Button", nil, parent)
    local up = ArtTexture(b, "ARTWORK", NP.Art["page" .. which .. "Up"])
    if up then
        b:SetNormalTexture(up)
        b:SetPushedTexture(NP.Art["page" .. which .. "Down"])
        b:SetDisabledTexture(NP.Art["page" .. which .. "Disabled"])
        b:SetHighlightTexture(NP.Art.pageHighlight, "ADD")
        b.NPWidth = ART_ARROW_W
        return b
    end
    b:Hide()
    b = MakeButton(parent, which == "Prev" and "<" or ">")
    b.NPTextArrow = true
    b.NPWidth = TEXT_ARROW_W
    return b
end

-- tooltip: getLines(self) returns a title and a list of { text, colour }
local function SetTooltip(b, getLines)
    if b.SetMotionScriptsWhileDisabled then b:SetMotionScriptsWhileDisabled(true) end
    b:SetScript("OnEnter", function(self)
        local title, lines = getLines(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(title)
        for _, l in ipairs(lines or {}) do
            local c = l[2] or NP.Color.white
            GameTooltip:AddLine(l[1], c[1], c[2], c[3], true)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function TextWidth(fs)
    local w
    if fs.GetUnboundedStringWidth then w = fs:GetUnboundedStringWidth() end
    return w or fs:GetStringWidth() or 0
end

-- Cut to `max` characters (UTF-8 safe: counts characters, not bytes) + "...".
local function CutChars(s, max)
    local count = 0
    for pos in s:gmatch("()[%z\1-\127\192-\255][\128-\191]*") do
        count = count + 1
        if count > max then
            local cut = s:sub(1, pos - 1)
            -- don't end on half of an escaped "||"
            local pipes = #(cut:match("|*$"))
            if pipes % 2 == 1 then cut = cut:sub(1, -2) end
            return cut .. "..."
        end
    end
    return s
end

-- First line of a note with text in it, for the tab tooltip; "(empty)" if none.
function NP.NotePreview(text)
    local line = (text or ""):match("[^\n]*%S[^\n]*")
    if not line then return "(empty)" end
    return CutChars(strtrim(line), TOOLTIP_CHARS)
end

-- Rename -----------------------------------------------------------------------

-- save: true = keep the typed name (Enter, click away, window closed), false = Esc.
local function FinishRename(save)
    local note = renaming
    if not note then return end
    renaming = nil
    local text = strtrim(renameBox:GetText() or "")
    renameBox:ClearFocus()
    renameBox:Hide()
    if save and text ~= "" then
        note.title = text
    end
    NP.RefreshTabs()
    NP.UpdateTitle()
end
NP.FinishRename = FinishRename

function NP.CancelRename()
    FinishRename(false)
end

function NP.StartRename(i)
    local note = NP.db.notes[i]
    local tab = tabs[i]
    if not note or not tab or not tab:IsShown() then return end
    if renaming then FinishRename(true) end
    renaming = note
    renameBox:ClearAllPoints()
    renameBox:SetPoint("LEFT", tab, "LEFT", 3, 0)
    renameBox:SetPoint("RIGHT", tab, "RIGHT", -3, 0)
    renameBox:SetHeight(20)
    renameBox:SetText(note.title)
    renameBox:Show()
    renameBox:SetFocus()
    renameBox:HighlightText()
end

local function CreateRenameBox(parent)
    local eb = NP.TryCreateFrame("EditBox", nil, parent, "BackdropTemplate") or CreateFrame("EditBox", nil, parent)
    if eb.SetBackdrop then
        eb:SetBackdrop(BACKDROP)
        eb:SetBackdropColor(unpack(NP.Color.renameBg))
        eb:SetBackdropBorderColor(unpack(NP.Color.gold))
    end
    eb:SetFontObject(GameFontHighlightSmall)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(MAX_TITLE)
    eb:SetTextInsets(5, 5, 0, 0)
    eb:SetFrameLevel(parent:GetFrameLevel() + 20)
    eb:Hide()
    eb:SetScript("OnEnterPressed", function() FinishRename(true) end)
    eb:SetScript("OnEscapePressed", function() FinishRename(false) end)
    eb:SetScript("OnEditFocusLost", function() FinishRename(true) end) -- click away saves
    eb:SetScript("OnTabPressed", function()
        if IsControlKeyDown() then
            FinishRename(true)
            NP.CycleNote(IsShiftKeyDown() and -1 or 1)
        end
    end)
    return eb
end

-- Note actions -----------------------------------------------------------------

function NP.AddNote()
    local notes = NP.db.notes
    if #notes >= NP.MAX_NOTES then
        NP.Print("you can have up to " .. NP.MAX_NOTES .. " notes.")
        return
    end
    NP.SaveText()
    notes[#notes + 1] = { title = NP.NewNoteTitle(notes, #notes + 1), text = "" }
    NP.ShowNote(#notes, true) -- already saved above
    NP.FocusText()
end

-- Ctrl+Tab / Ctrl+Shift+Tab: next / previous note, wrapping round.
function NP.CycleNote(dir)
    local db = NP.db
    local n = #db.notes
    if n < 2 then return end
    NP.ShowNote((db.current - 1 + dir) % n + 1)
    NP.FocusText()
end

function NP.MoveNote(i, dir)
    local db = NP.db
    local j = i + dir
    if not db.notes[i] or not db.notes[j] then return end
    NP.SaveText()
    db.notes[i], db.notes[j] = db.notes[j], db.notes[i]
    if db.current == i then
        db.current = j
    elseif db.current == j then
        db.current = i
    end
    NP.RefreshTabs(true)
end

local function DeleteNoteTable(note)
    local db = NP.db
    local i = IndexOf(note)
    if not i or #db.notes <= 1 then return end
    if renaming == note then FinishRename(false) end
    local wasCurrent = (i == db.current)
    if not wasCurrent then NP.SaveText() end
    table.remove(db.notes, i)
    if wasCurrent then
        NP.ShowNote(math.min(i, #db.notes), true) -- the text box held the deleted note
    else
        if db.current > i then db.current = db.current - 1 end
        NP.RefreshTabs(true)
    end
end

-- Always ask before deleting (empty notes too). The last note can't be deleted.
function NP.RequestDelete(i)
    local db = NP.db
    local note = db.notes[i]
    if not note then return end
    if #db.notes <= 1 then
        NP.Print("the last note can't be deleted.")
        return
    end
    if i == db.current then NP.SaveText() end
    pendingDelete = note
    local shown
    if StaticPopupDialogs and StaticPopup_Show then
        if not StaticPopupDialogs.NOTEPAD_DELETE_NOTE then
            StaticPopupDialogs.NOTEPAD_DELETE_NOTE = {
                text = "Are you sure you want to delete the note \"%s\"?\n%s",
                button1 = YES or "Yes",
                button2 = NO or "No",
                OnAccept = function()
                    local n = pendingDelete
                    pendingDelete = nil
                    if n then DeleteNoteTable(n) end
                end,
                OnCancel = function() pendingDelete = nil end,
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
                showAlert = true,
                preferredIndex = 3,
            }
        end
        local detail = (note.text == "") and "It is empty." or "Its text will be lost."
        local ok, dialog = pcall(StaticPopup_Show, "NOTEPAD_DELETE_NOTE", NP.GoldText(note.title), detail)
        shown = ok and dialog
    end
    if not shown then
        -- No popup available: Shift + right-click is the deliberate way to delete.
        if IsShiftKeyDown() then
            pendingDelete = nil
            DeleteNoteTable(note)
        else
            NP.Print("hold Shift and right-click the tab \"" .. NP.GoldText(note.title) .. "\" to delete it.")
        end
    end
end

-- Right-click menu (MenuUtil; only calls our own functions, nothing protected).
local function OpenMenu(owner, i)
    local note = NP.db.notes[i]
    if not note then return end
    local ok = false
    if MenuUtil and MenuUtil.CreateContextMenu then
        ok = pcall(MenuUtil.CreateContextMenu, owner, function(_, root)
            local notes = NP.db.notes
            local idx = IndexOf(note)
            if not idx then return end
            root:CreateTitle(note.title)
            root:CreateButton("Rename", function()
                local j = IndexOf(note)
                if j then NP.StartRename(j) end
            end)
            local left = root:CreateButton("Move left", function()
                local j = IndexOf(note)
                if j then NP.MoveNote(j, -1) end
            end)
            if idx <= 1 and left and left.SetEnabled then left:SetEnabled(false) end
            local right = root:CreateButton("Move right", function()
                local j = IndexOf(note)
                if j then NP.MoveNote(j, 1) end
            end)
            if idx >= #notes and right and right.SetEnabled then right:SetEnabled(false) end
            local del = root:CreateButton("Delete", function()
                local j = IndexOf(note)
                if j then NP.RequestDelete(j) end
            end)
            if #notes <= 1 and del and del.SetEnabled then del:SetEnabled(false) end
        end)
    end
    if not ok then
        NP.StartRename(i) -- no menu: right-click renames, Shift + right-click deletes
    end
end

-- Tab row ------------------------------------------------------------------------

-- Blizzard's top tab (only if it has all the parts we use), else our own box.
local function NewTabButton()
    if PanelTemplates_TabResize then
        local t = NP.TryCreateFrame("Button", nil, row, TAB_TEMPLATE)
        if t then
            local complete = true
            for _, key in ipairs(TAB_PARTS) do
                if type(t[key]) ~= "table" then complete = false break end
            end
            if complete then
                t.NPBlizz = true
                t.NPText = t.Text
                return t
            end
            t:Hide()
        end
    end
    return MakeButton(row, nil)
end

local function CreateTab(i)
    local t = NewTabButton()
    t:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    t:SetScript("OnClick", function(self, button)
        local idx = self.NPIndex
        if button == "RightButton" then
            if IsShiftKeyDown() then NP.RequestDelete(idx) else OpenMenu(self, idx) end
        elseif idx ~= NP.db.current then
            NP.ShowNote(idx)
        end
    end)
    t:SetScript("OnDoubleClick", function(self, button)
        if button == "LeftButton" then NP.StartRename(self.NPIndex) end
    end)
    SetTooltip(t, function(self)
        local note = NP.db.notes[self.NPIndex]
        if not note then return "", nil end
        local C = NP.Color
        return note.title, {
            { NP.NotePreview(note.text), C.white },
            { "Double-click: rename", C.grey },
            { "Right-click: rename, move, delete", C.grey },
        }
    end)
    tabs[i] = t
    return t
end

-- Full-name width of a tab.
local function MeasureTab(t)
    if t.NPBlizz then
        PanelTemplates_TabResize(t, 0)
        return math.max(TAB_MIN_W, math.ceil(t:GetWidth() or 0))
    end
    return math.max(TAB_MIN_W, math.ceil(TextWidth(t.NPText) + TAB_PAD))
end

local function SizeTab(t, w, h)
    if t.NPBlizz then
        PanelTemplates_TabResize(t, 0, w)
        t:SetHeight(h)
    else
        t:SetSize(w, h)
    end
end

-- Lay the tabs out. ensureCurrent: scroll so the open tab is visible.
function NP.RefreshTabs(ensureCurrent)
    if not row then return end
    local db = NP.db
    local notes = db.notes
    local n = #notes

    for i = 1, n do
        local t = tabs[i] or CreateTab(i)
        t.NPIndex = i
        t.NPText:SetText(notes[i].title)
        t.NPWidth = MeasureTab(t) -- as wide as the whole name; capped to the tab area below
        SetTabSelected(t, i == db.current)
    end
    for i = n + 1, #tabs do tabs[i]:Hide() end
    plusBtn:SetAlpha(n >= NP.MAX_NOTES and 0.4 or 1) -- dimmed at the most notes

    local rowW, rowH = row:GetWidth(), row:GetHeight()
    if not rowW or rowW <= 0 then return end

    -- last tab index that fits from `from` in `avail` pixels (always at least one)
    local function LastFitting(from, avail)
        local x, last = 0, from - 1
        for i = from, n do
            local w = tabs[i].NPWidth
            if i > from and x + w > avail then break end
            x = x + w + GAP
            last = i
        end
        return last
    end

    local full = rowW - PLUS_W - GAP
    local overflow = LastFitting(1, full) < n
    local arrowsW = leftBtn.NPWidth + rightBtn.NPWidth + 2 * GAP
    local avail = overflow and (full - arrowsW) or full
    if not overflow then first = 1 end
    first = Clamp(first, 1, n)
    if ensureCurrent and overflow then
        if db.current < first then first = db.current end
        while first < db.current and LastFitting(first, avail) < db.current do
            first = first + 1
        end
    end
    while first > 1 and LastFitting(first - 1, avail) >= n do
        first = first - 1 -- no empty space at the end
    end
    local last = LastFitting(first, avail)

    local x = 0
    for i = 1, n do
        local t = tabs[i]
        if i >= first and i <= last then
            local w = math.min(t.NPWidth, math.max(TAB_MIN_W, avail))
            t:Show() -- show first: the Blizzard tab resizes itself in OnShow
            SizeTab(t, w, rowH)
            t:ClearAllPoints()
            t:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", x, 0)
            x = x + w + GAP
        else
            t:Hide()
        end
    end

    leftBtn:SetShown(overflow)
    rightBtn:SetShown(overflow)
    if overflow then
        leftBtn:SetEnabled(first > 1)
        rightBtn:SetEnabled(last < n)
        if leftBtn.NPTextArrow then Style(leftBtn, false, first <= 1) end
        if rightBtn.NPTextArrow then Style(rightBtn, false, last >= n) end
    end

    if renaming then
        local i = IndexOf(renaming)
        if not i or not tabs[i]:IsShown() then FinishRename(true) end
    end
end

local function Scroll(delta)
    first = first + delta
    NP.RefreshTabs(false)
end

-- For tests and debugging: the row's widgets.
function NP.TabWidgets()
    return { row = row, plus = plusBtn, left = leftBtn, right = rightBtn, tabs = tabs, rename = renameBox }
end

function NP.CreateTabs(f, inset, height)
    if row then return end
    row = CreateFrame("Frame", nil, f)
    -- Blizzard tabs overlap the inset's top edge by 3 px (like Blizzard's own top tabs);
    -- the boxes keep a 2 px gap
    local y = (height == BLIZZ_TAB_H) and -3 or 2
    row:SetPoint("BOTTOMLEFT", inset, "TOPLEFT", 0, y)
    row:SetPoint("BOTTOMRIGHT", inset, "TOPRIGHT", 0, y)
    row:SetHeight(height)
    row:EnableMouseWheel(true)
    row:SetScript("OnMouseWheel", function(_, delta) Scroll(-delta) end)
    row:SetScript("OnSizeChanged", function() NP.RefreshTabs(true) end)
    row:SetScript("OnShow", function() NP.RefreshTabs(true) end)
    NP.tabRow = row

    local btnH = math.min(height, BOX_TAB_H)
    plusBtn = MakePlusButton(row)
    plusBtn:SetSize(PLUS_W, btnH)
    plusBtn:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, math.floor((height - btnH) / 2)) -- centred in the row
    plusBtn:SetScript("OnClick", function() NP.AddNote() end)
    SetTooltip(plusBtn, function()
        if #NP.db.notes >= NP.MAX_NOTES then
            return "New note", { { "You already have " .. NP.MAX_NOTES .. " notes (the most)." } }
        end
        return "New note"
    end)

    local arrowTip = function()
        return "Scroll tabs", { { "(mouse wheel works too)", NP.Color.grey } }
    end
    rightBtn = MakeArrowButton(row, "Next")
    rightBtn:SetSize(rightBtn.NPWidth, btnH)
    rightBtn:SetPoint("BOTTOMRIGHT", plusBtn, "BOTTOMLEFT", -GAP, 0)
    rightBtn:SetScript("OnClick", function() Scroll(1) end)
    SetTooltip(rightBtn, arrowTip)

    leftBtn = MakeArrowButton(row, "Prev")
    leftBtn:SetSize(leftBtn.NPWidth, btnH)
    leftBtn:SetPoint("BOTTOMRIGHT", rightBtn, "BOTTOMLEFT", -GAP, 0)
    leftBtn:SetScript("OnClick", function() Scroll(-1) end)
    SetTooltip(leftBtn, arrowTip)

    renameBox = CreateRenameBox(row)
    NP.RefreshTabs(true)
end
