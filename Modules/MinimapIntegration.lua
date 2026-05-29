-------------------------------------------------------------------------------
--  SphereUnitFrames · MinimapIntegration.lua
--  Fusion visuelle Minimap ↔ Sphère HP.
--
--  Principe (refonte) :
--    • On reparente le BLIP `Minimap` (pas tout MinimapCluster) dans
--      minimapHolder (root+2). Seul le disque carte est conservé — le cadre,
--      le texte de zone et les boutons d'origine sont masqués.
--    • Masque circulaire (TempPortraitAlphaMask) → carte ronde épousant l'orbe.
--    • Le verre/gloss de l'orbe (overlayOrbFrame root+4) reste AU-DESSUS de la
--      carte (root+2) → sensation de carte sous le verre de la sphère.
--    • Orb:SetMapMode masque les couches HP pour révéler la carte.
--    • Clic gauche sur l'orbe (Interaction) → Minimap:Toggle().
--    • Bouton groupé (SUFMinimapHub) : clic gauche = toggle, clic droit =
--      flyout regroupant les mini-boutons de la minimap.
--
--  Gardes combat : SetParent/SetSize interdits en InCombatLockdown().
-------------------------------------------------------------------------------

local ADDON = "SphereUnitFrames"
local SUF   = _G[ADDON]
if not SUF then return end

SUF.Minimap = SUF.Minimap or {}
local Minimap = SUF.Minimap

local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

Minimap._integrated       = false
Minimap._pendingIntegrate = false
Minimap._pendingRelease   = false
Minimap._orig             = nil   -- état d'origine du blip Minimap

-- ─── Sauvegarde / restauration de l'état du blip ──────────────────────────────
local function _saveOriginal()
    if Minimap._orig then return end
    if not _G.Minimap then return end
    local mm = _G.Minimap
    local o  = { points = {} }
    pcall(function() o.parent = mm:GetParent() end)
    pcall(function() o.scale  = mm:GetScale() end)
    pcall(function() o.w, o.h = mm:GetSize() end)
    local n = (mm.GetNumPoints and mm:GetNumPoints()) or 0
    for i = 1, n do
        local pt, rel, rpt, x, y = mm:GetPoint(i)
        o.points[i] = { pt, rel, rpt, x, y }
    end
    Minimap._orig = o
end

-- Masquer/montrer les décorations du cluster (cadre, texte zone, compass)
local function _setClusterDecor(shown)
    local function vis(name)
        local f = _G[name]
        if f then pcall(function() if shown then f:Show() else f:Hide() end end) end
    end
    -- Noms variables selon version → tous gardés en pcall
    vis("MinimapBorder"); vis("MinimapBorderTop"); vis("MinimapBackdrop")
    vis("MinimapCompassTexture"); vis("MiniMapWorldMapButton")
    vis("MinimapZoneTextButton"); vis("MinimapZoneText")
    if MinimapCluster then
        pcall(function() if MinimapCluster.BorderTop then
            if shown then MinimapCluster.BorderTop:Show() else MinimapCluster.BorderTop:Hide() end
        end end)
        pcall(function() if MinimapCluster.ZoneTextButton then
            if shown then MinimapCluster.ZoneTextButton:Show() else MinimapCluster.ZoneTextButton:Hide() end
        end end)
    end
end

-- ─── Init ────────────────────────────────────────────────────────────────────
function Minimap:Init()
    local cfg = SUF.db
    if not cfg then return end
    self:EnsureHub()
    if cfg.minimap_mode == "integrated" then
        C_Timer.After(0.1, function()
            if SUF.Minimap then SUF.Minimap:Evaluate() end
        end)
    end
end

-- ─── Integrate : reparente le blip dans l'orbe ────────────────────────────────
function Minimap:Integrate()
    if self._integrated then return end
    local data = SUF.player
    if not (data and data.minimapHolder) then return end
    if not _G.Minimap then return end

    if InCombatLockdown() then
        self._pendingIntegrate = true
        self._pendingRelease   = false
        return
    end

    _saveOriginal()
    local mm     = _G.Minimap
    local holder = data.minimapHolder
    local orbSize = (SUF.db and SUF.db.orbSize) or 160

    pcall(function()
        mm:SetParent(holder)
        mm:ClearAllPoints()
        mm:SetPoint("CENTER", holder, "CENTER", 0, 0)
        mm:SetScale(1.0)
        mm:SetSize(orbSize * (SUF.db.minimap_zoom or 1.0), orbSize * (SUF.db.minimap_zoom or 1.0))
        mm:SetFrameStrata(holder:GetFrameStrata())
        mm:SetFrameLevel((holder:GetFrameLevel() or 102))
    end)

    -- Masque circulaire sur le blip
    if SUF.db.minimap_blip_only ~= false then
        pcall(function() mm:SetMaskTexture(CIRCLE_MASK) end)
        _setClusterDecor(false)
    end

    -- Boutons zoom/tracking d'origine masqués (regroupés dans le hub)
    if SUF.db and SUF.db.minimap_hide_buttons then
        local function hide(name) local f=_G[name]; if f then pcall(f.Hide,f) end end
        hide("MinimapZoomIn"); hide("MinimapZoomOut")
        hide("MiniMapTracking"); hide("MinimapToggleButton")
    end

    self._integrated       = true
    self._pendingIntegrate = false
    if SUF.Log then SUF.Log:Info("Minimap", "Blip intégré dans l'orbe") end
