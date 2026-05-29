-------------------------------------------------------------------------------
--  SphereUnitFrames · Config.lua
--  Namespace global SUF, paths médias, helpers taint, defaults AceDB.
--
--  RÈGLES TAINT WoW MIDNIGHT (héritées de SphereNameplates) :
--    • UnitHealth/Max/Percent → secret tainted → passer par C-API
--    • UnitGUID → secret string → pcall avant toute clé de table
--    • isFromPlayerOrPlayerPet → boolean tainté → filtrer |PLAYER C-side
--    • Pour le joueur, valeurs MOINS taintées qu'ennemies, mais on garde
--      les patterns défensifs par prudence.
--
--  ESCAPE HP FIABLE :
--    scratchFS:SetFormattedText("%.10f", tainted_pct)
--    local s = scratchFS:GetText()
--    local ratio = tonumber(s) / 100
-------------------------------------------------------------------------------

local ADDON = "SphereUnitFrames"
local SUF   = {}
_G[ADDON]   = SUF

SUF.version  = "0.1.0"
SUF.InCombat = false

-- ─── Chemins médias ──────────────────────────────────────────────────────────
SUF.MEDIA  = "Interface\\AddOns\\SphereUnitFrames\\media\\"
-- Assets auras/bordures partagés depuis SphereNameplates (si installé)
SUF.SNP_ASSETS  = "Interface\\AddOns\\SphereNameplates\\media2\\Assets\\"
SUF.SNP_MEDIA   = "Interface\\AddOns\\SphereNameplates\\media\\"

-- ─── Textures natives Blizzard (toujours disponibles) ────────────────────────
SUF.NATIVE_RING  = "Interface\\Buttons\\UI-AutoCastableOverlay"
SUF.RADIAL_GLOW  = "Interface\\Cooldown\\ping4"
SUF.WHITE8x8     = "Interface\\Buttons\\WHITE8X8"

-- ─── Styles de bordure ───────────────────────────────────────────────────────
-- Partagés visuellement avec SNP si les assets sont présents.
-- SUF.GetBorderStyleInfo() vérifie l'existence avant usage.
SUF.BORDER_STYLES = {
    solide       = { name="Solide",      path=nil },
    wow_horde    = { name="Horde",       path=SUF.SNP_MEDIA.."wow_style.png",              blend="BLEND", tint=false, uv={0,       0.3333, 0,   0.5} },
    wow_alliance = { name="Alliance",    path=SUF.SNP_MEDIA.."wow_style.png",              blend="BLEND", tint=false, uv={0.3333,  0.6667, 0,   0.5} },
    wow_evil     = { name="Evil",        path=SUF.SNP_MEDIA.."wow_style.png",              blend="BLEND", tint=false, uv={0.6667,  1,      0,   0.5} },
    wow_beast    = { name="Beast",       path=SUF.SNP_MEDIA.."wow_style.png",              blend="BLEND", tint=false, uv={0,       0.3333, 0.5, 1  } },
    wow_stone    = { name="Simple Stone",path=SUF.SNP_MEDIA.."wow_style.png",              blend="BLEND", tint=false, uv={0.3333,  0.6667, 0.5, 1  } },
    wow_gold     = { name="Simple Gold", path=SUF.SNP_MEDIA.."wow_style.png",              blend="BLEND", tint=false, uv={0.6667,  1,      0.5, 1  } },
    ns_horde     = { name="Horde Fer",   path=SUF.SNP_MEDIA.."cadre_sphere_new_style.png", blend="BLEND", tint=false, uv={0,       0.3333, 0,   0.5} },
    ns_alliance  = { name="Alliance Or", path=SUF.SNP_MEDIA.."cadre_sphere_new_style.png", blend="BLEND", tint=false, uv={0.3333,  0.6667, 0,   0.5} },
    ns_gold_ring = { name="Anneau Or",   path=SUF.SNP_MEDIA.."cadre_sphere_new_style.png", blend="BLEND", tint=false, uv={0.6667,  1,      0.5, 1  } },
}

function SUF:GetBorderStyleInfo(style)
    local s = SUF.BORDER_STYLES[style]
    if s then return s end
    return SUF.BORDER_STYLES["solide"]
end

