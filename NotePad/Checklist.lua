-- Note Pad: checklist view (a note with kind = "checklist"; data helpers are in Core.lua)
-- Lines with tick boxes; items go in by Shift-click (post-hook on Blizzard's link insert),
-- by dragging them from the bags (GetCursorInfo + ClearCursor only), or typed.
local _, NP = ...

local ROW_H_MIN = 22    -- row height at the default text size (12 px lines)
local ROW_PAD = 10      -- row height = text size + this (never under ROW_H_MIN)
local rowH = ROW_H_MIN  -- follows the text size setting (NP.ChecklistApplyFont)
local CHECK_SIZE = 24
local ICON_SIZE = 16
local TOP_H = 32        -- add box row
local BOTTOM_H = 32     -- counter + Clear ticked

-- The lines' font (Settings.lua makes NotePadListFont; GameFontHighlight until then).
local function ListFont()
    return NP.ListFont and NP.ListFont() or GameFontHighlight
end

local view, addBox, addBtn, scroll, content, counter, clearBtn, emptyText, lineEdit
local rows = {}
local shownNote          -- the checklist note the view shows (nil = hidden)
local editing            -- { note = , item = } while a line is edited inline
local pendingClear       -- note waiting for the "Clear ticked" answer
local ownInsert = false  -- true while we send a link to chat ourselves
local hookedName         -- which Blizzard function the link hook is on
local secretSkips = 0    -- links skipped because they were secret values
local used = {}          -- which template / fallback each part uses (self-test)
local scrollPlace = setmetatable({}, { __mode = "k" }) -- scroll offset per checklist, this session

local function Clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- issecretvalue (newer clients): never compare or store a secret. A failing check counts as secret.
local function IsSecret(v)
    local f = issecretvalue
    if type(f) ~= "function" then return false end
    local ok, s = pcall(f, v)
    return (not ok) or s == true
end
NP.IsSecretValue = IsSecret

local function PlayCheckSound(on)
    if PlaySound and SOUNDKIT then
        local id = on and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF
        if id then pcall(PlaySound, id) end
    end
end

-- Item icon of the first item link in a line (instant info: always cached), or nil.
local function ItemIcon(text)
    local id = tonumber(text:match("|Hitem:(%d+)"))
    if not id then return nil end
    local get = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if type(get) ~= "function" then return nil end
    local ok, _, _, _, _, icon = pcall(get, id)
    if ok and icon and not IsSecret(icon) then return icon end
    return nil
end

-- The first hyperlink in a line ("item:123:..."), for the tooltip.
local function FirstLink(text)
    return text:match("|H(%a+:[^|]*)|h")
end

-- How many of the line's first item you have. Returns all, bags, bank, warband bank (banks as of
-- the last visit), or nil when the line has no item link, the API is missing or an answer is secret.
-- C_Item.GetItemCount(id, includeBank, includeUses, includeReagentBank, includeAccountBank)
-- (Forever: ItemDocumentation.lua, used so by ItemUtil.GetCraftingReagentCount). This client has
-- no separate reagent bank (Enum.BagIndex has no Reagentbank), so that flag adds nothing; it is
-- passed in case a later client has one (it then counts as "bank"). The old global
-- GetItemCount(id, includeBank) ignores the extra flags (no warband bank there).
local function ItemCounts(text)
    local id = tonumber(text:match("|Hitem:(%d+)"))
    if not id then return nil end
    local get = (C_Item and C_Item.GetItemCount) or GetItemCount
    if type(get) ~= "function" then return nil end
    local ok1, bags = pcall(get, id, false)
    local ok2, bank = pcall(get, id, true, false, true, false)
    local ok3, all = pcall(get, id, true, false, true, true)
    if IsSecret(bags) or IsSecret(bank) or IsSecret(all) then
        secretSkips = secretSkips + 1
        return nil
    end
    if not ok1 or type(bags) ~= "number" then return nil end
    if not ok2 or type(bank) ~= "number" or bank < bags then bank = bags end
    if not ok3 or type(all) ~= "number" or all < bank then all = bank end
    return all, bags, bank - bags, all - bank
end
NP.ChecklistItemCounts = ItemCounts -- tests / self-test

-- Tooltip line: "You have 15: bags 8, bank 4, warband bank 3" (warband bank only when > 0), or nil.
function NP.ChecklistCountText(text)
    local all, bags, bank, warband = ItemCounts(text)
    if not all then return nil end
    local s = ("You have %d: bags %d, bank %d"):format(all, bags, bank)
    if warband > 0 then s = s .. (", warband bank %d"):format(warband) end
    return s
end

