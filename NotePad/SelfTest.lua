-- Note Pad: /np selftest [full]. From the wowforever-kit starter (.claude\tools\selftest\GUIDE.md).
-- The addon checks itself in the running game: the window, the tab row, the [+] button and the
-- checklist view are shown, have a position and a size, are on screen and aren't covered; their art
-- loads; the saved data survives NP.RepairDB (on copies only); the Shift-click link hook is in place;
-- the settings (text size fonts, opacity, lock, checklist row height, the cog and its menu) are applied.
-- "full" also shows a throwaway checklist (never saved) to check its rows, tick box and item icon.
-- Safety: reads only. It shows and hides only the addon's own frames and puts them back; no Blizzard
-- function is replaced or hooked; nothing protected. Every value read from a frame is checked with
-- issecretvalue before it is compared ("skipped (secret)"). In combat it waits; if combat starts
-- mid-run it stops and puts everything back. Never writes the saved data. The report has no player
-- names, realms, guilds, note titles or item links.
local ADDON_NAME, NP = ...

local ST = {}
NP.SelfTest = ST

local MAX_LIST = 8          -- skipped names listed in the report
local COVER_SHARE = 0.3     -- a part counts as covered when this much of it is under another frame
local SCREEN_SLACK = 2      -- px
local COPY_MAX = 4000       -- report length

-- Hearthstone (item 6948): in every client, its icon is always known (GetItemInfoInstant).
local TEST_LINK = "|cffffffff|Hitem:6948::::::::::::::|h[Hearthstone]|h|r"

local run                   -- the run in progress (nil when idle)

-- ---------------------------------------------------------------------------
-- Safe reads

local function IsSecret(v)
    local f = issecretvalue
    if type(f) ~= "function" then return false end
    local ok, s = pcall(f, v)
    return ok and s and true or false
end

local function Pack(...) return { n = select("#", ...), ... } end

-- obj:method(...) -> "ok", results... | "noapi" | "err" | "secret" (any result secret).
local function Read(obj, method, ...)
    if type(obj) ~= "table" then return "noapi" end
    local f = obj[method]
    if type(f) ~= "function" then return "noapi" end
    local r = Pack(pcall(f, obj, ...))
    if not r[1] then return "err" end
    for i = 2, r.n do
        if IsSecret(r[i]) then return "secret" end
    end
    return "ok", unpack(r, 2, r.n)
end

local function InCombat() return InCombatLockdown and InCombatLockdown() and true or false end
local function Short(err) return "error: " .. tostring(err):gsub("^.-:%d+: ", ""):sub(1, 80) end

-- ---------------------------------------------------------------------------
-- Results

