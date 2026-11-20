-- Note Pad: core (saved data, events, slash commands)
local addonName, NP = ...

NP.DB_VERSION = 2
NP.MAX_NOTES = 20

-- `notes` is not in here: it is an array and is checked by NormalizeNotes.
-- The old v1 key `text` is not in here either: it is kept only as a backup.
-- `settings` and `window.shown` are new in Beta A; older versions keep (and ignore) them.
NP.defaults = {
    current = 1,
    window = { point = "CENTER", relPoint = "CENTER", x = 0, y = 0, w = 420, h = 320, minimized = false, shown = false },
    minimap = { angle = 225, hide = false },
    settings = { fontSize = 14, alpha = 1, locked = false, rememberOpen = false },
}

-- Settings limits (Settings.lua uses them; RepairDB keeps saved values inside them).
NP.FONT_MIN, NP.FONT_MAX = 10, 18
NP.ALPHA_MIN = 0.3

-- Every Blizzard template the addon uses, in one place (a missing one falls back to own frames).
NP.Templates = {
    window      = "ButtonFrameTemplate",
    backdrop    = "BackdropTemplate",
    scrollEdit  = "ScrollingEditBoxTemplate",
    scrollBar   = "MinimalScrollBar",
    scrollFrame = "UIPanelScrollFrameTemplate",
    close       = "UIPanelCloseButton",
    fold        = "MaximizeMinimizeButtonFrameTemplate",
    tab         = "PanelTopTabButtonTemplate",
    button      = "UIPanelButtonTemplate",
    input       = "InputBoxTemplate",
    check       = "UICheckButtonTemplate",
    search      = "SearchBoxTemplate",
}