end

-- ─── Release : restaure le blip à sa place d'origine ──────────────────────────
function Minimap:Release()
    if not self._integrated then return end
    if not _G.Minimap then return end

    if InCombatLockdown() then
        self._pendingRelease   = true
        self._pendingIntegrate = false
        return
    end

    local mm = _G.Minimap
    local o  = Minimap._orig
    pcall(function()
        if o then
            mm:SetParent(o.parent or MinimapCluster or UIParent)
            mm:ClearAllPoints()
            if o.points and #o.points > 0 then
                for _, p in ipairs(o.points) do mm:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
            else
                mm:SetPoint("CENTER", MinimapCluster or UIParent, "CENTER", 0, 0)
            end
            if o.scale then mm:SetScale(o.scale) end
            if o.w and o.h then mm:SetSize(o.w, o.h) end
        end
    end)
    _setClusterDecor(true)
    pcall(function()
        if MinimapZoomIn  then MinimapZoomIn:Show()  end
        if MinimapZoomOut then MinimapZoomOut:Show() end
        if MiniMapTracking then MiniMapTracking:Show() end
    end)

    local data = SUF.player
    if data and data.minimapHolder then data.minimapHolder:Hide() end
    self._integrated     = false
    self._pendingRelease = false
    if SUF.Log then SUF.Log:Info("Minimap", "Blip relâché") end
end

-- ─── ShowMap / ShowSphere / Toggle ────────────────────────────────────────────
function Minimap:ShowMap()
    if InCombatLockdown() then return end
    local data = SUF.player
    if not data then return end
    if not self._integrated then self:Integrate() end
    if data.minimapHolder then data.minimapHolder:Show() end
    if not data._mapMode and SUF.Orb then pcall(SUF.Orb.SetMapMode, SUF.Orb, data, true) end
    if SUF.db then SUF.db.minimap_shown = true end
end

function Minimap:ShowSphere()
    local data = SUF.player
    if data and data.minimapHolder then data.minimapHolder:Hide() end
    -- ne réinitialise l'orbe que si on était réellement en mode carte
    if data and data._mapMode and SUF.Orb then pcall(SUF.Orb.SetMapMode, SUF.Orb, data, false) end
    if SUF.db then SUF.db.minimap_shown = false end
end

function Minimap:Toggle()
    if SUF.db and SUF.db.minimap_shown then self:ShowSphere() else self:ShowMap() end
end

-- ─── UpdateScale ──────────────────────────────────────────────────────────────
function Minimap:UpdateScale()
    if not self._integrated then return end
    if not _G.Minimap then return end
    local orbSize = (SUF.db and SUF.db.orbSize) or 160
    local mm = _G.Minimap
    pcall(function()
        mm:SetSize(orbSize * (SUF.db.minimap_zoom or 1.0), orbSize * (SUF.db.minimap_zoom or 1.0))
        local data = SUF.player
        if data and data.minimapHolder then
            mm:ClearAllPoints()
            mm:SetPoint("CENTER", data.minimapHolder, "CENTER", 0, 0)
        end
    end)
end

-- ─── Evaluate ─────────────────────────────────────────────────────────────────
function Minimap:Evaluate()
    local cfg = SUF.db
    if not cfg then return end
    if (cfg.minimap_mode or "disabled") == "disabled" then
        self:ShowSphere()
        if self._integrated then self:Release() end
        return
    end
    -- Mode intégré : le blip vit dans l'orbe (retire la minimap du coin).
    -- L'affichage carte vs sphère est piloté par minimap_shown (clic toggle).
    if not self._integrated and not SUF.InCombat and not InCombatLockdown() then
        self:Integrate()
    end
    if cfg.minimap_shown and not SUF.InCombat then
        self:ShowMap()
    else
        self:ShowSphere()
    end
end

