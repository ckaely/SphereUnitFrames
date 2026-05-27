-------------------------------------------------------------------------------
--  SphereUnitFrames · MinimapIntegration.lua
--  Fusion visuelle Minimap ↔ Sphère HP.
--
--  Architecture :
--    • minimapHolder (root+2) créé dans Orb.lua — SetAllPoints(orb)
--    • MinimapCluster reparenté dans minimapHolder via SetParent
--    • Scale automatique : MinimapCluster:SetScale(orbSize / 208)
--    • Layer : minimapHolder = root+2, glassFrame = root+4 → verre sur la carte ✓
--    • Visibilité conditionnelle : HP ≥ seuil ET hors combat
--
--  Gardes combat :
--    • SetParent/SetScale interdits en InCombatLockdown()
--    • Flags _pendingIntegrate/_pendingRelease résolus dans OnExitCombat
--
--  Commandes : /suf minimap
-------------------------------------------------------------------------------

local ADDON = "SphereUnitFrames"
local SUF   = _G[ADDON]
if not SUF then return end

SUF.Minimap = SUF.Minimap or {}
local Minimap = SUF.Minimap

-- Taille par défaut de MinimapCluster en WoW retail
local DEFAULT_MINIMAP_SIZE = 208

Minimap._integrated        = false
Minimap._pendingIntegrate  = false
Minimap._pendingRelease    = false
Minimap._originalParent    = nil
Minimap._originalPoints    = nil
Minimap._originalScale     = 1.0

-- ─── Init ────────────────────────────────────────────────────────────────────
function Minimap:Init()
    local cfg = SUF.db
    if not cfg then return end
    if cfg.minimap_mode == "integrated" then
        -- Tenter l'intégration immédiate (on est hors combat au chargement)
        C_Timer.After(0.1, function()
            if SUF.Minimap then SUF.Minimap:Evaluate() end
        end)
    end
end

-- ─── Sauvegarder la position originale ───────────────────────────────────────
local function _saveOriginalState()
    if Minimap._originalParent then return end
    local mc = MinimapCluster
    if not mc then return end
    local ok, p = pcall(function() return mc:GetParent() end)
    Minimap._originalParent = (ok and p) or UIParent
    local ok2, s = pcall(function() return mc:GetScale() end)
    Minimap._originalScale = (ok2 and s) or 1.0
    -- Sauvegarder les anchors
    local nPts = mc:GetNumPoints() or 0
    Minimap._originalPoints = {}
    for i = 1, nPts do
        local pt, rel, rpt, x, y = mc:GetPoint(i)
        Minimap._originalPoints[i] = {pt, rel, rpt, x, y}
    end
end

-- ─── Integrate ────────────────────────────────────────────────────────────────
function Minimap:Integrate()
    if self._integrated then return end
    local data = SUF.player
    if not (data and data.minimapHolder) then return end
    if not MinimapCluster then return end

    if InCombatLockdown() then
        self._pendingIntegrate = true
        self._pendingRelease   = false
        return
    end

    _saveOriginalState()

    pcall(function()
        MinimapCluster:SetParent(data.minimapHolder)
        MinimapCluster:ClearAllPoints()
        MinimapCluster:SetPoint("CENTER", data.minimapHolder, "CENTER", 0, 0)
    end)

    local orbSize = (SUF.db and SUF.db.orbSize) or 160
    local scale   = orbSize / DEFAULT_MINIMAP_SIZE
    pcall(function() MinimapCluster:SetScale(scale) end)

    -- Masquer les boutons de zoom / tracking si configuré
    if SUF.db and SUF.db.minimap_hide_buttons then
        pcall(function()
            if MinimapZoomIn  then MinimapZoomIn:Hide()  end
            if MinimapZoomOut then MinimapZoomOut:Hide() end
        end)
        -- MiniMapTracking : peut exister ou non selon version
        pcall(function()
            if MiniMapTracking then MiniMapTracking:Hide() end
        end)
    end

    data.minimapHolder:Show()
    self._integrated       = true
    self._pendingIntegrate = false

    if SUF.Log then SUF.Log:Info("Minimap", string.format("Intégrée (scale=%.2f)", scale)) end
