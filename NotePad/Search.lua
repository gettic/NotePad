-- Note Pad: search every note (the open notebook first, then the other one).
-- Open: the magnifier in the title bar, Ctrl+F in the text, /np find <text>. The results lie
-- over the text area; a click (Enter: the first) opens that note with the match selected,
-- or scrolls a checklist to the line. Esc closes. Loads after Settings.lua.
local _, NP = ...

local MAX_ROWS = 10
local ROW_H = 20
local TOP_H = 32        -- search box row
local BOTTOM_H = 22     -- "N matches" line
local MAX_HITS = 500    -- kept for the list; more are only counted
local BEFORE, AFTER = 20, 50 -- preview: bytes before / after the match

local panel, box, button, status
local rows = {}
local hits, total = {}, 0
local offset = 0        -- first hit shown (mouse wheel pages the list)
local used = "-"        -- template the box uses (self-test)

-- Text helpers ------------------------------------------------------------------------

-- The text as it shows: colour codes out, link names kept ("[Hearthstone]"), textures (|T..|t)
-- and atlases (|A..|a) out, "||" = "|". Works on whole runs of text between the "|" codes.
-- map: list of runs { shown start, raw start, pipe } to find raw bytes again (nil = same text).
local CLOSER = { H = "|h", T = "|t", A = "|a" } -- link / texture / atlas: skipped up to this

local function Visible(s)
    s = tostring(s or "")
    if not s:find("|", 1, true) then return s, nil end
    local out, map, n, v = {}, {}, 0, 1
    local i, len = 1, #s
    local function Copy(a, b, pipe) -- raw bytes a..b are shown (pipe: "||" shown as one "|")
        n = n + 1
        out[n] = pipe and "|" or s:sub(a, b)
        map[n] = { v, a, pipe }
        v = v + (pipe and 1 or (b - a + 1))
    end
    while i <= len do
        local p = s:find("|", i, true)
        if not p then
            Copy(i, len)
            break
        end
        if p > i then Copy(i, p - 1) end
        local nx = s:sub(p + 1, p + 1)
        if nx == "c" and s:sub(p + 2, p + 9):match("^%x%x%x%x%x%x%x%x$") then
            i = p + 10
        elseif nx == "r" or nx == "h" then
            i = p + 2
        elseif CLOSER[nx] then
            local e = s:find(CLOSER[nx], p + 2, true)
            if e then i = e + 2 else Copy(p, p); i = p + 1 end
        elseif nx == "|" then
            Copy(p, p + 1, true)
            i = p + 2
        else
            Copy(p, p)
            i = p + 1
        end
    end
    return table.concat(out), map
end
NP.SearchVisible = Visible -- tests

-- The raw byte of shown byte `at` (last = the end of a match: a shown "|" ends after its "||").
local function RawPos(map, at, last)
    if not map then return at end
    local lo, hi = 1, #map
    while lo < hi do -- the last run that starts at or before `at`
        local mid = math.floor((lo + hi + 1) / 2)
        if map[mid][1] <= at then lo = mid else hi = mid - 1 end
    end
    local run = map[lo]
    if run[3] then return run[2] + (last and 1 or 0) end
    return run[2] + (at - run[1])
end
NP.SearchRawPos = RawPos -- tests, self-test

-- Shown text per note / checklist line, made again only when its text changed (a keystroke in
-- the search box must not rebuild every long note). Weak keys: deleted notes drop out.
local cache = setmetatable({}, { __mode = "k" })
local cacheBuilds = 0 -- tests

local function Prepared(owner, raw)
    raw = tostring(raw or "")
    local c = cache[owner]
    if not c or c.raw ~= raw then
        local vis, map = Visible(raw)
        c = { raw = raw, vis = vis, map = map, low = strlower(vis) }
        cache[owner] = c
        cacheBuilds = cacheBuilds + 1
    end
    return c
end
function NP.SearchCacheBuilds() return cacheBuilds end -- tests

-- Move i back / forward to the first byte of a UTF-8 letter (never cut one in half).
local function LetterStart(s, i)
    while i > 1 do
        local b = s:byte(i)
        if not b or b < 128 or b > 191 then break end
        i = i - 1
    end
    return i
