-------------------------------------------------------------------------------
--  SphereUnitFrames · Orb.lua
--  Moteur visuel de la sphère joueur.
--  Adapté de SphereNameplates/Orb.lua — frame FIXE (pas nameplate).
--
--  Hiérarchie de frames (root = SUF_Root) :
--    root+1  bgFrame          : fond sphère + bgEffects (galaxy/shimmer bg)
--    root+2  minimapHolder    : conteneur minimap (MinimapCluster reparenté ici)
--    root+3  hpBar            : StatusBar pilote C-side HP (invisible)
--    root+4  hpFxClipFrame    : FX foreground liés à HP (galaxy/shimmer/wave/star)
--    root+4  overlayOrbFrame  : glass, gloss, shadows
--    root+7  emptyShadeFrame  : voile zone vide (suit fillTex:TOP C-side)
--    root+7  powerBar         : barre ressource secondaire
--    root+8  borderOverlayFrame : bordure décorative
--    root+9  overlayFrame     : textes HP / %
--
--  Règles clés (héritées SNP) :
--    • hpEffectMask ancré sur fillTex:TOP (géométrie C-side, pas ratio Lua)
--    • glassTex/glassTex2/glossTex → AddMaskTexture(hpEffectMask)
--    • emptyShadeFrame ancré TOP orbe → BOTTOM fillTex:TOP
--    • fillTex alpha = orb_hp_fill_alpha (défaut 0 = pilote invisible)
--    • AnimTick : un seul OnUpdate externe (30 FPS via accumulateur Core)
-------------------------------------------------------------------------------

local ADDON = "SphereUnitFrames"
local SUF   = _G[ADDON]
if not SUF then return end

SUF.Orb = SUF.Orb or {}
local Orb = SUF.Orb

-- ─── Constantes ──────────────────────────────────────────────────────────────
local NATIVE_RING  = SUF.NATIVE_RING  or "Interface\\Buttons\\UI-AutoCastableOverlay"
local RADIAL_GLOW  = SUF.RADIAL_GLOW  or "Interface\\Cooldown\\ping4"
local WHITE8x8     = SUF.WHITE8x8     or "Interface\\Buttons\\WHITE8X8"
-- Masque circulaire natif WoW (cercle blanc solide sur transparent).
-- Garanti disponible depuis WoW 3.x. Utilisé par les portraits de personnage.
-- NE PAS utiliser ping4 (radial glow = gradient, produit un carré visible).
local CIRCLE_MASK  = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local pi, cos, sin, abs = math.pi, math.cos, math.sin, math.abs

