-- Note Pad: core (saved data, events, slash commands)
local addonName, NP = ...

NP.DB_VERSION = 1

NP.defaults = {
    text = "",
    window = { point = "CENTER", relPoint = "CENTER", x = 0, y = 0, w = 420, h = 320 },
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

function NP.InitDB()
    if type(NotePadDB) ~= "table" then NotePadDB = {} end
    local db = NotePadDB
    ApplyDefaults(db, NP.defaults)
    -- Future upgrades go here, keyed on db.dbVersion; never drop the user's text.
    db.dbVersion = NP.DB_VERSION
    NP.db = db
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
        NP.Print("/np reset - move the window back to the middle")
        NP.Print("/np minimap - show or hide the minimap button")
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
