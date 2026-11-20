-- Note Pad: tab row (one tab per note: add, switch, rename, move, delete)
local _, NP = ...

local TAB_MIN_W, TAB_PAD, GAP = 50, 20, 2
local PLUS_W = 32            -- [+] a bit wider than square: the red button art is drawn wide
local ART_ARROW_W, TEXT_ARROW_W = 24, 18
local BLIZZ_TAB_H, BOX_TAB_H = 32, 24
local MAX_TITLE = 24
local RENAME_H = 18 -- rename box height, centred on the tab label
local TOOLTIP_CHARS = 40     -- first line of the note shown in the tab tooltip
local TAB_TEMPLATE = NP.Templates.tab
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
    for i, n in ipairs(NP.Book().notes) do
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
local function num(v, default) return type(v) == "number" and v or default end

-- Where a tab's label sits (offset of its centre from the tab's centre): for Blizzard
-- tabs as in PanelTemplates_SelectTab / DeselectTab for top tabs (selected -4, not -9).
local function LabelOffset(t, on)
    if not t.NPBlizz then return 0, 0 end
    local y = on and num(t.selectedTextY, -3) or num(t.deselectedTextY, 2)
    if t.isTopTab ~= false then y = -y - 7 end -- our template is always a top tab
    local x = on and num(t.selectedTextX, 0) or num(t.deselectedTextX, 0)
    return x, y
end

-- The template's HIGHLIGHT layer is the unselected tab art (additive, alpha 0.4), so on
-- the open tab it would show the unselected look on mouse-over. Blizzard avoids that by
-- disabling the open tab; we keep it enabled, so we fade its highlight pieces instead.
local HIGHLIGHT_PARTS = { "LeftHighlight", "MiddleHighlight", "RightHighlight" }

local function SetBlizzTabSelected(t, on)
    t.Left:SetShown(not on)
    t.Middle:SetShown(not on)
    t.Right:SetShown(not on)
    t.LeftActive:SetShown(on)
    t.MiddleActive:SetShown(on)
    t.RightActive:SetShown(on)
    for _, k in ipairs(HIGHLIGHT_PARTS) do
        local h = t[k]
        if type(h) == "table" and h.SetAlpha then
            if not t.NPHighlightAlpha and h.GetAlpha then t.NPHighlightAlpha = num(h:GetAlpha(), 0.4) end
            h:SetAlpha(on and 0 or (t.NPHighlightAlpha or 0.4))
        end
    end
    t:SetNormalFontObject(on and GameFontHighlightSmall or GameFontNormalSmall)
    t.NPSelected = on
    -- label height without disabling the tab
    local text = t.Text or t:GetFontString()
    if type(text) == "table" and text.SetPoint then
        local x, y = LabelOffset(t, on)
        text:ClearAllPoints()
        text:SetPoint("CENTER", t, "CENTER", x, y)
    end
end

local function SetTabSelected(t, on)
    if t.NPBlizz then SetBlizzTabSelected(t, on) else Style(t, on) end
end

local function MakeButton(parent, label)
    local b = NP.TryCreateFrame("Button", nil, parent, NP.Templates.backdrop) or CreateFrame("Button", nil, parent)
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
    local b = NP.TryCreateFrame("Button", nil, parent, NP.Templates.button)
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
    b.NPOwnArt = true -- no disabled art: faded at the most notes
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

function NP.StartRename(i)
    local note = NP.Book().notes[i]
    local tab = tabs[i]
    if not note or not tab or not tab:IsShown() then return end
    if renaming then FinishRename(true) end
    renaming = note
    -- exactly over the label: same height, same font, centred, so the name doesn't jump
    local selected = (i == NP.Book().current)
    local _, y = LabelOffset(tab, selected)
    renameBox:ClearAllPoints()
    renameBox:SetPoint("LEFT", tab, "LEFT", 3, y)
    renameBox:SetPoint("RIGHT", tab, "RIGHT", -3, y)
    renameBox:SetHeight(RENAME_H)
    renameBox:SetFontObject((selected or not tab.NPBlizz) and GameFontHighlightSmall or GameFontNormalSmall)
    renameBox:SetText(note.title)
    renameBox:Show()
    renameBox:SetFocus()
    renameBox:HighlightText()
end

