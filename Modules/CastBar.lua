-------------------------------------------------------------------------------
--  SphereUnitFrames · CastBar.lua
--  Cast bar circulaire pour l'unité "player" uniquement.
--  Un seul watcher (RegisterUnitEvent), pas de pool de frames.
--  Modes : "circular" (CooldownFrame arc) | "classic" (pill bar)
-------------------------------------------------------------------------------

local ADDON = "SphereUnitFrames"
local SUF   = _G[ADDON]
if not SUF then return end

SUF.CastBar = SUF.CastBar or {}
local CastBar = SUF.CastBar

-- ─── Palette ─────────────────────────────────────────────────────────────────
local CLR_CAST    = {r=1.0,  g=0.65, b=0.00}
local CLR_CHANNEL = {r=0.30, g=0.70, b=1.00}
local CLR_NONINT  = {r=0.62, g=0.18, b=1.00}
local CLR_FINISH  = {r=0.30, g=1.00, b=0.30}
local CLR_BROKEN  = {r=0.95, g=0.20, b=0.20}

local CAST_EVENTS = {
    "UNIT_SPELLCAST_START",
    "UNIT_SPELLCAST_DELAYED",
    "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_CHANNEL_UPDATE",
    "UNIT_SPELLCAST_INTERRUPTIBLE",
    "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
    "UNIT_SPELLCAST_SUCCEEDED",
}

local _watcher = nil

-- ─── Helpers ─────────────────────────────────────────────────────────────────
local function _safeNum(v)
    if v == nil then return nil end
    local n = SUF:UntaintNum(v)
    if n then return n end
    local ok, r = pcall(tonumber, v)
    return ok and r or nil
end

local function _normMS(v)
    local n = _safeNum(v)
    if not n or n <= 0 then return nil end
    return n > 1000 and (n / 1000) or n
end

local function _spellIcon(spellId)
    if not spellId then return nil end
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, t = pcall(C_Spell.GetSpellTexture, spellId)
        if ok and t ~= nil then return t end
    end
    if GetSpellTexture then
        local ok, t = pcall(GetSpellTexture, spellId)
        if ok and t ~= nil then return t end
    end
    return nil
end

local function _spellName(spellId)
    if not spellId then return nil end
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, spellId)
        if ok and type(info) == "table" and info.name ~= nil then
            -- SetText accepte les secret strings
            return info.name
        end
    end
    return nil
end