end

-- ─── Release ─────────────────────────────────────────────────────────────────
function Minimap:Release()
    if not self._integrated then return end
    if not MinimapCluster then return end

    if InCombatLockdown() then
        self._pendingRelease   = true
        self._pendingIntegrate = false
        return
    end

    -- Restaurer le parent original
    pcall(function()
        local parent = Minimap._originalParent or UIParent
        MinimapCluster:SetParent(parent)
        MinimapCluster:ClearAllPoints()
        if Minimap._originalPoints and #Minimap._originalPoints > 0 then
            for _, pt in ipairs(Minimap._originalPoints) do
                MinimapCluster:SetPoint(pt[1], pt[2], pt[3], pt[4], pt[5])
            end
        else
            -- Fallback : position par défaut top-right
            MinimapCluster:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -14, -14)
        end
        MinimapCluster:SetScale(Minimap._originalScale or 1.0)
    end)

    -- Restaurer les boutons
    pcall(function()
        if MinimapZoomIn  then MinimapZoomIn:Show()  end
        if MinimapZoomOut then MinimapZoomOut:Show() end
    end)
    pcall(function()
        if MiniMapTracking then MiniMapTracking:Show() end
    end)

    local data = SUF.player
    if data and data.minimapHolder then
        data.minimapHolder:Hide()
    end

    self._integrated     = false
    self._pendingRelease = false

    if SUF.Log then SUF.Log:Info("Minimap", "Relâchée") end
end

-- ─── UpdateScale (appelé depuis RefreshAll quand orbSize change) ──────────────
function Minimap:UpdateScale()
    if not self._integrated then return end
    if not MinimapCluster then return end
    local orbSize = (SUF.db and SUF.db.orbSize) or 160
    local scale   = orbSize / DEFAULT_MINIMAP_SIZE
    pcall(function() MinimapCluster:SetScale(scale) end)

    -- Repositionner dans le holder (scale change le positionnement relatif)
    local data = SUF.player
    if data and data.minimapHolder then
        pcall(function()
            MinimapCluster:ClearAllPoints()
            MinimapCluster:SetPoint("CENTER", data.minimapHolder, "CENTER", 0, 0)
        end)
    end
end

-- ─── Evaluate (décide intégrer/relâcher selon conditions) ────────────────────
function Minimap:Evaluate()
    local cfg = SUF.db
    if not cfg then return end

    if cfg.minimap_mode == "disabled" then
        if self._integrated then self:Release() end
        return
    end

    if cfg.minimap_mode ~= "integrated" then
        if self._integrated then self:Release() end
        return
    end

    -- Conditions d'affichage
    local data     = SUF.player
    local ratio    = (data and (data.displayHP or data.targetHP)) or 1.0
    local threshold = ((cfg.minimap_hp_threshold or 90) / 100)
    local hpOK     = ratio >= threshold
    local combatOK = not SUF.InCombat

    if hpOK and combatOK then
        if not self._integrated then self:Integrate() end
    else
        if self._integrated then self:Release() end
    end
end

-- ─── OnEnterCombat ────────────────────────────────────────────────────────────
function Minimap:OnEnterCombat()
    self._pendingIntegrate = false
    if self._integrated then
        self:Release()
    end
end

-- ─── OnExitCombat ─────────────────────────────────────────────────────────────
function Minimap:OnExitCombat()
    if self._pendingRelease then
        self._pendingRelease = false
        self:Release()
        return
    end
    if self._pendingIntegrate then
        self._pendingIntegrate = false
    end
    -- Délai court pour laisser le taint se dissiper
    C_Timer.After(0.5, function()
        if SUF.Minimap then SUF.Minimap:Evaluate() end
    end)
end
