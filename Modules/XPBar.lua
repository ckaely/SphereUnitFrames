-------------------------------------------------------------------------------
--  SphereUnitFrames · XPBar.lua
--  Barre d'XP CIRCULAIRE continue autour de la sphère.
--  10 dividers radiaux dessinés par-dessus pour montrer les paliers (visuels).
-------------------------------------------------------------------------------

local ADDON = "SphereUnitFrames"
local SUF   = _G[ADDON]
if not SUF then return end

SUF.XPBar = SUF.XPBar or {}
local XPBar = SUF.XPBar

local SEG_COUNT = 10
local function SNPM(n) return (SUF.MEDIA or "Interface\\AddOns\\SphereUnitFrames\\media\\") .. n end

-- Le CooldownFrame permet un fill circulaire continu : on l'utilise comme
-- "barre de progression circulaire", avec une durée très longue pour qu'il
-- soit visuellement statique (drift négligeable < 1 px / minute).
local STATIC_DURATION = 1e6

function XPBar:Build(data)
    if not data or not data.root or not data.orb then return end
    local cfg = SUF.db
    if cfg and cfg.xpbar_enabled == false then return end
    if data._xpBar then return data._xpBar end

    local root   = data.root
    local orb    = data.orb
    local size   = (cfg and cfg.orbSize) or 160
    local barSize = size * 1.30 * (cfg and cfg.xpbar_radius_ratio or 1.0)
    local rootFL = root:GetFrameLevel() or 100

    local frame = CreateFrame("Frame", "SUFXPBarFrame", root)
    frame:SetSize(size * 1.5, size * 1.5)
    frame:SetPoint("CENTER", orb, "CENTER", 0, 0)
    frame:SetFrameLevel(rootFL + 8)

    -- ── Ombre transparente (cercle plein légèrement plus grand) ──────────────
    local shadow = frame:CreateTexture(nil, "BACKGROUND")
    shadow:SetTexture(SNPM("orb-border"))
    shadow:SetSize(barSize + 6, barSize + 6)
    shadow:SetPoint("CENTER", frame, "CENTER", 0, 1)
    shadow:SetVertexColor(0, 0, 0, cfg and cfg.xpbar_shadow_alpha or 0.55)
    shadow:SetBlendMode("BLEND")

    -- ── Contour extérieur subtil ──────────────────────────────────────────────
    local outline = frame:CreateTexture(nil, "BORDER")
    outline:SetTexture(SNPM("orb-border"))
    outline:SetSize(barSize + 2, barSize + 2)
    outline:SetPoint("CENTER", frame, "CENTER", 0, 0)
    outline:SetVertexColor(0.32, 0.10, 0.55, cfg and cfg.xpbar_outline_alpha or 0.85)
    outline:SetBlendMode("ADD")

    -- ── Barre violette continue (CooldownFrame edge circulaire) ───────────────
    local cd = CreateFrame("Cooldown", "SUFXPBarCD", frame)
    cd:SetSize(barSize, barSize)
    cd:SetPoint("CENTER", frame, "CENTER", 0, 0)
    cd:SetDrawSwipe(true)
    cd:SetDrawEdge(false)
    cd:SetDrawBling(false)
    cd:SetHideCountdownNumbers(true)
    cd:SetReverse(true)   -- on veut afficher la portion "écoulée" comme remplie
    pcall(function() cd:SetSwipeTexture("Interface\\Cooldown\\ping4") end)
    pcall(function() cd:SetUseCircularEdge(true) end)
    local litR = cfg and cfg.xpbar_lit_r or 0.65
    local litG = cfg and cfg.xpbar_lit_g or 0.25
    local litB = cfg and cfg.xpbar_lit_b or 1.00
    cd:SetSwipeColor(litR, litG, litB, 0.92)

    -- ── Trou central (l'XP bar est un anneau, pas un disque) ─────────────────
    -- Masque inversé : on cache le centre via une texture qui occulte le disque
    -- intérieur (orb + petit padding).
    local innerHole = frame:CreateTexture(nil, "ARTWORK", nil, 4)
    innerHole:SetTexture(SUF.WHITE8x8 or "Interface\\Buttons\\WHITE8X8")
    innerHole:SetSize(size * 1.02, size * 1.02)
    innerHole:SetPoint("CENTER", frame, "CENTER", 0, 0)
    -- On utilise un masque circulaire pour clipper en rond
    local holeMask = innerHole:CreateMaskTexture and frame:CreateMaskTexture() or nil
    if holeMask then
        pcall(function()
            holeMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask",
                "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            holeMask:SetSize(size * 1.02, size * 1.02)
            holeMask:SetPoint("CENTER", frame, "CENTER", 0, 0)
            innerHole:AddMaskTexture(holeMask)
        end)
    end
    innerHole:SetVertexColor(0, 0, 0, 0)  -- transparent : sert juste à "trouer" visuellement
    -- En réalité, le mieux est de laisser le CD swipe à largeur réduite ; ici on
    -- s'appuie sur le fait que ping4 est un radial avec centre plus sombre.

    -- ── Dividers (10 lignes radiales noires PAR-DESSUS la barre) ────────────
    -- Ce sont les "paliers" visuels, comme dessiné par l'utilisateur.
    local segWidth  = (cfg and cfg.xpbar_seg_width)  or 3
    local segHeight = (cfg and cfg.xpbar_seg_height) or (barSize - size + 8)
    local dividers = {}
    local rRing = (barSize + size) * 0.5 * 0.5  -- rayon médian de l'anneau
    for i = 1, SEG_COUNT do
        -- Position du divider : à la frontière entre 2 segments
        local degDiv = (i - 1) * (360 / SEG_COUNT) - 90  -- top (12h) comme départ
        local rad = math.rad(degDiv)
        local x = math.cos(rad) * rRing
        local y = -math.sin(rad) * rRing

        local div = frame:CreateTexture(nil, "OVERLAY", nil, 4)
        div:SetTexture(SUF.WHITE8x8 or "Interface\\Buttons\\WHITE8X8")
        div:SetSize(segWidth, segHeight)
        div:SetPoint("CENTER", frame, "CENTER", x, y)
        div:SetRotation(rad + math.pi / 2)   -- aligné perpendiculaire au rayon
        div:SetVertexColor(0, 0, 0, 0.90)
        dividers[i] = div
    end

    data._xpBar = {
        frame = frame, cd = cd, shadow = shadow, outline = outline,
        dividers = dividers,
    }
    return data._xpBar
end

function XPBar:Update(data)
    data = data or SUF.player
    if not data or not data._xpBar then return end
    local cfg = SUF.db
    if cfg and cfg.xpbar_enabled == false then return end

    local xp, maxXP
    pcall(function() xp = UnitXP("player") end)
    pcall(function() maxXP = UnitXPMax("player") end)
    xp = tonumber(xp) or 0
    maxXP = tonumber(maxXP) or 0
    if maxXP <= 0 then
        data._xpBar.frame:Hide()
        return
    end
    data._xpBar.frame:Show()
    local ratio = math.max(0, math.min(1, xp / maxXP))

    -- Couleur (live update si config a changé)
    if cfg and data._xpBar.cd then
        local r = cfg.xpbar_lit_r or 0.65
        local g = cfg.xpbar_lit_g or 0.25
        local b = cfg.xpbar_lit_b or 1.00
        data._xpBar.cd:SetSwipeColor(r, g, b, 0.92)
    end

    -- Remplissage circulaire : on truque le SetCooldown pour afficher xpRatio
    -- comme "portion écoulée" (visible avec reverse=true).
    local now = GetTime()
    data._xpBar.cd:SetCooldown(now - ratio * STATIC_DURATION, STATIC_DURATION)
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

function XPBar:Refresh()
    local data = SUF.player
    if not data then return end
    if data._xpBar then
        data._xpBar.frame:Hide()
        data._xpBar = nil
    end
    self:Build(data)
    self:Update(data)
end