-- ─── Init (après Orb:CreatePlayer) ───────────────────────────────────────────
function CastBar:Init(data)
    if not data or not data.root then return end
    if data.castbar then return end

    local root   = data.root
    local rootFL = root:GetFrameLevel() or 100
    local cfg    = SUF.db
    local size   = (cfg and cfg.orbSize) or 160
    local arcSize = size + 28

    -- ── Circular arc ─────────────────────────────────────────────────────────
    local arcFrame = CreateFrame("Frame", "SUFCastArcFrame", root)
    arcFrame:SetSize(arcSize, arcSize)
    arcFrame:SetPoint("CENTER", root, "CENTER", 0, math.floor(size * 0.05))
    arcFrame:SetFrameLevel(rootFL + 5)

    local cd = CreateFrame("Cooldown", nil, arcFrame)
    cd:SetAllPoints(arcFrame)
    cd:SetDrawSwipe(true)
    cd:SetDrawEdge(true)
    cd:SetHideCountdownNumbers(true)
    cd:SetReverse(true)
    pcall(function() cd:SetSwipeTexture("Interface\\Cooldown\\ping4") end)
    pcall(function() cd:SetUseCircularEdge(true) end)
    pcall(function() cd:SetDrawBling(false) end)
    cd:SetSwipeColor(CLR_CAST.r, CLR_CAST.g, CLR_CAST.b, 0.85)

    -- Anneau glow ADD
    local glowRing = arcFrame:CreateTexture(nil, "OVERLAY")
    glowRing:SetTexture(SUF.NATIVE_RING or "Interface\\Buttons\\UI-AutoCastableOverlay")
    glowRing:SetSize(arcSize + 16, arcSize + 16)
    glowRing:SetPoint("CENTER", arcFrame, "CENTER")
    glowRing:SetBlendMode("ADD")
    glowRing:SetVertexColor(CLR_CAST.r, CLR_CAST.g, CLR_CAST.b)
    glowRing:SetAlpha(0)

    -- ── Collapse Glow Ring : grand anneau qui rétrécit jusqu'à l'arc ──────
    local collapseRing = arcFrame:CreateTexture(nil, "OVERLAY", nil, 2)
    collapseRing:SetTexture("Interface\\Cooldown\\ping4")
    collapseRing:SetBlendMode("ADD")
    collapseRing:SetPoint("CENTER", arcFrame, "CENTER")
    collapseRing:SetSize(arcSize, arcSize)
    collapseRing:SetVertexColor(CLR_CAST.r, CLR_CAST.g, CLR_CAST.b, 0)
    collapseRing:Hide()

    -- ── Interrupt mark : croix rouge flash sur interrupt ──────────────────
    local interruptMark = arcFrame:CreateTexture(nil, "OVERLAY", nil, 5)
    interruptMark:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
    interruptMark:SetSize(20, 20)
    interruptMark:SetPoint("CENTER", arcFrame, "CENTER")
    interruptMark:SetVertexColor(0.95, 0.20, 0.20, 1)
    interruptMark:SetAlpha(0)

    -- ── Classic pill bar ──────────────────────────────────────────────────────
    local pill = CreateFrame("StatusBar", nil, root)
    pill:SetSize(size, 12)
    pill:SetPoint("TOP", root, "BOTTOM", 0, -2)
    pill:SetFrameLevel(rootFL + 5)
    pill:SetStatusBarTexture(SUF.WHITE8x8 or "Interface\\Buttons\\WHITE8X8")
    pill:SetMinMaxValues(0, 1)
    pill:SetValue(0)
    local pillBg = pill:CreateTexture(nil, "BACKGROUND")
    pillBg:SetAllPoints(pill)
    pillBg:SetTexture(SUF.WHITE8x8 or "Interface\\Buttons\\WHITE8X8")
    pillBg:SetVertexColor(0.03, 0.03, 0.05, 0.85)
    local pillTex = pill:GetStatusBarTexture()
    if pillTex then pillTex:SetVertexColor(CLR_CAST.r, CLR_CAST.g, CLR_CAST.b, 1) end

    -- ── Icon ─────────────────────────────────────────────────────────────────
    local iconSz  = 28
    local iconFrm = CreateFrame("Frame", nil, root)
    iconFrm:SetSize(iconSz, iconSz)
    iconFrm:SetPoint("BOTTOMLEFT", root, "TOPRIGHT", -math.floor(size * 0.1), 4)
    iconFrm:SetFrameLevel(rootFL + 6)

    local iconMask = iconFrm:CreateMaskTexture()
    pcall(function()
        iconMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask",
            "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        iconMask:SetAllPoints(iconFrm)
    end)
    local iconTex = iconFrm:CreateTexture(nil, "ARTWORK")
    iconTex:SetAllPoints(iconFrm)
    iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if iconMask then pcall(iconTex.AddMaskTexture, iconTex, iconMask) end

    local iconBorder = iconFrm:CreateTexture(nil, "OVERLAY")
    iconBorder:SetPoint("CENTER", iconFrm, "CENTER")
    iconBorder:SetSize(iconSz + 8, iconSz + 8)
    iconBorder:SetTexture(SUF.NATIVE_RING or "Interface\\Buttons\\UI-AutoCastableOverlay")
    iconBorder:SetBlendMode("ADD")
    iconBorder:SetVertexColor(CLR_CAST.r, CLR_CAST.g, CLR_CAST.b)

    -- ── Textes ───────────────────────────────────────────────────────────────
    local fontSize = (cfg and cfg.castbar_time_font_size) or 12
    local font     = (cfg and cfg.hp_font) or "Fonts\\FRIZQT__.TTF"

    local castName = root:CreateFontString(nil, "OVERLAY")
    castName:SetFont(font, fontSize, "OUTLINE")
    castName:SetPoint("TOP", root, "BOTTOM", 0, -16)
    castName:SetWidth(size * 1.8)
    castName:SetJustifyH("CENTER")
    castName:SetTextColor(1, 0.88, 0.45, 1)

    local castTime = root:CreateFontString(nil, "OVERLAY")
    castTime:SetFont(font, fontSize - 2, "OUTLINE")
    castTime:SetPoint("TOP", castName, "BOTTOM", 0, -1)
    castTime:SetJustifyH("CENTER")
    castTime:SetTextColor(1, 1, 1, 1)

    -- Lock icon
    local lockTex = root:CreateTexture(nil, "OVERLAY")
    lockTex:SetSize(10, 12)
    lockTex:SetPoint("RIGHT", castName, "LEFT", -3, 0)
    lockTex:SetTexture("Interface\\PetBattles\\PetBattle-LockIcon")
    lockTex:SetAlpha(0)

    -- ── Assemble ─────────────────────────────────────────────────────────────
    data.castbar = {
        arcFrame      = arcFrame,
        cd            = cd,
        glowRing      = glowRing,
        collapseRing  = collapseRing,
        interruptMark = interruptMark,
        pill          = pill,
        iconFrm     = iconFrm,
        iconTex     = iconTex,
        iconBorder  = iconBorder,
        castName    = castName,
        castTime    = castTime,
        lockTex     = lockTex,
        active      = false,
        channeling  = false,
        interruptible = true,
        startTime   = 0,
        endTime     = 0,
        duration    = 0,
        spellId     = nil,
        color       = CLR_CAST,
    }

    arcFrame:Hide()
    pill:Hide()
    iconFrm:Hide()
    castName:Hide()
    castTime:Hide()

    self:_InitWatcher()
