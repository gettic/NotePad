-- Note Pad: core (saved data, events, slash commands)
local addonName, NP = ...

NP.DB_VERSION = 2
NP.MAX_NOTES = 20

-- `notes` is not in here: it is an array and is checked by NormalizeNotes.
-- The old v1 key `text` is not in here either: it is kept only as a backup.
NP.defaults = {
    current = 1,
    window = { point = "CENTER", relPoint = "CENTER", x = 0, y = 0, w = 420, h = 320, minimized = false },
    minimap = { angle = 225, hide = false },
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
}

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

-- "Note N" with N = the tab number the note gets (`pos`, default: a new last tab);
-- if another note already has that name, the next free number above it.
function NP.NewNoteTitle(notes, pos)
    local used = {}
    for _, n in ipairs(notes) do
        if n.title then used[n.title] = true end
    end
    local i = math.max(1, math.floor(tonumber(pos) or (#notes + 1)))
    while used["Note " .. i] do i = i + 1 end
    return "Note " .. i
end

-- Make `db.notes` a clean array of { title = string, text = string }.
-- Fixes bad entries key by key; never drops an entry that holds text.
local function NormalizeNotes(db)
    local fixed = {}
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
                fixed[#fixed + 1] = n
            end
        end
    end
    for i, n in ipairs(fixed) do
        if not n.title then n.title = NP.NewNoteTitle(fixed, i) end
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
                db.notes[#db.notes + 1] = { title = "Recovered note", text = v1Text }
            end
            db.v1Hash = hash
        end
    end
end

function NP.InitDB()
    if type(NotePadDB) ~= "table" then NotePadDB = {} end
    local db = NotePadDB
    ApplyDefaults(db, NP.defaults)
    NP.MigrateDB(db)
    db.dbVersion = NP.DB_VERSION
    NP.db = db
end

function NP.CurrentNote()
    local db = NP.db
    return db.notes[db.current] or db.notes[1]
end

-- Called from the minimap's addon menu (TOC field AddonCompartmentFunc).
function NotePad_ToggleFromCompartment()
    if NP.ToggleWindow then NP.ToggleWindow() end
end

local function HandleSlash(msg)
    local cmd = strtrim(strlower(msg or ""))
    if cmd == "" then
        NP.ToggleWindow()
    elseif cmd == "new" then
        NP.OpenWindow()
        NP.AddNote()
    elseif cmd:match("^%d+$") then
        local n = tonumber(cmd)
        local count = #NP.db.notes
        if NP.db.notes[n] then
            -- before and after opening, so nothing that runs while the window opens can switch it back
            NP.ShowNote(n)
            NP.OpenWindow()
            NP.ShowNote(n)
        else
            NP.Print("there is no note " .. n .. " (you have " .. count .. (count == 1 and " note)." or " notes)."))
        end
    elseif cmd == "reset" then
        NP.ResetWindow()
        NP.Print("window reset to the middle of the screen.")
    elseif cmd == "minimap" then
        NP.ToggleMinimapButton()
    else
        NP.Print("/np - open or close the note pad (opens unfolded)")
        NP.Print("/np new - add a new note")
        NP.Print("/np <number> - open note number <number>, e.g. /np 2")
        NP.Print("/np reset - move the window back to the middle (and unfold it)")
        NP.Print("/np minimap - show or hide the minimap button")
        NP.Print("Tabs: [+] adds a note, double-click a tab to rename, right-click for more; Ctrl+Tab / Ctrl+Shift+Tab switch notes while typing.")
        NP.Print("Fold the window to its title bar: the fold button, double-click the title bar, or right-click the minimap button.")
        NP.Print("Notes save as you type.")
    end
end

SLASH_NOTEPAD1 = "/np"
SLASH_NOTEPAD2 = "/notepad"
SlashCmdList["NOTEPAD"] = HandleSlash

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGOUT")
events:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        self:UnregisterEvent("ADDON_LOADED")
        NP.InitDB()
        NP.CreateWindow()
        NP.CreateMinimapButton()
    elseif event == "PLAYER_LOGOUT" then
        if NP.SaveText then NP.SaveText() end
    end
end)