-- ─── Bouton groupé (hub) ──────────────────────────────────────────────────────
-- Regroupe les mini-boutons de la minimap. Clic gauche = toggle carte/sphère,
-- clic droit = flyout listant les boutons collectés.
function Minimap:EnsureHub()
    if self._hub then return self._hub end
    local data = SUF.player
    if not data or not data.root then return nil end
    if InCombatLockdown() then return nil end

    local root = data.root
    local hub = CreateFrame("Button", "SUFMinimapHub", root)
    hub:SetSize(26, 26)
    -- ancré en bas-droit de l'orbe (comme le "M" du screenshot)
    hub:SetPoint("CENTER", data.orb, "BOTTOMRIGHT", -6, 6)
    hub:SetFrameLevel((root:GetFrameLevel() or 100) + 9)
    hub:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local bg = hub:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(hub)
    bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    bg:SetVertexColor(0.05, 0.05, 0.08, 0.85)
    local mask = hub:CreateMaskTexture()
    pcall(function()
        mask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(hub)
        bg:AddMaskTexture(mask)
    end)
    local ic = hub:CreateTexture(nil, "ARTWORK")
    ic:SetPoint("CENTER")
    ic:SetSize(18, 18)
    ic:SetTexture("Interface\\Minimap\\Tracking\\None")
    pcall(function() ic:SetTexture("Interface\\Icons\\INV_Misc_Map_01") end)
    pcall(function() ic:AddMaskTexture(mask) end)
    hub._icon = ic

    hub:SetScript("OnClick", function(self, btn)
        if btn == "LeftButton" then
            if SUF.Minimap then pcall(SUF.Minimap.Toggle, SUF.Minimap) end
        else
            if SUF.Minimap then pcall(SUF.Minimap.ToggleFlyout, SUF.Minimap) end
        end
    end)
    hub:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Minimap")
            GameTooltip:AddLine("|cFFAAAAAAClic gauche : carte / sphère|r")
            GameTooltip:AddLine("|cFFAAAAAAClic droit : boutons minimap|r")
            GameTooltip:Show()
        end
    end)
    hub:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    self._hub = hub
    return hub
end

-- Collecte les mini-boutons de la minimap (LibDBIcon + boutons enfants)
local function _collectMinimapButtons()
    local found = {}
    local seen  = {}
    local function consider(f)
        if not f or seen[f] then return end
        if type(f) ~= "table" then return end
        local ok, isBtn = pcall(function() return f.GetObjectType and f:GetObjectType() == "Button" end)
        if not (ok and isBtn) then return end
        local okN, name = pcall(function() return f:GetName() end)
        if okN and name and (name:find("LibDBIcon") or name:find("MinimapButton") or name:find("_MinimapButton")) then
            seen[f] = true; found[#found+1] = f
        end
    end
    -- enfants du blip Minimap
    if _G.Minimap then
        local ok, kids = pcall(function() return { _G.Minimap:GetChildren() } end)
        if ok then for _, c in ipairs(kids) do consider(c) end end
    end
    -- LibDBIcon global
    if _G.LibStub then
        local okL, ldb = pcall(function() return LibStub("LibDBIcon-1.0", true) end)
        if okL and ldb and ldb.objects then
            for _, b in pairs(ldb.objects) do consider(b) end
        end
    end
    return found
end

function Minimap:ToggleFlyout()
    if self._flyout and self._flyout:IsShown() then self._flyout:Hide(); return end
    if InCombatLockdown() then SUF:Print("Boutons minimap indisponibles en combat."); return end
    if not self._hub then self:EnsureHub() end
    if not self._hub then return end

    local fly = self._flyout
    if not fly then
        fly = CreateFrame("Frame", "SUFMinimapFlyout", UIParent, "BackdropTemplate")
        fly:SetFrameStrata("DIALOG")
        fly:SetFrameLevel(400)
        pcall(function()
            fly:SetBackdrop({ bgFile="Interface\\Buttons\\WHITE8X8",
                edgeFile="Interface\\Buttons\\WHITE8X8", edgeSize=1 })
            fly:SetBackdropColor(0.06, 0.06, 0.10, 0.96)
            fly:SetBackdropBorderColor(0.5, 0.5, 0.65, 1)
        end)
        self._flyout = fly
    end

    -- (Re)parente les boutons collectés dans une grille
    local btns = _collectMinimapButtons()
    local perRow, sz, pad = 4, 30, 4
    local n = #btns
    if n == 0 then
        fly:SetSize(150, 30)
    else
        local rows = math.ceil(n / perRow)
        fly:SetSize(perRow * (sz + pad) + pad, rows * (sz + pad) + pad)
        for i, b in ipairs(btns) do
            local col = (i - 1) % perRow
            local row = math.floor((i - 1) / perRow)
            pcall(function()
                b:SetParent(fly)
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", fly, "TOPLEFT", pad + col*(sz+pad), -(pad + row*(sz+pad)))
                b:SetSize(sz, sz)
                b:Show()
            end)
        end
    end
    fly:ClearAllPoints()
    fly:SetPoint("BOTTOM", self._hub, "TOP", 0, 4)
    fly:Show()
end

-- ─── Combat hooks ─────────────────────────────────────────────────────────────
function Minimap:OnEnterCombat()
    self._pendingIntegrate = false
    if self._flyout then self._flyout:Hide() end
end

function Minimap:OnExitCombat()
    if self._pendingRelease then
        self._pendingRelease = false
        self:Release()
        return
    end
    if self._pendingIntegrate then
        self._pendingIntegrate = false
    end
    C_Timer.After(0.5, function()
        if SUF.Minimap then SUF.Minimap:Evaluate() end
    end)
end