end

function CastBar:_InitWatcher()
    if _watcher then return end
    _watcher = CreateFrame("Frame", "SUFCastWatcher")
    for _, ev in ipairs(CAST_EVENTS) do
        pcall(_watcher.RegisterUnitEvent, _watcher, ev, "player")
    end
    _watcher:SetScript("OnEvent", function(_, event, unit, ...)
        CastBar:_OnEvent(event, unit, ...)
    end)
end

-- ─── Event handler ───────────────────────────────────────────────────────────
function CastBar:_OnEvent(event, unit, ...)
    local data = SUF.player
    if not (data and data.castbar) then return end
    local cb = data.castbar

    if event == "UNIT_SPELLCAST_START" then
        local name, sMS, eMS, notInt, spellId
        pcall(function()
            name, _, _, sMS, eMS, _, _, notInt, spellId = UnitCastingInfo("player")
        end)
        local s = _normMS(sMS) or GetTime()
        local e = _normMS(eMS) or (GetTime() + 1.5)
        self:_StartCast(data, false, spellId, s, e, not notInt)

    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        local name, sMS, eMS, notInt, spellId
        pcall(function()
            name, _, _, sMS, eMS, _, notInt, spellId = UnitChannelInfo("player")
        end)
        local s = _normMS(sMS) or GetTime()
        local e = _normMS(eMS) or (GetTime() + 2.0)
        self:_StartCast(data, true, spellId, s, e, not notInt)

    elseif event == "UNIT_SPELLCAST_DELAYED" then
        pcall(function()
            local _, _, _, sMS, eMS = UnitCastingInfo("player")
            local s = _normMS(sMS); local e = _normMS(eMS)
            if s and e then cb.startTime = s; cb.endTime = e; cb.duration = math.max(0.1, e - s) end
            if cb.cd and cb.active then cb.cd:SetCooldown(s or cb.startTime, cb.duration) end
        end)

    elseif event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
        pcall(function()
            local _, _, _, sMS, eMS = UnitChannelInfo("player")
            local s = _normMS(sMS); local e = _normMS(eMS)
            if s and e then cb.startTime = s; cb.endTime = e; cb.duration = math.max(0.1, e - s) end
        end)

    elseif event == "UNIT_SPELLCAST_STOP"
        or event == "UNIT_SPELLCAST_FAILED"
        or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        self:Reset(data)

    elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
        if cb.castName then cb.castName:SetTextColor(CLR_BROKEN.r, CLR_BROKEN.g, CLR_BROKEN.b) end
        if cb.iconBorder then cb.iconBorder:SetVertexColor(CLR_BROKEN.r, CLR_BROKEN.g, CLR_BROKEN.b) end
        local pillTex = cb.pill and cb.pill:GetStatusBarTexture()
        if pillTex then pillTex:SetVertexColor(CLR_BROKEN.r, CLR_BROKEN.g, CLR_BROKEN.b, 1) end
        -- Interrupt mark flash
        local cfg = SUF.db
        if cfg.castbar_interrupt_mark_enabled ~= false and cb.interruptMark then
            local sz = cfg.castbar_interrupt_mark_size or 18
            cb.interruptMark:SetSize(sz * 1.6, sz * 1.6)
            cb.interruptMark:SetAlpha(1)
            local dur = cfg.castbar_interrupt_mark_duration or 0.42
            local fadeOut = cb.interruptMark:CreateAnimationGroup()
            local a1 = fadeOut:CreateAnimation("Alpha")
            a1:SetFromAlpha(1); a1:SetToAlpha(0); a1:SetDuration(dur)
            local sc = fadeOut:CreateAnimation("Scale")
            sc:SetFromScale(1.6, 1.6); sc:SetToScale(0.4, 0.4); sc:SetDuration(dur)
            fadeOut:Play()
        end
        -- Kick FX shards (port SNP)
        pcall(self.SpawnKickShards, self, data)
        C_Timer.After(0.4, function()
            if data.castbar and not data.castbar.active then return end
            CastBar:Reset(data)
        end)

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if cb.castName then cb.castName:SetTextColor(CLR_FINISH.r, CLR_FINISH.g, CLR_FINISH.b) end
        C_Timer.After(0.22, function() CastBar:Reset(data) end)

    elseif event == "UNIT_SPELLCAST_INTERRUPTIBLE" then
        cb.interruptible = true
        self:_ApplyColor(data)

    elseif event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
        cb.interruptible = false
        self:_ApplyColor(data)
    end
