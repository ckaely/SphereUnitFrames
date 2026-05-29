-------------------------------------------------------------------------------
--  SphereUnitFrames · XPBar.lua
--  Barre circulaire d'XP autour de la sphère.
--  10 segments (paliers), couleur violette, ombre transparente, contour.
-------------------------------------------------------------------------------

local ADDON = "SphereUnitFrames"
local SUF   = _G[ADDON]
if not SUF then return end

SUF.XPBar = SUF.XPBar or {}
local XPBar = SUF.XPBar

local SEG_COUNT = 10

local function SNPM(n) return (SUF.MEDIA or "Interface\\AddOns\\SphereUnitFrames\\media\\") .. n end

function XPBar:Build(data)
    if not data or not data.root or not data.orb then return end
    local cfg = SUF.db
    if cfg and cfg.xpbar_enabled == false then return end
    if data._xpBar then return data._xpBar end

    local root   = data.root
    local orb    = data.orb
    local size   = (cfg and cfg.orbSize) or 160
    local rRing  = (cfg and cfg.xpbar_radius_ratio or 0.62) * size
    local rootFL = root:GetFrameLevel() or 100

    local frame = CreateFrame("Frame", "SUFXPBarFrame", root)
    frame:SetSize(size * 1.4, size * 1.4)
    frame:SetPoint("CENTER", orb, "CENTER", 0, 0)
    frame:SetFrameLevel(rootFL + 8)

    -- ── Ombre transparente derrière (cercle plus grand) ──────────────────────
    local shadow = frame:CreateTexture(nil, "BACKGROUND")
    shadow:SetTexture(SNPM("orb-border"))
    shadow:SetSize(size * 1.36, size * 1.36)
    shadow:SetPoint("CENTER", frame, "CENTER", 0, 2)
    shadow:SetVertexColor(0, 0, 0, cfg and cfg.xpbar_shadow_alpha or 0.55)
    shadow:SetBlendMode("BLEND")

    -- ── Contour violet (ring autour des segments) ────────────────────────────
    local outline = frame:CreateTexture(nil, "BORDER")
    outline:SetTexture(SNPM("orb-border"))
    outline:SetSize(size * 1.30, size * 1.30)
    outline:SetPoint("CENTER", frame, "CENTER", 0, 0)
    outline:SetVertexColor(0.45, 0.15, 0.75, cfg and cfg.xpbar_outline_alpha or 0.85)
    outline:SetBlendMode("ADD")

    -- ── 10 segments (paliers) ────────────────────────────────────────────────
    local segments = {}
    local segWidth  = (cfg and cfg.xpbar_seg_width)  or (size * 0.28)
    local segHeight = (cfg and cfg.xpbar_seg_height) or 7
    for i = 1, SEG_COUNT do
        -- Centre du segment i (en degrés, départ haut, sens horaire)
        local degCenter = (i - 0.5) * (360 / SEG_COUNT) - 90
        local rad = math.rad(degCenter)
        local x = math.cos(rad) * rRing
        local y = -math.sin(rad) * rRing   -- WoW : y inversé

        local seg = frame:CreateTexture(nil, "ARTWORK", nil, 2)
        seg:SetTexture(SUF.WHITE8x8 or "Interface\\Buttons\\WHITE8X8")
        seg:SetSize(segWidth, segHeight)
        seg:SetPoint("CENTER", frame, "CENTER", x, y)
        -- Rotation pour suivre la tangente du cercle
        seg:SetRotation(rad + math.pi / 2)
        seg:SetVertexColor(0.16, 0.10, 0.22, 0.45)  -- éteint = sombre transparent
        segments[i] = seg

        -- Mini outline sur chaque segment (contour subtil)
        local rim = frame:CreateTexture(nil, "ARTWORK", nil, 3)
        rim:SetTexture(SUF.WHITE8x8 or "Interface\\Buttons\\WHITE8X8")
        rim:SetSize(segWidth + 2, segHeight + 2)
        rim:SetPoint("CENTER", seg, "CENTER", 0, 0)
        rim:SetRotation(rad + math.pi / 2)
        rim:SetVertexColor(0, 0, 0, 0.7)
        rim:SetDrawLayer("ARTWORK", 1)   -- sous le segment lui-même
    end

    data._xpBar = {frame=frame, segments=segments, shadow=shadow, outline=outline}
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
        -- max level → cacher
        if data._xpBar.frame then data._xpBar.frame:Hide() end
        return
    end
    data._xpBar.frame:Show()
    local ratio = math.max(0, math.min(1, xp / maxXP))
    local lit = math.floor(ratio * SEG_COUNT + 0.0001)
    -- Segment partiellement allumé (% à l'intérieur du palier)
    local partial = ratio * SEG_COUNT - lit

    local litR, litG, litB = 0.65, 0.25, 1.00
    if cfg then
        litR = cfg.xpbar_lit_r or litR
        litG = cfg.xpbar_lit_g or litG
        litB = cfg.xpbar_lit_b or litB
    end

    for i = 1, SEG_COUNT do
        local seg = data._xpBar.segments[i]
        if seg then
            if i <= lit then
                seg:SetVertexColor(litR, litG, litB, 0.95)
            elseif i == lit + 1 and partial > 0 then
                -- Segment courant partiellement allumé
                local a = 0.30 + 0.65 * partial
                seg:SetVertexColor(litR * 0.7, litG * 0.7, litB * 0.7, a)
            else
                seg:SetVertexColor(0.16, 0.10, 0.22, 0.45)
            end
        end
    end
end

function XPBar:Init()
    local data = SUF.player
    if not data then return end
    self:Build(data)
    self:Update(data)
    -- Events XP
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
