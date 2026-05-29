-------------------------------------------------------------------------------
--  SphereUnitFrames · MicroMenu.lua
--  Micro menu fantasy fade-in : Personnage / Sorts / Talents / ... + Addons.
--  Style discret par défaut (alpha 0.30), apparait sur survol,
--  effet de zoom "dock macOS" par icône, sous-menu LibDBIcon.
-------------------------------------------------------------------------------

local ADDON = "SphereUnitFrames"
local SUF   = _G[ADDON]
if not SUF then return end

SUF.MicroMenu = SUF.MicroMenu or {}
local MM = SUF.MicroMenu

local function _safeCall(...)
    local args = {...}
    return function()
        for _, candidate in ipairs(args) do
            local fn = type(candidate) == "string" and _G[candidate] or candidate
            if type(fn) == "function" then
                if pcall(fn) then return end
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
     action=function() if _G.StoreMicroButton then
        pcall(_G.StoreMicroButton:GetScript("OnClick"), _G.StoreMicroButton, "LeftButton")
     end end},
    {label="Menu",        icon="Interface\\Buttons\\UI-MicroButton-MainMenu-Up",
     action=_safeCall("ToggleGameMenu")},
}

MM._frame   = nil
MM._buttons = nil

-- ─── Zoom dock-style : interpole la taille du bouton vers une cible ──────────
local function _btnTick(b, elapsed)
    if not b._origSize then return end
    local target = b._zoomTarget or b._origSize
    local current = b:GetWidth() or b._origSize
    local diff = target - current
    if math.abs(diff) > 0.4 then
        local step = diff * math.min(1, elapsed * 12)
        b:SetSize(current + step, current + step)
    else
        b:SetSize(target, target)
    end
end

function MM:Build()
    if self._frame then return self._frame end
    local cfg = SUF.db
    if cfg and cfg.micromenu_enabled == false then return nil end

    local btnSize  = (cfg and cfg.micromenu_btn_size)  or 22
    local btnSpace = (cfg and cfg.micromenu_btn_space) or 4
    local idleA    = (cfg and cfg.micromenu_idle_alpha) or 0.30
    local count    = #BUTTONS + 1   -- +1 = bouton "Addons"

    local f = CreateFrame("Frame", "SUFMicroMenu", UIParent)
    f:SetSize(count * (btnSize + btnSpace) + btnSpace, btnSize + 14)
    f:SetFrameStrata("MEDIUM")
    f:SetFrameLevel(100)
    f:EnableMouse(true)
    -- ── Position : bas écran, discret ────────────────────────────────────────
    f:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 6)
    f:SetAlpha(idleA)

    -- Fade-in au survol, fade-out à la sortie (avec délai pour stabilité)
    f._idleA = idleA
    f:SetScript("OnEnter", function(self)
        UIFrameFadeIn(self, 0.15, self:GetAlpha(), 1.0)
    end)
    f:SetScript("OnLeave", function(self)
        C_Timer.After(0.10, function()
            if self and not self:IsMouseOver() then
                UIFrameFadeOut(self, 0.45, self:GetAlpha(), self._idleA or 0.30)
            end
        end)
    end)

    self._buttons = {}

    local function makeBtn(i, def, isAddons)
        local b = CreateFrame("Button", "SUFMicroBtn_"..i, f)
        b:SetSize(btnSize, btnSize)
        b._origSize = btnSize
        b._zoomTarget = btnSize
        -- Ancrage : centre vertical de la barre
        b:SetPoint("BOTTOM", f, "BOTTOM", (i - 0.5 - count * 0.5) * (btnSize + btnSpace), 4)

        local icon = b:CreateTexture(nil, "ARTWORK")
        icon:SetTexture(def.icon)
        icon:SetPoint("CENTER", b, "CENTER", 0, 0)
        icon:SetSize(btnSize, btnSize)
        icon:SetTexCoord(0.10, 0.90, 0.10, 0.90)
        b._icon = icon

        -- Tick zoom à chaque frame
        b:SetScript("OnUpdate", _btnTick)

        b:SetScript("OnEnter", function(self)
            self._zoomTarget = self._origSize * 1.55
            -- Tooltip
            if GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(def.label, 1, 0.92, 0.6)
                GameTooltip:Show()
            end
        end)
        b:SetScript("OnLeave", function(self)
            self._zoomTarget = self._origSize
            if GameTooltip then GameTooltip:Hide() end
        end)
        b:SetScript("OnClick", isAddons and function() MM:ToggleAddonFlyout(b) end or def.action)
        return b
    end

    for i, def in ipairs(BUTTONS) do
        self._buttons[i] = makeBtn(i, def, false)
    end
    -- Bouton "Addons" en fin de rangée
    self._buttons[#BUTTONS + 1] = makeBtn(#BUTTONS + 1,
        {label="Addons (minimap)", icon="Interface\\Icons\\INV_Misc_EngGizmos_27"},
        true)

    -- Repositionne maintenant que tous les boutons existent (alignement gauche → droite centré)
    local total = count * (btnSize + btnSpace) - btnSpace
    for i, b in ipairs(self._buttons) do
        b:ClearAllPoints()
        b:SetPoint("LEFT", f, "LEFT",
            (i - 1) * (btnSize + btnSpace) + (f:GetWidth() - total) * 0.5, 0)
    end

    self._frame = f
    return f