end

function CastBar:_StartCast(data, isChannel, spellId, startSec, endSec, interruptible)
    local cb = data.castbar
    cb.active         = true
    cb.channeling     = isChannel
    cb.interruptible  = interruptible
    cb.startTime      = startSec
    cb.endTime        = endSec
    cb.duration       = math.max(0.1, endSec - startSec)
    cb.spellId        = spellId
    cb.color          = isChannel and CLR_CHANNEL or CLR_CAST

    -- Icon
    local iconPath = _spellIcon(spellId)
    if iconPath and cb.iconTex then pcall(cb.iconTex.SetTexture, cb.iconTex, iconPath) end

    -- Name
    if cb.castName then
        local n = _spellName(spellId)
        if n ~= nil then
            pcall(cb.castName.SetText, cb.castName, n)
        else
            cb.castName:SetText(isChannel and "Canalisation" or "Incantation")
        end
        cb.castName:Show()
    end

    -- Visual mode
    local cfg  = SUF.db
    local mode = (cfg and cfg.castbar_style) or "circular"
    local showCirc  = (mode == "circular" or mode == "segments")
    local showPill  = (mode == "classic")

    local showCollapse = (mode == "collapse_glow")
    local showSegments = (mode == "segments")
    if showSegments then self:BuildSegments(data) end
    if cb.arcFrame then
        if showCirc or showCollapse or showSegments then cb.arcFrame:Show() else cb.arcFrame:Hide() end
    end
    if cb.pill then
        if showPill then cb.pill:Show() else cb.pill:Hide() end
    end
    if cb.collapseRing then
        if showCollapse then cb.collapseRing:Show() else cb.collapseRing:Hide() end
    end
    if cb.iconFrm then
        cb.iconFrm:Show()
    end
    if cb.castTime and cfg and cfg.castbar_show_time ~= false then
        cb.castTime:Show()
    end
    if cb.lockTex then cb.lockTex:SetAlpha(interruptible and 0 or 0.8) end

    -- Cooldown arc
    if cb.cd then
        cb.cd:SetReverse(not isChannel)
        cb.cd:SetCooldown(startSec, cb.duration)
    end

    self:_ApplyColor(data)
end

function CastBar:_ApplyColor(data)
    local cb = data.castbar
    if not cb then return end
    local c = (not cb.interruptible) and CLR_NONINT
           or cb.channeling and CLR_CHANNEL
           or CLR_CAST
    cb.color = c
    if cb.cd       then cb.cd:SetSwipeColor(c.r, c.g, c.b, 0.85) end
    if cb.glowRing then cb.glowRing:SetVertexColor(c.r, c.g, c.b) end
    if cb.iconBorder then cb.iconBorder:SetVertexColor(c.r, c.g, c.b) end
    local pillTex = cb.pill and cb.pill:GetStatusBarTexture()
    if pillTex then pillTex:SetVertexColor(c.r, c.g, c.b, 1) end
    local tr = cb.interruptible and 1.0 or 0.88
    local tg = cb.channeling and 0.75 or (cb.interruptible and 0.88 or 0.62)
    local tb = cb.channeling and 0.45 or (cb.interruptible and 0.45 or 1.0)
    if cb.castName then cb.castName:SetTextColor(tr, tg, tb, 1) end