-- ─── CreatePlayer ─────────────────────────────────────────────────────────────
-- Crée la frame sphère joueur unique. Appelée depuis Core:Initialize().
function Orb:CreatePlayer()
    local cfg    = SUF.db
    local size   = cfg.orbSize or 160
    local rootW  = size * 3.0
    local rootH  = size * 2.8

    -- ── Root frame ──────────────────────────────────────────────────────────
    local root = CreateFrame("Frame", "SUFRoot", UIParent)
    root:SetFrameStrata("MEDIUM")
    root:SetSize(rootW, rootH)
    root:SetPoint("BOTTOM", UIParent, "BOTTOM", cfg.posX or 0, cfg.posY or 200)
    root:SetMovable(true)
    root:EnableMouse(false)   -- désactivé par défaut; Interaction.lua l'active
    root:SetIgnoreParentAlpha(true)

    local rootFL = 100
    root:SetFrameLevel(rootFL)

    local data = {
        root      = root,
        unit      = "player",
        orbSize   = size,
        _inCombat = false,
        targetHP  = 1.0,
        displayHP = 1.0,
        _hpDriver = "none",
    }

    -- ── orbFrame (masque circulaire principal) ─────────────────────────────
    local orb = CreateFrame("Frame", "SUFOrbFrame", root)
    orb:SetSize(size, size)
    orb:SetPoint("CENTER", root, "CENTER", 0, size * 0.05)
    orb:SetFrameLevel(rootFL + 2)
    data.orb = orb

    -- Masque circulaire — TempPortraitAlphaMask = cercle blanc solide natif WoW.
    -- IMPÉRATIF : ne JAMAIS utiliser ping4 ici — c'est un radial glow, pas un
    -- disque solide → produit un fond rectangulaire visible (carré noir).
    local mask = orb:CreateMaskTexture()
    mask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(orb)
    data.mask = mask

    -- ── bgFrame (root+1) ───────────────────────────────────────────────────
    local bgFrame = CreateFrame("Frame", nil, root)
    bgFrame:SetAllPoints(orb)
    bgFrame:SetFrameLevel(rootFL + 1)
    data.bgFrame = bgFrame

    -- Fond noir de la sphère
    local bgTex = bgFrame:CreateTexture(nil, "ARTWORK")
    bgTex:SetTexture(WHITE8x8)
    bgTex:SetAllPoints(bgFrame)
    bgTex:SetVertexColor(0.03, 0.03, 0.05, cfg.bgAlpha or 0.75)
    bgTex:AddMaskTexture(mask)
    data.bgTex = bgTex

    -- Fond effets (galaxy bg, shimmer bg — visibles dans zone VIDE intentionnellement)
    local bgEffectsFrame = CreateFrame("Frame", nil, root)
    bgEffectsFrame:SetAllPoints(orb)
    bgEffectsFrame:SetFrameLevel(rootFL + 1)
    data.bgEffectsFrame = bgEffectsFrame

    local bgGalaxy = bgEffectsFrame:CreateTexture(nil, "ARTWORK")
    bgGalaxy:SetTexture(NATIVE_RING)
    bgGalaxy:SetAllPoints(bgEffectsFrame)
    bgGalaxy:SetBlendMode("ADD")
    bgGalaxy:SetVertexColor(0.3, 0.5, 1.0, cfg.orb_galaxy_alpha or 0.15)
    bgGalaxy:AddMaskTexture(mask)
    data.bgGalaxy = bgGalaxy

    local bgShimmer = bgEffectsFrame:CreateTexture(nil, "ARTWORK")
    bgShimmer:SetTexture(NATIVE_RING)
    bgShimmer:SetAllPoints(bgEffectsFrame)
    bgShimmer:SetBlendMode("ADD")
    bgShimmer:SetVertexColor(0.6, 0.4, 1.0, cfg.orb_shimmer_alpha or 0.22)
    bgShimmer:AddMaskTexture(mask)
    bgShimmer:SetTexCoord(0, 1, 0, 1)
    data.bgShimmer = bgShimmer

    -- ── minimapHolder (root+2) — conteneur pour MinimapCluster ────────────
    local minimapHolder = CreateFrame("Frame", "SUFMinimapHolder", root)
    minimapHolder:SetFrameLevel(rootFL + 2)
    minimapHolder:SetAllPoints(orb)
    minimapHolder:Hide()  -- masqué par défaut
    data.minimapHolder = minimapHolder

    -- ── hpBar (root+3) — pilote StatusBar C-side ───────────────────────────
    local hpBar = CreateFrame("StatusBar", "SUFHPBar", root)
    hpBar:SetFrameLevel(rootFL + 3)
    hpBar:SetAllPoints(orb)
    hpBar:SetOrientation("VERTICAL")
    hpBar:SetStatusBarTexture(WHITE8x8)
    hpBar:SetMinMaxValues(0, 100)
    hpBar:SetValue(100)
    hpBar:SetStatusBarColor(1.0, 0.2, 0.2, cfg.orb_hp_fill_alpha or 0.0)
    data.hpBar = hpBar

    -- fillTex : texture pilotée par hpBar (même StatusBar)
    local fillTex = hpBar:GetStatusBarTexture()
    fillTex:AddMaskTexture(mask)
    data.fillTex = fillTex

    -- hpEffectMask : ancré BOTTOM sur orb, TOP sur fillTex:TOP
    -- Suit la géométrie C-side du StatusBar HP, pas un ratio Lua.
    local hpEffectMask = root:CreateMaskTexture()
    hpEffectMask:SetTexture(WHITE8x8, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    hpEffectMask:ClearAllPoints()
    hpEffectMask:SetPoint("BOTTOMLEFT",  orb,     "BOTTOMLEFT",  0,  0)
    hpEffectMask:SetPoint("BOTTOMRIGHT", orb,     "BOTTOMRIGHT", 0,  0)
    hpEffectMask:SetPoint("TOP",         fillTex, "TOP",         0,  0)
    data.hpEffectMask = hpEffectMask

    -- hpFxClipFrame (root+4) : FX foreground masqués par HP
    local hpFxClipFrame = CreateFrame("Frame", nil, root)
    hpFxClipFrame:SetFrameLevel(rootFL + 4)
    hpFxClipFrame:ClearAllPoints()
    hpFxClipFrame:SetPoint("BOTTOMLEFT",  orb,     "BOTTOMLEFT",  0,  0)
    hpFxClipFrame:SetPoint("BOTTOMRIGHT", orb,     "BOTTOMRIGHT", 0,  0)
    hpFxClipFrame:SetPoint("TOP",         fillTex, "TOP",         0,  0)
    -- SetClipsChildren : clip les textures enfants aux limites du frame
    -- (pattern SNP — évite les débordements visuels sur la zone vide)
    if hpFxClipFrame.SetClipsChildren then
        pcall(hpFxClipFrame.SetClipsChildren, hpFxClipFrame, true)
    end
    data.hpFxClipFrame = hpFxClipFrame

    local hpFxClipMask = root:CreateMaskTexture()
    hpFxClipMask:SetTexture(WHITE8x8, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    hpFxClipMask:SetAllPoints(hpFxClipFrame)
    data.hpFxClipMask = hpFxClipMask

    -- Galaxy foreground (suit HP)
    local galaxy = hpFxClipFrame:CreateTexture(nil, "ARTWORK")
    galaxy:SetAllPoints(orb)
    galaxy:SetTexture(NATIVE_RING)
    galaxy:SetBlendMode("ADD")
    galaxy:SetVertexColor(0.3, 0.5, 1.0, cfg.orb_galaxy_alpha or 0.15)
    galaxy:AddMaskTexture(hpEffectMask)
    galaxy:AddMaskTexture(hpFxClipMask)
    galaxy:AddMaskTexture(mask)
    data.galaxy = galaxy

    -- Shimmer foreground
    local shimmer = hpFxClipFrame:CreateTexture(nil, "ARTWORK")
    shimmer:SetAllPoints(orb)
    shimmer:SetTexture(NATIVE_RING)
    shimmer:SetBlendMode("ADD")
    shimmer:SetVertexColor(0.6, 0.4, 1.0, cfg.orb_shimmer_alpha or 0.22)
    shimmer:AddMaskTexture(hpEffectMask)
    shimmer:AddMaskTexture(hpFxClipMask)
    shimmer:AddMaskTexture(mask)
    shimmer:SetTexCoord(0.25, 1.25, 0.25, 1.25)
    data.shimmer = shimmer

    -- Light Star
    local lightStar = hpFxClipFrame:CreateTexture(nil, "ARTWORK")
    lightStar:SetAllPoints(orb)
    local snpStarPath = SUF.SNP_MEDIA and (SUF.SNP_MEDIA .. "light_star.png")
    if snpStarPath and GetFileDataID and GetFileDataID(snpStarPath) ~= 0 then
        lightStar:SetTexture(snpStarPath)
    else
        lightStar:SetTexture(NATIVE_RING)
    end
    lightStar:SetBlendMode("ADD")
    lightStar:SetVertexColor(1.0, 1.0, 1.0, cfg.orb_midnight_star_alpha or 0.60)
    lightStar:AddMaskTexture(hpEffectMask)
    lightStar:AddMaskTexture(hpFxClipMask)
    lightStar:AddMaskTexture(mask)
    lightStar:SetShown(cfg.orb_midnight_star == true)
    data.lightStar    = lightStar
    data._starAngle   = 0

    -- ── overlayOrbFrame (root+4) — glass, gloss, shadows ──────────────────
    local overlayOrbFrame = CreateFrame("Frame", nil, root)
    overlayOrbFrame:SetAllPoints(orb)
    overlayOrbFrame:SetFrameLevel(rootFL + 4)
    data.overlayOrbFrame = overlayOrbFrame

    -- Shadow (BLEND — assombrit, pas de hpEffectMask → contraste zone vide)
    local shadowTex = overlayOrbFrame:CreateTexture(nil, "ARTWORK")
    shadowTex:SetTexture(RADIAL_GLOW)
    shadowTex:SetAllPoints(overlayOrbFrame)
    shadowTex:SetBlendMode("BLEND")
    shadowTex:SetVertexColor(0, 0, 0, cfg.orb_shadow_alpha or 0.35)
    shadowTex:AddMaskTexture(mask)
    data.shadowTex = shadowTex

    -- Specular highlight (ADD, pas de hpEffectMask — point de lumière en haut-gauche)
    local specular = overlayOrbFrame:CreateTexture(nil, "OVERLAY")
    specular:SetSize(size * 0.55, size * 0.55)
    specular:SetPoint("TOPLEFT", overlayOrbFrame, "TOPLEFT", size * 0.05, -size * 0.05)
    specular:SetTexture(RADIAL_GLOW)
    specular:SetBlendMode("ADD")
    specular:SetVertexColor(1.0, 1.0, 1.0, 0.12)
    specular:AddMaskTexture(mask)
    data.specular = specular

    -- Glass 1 (ADD + hpEffectMask → limité zone remplie)
    local glassTex = overlayOrbFrame:CreateTexture(nil, "OVERLAY")
    glassTex:SetAllPoints(overlayOrbFrame)
    glassTex:SetTexture(NATIVE_RING)
    glassTex:SetBlendMode("ADD")
    glassTex:SetVertexColor(1.0, 1.0, 1.0, cfg.orb_glass_alpha or 0.15)
    glassTex:AddMaskTexture(hpEffectMask)
    glassTex:AddMaskTexture(mask)
    data.glassTex = glassTex

    -- Glass 2 (ADD + hpEffectMask)
    local glassTex2 = overlayOrbFrame:CreateTexture(nil, "OVERLAY")
    glassTex2:SetAllPoints(overlayOrbFrame)
    glassTex2:SetTexture(NATIVE_RING)
    glassTex2:SetBlendMode("ADD")
    glassTex2:SetVertexColor(0.8, 0.9, 1.0, (cfg.orb_glass_alpha or 0.15) * 0.6)
    glassTex2:AddMaskTexture(hpEffectMask)
    glassTex2:AddMaskTexture(mask)
    glassTex2:SetTexCoord(1, 0, 0, 1)
    data.glassTex2 = glassTex2

    -- Gloss (ADD + hpEffectMask)
    local glossTex = overlayOrbFrame:CreateTexture(nil, "OVERLAY")
    glossTex:SetAllPoints(overlayOrbFrame)
    glossTex:SetTexture(RADIAL_GLOW)
    glossTex:SetBlendMode("ADD")
    glossTex:SetVertexColor(1.0, 1.0, 1.0, cfg.orb_gloss_alpha or 0.20)
    glossTex:AddMaskTexture(hpEffectMask)
    glossTex:AddMaskTexture(mask)
    data.glossTex = glossTex

    -- ── emptyShadeFrame (root+7) — voile zone vide ─────────────────────────
    -- Ancré TOP sur l'orbe, BOTTOM sur fillTex:TOP. Suit géométrie C-side.
    local emptyShadeFrame = CreateFrame("Frame", nil, root)
    emptyShadeFrame:SetFrameLevel(rootFL + 7)
    emptyShadeFrame:ClearAllPoints()
    emptyShadeFrame:SetPoint("TOPLEFT",     orb,     "TOPLEFT",     0,  0)
    emptyShadeFrame:SetPoint("TOPRIGHT",    orb,     "TOPRIGHT",    0,  0)
    emptyShadeFrame:SetPoint("BOTTOM",      fillTex, "TOP",         0,  0)

    local emptyShadeTex = emptyShadeFrame:CreateTexture(nil, "ARTWORK")
    emptyShadeTex:SetAllPoints(emptyShadeFrame)
    emptyShadeTex:SetTexture(WHITE8x8)
    emptyShadeTex:SetBlendMode("BLEND")
    emptyShadeTex:SetVertexColor(
        cfg.orb_empty_shadeR or 0,
        cfg.orb_empty_shadeG or 0,
        cfg.orb_empty_shadeB or 0,
        cfg.orb_empty_shade_enabled and (cfg.orb_empty_shade_alpha or 0.45) or 0.0)
    emptyShadeTex:AddMaskTexture(mask)
    data.emptyShadeFrame  = emptyShadeFrame
    data.emptyShadeTex    = emptyShadeTex

    -- ── borderOverlayFrame (root+8) — bordure décorative ──────────────────
    local borderOverlayFrame = CreateFrame("Frame", nil, root)
    borderOverlayFrame:SetAllPoints(orb)
    borderOverlayFrame:SetFrameLevel(rootFL + 8)
    data.borderOverlayFrame = borderOverlayFrame

    local borderTex = borderOverlayFrame:CreateTexture(nil, "ARTWORK")
    borderTex:SetAllPoints(borderOverlayFrame)
    borderTex:SetBlendMode("ADD")
    -- NE PAS AddMaskTexture(mask) ici : la bordure est AUTOUR de l'orbe,
    -- pas dedans. Masquer = la clipper au cercle = invisible à l'extérieur.
    borderTex:SetAlpha(0)  -- appliqué dans SoftUpdate / ApplyBorderStyle
    data.borderTex = borderTex

    -- ── overlayFrame (root+9) — textes HP ─────────────────────────────────
    local overlayFrame = CreateFrame("Frame", nil, root)
    overlayFrame:SetAllPoints(orb)
    overlayFrame:SetFrameLevel(rootFL + 9)
    data.overlayFrame = overlayFrame

    -- Texte HP principal (pourcentage)
    local hpText = overlayFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hpText:SetPoint("CENTER", overlayFrame, "CENTER", 0, size * 0.0)
    hpText:SetFont(cfg.hp_font or "Fonts\\FRIZQT__.TTF", cfg.hp_font_size or 22, "OUTLINE")
    hpText:SetTextColor(1, 1, 1, 1)
    hpText:SetText("100%")
    data.hpText = hpText

    -- Texte HP secondaire (valeur absolue)
    local hpSubText = overlayFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hpSubText:SetPoint("TOP", hpText, "BOTTOM", 0, -2)
    hpSubText:SetFont(cfg.hp_font or "Fonts\\FRIZQT__.TTF", math.max(9, (cfg.hp_font_size or 22) - 8), "OUTLINE")
    hpSubText:SetTextColor(0.8, 0.8, 0.8, 1)
    hpSubText:SetShown(cfg.show_hp_absolute == true)
    data.hpSubText = hpSubText

    -- ── Stocker et exposer data ───────────────────────────────────────────
    data.rootFL = rootFL
    SUF.player  = data

    -- ── orb_empty_clear : applique hpEffectMask aux couches de fond ───────
    if cfg.orb_empty_clear_enabled then
        bgTex:AddMaskTexture(hpEffectMask)
        bgGalaxy:AddMaskTexture(hpEffectMask)
        bgShimmer:AddMaskTexture(hpEffectMask)
    end

    -- ── Appliquer la config initiale ──────────────────────────────────────
    Orb:SoftUpdate(data)

    return data
end

-- ─── SoftUpdate ───────────────────────────────────────────────────────────────
-- Met à jour les options visuelles sans recréer les frames.
function Orb:SoftUpdate(data)
    if not data then data = SUF.player end
    if not data then return end
    local cfg = SUF.db

    -- Fond
    data.bgTex:SetVertexColor(0.03, 0.03, 0.05, cfg.bgAlpha or 0.75)

    -- Shadow
    data.shadowTex:SetVertexColor(0, 0, 0, cfg.orb_shadow_alpha or 0.35)

    -- Glass / gloss
    local ga = cfg.orb_glass_alpha or 0.15
    data.glassTex:SetVertexColor(1.0, 1.0, 1.0, ga)
    data.glassTex2:SetVertexColor(0.8, 0.9, 1.0, ga * 0.6)
    data.glossTex:SetVertexColor(1.0, 1.0, 1.0, cfg.orb_gloss_alpha or 0.20)

    -- HP fill alpha
    if data.hpBar then
        local r, g, b = SUF:ResolveFillColor(cfg, data.displayHP or 1.0)
        data.hpBar:SetStatusBarColor(r, g, b, cfg.orb_hp_fill_alpha or 0.0)
    end

    -- Effets orbe : couleur + alpha entièrement gérés par UpdateFill en fin de fonction.
    -- NE PAS appeler SetAlpha() séparément ici : SetVertexColor(r,g,b,a) dans UpdateFill
    -- écrase l'alpha indépendamment — un SetAlpha() en amont créerait une double couche.
    data.lightStar:SetShown(cfg.orb_midnight_star == true)
    if cfg.orb_midnight_star then
        data.lightStar:SetVertexColor(1, 1, 1, cfg.orb_midnight_star_alpha or 0.6)
    end

    -- Zone vide
    if data.emptyShadeTex then
        local a = (cfg.orb_empty_shade_enabled) and (cfg.orb_empty_shade_alpha or 0.45) or 0.0
        data.emptyShadeTex:SetVertexColor(
            cfg.orb_empty_shadeR or 0,
            cfg.orb_empty_shadeG or 0,
            cfg.orb_empty_shadeB or 0, a)
    end

    -- Bordure
    Orb:ApplyBorderStyle(data)

    -- Texte HP
    if data.hpText then
        data.hpText:SetFont(cfg.hp_font or "Fonts\\FRIZQT__.TTF", cfg.hp_font_size or 22, "OUTLINE")
        data.hpText:SetShown(cfg.show_hp_percent ~= false)
    end
    if data.hpSubText then
        data.hpSubText:SetShown(cfg.show_hp_absolute == true)
    end

    -- Position
    data.root:ClearAllPoints()
    data.root:SetPoint("BOTTOM", UIParent, "BOTTOM", cfg.posX or 0, cfg.posY or 200)

    -- Minimap scale update
    if SUF.Minimap and SUF.Minimap._integrated then
        pcall(SUF.Minimap.UpdateScale, SUF.Minimap)
    end

    -- Appliquer la couleur de fill (classe / progressive / fixed) aux FX de l'orbe.
    -- Doit être en dernier : les alphas sont déjà positionnés ci-dessus.
    -- Invalider le cache pour forcer le re-rendu même si la couleur n'a pas changé.
    data._lastFillR = nil
    Orb:UpdateFill(data, data.displayHP or 1.0)
end

-- ─── ApplyBorderStyle ────────────────────────────────────────────────────────
function Orb:ApplyBorderStyle(data)
    if not data then return end
    local cfg   = SUF.db
    local info  = SUF:GetBorderStyleInfo(cfg.borderStyle)
    local tex   = data.borderTex
    if not tex then return end

    if not info or not info.path then
        -- Style "solide" : anneau lumineux ADD autour de l'orbe.
        -- NATIVE_RING = ring shape (pas un disque) → naturellement circulaire.
        -- Taille > orbSize → visible en dehors du cercle.
        -- Couleur mise à jour par UpdateFill() pour suivre la couleur de classe.
        tex:SetTexture(NATIVE_RING)
        tex:SetBlendMode("ADD")
        tex:SetVertexColor(cfg.borderR or 1, cfg.borderG or 0.8, cfg.borderB or 0, cfg.borderA or 1)
        tex:SetAlpha(cfg.borderA or 1)
        local sz = (cfg.orbSize or 160) * (cfg.border_size_ratio or 1.5)
        tex:ClearAllPoints()
        tex:SetSize(sz, sz)
        tex:SetPoint("CENTER", data.orb, "CENTER", 0, 0)
        return
    end

    -- Vérifier que le fichier asset existe (SNP peut ne pas être installé)
    tex:SetTexture(info.path)
    if info.uv then
        tex:SetTexCoord(info.uv[1], info.uv[2], info.uv[3], info.uv[4])
    else
        tex:SetTexCoord(0, 1, 0, 1)
    end
    tex:SetBlendMode(info.blend or "ADD")
    if info.tint ~= false then
        tex:SetVertexColor(cfg.borderR or 1, cfg.borderG or 0.8, cfg.borderB or 0, cfg.borderA or 1)
    else
        tex:SetVertexColor(1, 1, 1, cfg.borderA or 1)
    end
    tex:SetAlpha(cfg.borderA or 1)
    local r = (cfg.border_size_ratio or 1.5)
    local sz = (cfg.orbSize or 160) * r
    tex:SetSize(sz, sz)
    tex:SetPoint("CENTER", data.orb, "CENTER", 0, 0)
end

-- ─── UpdateFill ──────────────────────────────────────────────────────────────
-- Met à jour la couleur de remplissage de l'orbe.
-- ratio : 0..1 (peut être nil → utilise displayHP)
function Orb:UpdateFill(data, ratio)
    if not data then return end
    local cfg = SUF.db
    ratio = ratio or data.displayHP or data.targetHP or 1.0

    local r, g, b = SUF:ResolveFillColor(cfg, ratio)

    -- Court-circuit si la couleur n'a pas changé
    local dr = math.abs((data._lastFillR or -1) - r)
    local dg = math.abs((data._lastFillG or -1) - g)
    local db = math.abs((data._lastFillB or -1) - b)
    if dr < 0.005 and dg < 0.005 and db < 0.005 then return end

    data._lastFillR = r
    data._lastFillG = g
    data._lastFillB = b

    -- Appliquer aux FX foreground
    local ga = cfg.orb_galaxy_enabled ~= false and (cfg.orb_galaxy_alpha or 0.15) or 0
    local sa = cfg.orb_shimmer_enabled ~= false and (cfg.orb_shimmer_alpha or 0.22) or 0

    if data.galaxy  then data.galaxy:SetVertexColor(r, g, b, ga) end
    if data.shimmer then data.shimmer:SetVertexColor(
        r * 0.6 + g * 0.4, g * 0.4 + b * 0.6, b, sa) end

    -- Light star couleur
    if data.lightStar and cfg.orb_midnight_star and cfg.orb_midnight_star_class_color then
        data.lightStar:SetVertexColor(r, g, b, cfg.orb_midnight_star_alpha or 0.6)
    end

    -- HP fill visible
    if data.hpBar then
        data.hpBar:SetStatusBarColor(r, g, b, cfg.orb_hp_fill_alpha or 0.88)
    end

    -- Bordure "solide" suit la couleur de classe/fill
    if data.borderTex then
        local bStyle = cfg.borderStyle or "solide"
        local bInfo  = SUF.BORDER_STYLES[bStyle]
        if not bInfo or not bInfo.path then
            -- Style solide : teinte de la bordure = couleur de classe
            data.borderTex:SetVertexColor(r, g, b, cfg.borderA or 1.0)
        end
    end
end

-- ─── UpdateHPText ────────────────────────────────────────────────────────────
function Orb:UpdateHPText(data)
    if not data then return end
    local cfg   = SUF.db
    local ratio = data.displayHP or data.targetHP or 1.0
    local r, g, b = SUF:GetHPTextColor(cfg, ratio)

    if data.hpText and cfg.show_hp_percent ~= false then
        local pct = math.floor(ratio * 100 + 0.5)
        data.hpText:SetText(pct .. "%")
        data.hpText:SetTextColor(r, g, b, 1)
    end

    if data.hpSubText and cfg.show_hp_absolute then
        -- Valeur absolue via escape C-side
        pcall(function()
            local ok, h = pcall(UnitHealth, "player")
            local ok2, m = pcall(UnitHealthMax, "player")
            if ok and ok2 and h and m then
                local hs = SUF:UntaintNum(h)
                local ms = SUF:UntaintNum(m)
                if hs and ms then
                    data.hpSubText:SetText(AbbreviateNumbers(hs) .. " / " .. AbbreviateNumbers(ms))
                end
            end
        end)
    end
end

-- ─── RebuildPlayer ───────────────────────────────────────────────────────────
-- Détruit et recrée la frame joueur (utilisé quand orbSize change).
function Orb:RebuildPlayer()
    local data = SUF.player
    if data and data.root then
        -- Sauvegarder état minimap
        if SUF.Minimap and SUF.Minimap._integrated then
            pcall(SUF.Minimap.Release, SUF.Minimap)
        end
        -- Démanteler modules
        if SUF.CastBar then pcall(SUF.CastBar.Reset,    SUF.CastBar, data) end
        if SUF.Auras   then pcall(SUF.Auras.ReleaseAll, SUF.Auras,   data) end
        data.root:Hide()
        -- Note : on ne delete pas (pas de garbage GC explicite en WoW)
        -- On masque et on recrée par-dessus
    end
    Orb:CreatePlayer()
    local newData = SUF.player
    if newData then
        -- Réinitialiser les modules
        if SUF.CastBar     then pcall(SUF.CastBar.Init,     SUF.CastBar,     newData) end
        if SUF.Auras       then
            pcall(SUF.Auras.Init,        SUF.Auras,       newData)
            pcall(SUF.Auras.PrewarmPool, SUF.Auras,       24)
        end
        if SUF.Power       then pcall(SUF.Power.Init,       SUF.Power,       newData) end
        if SUF.Interaction then pcall(SUF.Interaction.Init, SUF.Interaction, newData) end
        if SUF.ActionBars  then pcall(SUF.ActionBars.Rebuild, SUF.ActionBars) end
    end
end

-- ─── AnimTick ─────────────────────────────────────────────────────────────────
-- Appelé par Core.lua à ~30 FPS via accumulateur.
function Orb:AnimTick(data, dt)
    if not data then return end
    local now = GetTime()
    local cfg = SUF.db

    -- Rotation light_star
    if data.lightStar and data.lightStar:IsShown() and cfg.orb_midnight_star then
        local dir   = (cfg.orb_midnight_star_dir == -1) and -1 or 1
        local speed = (cfg.orb_midnight_star_speed or 1.0) * dir
        data._starAngle = (data._starAngle or 0) + dt * speed * 0.5
        data.lightStar:SetRotation(data._starAngle)
        -- Scale pulse doux
        local s = 1.0 + 0.04 * math.sin(now * 1.8)
        data.lightStar:SetScale(s * (cfg.orb_midnight_star_scale or 1.0))
    end

    -- Shimmer offset animé
    if data.shimmer and cfg.orb_shimmer_enabled ~= false then
        local t = now * 0.15
        data.shimmer:SetTexCoord(
            t % 1, (t + 1) % 1 + 1,
            (t * 0.7) % 1, (t * 0.7) % 1 + 1)
    end

    -- Galaxy rotation douce
    if data.bgGalaxy and cfg.orb_galaxy_enabled ~= false then
        local angle = now * 0.08
        data.bgGalaxy:SetRotation(angle)
        data.galaxy:SetRotation(angle)
    end
end

-- ─── UpdateCC ────────────────────────────────────────────────────────────────
-- Effet visuel quand le joueur est CC (futur).
function Orb:UpdateCC(data, ccActive, ccColor)
    if not data then return end
    -- TODO Phase 4 : border pulse rouge quand stuné/root/etc.
end