end

-- ─── Sous-menu : tous les boutons addons (LibDBIcon + enfants Minimap) ───────
function MM:ToggleAddonFlyout(parent)
    if self._flyout and self._flyout:IsShown() then
        self._flyout:Hide(); return
    end
    if InCombatLockdown() then
        SUF:Print("Sous-menu addons indisponible en combat.")
        return
    end
    local f = self._flyout
    if not f then
        f = CreateFrame("Frame", "SUFMicroAddonFlyout", UIParent, "BackdropTemplate")
        f:SetFrameStrata("DIALOG")
        f:SetFrameLevel(400)
        pcall(function()
            f:SetBackdrop({
                bgFile   = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile=true, tileSize=16, edgeSize=10,
                insets={left=3,right=3,top=3,bottom=3},
            })
            f:SetBackdropColor(0.06, 0.06, 0.10, 0.96)
            f:SetBackdropBorderColor(0.55, 0.45, 0.18, 0.95)
        end)
        self._flyout = f
    end

    -- Collecte LibDBIcon + boutons enfants du blip Minimap
    local btns, seen = {}, {}
    local function consider(o)
        if not o or seen[o] then return end
        local ok, isBtn = pcall(function() return o.GetObjectType and o:GetObjectType() == "Button" end)
        if not (ok and isBtn) then return end
        local okN, name = pcall(function() return o:GetName() end)
        if okN and name and (name:find("LibDBIcon") or name:find("MinimapButton") or name:find("_MinimapButton") or name:find("MinimapIcon")) then
            seen[o] = true; btns[#btns+1] = o
        end
    end
    if _G.Minimap then
        local ok, kids = pcall(function() return { _G.Minimap:GetChildren() } end)
        if ok then for _, c in ipairs(kids) do consider(c) end end
    end
    if _G.LibStub then
        local okL, ldb = pcall(function() return LibStub("LibDBIcon-1.0", true) end)
        if okL and ldb and ldb.objects then
            for _, b in pairs(ldb.objects) do consider(b) end
        end
    end

    local perRow, sz, pad = 8, 26, 4
    local n = #btns
    if n == 0 then
        f:SetSize(180, 40)
        if not f._emptyFS then
            f._emptyFS = f:CreateFontString(nil, "OVERLAY")
            f._emptyFS:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
            f._emptyFS:SetPoint("CENTER")
            f._emptyFS:SetTextColor(1, 0.85, 0.5, 1)
        end
        f._emptyFS:SetText("Aucun bouton addon détecté")
        f._emptyFS:Show()
    else
        if f._emptyFS then f._emptyFS:Hide() end
        local rows = math.ceil(n / perRow)
        f:SetSize(perRow * (sz + pad) + pad * 2, rows * (sz + pad) + pad * 2)
        for i, b in ipairs(btns) do
            local col = (i - 1) % perRow
            local row = math.floor((i - 1) / perRow)
            pcall(function()
                b:SetParent(f)
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", f, "TOPLEFT", pad + col*(sz+pad), -(pad + row*(sz+pad)))
                b:SetSize(sz, sz)
                b:Show()
            end)
        end
    end
    f:ClearAllPoints()
    f:SetPoint("BOTTOM", parent, "TOP", 0, 8)
    f:Show()
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
    if self._flyout then self._flyout:Hide() end
    if SUF.db and SUF.db.micromenu_enabled ~= false then self:Build() end
end

function MM:SetVisible(v)
    if self._frame then self._frame:SetShown(v) end
end
