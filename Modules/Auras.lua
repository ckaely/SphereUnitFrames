-------------------------------------------------------------------------------
--  SphereUnitFrames · Auras.lua
--  Auras (buffs / debuffs) pour l'unité "player".
--  Adapté de SphereNameplates/Modules/Auras.lua — SP → SUF.
--  Retiré : segment mode (nécessite assets SNP), SP:GetCfg, SimulateAuras.
-------------------------------------------------------------------------------

local ADDON = "SphereUnitFrames"
local SUF   = _G[ADDON]
if not SUF then return end

SUF.Auras = SUF.Auras or {}
local Auras = SUF.Auras

-- ─── Couleurs ─────────────────────────────────────────────────────────────────
local DISPEL_COLORS = {
    Magic   = {r=0.20, g=0.60, b=1.00},
    Curse   = {r=0.60, g=0.00, b=1.00},
    Disease = {r=0.60, g=0.40, b=0.00},
    Poison  = {r=0.00, g=0.60, b=0.00},
    Bleed   = {r=0.80, g=0.00, b=0.00},
}

local _ceil = math.ceil
local _sin  = math.sin
local _cos  = math.cos
local _pi   = math.pi

-- ─── Helpers ─────────────────────────────────────────────────────────────────
local function SafeBool(v, fb)
    local ok, r = pcall(function() return v and true or false end)
    return ok and r or fb
end

local function SafeString(v)
    local ok, r = pcall(tostring, v)
    return ok and r or nil
end

local function SafeDispelName(v)
    local ok, r = pcall(function()
        if v=="Magic" or v=="Curse" or v=="Disease" or v=="Poison" or v=="Bleed" then return v end
        return nil
    end)
    return ok and r or nil
end

local function SafeAuraNumber(v)
    return SUF:UntaintNum(v)
end

local function ReadAuraField(aura, key)
    local ok, v = pcall(function() return aura[key] end)
    return ok and v or nil
end

local function SafeIsNil(v)
    local ok, r = pcall(function() return v == nil end)
    return ok and r or false
end

local function HasFilterToken(filter, token)
    return type(filter) == "string" and filter:find(token, 1, true) ~= nil
end

local function _cfg()
    return SUF.db or {}
end

-- ─── Cooldown helper ─────────────────────────────────────────────────────────
local function ConfigureAuraCooldown(cd, r, g, b, alpha, edge)
    if not cd then return end
    cd:SetSwipeColor(r or 1, g or 0.2, b or 0.08, alpha or 0.86)
    pcall(function() cd:SetDrawEdge(edge ~= false) end)
end

local function UpdateTimerText(icon)
    if not (icon and icon.timer) then return end
    local exp = icon._timerExp
    if not icon._timerTextEnabled or not exp then
        icon.timer:SetText(""); icon.timer:Hide(); return
    end
    local ok, remain = pcall(function() return exp - GetTime() end)
    if not ok or remain <= 0 then
        icon.timer:SetText(""); icon.timer:Hide(); return
    end
    icon.timer:SetText(remain >= 60 and (tostring(_ceil(remain/60)) .. "m") or tostring(_ceil(remain)))
    icon.timer:Show()
end

-- ─── API détection ────────────────────────────────────────────────────────────
local _UA             = C_UnitAuras
local GetAuraSlots    = _UA and _UA.GetAuraSlots
local GetAuraBySlot   = _UA and _UA.GetAuraDataBySlot
local GetUnitAuras    = _UA and _UA.GetUnitAuras
local _hasLegacyAura  = (type(UnitDebuff) == "function")