local function Count(n) run.checks = run.checks + (n or 1) end
local function Problem(code, name, text) run.problems[#run.problems + 1] = code .. " " .. name .. ": " .. text end
local function Skip(name, why) run.skips[#run.skips + 1] = name .. " " .. why end
local function Info(text) run.info[#run.info + 1] = text end

-- Runs fn in pcall; a throw becomes one "ERR" line.
local function Guard(label, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then Problem("ERR", label, Short(err)) end
    return ok
end

-- ---------------------------------------------------------------------------
-- Frame geometry (screen pixels, so frames with other scales compare)

local function ScreenRect(o)
    local st, l, b, w, h = Read(o, "GetRect")
    if st == "secret" then return "secret" end
    if st ~= "ok" or l == nil or b == nil or w == nil or h == nil then return nil end
    local s2, es = Read(o, "GetEffectiveScale")
    if s2 == "secret" then return "secret" end
    if s2 ~= "ok" or type(es) ~= "number" then es = 1 end
    return { l = l * es, b = b * es, r = (l + w) * es, t = (b + h) * es, w = w, h = h }
end

local function Overlap(a, b)
    local w = math.min(a.r, b.r) - math.max(a.l, b.l)
    local h = math.min(a.t, b.t) - math.max(a.b, b.b)
    if w <= 0 or h <= 0 then return 0 end
    return w * h
end

-- Frame level of a frame, or of a texture's / font string's frame. nil = can't tell, "secret".
local function Level(o)
    local st, lv = Read(o, "GetFrameLevel")
    if st == "secret" then return "secret" end
    if st == "ok" and type(lv) == "number" then return lv end
    local s2, p = Read(o, "GetParent")
    if s2 == "secret" then return "secret" end
    st, lv = Read(p, "GetFrameLevel")
    if st == "secret" then return "secret" end
    return st == "ok" and type(lv) == "number" and lv or nil
end

local STRATA = { WORLD = 0, BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5,
    FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
local function Strata(o)
    local st, s = Read(o, "GetFrameStrata")
    if st == "noapi" then st, s = Read(select(2, Read(o, "GetParent")), "GetFrameStrata") end
    if st == "secret" then return "secret" end
    return st == "ok" and STRATA[s] or nil
end

-- true when a is b or one is inside the other (parent chain); nil = can't tell.
local function Related(a, b)
    for _, pair in ipairs({ { a, b }, { b, a } }) do
        local p, n = pair[1], 0
        while p and n < 25 do
            if p == pair[2] then return true end
            local st, q = Read(p, "GetParent")
            if st ~= "ok" then return nil end
            p, n = q, n + 1
        end
    end
    return false
end

-- nil = the texture's art loads; else a short reason.
local function ArtMissing(tex)
    if type(tex) ~= "table" then return "missing" end
    local st, atlas = Read(tex, "GetAtlas")
    if st == "secret" then return "secret" end
    if st == "ok" and type(atlas) == "string" and atlas ~= "" then
        local get = C_Texture and C_Texture.GetAtlasInfo
        if type(get) ~= "function" then return nil end
        local ok, info = pcall(get, atlas)
        if not ok or type(info) ~= "table" then return "atlas " .. atlas .. " gone" end
        return nil
    end
    local id
    st, id = Read(tex, "GetTextureFileID")
    if st == "secret" then return "secret" end
    if st ~= "ok" or id == nil then
        st, id = Read(tex, "GetTexture")
        if st == "secret" then return "secret" end
    end
    if id == nil or id == 0 or id == "" then return "no file" end
    return nil
end

-- ---------------------------------------------------------------------------
-- UI parts

-- The window template's parts that hold its border/title/portrait art. Missing ones are ignored.
local TEMPLATE_PARTS = { "NineSlice", "PortraitContainer", "TitleContainer", "CloseButton" }

local function ArtTop(win)
    local top, name
    for _, key in ipairs(TEMPLATE_PARTS) do
        local lv = Level(win[key])
        if lv == "secret" then return "secret" end
        if type(lv) == "number" and (top == nil or lv > top) then top, name = lv, key end
    end
    return top, name
end

-- Frames that may draw over a part: the template's portrait/title/X plus the group's other parts.
local function Coverers(win, parts)
    local list = {}
    for _, key in ipairs({ "PortraitContainer", "TitleContainer", "CloseButton" }) do
        if win and win[key] then list[#list + 1] = { name = key, obj = win[key] } end
    end
    for _, p in ipairs(parts) do if p.obj then list[#list + 1] = p end end
    return list
end

-- One part = { name = "plus", obj = <frame>, top = true (must be above the border art),
--   opt = true (may be missing), shownOnly = true (only checked while shown), thin = true (a line),
--   art = { "Icon" } (texture keys whose art must load), artSelf = true (obj is a texture) }.
-- At most one problem line per part: the first check that fails.
local function CheckPart(p, win, coverers)
    local o = p.obj
    Count()
    if o == nil then
        if p.opt then return end
        return Problem("UI", p.name, "missing")
    end
    local st, shown = Read(o, "IsShown")
    if st == "secret" then return Skip(p.name, "(secret)") end
    if st ~= "ok" then return Problem("UI", p.name, "can't read (" .. st .. ")") end
    if not shown then
        if p.shownOnly then return end
        return Problem("UI", p.name, "hidden")
    end
    local vis
    st, vis = Read(o, "IsVisible")
    if st == "secret" then return Skip(p.name, "(secret)") end
    if st == "ok" and not vis then return Problem("UI", p.name, "shown but its parent is hidden") end

    Count()
    local valid
    st, valid = Read(o, "IsRectValid")
    if st == "secret" then return Skip(p.name, "(secret)") end
    if st == "ok" and valid == false then return Problem("UI", p.name, "no position") end
    local rect = ScreenRect(o)
    if rect == "secret" then return Skip(p.name, "(secret)") end
    if rect == nil then return Problem("UI", p.name, "no position") end

    Count()
    if not (rect.w > 1 and rect.h > 1) and not p.thin then
        return Problem("UI", p.name, ("size %dx%d"):format(math.floor(rect.w), math.floor(rect.h)))
    end

    Count()
    local screen = ScreenRect(UIParent)
    if type(screen) == "table" and (rect.l < screen.l - SCREEN_SLACK or rect.b < screen.b - SCREEN_SLACK
        or rect.r > screen.r + SCREEN_SLACK or rect.t > screen.t + SCREEN_SLACK) then
        return Problem("UI", p.name, "off screen")
    end

    Count()
    local alpha
    st, alpha = Read(o, "GetEffectiveAlpha")
    if st == "secret" then return Skip(p.name, "(secret)") end
    if st == "ok" and type(alpha) == "number" and alpha < 0.05 then
        return Problem("UI", p.name, ("invisible (alpha %.2f)"):format(alpha))
    end

    local lv, ss = Level(o), Strata(o)
    if lv == "secret" or ss == "secret" then return Skip(p.name, "(secret)") end

    -- Above the window's border/title/portrait art.
    if p.top and win then
        Count()
        local top, topName = ArtTop(win)
        local ws = Strata(win)
        if top == "secret" or ws == "secret" then return Skip(p.name, "(secret)") end
        local higherStrata = ss and ws and ss > ws
        if type(lv) == "number" and type(top) == "number" and lv <= top and not higherStrata then
            return Problem("UI", p.name, ("under art %d<=%d (%s)"):format(lv, top, topName))
        end
    end

    -- Not under another frame that covers a good part of it.
    if type(lv) == "number" then
        Count()
        for _, c in ipairs(coverers or {}) do
            if c.obj ~= o and Related(o, c.obj) == false and select(2, Read(c.obj, "IsVisible")) == true then
                local clv, cs = Level(c.obj), Strata(c.obj)
                if clv == "secret" or cs == "secret" then
                    Skip(p.name, "cover (secret)")
                elseif type(clv) == "number" and clv > lv and (cs == nil or ss == nil or cs == ss) then
                    local cr = ScreenRect(c.obj)
                    local area = (rect.r - rect.l) * (rect.t - rect.b)
                    if type(cr) == "table" and area > 0 and Overlap(rect, cr) / area >= COVER_SHARE then
                        return Problem("UI", p.name, ("covered by %s (%d>%d)"):format(c.name, clv, lv))
                    end
                end
            end
        end
    end

    -- Its art really loads.
    for _, key in ipairs(p.art or {}) do
        Count()
        local miss = ArtMissing(o[key])
        if miss == "secret" then Skip(p.name .. "." .. key, "(secret)")
        elseif miss then return Problem("TEX", p.name .. "." .. key, miss) end
    end
    if p.artSelf then
        Count()
        local miss = ArtMissing(o)
        if miss == "secret" then Skip(p.name, "art (secret)")
        elseif miss then return Problem("TEX", p.name, miss) end
    end

    -- Button label cut off.
    local fs = select(2, Read(o, "GetFontString"))
    if fs then
        Count()
        local s2, cut = Read(fs, "IsTruncated")
        if s2 == "ok" and cut then return Problem("UI", p.name, "text cut") end
    end
end

local function CheckGroup(parts, win)
    local cov = Coverers(win, parts)
    for _, p in ipairs(parts) do Guard("UI " .. p.name, CheckPart, p, win, cov) end
end

local function Win() return _G.NotePadFrame end
local function Folded() return NP.db and NP.db.window and NP.db.window.minimized and true or false end

-- The window, fold button, tab row, [+] and resize grip (tab row and grip are hidden while folded).
function ST.MainParts()
    local w = NP.TabWidgets and NP.TabWidgets() or {}
    local ww = NP.WindowWidgets and NP.WindowWidgets() or {}
    local parts = { { name = "window", obj = Win() }, { name = "fold", obj = ww.fold } }
    local cog = ww.settings
    if cog then -- the settings cog (folded too); its atlas must load
        parts[#parts + 1] = { name = "settings", obj = cog, top = true,
            art = (type(cog) == "table" and cog.NPLook == "atlas") and { "Icon" } or nil }
    end
    if not Folded() then
        parts[#parts + 1] = { name = "tabRow", obj = w.row }
        parts[#parts + 1] = { name = "plus", obj = w.plus }
        if not (NP.db.settings and NP.db.settings.locked) then -- locked: the grip is hidden on purpose
            parts[#parts + 1] = { name = "grip", obj = ww.grip }
        end
    end
    return parts
end

-- The resize grip must not lie on a scroll bar's down arrow or the Clear ticked button.
local function DownArrow(scrollFrame)
    local bar = type(scrollFrame) == "table" and scrollFrame.ScrollBar
    if type(bar) ~= "table" then return nil end
    return bar.ScrollDownButton or bar.Forward or bar
end

-- The fold button is drawn above the metal border (at least the border's level), like the X.
local function CheckFoldLevel()
    local ww = NP.WindowWidgets and NP.WindowWidgets() or {}
    local w = Win()
    local border = w and w.NineSlice
    if not ww.fold or type(border) ~= "table" then return end
    Count()
    local fl, bl = Level(ww.fold), Level(border)
    if fl == "secret" or bl == "secret" then return Skip("fold", "level (secret)") end
    if type(fl) == "number" and type(bl) == "number" and fl < bl then
        Problem("UI", "fold", ("under the border %d<%d"):format(fl, bl))
    end
end

-- Esc closes the open window but not the folded bar.
local function CheckEsc()
    if not NP.EscClosesWindow then return end
    Count()
    local esc = NP.EscClosesWindow()
    if esc == Folded() then
        Problem("ESC", "window", Folded() and "Esc would close the folded bar" or "Esc doesn't close the window")
    end
end

-- Bindings.xml loaded: the "Open or close Note Pad" key is in Key Bindings.
local function CheckBinding()
    Count()
    if type(GetNumBindings) ~= "function" or type(GetBinding) ~= "function" then
        return Skip("binding", "(no API)")
    end
    for i = 1, GetNumBindings() do
        local ok, action = pcall(GetBinding, i)
        if ok and action == "NOTEPAD_TOGGLE" then
            Info("binding " .. ((GetBindingKey and GetBindingKey("NOTEPAD_TOGGLE")) and "set" or "not set"))
            return
        end
    end
    Problem("BIND", "NOTEPAD_TOGGLE", "not in Key Bindings")
end

local function CheckGrip()
    local ww = NP.WindowWidgets and NP.WindowWidgets() or {}
    local grip = ww.grip
    if not grip or Folded() then return end
    local g = ScreenRect(grip)
    if type(g) ~= "table" then return end
    local c = NP.ChecklistWidgets and NP.ChecklistWidgets() or {}
    local others = {
        { "textScrollBar", ww.modernBar },
        { "textScrollDown", DownArrow(ww.classicScroll) },
        { "listScrollDown", DownArrow(c.scroll) },
        { "clearButton", c.clearButton },
    }
    for _, o in ipairs(others) do
        if type(o[2]) == "table" and select(2, Read(o[2], "IsVisible")) == true then
            Count()
            local r = ScreenRect(o[2])
            if r == "secret" then
                Skip("grip/" .. o[1], "(secret)")
            elseif type(r) == "table" and Overlap(g, r) > 1 then
                Problem("UI", "grip", "covers " .. o[1])
            end
        end
    end
end

-- Settings (Beta A): saved values in range, the font objects at the set size, the text box using
-- ours, window opacity, lock (grip hidden), checklist row height, and the menu builds (dry run on a
-- stand-in, nothing is shown or changed).
local function CheckSettings()
    local s = NP.db and NP.db.settings
    Count()
    if type(s) ~= "table" then return Problem("SET", "settings", "missing") end
    local size, alpha = s.fontSize, s.alpha
    if not (type(size) == "number" and size >= NP.FONT_MIN and size <= NP.FONT_MAX) then
        return Problem("SET", "fontSize", "out of range")
    end
    Count()
    if not (type(alpha) == "number" and alpha >= NP.ALPHA_MIN and alpha <= 1) then
        return Problem("SET", "alpha", "out of range")
    end

    local fonts = NP.Fonts or {}
    for _, f in ipairs({ { "editFont", fonts.edit, size }, { "listFont", fonts.list, size - 2 } }) do
        Count()
        if type(f[2]) ~= "table" then
            Problem("FONT", f[1], "missing")
        else
            local st, path, h = Read(f[2], "GetFont")
            if st == "secret" then
                Skip(f[1], "(secret)")
            elseif st ~= "ok" or not path then
                Problem("FONT", f[1], "no font file")
            elseif type(h) == "number" and math.abs(h - f[3]) > 1 then
                Problem("FONT", f[1], ("size %.1f, want %d"):format(h, f[3]))
            end
        end
    end

    local ww = NP.WindowWidgets and NP.WindowWidgets() or {}
    -- the text box draws with our font: compare what is drawn (file, size), and name what was found
    -- (another addon may re-skin edit boxes; the line then says which font it put there)
    if fonts.edit and ww.editBox then
        Count()
        local st, fo = Read(ww.editBox, "GetFontObject")
        local s2, path, h = Read(ww.editBox, "GetFont")
        local s3, wantPath, wantH = Read(fonts.edit, "GetFont")
        if st == "secret" or s2 == "secret" or s3 == "secret" then
            Skip("textBox", "font (secret)")
        else
            local foName = "-"
            if type(fo) == "table" then
                local s4, n = Read(fo, "GetName")
                foName = (fo == fonts.edit) and "NotePadEditFont" or (s4 == "ok" and n) or "unnamed"
            end
            local function File(p) return tostring(p or "?"):match("([^\\/]+)$") or "?" end
            local function Size(v) return type(v) == "number" and ("%g"):format(math.floor(v * 10 + 0.5) / 10) or "?" end
            local found = ("%s %s (%s)"):format(File(path), Size(h), tostring(foName))
            Info("textBox font " .. found)
            local same = s2 == "ok" and s3 == "ok" and path ~= nil and tostring(path):lower() == tostring(wantPath):lower()
                and type(h) == "number" and type(wantH) == "number" and math.abs(h - wantH) < 0.6
            if not same then
                Problem("FONT", "textBox", ("%s, want %s %s"):format(found, File(wantPath), Size(wantH)))
            end
        end
    end

    if ww.frame then
        Count()
        local st, a = Read(ww.frame, "GetAlpha")
        if st == "ok" and type(a) == "number" and math.abs(a - 1) > 0.01 and math.abs(a - alpha) > 0.01 then
            Problem("SET", "opacity", ("window %.2f, setting %.2f"):format(a, alpha))
        end
    end

    -- "open after login" bookkeeping: the saved open flag matches the window (the run has it open)
    if ww.frame and not NP.loggingOut then
        Count()
        local st, open = Read(ww.frame, "IsShown")
        if st == "ok" and (NP.db.window.shown and true or false) ~= (open and true or false) then
            Problem("SET", "shown", "saved open flag doesn't match the window")
        end
    end

    if ww.grip and not Folded() then
        Count()
        local st, shown = Read(ww.grip, "IsShown")
        if st == "ok" and (shown and true or false) == (s.locked and true or false) then
            Problem("SET", "lock", s.locked and "grip shown while locked" or "grip hidden while unlocked")
        end
    end

    if NP.ChecklistRowHeight then
        Count()
        local want = math.max(22, size - 2 + 10)
        if NP.ChecklistRowHeight() ~= want then
            Problem("SET", "rowHeight", ("%s, want %d"):format(tostring(NP.ChecklistRowHeight()), want))
        end
    end

    -- the menu builds: 9 text sizes, 6 opacities, 2 tick boxes
    if NP.SettingsMenuGenerator then
        Count()
        local n = { radio = 0, check = 0 }
        local desc
        desc = {
            CreateTitle = function() end, CreateDivider = function() end,
            CreateButton = function() return desc end,
            CreateRadio = function() n.radio = n.radio + 1 end,
            CreateCheckbox = function() n.check = n.check + 1 end,
        }
        local ok, err = pcall(NP.SettingsMenuGenerator, nil, desc)
        if not ok then
            Problem("SET", "menu", Short(err))
        elseif n.radio ~= (NP.FONT_MAX - NP.FONT_MIN + 1) + 6 or n.check ~= 2 then
            Problem("SET", "menu", ("%d radios, %d tick boxes"):format(n.radio, n.check))
        end
    end

    Info(("settings size %d opacity %d lock %s remember %s"):format(size, math.floor(alpha * 100 + 0.5),
        s.locked and "on" or "off", s.rememberOpen and "on" or "off"))
    Info("corner " .. tostring(ww.corner or "-") .. ", cog " .. tostring(type(ww.settings) == "table" and ww.settings.NPLook or "none"))
end

-- The checklist view. required = it must be shown (full mode, or a checklist is open).
function ST.ChecklistParts(required)
    local c = NP.ChecklistWidgets and NP.ChecklistWidgets() or {}
    local so = not required
    -- a text note is open: the view is hidden, so its parts are too (they keep their own "shown" flag)
    if so and select(2, Read(c.view, "IsVisible")) ~= true then
        return { { name = "checklist", obj = c.view, shownOnly = true } }
    end
    local r1 = c.rows and c.rows[1]
    local check = r1 and r1.NPCheck
    local checkArt = check and select(2, Read(check, "GetNormalTexture"))
    return {
        { name = "checklist", obj = c.view, shownOnly = so },
        { name = "addBox", obj = c.addBox, shownOnly = so },
        { name = "addButton", obj = c.addButton, shownOnly = so },
        { name = "clearButton", obj = c.clearButton, shownOnly = so },
        { name = "counter", obj = c.counter, shownOnly = so },
        { name = "row1", obj = r1, opt = not required, shownOnly = so },
        { name = "row1Check", obj = check, opt = not required, shownOnly = so },
        { name = "row1CheckArt", obj = checkArt, opt = true, shownOnly = true, artSelf = true },
    }
end

-- ---------------------------------------------------------------------------
-- Saved data (on copies only: the real SavedVariables are never written)

local function DeepCopy(v, seen)
    if type(v) ~= "table" then return v end
    seen = seen or {}
    if seen[v] then return seen[v] end
    local c = {}
    seen[v] = c
    for k, x in pairs(v) do c[DeepCopy(k, seen)] = DeepCopy(x, seen) end
    return c
end

local function Lines(note)
    return type(note) == "table" and type(note.items) == "table" and #note.items or -1
end

local function CheckSaved()
    local prep = NP.RepairDB
    if type(prep) ~= "function" then return Skip("db", "(no RepairDB)") end

    -- the player's own data, on a copy: nothing lost
    Count()
    local copy = DeepCopy(NP.db or {})
    local before = type(copy.notes) == "table" and #copy.notes or 0
    local ok, err = pcall(prep, copy)
    if not ok then return Problem("DB", "current", Short(err)) end
    if #copy.notes < before then Problem("DB", "current", "notes lost") end

    -- broken data of every kind
    Count()
    ok, err = pcall(prep, { version = "x", point = { "NOPE" }, settings = 5, window = 7, minimap = "z",
        notes = 5, current = "q" })
    if not ok then Problem("DB", "broken", Short(err)) end

    -- a damaged window place falls back to the middle; junk in the deleted-notes list is cleaned
    Count()
    local junk = { window = { point = "NOPE", relPoint = "CENTER", x = 0 / 0, y = 0 },
        deleted = { "x", { note = { text = 5 }, pos = "a" }, { note = "y" }, 7 } }
    ok, err = pcall(prep, junk)
    if not ok then
        Problem("DB", "window", Short(err))
    elseif junk.window.point ~= "CENTER" or junk.window.x ~= 0 or #(junk.deleted or {}) ~= 1
        or junk.deleted[1].note.text ~= "5" then
        Problem("DB", "window", "bad place or deleted list not repaired")
    end

    -- settings out of range or of the wrong type are put back in range
    Count()
    local sj = { settings = { fontSize = 99.4, alpha = 0 / 0, locked = "yes" } }
    ok, err = pcall(prep, sj)
    if not ok then
        Problem("DB", "settings", Short(err))
    elseif sj.settings.fontSize ~= NP.FONT_MAX or sj.settings.alpha ~= 1 or sj.settings.locked ~= false
        or sj.settings.rememberOpen ~= false then
        Problem("DB", "settings", "not repaired")
    end

    -- broken checklists: every line that holds text survives
    Count()
    local bad = { notes = {
        { kind = "checklist", title = "A", text = 3,
          items = { "one", 2, { text = "three", done = "yes" }, false, { text = {} }, [9] = { text = "nine", done = true } } },
        { kind = "checklist", items = "bad", text = "[x] a\n[ ] b\n\nc" },
        { kind = "later", text = "k" },
    }, current = 99 }
    ok, err = pcall(prep, bad)
    if not ok then
        Problem("DB", "checklist", Short(err))
    else
        local n = bad.notes
        local good = Lines(n[1]) == 4 and n[1].items[4].done == true and n[1].items[3].done == false
            and Lines(n[2]) == 3 and n[2].items[1].done == true and n[2].items[3].text == "c"
            and n[3].kind == "later" and n[3].text == "k" and bad.current == 1
        if not good then Problem("DB", "checklist", "repair lost or changed lines") end
    end

    -- note <-> checklist text round trip
    Count()
    local items = { { text = "a [x] b", done = true }, { text = "[ ] inner", done = false }, { text = "c", done = false } }
    local back = NP.ChecklistTextToItems(NP.ChecklistItemsToText(items))
    local same = #back == #items
    for i = 1, #items do
        if not back[i] or back[i].text ~= items[i].text or back[i].done ~= items[i].done then same = false end
    end
    if not same then Problem("DB", "roundtrip", "lines differ") end

    -- the line-edit box takes a whole long line (a byte limit would cut it when editing)
    local le = NP.ChecklistWidgets and NP.ChecklistWidgets().lineEdit
    if le and le.GetMaxBytes then
        Count()
        local readOk, m = pcall(le.GetMaxBytes, le)
        if readOk and type(m) == "number" and m > 0 then Problem("DB", "lineEditLimit", "edit box cuts lines at " .. m .. " bytes") end
    end

    -- text typed into a checklist by an older Note Pad is kept as a "Recovered note", once
    Count()
    local n = { kind = "checklist", title = "L", items = { { text = "a", done = true } } }
    NP.UpdateChecklistMirror(n)
    n.text = n.text .. "\ntyped later"
    local db = { notes = { n }, current = 1, dbVersion = 2 }
    ok, err = pcall(prep, db)
    if ok then ok, err = pcall(prep, db) end -- a second load must not recover it again
    if not ok then
        Problem("DB", "recover", Short(err))
    elseif #db.notes ~= 2 or not tostring(db.notes[2].text):find("typed later", 1, true) or Lines(db.notes[1]) ~= 1 then
        Problem("DB", "recover", "old-version text not kept once")
    end
end

-- The Shift-click hook and the APIs the checklist uses.
local function CheckHooks()
    Count()
    local info = NP.ChecklistInfo and NP.ChecklistInfo()
    if not (info and info.hook) then Problem("HOOK", "link", "not installed") end
    local apis = {
        { "GetCursorInfo", GetCursorInfo },
        { "ClearCursor", ClearCursor },
        { "GetCurrentKeyBoardFocus", GetCurrentKeyBoardFocus },
        { "GetItemInfoInstant", (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant },
        { "GameTooltip.SetHyperlink", GameTooltip and GameTooltip.SetHyperlink },
    }
    for _, a in ipairs(apis) do
        Count()
        if type(a[2]) ~= "function" then Problem("API", a[1], "missing") end
    end
end

local function AddInfo()
    local info = NP.ChecklistInfo and NP.ChecklistInfo() or { used = {} }
    Info("hook " .. tostring(info.hook or "none"))
    Info(("issecretvalue %s, secret skips %d"):format(type(issecretvalue) == "function" and "yes" or "no",
        tonumber(info.secretSkips) or 0))
    local t = {}
    for _, k in ipairs({ "addBox", "addButton", "clearButton", "scroll", "check", "lineEdit" }) do
        t[#t + 1] = k .. "=" .. tostring(info.used and info.used[k] or "-")
    end
    Info("templates " .. table.concat(t, " "))
end

-- ---------------------------------------------------------------------------
-- Steps (each runs some frames later, so the UI has laid out; combat stops the run)

local Finish

local function Later(frames, fn)
    local function Tick()
        if not run then return end
        frames = frames - 1
        if frames > 0 then return C_Timer.After(0, Tick) end
        if InCombat() then
            run.stopped = true
            return Finish()
        end
        local ok, err = pcall(fn)
        if not ok then
            Problem("ERR", "step", Short(err))
            Finish()
        end
    end
    C_Timer.After(0, Tick)
end

local function StepChecklist()
    CheckGroup(ST.ChecklistParts(true), Win())
    Guard("grip", CheckGrip)
    local c = NP.ChecklistWidgets()
    local r1 = c.rows and c.rows[1]
    Count()
    local icon = r1 and r1.NPIcon
    local st, shown = Read(icon, "IsShown")
    if st == "ok" and not shown then
        Problem("UI", "row1Icon", "no item icon")
    elseif st == "ok" then
        CheckGroup({ { name = "row1Icon", obj = icon, artSelf = true } }, Win())
    end
    -- the row is as tall as the text size asks
    if r1 and NP.ChecklistRowHeight then
        Count()
        local s2, h = Read(r1, "GetHeight")
        if s2 == "ok" and type(h) == "number" and math.abs(h - NP.ChecklistRowHeight()) > 0.5 then
            Problem("UI", "row1", ("height %.1f, want %d"):format(h, NP.ChecklistRowHeight()))
        end
    end
    AddInfo()
    Finish()
end

local function StepMain()
    CheckGroup(ST.MainParts(), Win())
    Guard("fold", CheckFoldLevel)
    Guard("esc", CheckEsc)
    Guard("grip", CheckGrip)
    Guard("settings", CheckSettings)
    local open = NP.IsChecklist(NP.CurrentNote())
    if Folded() then
        Skip("checklist", "(window folded)")
    elseif run.mode == "full" and NP.ShowChecklist then
        -- a throwaway checklist (not in the saved data) over the open note; Restore() puts it back
        run.state.testNote = { title = "Self-test", kind = "checklist",
            items = { { text = TEST_LINK, done = false }, { text = "Self-test line", done = true } } }
        NP.UpdateChecklistMirror(run.state.testNote)
        run.state.showedTest = true
        NP.ShowChecklist(run.state.testNote)
        return Later(2, StepChecklist)
    else
        CheckGroup(ST.ChecklistParts(open), Win())
    end
    AddInfo()
    Finish()
end

-- ---------------------------------------------------------------------------
-- Restore and output

local function Try(label, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok and run then Problem("ERR", "restore " .. label, Short(err)) end
end

-- Puts back everything the run opened (only what it opened), whatever happened.
local function Restore()
    local s = run.state
    if s.showedTest then
        local cur = NP.CurrentNote()
        Try("checklist", NP.ShowChecklist, NP.IsChecklist(cur) and cur or nil)
    end
    local w = Win()
    if s.openedWindow and w then Try("window", w.Hide, w) end
end

-- The report: header, one line per problem, skips, info. No names, realms, guilds or links.
function ST.Text(r)
    r = r or run
    local okB, ver, build = false
    if GetBuildInfo then okB, ver, build = pcall(GetBuildInfo) end
    local addonVer = "?"
    local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    if meta then
        local ok, v = pcall(meta, ADDON_NAME, "Version")
        if ok and v then addonVer = v end
    end
    local head = ("%s selftest %s | game %s (%s) | %s | %d checks, %d problems"):format(ADDON_NAME, addonVer,
        okB and tostring(ver) or "?", okB and tostring(build) or "?", r.mode, r.checks, #r.problems)
    if r.stopped then head = head .. " | stopped: combat" end
    local parts = { head }
    for _, p in ipairs(r.problems) do parts[#parts + 1] = p end
    if #r.skips > 0 then
        parts[#parts + 1] = ("skipped %d: %s"):format(#r.skips, table.concat(r.skips, ", ", 1, math.min(#r.skips, MAX_LIST)))
    end
    for _, i in ipairs(r.info) do parts[#parts + 1] = i end
    local text = table.concat(parts, " | ")
    if #text > COPY_MAX then text = text:sub(1, COPY_MAX - 3) .. "..." end
    return text
end

-- A small copy box (select all + Ctrl+C).
local box
local function ShowCopyBox(text)
    if not box then
        box = CreateFrame("Frame", "NotePadSelfTestBox", UIParent, "BasicFrameTemplateWithInset")
        box:SetSize(520, 160)
        box:SetPoint("CENTER")
        box:SetFrameStrata("DIALOG")
        box:SetMovable(true); box:EnableMouse(true)
        box:RegisterForDrag("LeftButton")
        box:SetScript("OnDragStart", box.StartMoving)
        box:SetScript("OnDragStop", box.StopMovingOrSizing)
        local sf = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 12, -30); sf:SetPoint("BOTTOMRIGHT", -30, 10)
        local eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true); eb:SetAutoFocus(true); eb:SetFontObject(ChatFontNormal); eb:SetSize(470, 110)
        eb:SetScript("OnEscapePressed", function() box:Hide() end)
        sf:SetScrollChild(eb)
        box.edit = eb
        if UISpecialFrames then tinsert(UISpecialFrames, "NotePadSelfTestBox") end -- Esc closes it
    end
    box.edit:SetText(text)
    box.edit:HighlightText()
    box:Show()
    box.edit:SetFocus()
end

Finish = function()
    if not run then return end
    local ok, err = pcall(Restore)
    if not ok then Problem("ERR", "restore", Short(err)) end
    local r = run
    run = nil
    if r.stopped then
        NP.Print("Self-test stopped (combat). Nothing was changed.")
    elseif #r.problems == 0 then
        NP.Print(("Self-test OK (%d checks)."):format(r.checks))
    else
        NP.Print(("Self-test found %d problem(s) in %d checks. Copy the text and send it."):format(#r.problems, r.checks))
    end
    local text = ST.Text(r)
    if not pcall(ShowCopyBox, text) then print(text) end
    ST.last = r
    ST.lastText = text
end

-- ---------------------------------------------------------------------------
-- Start

local waiter
local function AfterCombat(mode)
    if not waiter then waiter = CreateFrame("Frame") end
    waiter.mode = mode
    waiter:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        self:SetScript("OnEvent", nil)
        ST:Start(self.mode)
    end)
    waiter:RegisterEvent("PLAYER_REGEN_ENABLED")
end

function ST.NewRun(mode)
    return { mode = mode or "quick", checks = 0, problems = {}, skips = {}, info = {}, state = {} }
end

function ST.IsRunning() return run ~= nil end

-- mode: "quick" (window, tabs, the open checklist) or "full" (also a throwaway checklist).
function ST:Start(mode)
    if run then return NP.Print("Self-test is already running.") end
    if InCombat() then
        NP.Print("The self-test waits until combat ends.")
        return AfterCombat(mode)
    end
    run = ST.NewRun(mode)
    Guard("db", CheckSaved)
    Guard("hooks", CheckHooks)
    Guard("binding", CheckBinding)
    local ok, err = pcall(function()
        local w = Win()
        if not w then error("window not built") end
        if not w:IsShown() then
            run.state.openedWindow = true
            w:Show()
        end
    end)
    if not ok then
        Problem("ERR", "window", Short(err))
        return Finish()
    end
    Later(2, StepMain)
end