function SUF:GetBorderTexturePath(style)
    local s = self:GetBorderStyleInfo(style)
    return s and s.path or nil
end

-- ─── AceDB Defaults ──────────────────────────────────────────────────────────
SUF.defaults = {
    profile = {
        -- Position & scale
        posX             = 0,
        posY             = 200,
        scale            = 1.0,
        locked           = false,

        -- Sphère dimensionnelle
        orbSize          = 160,

        -- Couleur fill
        fill_color_mode  = "class",   -- "class" | "fixed" | "progressive"
        fill_r           = 1.0, fill_g = 0.2, fill_b = 0.2,

        -- Fonds / ombres
        bgAlpha               = 0.75,
        orb_shadow_alpha      = 0.35,
        orb_shadow2_enabled   = false,
        orb_shadow2_alpha     = 0.0,
        orb_gloss_alpha       = 0.20,
        orb_glass_alpha       = 0.15,

        -- HP fill visible (0.88 = sphère colorée visible)
        orb_hp_fill_alpha     = 0.88,

        -- Zone vide
        orb_empty_clear_enabled = true,
        orb_empty_shade_enabled = false,
        orb_empty_shadeR        = 0.0,
        orb_empty_shadeG        = 0.0,
        orb_empty_shadeB        = 0.0,
        orb_empty_shade_alpha   = 0.45,

        -- Effets orbe
        orb_galaxy_enabled      = true,
        orb_galaxy_alpha        = 0.15,
        orb_shimmer_enabled     = true,
        orb_shimmer_alpha       = 0.22,
        orb_wave_enabled        = false,
        orb_wave_alpha          = 0.30,
        orb_midnight_star       = false,
        orb_midnight_star_alpha = 0.60,
        orb_midnight_star_scale = 1.0,
        orb_midnight_star_speed = 1.0,
        orb_midnight_star_dir   = 1,
        orb_midnight_star_class_color = false,

        -- Bordure décorative
        borderStyle = "solide",
        borderR = 1.0, borderG = 0.8, borderB = 0.0, borderA = 1.0,
        border_size_ratio = 1.5,

        -- Textes HP
        show_hp_percent  = true,
        show_hp_absolute = true,
        hp_font          = "Fonts\\FRIZQT__.TTF",
        hp_font_size     = 22,
        hp_font_r        = 1.0, hp_font_g = 1.0, hp_font_b = 1.0,

        -- Couleurs progressives
        fill_prog_high_r = 0.2,  fill_prog_high_g = 0.9,  fill_prog_high_b = 0.3,
        fill_prog_mid_r  = 1.0,  fill_prog_mid_g  = 0.8,  fill_prog_mid_b  = 0.0,
        fill_prog_low_r  = 1.0,  fill_prog_low_g  = 0.4,  fill_prog_low_b  = 0.0,
        fill_prog_crit_r = 0.9,  fill_prog_crit_g = 0.1,  fill_prog_crit_b = 0.1,

        -- CastBar
        castbar_enabled      = true,
        castbar_style        = "circular",  -- "circular" | "segments" | "classic"
        castbar_v8_segments  = false,
        castbar_v8_count     = 16,
        castbar_show_icon    = true,
        castbar_show_time    = true,
        castbar_time_font_size = 12,
        castbar_time_offset_y  = -10,
        castbar_color_cast_r   = 1.0, castbar_color_cast_g   = 0.7, castbar_color_cast_b   = 0.0,
        castbar_color_channel_r= 0.3, castbar_color_channel_g= 0.7, castbar_color_channel_b= 1.0,
        castbar_color_immune_r = 0.6, castbar_color_immune_g = 0.6, castbar_color_immune_b = 0.6,

        -- Auras
        auras_enabled        = true,
        auras_mode           = "ring",   -- "ring" | "arc" | "segments"
        auras_size           = 28,
        auras_offset_radius  = 1.35,
        auras_max_buffs      = 8,
        auras_max_debuffs    = 8,
        auras_buff_mine_only    = false,
        auras_debuff_mine_only  = false,
        auras_show_timers    = true,
        -- Direction des arcs : "top" | "bottom" | "left" | "right"
        auras_buff_arc_dir   = "top",
        auras_debuff_arc_dir = "bottom",
        auras_arc_spread     = 160,  -- degrés de spread max (tous arcs)

        -- Power / ressource secondaire
        power_enabled        = true,
        power_height         = 7,
        power_alpha          = 0.85,
        power_offset_y       = -8,

        -- Minimap
        minimap_enabled          = true,
        minimap_mode             = "integrated", -- "disabled" | "adjacent" | "integrated"
        minimap_hp_threshold     = 0,           -- 0 = toujours visible hors combat
        minimap_transition_speed = 0.3,
        minimap_hide_buttons     = true,

        -- Barres d'action (ailes triangulaires)
        actionbars_enabled       = true,
        actionbar_left_bar       = 2,
        actionbar_left_start     = 1,
        actionbar_left_count     = 12,
        actionbar_right_bar      = 3,
        actionbar_right_start    = 1,
        actionbar_right_count    = 12,
        actionbar_tri_size       = 44,
        actionbar_glow_procs     = true,
        actionbar_range_check    = true,

        -- Modules ON/OFF (isolation FPS)
        modules_orbanim_enabled  = true,
        modules_castbar_enabled  = true,
        modules_auras_enabled    = true,
        modules_hplerp_enabled   = true,
        modules_power_enabled    = true,

        -- Logs
        logs_enabled      = false,
        logs_max_entries  = 200,
        logs_level_info   = true,
        logs_level_warn   = true,
        logs_level_error  = true,
        logs_level_perf   = false,
        logs_level_debug  = false,

        -- Performance Monitor
        perf_enabled      = false,
        perf_seuil_ms     = 5.0,
        perf_panel_visible= false,
    }
}

