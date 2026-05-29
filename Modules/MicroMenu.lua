-------------------------------------------------------------------------------
--  SphereUnitFrames · MicroMenu.lua
--  Rangée de boutons type "micro menu" — feuille perso, talents, sorts, etc.
--  Utilise les textures natives Blizzard UI-MicroButton-*-Up + Up icons.
-------------------------------------------------------------------------------

local ADDON = "SphereUnitFrames"
local SUF   = _G[ADDON]
if not SUF then return end

SUF.MicroMenu = SUF.MicroMenu or {}
local MM = SUF.MicroMenu

-- Toggles défensifs (les fonctions WoW Midnight ont parfois changé de nom)
local function _safeCall(...)
    local args = {...}
    return function()
        for _, candidate in ipairs(args) do
            local fn = type(candidate) == "string" and _G[candidate] or candidate
            if type(fn) == "function" then
                local ok = pcall(fn)
                if ok then return end
            end
        end
    end
end

local BUTTONS = {
    {label="Personnage",  icon="Interface\\Buttons\\UI-MicroButton-Character-Up",
     action=function() pcall(function() ToggleCharacter("PaperDollFrame") end) end},
    {label="Sorts",       icon="Interface\\Buttons\\UI-MicroButton-Spellbook-Up",
     action=_safeCall("ToggleSpellBook")},
    {label="Talents",     icon="Interface\\Buttons\\UI-MicroButton-Talents-Up",
     action=function()
        if PlayerSpellsUtil and PlayerSpellsUtil.ToggleClassTalentFrame then
            pcall(PlayerSpellsUtil.ToggleClassTalentFrame)
        elseif _G.ClassTalentFrame_ToggleFrame then pcall(_G.ClassTalentFrame_ToggleFrame)
        elseif _G.ToggleTalentFrame then pcall(_G.ToggleTalentFrame) end
     end},
    {label="Hauts faits", icon="Interface\\Buttons\\UI-MicroButton-Achievement-Up",
     action=_safeCall("ToggleAchievementFrame")},
    {label="Quêtes",      icon="Interface\\Buttons\\UI-MicroButton-Quest-Up",
     action=_safeCall("ToggleQuestLog")},
    {label="Sociaux",     icon="Interface\\Buttons\\UI-MicroButton-Socials-Up",
     action=_safeCall("ToggleFriendsFrame")},
    {label="Collections", icon="Interface\\Buttons\\UI-MicroButton-MountsAndPets-Up",
     action=_safeCall("ToggleCollectionsJournal")},
    {label="Boutique",    icon="Interface\\Buttons\\UI-MicroButton-Store-Up",
     action=function() if _G.StoreMicroButton then pcall(_G.StoreMicroButton:GetScript("OnClick"), _G.StoreMicroButton) end end},
    {label="Menu",        icon="Interface\\Buttons\\UI-MicroButton-MainMenu-Up",
     action=_safeCall("ToggleGameMenu")},
}

MM._buttons = nil
MM._frame   = nil

function MM:Build()
    if self._frame then return self._frame end
    local cfg = SUF.db
    if cfg and cfg.micromenu_enabled == false then return nil end

    local data = SUF.player
    local parent = (data and data.root) or UIParent
    local f = CreateFrame("Frame", "SUFMicroMenu", parent)
    local btnSize  = (cfg and cfg.micromenu_btn_size) or 26
    local btnSpace = (cfg and cfg.micromenu_btn_space) or 2
    local count    = #BUTTONS
    f:SetSize(count * (btnSize + btnSpace), btnSize + 6)
    f:SetFrameStrata("MEDIUM")
    f:SetFrameLevel(((data and data.root and data.root:GetFrameLevel()) or 100) + 10)

    local pos = (cfg and cfg.micromenu_position) or "bottom"
    if pos == "top" then
        f:SetPoint("BOTTOM", (data and data.orb) or UIParent, "TOP", 0, 14)
    else
        f:SetPoint("TOP", (data and data.orb) or UIParent, "BOTTOM", 0, -14)
    end

    self._buttons = {}
    for i, def in ipairs(BUTTONS) do
        local b = CreateFrame("Button", "SUFMicroMenu_"..i, f, "BackdropTemplate")
        b:SetSize(btnSize, btnSize)
        b:SetPoint("LEFT", f, "LEFT", (i - 1) * (btnSize + btnSpace), 0)
        pcall(function()
            b:SetBackdrop({
                bgFile   = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = 1,
            })
            b:SetBackdropColor(0.04, 0.04, 0.07, 0.85)
            b:SetBackdropBorderColor(0.55, 0.45, 0.18, 0.85)
        end)

        local icon = b:CreateTexture(nil, "ARTWORK")
        icon:SetTexture(def.icon)
        icon:SetPoint("CENTER", b, "CENTER", 0, 0)
        icon:SetSize(btnSize - 4, btnSize - 4)
        icon:SetTexCoord(0.12, 0.88, 0.12, 0.88)
        b._icon = icon

        -- Highlight or au survol
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(b)
        hl:SetTexture("Interface\\Buttons\\WHITE8X8")
        hl:SetVertexColor(1.0, 0.85, 0.2, 0.25)

        b:SetScript("OnClick", def.action)
        b:SetScript("OnEnter", function(self)
            if GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(def.label, 1, 0.92, 0.6)
                GameTooltip:Show()
            end
        end)
        b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

        self._buttons[i] = b
    end

    self._frame = f
    return f
end

function MM:Init()
    local cfg = SUF.db
    if not cfg then return end
    if cfg.micromenu_enabled ~= false then
        C_Timer.After(0.2, function() MM:Build() end)
    end
end

function MM:Refresh()
    if self._frame then self._frame:Hide(); self._frame = nil; self._buttons = nil end
    if SUF.db and SUF.db.micromenu_enabled ~= false then self:Build() end
end

function MM:SetVisible(v)
    if self._frame then self._frame:SetShown(v) end
end
