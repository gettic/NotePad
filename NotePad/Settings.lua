-- Note Pad: settings (text size, opacity, lock, open after login), the settings cog and its menu.
-- Saved in NotePadDB.settings (defaults and repair in Core.lua). Loads after Checklist.lua.
local _, NP = ...

local frame        -- NotePadFrame (SetupSettings)
local ticker       -- runs only while the window is shown and see-through
local openMenu     -- the settings menu while it is open
local setUp = false

-- Fonts ---------------------------------------------------------------------------
-- Own font objects, copies of Blizzard's (never change ChatFontNormal or GameFontHighlight
-- themselves: chat and the whole UI use them). Text notes: chat font at the set size;
-- checklist lines: GameFontHighlight, 2 px smaller (12 at the default 14, as before).
local EDIT_BASE, LIST_BASE = "ChatFontNormal", "GameFontHighlight"
local LIST_SMALLER = 2

local function MakeFont(name, baseName)
    local f = _G[name]
    if type(f) ~= "table" and type(CreateFont) == "function" then
        local ok, made = pcall(CreateFont, name)
        if ok then f = made end
    end
    if type(f) ~= "table" then return nil end
    local base = _G[baseName]
    if type(base) == "table" and f.CopyFontObject then pcall(f.CopyFontObject, f, base) end
    return f
end

NP.Fonts = { editBase = EDIT_BASE, listBase = LIST_BASE }
NP.Fonts.edit = MakeFont("NotePadEditFont", EDIT_BASE)
NP.Fonts.list = MakeFont("NotePadListFont", LIST_BASE)

function NP.EditFont() return NP.Fonts.edit or _G[EDIT_BASE] end
function NP.ListFont() return NP.Fonts.list or _G[LIST_BASE] end

-- Same face and outline as the Blizzard font it copies, new height.
local function SizeFont(font, baseName, size)
    if type(font) ~= "table" or not font.SetFont then return end
    local base = _G[baseName]
    local src = (type(base) == "table" and base.GetFont) and base or font
    if not src.GetFont then return end
    local path, _, flags = src:GetFont()
    if path then pcall(font.SetFont, font, path, size, flags or "") end
end

-- The saved size on both font objects (before the window is built, and after a change).
function NP.ApplyFonts()
    local size = NP.db.settings.fontSize
    SizeFont(NP.Fonts.edit, EDIT_BASE, size)
    SizeFont(NP.Fonts.list, LIST_BASE, size - LIST_SMALLER)
    if NP.ChecklistApplyFont then NP.ChecklistApplyFont(size - LIST_SMALLER) end
end

-- n: any number; kept in FONT_MIN..FONT_MAX, whole. Returns the size now in use.
function NP.SetFontSize(n)
    local s = NP.db.settings
    n = tonumber(n)
    if not n or n ~= n or n == math.huge or n == -math.huge then return s.fontSize end
    n = math.max(NP.FONT_MIN, math.min(NP.FONT_MAX, math.floor(n + 0.5)))
    if n == s.fontSize then return n end
    s.fontSize = n
    NP.ApplyFonts()
    if NP.ReapplyEditorFont then NP.ReapplyEditorFont() end
    return n
end

-- Ctrl + mouse wheel: one step bigger (wheel up) or smaller.
function NP.StepFontSize(delta)
    return NP.SetFontSize(NP.db.settings.fontSize + ((tonumber(delta) or 0) > 0 and 1 or -1))
end

-- Ctrl + wheel on a scrolling frame of ours: text size; without Ctrl its own scrolling.
local function WrapWheel(f)
    if type(f) ~= "table" or not f.GetScript or f.NPWheelWrapped then return end
    local old = f:GetScript("OnMouseWheel")
    f:SetScript("OnMouseWheel", function(self, delta, ...)
        if IsControlKeyDown() then
            NP.StepFontSize(delta)
            return
        end
        if old then return old(self, delta, ...) end
    end)
    if f.EnableMouseWheel then f:EnableMouseWheel(true) end
    f.NPWheelWrapped = true
end

-- Opacity --------------------------------------------------------------------------
-- The whole window (folded bar too) is see-through, but fully there while the mouse is on
-- it, one of its boxes has the keyboard (typing, renaming) or its settings menu is open.

local function OursHasFocus()
    local p = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
    local n = 0
    while type(p) == "table" and n < 30 do
        if p == frame then return true end
        p = p.GetParent and p:GetParent()
        n = n + 1
    end
    return false
end