end

-- Shown in a FontString: a lone "|" would start a code.
local function Plain(s) return (s:gsub("|", "||")) end

-- One line of preview around bytes s..e of `vis`, the match in gold.
-- (Only the bytes near the match are looked at: long notes stay quick.)
local function Preview(vis, s, e)
    local a = math.max(1, s - BEFORE)
    local nl = vis:sub(a, s - 1):match(".*()\n")
    local cutHead = false
    if nl then
        a = a + nl -- the line starts after that line break
    else
        a = LetterStart(vis, a)
        cutHead = a > 1 and vis:sub(a - 1, a - 1) ~= "\n"
    end
    local after = vis:sub(e + 1, e + AFTER)
    local nl2 = after:find("\n", 1, true)
    local b, cutTail
    if nl2 then
        b, cutTail = e + nl2 - 1, false
    else
        b = math.min(#vis, e + AFTER)
        cutTail = b < #vis and vis:sub(b + 1, b + 1) ~= "\n"
        if cutTail then b = LetterStart(vis, b + 1) - 1 end
    end
    local head = vis:sub(a, s - 1):gsub("^%s+", "")
    return (cutHead and "..." or "") .. Plain(head) .. NP.GoldText(Plain(vis:sub(s, e)))
        .. Plain(vis:sub(e + 1, b)) .. (cutTail and "..." or "")
end

-- Every match of `q` (case-insensitive, plain text) in the open notebook, then the other one.
-- Returns hits ({ book, note, index, item | s, e (raw bytes), preview }) and the full count.
function NP.SearchNotes(q)
    local found, count = {}, 0
    -- the query in its shown form too: the box returns a typed "|" as "||", a pasted link as code
    q = strlower(strtrim((Visible(tostring(q or "")))))
    if q == "" then return found, 0 end
    local books = { NP.Book() }
    local other = NP.OtherBook and NP.OtherBook()
    if other and other ~= books[1] then books[2] = other end
    local function Add(h)
        count = count + 1
        if #found < MAX_HITS then found[#found + 1] = h end
    end
    for _, book in ipairs(books) do
        for idx, note in ipairs(book.notes) do
            if NP.IsChecklist(note) then
                for li, it in ipairs(note.items) do
                    local c = Prepared(it, it.text)
                    local s, e = c.low:find(q, 1, true)
                    if s then
                        -- the line table itself: still the right line if lines move later
                        Add({ book = book, note = note, index = idx, item = li, line = it, preview = Preview(c.vis, s, e) })
                    end
                end
            else
                local c = Prepared(note, note.text)
                local vis, map, low = c.vis, c.map, c.low
                local from = 1
                while true do
                    local s, e = low:find(q, from, true)
                    if not s then break end
                    if #found < MAX_HITS then
                        Add({ book = book, note = note, index = idx,
                            s = RawPos(map, s), e = RawPos(map, e, true), preview = Preview(vis, s, e) })
                    else
                        count = count + 1
                    end
                    from = e + 1
                end
            end
        end
    end
    return found, count
end

-- The list ------------------------------------------------------------------------------

local function Refresh()
    if not panel then return end
    local h = panel:GetHeight() or 0
    local fit = (h > TOP_H + BOTTOM_H) and math.floor((h - TOP_H - BOTTOM_H) / ROW_H) or MAX_ROWS
    fit = math.max(1, math.min(MAX_ROWS, fit))
    offset = math.max(0, math.min(offset, #hits - fit))
    local cur = NP.Book()
    for i = 1, MAX_ROWS do
        local r = rows[i]
        local hit = hits[offset + i]
        if hit and i <= fit then
            local tag = (hit.book ~= cur) and ("|cff999999" .. Plain(NP.BookName(hit.book)) .. ":|r ") or ""
            r.NPText:SetText(tag .. "|cffbbbbbb" .. Plain(hit.note.title) .. ":|r " .. hit.preview)
            r.NPHit = hit
            r:Show()
        else
            r.NPHit = nil
            r:Hide()
        end
    end
    local q = box and box:GetText() or ""
    if strtrim(q) == "" then
        status:SetText("Type to search all notes. Enter opens the first match, Esc closes.")
    elseif total == 0 then
        status:SetText("No matches.")
    else
        local shownTo = math.min(#hits, offset + fit)
        local word = (total == 1) and "match" or "matches"
        if total > fit then
            status:SetText(("%d-%d of %d %s (mouse wheel for more)"):format(offset + 1, shownTo, total, word))
        else
            status:SetText(("%d %s"):format(total, word))
        end
    end
end

local function Run()
    if not box then return end
    hits, total = NP.SearchNotes(box:GetText())
    offset = 0
    Refresh()
end

function NP.RefreshSearch()
    if panel and panel:IsShown() then Run() end
end

-- Open the note of a hit: switch notebook if needed, select the match / show the line.
function NP.OpenSearchHit(hit)
    if type(hit) ~= "table" then return false end
    local book = NP.BookOf(hit.note)
    if not book then Run() return false end -- deleted since
    if book ~= NP.Book() then NP.SetCharBook(book ~= NP.db) end
    local idx
    for i, n in ipairs(NP.Book().notes) do
        if n == hit.note then idx = i break end
    end
    if not idx then Run() return false end
    if panel then panel:Hide() end
    NP.OpenWindow()
    NP.ShowNote(idx)
    if hit.item then
        -- the line where it is now (lines may have moved or gone since the search ran)
        local li
        for i, it in ipairs(NP.IsChecklist(hit.note) and hit.note.items or {}) do
            if it == hit.line then li = i break end
        end
        if not li then return false end
        return NP.ShowChecklistRow and NP.ShowChecklistRow(hit.note, li) or false
    end
    return NP.SelectEditorText(hit.s - 1, hit.e)
end

function NP.OpenSearch(text)
    if not panel then return end
    NP.OpenWindow()
    NP.SaveText()
    if NP.FinishLineEdit then NP.FinishLineEdit(true) end
    if NP.FinishRename then NP.FinishRename(true) end
    if type(text) == "string" and text ~= "" then box:SetText(text) end
    panel:Show()
    if button then button:LockHighlight() end
    Run()
    box:SetFocus()
    box:HighlightText()
end

function NP.CloseSearch()
    if panel and panel:IsShown() then panel:Hide() end
end

function NP.ToggleSearch()
    -- IsVisible: on the folded bar the panel is still "shown" but hidden with the text area;
    -- a click there unfolds and shows it
    if panel and panel:IsVisible() then
        NP.CloseSearch()
        NP.FocusText()
    else
        NP.OpenSearch()
    end
end

function NP.SearchWidgets()
    return { panel = panel, box = box, button = button, status = status, rows = rows, used = used }
end

function NP.SearchHits() return hits, total end -- tests

-- Building ------------------------------------------------------------------------------

local function CreateBox(parent)
    local b = NP.TryCreateFrame("EditBox", "NotePadSearchBox", parent, NP.Templates.search)
    used = "search"
    if not b then
        b = NP.TryCreateFrame("EditBox", "NotePadSearchBox", parent, NP.Templates.input)
        used = "input"
    end
    if not b then
        b = NP.TryCreateFrame("EditBox", "NotePadSearchBox", parent, NP.Templates.backdrop)
            or CreateFrame("EditBox", "NotePadSearchBox", parent)
        used = "own"
        if b.SetBackdrop then
            b:SetBackdrop({ bgFile = NP.Art.tooltipBg, edgeFile = NP.Art.tooltipBorder, tile = true,
                tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
            b:SetBackdropColor(unpack(NP.Color.inputBg))
            b:SetBackdropBorderColor(unpack(NP.Color.inputBorder))
        end
        b:SetFontObject(ChatFontNormal)
        b:SetTextInsets(6, 6, 0, 0)
    end
    b:SetAutoFocus(false)
    b:SetMaxLetters(60)
    -- the template keeps its own scripts (clear button, "Search" text): ours are hooked or set
    -- on this box only
    b:HookScript("OnTextChanged", function() Run() end)
    b:SetScript("OnEnterPressed", function() NP.OpenSearchHit(hits[1]) end)
    b:SetScript("OnEscapePressed", function()
        NP.CloseSearch()
        NP.FocusText()
    end)
    return b
end

local function CreateRow(i)
    local r = CreateFrame("Button", nil, panel)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", panel, "TOPLEFT", 6, -TOP_H - (i - 1) * ROW_H)
    r:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -6, -TOP_H - (i - 1) * ROW_H)
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    if hl:SetTexture(NP.Art.rowHighlight) == false then
        hl:SetColorTexture(unpack(NP.Color.rowHover))
    else
        hl:SetBlendMode("ADD")
        hl:SetAlpha(0.6)
    end
    local fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", 4, 0)
    fs:SetPoint("RIGHT", -4, 0)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    r.NPText = fs
    r:SetScript("OnClick", function(self) NP.OpenSearchHit(self.NPHit) end)
    r:Hide()
    rows[i] = r
    return r
end

local function Tooltip(self)
    local h = NP.Color.hint
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Search")
    GameTooltip:AddLine("Search all notes (both notebooks)", 1, 1, 1, true)
    GameTooltip:AddLine("Ctrl+F while typing a note: search", h[1], h[2], h[3], true)
    GameTooltip:AddLine("/np find <text>", h[1], h[2], h[3], true)
    GameTooltip:Show()
end

-- The magnifier button (left of `anchor`, the cog) and the panel over `inset`.
function NP.CreateSearch(f, inset, anchor)
    if button then return button end
    button = CreateFrame("Button", nil, f)
    button:SetSize(20, 20)
    if anchor then
        button:SetPoint("RIGHT", anchor, "LEFT", -1, 0)
        button:SetFrameLevel(anchor:GetFrameLevel())
    else
        button:SetPoint("TOPRIGHT", f, "TOPRIGHT", -78, -2)
    end
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("CENTER")
    icon:SetSize(14, 14)
    if NP.AtlasExists(NP.Art.searchAtlas) and pcall(icon.SetAtlas, icon, NP.Art.searchAtlas) then
        local hl = button:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(icon)
        pcall(hl.SetAtlas, hl, NP.Art.searchAtlas)
        hl:SetBlendMode("ADD")
        hl:SetAlpha(0.5)
        button.Icon = icon
        button.NPLook = "atlas"
    else
        icon:Hide()
        local fs = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("CENTER")
        fs:SetText("Find")
        button:SetFontString(fs)
        button:SetWidth(30)
        button.NPLook = "text"
    end
    button:SetScript("OnClick", function() NP.ToggleSearch() end)
    button:SetScript("OnEnter", Tooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    panel = CreateFrame("Frame", nil, inset)
    panel:SetAllPoints(inset)
    panel:SetFrameLevel(inset:GetFrameLevel() + 30) -- over the text box, its scroll bar and the checklist
    panel:EnableMouse(true)                          -- clicks don't fall through to the text
    panel:EnableMouseWheel(true)
    panel:Hide()
    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", 3, -3)
    bg:SetPoint("BOTTOMRIGHT", -3, 3)
    bg:SetColorTexture(unpack(NP.Color.searchBg))

    box = CreateBox(panel)
    box:SetHeight(20)
    box:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -6)
    box:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -10, -6)

    for i = 1, MAX_ROWS do CreateRow(i) end
    status = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    status:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 10, 6)
    status:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -24, 6) -- clear of the resize grip
    status:SetJustifyH("LEFT")
    status:SetWordWrap(false)
    status:SetHeight(14)

    panel:SetScript("OnMouseWheel", function(_, delta)
        offset = offset - delta * 3
        Refresh()
    end)
    panel:SetScript("OnSizeChanged", Refresh)
    panel:SetScript("OnShow", Run) -- notes may have changed since it was last open
    panel:SetScript("OnHide", function()
        box:ClearFocus()
        if button then button:UnlockHighlight() end
    end)
    return button
end
