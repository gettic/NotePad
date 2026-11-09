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

function NP.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffd100Note Pad:|r " .. tostring(msg))
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

-- Lowest "Note N" name that isn't used yet.
function NP.NewNoteTitle(notes)
    local used = {}
    for _, n in ipairs(notes) do
        if n.title then used[n.title] = true end
    end
    local i = 1
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
    for _, n in ipairs(fixed) do
        if not n.title then n.title = NP.NewNoteTitle(fixed) end
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
    elseif cmd == "reset" then
        NP.ResetWindow()
        NP.Print("window reset to the middle of the screen.")
    elseif cmd == "minimap" then
        NP.ToggleMinimapButton()
    else
        NP.Print("/np - open or close the note pad")
        NP.Print("/np reset - move the window back to the middle (and unfold it)")
        NP.Print("/np minimap - show or hide the minimap button")
        NP.Print("Tabs: click [+] to add a note, double-click a tab to rename, right-click for more.")
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