-- All art in one place: paths to Blizzard art that ships with the game (no bundled files).
NP.Art = {
    icon             = "Interface\\Icons\\INV_Misc_Note_01",
    minimapBorder    = "Interface\\Minimap\\MiniMap-TrackingBorder",
    minimapBg        = "Interface\\Minimap\\UI-Minimap-Background",
    minimapHighlight = "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight",
    gripUp           = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up",
    gripDown         = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down",
    gripHighlight    = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight",
    redButtonUp      = "Interface\\Buttons\\UI-Panel-Button-Up",
    redButtonDown    = "Interface\\Buttons\\UI-Panel-Button-Down",
    redButtonHighlight = "Interface\\Buttons\\UI-Panel-Button-Highlight",
    pagePrevUp       = "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up",
    pagePrevDown     = "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down",
    pagePrevDisabled = "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Disabled",
    pageNextUp       = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up",
    pageNextDown     = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down",
    pageNextDisabled = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Disabled",
    pageHighlight    = "Interface\\Buttons\\UI-Common-MouseHilight",
    tooltipBg        = "Interface\\Tooltips\\UI-Tooltip-Background",
    tooltipBorder    = "Interface\\Tooltips\\UI-Tooltip-Border",
    dialogBg         = "Interface\\DialogFrame\\UI-DialogBox-Background",
    dialogBorder     = "Interface\\DialogFrame\\UI-DialogBox-Border",
    smallerUp        = "Interface\\Buttons\\UI-Panel-SmallerButton-Up",
    smallerDown      = "Interface\\Buttons\\UI-Panel-SmallerButton-Down",
    biggerUp         = "Interface\\Buttons\\UI-Panel-BiggerButton-Up",
    biggerDown       = "Interface\\Buttons\\UI-Panel-BiggerButton-Down",
    minimizeHighlight = "Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight",
    -- checklist (own tick box only when UICheckButtonTemplate is missing)
    checkUp          = "Interface\\Buttons\\UI-CheckBox-Up",
    checkDown        = "Interface\\Buttons\\UI-CheckBox-Down",
    checkHighlight   = "Interface\\Buttons\\UI-CheckBox-Highlight",
    checkMark        = "Interface\\Buttons\\UI-CheckBox-Check",
    rowHighlight     = "Interface\\QuestFrame\\UI-QuestTitleHighlight",
    -- atlases (checked with C_Texture.GetAtlasInfo before use)
    settingsAtlas    = "questlog-icon-setting",              -- cog in the title bar
    cornerDouble     = "UI-Frame-Metal-CornerTopRightDouble", -- metal corner behind [v][X]
    searchAtlas      = "common-search-magnifyingglass",      -- search button (SearchBoxTemplate's icon)
}

-- All colours in one place: Blizzard's named colours where they exist, else the same values.
local function NamedColor(global, r, g, b)
    local c = _G[global]
    if type(c) == "table" and c.GetRGB then
        local cr, cg, cb = c:GetRGB()
        return { cr, cg, cb, 1 }
    end
    return { r, g, b, 1 }
end

NP.Color = {
    gold        = NamedColor("NORMAL_FONT_COLOR", 1, 0.82, 0),
    white       = NamedColor("HIGHLIGHT_FONT_COLOR", 1, 1, 1),
    grey        = NamedColor("GRAY_FONT_COLOR", 0.5, 0.5, 0.5),
    tabText     = { 0.85, 0.85, 0.85, 1 },
    tabBg       = { 0.06, 0.06, 0.06, 0.9 },
    tabBorder   = { 0.45, 0.45, 0.45, 1 },
    tabSelBg    = { 0.25, 0.2, 0.05, 0.95 },
    tabPlainBg  = { 0.1, 0.1, 0.1, 0.9 },
    tabPlainSel = { 0.35, 0.28, 0.05, 0.95 },
    barBg       = { 0.05, 0.05, 0.05, 0.95 },
    barBorder   = { 0.6, 0.6, 0.6, 1 },
    edgeOuter   = { 0, 0, 0, 1 },          -- folded bar: outer 1 px line
    edgeInner   = { 0.55, 0.42, 0.22, 1 }, -- folded bar: inner 1 px line (bronze, like the metal)
    red         = { 0.55, 0.05, 0.05, 1 },
    renameBg    = { 0, 0, 0, 1 },
    hover       = { 1, 1, 1, 0.08 },
    rowHover    = { 1, 1, 1, 0.1 },        -- checklist row highlight when the quest-log art is missing
    inputBg     = { 0, 0, 0, 0.5 },        -- checklist boxes without InputBoxTemplate
    inputBorder = { 0.45, 0.45, 0.45, 1 },
    searchBg    = { 0.03, 0.03, 0.03, 0.97 }, -- search results over the text (must hide it)
}
NP.Color.hint = NP.Color.grey -- "Left-click: ..." lines in every tooltip
NP.TICKED_ALPHA = 0.5 -- ticked checklist lines are dimmed (WoW text has no strike-through)

-- Text in Blizzard's gold (NORMAL_FONT_COLOR).
function NP.GoldText(s)
    s = tostring(s)
    if NORMAL_FONT_COLOR and NORMAL_FONT_COLOR.WrapTextInColorCode then
        return NORMAL_FONT_COLOR:WrapTextInColorCode(s)
    end
    return "|cffffd100" .. s .. "|r"
end

function NP.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(NP.GoldText("Note Pad:") .. " " .. tostring(msg))
end

-- Fill missing or wrongly typed keys from defaults; never touch keys that are fine.
local function ApplyDefaults(db, defaults)
    for key, def in pairs(defaults) do
        if type(def) == "table" then
            if type(db[key]) ~= "table" then db[key] = {} end
            ApplyDefaults(db[key], def)
        elseif type(db[key]) ~= type(def) then
            db[key] = def
        end
    end
end

-- Small fingerprint of a text, so the v1 backup text isn't recovered twice.
local function TextHash(s)
    local h = 5381
    for i = 1, #s do
        h = (h * 33 + s:byte(i)) % 4294967296
    end
    return #s .. ":" .. h
end
NP.TextHash = TextHash

-- "Note N" with N = the tab number the note gets (`pos`, default: a new last tab);
-- if another note already has that name, the next free number above it.
-- prefix: "Note" (default) or e.g. "List" for checklists.
function NP.NewNoteTitle(notes, pos, prefix)
    prefix = prefix or "Note"
    local used = {}
    for _, n in ipairs(notes) do
        if n.title then used[n.title] = true end
    end
    local i = math.max(1, math.floor(tonumber(pos) or (#notes + 1)))
    while used[prefix .. " " .. i] do i = i + 1 end
    return prefix .. " " .. i
end

-- Checklists ---------------------------------------------------------------------
-- A checklist is a note with kind = "checklist" and items = { { text = s, done = bool }, ... }.
-- Its `text` always holds a readable copy ("[x] line" / "[ ] line"), so older versions of
-- Note Pad (which only know `text`) still show the list. mirrorHash = TextHash of that copy:
-- if `text` no longer matches it, an older version edited it and the text is recovered.

NP.CHECKLIST_MAX_LINES = 200

function NP.IsChecklist(note)
    return type(note) == "table" and note.kind == "checklist"
end

-- One line of a checklist: no line breaks.
function NP.CleanLine(s)
    s = tostring(s or ""):gsub("[\r\n]+", " ")
    return strtrim(s)
end

function NP.ChecklistItemsToText(items)
    local out = {}
    for i, it in ipairs(items) do
        out[i] = (it.done and "[x] " or "[ ] ") .. it.text
    end
    return table.concat(out, "\n")
end

-- Text -> lines; "[x] " / "[ ] " at the start sets the tick; blank lines are skipped.
function NP.ChecklistTextToItems(text)
    local items = {}
    for line in (tostring(text or "") .. "\n"):gmatch("([^\n]*)\n") do
        line = line:gsub("\r", "")
        local mark, rest = line:match("^%s*%[([xX ])%]%s?(.*)$")
        local item
        if mark then
            item = { text = NP.CleanLine(rest), done = (mark ~= " ") }
        else
            item = { text = NP.CleanLine(line), done = false }
        end
        if item.text ~= "" then items[#items + 1] = item end
    end
    return items
end

-- Rewrite the readable copy after a change.
function NP.UpdateChecklistMirror(note)
    note.text = NP.ChecklistItemsToText(note.items)
    note.mirrorHash = TextHash(note.text)
end

-- done, total
function NP.ChecklistCounts(note)
    local done, total = 0, 0
    if NP.IsChecklist(note) and type(note.items) == "table" then
        for _, it in ipairs(note.items) do
            total = total + 1
            if it.done then done = done + 1 end
        end
    end
    return done, total
end

-- "|cff..|Hitem:..|h[Name]|h|r" -> "[Name]" (for tooltips and previews).
function NP.PlainText(s)
    s = tostring(s or "")
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1")
    return s
end

-- Repair one checklist; never drops a line that holds text. Returns text an older
-- version typed into it (to be kept as a "Recovered note"), or nil.
local function NormalizeChecklist(n)
    local items = {}
    local src = n.items
    if type(src) == "table" then
        local keys = {}
        for k in pairs(src) do
            if type(k) == "number" then keys[#keys + 1] = k end
        end
        table.sort(keys)
        for _, k in ipairs(keys) do
            local it = src[k]
            local text, done
            if type(it) == "string" or type(it) == "number" then
                text, done = tostring(it), false
            elseif type(it) == "table" then
                text = (type(it.text) == "string" or type(it.text) == "number") and tostring(it.text) or ""
                done = (it.done == true)
            end
            text = text and NP.CleanLine(text) or ""
            if text ~= "" then items[#items + 1] = { text = text, done = done } end
        end
    end
    local recovered
    if #items == 0 and n.text ~= "" then
        items = NP.ChecklistTextToItems(n.text) -- lines missing or broken: the copy is all we have
    elseif n.text ~= "" and n.text ~= NP.ChecklistItemsToText(items) then
        -- not our own copy (hash differs or missing): typed in by an older version, keep it
        local hash = type(n.mirrorHash) == "string" and n.mirrorHash or nil
        if hash == nil or TextHash(n.text) ~= hash then recovered = n.text end
    end
    n.items = items
    NP.UpdateChecklistMirror(n)
    -- the exact text of the note it was made from (see NP.ConvertNote): kept only as a pair
    if type(n.noteText) ~= "string" or type(n.noteMirror) ~= "string" then
        n.noteText, n.noteMirror = nil, nil
    end
    return recovered
end

-- `base`, or "base 2", "base 3" ... if a note already has that name.
local function UniqueTitle(notes, base)
    local used = {}
    for _, n in ipairs(notes) do
        if type(n) == "table" and n.title then used[n.title] = true end
    end
    if not used[base] then return base end
    local i = 2
    while used[base .. " " .. i] do i = i + 1 end
    return base .. " " .. i
end

-- Make `db.notes` a clean array of { title = string, text = string }.
-- Fixes bad entries key by key; never drops an entry that holds text.
local function NormalizeNotes(db)
    local fixed, recovered = {}, {}
    local src = db.notes
    if type(src) == "string" or type(src) == "number" then
        src = { tostring(src) }
    end
    if type(src) == "table" then
        local keys = {}
        for k in pairs(src) do
            if type(k) == "number" then keys[#keys + 1] = k end
        end
        table.sort(keys)
        for _, k in ipairs(keys) do
            local n = src[k]
            if type(n) == "string" or type(n) == "number" then
                n = { text = tostring(n) }
            end
            if type(n) == "table" then
                if type(n.text) == "number" then n.text = tostring(n.text) end
                if type(n.text) ~= "string" then n.text = "" end
                if type(n.title) == "number" then n.title = tostring(n.title) end
                if type(n.title) ~= "string" or n.title:match("^%s*$") then n.title = nil end
                -- other `kind` values (from a newer version) are left alone and shown as notes
                if n.kind == "checklist" then
                    recovered[#recovered + 1] = NormalizeChecklist(n)
                end
                fixed[#fixed + 1] = n
            end
        end
    end
    for _, text in ipairs(recovered) do
        fixed[#fixed + 1] = { title = UniqueTitle(fixed, "Recovered note"), text = text }
    end
    for i, n in ipairs(fixed) do
        if not n.title then n.title = NP.NewNoteTitle(fixed, i, NP.IsChecklist(n) and "List" or nil) end
    end
    if #fixed == 0 then
        fixed[1] = { title = "Note 1", text = "" }
    end
    db.notes = fixed
    if db.current < 1 or db.current > #fixed or db.current ~= math.floor(db.current) then
        db.current = 1
    end
end

-- v1 -> v2: the single note becomes the first tab. Safe to run on any data.
function NP.MigrateDB(db)
    local oldVersion = type(db.dbVersion) == "number" and db.dbVersion or 0
    local hadNotes = db.notes ~= nil
    local v1Text = type(db.text) == "string" and db.text or nil

    if not hadNotes then
        db.notes = { { title = "Note 1", text = v1Text or "" } }
        db.current = 1
        if v1Text then db.v1Hash = TextHash(v1Text) end
    end

    NormalizeNotes(db)

    -- Someone went back to v0.0.1 (it sets dbVersion to 1), typed there, and came back:
    -- keep that text as an extra tab unless a tab already holds it.
    if hadNotes and oldVersion < 2 and v1Text and v1Text ~= "" then
        local hash = TextHash(v1Text)
        if hash ~= db.v1Hash then
            local found = false
            for _, n in ipairs(db.notes) do
                if n.text == v1Text then found = true break end
            end
            if not found then
                db.notes[#db.notes + 1] = { title = UniqueTitle(db.notes, "Recovered note"), text = v1Text }
            end
            db.v1Hash = hash
        end
    end
end

-- The window's saved place: only real anchor names and real numbers (a damaged file
-- would otherwise make SetPoint fail while the addon loads).
local POINTS = { TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true, RIGHT = true,
    BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true }
local function Finite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end

local function RepairWindow(win)
    local d = NP.defaults.window
    if not POINTS[win.point] or not POINTS[win.relPoint] or not Finite(win.x) or not Finite(win.y) then
        win.point, win.relPoint, win.x, win.y = d.point, d.relPoint, d.x, d.y
    end
    if not Finite(win.w) then win.w = d.w end
    if not Finite(win.h) then win.h = d.h end
end

-- Recently deleted notes (for /np undo), saved so a /reload doesn't lose them:
-- db.deleted = { { note = <note>, pos = n, seq = n }, ... }, oldest first, at most NP.UNDO_NOTES.
NP.UNDO_NOTES = 3

local function RepairDeleted(db)
    local src = db.deleted
    if type(src) ~= "table" then
        db.deleted = nil
        return
    end
    local keys = {}
    for k in pairs(src) do
        if type(k) == "number" then keys[#keys + 1] = k end
    end
    table.sort(keys)
    local list = {}
    for _, k in ipairs(keys) do
        local e = src[k]
        local n = type(e) == "table" and e.note
        if type(n) == "table" then
            if type(n.text) == "number" then n.text = tostring(n.text) end
            if type(n.text) ~= "string" then n.text = "" end
            if type(n.title) == "number" then n.title = tostring(n.title) end
            if type(n.title) ~= "string" or n.title:match("^%s*$") then n.title = "Deleted note" end
            local recovered = (n.kind == "checklist") and NormalizeChecklist(n) or nil
            -- NaN / junk -> 1; endless or too big -> after the last note
            local pos = (type(e.pos) == "number" and e.pos >= 1) and math.min(math.floor(e.pos), NP.MAX_NOTES + 1) or 1
            local seq = Finite(e.seq) and e.seq or 0
            list[#list + 1] = { note = n, pos = pos, seq = seq }
            if recovered then
                list[#list + 1] = { note = { title = "Recovered note", text = recovered }, pos = pos, seq = seq }
            end
        end
    end
    while #list > NP.UNDO_NOTES do table.remove(list, 1) end
    db.deleted = (#list > 0) and list or nil
end

-- Text size: a whole number in FONT_MIN..FONT_MAX; opacity: ALPHA_MIN..1 (junk -> defaults).
local function RepairSettings(s)
    local d = NP.defaults.settings
    if Finite(s.fontSize) then
        s.fontSize = math.max(NP.FONT_MIN, math.min(NP.FONT_MAX, math.floor(s.fontSize + 0.5)))
    else
        s.fontSize = d.fontSize
    end
    if Finite(s.alpha) then
        s.alpha = math.max(NP.ALPHA_MIN, math.min(1, s.alpha))
    else
        s.alpha = d.alpha
    end
end

-- Character notebooks (Beta B): db.chars["Name-Realm"] = { notes = {...}, current = n,
-- deleted = {...}, use = true|false }. Each book is repaired like the account book; nothing
-- that holds text is dropped (a book saved as plain text becomes a book with that note).
local function RepairChars(db)
    local src = db.chars
    if src == nil then return end
    if type(src) ~= "table" then
        -- never written like this by Note Pad: keep any text as an account note
        if (type(src) == "string" and src ~= "") or type(src) == "number" then
            db.notes[#db.notes + 1] = { title = UniqueTitle(db.notes, "Recovered note"), text = tostring(src) }
        end
        db.chars = nil
        return
    end
    local fixed = {}
    for k, b in pairs(src) do
        if type(b) == "string" or type(b) == "number" then b = { notes = b } end
        if type(b) == "table" then
            local key = tostring(k)
            while fixed[key] do key = key .. "+" end -- a number key and the same text as a key
            if not Finite(b.current) then b.current = 1 end
            b.use = (b.use == true)
            NormalizeNotes(b)
            RepairDeleted(b)
            fixed[key] = b
        end
    end
    db.chars = next(fixed) and fixed or nil
end

-- Defaults + repair + migration on any table (the self-test runs it on a copy).
function NP.RepairDB(db)
    ApplyDefaults(db, NP.defaults)
    RepairWindow(db.window)
    RepairSettings(db.settings)
    NP.MigrateDB(db)
    RepairDeleted(db)
    RepairChars(db)
    db.dbVersion = NP.DB_VERSION
    return db
end

-- Notebooks ------------------------------------------------------------------------
-- The account book is NotePadDB itself (notes, current, deleted: as before, so older versions
-- still read it). A character's own book lives in NotePadDB.chars; `use` says which one this
-- character has open. Every note list goes through NP.Book().

-- "Name-Realm" of the logged-in character, or nil while the game doesn't know it yet.
local function CharKey()
    local name = UnitName and UnitName("player")
    local realm = GetRealmName and GetRealmName()
    if type(name) ~= "string" or name == "" or name == UNKNOWNOBJECT or name == "Unknown" then return nil end
    if type(realm) ~= "string" or realm == "" then return nil end
    return name .. "-" .. realm, name
end

function NP.UpdateCharKey()
    NP.charKey, NP.charName = CharKey()
    return NP.charKey
end

-- This character's book (create = make it if it isn't there), or nil.
function NP.CharBook(create)
    local db, key = NP.db, NP.charKey
    if not db or not key then return nil end
    local b = type(db.chars) == "table" and db.chars[key] or nil
    if not b and create then
        if type(db.chars) ~= "table" then db.chars = {} end
        b = { notes = { { title = "Note 1", text = "" } }, current = 1, use = false }
        db.chars[key] = b
    end
    return b
end

function NP.UsingCharBook()
    local b = NP.CharBook()
    return b ~= nil and b.use == true
end

-- The open notebook: { notes = {...}, current = n, deleted = {...} }.
function NP.Book()
    local b = NP.CharBook()
    if b and b.use == true then return b end
    return NP.db
end

-- The other notebook (account <-> this character), or nil if this character has none yet.
function NP.OtherBook()
    if NP.UsingCharBook() then return NP.db end
    return NP.CharBook()
end

-- Which book holds `note` (nil if none).
function NP.BookOf(note)
    for _, b in ipairs({ NP.db, NP.CharBook() or false }) do
        if b then
            for _, n in ipairs(b.notes) do
                if n == note then return b end
            end
        end
    end
end

-- on = this character's own notes; off = the account notes (all characters).
function NP.SetCharBook(on)
    on = not not on
    -- the name may have come after PLAYER_LOGIN: look again before refusing
    if not NP.charKey and NP.UpdateCharKey() and NP.UsingCharBook() then
        if NP.OnBookChanged then NP.OnBookChanged() end -- its notebook was in use: show it now
    end
    if NP.UsingCharBook() == on then return on end
    if on and not NP.charKey then
        NP.Print("The character's name isn't known yet. Try again in a moment.")
        return false
    end
    -- everything open goes into the book it belongs to first
    if NP.SaveText then NP.SaveText() end
    if NP.FinishLineEdit then NP.FinishLineEdit(true) end
    if NP.FinishRename then NP.FinishRename(true) end
    local b = NP.CharBook(on)
    if b then b.use = on end
    if NP.OnBookChanged then NP.OnBookChanged() end
    return on
end

-- "Account" or the character's name (menus, title, chat).
function NP.BookName(book)
    if book and book ~= NP.db then return NP.charName or "Character" end
    return "Account"
end

-- Undo ---------------------------------------------------------------------------
-- Deleted notes (saved, see above) and removed checklist lines (this session only) share
-- one order (seq): /np undo brings back the newest.

local undoSeq = 0
local lineUndo = {}         -- { seq =, note = <checklist>, lines = { { i = index, item = item }, ... } }
local LINE_UNDO_MAX = 10

local function NextSeq()
    undoSeq = undoSeq + 1
    return undoSeq
end

function NP.PushDeletedNote(note, pos)
    local db = NP.Book() -- each notebook keeps its own deleted notes
    db.deleted = db.deleted or {}
    db.deleted[#db.deleted + 1] = { note = note, pos = pos, seq = NextSeq() }
    while #db.deleted > NP.UNDO_NOTES do table.remove(db.deleted, 1) end
end

-- lines: { { i = original index, item = item }, ... } in ascending index order
function NP.PushRemovedLines(note, lines)
    if #lines == 0 then return end
    lineUndo[#lineUndo + 1] = { seq = NextSeq(), note = note, lines = lines }
    while #lineUndo > LINE_UNDO_MAX do table.remove(lineUndo, 1) end
end

local function IndexOfNote(note)
    for i, n in ipairs(NP.Book().notes) do
        if n == note then return i end
    end
end

-- What /np undo would bring back in the open notebook: "note", entry | "lines", entry | nil.
local function UndoTop()
    -- line entries whose checklist is gone (deleted, or turned into a note) can't come back;
    -- those of a checklist in the other notebook wait until it is open again
    local l
    for k = #lineUndo, 1, -1 do
        local e = lineUndo[k]
        if not NP.IsChecklist(e.note) or not NP.BookOf(e.note) then
            table.remove(lineUndo, k)
        elseif not l and IndexOfNote(e.note) then
            l = e
        end
    end
    local deleted = NP.Book().deleted
    local d = deleted and deleted[#deleted]
    if d and (not l or d.seq >= l.seq) then return "note", d end
    if l then return "lines", l end
    return nil
end

function NP.CanUndo() return UndoTop() ~= nil end

-- Short text for menus: what undo would bring back.
function NP.UndoLabel()
    local kind, e = UndoTop()
    if kind == "note" then return "Bring back \"" .. e.note.title .. "\"" end
    if kind == "lines" then
        return #e.lines == 1 and "Bring back 1 line" or ("Bring back " .. #e.lines .. " lines")
    end
    return nil
end

function NP.Undo()
    local db = NP.Book()
    local kind, e = UndoTop()
    if not kind then
        NP.Print("Nothing to bring back.")
        return false
    end
    if kind == "note" then
        if #db.notes >= NP.MAX_NOTES then
            NP.Print(NP.MAX_NOTES .. " notes is the most. Delete one to bring \"" .. NP.GoldText(e.note.title) .. "\" back.")
            return false
        end
        table.remove(db.deleted)
        if #db.deleted == 0 then db.deleted = nil end
        NP.SaveText()
        local pos = math.min(e.pos, #db.notes + 1)
        table.insert(db.notes, pos, e.note)
        if db.current >= pos then db.current = db.current + 1 end
        if NP.OpenWindow then NP.OpenWindow() end
        if NP.ShowNote then NP.ShowNote(pos) end
        NP.Print("Brought back \"" .. NP.GoldText(e.note.title) .. "\".")
        return true
    end
    -- lines
    local note = e.note
    local room = NP.CHECKLIST_MAX_LINES - #note.items
    if room < #e.lines then
        NP.Print("A checklist can have up to " .. NP.CHECKLIST_MAX_LINES .. " lines; \"" .. NP.GoldText(note.title) .. "\" is too full.")
        return false
    end
    for k = #lineUndo, 1, -1 do
        if lineUndo[k] == e then table.remove(lineUndo, k) break end
    end
    for _, l in ipairs(e.lines) do -- ascending: each goes back to its old place
        table.insert(note.items, math.min(l.i, #note.items + 1), l.item)
    end
    NP.UpdateChecklistMirror(note)
    local idx = IndexOfNote(note)
    if NP.OpenWindow then NP.OpenWindow() end
    if idx and NP.ShowNote then NP.ShowNote(idx) end
    if NP.ChecklistRefresh then NP.ChecklistRefresh(note) end
    NP.Print(#e.lines == 1 and ("Brought back 1 line in \"" .. NP.GoldText(note.title) .. "\".")
        or ("Brought back " .. #e.lines .. " lines in \"" .. NP.GoldText(note.title) .. "\"."))
    return true
end

function NP.InitDB()
    if type(NotePadDB) ~= "table" then NotePadDB = {} end
    NP.db = NP.RepairDB(NotePadDB)
    NP.UpdateCharKey()
    local books = { NP.db }
    for _, b in pairs(NP.db.chars or {}) do books[#books + 1] = b end
    for _, b in ipairs(books) do
        for _, e in ipairs(b.deleted or {}) do
            if e.seq > undoSeq then undoSeq = e.seq end
        end
    end
end

function NP.CurrentNote()
    local db = NP.Book()
    return db.notes[db.current] or db.notes[1]
end

-- Called from the minimap's addon menu (TOC field AddonCompartmentFunc).
function NotePad_ToggleFromCompartment()
    if NP.ToggleWindow then NP.ToggleWindow() end
end

-- The first note (tab order) whose name is `text`, else the first whose name starts with it;
-- case-insensitive (ASCII letters only, like strlower). Returns the index or nil.
function NP.FindNoteByName(text)
    local want = strlower(strtrim(tostring(text or "")))
    if want == "" then return nil end
    local notes = NP.Book().notes
    for i, n in ipairs(notes) do
        if strlower(n.title or "") == want then return i end
    end
    for i, n in ipairs(notes) do
        if strlower(n.title or ""):sub(1, #want) == want then return i end
    end
    return nil
end

-- Typed text shown back in chat: no colour or link codes.
local function Shown(s)
    s = tostring(s):gsub("|", "||")
    if #s > 40 then s = s:sub(1, 37) .. "..." end
    return s
end

local function OpenByName(name)
    local i = NP.FindNoteByName(name)
    if i then
        NP.ShowNote(i) -- before and after opening, as for /np <number>
        NP.OpenWindow()
        NP.ShowNote(i)
    else
        NP.Print("No note starting with \"" .. Shown(name) .. "\". Type /np help for the commands.")
    end
end

local function OnOff(on) return on and "on" or "off" end

function NP.PrintBook()
    if NP.UsingCharBook() then
        NP.Print("Notebook: " .. NP.GoldText(NP.BookName(NP.Book())) .. " (only this character). /np char goes back to the account notes.")
    else
        NP.Print("Notebook: " .. NP.GoldText("Account") .. " (all characters). /np char opens this character's own notes.")
    end
end

local function PrintHelp()
    NP.Print("/np - open or close Note Pad")
    NP.Print("/np new - add a new note")
    NP.Print("/np list - add a new checklist")
    NP.Print("/np 2 - open note 2 (any number works)")
    NP.Print("/np raid - open the note whose name starts with \"raid\" (/np open <name> for any name)")
    NP.Print("/np undo - bring back the last deleted note or checklist lines")
    NP.Print("/np size 14 - text size (" .. NP.FONT_MIN .. " to " .. NP.FONT_MAX .. "); Ctrl + mouse wheel over the text works too")
    NP.Print("/np opacity 80 - see-through window (" .. math.floor(NP.ALPHA_MIN * 100) .. " to 100); full while the mouse is on it")
    NP.Print("/np lock - lock or unlock the window's place and size")
    NP.Print("/np remember - open Note Pad after login if it was open")
    NP.Print("/np char - switch between the account notes and this character's own notes")
    NP.Print("/np find gold - search all notes (Ctrl+F in the text works too)")
    NP.Print("/np reset - put the window back in the middle")
    NP.Print("/np minimap - show or hide the minimap button")
    NP.Print("/np selftest - check the addon and show a line to copy")
    NP.Print("Tabs: [+] adds a note. Double-click a tab to rename it, right-click for more, drag it to move it. Ctrl+Tab switches notes.")
    NP.Print("To fold the window, double-click its title bar or right-click the minimap button. Right-click the title bar (or the cog) for settings.")
end

local function HandleSlash(msg)
    local raw = strtrim(tostring(msg or "")):gsub("%s+", " ") -- "selftest  full" = "selftest full"
    local cmd = strlower(raw)
    local word, rest = cmd:match("^(%S+) ?(.*)$")
    local rawRest = raw:match("^%S+ (.*)$") or ""
    if cmd == "" then
        NP.ToggleWindow()
    elseif cmd == "new" then
        NP.OpenWindow()
        NP.AddNote()
    elseif cmd == "list" then
        NP.OpenWindow()
        NP.AddNote("checklist")
    elseif cmd == "selftest" or cmd == "selftest full" then
        if NP.SelfTest then NP.SelfTest:Start(cmd == "selftest full" and "full" or "quick") end
    elseif cmd:match("^%d+$") then
        local n = tonumber(cmd)
        local notes = NP.Book().notes
        local count = #notes
        if notes[n] then
            -- before and after opening, so nothing that runs while the window opens can switch it back
            NP.ShowNote(n)
            NP.OpenWindow()
            NP.ShowNote(n)
        else
            -- the digits as typed (no "1e+20"), without leading zeros
            local shown = cmd:gsub("^0+(%d)", "%1")
            if #shown > 9 then shown = shown:sub(1, 6) .. "..." end
            NP.Print("There is no note " .. shown .. ". You have " .. count .. (count == 1 and " note." or " notes."))
        end
    elseif cmd == "undo" then
        NP.Undo()
    elseif cmd == "reset" then
        NP.ResetWindow()
        NP.Print("The window is back in the middle of the screen.")
    elseif cmd == "minimap" then
        NP.ToggleMinimapButton()
    elseif cmd == "help" then
        PrintHelp()
    elseif word == "open" then
        if rawRest == "" then
            NP.Print("Type /np open and the start of a note's name, e.g. /np open raid.")
        else
            OpenByName(rawRest)
        end
    elseif word == "size" then
        local n = tonumber(rest)
        if rest == "" then
            NP.Print("Text size is " .. NP.db.settings.fontSize .. ". Type /np size " .. NP.FONT_MIN .. " to /np size " .. NP.FONT_MAX .. ".")
        elseif not n or n ~= n then
            NP.Print("Type a number, e.g. /np size 14 (" .. NP.FONT_MIN .. " to " .. NP.FONT_MAX .. ").")
        else
            local got = NP.SetFontSize(n)
            local note = ""
            if n < NP.FONT_MIN or n > NP.FONT_MAX then
                note = " (sizes go from " .. NP.FONT_MIN .. " to " .. NP.FONT_MAX .. ")"
            elseif n ~= math.floor(n) then
                note = " (whole sizes only)"
            end
            NP.Print("Text size: " .. got .. note .. ".")
        end
    elseif word == "opacity" then
        local n = tonumber((rest:gsub("%%$", "")))
        local lo = math.floor(NP.ALPHA_MIN * 100)
        if rest == "" then
            NP.Print("Opacity is " .. math.floor(NP.db.settings.alpha * 100 + 0.5) .. "%. Type /np opacity " .. lo .. " to /np opacity 100.")
        elseif not n or n ~= n then
            NP.Print("Type a number, e.g. /np opacity 80 (" .. lo .. " to 100).")
        else
            if n > 0 and n <= 1 then n = n * 100 end -- 0.5 means 50 %
            local got = math.floor(NP.SetOpacity(n / 100) * 100 + 0.5)
            local note = (n < lo or n > 100) and (" (opacity goes from " .. lo .. " to 100%)") or ""
            NP.Print("Opacity: " .. got .. "%" .. note .. ".")
        end
    elseif cmd == "lock" then
        local on = NP.SetLocked(not NP.db.settings.locked)
        NP.Print(on and "The window is locked: it can't be moved or resized. /np lock unlocks it."
            or "The window is unlocked.")
    elseif cmd == "remember" then
        local on = NP.SetRememberOpen(not NP.db.settings.rememberOpen)
        NP.Print("Open after login if it was open: " .. OnOff(on) .. ".")
    elseif cmd == "char" then
        local want = not NP.UsingCharBook()
        if NP.SetCharBook(want) == want then NP.PrintBook() end
    elseif word == "find" then
        NP.OpenWindow()
        if NP.OpenSearch then NP.OpenSearch(rawRest) end
    else
        -- not a command: the start of a note's name
        OpenByName(raw)
    end
end

SLASH_NOTEPAD1 = "/np"
SLASH_NOTEPAD2 = "/notepad"
SlashCmdList["NOTEPAD"] = HandleSlash

-- Key Bindings > AddOns (Bindings.xml): one key to open or close the window.
BINDING_HEADER_NOTEPAD = "Note Pad"
BINDING_NAME_NOTEPAD_TOGGLE = "Open or close Note Pad"
function NotePad_ToggleBinding()
    if NP.ToggleWindow then NP.ToggleWindow() end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGOUT")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event, arg1)
    if event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        -- the character's name wasn't known at ADDON_LOADED: find its notebook now
        if NP.db and not NP.charKey and NP.UpdateCharKey() and NP.UsingCharBook() and NP.OnBookChanged then
            NP.OnBookChanged()
        end
        return
    end
    if event == "ADDON_LOADED" and arg1 == addonName then
        self:UnregisterEvent("ADDON_LOADED")
        NP.InitDB()
        if NP.ApplyFonts then NP.ApplyFonts() end -- before the window: its boxes use the fonts
        NP.CreateWindow()
        NP.CreateMinimapButton()
        if NP.SetupSettings then NP.SetupSettings() end -- opacity, lock, Ctrl+wheel, reopen
    elseif event == "PLAYER_LOGOUT" then
        NP.loggingOut = true -- the UI closing frames now must not count as "the user closed it"
        if NP.SaveText then NP.SaveText() end
        if NP.FinishLineEdit then NP.FinishLineEdit(true) end
    end
end)