-- ─── Scratch frames pour escape de valeurs taintées ──────────────────────────
-- Créées une fois, jamais détruites. Pattern validé SNP.
local _scratchFS = nil
local _scratchBar = nil

local function _ensureScratch()
    if not _scratchFS then
        local f = CreateFrame("Frame", "SUF_ScratchFrame", UIParent)
        f:Hide()
        _scratchFS = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    end
    if not _scratchBar then
        _scratchBar = CreateFrame("StatusBar", "SUF_ScratchBar", UIParent)
        _scratchBar:Hide()
        _scratchBar:SetMinMaxValues(0, 1)
    end
end

-- Escape d'un nombre potentiellement tainté → float propre ou nil
function SUF:UntaintNum(v)
    if v == nil then return nil end
    _ensureScratch()
    local ok, s = pcall(function()
        _scratchFS:SetFormattedText("%.10f", v)
        return _scratchFS:GetText()
    end)
    if not ok then return nil end
    return tonumber(s)
end

-- Ratio HP joueur (0..1) — escape C-side, toujours safe
function SUF:GetHPRatio()
    _ensureScratch()
    local ok, result = pcall(function()
        local ok2, pct = pcall(function()
            return UnitHealthPercent("player", false, CurveConstants and CurveConstants.ScaleTo100 or nil)
        end)
        if ok2 and pct then
            _scratchFS:SetFormattedText("%.10f", pct)
            local s = _scratchFS:GetText()
            local n = tonumber(s)
            if n then return n / 100 end
        end
        -- Fallback historique
        _scratchBar:SetMinMaxValues(0, UnitHealthMax("player"))
        _scratchBar:SetValue(UnitHealth("player"))
        local cur = _scratchBar:GetValue()
        local mn, mx = _scratchBar:GetMinMaxValues()
        if mx and mx > 0 and cur then return cur / mx end
        return 1.0
    end)
    return (ok and result) or 1.0
end

-- ─── SafeUnit wrappers ───────────────────────────────────────────────────────
-- Pour le joueur, moins risqués que nameplates ennemies.
-- Conservés pour cohérence et résistance aux changements Midnight.

function SUF:SafeUnitIsPlayer(unit)
    local ok, v = pcall(UnitIsPlayer, unit or "player")
    return ok and v == true
end

function SUF:SafeUnitIsDead(unit)
    local ok, v = pcall(UnitIsDead, unit or "player")
    return ok and v == true
end

function SUF:SafeUnitExists(unit)
    local ok, v = pcall(UnitExists, unit or "player")
    return ok and v == true
end