end

-- ─── Tick (60 FPS depuis Core_OnUpdate) ──────────────────────────────────────
function CastBar:Tick(data, now)
    local cb = data and data.castbar
    if not cb or not cb.active then return end
    local cfg = SUF.db
    if cfg and cfg.castbar_enabled == false then self:Reset(data); return end

    local dur = cb.duration
    if dur <= 0 then return end

    -- Pill progress (arc est géré par le CooldownFrame natif)
    if cb.pill and cb.pill:IsShown() then
        local p = math.max(0, math.min(1, (now - cb.startTime) / dur))
        if cb.channeling then p = 1 - p end
        cb.pill:SetValue(p)
    end

    -- Texte temps restant
    if cb.castTime and cb.castTime:IsShown() then
        local remaining = math.max(0, cb.endTime - now)
        cb.castTime:SetText(string.format("%.1fs", remaining))
    end

    -- Glow pulse proche de la fin
    if cb.glowRing then
        local p = math.max(0, math.min(1, (now - cb.startTime) / dur))
        if not cb.channeling and p > 0.80 then
            local frac = (p - 0.80) / 0.20
            cb.glowRing:SetAlpha(0.15 + 0.45 * frac)
        else
            cb.glowRing:SetAlpha(0)
        end
    end

    -- Mode segments : éclaire les ticks au prorata
    if cb._segs and (cfg.castbar_style == "segments") then
        local p = math.max(0, math.min(1, (now - cb.startTime) / dur))
        if cb.channeling then p = 1 - p end
        self:UpdateSegments(data, p)
    end

    -- Collapse Glow Ring : grand anneau qui rétrécit vers l'arc
    if cb.collapseRing and cb.collapseRing:IsShown() then
        local p = math.max(0, math.min(1, (now - cb.startTime) / dur))
        local s0 = cfg.castbar_collapse_start_scale or 1.75
        local s1 = cfg.castbar_collapse_end_scale   or 0.72
        local scale = s0 + (s1 - s0) * p
        local sz = ((cfg.orbSize or 160) + 28) * scale
        cb.collapseRing:SetSize(sz, sz)
        local baseA = (cfg.castbar_collapse_alpha or 0.85)
        local pulse = cfg.castbar_collapse_glow_pulse
                      and (0.85 + 0.15 * math.sin(now * 6))
                      or 1.0
        cb.collapseRing:SetVertexColor(cb.color.r, cb.color.g, cb.color.b, baseA * pulse)
    end

    -- Expiration
    if now >= cb.endTime + 0.30 then
        self:Reset(data)
    end
end

-- ─── Presets (port SNP : minimal / overwatch / techno) ───────────────────────
local CASTBAR_PRESETS = {
    minimal = {
        castbar_style          = "circular",
        castbar_show_track     = true,
        castbar_show_ticks     = false,
        castbar_show_pin12     = false,
        castbar_glow_intensity = 0.8,
        castbar_complete_flash = true,
        castbar_arc_thickness  = 10,
        castbar_collapse_alpha = 0.75,
    },
    overwatch = {
        castbar_style          = "collapse_glow",
        castbar_show_track     = true,
        castbar_show_ticks     = false,
        castbar_show_pin12     = true,
        castbar_glow_intensity = 1.4,
        castbar_complete_flash = true,
        castbar_arc_thickness  = 16,
        castbar_collapse_start_scale = 2.0,
        castbar_collapse_end_scale   = 0.65,
        castbar_collapse_alpha       = 0.92,
        castbar_collapse_glow_pulse  = true,
    },
    techno = {
        castbar_style          = "segments",
        castbar_show_track     = true,
        castbar_show_ticks     = true,
        castbar_show_pin12     = true,
        castbar_glow_intensity = 1.6,
        castbar_v8_segments    = true,
        castbar_v8_count       = 18,
        castbar_arc_thickness  = 14,
    },
}

function CastBar:ApplyPreset(name)
    local p = CASTBAR_PRESETS[name]
    if not p or not SUF.db then return end
    for k, v in pairs(p) do SUF.db[k] = v end
    SUF.db.castbar_preset = name
    if SUF.player then
        self:Reset(SUF.player)
        if SUF.RefreshAll then pcall(SUF.RefreshAll, SUF) end
    end
end

