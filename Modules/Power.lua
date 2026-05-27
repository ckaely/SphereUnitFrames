-------------------------------------------------------------------------------
--  SphereUnitFrames · Power.lua
--  Barre de ressource secondaire (mana / rage / énergie / runes…)
--  Power:Init(data) crée data.powerBar sous l'orbe.
--  Power:Update(data) rafraîchit valeur + couleur.
-------------------------------------------------------------------------------

local ADDON = "SphereUnitFrames"
local SUF   = _G[ADDON]
if not SUF then return end

SUF.Power = SUF.Power or {}
local Power = SUF.Power

-- Couleurs par Enum.PowerType
local POWER_COLORS = {
    [0]  = {r=0.00, g=0.44, b=0.87},  -- Mana
    [1]  = {r=0.85, g=0.12, b=0.12},  -- Rage
    [2]  = {r=1.00, g=0.55, b=0.15},  -- Focus
    [3]  = {r=1.00, g=0.90, b=0.00},  -- Energy
    [4]  = {r=1.00, g=0.22, b=0.00},  -- Combo Points
    [5]  = {r=0.55, g=0.45, b=0.85},  -- Runes
    [6]  = {r=0.75, g=0.00, b=0.80},  -- Runic Power
    [7]  = {r=0.52, g=0.20, b=0.78},  -- Soul Shards
    [8]  = {r=0.22, g=0.68, b=1.00},  -- Lunar Power (Balance)
    [9]  = {r=0.95, g=0.88, b=0.48},  -- Holy Power
    [11] = {r=0.38, g=0.80, b=0.88},  -- Maelstrom
    [12] = {r=0.10, g=0.95, b=0.80},  -- Chi
    [13] = {r=0.40, g=0.00, b=0.50},  -- Insanity
    [17] = {r=0.55, g=0.50, b=0.95},  -- Arcane Charges
    [18] = {r=0.90, g=0.40, b=0.05},  -- Fury
    [19] = {r=0.82, g=0.50, b=0.90},  -- Pain
    [20] = {r=0.22, g=0.78, b=0.95},  -- Essence
}

local DEFAULT_COLOR = {r=0.50, g=0.50, b=0.70}

local function _powerColor(pt)
    return POWER_COLORS[pt] or DEFAULT_COLOR
end

-- ─── Init ────────────────────────────────────────────────────────────────────
-- Appelé depuis Initialize() après Orb:CreatePlayer().
function Power:Init(data)
    if not data or not data.root then return end
    if data.powerBar then return end  -- déjà initialisé

    local cfg  = SUF.db
    local root = data.root
    local rootFL = root:GetFrameLevel() or 100
    local size = (cfg and cfg.orbSize) or 160
    local height = (cfg and cfg.power_height) or 7
    local offY   = (cfg and cfg.power_offset_y) or -8

    -- StatusBar horizontal sous l'orbe
    local bar = CreateFrame("StatusBar", "SUFPowerBar", root)
    bar:SetSize(size, height)
    bar:SetPoint("TOP", root, "BOTTOM", 0, offY)
    bar:SetFrameLevel(rootFL + 6)
    bar:SetStatusBarTexture(SUF.WHITE8x8 or "Interface\\Buttons\\WHITE8X8")
    bar:SetMinMaxValues(0, 100)
    bar:SetValue(100)

    -- Fond
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(bar)
    bg:SetTexture(SUF.WHITE8x8 or "Interface\\Buttons\\WHITE8X8")
    bg:SetVertexColor(0.05, 0.05, 0.07, 0.80)

    -- Bordure fine
    local border = bar:CreateTexture(nil, "OVERLAY")
    border:SetPoint("TOPLEFT",     bar, "TOPLEFT",     -1,  1)
    border:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT",  1, -1)
    border:SetTexture(SUF.WHITE8x8 or "Interface\\Buttons\\WHITE8X8")
    border:SetVertexColor(0, 0, 0, 0.50)

    data.powerBar = bar
    bar:SetAlpha((cfg and cfg.power_alpha) or 0.85)
    bar:Show()
end

-- ─── Update ───────────────────────────────────────────────────────────────────
function Power:Update(data)
    if not data or not data.powerBar then return end
    local cfg = SUF.db
    if not cfg then return end

    if cfg.power_enabled == false then
        data.powerBar:Hide()
        return
    end
    data.powerBar:Show()
    data.powerBar:SetAlpha(cfg.power_alpha or 0.85)

    -- Lire le type de puissance
    local powerType = 0
    pcall(function()
        local _, _, id = UnitPowerType("player")
        local clean = SUF:UntaintNum(id)
        if clean then powerType = clean end
    end)
    if powerType == 0 then
        pcall(function()
            local pt = select(1, UnitPowerType("player"))
            local clean = SUF:UntaintNum(pt)
            if clean then powerType = clean end
        end)
    end

    -- Lire les valeurs
    local cur, max = 0, 1
    pcall(function()
        local c = UnitPower("player", powerType)
        local m = UnitPowerMax("player", powerType)
        cur = SUF:UntaintNum(c) or 0
        max = SUF:UntaintNum(m) or 1
    end)

    if max <= 0 then
        data.powerBar:Hide()
        return
    end

    data.powerBar:SetMinMaxValues(0, max)
    data.powerBar:SetValue(cur)

    -- Couleur selon le type
    local c = _powerColor(powerType)
    local tex = data.powerBar:GetStatusBarTexture()
    if tex then tex:SetVertexColor(c.r, c.g, c.b, 1) end

    -- Ajuster la taille si l'orbe a changé de taille
    local size = (cfg.orbSize or 160)
    local h    = (cfg.power_height or 7)
    local w, _ = data.powerBar:GetSize()
    if math.abs(w - size) > 1 then
        data.powerBar:SetSize(size, h)
        data.powerBar:ClearAllPoints()
        data.powerBar:SetPoint("TOP", data.root, "BOTTOM", 0, cfg.power_offset_y or -8)
    end
end