local function WantFull()
    if frame:IsMouseOver() then return true end
    if openMenu then
        -- Blizzard's menus come from a pool: once ours is closed, forget it, so a later menu
        -- (tabs, another addon) that reuses the frame doesn't keep the window solid
        if openMenu.IsShown and openMenu:IsShown() then return true end
        openMenu = nil
    end
    return OursHasFocus()
end

function NP.UpdateAlpha()
    if not frame then return end
    local a = NP.db.settings.alpha
    frame:SetAlpha((a >= 1 or WantFull()) and 1 or a)
end

local function UpdateTicker()
    local need = frame and frame:IsShown() and NP.db.settings.alpha < 1
    if need and not ticker and C_Timer and C_Timer.NewTicker then
        ticker = C_Timer.NewTicker(0.1, NP.UpdateAlpha)
    elseif not need and ticker then
        ticker:Cancel()
        ticker = nil
    end
    NP.UpdateAlpha()
end

-- a: 0.3 .. 1 (kept inside). Returns the opacity now in use.
function NP.SetOpacity(a)
    local s = NP.db.settings
    a = tonumber(a)
    if not a or a ~= a or a == math.huge or a == -math.huge then return s.alpha end
    a = math.max(NP.ALPHA_MIN, math.min(1, a))
    s.alpha = math.floor(a * 100 + 0.5) / 100
    UpdateTicker()
    return s.alpha
end

function NP.SettingsTickerRunning() return ticker ~= nil end -- tests

-- Lock and open after login ----------------------------------------------------------

-- Locked: no moving, no resizing (Window.lua checks it; the grip hides). Folding and closing work.
function NP.SetLocked(on)
    NP.db.settings.locked = not not on
    if NP.UpdateGrip then NP.UpdateGrip() end
    return NP.db.settings.locked
end

function NP.SetRememberOpen(on)
    NP.db.settings.rememberOpen = not not on
    return NP.db.settings.rememberOpen
end

-- Menu ---------------------------------------------------------------------------------
local OPACITIES = { 100, 90, 80, 70, 60, 50 }

local function Percent(a) return math.floor(a * 100 + 0.5) end