-- ─── Kick FX (shards rouges en explosion sur interrupt) ──────────────────────
local SHARD_COUNT = 8
function CastBar:SpawnKickShards(data)
    local cb = data and data.castbar
    if not cb or not cb.arcFrame then return end
    if not (SUF.db and SUF.db.castbar_show_kick_fx ~= false) then return end
    local af = cb.arcFrame
    local size = af:GetWidth() or 200
    cb._shardPool = cb._shardPool or {}
    for i = 1, SHARD_COUNT do
        local s = cb._shardPool[i]
        if not s then
            s = af:CreateTexture(nil, "OVERLAY", nil, 4)
            s:SetTexture("Interface\\AddOns\\SphereUnitFrames\\media\\tri_up.png")
            s:SetSize(10, 10)
            s:SetBlendMode("ADD")
            s:SetVertexColor(0.95, 0.18, 0.18, 1)
            cb._shardPool[i] = s
        end
        s:ClearAllPoints()
        s:SetPoint("CENTER", af, "CENTER", 0, 0)
        s:SetAlpha(1)
        s:Show()
        -- Animation : translation radiale + fade
        local angle = (i / SHARD_COUNT) * 2 * math.pi
        local dx = math.cos(angle) * size * 0.6
        local dy = math.sin(angle) * size * 0.6
        local g  = s:CreateAnimationGroup()
        local tr = g:CreateAnimation("Translation")
        tr:SetOffset(dx, dy); tr:SetDuration(0.45)
        local fa = g:CreateAnimation("Alpha")
        fa:SetFromAlpha(1); fa:SetToAlpha(0); fa:SetDuration(0.45)
        local sc = g:CreateAnimation("Scale")
        sc:SetFromScale(1.0, 1.0); sc:SetToScale(0.4, 0.4); sc:SetDuration(0.45)
        g:SetScript("OnFinished", function() s:Hide() end)
        g:Play()
    end
end

-- ─── Mode segments (ticks visibles autour de l'arc) ──────────────────────────
function CastBar:BuildSegments(data)
    local cb = data.castbar
    if not cb or not cb.arcFrame then return end
    if cb._segs then return end
    cb._segs = {}
    local cfg = SUF.db
    local n = cfg.castbar_v8_count or 12
    local arcSize = cb.arcFrame:GetWidth() or 188
    local R = arcSize * 0.5 - 2
    for i = 1, n do
        local t = cb.arcFrame:CreateTexture(nil, "OVERLAY", nil, 3)
        t:SetTexture(SUF.WHITE8x8 or "Interface\\Buttons\\WHITE8X8")
        t:SetSize(3, 8)
        t:SetVertexColor(1, 1, 1, 0.85)
        local angle = (i - 1) / n * 2 * math.pi - math.pi / 2
        t:SetPoint("CENTER", cb.arcFrame, "CENTER",
            math.cos(angle) * R, math.sin(angle) * R)
        local rot = math.deg(angle) - 90
        t:SetRotation(math.rad(rot))
        cb._segs[i] = t
    end
end

function CastBar:UpdateSegments(data, progress)
    local cb = data.castbar
    if not cb or not cb._segs then return end
    local n = #cb._segs
    local lit = math.floor(progress * n + 0.5)
    for i = 1, n do
        local on = (i <= lit)
        cb._segs[i]:SetVertexColor(
            on and cb.color.r or 0.3,
            on and cb.color.g or 0.3,
            on and cb.color.b or 0.3,
            on and 1.0 or 0.4)
    end
end

-- ─── Reset ────────────────────────────────────────────────────────────────────
function CastBar:Reset(data)
    local cb = data and data.castbar
    if not cb then return end
    cb.active    = false
    cb.channeling = false
    cb.spellId   = nil
    if cb.arcFrame  then cb.arcFrame:Hide() end
    if cb.pill      then cb.pill:Hide() end
    if cb.iconFrm   then cb.iconFrm:Hide() end
    if cb.castName  then cb.castName:Hide(); cb.castName:SetText("") end
    if cb.castTime  then cb.castTime:Hide(); cb.castTime:SetText("") end
    if cb.lockTex   then cb.lockTex:SetAlpha(0) end
    if cb.glowRing  then cb.glowRing:SetAlpha(0) end
    if cb.cd        then pcall(cb.cd.Clear, cb.cd) end
    if cb.pill      then cb.pill:SetValue(0) end
end
