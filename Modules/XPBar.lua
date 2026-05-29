-------------------------------------------------------------------------------
--  SphereUnitFrames · XPBar.lua
--  Barre circulaire d'XP autour de la sphère.
--  60 micro-segments fins → continuité visuelle.
--  10 dividers radiaux noirs PAR-DESSUS = paliers visuels (cf croquis user).
-------------------------------------------------------------------------------

local ADDON = "SphereUnitFrames"
local SUF   = _G[ADDON]
if not SUF then return end

SUF.XPBar = SUF.XPBar or {}
local XPBar = SUF.XPBar

local SEG_FINE    = 60
local SEG_VISUAL  = 10
local function SNPM(n) return (SUF.MEDIA or "Interface\\AddOns\\SphereUnitFrames\\media\\") .. n end

function XPBar:Build(data)
    if not data or not data.root or not data.orb then return end
    local cfg = SUF.db
    if cfg and cfg.xpbar_enabled == false then return end
    if data._xpBar then return data._xpBar end

    local root   = data.root
    local orb    = data.orb
    local size   = (cfg and cfg.orbSize) or 160
    local radius = size * 0.50 * (cfg and cfg.xpbar_radius_ratio or 1.32)
    local rootFL = root:GetFrameLevel() or 100

    local frame = CreateFrame("Frame", "SUFXPBarFrame", root)
    frame:SetSize(size * 2.0, size * 2.0)
    frame:SetPoint("CENTER", orb, "CENTER", 0, 0)
    frame:SetFrameLevel(rootFL + 8)

    local WHITE = SUF.WHITE8x8 or "Interface\\Buttons\\WHITE8X8"

    -- ── Ombre derrière (anneau plus large, sombre, BACKGROUND -2) ─────────────
    local shadow = frame:CreateTexture(nil, "BACKGROUND", nil, -2)
    shadow:SetTexture(SNPM("orb-border"))
    shadow:SetSize(radius * 2 + 14, radius * 2 + 14)
    shadow:SetPoint("CENTER", frame, "CENTER", 0, 1)
    shadow:SetVertexColor(0, 0, 0, cfg and cfg.xpbar_shadow_alpha or 0.55)
    shadow:SetBlendMode("BLEND")

    -- ── Contour subtil ───────────────────────────────────────────────────────
    local outline = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
    outline:SetTexture(SNPM("orb-border"))
    outline:SetSize(radius * 2 + 4, radius * 2 + 4)
    outline:SetPoint("CENTER", frame, "CENTER", 0, 0)
    outline:SetVertexColor(0.40, 0.15, 0.65, cfg and cfg.xpbar_outline_alpha or 0.80)
    outline:SetBlendMode("ADD")

    -- ── 60 micro-segments fins (= barre continue) ────────────────────────────
    local segW = (cfg and cfg.xpbar_seg_width)  or 5
    local segH = (cfg and cfg.xpbar_seg_height) or 9
    local fine = {}
    for i = 1, SEG_FINE do
        local degMid = (i - 0.5) * (360 / SEG_FINE) - 90
        local rad = math.rad(degMid)
        local x = math.cos(rad) * radius
        local y = -math.sin(rad) * radius
        local s = frame:CreateTexture(nil, "ARTWORK", nil, 1)
        s:SetTexture(WHITE)
        s:SetSize(segW, segH)
        s:SetPoint("CENTER", frame, "CENTER", x, y)
        s:SetRotation(rad + math.pi / 2)
        s:SetVertexColor(0.10, 0.06, 0.16, 0.45)
        fine[i] = s
    end

    -- ── 10 dividers radiaux PAR-DESSUS (paliers visuels) ────────────────────
    local dividers = {}
    for i = 1, SEG_VISUAL do
        local degDiv = (i - 1) * (360 / SEG_VISUAL) - 90
        local rad = math.rad(degDiv)
        local x = math.cos(rad) * radius
        local y = -math.sin(rad) * radius
        local d = frame:CreateTexture(nil, "OVERLAY", nil, 5)
        d:SetTexture(WHITE)
        d:SetSize(3, segH + 6)
        d:SetPoint("CENTER", frame, "CENTER", x, y)
        d:SetRotation(rad + math.pi / 2)
        d:SetVertexColor(0, 0, 0, 0.95)
        dividers[i] = d
    end

    data._xpBar = { frame = frame, fine = fine, dividers = dividers,
                    shadow = shadow, outline = outline }
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

    -- Max level → on cache la barre, mais on garde l'ombre comme contour décoratif
    if maxXP <= 0 then
        for _, s in ipairs(data._xpBar.fine) do
            s:SetVertexColor(0.12, 0.08, 0.18, 0.30)
        end
        return
    end

    local ratio = math.max(0, math.min(1, xp / maxXP))
    local lit   = ratio * SEG_FINE
    local r = cfg and cfg.xpbar_lit_r or 0.65
    local g = cfg and cfg.xpbar_lit_g or 0.25
    local b = cfg and cfg.xpbar_lit_b or 1.00

    for i, s in ipairs(data._xpBar.fine) do
        if i <= math.floor(lit) then
            s:SetVertexColor(r, g, b, 0.95)
        elseif i == math.floor(lit) + 1 then
            -- segment partiel (% à l'intérieur du micro-segment)
            local p = lit - math.floor(lit)
            s:SetVertexColor(
                0.10 + (r - 0.10) * p,
                0.06 + (g - 0.06) * p,
                0.16 + (b - 0.16) * p,
                0.45 + 0.50 * p)
        else
            s:SetVertexColor(0.10, 0.06, 0.16, 0.45)
        end
    end
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