-- Built only when the menu opens (Blizzard's menu: MenuUtil.CreateContextMenu).
local menuToken -- which opening of the menu is the latest

local function Generator(_, root)
    local s = NP.db.settings
    -- when this menu closes (released to the pool), forget it at once
    if root.AddMenuReleasedCallback then
        local token = {}
        menuToken = token
        root:AddMenuReleasedCallback(function()
            if menuToken == token then
                menuToken = nil
                openMenu = nil
                NP.UpdateAlpha()
            end
        end)
    end
    if root.CreateTitle then root:CreateTitle("Note Pad") end
    local size = root:CreateButton("Text size: " .. s.fontSize)
    for n = NP.FONT_MIN, NP.FONT_MAX do
        size:CreateRadio(n == NP.defaults.settings.fontSize and (n .. " (default)") or tostring(n),
            function(v) return NP.db.settings.fontSize == v end,
            function(v) NP.SetFontSize(v) end, n)
    end
    local op = root:CreateButton("Opacity: " .. Percent(s.alpha) .. "%")
    for _, p in ipairs(OPACITIES) do
        op:CreateRadio(p .. "%",
            function(v) return Percent(NP.db.settings.alpha) == v end,
            function(v) NP.SetOpacity(v / 100) end, p)
    end
    root:CreateCheckbox("Lock window",
        function() return NP.db.settings.locked end,
        function() NP.SetLocked(not NP.db.settings.locked) end)
    root:CreateCheckbox("Open after login if it was open",
        function() return NP.db.settings.rememberOpen end,
        function() NP.SetRememberOpen(not NP.db.settings.rememberOpen) end)
    -- notebook: the account's notes (every character) or this character's own
    -- a name that came late: look again (and show its notebook if it was in use)
    if not NP.charKey and NP.UpdateCharKey and NP.UpdateCharKey() and NP.UsingCharBook() and NP.OnBookChanged then
        NP.OnBookChanged()
    end
    if NP.charKey then
        local nb = root:CreateButton("Notebook: " .. NP.BookName(NP.Book()))
        nb:CreateRadio("Account (all characters)",
            function() return not NP.UsingCharBook() end,
            function() NP.SetCharBook(false) end, false)
        nb:CreateRadio(NP.BookName(NP.CharBook() or {}) .. " (only this character)",
            function() return NP.UsingCharBook() end,
            function() NP.SetCharBook(true) end, true)
    end
    if root.CreateDivider then root:CreateDivider() end
    root:CreateButton("Reset place and size", function() NP.ResetWindow() end)
end
NP.SettingsMenuGenerator = Generator -- tests

-- No menu system: the slash commands say the same.
function NP.OpenSettingsMenu(owner)
    if GameTooltip then GameTooltip:Hide() end
    if MenuUtil and MenuUtil.CreateContextMenu then
        local ok, menu = pcall(MenuUtil.CreateContextMenu, owner, Generator)
        if ok then
            openMenu = menu
            NP.UpdateAlpha()
            return true
        end
    end
    NP.Print("Settings: /np size 14, /np opacity 80, /np lock, /np remember, /np char (/np help lists them all).")
    return false
end

-- Cog button --------------------------------------------------------------------------

local function CogTooltip(self)
    local s = NP.db.settings
    local h, w = NP.Color.hint, NP.Color.white
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Settings")
    GameTooltip:AddLine(("Text size %d, opacity %d%%"):format(s.fontSize, Percent(s.alpha)), w[1], w[2], w[3])
    if s.locked then GameTooltip:AddLine("The window is locked.", w[1], w[2], w[3]) end
    if NP.UsingCharBook() then GameTooltip:AddLine("Notebook: " .. NP.BookName(NP.Book()), w[1], w[2], w[3]) end
    GameTooltip:AddLine("Click: text size, opacity, lock, notebook", h[1], h[2], h[3], true)
    GameTooltip:AddLine("Ctrl + mouse wheel over the text: text size", h[1], h[2], h[3], true)
    GameTooltip:AddLine("Right-click the title bar: this menu too", h[1], h[2], h[3], true)
    GameTooltip:Show()
end

-- Blizzard's settings cog (the quest log's atlas, as UIPanelIconDropdownButtonTemplate shows it)
-- left of the fold button; no atlas: a "..." text button. Same level as the fold/close buttons
-- (above the metal border).
function NP.CreateSettingsButton(f, fold, close)
    local b = CreateFrame("Button", nil, f)
    b:SetSize(20, 20)
    local anchor = fold or close
    if anchor then
        b:SetPoint("RIGHT", anchor, "LEFT", -1, 0)
    else
        b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -56, -2)
    end
    local lv = b:GetFrameLevel()
    for _, o in ipairs({ fold, close, f.TitleContainer }) do
        if type(o) == "table" and o.GetFrameLevel then
            local l = o:GetFrameLevel()
            if type(l) == "number" and l > lv then lv = l end
        end
    end
    b:SetFrameLevel(lv + 1) -- one above them all: the title strip never draws over the cog

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("CENTER")
    icon:SetSize(15, 16)
    if NP.AtlasExists(NP.Art.settingsAtlas) and pcall(icon.SetAtlas, icon, NP.Art.settingsAtlas) then
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(icon)
        pcall(hl.SetAtlas, hl, NP.Art.settingsAtlas)
        hl:SetBlendMode("ADD")
        hl:SetAlpha(0.4)
        b.Icon = icon
        b.NPLook = "atlas"
    else
        icon:Hide()
        local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("CENTER", 0, 3)
        fs:SetText("...")
        b:SetFontString(fs)
        b.NPLook = "text"
    end
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(self) NP.OpenSettingsMenu(self) end)
    b:SetScript("OnEnter", CogTooltip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

-- After the window is built (Core.lua, ADDON_LOADED) -------------------------------------

function NP.SetupSettings()
    if setUp then return end
    local ww = NP.WindowWidgets and NP.WindowWidgets() or {}
    frame = ww.frame
    if not frame then return end
    setUp = true

    -- open/closed, for "open after login" (not while the game is logging out or reloading:
    -- it closes every window then)
    frame:HookScript("OnShow", function()
        if not NP.loggingOut then NP.db.window.shown = true end
        UpdateTicker()
    end)
    frame:HookScript("OnHide", function(self)
        -- still "shown" = only a parent was hidden (Alt+Z, a cinematic): not closed by the user
        if not NP.loggingOut and not self:IsShown() then NP.db.window.shown = false end
        openMenu = nil
        UpdateTicker()
    end)

    -- Ctrl + wheel over the text (the checklist's own wheel scripts check Ctrl themselves)
    local box = ww.modernBox
    if box and box.GetScrollBox then
        local ok, sb = pcall(box.GetScrollBox, box)
        if ok then WrapWheel(sb) end
    end
    WrapWheel(ww.classicScroll)

    if NP.UpdateGrip then NP.UpdateGrip() end
    local wasShown = NP.db.window.shown
    NP.db.window.shown = frame:IsShown()
    if NP.db.settings.rememberOpen and wasShown then frame:Show() end -- folded state is already applied
    UpdateTicker()
end