-- How many the line asks for: a whole number written next to the first ITEM link
-- ("20 [Linen Cloth]", "20x [..]", "x20 [..]", "[..] x20", "[..] 20x", "[..] 20"), 1..9999, else nil. Odd numbers
-- ("-5", "1.5", "12/20", "20k") give nil. Other links (quests, spells) are never "next to".
local function WantedCount(text)
    local plain = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:|]*:", ""):gsub("|r", "")
    local seen = false
    plain = plain:gsub("|H(.-)|h.-|h", function(link)
        if not seen and link:sub(1, 5) == "item:" then
            seen = true
            return "\1"
        end
        return "\2"
    end)
    if not seen then return nil end
    -- before: at the start or after a space; after: followed by the end, a space or , ; )
    local n = plain:match("^%s*[xX]?(%d+)%s*[xX]?%s*\1") or plain:match("%s[xX]?(%d+)%s*[xX]?%s*\1")
    if not n then
        local m, nextChar = plain:match("\1%s*[xX]?%s*(%d+)[xX]?(.?)")
        if m and (nextChar == "" or nextChar:find("^[%s,;%)]")) then n = m end
    end
    n = tonumber(n)
    if n and n >= 1 and n <= 9999 then return n end
    return nil
end
NP.ChecklistWantedCount = WantedCount -- tests

-- Data changes -------------------------------------------------------------------

local Refresh

local function Changed(note, scrollToEnd)
    NP.UpdateChecklistMirror(note)
    if note == shownNote then Refresh(scrollToEnd) end
end