function SUF:SafeUnitGUID(unit)
    local ok, g = pcall(UnitGUID, unit or "player")
    if ok and type(g) == "string" and g ~= "" then return g end
    return nil
end

function SUF:SafeUnitAffectingCombat(unit)
    local ok, v = pcall(UnitAffectingCombat, unit or "player")
    if not ok then return false end
    local okB, b = pcall(function() return v == true end)
    return okB and b
end

-- ─── ResolveFillColor ─────────────────────────────────────────────────────────
-- Retourne r, g, b selon fill_color_mode + ratio HP.
-- Ne lit PAS UnitHealth directement — utilise le ratio déjà résolu.
function SUF:ResolveFillColor(cfg, ratio)
    ratio = ratio or 1.0
    local mode = cfg.fill_color_mode or "class"

    if mode == "class" then
        local ok, _, englishClass = pcall(UnitClass, "player")
        if ok and englishClass then
            local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[englishClass]
            if cc then return cc.r, cc.g, cc.b end
        end
        return 1.0, 1.0, 1.0

    elseif mode == "progressive" then
        if ratio > 0.75 then
            return cfg.fill_prog_high_r, cfg.fill_prog_high_g, cfg.fill_prog_high_b
        elseif ratio > 0.50 then
            return cfg.fill_prog_mid_r,  cfg.fill_prog_mid_g,  cfg.fill_prog_mid_b
        elseif ratio > 0.25 then
            return cfg.fill_prog_low_r,  cfg.fill_prog_low_g,  cfg.fill_prog_low_b
        else
            return cfg.fill_prog_crit_r, cfg.fill_prog_crit_g, cfg.fill_prog_crit_b
        end

    else -- "fixed"
        return cfg.fill_r or 1.0, cfg.fill_g or 0.2, cfg.fill_b or 0.2
    end
end

-- ─── ClampPos ────────────────────────────────────────────────────────────────
-- Clamp posX/posY pour que la root frame reste entièrement sur l'écran.
-- Coordonnées pour SetPoint("BOTTOM", UIParent, "BOTTOM", posX, posY) :
--   posX = offset horizontal depuis le centre de UIParent (peut être négatif)
--   posY = distance du bas de la frame depuis le bas de UIParent (≥ 0)
-- Doit correspondre aux dimensions calculées dans Orb.lua:CreatePlayer.
function SUF:ClampPos(x, y)
    if not UIParent then return x, y end
    local sw    = UIParent:GetWidth()  or 1024
    local sh    = UIParent:GetHeight() or 768
    local sz    = (SUF.db and SUF.db.orbSize) or 160
    local rootW = sz * 3.0        -- cohérent avec Orb.lua rootW = size * 3.0
    local rootH = sz * 2.8        -- cohérent avec Orb.lua rootH = size * 2.8
    local halfW = rootW * 0.5 + 10
    -- posX : frame doit rester horizontalement dans l'écran
    x = math.max(-(sw * 0.5 - halfW), math.min(sw * 0.5 - halfW, x))
    -- posY : bas de la frame dans [10 .. sh - rootH - 10]
    y = math.max(10, math.min(sh - rootH - 10, y))
    return x, y
end

-- ─── GetHPTextColor ──────────────────────────────────────────────────────────
-- Couleur du texte HP selon ratio (pour les textes de l'orbe).
function SUF:GetHPTextColor(cfg, ratio)
    ratio = ratio or 1.0
    if ratio > 0.75 then return 1.0, 1.0, 1.0 end
    if ratio > 0.50 then return 1.0, 0.9, 0.5 end
    if ratio > 0.25 then return 1.0, 0.5, 0.1 end
    return 1.0, 0.2, 0.2
end

-- ─── Print helpers ───────────────────────────────────────────────────────────
function SUF:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cFF88CCFFSphereUnitFrames|r: " .. tostring(msg))
end

function SUF:Debug(msg)
    if SUF.db and SUF.db.logs_enabled then
        if SUF.Log then SUF.Log:Debug("Core", msg) end
    end
end

-- ─── Donnée joueur globale ────────────────────────────────────────────────────
-- Créée dans Orb.lua:CreatePlayer(), référencée depuis tous les modules.
SUF.player = nil
