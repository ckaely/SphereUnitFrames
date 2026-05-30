-------------------------------------------------------------------------------
--  SphereUnitFrames · XPBar.lua
--  Barre d'XP CIRCULAIRE simple : un disque CooldownFrame placé SOUS l'orbe.
--  L'orbe couvre le centre → seul l'anneau extérieur s'affiche.
--  Le CooldownFrame en mode reverse fait office de "masque qui remplit
--  selon le pourcentage" (le secteur visible = ratio × 360°).
-------------------------------------------------------------------------------

local ADDON = "SphereUnitFrames"
local SUF   = _G[ADDON]
if not SUF then return end

SUF.XPBar = SUF.XPBar or {}
local XPBar = SUF.XPBar

-- Durée fictive longue → barre visuellement statique (drift négligeable).
-- (Note d'altitude : on détourne SetCooldown pour faire un fill statique.
--  Acceptable tant qu'on n'a qu'une seule barre ; remplaçable plus tard par
--  le pattern Quafe-PpBar décrit dans Ingenieur_addons.md §8 si besoin.)
local STATIC_DURATION = 1e6

-- Couleur courante (depuis cfg, avec defaults). Utilisée par Build et Update.
local function _color(cfg)
    return cfg.xpbar_lit_r or 0.65,
           cfg.xpbar_lit_g or 0.25,
           cfg.xpbar_lit_b or 1.00
end

function XPBar:Build(data)
    if not data or not data.root or not data.orb then return end
    local cfg = SUF.db
    if not cfg or cfg.xpbar_enabled == false then return end
    if data._xpFrame then return end

    local root    = data.root
    local orb     = data.orb
    local barSize = (cfg.orbSize or 160) * (cfg.xpbar_radius_ratio or 1.32)
    local rootFL  = root:GetFrameLevel() or 100

    -- Frame placé SOUS le frame de l'orbe (rootFL+2) → l'orbe le recouvre au
    -- centre. Seul le bord (l'anneau XP) reste visible.
    local frame = CreateFrame("Frame", "SUFXPBarFrame", root)
    frame:SetSize(barSize, barSize)
    frame:SetPoint("CENTER", orb, "CENTER", 0, 0)
    frame:SetFrameLevel(math.max(0, rootFL - 1))

    -- CooldownFrame en mode "pie statique" : c'est notre masque de remplissage.
    -- SetReverse(true) → le secteur "elapsed" est visible (= la portion remplie).
    -- SetCooldown(now - ratio × dur, dur) → elapsed = ratio × dur.
    local cd = CreateFrame("Cooldown", "SUFXPBarCD", frame)
    cd:SetAllPoints(frame)
    cd:SetDrawSwipe(true)
    cd:SetDrawEdge(false)
    cd:SetDrawBling(false)
    cd:SetHideCountdownNumbers(true)
    cd:SetReverse(true)
    cd:SetUseCircularEdge(true)
    cd:SetSwipeTexture("Interface\\Cooldown\\ping4")

    data._xpFrame  = frame
    data._xpCD     = cd
    data._xpSize   = barSize    -- pour détecter les changements de géométrie
end

function XPBar:Update(data)
    data = data or SUF.player
    if not data or not data._xpCD then return end
    local cfg = SUF.db
    if not cfg or cfg.xpbar_enabled == false then return end

    local xp    = SUF:UntaintNum(UnitXP("player"))    or 0
    local maxXP = SUF:UntaintNum(UnitXPMax("player")) or 0

    -- Max level → on cache la barre
    if maxXP <= 0 then data._xpFrame:Hide(); return end
    data._xpFrame:Show()

    local ratio = math.max(0, math.min(1, xp / maxXP))

    -- Couleur live : ne re-applique que si elle a changé.
    local r, g, b = _color(cfg)
    if data._xpLastColor ~= r * 1e6 + g * 1e3 + b then
        data._xpCD:SetSwipeColor(r, g, b, 0.92)
        data._xpLastColor = r * 1e6 + g * 1e3 + b
    end

    -- Fill = ratio × 360° : skip si inchangé (PLAYER_ENTERING_WORLD + Init
    -- peuvent tirer Update 2× au même tick).
    if data._xpLastRatio and math.abs(ratio - data._xpLastRatio) < 1e-4 then
        return
    end
    data._xpLastRatio = ratio
    data._xpCD:SetCooldown(GetTime() - ratio * STATIC_DURATION, STATIC_DURATION)
end

function XPBar:Init()
    local data = SUF.player
    if not data then return end
    self:Build(data)
    self:Update(data)
    if not self._evt then
        local e = CreateFrame("Frame")
        e:RegisterEvent("PLAYER_XP_UPDATE")
        e:RegisterEvent("PLAYER_LEVEL_UP")
        e:RegisterEvent("UPDATE_EXHAUSTION")
        e:RegisterEvent("PLAYER_ENTERING_WORLD")
        e:SetScript("OnEvent", function() XPBar:Update(SUF.player) end)
        self._evt = e
    end
end

-- Live refresh : on ne reconstruit que si la géométrie a changé.
function XPBar:Refresh()
    local data = SUF.player
    if not data then return end
    local cfg = SUF.db
    if not cfg then return end
    local newSize = (cfg.orbSize or 160) * (cfg.xpbar_radius_ratio or 1.32)
    if data._xpFrame and data._xpSize == newSize then
        -- couleur / xp seulement → Update suffit (force la repaint via cache miss)
        data._xpLastColor = nil
        data._xpLastRatio = nil
        self:Update(data)
        return
    end
    if data._xpFrame then
        data._xpFrame:Hide()
        data._xpFrame = nil
        data._xpCD    = nil
        data._xpSize  = nil
    end
    self:Build(data)
    self:Update(data)
end