-- ─── FetchAuras ───────────────────────────────────────────────────────────────
local function FetchAuras(unit, baseFilter)
    local result, seen = {}, {}

    local function addAura(aura)
        if not aura then return end
        local auraID  = SafeAuraNumber(ReadAuraField(aura, "auraInstanceID"))
        local spellID = SafeAuraNumber(ReadAuraField(aura, "spellId"))
        local key = auraID or (spellID and (tostring(baseFilter)..":"..tostring(spellID))) or nil
        if key and seen[key] then return end
        if key then seen[key] = true end
        result[#result+1] = aura
    end

    if GetAuraSlots then
        local function tryGetSlots(filter)
            local returns = {}
            local function capture(...)
                local n = select("#", ...)
                returns.n = n
                for i = 1, n do returns[i] = select(i, ...) end
            end
            local ok = pcall(function() capture(GetAuraSlots(unit, filter)) end)
            if not ok then return nil end
            local slots = {}
            for i = 2, (returns.n or 0) do
                if returns[i] ~= nil then slots[#slots+1] = returns[i] end
            end
            return slots
        end

        local filters = {}
        local function addFilter(f)
            if not f then return end
            for _, e in ipairs(filters) do if e==f then return end end
            filters[#filters+1] = f
        end
        addFilter(baseFilter)
        if HasFilterToken(baseFilter,"HARMFUL") and not HasFilterToken(baseFilter,"PLAYER") then
            addFilter(baseFilter.."|PLAYER")
        end

        local seenSlots = {}
        for _, filter in ipairs(filters) do
            local slots = tryGetSlots(filter)
            if slots then
                for _, slot in ipairs(slots) do
                    if slot ~= nil and not seenSlots[slot] then
                        seenSlots[slot] = true
                        local ok3, aura = pcall(GetAuraBySlot, unit, slot)
                        if ok3 and aura then addAura(aura) end
                    end
                end
            end
        end

        if GetUnitAuras then
            local ok, auras = pcall(GetUnitAuras, unit, baseFilter, nil)
            if ok and type(auras) == "table" then
                for _, a in ipairs(auras) do addAura(a) end
            end
        end

    elseif GetUnitAuras then
        local ok, auras = pcall(GetUnitAuras, unit, baseFilter, nil)
        if ok and type(auras) == "table" then
            for _, a in ipairs(auras) do addAura(a) end
        end

    elseif _hasLegacyAura then
        local getter = HasFilterToken(baseFilter,"HARMFUL") and UnitDebuff or UnitBuff
        local i = 1
        while true do
            local ok, name, icon, count, dispelType, dur, expTime = pcall(getter, unit, i)
            if not ok or not name then break end
            result[#result+1] = {
                icon=icon, applications=count, dispelName=dispelType,
                duration=dur, expirationTime=expTime,
            }
            i = i + 1; if i > 40 then break end
        end
    end
    return result
end

Auras.FetchAuras = FetchAuras

-- ─── Pool d'icônes ────────────────────────────────────────────────────────────
local pool = {}
local CIRCLE_MASK_AURA = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local function AcquireIcon(parent)
    local f = table.remove(pool)
    if not f then
        if InCombatLockdown() then return nil end
        f = CreateFrame("Frame", nil, parent)
        f:SetSize(24, 24)

        local mask = f:CreateMaskTexture()
        pcall(function()
            mask:SetTexture(CIRCLE_MASK_AURA, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            mask:SetAllPoints(f)
        end)
        f._mask = mask

        -- Fond
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(f)
        bg:SetTexture(SUF.WHITE8x8 or "Interface\\Buttons\\WHITE8X8")
        bg:SetVertexColor(0.08, 0.07, 0.06, 0.92)
        if f._mask then pcall(bg.AddMaskTexture, bg, f._mask) end

        -- Icône
        f.icon = f:CreateTexture(nil, "ARTWORK")
        f.icon:SetPoint("CENTER")
        f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        if f._mask then pcall(f.icon.AddMaskTexture, f.icon, f._mask) end

        -- Bordure
        f.border = f:CreateTexture(nil, "OVERLAY")
        f.border:SetPoint("CENTER")
        f.border:SetTexture(SUF.NATIVE_RING or "Interface\\Buttons\\UI-AutoCastableOverlay")
        f.border:SetBlendMode("ADD")
        f.border:SetAlpha(0.90)

        -- Stack count
        f.count = f:CreateFontString(nil, "OVERLAY")
        f.count:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
        f.count:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 1, -1)
        f.count:SetTextColor(1, 1, 1, 1)
        f.count:SetShadowColor(0, 0, 0, 1)
        f.count:SetShadowOffset(1, -1)

        -- Timer texte
        f.timer = f:CreateFontString(nil, "OVERLAY")
        f.timer:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
        f.timer:SetPoint("CENTER", f, "CENTER", 0, 0)
        f.timer:SetTextColor(1, 0.92, 0.75, 1)
        f.timer:SetShadowColor(0, 0, 0, 1)
        f.timer:SetShadowOffset(1, -1)
        f.timer:Hide()
        f:SetScript("OnUpdate", function(self, elapsed)
            self._timerTick = (self._timerTick or 0) + (elapsed or 0)
            if self._timerTick >= 0.20 then
                self._timerTick = 0
                UpdateTimerText(self)
            end
        end)

        -- Cooldown swipe
        f.cd = CreateFrame("Cooldown", nil, f)
        f.cd:SetAllPoints(f)
        f.cd:SetDrawSwipe(true)
        f.cd:SetReverse(true)
        f.cd:SetHideCountdownNumbers(true)
        ConfigureAuraCooldown(f.cd, 1, 0.20, 0.08)
        pcall(function() f.cd:SetDrawEdge(true) end)
    else
        f:SetParent(parent)
    end
    f:ClearAllPoints()
    f:Hide()
    return f
end

local function ReleaseIcon(f)
    f:Hide()
    f:ClearAllPoints()
    f.auraID   = nil
    f.auraType = nil
    f._isCc    = nil
    f._ccExpiry= nil
    if f.count  then f.count:SetText("") end
    if f.timer  then f.timer:SetText(""); f.timer:Hide() end
    if f.border then f.border:SetAlpha(0) end
    if f.cd     then f.cd:Clear() end
    f._timerExp         = nil
    f._timerTextEnabled = nil
    f._timerTick        = 0
    table.insert(pool, f)
end

-- ─── Layout icône ─────────────────────────────────────────────────────────────
local function LayoutAuraIconVisual(icon, size)
    if not icon then return end
    size = size or icon:GetWidth() or 24
    local inner  = math.max(8, math.floor(size * 0.82 + 0.5))
    local border = math.max(size + 4, math.floor(size * 1.35 + 0.5))
    if icon._mask  then icon._mask:ClearAllPoints(); icon._mask:SetAllPoints(icon) end
    if icon.icon   then icon.icon:ClearAllPoints(); icon.icon:SetPoint("CENTER"); icon.icon:SetSize(inner, inner) end
    if icon.border then icon.border:ClearAllPoints(); icon.border:SetPoint("CENTER"); icon.border:SetSize(border, border) end
    if icon.count  then icon.count:ClearAllPoints(); icon.count:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1) end
    if icon.timer  then icon.timer:ClearAllPoints(); icon.timer:SetPoint("CENTER", icon, "CENTER", 0, 0) end
    if icon.cd     then icon.cd:ClearAllPoints(); icon.cd:SetAllPoints(icon) end
end

-- ─── Update icône ─────────────────────────────────────────────────────────────
local function UpdateAuraIcon(icon, auraData, auraType, cfg)
    cfg = cfg or _cfg()
    local iconTex, applications, duration, expTime
    pcall(function() iconTex      = auraData.icon end)
    pcall(function() applications = auraData.applications end)
    pcall(function() duration     = auraData.duration end)
    pcall(function() expTime      = auraData.expirationTime end)
    local dispelName = SafeDispelName(ReadAuraField(auraData, "dispelName"))
    local dur = SafeAuraNumber(duration)
    local exp = SafeAuraNumber(expTime)

    -- CC detection
    local isCc = false
    if not dispelName and dur and exp then
        local ok2, showAll = pcall(function() return auraData.nameplateShowAll end)
        local allowCC = not ok2 or showAll ~= false
        if allowCC and dur >= 1.0 and dur <= 30 then isCc = true end
    end
    icon._isCc     = isCc
    icon._ccExpiry = isCc and exp or nil

    -- Texture icône
    local safeIcon = 134400
    pcall(function() if iconTex ~= nil then safeIcon = iconTex end end)
    pcall(icon.icon.SetTexture, icon.icon, safeIcon)

    -- Couleur bordure
    local dc = dispelName and DISPEL_COLORS[dispelName]
    if dc then
        icon.border:SetVertexColor(dc.r, dc.g, dc.b, 1)
        icon.border:SetAlpha(0.92)
    elseif auraType == "help" then
        icon.border:SetVertexColor(0.12, 0.72, 1.0, 1)
        icon.border:SetAlpha(0.80)
    else
        icon.border:SetVertexColor(1, 0.24, 0.08, 1)
        icon.border:SetAlpha(0.86)
    end

    -- Stack count
    if icon.count then
        local appCount = SafeAuraNumber(applications)
        icon.count:SetText((appCount and appCount > 1) and tostring(appCount) or "")
    end

    -- Cooldown swipe
    if icon.cd then
        local showCd = false
        local showTimers = (auraType == "help" and cfg.auras_show_timers ~= false)
                       or  (auraType ~= "help" and cfg.auras_show_timers ~= false)
        if showTimers and duration ~= nil and expTime ~= nil then
            pcall(function()
                local remaining = expTime - GetTime()
                if remaining > 0 and duration > 0 then
                    icon.cd:SetCooldown(expTime - duration, duration)
                    icon.cd:Show()
                    showCd = true
                end
            end)
        end
        if not showCd then pcall(icon.cd.Clear, icon.cd); pcall(icon.cd.Hide, icon.cd) end
    end

    if icon.timer then
        icon._timerExp         = exp or expTime
        icon._timerTextEnabled = cfg.auras_show_timers ~= false
                                 and (exp ~= nil or expTime ~= nil)
        UpdateTimerText(icon)
    end
end

-- ─── Ring angles (5 emplacements) ────────────────────────────────────────────
local RING_ANGLES = {}
for i, deg in ipairs({270, 198, 342, 126, 54}) do
    RING_ANGLES[i] = deg * _pi / 180
end

-- ─── Direction → angle centre (radians) ──────────────────────────────────────
-- Coordonnées WoW : 0° = droite, 90° = haut, 180° = gauche, 270° = bas
local DIR_ANGLE = {
    top    = _pi * 0.5,    -- 90°  → haut
    bottom = _pi * 1.5,    -- 270° → bas
    left   = _pi,          -- 180° → gauche
    right  = 0,            -- 0°   → droite
}

-- ─── Repositionnement ────────────────────────────────────────────────────────
local function RepositionIcons(data)
    local cfg      = _cfg()
    local baseSize = cfg.auras_size or 28
    local icons    = data.auraIcons
    local n        = #icons
    if n == 0 then data._ringAuraCount = 0; return end

    local orbRadius = (data.orbSize or 160) * 0.5

    -- ── Mode anneau (5 slots fixes) ──────────────────────────────────────────
    if (cfg.auras_mode or "ring") == "ring" then
        local maxSlots = math.min(n, 5)
        for i = 1, maxSlots do
            local ic   = icons[i]
            local size = baseSize
            local R    = orbRadius * (cfg.auras_offset_radius or 1.35) + size * 0.5
            local ang  = RING_ANGLES[i]
            ic:SetSize(size, size)
            LayoutAuraIconVisual(ic, size)
            ic:ClearAllPoints()
            ic:SetPoint("CENTER", data.orb, "CENTER", R * _cos(ang), R * _sin(ang))
            ic:Show()
        end
        for i = maxSlots+1, n do icons[i]:Hide() end
        data._ringAuraCount = maxSlots
        return
    end

    -- ── Mode arc (direction configurable par type) ───────────────────────────
    data._ringAuraCount = 0

    local groups = {harm={}, help={}}
    for _, ic in ipairs(icons) do
        if ic.auraType == "help" then groups.help[#groups.help+1] = ic
        else                          groups.harm[#groups.harm+1] = ic end
    end

    local maxSpreadDeg = cfg.auras_arc_spread or 160
    local maxSpreadRad = maxSpreadDeg * _pi / 180

    local function placeGroup(list, auraType)
        local count = #list
        if count == 0 then return end
        local R = orbRadius * (cfg.auras_offset_radius or 1.35) + baseSize * 0.5

        -- Lire la direction de l'arc depuis la config
        local dirKey = (auraType == "help")
                       and (cfg.auras_buff_arc_dir   or "top")
                       or  (cfg.auras_debuff_arc_dir or "bottom")
        local center = DIR_ANGLE[dirKey] or _pi * 1.5

        -- Spread proportionnel au nombre d'auras, plafonné à maxSpread
        local spread = math.min(maxSpreadRad, (count - 1) * (32 * _pi / 180))

        for i, ic in ipairs(list) do
            local frac  = (count > 1) and ((i-1) / (count-1)) or 0.5
            local angle = center - spread * 0.5 + frac * spread
            ic:SetSize(baseSize, baseSize)
            LayoutAuraIconVisual(ic, baseSize)
            ic:ClearAllPoints()
            ic:SetPoint("CENTER", data.orb, "CENTER", R * _cos(angle), R * _sin(angle))
            ic:Show()
        end
    end

    placeGroup(groups.harm, "harm")
    placeGroup(groups.help, "help")
end

-- ─── Interface publique ───────────────────────────────────────────────────────
function Auras:Init(data)
    data.auraIcons = data.auraIcons or {}
    data.auraMap   = data.auraMap   or {}
end

function Auras:RemoveAll(data)
    if not data.auraIcons then return end
    for _, ic in ipairs(data.auraIcons) do ReleaseIcon(ic) end
    data.auraIcons      = {}
    data.auraMap        = {}
    data._ringAuraCount = 0
end

function Auras:UpdateUnit(data, unit, updateInfo)
    local cfg = _cfg()
    if cfg.auras_enabled == false then
        self:RemoveAll(data)
        return
    end

    -- Throttle anti-flickering
    local now = GetTime()
    if updateInfo and not updateInfo.isFullUpdate then
        data._auraLastUpdate = data._auraLastUpdate or 0
        if (now - data._auraLastUpdate) < 0.15 then return end
    end
    data._auraLastUpdate = now

    self:Init(data)
    self:RemoveAll(data)

    local maxDebuff = cfg.auras_max_debuffs or 8
    local maxBuff   = cfg.auras_max_buffs   or 8

    local function AddBatch(baseFilter, auraType, maxCount)
        local mineOnly = (auraType == "harm" and cfg.auras_debuff_mine_only)
                      or (auraType == "help" and cfg.auras_buff_mine_only)
        local effectiveFilter = (mineOnly and not HasFilterToken(baseFilter, "PLAYER"))
                                and (baseFilter.."|PLAYER") or baseFilter
        local auras = FetchAuras(unit, effectiveFilter)
        local added = 0
        for _, aura in ipairs(auras) do
            if added >= maxCount then break end
            local ic = AcquireIcon(data.root)
            if not ic then break end
            UpdateAuraIcon(ic, aura, auraType, cfg)
            ic.auraType = auraType
            local ok2, instID = pcall(function() return aura.auraInstanceID end)
            ic.auraID = ok2 and SUF:UntaintNum(instID) or nil
            if ic.auraID then data.auraMap[ic.auraID] = ic end
            table.insert(data.auraIcons, ic)
            added = added + 1
        end
    end

    AddBatch("HARMFUL", "harm", maxDebuff)
    AddBatch("HELPFUL", "help", maxBuff)

    RepositionIcons(data)

    -- CC detection → UpdateCC
    local ccExpiry = nil
    for _, ic in ipairs(data.auraIcons) do
        if ic._isCc and ic._ccExpiry then
            local isLonger = not ccExpiry
            if not isLonger then
                pcall(function() isLonger = ic._ccExpiry > ccExpiry end)
            end
            if isLonger then ccExpiry = ic._ccExpiry end
        end
    end
    if SUF.Orb then pcall(SUF.Orb.UpdateCC, SUF.Orb, data, ccExpiry) end
end

-- ─── Pré-chauffe du pool ──────────────────────────────────────────────────────
function Auras:PrewarmPool(count)
    count = count or 24
    local toCreate = count - #pool
    if toCreate <= 0 then return end
    for _ = 1, toCreate do
        local f = AcquireIcon(UIParent)
        if f then
            f:Hide(); f:ClearAllPoints(); f:SetParent(UIParent)
            table.insert(pool, f)
        end
    end
end