local function CreateRenameBox(parent)
    local eb = NP.TryCreateFrame("EditBox", nil, parent, NP.Templates.backdrop) or CreateFrame("EditBox", nil, parent)
    if eb.SetBackdrop then
        eb:SetBackdrop(BACKDROP)
        eb:SetBackdropColor(unpack(NP.Color.renameBg))
        eb:SetBackdropBorderColor(unpack(NP.Color.gold))
    end
    eb:SetFontObject(GameFontHighlightSmall)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(MAX_TITLE)
    eb:SetTextInsets(5, 5, 0, 0)
    if eb.SetJustifyH then eb:SetJustifyH("CENTER") end -- tab labels are centred too
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

function NP.LimitText()
    return NP.MAX_NOTES .. " notes is the most. Delete one to add another."
end

-- kind: nil = text note, "checklist" = checklist.
function NP.AddNote(kind)
    local notes = NP.Book().notes
    if #notes >= NP.MAX_NOTES then
        NP.Print(NP.LimitText())
        return
    end
    NP.SaveText()
    local note
    if kind == "checklist" then
        note = { title = NP.NewNoteTitle(notes, #notes + 1, "List"), kind = "checklist", items = {} }
        NP.UpdateChecklistMirror(note)
    else
        note = { title = NP.NewNoteTitle(notes, #notes + 1), text = "" }
    end
    notes[#notes + 1] = note
    NP.ShowNote(#notes, true) -- already saved above
    NP.FocusText()
end

-- Turn note i into a checklist (one line per text line) or back into a text note
-- ("[x] " / "[ ] " in front of each line). Blank lines are left out.
function NP.ConvertNote(i)
    local note = NP.Book().notes[i]
    if not note then return end
    NP.SaveText()
    if NP.FinishLineEdit then NP.FinishLineEdit(true) end
    if NP.IsChecklist(note) then
        NP.UpdateChecklistMirror(note)
        -- list unchanged since it was made from a note: that note's exact text comes back
        -- (blank lines, spaces, "[X]" ...); else `text` already holds every line
        if type(note.noteText) == "string" and note.noteMirror == note.mirrorHash then
            note.text = note.noteText
        end
        note.kind, note.items, note.mirrorHash, note.noteText, note.noteMirror = nil, nil, nil, nil, nil
    else
        local items = NP.ChecklistTextToItems(note.text)
        if #items > NP.CHECKLIST_MAX_LINES then
            NP.Print("A checklist can have up to " .. NP.CHECKLIST_MAX_LINES .. " lines; \"" ..
                NP.GoldText(note.title) .. "\" has " .. #items .. ".")
            return
        end
        local original = note.text
        note.kind, note.items = "checklist", items
        NP.UpdateChecklistMirror(note)
        if note.text ~= original then
            -- the list can't show blank lines or spacing: keep the exact text until the list changes
            note.noteText, note.noteMirror = original, note.mirrorHash
            NP.Print("Turn it back into a note before changing the list to get the exact text back (blank lines, spacing).")
        end
    end
    if i == NP.Book().current then
        NP.ShowNote(i, true) -- saved above
    else
        NP.RefreshTabs()
    end
end

-- Ctrl+Tab / Ctrl+Shift+Tab: next / previous note, wrapping round.
function NP.CycleNote(dir)
    local db = NP.Book()
    local n = #db.notes
    if n < 2 then return end
    NP.ShowNote((db.current - 1 + dir) % n + 1)
    NP.FocusText()
end

-- Move note `from` to place `to` (1 .. #notes); the open note stays open. Returns true if moved.
function NP.MoveNoteTo(from, to)
    local db = NP.Book()
    local notes = db.notes
    if not notes[from] or type(to) ~= "number" or to ~= to then return false end
    to = Clamp(math.floor(to), 1, #notes)
    if to == from then return false end
    if renaming then FinishRename(true) end
    NP.SaveText()
    if NP.FinishLineEdit then NP.FinishLineEdit(true) end
    local open = notes[db.current]
    table.insert(notes, to, table.remove(notes, from))
    for i, n in ipairs(notes) do
        if n == open then db.current = i break end
    end
    NP.RefreshTabs(true)
    return true
end

function NP.MoveNote(i, dir)
    return NP.MoveNoteTo(i, i + dir)
end

local function DeleteNoteTable(note)
    local db = NP.Book()
    local i = IndexOf(note)
    if not i or #db.notes <= 1 then return end
    if renaming == note then FinishRename(false) end
    local wasCurrent = (i == db.current)
    NP.SaveText() -- the open note's text (if this is it, it's kept for /np undo)
    if NP.FinishLineEdit then NP.FinishLineEdit(true) end
    table.remove(db.notes, i)
    NP.PushDeletedNote(note, i)
    if wasCurrent then
        NP.ShowNote(math.min(i, #db.notes), true) -- the text box held the deleted note
    else
        if db.current > i then db.current = db.current - 1 end
        NP.RefreshTabs(true)
    end
    NP.Print("Deleted \"" .. NP.GoldText(note.title) .. "\". Type /np undo to bring it back.")
end

-- Move or copy a note to the other notebook -------------------------------------------

-- Deep copy of a note (title, text, checklist items ...): the copy shares no tables.
local function CopyNote(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = CopyNote(x) end
    return t
end

-- Plain data step (the self-test runs it on copies): note i of fromBook goes to the end of
-- toBook (copy = a deep copy, else moved). fresh = toBook was just made: its starting empty
-- "Note 1" is replaced. Returns true, or false + "missing" | "full" | "last".
function NP.TransferNote(fromBook, i, toBook, copy, fresh)
    local note = fromBook and fromBook.notes and fromBook.notes[i]
    if not note or type(toBook) ~= "table" or type(toBook.notes) ~= "table" then return false, "missing" end
    if not copy and #fromBook.notes <= 1 then return false, "last" end
    local only = toBook.notes[1]
    local replace = fresh and #toBook.notes == 1 and not NP.IsChecklist(only)
        and (only.text == nil or only.text == "")
    if not replace and #toBook.notes >= NP.MAX_NOTES then return false, "full" end
    local sent = copy and CopyNote(note) or note
    -- add first, remove after: an error half-way can't lose the note
    if replace then
        toBook.notes[1] = sent
        toBook.current = 1
    else
        toBook.notes[#toBook.notes + 1] = sent
    end
    if not copy then
        table.remove(fromBook.notes, i)
        local cur = tonumber(fromBook.current) or 1
        if cur > i then cur = cur - 1 end
        fromBook.current = Clamp(cur, 1, #fromBook.notes)
    end
    return true
end

-- "Account notes" / "<Name>'s notes" (chat and menus).
local function BookLabel(book)
    if book == NP.db then return "account notes" end
    return (NP.charName or "Character") .. "'s notes"
end

-- The notebook a tab's note would go to, its label; nil while the character isn't known.
function NP.OtherBookLabel()
    if not NP.charKey then NP.UpdateCharKey() end
    if not NP.charKey then return nil end
    return BookLabel(NP.UsingCharBook() and NP.db or "char")
end

-- Tab menu: move (copy = false) or copy note i of the open notebook to the other one.
function NP.SendNoteToOtherBook(i, copy)
    local from = NP.Book()
    local note = from.notes[i]
    if not note then return false end
    if not NP.charKey then NP.UpdateCharKey() end
    if not NP.charKey then
        NP.Print("The character's name isn't known yet. Try again in a moment.")
        return false
    end
    if not copy and #from.notes <= 1 then
        NP.Print("The last note can't be moved. Copy it instead.")
        return false
    end
    if renaming then FinishRename(true) end
    NP.SaveText() -- the open note's text goes with it
    if NP.FinishLineEdit then NP.FinishLineEdit(true) end
    local to, fresh = NP.OtherBook(), false
    if not to then
        to = NP.CharBook(true) -- made now (not opened: `use` stays false)
        fresh = true
    end
    local wasCurrent = (i == from.current)
    local ok, why = NP.TransferNote(from, i, to, copy, fresh)
    local where = BookLabel(to)
    if not ok then
        if why == "full" then
            NP.Print("The " .. where .. " already have " .. NP.MAX_NOTES .. " notes. Delete one there first.")
        end
        return false
    end
    if not copy and wasCurrent then
        NP.ShowNote(from.current, true) -- saved above; the text box held the moved note
    else
        NP.RefreshTabs(true)
    end
    if NP.RefreshSearch then NP.RefreshSearch() end
    NP.Print((copy and "Copied \"" or "Moved \"") .. NP.GoldText(note.title) .. "\" to " .. where
        .. ". Switch notebooks in the cog menu.")
    return true
end

-- Always ask before deleting (empty notes too). The last note can't be deleted.
function NP.RequestDelete(i)
    local db = NP.Book()
    local note = db.notes[i]
    if not note then return end
    if #db.notes <= 1 then
        NP.Print("The last note can't be deleted.")
        return
    end
    if i == db.current then NP.SaveText() end
    local shown
    if StaticPopupDialogs and StaticPopup_Show then
        if not StaticPopupDialogs.NOTEPAD_DELETE_NOTE then
            StaticPopupDialogs.NOTEPAD_DELETE_NOTE = {
                text = "Delete the note \"%s\"?\n%s",
                button1 = DELETE or "Delete",
                button2 = CANCEL or "Cancel",
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
        local detail = (note.text == "") and "It is empty." or "/np undo brings it back."
        -- StaticPopup_Show cancels an open delete popup first (its OnCancel clears
        -- pendingDelete), so the note to delete is set after it, never before.
        local ok, dialog = pcall(StaticPopup_Show, "NOTEPAD_DELETE_NOTE", NP.GoldText(note.title), detail)
        shown = ok and dialog
        if shown then pendingDelete = note end
    end
    if not shown then
        -- No popup available: Shift + right-click is the deliberate way to delete.
        pendingDelete = nil
        if IsShiftKeyDown() then
            DeleteNoteTable(note)
        else
            NP.Print("Hold Shift and right-click the tab \"" .. NP.GoldText(note.title) .. "\" to delete it.")
        end
    end
end

-- Right-click menu (MenuUtil; only calls our own functions, nothing protected).
local function OpenMenu(owner, i)
    local note = NP.Book().notes[i]
    if not note then return end
    local ok = false
    if MenuUtil and MenuUtil.CreateContextMenu then
        ok = pcall(MenuUtil.CreateContextMenu, owner, function(_, root)
            local notes = NP.Book().notes
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
            root:CreateButton(NP.IsChecklist(note) and "Turn into note" or "Turn into checklist", function()
                local j = IndexOf(note)
                if j then NP.ConvertNote(j) end
            end)
            if NP.IsChecklist(note) and NP.ChecklistUntickAll then
                local untick = root:CreateButton("Untick all", function() NP.ChecklistUntickAll(note) end)
                if NP.ChecklistCounts(note) == 0 and untick and untick.SetEnabled then untick:SetEnabled(false) end
            end
            local other = NP.OtherBookLabel()
            if other then -- hidden while the character's name isn't known
                local move = root:CreateButton("Move to " .. other, function()
                    local j = IndexOf(note)
                    if j then NP.SendNoteToOtherBook(j, false) end
                end)
                if #notes <= 1 and move and move.SetEnabled then move:SetEnabled(false) end
                root:CreateButton("Copy to " .. other, function()
                    local j = IndexOf(note)
                    if j then NP.SendNoteToOtherBook(j, true) end
                end)
            end
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

-- Right-click on [+]: new note or new checklist. No MenuUtil: a checklist straight away
-- (left-click already makes a note).
local function OpenNewMenu(owner)
    local ok = false
    if MenuUtil and MenuUtil.CreateContextMenu then
        ok = pcall(MenuUtil.CreateContextMenu, owner, function(_, root)
            root:CreateButton("New note", function() NP.AddNote() end)
            root:CreateButton("New checklist", function() NP.AddNote("checklist") end)
            local label = NP.UndoLabel and NP.UndoLabel()
            if label then root:CreateButton(label, function() NP.Undo() end) end
        end)
    end
    if not ok then NP.AddNote("checklist") end
end

-- Drag a tab to move it ------------------------------------------------------------
-- The tab follows the cursor along the row (a bit see-through), a gold line shows where it
-- will go, and letting go moves the note there (NP.MoveNoteTo). Holding it over a page arrow
-- turns the page every PAGE_WAIT s. Clicks still work: WoW starts a drag only after the mouse
-- has moved a few pixels with the button held.
local PAGE_WAIT = 0.4
local DRAG_ALPHA = 0.7
local drag          -- { note, tab, offset, wait, slot } while a tab is dragged
local dragFrame     -- over the row, shown (and updating) only while dragging; holds dragLine
local dragLine
local justDragged = false -- the OnClick that comes with the drag's mouse-up is not a click
local Scroll        -- page the row (below)

local function CursorX()
    local x = GetCursorPosition()
    local s = row:GetEffectiveScale()
    return (type(x) == "number" and s and s > 0) and x / s or 0
end

-- Where the dragged tab would go: the slot before tab k (k = n + 1: after the last).
local function DropSlot(x)
    local n = #NP.Book().notes
    local lastShown
    for i = 1, n do
        local t = tabs[i]
        if t and t ~= drag.tab and t:IsShown() then
            local l, w = t:GetLeft(), t:GetWidth()
            if l and w and x < l + w / 2 then return i end
            lastShown = i
        end
    end
    return lastShown and (lastShown + 1) or (IndexOf(drag.note) or 1)
end

local function SlotToIndex(slot, from)
    return (slot > from) and (slot - 1) or slot
end

local function PlaceDragLine(slot)
    local rowL = row:GetLeft()
    local t = tabs[slot]
    local x
    if t and t ~= drag.tab and t:IsShown() and t:GetLeft() then
        x = t:GetLeft() - GAP / 2
    else
        for i = slot - 1, 1, -1 do
            local p = tabs[i]
            if p and p ~= drag.tab and p:IsShown() and p:GetRight() then x = p:GetRight() + GAP / 2 break end
        end
    end
    if not x or not rowL then dragLine:Hide() return end
    dragLine:ClearAllPoints()
    dragLine:SetPoint("TOP", row, "TOPLEFT", x - rowL, 0)
    dragLine:SetPoint("BOTTOM", row, "BOTTOMLEFT", x - rowL, 0)
    dragLine:Show()
end

local function EndDrag(drop)
    if not drag then return end
    local d = drag
    drag = nil
    dragFrame:Hide()
    d.tab:SetAlpha(1)
    d.tab:SetFrameLevel(d.level)
    justDragged = true
    C_Timer.After(0, function() justDragged = false end)
    local from = IndexOf(d.note)
    if drop and from and d.slot and NP.MoveNoteTo(from, SlotToIndex(d.slot, from)) then return end
    NP.RefreshTabs(false) -- not moved: the tab goes back to its place
end

local function DragUpdate(_, elapsed)
    if not drag then return end
    if not row:IsVisible() then return EndDrag(false) end
    -- the button was let go somewhere OnDragStop doesn't see (e.g. the tab was paged away)
    if type(IsMouseButtonDown) == "function" and not IsMouseButtonDown("LeftButton") then return EndDrag(true) end
    local x = CursorX()
    local rowL, rowW, w = row:GetLeft(), row:GetWidth(), drag.tab:GetWidth()
    if rowL and rowW and w then
        local left = Clamp(x - drag.offset - rowL, 0, math.max(0, rowW - PLUS_W - GAP - w))
        drag.tab:ClearAllPoints()
        drag.tab:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", left, 0)
    end
    -- over a page arrow: turn the page after a short wait
    local arrow
    for _, b in ipairs({ leftBtn, rightBtn }) do
        if b:IsShown() and b:IsEnabled() and b:IsMouseOver() then arrow = b end
    end
    if arrow then
        drag.wait = drag.wait + (elapsed or 0)
        if drag.wait >= PAGE_WAIT then
            drag.wait = 0
            Scroll(arrow == leftBtn and -1 or 1)
        end
    else
        drag.wait = 0
    end
    drag.slot = DropSlot(x)
    PlaceDragLine(drag.slot)
end

local function TabDragStart(self)
    local note = NP.Book().notes[self.NPIndex]
    if not note or #NP.Book().notes < 2 then return end
    if renaming then FinishRename(true) end
    if GameTooltip then GameTooltip:Hide() end
    local l = self:GetLeft()
    drag = { note = note, tab = self, offset = l and (CursorX() - l) or 0, wait = 0, level = self:GetFrameLevel() }
    self:SetAlpha(DRAG_ALPHA)
    self:SetFrameLevel(dragFrame:GetFrameLevel() - 1) -- over the other tabs, under the line
    dragFrame:Show()
    DragUpdate(dragFrame, 0)
end

local function TabDragStop()
    if drag then
        DragUpdate(dragFrame, 0) -- the slot where the mouse is now
        EndDrag(true)
    end
end

function NP.IsDraggingTab() return drag ~= nil end

local function CreateDragFrame()
    dragFrame = CreateFrame("Frame", nil, row)
    dragFrame:SetAllPoints(row)
    dragFrame:SetFrameLevel(row:GetFrameLevel() + 15)
    dragFrame:Hide()
    dragFrame:SetScript("OnUpdate", DragUpdate)
    dragFrame:SetScript("OnHide", function() if drag then EndDrag(false) end end)
    dragLine = dragFrame:CreateTexture(nil, "OVERLAY")
    dragLine:SetWidth(2)
    dragLine:SetColorTexture(unpack(NP.Color.gold))
    dragLine:Hide()
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
    t:RegisterForDrag("LeftButton")
    t:SetScript("OnDragStart", TabDragStart)
    t:SetScript("OnDragStop", TabDragStop)
    t:HookScript("OnMouseDown", function() justDragged = false end)
    t:SetScript("OnClick", function(self, button)
        local idx = self.NPIndex
        if justDragged and button == "LeftButton" then return end -- the end of a drag, not a click
        if button == "RightButton" then
            if IsShiftKeyDown() then NP.RequestDelete(idx) else OpenMenu(self, idx) end
        elseif idx ~= NP.Book().current then
            NP.ShowNote(idx)
        end
    end)
    t:SetScript("OnDoubleClick", function(self, button)
        if button == "LeftButton" then NP.StartRename(self.NPIndex) end
    end)
    SetTooltip(t, function(self)
        local note = NP.Book().notes[self.NPIndex]
        if not note then return "", nil end
        local C = NP.Color
        local hints = {
            { "Double-click: rename", C.hint },
            { "Drag: move the tab", C.hint },
            { "Right-click: rename, move, delete", C.hint },
            { "Shift + right-click: delete", C.hint },
            { "Ctrl+Tab while typing: next note", C.hint },
        }
        local lines
        if NP.IsChecklist(note) then
            local done, total = NP.ChecklistCounts(note)
            local firstLine = note.items[1] and NP.NotePreview(NP.PlainText(note.items[1].text)) or "(empty)"
            lines = { { ("Checklist: %d / %d done"):format(done, total), C.gold }, { firstLine, C.white } }
        else
            lines = { { NP.NotePreview(note.text), C.white } }
        end
        for _, h in ipairs(hints) do lines[#lines + 1] = h end
        return note.title, lines
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

-- [+] disabled at the most notes: Blizzard's grey disabled button and a grey "+"
-- (own art has no disabled look: faded instead). Its tooltip still shows (SetTooltip).
local function UpdatePlus(n)
    local on = n < NP.MAX_NOTES
    plusBtn:SetEnabled(on)
    local fs = plusBtn.GetFontString and plusBtn:GetFontString()
    if fs then fs:SetTextColor(unpack(on and NP.Color.white or NP.Color.grey)) end
    if plusBtn.NPOwnArt then plusBtn:SetAlpha(on and 1 or 0.4) end
end

local measured = -1 -- number of notes at the last full pass (names, widths, selection)

-- Lay the tabs out. ensureCurrent: scroll so the open tab is visible.
-- layoutOnly: only the row's width changed (resizing): reuse the measured widths.
function NP.RefreshTabs(ensureCurrent, layoutOnly)
    if not row then return end
    local db = NP.Book()
    local notes = db.notes
    local n = #notes

    if not (layoutOnly and measured == n) then
        for i = 1, n do
            local t = tabs[i] or CreateTab(i)
            t.NPIndex = i
            t.NPText:SetText(notes[i].title)
            t.NPWidth = MeasureTab(t) -- as wide as the whole name; capped to the tab area below
            SetTabSelected(t, i == db.current)
        end
        for i = n + 1, #tabs do tabs[i]:Hide() end
        UpdatePlus(n)
        measured = n
    end

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
        elseif drag and drag.tab == t then
            t:Show() -- paged away while dragged: it stays under the cursor (DragUpdate places it)
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

Scroll = function(delta)
    first = first + delta
    NP.RefreshTabs(false)
end

-- For tests and debugging: the row's widgets.
function NP.TabWidgets()
    return { row = row, plus = plusBtn, left = leftBtn, right = rightBtn, tabs = tabs, rename = renameBox,
        drag = dragFrame, dragLine = dragLine }
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
    row:SetScript("OnSizeChanged", function() NP.RefreshTabs(true, true) end) -- every frame while resizing: layout only
    row:SetScript("OnShow", function() NP.RefreshTabs(true) end)
    NP.tabRow = row

    local btnH = math.min(height, BOX_TAB_H)
    plusBtn = MakePlusButton(row)
    plusBtn:SetSize(PLUS_W, btnH)
    plusBtn:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, math.floor((height - btnH) / 2)) -- centred in the row
    if plusBtn.RegisterForClicks then plusBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    plusBtn:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            OpenNewMenu(self)
        elseif IsShiftKeyDown() then
            NP.AddNote("checklist")
        else
            NP.AddNote()
        end
    end)
    SetTooltip(plusBtn, function()
        if #NP.Book().notes >= NP.MAX_NOTES then
            return "New note", { { NP.LimitText() } }
        end
        return "New note", {
            { "Shift-click: new checklist", NP.Color.hint },
            { "Right-click: more", NP.Color.hint },
        }
    end)

    local arrowTip = function()
        return "More tabs", { { "Or use the mouse wheel", NP.Color.hint } }
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
    CreateDragFrame()
    NP.RefreshTabs(true)
end