-- Add one line (text or link) to `note`. Returns true if added.
function NP.ChecklistAddLine(note, text)
    if not NP.IsChecklist(note) then return false end
    text = NP.CleanLine(text)
    if text == "" then return false end
    if #note.items >= NP.CHECKLIST_MAX_LINES then
        NP.Print("A checklist can have up to " .. NP.CHECKLIST_MAX_LINES .. " lines.")
        return false
    end
    note.items[#note.items + 1] = { text = text, done = false }
    Changed(note, true)
    return true
end

function NP.ChecklistToggle(note, i)
    local it = note and note.items and note.items[i]
    if not it then return end
    it.done = not it.done
    Changed(note)
end

function NP.ChecklistMove(note, i, dir)
    local items = note and note.items
    local j = i + dir
    if not items or not items[i] or not items[j] then return end
    items[i], items[j] = items[j], items[i]
    Changed(note)
end

-- Removed lines can come back with /np undo (this session).
function NP.ChecklistDelete(note, i)
    local items = note and note.items
    if not items or not items[i] then return end
    if editing and editing.item == items[i] then NP.FinishLineEdit(false) end
    local item = table.remove(items, i)
    NP.PushRemovedLines(note, { { i = i, item = item } })
    Changed(note)
    NP.UndoHint("lineDelete", "Line deleted. Type /np undo to bring it back.") -- first time per session only
end

-- "Untick all": every ticked line unticked (nothing deleted); /np undo ticks them again.
-- Returns the number of lines unticked. quiet = no undo entry, no chat (the self-test's throwaway list).
function NP.ChecklistUntickAll(note, quiet)
    if not NP.IsChecklist(note) then return 0 end
    if editing and editing.note == note then NP.FinishLineEdit(true) end
    local unticked = {}
    for _, it in ipairs(note.items) do
        if it.done then
            it.done = false
            unticked[#unticked + 1] = it
        end
    end
    if #unticked == 0 then return 0 end
    Changed(note)
    if quiet then return #unticked end
    NP.PushUntick(note, unticked)
    NP.UndoHint("untick", (#unticked == 1 and "Unticked 1 line." or ("Unticked " .. #unticked .. " lines."))
        .. " Type /np undo to tick them again.")
    return #unticked
end

local function RemoveTicked(note)
    local keep, removed = {}, {}
    for i, it in ipairs(note.items) do
        if it.done then removed[#removed + 1] = { i = i, item = it } else keep[#keep + 1] = it end
    end
    if editing and editing.note == note and editing.item.done then NP.FinishLineEdit(false) end
    note.items = keep
    NP.PushRemovedLines(note, removed)
    Changed(note)
    NP.Print((#removed == 1 and "Removed 1 ticked line." or ("Removed " .. #removed .. " ticked lines."))
        .. " Type /np undo to bring them back.")
end

-- Undo put lines back into `note`: redraw if it is showing.
function NP.ChecklistRefresh(note)
    if note == shownNote then Refresh() end
end

-- "Clear ticked": asks first (StaticPopup). No popup: Shift + click clears.
function NP.RequestClearTicked()
    local note = shownNote
    if not note then return end
    local done = NP.ChecklistCounts(note)
    if done == 0 then return end
    local shown
    if StaticPopupDialogs and StaticPopup_Show then
        if not StaticPopupDialogs.NOTEPAD_CLEAR_TICKED then
            StaticPopupDialogs.NOTEPAD_CLEAR_TICKED = {
                text = "Remove the %s ticked lines from \"%s\"?\n/np undo brings them back.",
                button1 = REMOVE or "Remove",
                button2 = CANCEL or "Cancel",
                OnAccept = function()
                    local n = pendingClear
                    pendingClear = nil
                    if n and NP.IsChecklist(n) then RemoveTicked(n) end
                end,
                OnCancel = function() pendingClear = nil end,
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
                preferredIndex = 3,
            }
        end
        -- set after Show: Show cancels an open one first (its OnCancel clears pendingClear)
        local ok, dialog = pcall(StaticPopup_Show, "NOTEPAD_CLEAR_TICKED", NP.GoldText(done), NP.GoldText(note.title))
        shown = ok and dialog
        if shown then pendingClear = note end
    end
    if not shown then
        pendingClear = nil
        if IsShiftKeyDown() then
            RemoveTicked(note)
        else
            NP.Print("Hold Shift and click \"Clear ticked\" to remove the ticked lines.")
        end
    end
end

-- Drag and drop: only GetCursorInfo + ClearCursor (the item goes back to its bag slot).
-- Returns the item's link, or nil (anything else stays on the cursor).
local function TakeCursorItem()
    if type(GetCursorInfo) ~= "function" then return nil end
    local kind, _, link = GetCursorInfo()
    if kind ~= "item" then return nil end
    if IsSecret(link) then
        secretSkips = secretSkips + 1
        return nil
    end
    if type(link) ~= "string" or link == "" then return nil end
    if ClearCursor then ClearCursor() end
    return link
end

local function DropOnList()
    local link = TakeCursorItem()
    if link and shownNote then NP.ChecklistAddLine(shownNote, link) end
    return link ~= nil
end

local function DropOnBox(box)
    local link = TakeCursorItem()
    if link then
        box:SetFocus()
        box:Insert(link)
    end
    return link ~= nil
end

-- Shift-click link hook ------------------------------------------------------------

local pendingLinks = {}   -- { text, note } item links waiting one frame (see OnInsertLink)
local splitHooked = false

-- Adds the links that waited a frame (a split window opening in the same click emptied the list).
local function FlushPendingLinks()
    local list = pendingLinks
    pendingLinks = {}
    for _, p in ipairs(list) do
        if NP.IsChecklist(p.note) and NP.BookOf(p.note) then NP.ChecklistAddLine(p.note, p.text) end
    end
end

-- Runs after Blizzard's link insert (post-hook only). Puts the link into our focused box,
-- or adds an item link as a line (a frame later) when nothing has the keyboard and a checklist is showing.
local function OnInsertLink(text)
    if ownInsert then return end
    if IsSecret(text) then
        secretSkips = secretSkips + 1
        return
    end
    if type(text) ~= "string" or text == "" then return end
    local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
    if focus ~= nil then
        if focus == addBox or focus == lineEdit then
            focus:Insert(text)
        elseif NP.EditorBox and focus == NP.EditorBox() and NP.EditorNote() then
            focus:Insert(text)
            NP.SaveText()
        end
        return -- another box (chat, macro, other addons) has it
    end
    -- nothing has the keyboard: only item links, and only if this click didn't open the
    -- split-stack window (Shift is both "link" and "split"; Blizzard opens the split window in the
    -- same click, right after the link insert, so the add waits one frame)
    if shownNote and view and view:IsVisible() and text:find("|Hitem:", 1, true) then
        pendingLinks[#pendingLinks + 1] = { text = text, note = shownNote }
        if #pendingLinks == 1 then
            if C_Timer and C_Timer.After then C_Timer.After(0, FlushPendingLinks) else FlushPendingLinks() end
        end
    end
end
NP.OnInsertLink = OnInsertLink -- tests

-- The split-stack window opened in this click: the queued link was a split, not an add.
local function OnSplitOpened()
    for k = #pendingLinks, 1, -1 do pendingLinks[k] = nil end
end

local function InstallLinkHook()
    if hookedName then return end
    if type(ChatFrameUtil) == "table" and type(ChatFrameUtil.InsertLink) == "function" then
        hooksecurefunc(ChatFrameUtil, "InsertLink", OnInsertLink)
        hookedName = "ChatFrameUtil.InsertLink"
    elseif type(ChatEdit_InsertLink) == "function" then
        hooksecurefunc("ChatEdit_InsertLink", OnInsertLink)
        hookedName = "ChatEdit_InsertLink"
    end
    if not splitHooked and type(StackSplitFrame) == "table"
        and type(StackSplitFrame.OpenStackSplitFrame) == "function" then
        hooksecurefunc(StackSplitFrame, "OpenStackSplitFrame", OnSplitOpened)
        splitHooked = true
    end
end

-- Send a line's link to an open chat box (Shift-click on a row), like a bag item.
local function LinkToChat(text)
    local link = text:match("|c%x+|H.-|h.-|h|r") or text:match("|cn[^:|]*:|H.-|h.-|h|r") or text:match("|H.-|h.-|h")
    if not link then return end
    local insert = (type(ChatFrameUtil) == "table" and ChatFrameUtil.InsertLink) or ChatEdit_InsertLink
    if type(insert) ~= "function" then return end
    ownInsert = true
    pcall(insert, link)
    ownInsert = false
end

-- Widgets ------------------------------------------------------------------------------

local function SetPlaceholder(box)
    if box.NPPlaceholder then
        box.NPPlaceholder:SetShown((box:GetText() or "") == "" and not box:HasFocus())
    end
end

-- Single-line box: Blizzard's InputBoxTemplate, else a plain box with a thin border.
local function CreateInput(parent, name)
    local b = NP.TryCreateFrame("EditBox", nil, parent, NP.Templates.input)
    if b then
        used[name] = NP.Templates.input
    else
        b = NP.TryCreateFrame("EditBox", nil, parent, NP.Templates.backdrop) or CreateFrame("EditBox", nil, parent)
        if b.SetBackdrop then
            b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
            b:SetBackdropColor(unpack(NP.Color.inputBg))
            b:SetBackdropBorderColor(unpack(NP.Color.inputBorder))
        end
        b:SetTextInsets(6, 6, 0, 0)
        b:SetFontObject(ChatFontNormal)
        used[name] = "own"
    end
    b:SetAutoFocus(false)
    b:SetMaxLetters(0)
    -- no byte limit: a line can be any length (converted paragraphs, links); a limit
    -- would cut a long line as soon as it is put into the box
    if b.SetMaxBytes then b:SetMaxBytes(0) end
    b:HookScript("OnEscapePressed", function(self) self:ClearFocus() end)
    b:HookScript("OnTabPressed", function()
        if IsControlKeyDown() and NP.CycleNote then NP.CycleNote(IsShiftKeyDown() and -1 or 1) end
    end)
    b:HookScript("OnReceiveDrag", function(self) DropOnBox(self) end)
    b:HookScript("OnMouseUp", function(self) DropOnBox(self) end)
    return b
end

-- Blizzard's red panel button, else the same art by file.
local function CreateButton(parent, label, width, name)
    local b = NP.TryCreateFrame("Button", nil, parent, NP.Templates.button)
    if b then
        b:SetText(label)
        used[name] = NP.Templates.button
    else
        b = CreateFrame("Button", nil, parent)
        local coords = { 0, 0.625, 0, 0.6875 }
        local up = b:CreateTexture(nil, "ARTWORK")
        up:SetAllPoints()
        up:SetTexture(NP.Art.redButtonUp)
        up:SetTexCoord(unpack(coords))
        b:SetNormalTexture(up)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetTexture(NP.Art.redButtonHighlight)
        hl:SetTexCoord(unpack(coords))
        hl:SetBlendMode("ADD")
        local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("CENTER", 0, 1)
        fs:SetText(label)
        b:SetFontString(fs)
        used[name] = "own"
    end
    b:SetSize(width, 22)
    return b
end

-- Tick box: UICheckButtonTemplate, else the same check-box art by file.
local function CreateCheck(parent)
    local c = NP.TryCreateFrame("CheckButton", nil, parent, NP.Templates.check)
    if c then
        used.check = NP.Templates.check
    else
        c = CreateFrame("CheckButton", nil, parent)
        c:SetNormalTexture(NP.Art.checkUp)
        c:SetPushedTexture(NP.Art.checkDown)
        c:SetHighlightTexture(NP.Art.checkHighlight, "ADD")
        c:SetCheckedTexture(NP.Art.checkMark)
        used.check = "own"
    end
    c:SetSize(CHECK_SIZE, CHECK_SIZE)
    return c
end

-- Inline line editing -------------------------------------------------------------------

function NP.FinishLineEdit(save)
    local e = editing
    if not e then return end
    editing = nil
    local text = NP.CleanLine(lineEdit:GetText())
    lineEdit:ClearFocus()
    lineEdit:Hide()
    if save and text ~= "" and text ~= e.item.text then
        e.item.text = text
        NP.UpdateChecklistMirror(e.note)
    end
    if e.note == shownNote then Refresh() end
end

function NP.ChecklistEdit(i)
    local note = shownNote
    local it = note and note.items[i]
    local row = rows[i]
    if not it or not row or not row:IsShown() then return end
    if editing then NP.FinishLineEdit(true) end
    editing = { note = note, item = it }
    lineEdit:ClearAllPoints()
    lineEdit:SetPoint("LEFT", row, "LEFT", CHECK_SIZE + 4, 0)
    lineEdit:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    lineEdit:SetHeight(rowH)
    lineEdit:SetText(it.text)
    -- the box has no byte limit; if it still didn't take the whole line, don't edit it
    -- (saving the cut copy would lose the rest of the line)
    if lineEdit:GetText() ~= it.text then
        editing = nil
        lineEdit:SetText("")
        lineEdit:Hide()
        NP.Print("This line is too long to edit here. It was left as it is.")
        return
    end
    row.NPText:Hide()
    row.NPIcon:Hide()
    lineEdit:Show()
    lineEdit:SetFocus()
    lineEdit:HighlightText()
end

-- Rows ----------------------------------------------------------------------------------

local function IndexOfItem(item)
    if not shownNote then return nil end
    for i, it in ipairs(shownNote.items) do
        if it == item then return i end
    end
    return nil
end

local function OpenRowMenu(row)
    local item = row.NPItem
    local ok = false
    if MenuUtil and MenuUtil.CreateContextMenu then
        ok = pcall(MenuUtil.CreateContextMenu, row, function(_, root)
            local note = shownNote
            local idx = IndexOfItem(item)
            if not idx then return end
            root:CreateButton("Edit", function()
                local j = IndexOfItem(item)
                if j then NP.ChecklistEdit(j) end
            end)
            local up = root:CreateButton("Move up", function()
                local j = IndexOfItem(item)
                if j then NP.ChecklistMove(note, j, -1) end
            end)
            if idx <= 1 and up and up.SetEnabled then up:SetEnabled(false) end
            local down = root:CreateButton("Move down", function()
                local j = IndexOfItem(item)
                if j then NP.ChecklistMove(note, j, 1) end
            end)
            if idx >= #note.items and down and down.SetEnabled then down:SetEnabled(false) end
            local untick = root:CreateButton("Untick all", function() NP.ChecklistUntickAll(note) end)
            if NP.ChecklistCounts(note) == 0 and untick and untick.SetEnabled then untick:SetEnabled(false) end
            root:CreateButton("Delete", function()
                local j = IndexOfItem(item)
                if j then NP.ChecklistDelete(note, j) end
            end)
        end)
    end
    if not ok then
        local j = IndexOfItem(item)
        if j then NP.ChecklistEdit(j) end -- no menu: right-click edits
    end
end

-- Only the rows inside the scrolled area are shown (long lists stay light). Height not known
-- yet (window never laid out): show them all.
local function UpdateVisibleRows()
    if not shownNote or not scroll then return end
    local top = scroll:GetVerticalScroll() or 0
    local viewH = scroll:GetHeight() or 0
    for i = 1, #shownNote.items do
        local r = rows[i]
        if r then
            r:SetShown(viewH <= 1 or (i * rowH > top and (i - 1) * rowH < top + viewH))
        end
    end
end

local function ScrollBy(delta)
    local range = math.max(0, content:GetHeight() - scroll:GetHeight())
    scroll:SetVerticalScroll(Clamp(scroll:GetVerticalScroll() - delta * rowH * 2, 0, range))
    UpdateVisibleRows()
end

local function RowEnter(self)
    local text = self.NPItem and self.NPItem.text
    if not text then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local link = FirstLink(text)
    local ok = link and pcall(GameTooltip.SetHyperlink, GameTooltip, link)
    if not ok then
        GameTooltip:SetText(NP.PlainText(text), 1, 1, 1, 1, true)
    end
    local line = NP.ChecklistCountText(text)
    if line then
        local w = NP.Color.white
        GameTooltip:AddLine(line, w[1], w[2], w[3], true)
    end
    local g = NP.Color.grey
    GameTooltip:AddLine("Double-click: edit. Right-click: more. Alt + mouse wheel: move.", g[1], g[2], g[3], true)
    GameTooltip:Show()
end

-- Fills a row's count ("12", or "12 / 20" green once reached). Returns true if shown.
local function SetCount(r, it)
    local all = ItemCounts(it.text)
    if not all then
        r.NPCount:SetText("")
        r.NPCount:Hide()
        return false
    end
    local want = WantedCount(it.text)
    r.NPCount:SetText(want and (all .. " / " .. want) or tostring(all))
    local c = (it.done and NP.Color.grey) or ((want and all >= want) and NP.Color.green) or NP.Color.white
    r.NPCount:SetTextColor(c[1], c[2], c[3])
    r.NPCount:Show()
    return true
end

local function CreateRow(i)
    local r = CreateFrame("Button", nil, content)
    r:SetHeight(rowH)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    if hl:SetTexture(NP.Art.rowHighlight) == false then
        hl:SetColorTexture(unpack(NP.Color.rowHover))
    else
        hl:SetBlendMode("ADD")
        hl:SetAlpha(0.6)
    end

    local check = CreateCheck(r)
    check:SetPoint("LEFT", r, "LEFT", -1, 0)
    check:SetScript("OnClick", function(self)
        local j = IndexOfItem(r.NPItem)
        if j then
            NP.ChecklistToggle(shownNote, j)
            PlayCheckSound(self:GetChecked())
        end
    end)
    r.NPCheck = check

    local icon = r:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint("LEFT", check, "RIGHT", 1, 0)
    r.NPIcon = icon

    local fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetFontObject(ListFont()) -- the text size setting
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    fs:SetPoint("RIGHT", r, "RIGHT", -4, 0)
    r.NPText = fs

    local count = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    count:SetFontObject(ListFont())
    count:SetJustifyH("RIGHT")
    count:SetWordWrap(false)
    count:SetPoint("RIGHT", r, "RIGHT", -4, 0)
    count:Hide()
    r.NPCount = count -- "12" or "12 / 20" on item lines

    r:SetScript("OnClick", function(self, button)
        if DropOnList() then return end -- clicked with an item on the cursor
        if button == "RightButton" then
            OpenRowMenu(self)
        elseif IsShiftKeyDown() and self.NPItem then
            LinkToChat(self.NPItem.text)
        end
    end)
    r:SetScript("OnDoubleClick", function(self, button)
        if button ~= "LeftButton" then return end
        local j = IndexOfItem(self.NPItem)
        if j then NP.ChecklistEdit(j) end
    end)
    r:SetScript("OnEnter", RowEnter)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r:SetScript("OnReceiveDrag", DropOnList)
    r:EnableMouseWheel(true)
    r:SetScript("OnMouseWheel", function(self, delta)
        if IsControlKeyDown() and NP.StepFontSize then
            NP.StepFontSize(delta) -- Ctrl + wheel: text size
        elseif IsAltKeyDown() then
            local j = IndexOfItem(self.NPItem)
            if j then NP.ChecklistMove(shownNote, j, delta > 0 and -1 or 1) end
        else
            ScrollBy(delta)
        end
    end)
    rows[i] = r
    return r
end

local function LayoutRow(r, i, it)
    r.NPItem = it
    r:SetHeight(rowH) -- the text size may have changed since the row was made
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * rowH)
    r:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(i - 1) * rowH)
    r.NPCheck:SetChecked(it.done)
    local tex = ItemIcon(it.text)
    r.NPText:ClearAllPoints()
    if SetCount(r, it) then
        r.NPText:SetPoint("RIGHT", r.NPCount, "LEFT", -6, 0)
    else
        r.NPText:SetPoint("RIGHT", r, "RIGHT", -4, 0)
    end
    if tex then
        r.NPIcon:SetTexture(tex)
        r.NPIcon:Show()
        r.NPText:SetPoint("LEFT", r.NPIcon, "RIGHT", 4, 0)
    else
        r.NPIcon:Hide()
        r.NPText:SetPoint("LEFT", r.NPCheck, "RIGHT", 2, 0)
    end
    r.NPText:SetText(it.text)
    r.NPText:Show()
    local c = it.done and NP.Color.grey or NP.Color.white
    r.NPText:SetTextColor(c[1], c[2], c[3])
    local a = it.done and NP.TICKED_ALPHA or 1
    r.NPText:SetAlpha(a)
    r.NPIcon:SetAlpha(a)
    r.NPCount:SetAlpha(a)
    r:Show()
end

-- Bags or bank changed: only the counts (the text's anchor follows the count's width).
local function RefreshCounts()
    if not shownNote then return end
    for i, it in ipairs(shownNote.items) do
        local r = rows[i]
        -- every item line, also one whose count was hidden at the last redraw (no answer then)
        if r and r.NPItem == it and it.text:find("|Hitem:", 1, true) then
            if SetCount(r, it) then
                r.NPText:SetPoint("RIGHT", r.NPCount, "LEFT", -6, 0)
            else
                r.NPText:SetPoint("RIGHT", r, "RIGHT", -4, 0)
            end
        end
    end
end

Refresh = function(scrollToEnd)
    if not view or not shownNote then return end
    local items = shownNote.items
    local n = #items
    for i, it in ipairs(items) do
        LayoutRow(rows[i] or CreateRow(i), i, it)
    end
    for i = n + 1, #rows do rows[i]:Hide() end

    local viewH = scroll:GetHeight() or 0
    local viewW = scroll:GetWidth() or 0
    if viewW > 1 then content:SetWidth(viewW) end -- in case OnSizeChanged came before the first layout
    content:SetHeight(math.max(n * rowH, viewH, 1))
    emptyText:SetShown(n == 0)

    local done = NP.ChecklistCounts(shownNote)
    counter:SetText(("%d / %d done"):format(done, n))
    local cc = (n > 0 and done == n) and NP.Color.gold or NP.Color.white
    counter:SetTextColor(cc[1], cc[2], cc[3])
    clearBtn:SetEnabled(done > 0)

    local range = math.max(0, n * rowH - viewH)
    if scrollToEnd then
        scroll:SetVerticalScroll(range)
    elseif scroll:GetVerticalScroll() > range then
        scroll:SetVerticalScroll(range)
    end
    UpdateVisibleRows()

    if editing then
        local j = (editing.note == shownNote) and IndexOfItem(editing.item)
        if j and rows[j] then
            rows[j].NPText:Hide()
            rows[j].NPIcon:Hide()
            lineEdit:ClearAllPoints()
            lineEdit:SetPoint("LEFT", rows[j], "LEFT", CHECK_SIZE + 4, 0)
            lineEdit:SetPoint("RIGHT", rows[j], "RIGHT", -4, 0)
            lineEdit:SetHeight(rowH)
        else
            NP.FinishLineEdit(true)
        end
    end
end

local function AddFromBox()
    local text = addBox:GetText() or ""
    local added = false
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        if NP.ChecklistAddLine(shownNote, line) then added = true end
    end
    if added or NP.CleanLine(text) == "" then addBox:SetText("") end
    SetPlaceholder(addBox)
end

-- Public ----------------------------------------------------------------------------------

-- note = a checklist to show, nil = hide the view (a text note is open).
function NP.ShowChecklist(note)
    if not view then return end
    if editing and editing.note ~= note then NP.FinishLineEdit(true) end
    if not NP.IsChecklist(note) then
        if shownNote then scrollPlace[shownNote] = scroll:GetVerticalScroll() end
        shownNote = nil
        view:Hide()
        return
    end
    local switched = (note ~= shownNote)
    if switched and shownNote then scrollPlace[shownNote] = scroll:GetVerticalScroll() end
    shownNote = note
    view:Show()
    if switched then scroll:SetVerticalScroll(scrollPlace[note] or 0) end -- where it was left (this session)
    Refresh()
end

function NP.FocusChecklist()
    if addBox and view:IsVisible() then addBox:SetFocus() end
end

function NP.ClearChecklistFocus()
    if not view then return end
    NP.FinishLineEdit(true)
    addBox:ClearFocus()
end

function NP.ChecklistShownNote() return shownNote end

-- Search hit (Search.lua): scroll line i of the shown checklist into view and light it up
-- for a moment (the row's own hover highlight, locked).
local flashed
function NP.ShowChecklistRow(note, i)
    if not view or note ~= shownNote or not note.items[i] then return false end
    local viewH = scroll:GetHeight() or 0
    local top, cur = (i - 1) * rowH, scroll:GetVerticalScroll() or 0
    local range = math.max(0, #note.items * rowH - viewH)
    if top < cur then
        cur = top
    elseif top + rowH > cur + viewH then
        cur = top + rowH - viewH
    end
    scroll:SetVerticalScroll(Clamp(cur, 0, range))
    UpdateVisibleRows()
    local r = rows[i]
    if not r then return false end
    if flashed and flashed ~= r then flashed:UnlockHighlight() end
    flashed = r
    r:LockHighlight()
    C_Timer.After(1.5, function()
        if flashed == r then
            r:UnlockHighlight()
            flashed = nil
        end
    end)
    return true
end

-- The text size changed (Settings.lua): the font object already has the new size; rows get
-- taller or shorter with it (never under ROW_H_MIN), then the list is laid out again.
function NP.ChecklistApplyFont(size)
    size = tonumber(size) or 12
    rowH = math.max(ROW_H_MIN, math.floor(size + ROW_PAD + 0.5))
    if not view then return end
    local font = ListFont()
    for _, r in ipairs(rows) do
        r.NPText:SetFontObject(font)
        r.NPCount:SetFontObject(font)
    end
    lineEdit:SetFontObject(font)
    if shownNote then Refresh() end
end

function NP.ChecklistRowHeight() return rowH end

-- For the self-test: which Blizzard function is hooked, how many secret links were skipped,
-- and which template each part uses.
function NP.ChecklistInfo()
    return { hook = hookedName, splitHook = splitHooked, secretSkips = secretSkips, used = used,
        pendingLinks = #pendingLinks }
end

-- For tests and the self-test: the view's widgets.
function NP.ChecklistWidgets()
    return { view = view, addBox = addBox, addButton = addBtn, scroll = scroll, content = content,
        counter = counter, clearButton = clearBtn, empty = emptyText, lineEdit = lineEdit, rows = rows }
end

function NP.CreateChecklist(inset)
    if view then return end
    view = CreateFrame("Frame", nil, inset)
    view:SetAllPoints(inset)
    view:SetFrameLevel(inset:GetFrameLevel() + 2) -- above the text box's click catcher
    view:Hide()
    view:SetScript("OnShow", function(self)
        -- item counts follow the bags and bank only while a checklist is showing
        self:RegisterEvent("BAG_UPDATE_DELAYED")
        self:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
        Refresh() -- sizes are known now (window opened)
    end)
    view:SetScript("OnHide", function(self)
        self:UnregisterEvent("BAG_UPDATE_DELAYED")
        self:UnregisterEvent("PLAYERBANKSLOTS_CHANGED")
    end)
    view:SetScript("OnEvent", RefreshCounts)

    addBtn = CreateButton(view, "Add", 64, "addButton")
    addBtn:SetPoint("TOPRIGHT", view, "TOPRIGHT", -8, -6)
    addBtn:SetScript("OnClick", function()
        AddFromBox()
        addBox:SetFocus()
    end)

    addBox = CreateInput(view, "addBox")
    addBox:SetPoint("TOPLEFT", view, "TOPLEFT", 14, -7)
    addBox:SetPoint("RIGHT", addBtn, "LEFT", -8, 0)
    addBox:SetHeight(20)
    local ph = addBox:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    ph:SetPoint("LEFT", addBox, "LEFT", used.addBox == "own" and 6 or 0, 0)
    ph:SetPoint("RIGHT", addBox, "RIGHT", -4, 0)
    ph:SetJustifyH("LEFT")
    ph:SetWordWrap(false)
    ph:SetText("Type a line, or Shift-click an item")
    addBox.NPPlaceholder = ph
    addBox:SetScript("OnEnterPressed", AddFromBox)
    addBox:HookScript("OnTextChanged", SetPlaceholder)
    addBox:HookScript("OnEditFocusGained", SetPlaceholder)
    addBox:HookScript("OnEditFocusLost", SetPlaceholder)

    clearBtn = CreateButton(view, "Clear ticked", 100, "clearButton")
    clearBtn:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", -18, 6) -- left of the window's resize grip
    clearBtn:SetScript("OnClick", function() NP.RequestClearTicked() end)

    counter = view:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    counter:SetPoint("LEFT", view, "BOTTOMLEFT", 12, BOTTOM_H / 2 + 1)
    counter:SetJustifyH("LEFT")

    scroll = NP.TryCreateFrame("ScrollFrame", "NotePadChecklistScroll", view, NP.Templates.scrollFrame)
    used.scroll = scroll and NP.Templates.scrollFrame or "own"
    if not scroll then scroll = CreateFrame("ScrollFrame", "NotePadChecklistScroll", view) end
    scroll:SetPoint("TOPLEFT", view, "TOPLEFT", 8, -TOP_H - 2)
    scroll:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", -28, BOTTOM_H + 2)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta)
        if IsControlKeyDown() and NP.StepFontSize then NP.StepFontSize(delta) else ScrollBy(delta) end
    end)
    scroll:EnableMouse(true)
    scroll:SetScript("OnReceiveDrag", DropOnList)
    scroll:SetScript("OnMouseUp", DropOnList)

    -- no anchor: the scroll frame places its scroll child (and moves it when scrolled)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(math.max(1, scroll:GetWidth() or 1), 1)
    content:EnableMouse(true)
    content:SetScript("OnReceiveDrag", DropOnList)
    content:SetScript("OnMouseUp", DropOnList)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(_, w)
        content:SetWidth(math.max(1, w or 1))
        Refresh()
    end)
    scroll:HookScript("OnVerticalScroll", UpdateVisibleRows) -- the scroll bar moved it

    emptyText = content:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    emptyText:SetPoint("TOPLEFT", content, "TOPLEFT", 10, -16)
    emptyText:SetPoint("TOPRIGHT", content, "TOPRIGHT", -10, -16)
    emptyText:SetJustifyH("CENTER")
    emptyText:SetText("Nothing here yet.\nType a line above, Shift-click an item, or drag one here from your bags.")

    lineEdit = CreateInput(content, "lineEdit")
    lineEdit:SetFontObject(ListFont()) -- same size as the line it edits
    lineEdit:SetFrameLevel(content:GetFrameLevel() + 10)
    lineEdit:Hide()
    lineEdit:SetScript("OnEnterPressed", function() NP.FinishLineEdit(true) end)
    lineEdit:HookScript("OnEscapePressed", function() NP.FinishLineEdit(false) end)
    lineEdit:HookScript("OnEditFocusLost", function() NP.FinishLineEdit(true) end) -- click away saves

    InstallLinkHook()
end
