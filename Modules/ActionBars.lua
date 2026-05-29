-------------------------------------------------------------------------------
--  SphereUnitFrames · ActionBars.lua
--  Barres d'action triangulaires autour de la sphère joueur.
--
--  Modèle (voir schéma utilisateur) :
--    • Chaque TRIANGLE = 1 bouton d'action.
--    • Le layout est défini par le nombre de boutons PAR COLONNE.
--      ex: "7,5,3,1" → 4 colonnes décroissantes = triangle pointant vers
--      l'extérieur (16 boutons). Colonne 1 = la plus proche de l'orbe.
--    • Triangles △/▽ alternés (damier) pour tesseller proprement.
--    • Masques : SUF.MEDIA/tri_up.png + tri_down.png.
--    • Cadre : triangle plein teinté or derrière l'icône (bordure).
--
--  Slots WoW : remplis séquentiellement à partir de la barre choisie
--    (déborde sur la barre suivante si total > 12 — slots absolus contigus).
--
--  Combat safety :
--    • SecureActionButtonTemplate → cliquable en combat
--    • CreateFrame uniquement hors combat (gardes InCombatLockdown)
--    • ActionBars:Prewarm() appelé sur PLAYER_ENTERING_WORLD
-------------------------------------------------------------------------------

local ADDON = "SphereUnitFrames"
local SUF   = _G[ADDON]
if not SUF then return end

SUF.ActionBars = SUF.ActionBars or {}
local ActionBars = SUF.ActionBars

ActionBars._leftButtons  = nil
ActionBars._rightButtons = nil
ActionBars._leftWing     = nil
ActionBars._rightWing    = nil

local function SNPM(n)
    return (SUF.MEDIA or "Interface\\AddOns\\SphereUnitFrames\\media\\") .. n
end
local TRI_UP    = SNPM("tri_up.png")
local TRI_DOWN  = SNPM("tri_down.png")
local TRI_LEFT  = SNPM("tri_left.png")    -- ▷ base à gauche, pointe à DROITE
local TRI_RIGHT = SNPM("tri_right.png")   -- ◁ base à droite, pointe à GAUCHE

-- ─── Parsing colonnes ─────────────────────────────────────────────────────────
-- "7,5,3,1" → { 7, 5, 3, 1 }
local function _parseColumns(str)
    local cols = {}
    if type(str) ~= "string" then str = "7,5,3,1" end
    for n in str:gmatch("%d+") do
        local v = tonumber(n)
        if v and v > 0 then cols[#cols+1] = math.min(v, 12) end
    end
    if #cols == 0 then cols = {7, 5, 3, 1} end
    return cols
end

-- Slot d'action absolu WoW (1..120) — contigu à travers les barres.
local function _absSlot(baseBar, startSlot, seqIndex)
    return (baseBar - 1) * 12 + (startSlot - 1) + seqIndex  -- seqIndex 1-based
end

-- ─── Création d'un bouton triangulaire ────────────────────────────────────────
-- ─── Cast tint : progression orange → vert sur le fill du triangle ──────────
-- Le triangle du sort en cours passe progressivement d'orange à vert.
-- Pour les instants, c'est un mini 0.30 s. Pour un cast time, la transition
-- couvre la durée réelle du cast.
local CAST_R0, CAST_G0, CAST_B0 = 1.00, 0.50, 0.05   -- orange (début)
local CAST_R1, CAST_G1, CAST_B1 = 0.20, 0.95, 0.25   -- vert (fin)
local CAST_A                    = 0.88
local FILL_REST_R, FILL_REST_G, FILL_REST_B, FILL_REST_A = 0.03, 0.03, 0.05, 0.55

local function _startCastTint(btn, duration)
    if not btn then return end
    btn._castTint = { t0 = GetTime(), dur = math.max(0.25, duration or 0.30) }
end

local function _stopCastTint(btn)
    if not btn then return end
    btn._castTint = nil
    -- Le prochain _updateButton recolorera selon la couleur dominante du sort.
    -- Reset transitoire vers le sombre par défaut en attendant.
    if btn._fillTex then
        btn._fillTex:SetVertexColor(FILL_REST_R, FILL_REST_G, FILL_REST_B, FILL_REST_A)
    end
    -- Force la mise à jour pour repeindre la couleur du sort
    if SUF.ActionBars then SUF.ActionBars:UpdateAll() end
end

local function _completeCastTint(btn)
    -- Snap vert + maintien court avant fade
    if not btn or not btn._castTint then return end
    btn._castTint.t0  = GetTime() - btn._castTint.dur
    btn._castTint.hold = GetTime() + 0.18
end

local function _tickCastTint(btn)
    if not (btn and btn._castTint and btn._fillTex) then return end
    local now = GetTime()
    local p = (now - btn._castTint.t0) / btn._castTint.dur
    if p >= 1 then
        btn._fillTex:SetVertexColor(CAST_R1, CAST_G1, CAST_B1, CAST_A)
        if btn._castTint.hold and now > btn._castTint.hold then
            _stopCastTint(btn)
        elseif not btn._castTint.hold then
            btn._castTint.hold = now + 0.12
        end
        return
    end
    if p < 0 then p = 0 end
    local r = CAST_R0 + (CAST_R1 - CAST_R0) * p
    local g = CAST_G0 + (CAST_G1 - CAST_G0) * p
    local b = CAST_B0 + (CAST_B1 - CAST_B0) * p
    btn._fillTex:SetVertexColor(r, g, b, CAST_A)
end

-- ─── TriCooldown : spark qui parcourt le périmètre du triangle ────────────────
local function _attachTriCooldown(btn, triPath, btnSize)
    local cfg = SUF.db
    local sz  = btnSize * (cfg.actionbar_cd_runner_size or 0.32)
    local spark = btn:CreateTexture(nil, "OVERLAY", nil, 7)
    spark:SetTexture("Interface\\Cooldown\\ping4")
    spark:SetBlendMode("ADD")
    spark:SetSize(sz, sz)
    spark:SetVertexColor(
        cfg.actionbar_cd_runner_r or 1,
        cfg.actionbar_cd_runner_g or 0.85,
        cfg.actionbar_cd_runner_b or 0.30, 1)
    spark:Hide()
    btn._cdSpark = spark

    local half = btnSize * 0.5
    local v1x, v1y, v2x, v2y, v3x, v3y
    if triPath == TRI_LEFT then        -- ▷ (pointe à droite)
        v1x, v1y = -half,  half
        v2x, v2y = -half, -half
        v3x, v3y =  half,  0
    else                                -- ◁ (pointe à gauche)
        v1x, v1y =  half,  half
        v2x, v2y =  half, -half
        v3x, v3y = -half,  0
    end
    local function dist(ax, ay, bx, by)
        local dx, dy = bx - ax, by - ay
        return math.sqrt(dx * dx + dy * dy)
    end
    local L1 = dist(v1x, v1y, v3x, v3y)   -- v1→v3 (diag haute vers apex)
    local L2 = dist(v3x, v3y, v2x, v2y)   -- v3→v2 (diag basse depuis apex)
    local L3 = dist(v2x, v2y, v1x, v1y)   -- v2→v1 (vertical retour)
    local P  = L1 + L2 + L3

    btn._cdTick = 0
    btn:HookScript("OnUpdate", function(self, elapsed)
        -- Cast tint (orange → vert) : tick chaque frame, non throttlé
        _tickCastTint(self)
        if not SUF.db or SUF.db.actionbar_cd_runner == false then
            if spark:IsShown() then spark:Hide() end
            return
        end
        self._cdTick = (self._cdTick or 0) + elapsed
        if self._cdTick < 0.05 then return end
        self._cdTick = 0
        if not self._actionSlot then return end
        local ok, start, dur, enable = pcall(GetActionCooldown, self._actionSlot)
        if not ok or not (start and dur and dur > 0.5) or (enable == 0) then
            if spark:IsShown() then spark:Hide() end
            return
        end
        local now = GetTime()
        local t = (now - start) / dur
        if t >= 1 or t < 0 then spark:Hide(); return end
        local d = t * P
        local x, y
        if d < L1 then
            local f = d / L1
            x = v1x + (v3x - v1x) * f; y = v1y + (v3y - v1y) * f
        elseif d < L1 + L2 then
            local f = (d - L1) / L2
            x = v3x + (v2x - v3x) * f; y = v3y + (v2y - v3y) * f
        else
            local f = (d - L1 - L2) / L3
            x = v2x + (v1x - v2x) * f; y = v2y + (v1y - v2y) * f
        end
        spark:ClearAllPoints()
        spark:SetPoint("CENTER", self, "CENTER", x, y)
        spark:Show()
    end)
end

-- ─── Devinette couleur dominante du sort (via heuristique sur chemin d'icône) ─
local SCHOOL_COLORS = {
    fire    = {1.00, 0.55, 0.15},
    frost   = {0.40, 0.80, 1.00},
    nature  = {0.30, 1.00, 0.45},
    holy    = {1.00, 0.92, 0.45},
    shadow  = {0.55, 0.22, 0.75},
    arcane  = {0.78, 0.42, 1.00},
    blood   = {0.85, 0.10, 0.15},
    earth   = {0.55, 0.45, 0.20},
    physical= {0.75, 0.68, 0.40},
}
local function _guessSpellColor(iconPath)
    if not iconPath then return SCHOOL_COLORS.physical end
    local p = tostring(iconPath):lower()
    if p:find("fire") or p:find("flame") or p:find("burn") or p:find("inferno") then return SCHOOL_COLORS.fire end
    if p:find("frost") or p:find("ice") or p:find("freeze") or p:find("blizzard") then return SCHOOL_COLORS.frost end
    if p:find("nature") or p:find("heal") or p:find("druid") or p:find("nourish") or p:find("rejuv") then return SCHOOL_COLORS.nature end
    if p:find("holy") or p:find("light") or p:find("paladin") or p:find("renew") then return SCHOOL_COLORS.holy end
    if p:find("shadow") or p:find("warlock") or p:find("priest") or p:find("death") then return SCHOOL_COLORS.shadow end
    if p:find("arcane") or p:find("mage") or p:find("polymorph") then return SCHOOL_COLORS.arcane end
    if p:find("blood") or p:find("dk_") then return SCHOOL_COLORS.blood end
    if p:find("earth") or p:find("rock") or p:find("stone") then return SCHOOL_COLORS.earth end
    return SCHOOL_COLORS.physical
end

-- Décalage du centroïde du triangle par rapport au centre de la boîte.
-- ▷ (TRI_LEFT) : centroïde à (btnSize/3, btnSize/2) → décalage X = -btnSize/6
-- ◁ (TRI_RIGHT): centroïde à (2btnSize/3, btnSize/2) → décalage X = +btnSize/6
local function _centroidOffset(triPath, btnSize)
    if triPath == TRI_LEFT  then return -btnSize / 6, 0 end
    if triPath == TRI_RIGHT then return  btnSize / 6, 0 end
    if triPath == TRI_UP    then return 0, -btnSize / 6 end
    if triPath == TRI_DOWN  then return 0,  btnSize / 6 end
    return 0, 0
end

local _btnCount = 0
local function _createButton(parent, actionSlot, triPath, btnSize, name)
    if InCombatLockdown() then return nil end
    _btnCount = _btnCount + 1
    local btnName = name or ("SUFActionBtn" .. _btnCount)
    local cfg = SUF.db

    -- ActionBarButtonTemplate = template canonique retail : secure + icon driver
    -- + cooldown + glow + range. On masque toutes les sous-textures carrées.
    local btn = CreateFrame("CheckButton", btnName, parent,
        "SecureActionButtonTemplate, ActionBarButtonTemplate")
    btn:SetSize(btnSize, btnSize)
    btn:SetAttribute("type",   "action")
    btn:SetAttribute("action", actionSlot)
    btn:SetAttribute("checkselfcast",  true)
    btn:SetAttribute("checkfocuscast", true)
    btn:RegisterForClicks("AnyUp", "AnyDown")
    btn:RegisterForDrag("LeftButton")
    btn._actionSlot = actionSlot
    btn._triPath    = triPath

    -- Masque triangulaire appliqué à l'icône
    local mask = btn:CreateMaskTexture()
    pcall(function()
        mask:SetTexture(triPath, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(btn)
    end)
    btn._triMask = mask

    -- Cadre triangulaire : SOMBRE TRANSPARENT par défaut (subtil), pas jaune.
    -- Le jaune est réservé au flash de cast (quand on lance le sort).
    if cfg and cfg.actionbar_show_frames ~= false then
        local frame = btn:CreateTexture(nil, "BACKGROUND")
        frame:SetTexture(triPath)
        frame:SetPoint("CENTER", btn, "CENTER", 0, 0)
        frame:SetSize(btnSize, btnSize)
        frame:SetVertexColor(0.18, 0.18, 0.22, (cfg.actionbar_frame_alpha or 0.55))
        btn._frameTex = frame

        -- Fond sombre transparent interne
        local fill = btn:CreateTexture(nil, "BORDER")
        fill:SetTexture(triPath)
        fill:SetPoint("CENTER", btn, "CENTER", 0, 0)
        fill:SetSize(btnSize * 0.92, btnSize * 0.92)
        fill:SetVertexColor(0.03, 0.03, 0.05, 0.55)
        btn._fillTex = fill
    end

    -- Icône d'action : on UTILISE celle du template (qui pilote l'affichage
    -- automatiquement). On la centre au CENTROÏDE et on la masque triangle.
    local cx, cy = _centroidOffset(triPath, btnSize)
    btn._centroidX = cx
    btn._centroidY = cy
    btn._btnSize   = btnSize
    local iconTex = btn.icon or btn.Icon
    if iconTex then
        iconTex:ClearAllPoints()
        iconTex:SetPoint("CENTER", btn, "CENTER", cx, cy)
        iconTex:SetSize(btnSize * 0.72, btnSize * 0.72)
        iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        iconTex:SetDrawLayer("ARTWORK", 3)
        pcall(iconTex.AddMaskTexture, iconTex, mask)
        iconTex:SetAlpha(1)
        iconTex:Show()
    end

    -- (L'animation de cast est désormais une PROGRESSION de couleur orange→vert
    -- sur le fill du triangle, gérée par _tickCastTint dans l'OnUpdate.)

    -- ── Masquer TOUTES les sous-textures natives carrées ─────────────────
    -- ActionBarButtonTemplate insère beaucoup d'éléments (Border, SlotArt,
    -- NewActionTexture, IconMask circulaire Blizzard…) qui cassent le rendu.
    local kill = {
        "NormalTexture", "PushedTexture", "CheckedTexture", "HighlightTexture",
        "Border", "Flash", "FlyoutArrow", "FlyoutBorder", "FlyoutBorderShadow",
        "SlotArt", "SlotBackground", "NewActionTexture", "SpellHighlightTexture",
        "IconMask", "SlotHighlightTexture",
    }
    for _, name in ipairs(kill) do
        local t = btn[name]
        if t then pcall(function() t:SetAlpha(0); t:Hide() end) end
    end
    -- Variantes Get* (méthodes)
    for _, m in ipairs({"GetNormalTexture","GetPushedTexture","GetCheckedTexture","GetHighlightTexture"}) do
        pcall(function()
            local t = btn[m] and btn[m](btn)
            if t then t:SetAlpha(0) end
        end)
    end
    pcall(btn.SetNormalTexture, btn, "")
    pcall(btn.SetPushedTexture, btn, "")
    pcall(btn.SetHighlightTexture, btn, "")

    -- Highlight personnalisé (triangle teinté)
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture(triPath)
    hl:SetAllPoints(btn)
    hl:SetBlendMode("ADD")
    hl:SetVertexColor(1, 1, 1, 0.18)
    btn._highlight = hl

    -- Cooldown : masquer en triangle si possible
    if btn.cooldown then
        pcall(function()
            btn.cooldown:SetAllPoints(btn)
            btn.cooldown:SetSwipeTexture("Interface\\Cooldown\\ping4")
            if btn.cooldown.SetUseCircularEdge then btn.cooldown:SetUseCircularEdge(true) end
            if btn.cooldown.SetDrawBling     then btn.cooldown:SetDrawBling(false) end
            btn.cooldown:SetSwipeColor(0, 0, 0, 0.65)
            pcall(btn.cooldown.AddMaskTexture, btn.cooldown, mask)
        end)
    end

    -- Keybind (positionné au sommet de la zone triangulaire visible)
    if btn.HotKey then
        local kbR = cfg.actionbar_keybind_r or 1
        local kbG = cfg.actionbar_keybind_g or 1
        local kbB = cfg.actionbar_keybind_b or 0.8
        local kbA = cfg.actionbar_keybind_alpha or 0.95
        local kbSize = cfg.actionbar_keybind_size or 9
        btn.HotKey:SetFont("Fonts\\FRIZQT__.TTF", kbSize, "OUTLINE")
        btn.HotKey:SetTextColor(kbR, kbG, kbB, kbA)
        btn.HotKey:ClearAllPoints()
        btn.HotKey:SetPoint("TOP", btn, "TOP", cx, -2)
        btn.HotKey:SetShown(cfg.actionbar_show_keybinds ~= false)
    end
    if btn.Count then
        btn.Count:ClearAllPoints()
        btn.Count:SetPoint("BOTTOM", btn, "BOTTOM", cx, 3)
    end

    -- ── Cooldown triangulaire (edge runner) ─────────────────────────────
    _attachTriCooldown(btn, triPath, btnSize)

    -- ── Drag & drop (placer/déplacer un sort sur le bouton) ──────────────
    btn:SetScript("OnDragStart", function(self)
        if InCombatLockdown() then return end
        PickupAction(self._actionSlot)
        if SUF.ActionBars then SUF.ActionBars:UpdateAll() end
    end)
    btn:SetScript("OnReceiveDrag", function(self)
        if InCombatLockdown() then return end
        PlaceAction(self._actionSlot)
        if SUF.ActionBars then SUF.ActionBars:UpdateAll() end
    end)
    -- En complément, OnClick déjà géré par le secure framework.

    return btn
end

-- ─── Layout d'une aile : tessellation ◁▷ jointive, pointe vers l'extérieur ─────
-- Chaque colonne = une bande verticale de triangles ▷◁ alternés (pas vertical
-- = demi-base) qui s'emboîtent. Les colonnes avancent d'une pleine largeur de
-- triangle (bandes adjacentes bord à bord) → grand triangle plein qui pointe
-- vers l'extérieur, base large côté sphère.
-- columns : { 7, 5, 3, 1 } (boutons par colonne, décroissant = pointe).
local function _layoutWing(wing, buttons, columns, btnSize, isLeft)
    if not wing then return end
    local cfg     = SUF.db
    local spacing = cfg.actionbar_tri_spacing or 0.96
    local gap     = cfg.actionbar_gap or 6
    local orbR    = (wing._orbSize or 160) * 0.5

    local s       = btnSize * spacing       -- largeur de bande / taille triangle
    local stepY   = s * 0.5                  -- pas vertical = demi-base (emboîtement)
    local baseL   = orbR + gap               -- bord gauche de la 1re colonne

    local idx = 1
    for c = 1, #columns do
        local count = columns[c]
        local xc = baseL + (c - 1) * s + s * 0.5
        if isLeft then xc = -xc end
        for j = 1, count do
            local btn = buttons[idx]
            if btn then
                local yOff = ((count - 1) * 0.5 - (j - 1)) * stepY
                btn:ClearAllPoints()
                btn:SetPoint("CENTER", wing, "CENTER", xc, yOff)
            end
            idx = idx + 1
        end
    end
end

-- ─── Construire une aile complète ─────────────────────────────────────────────
local function _buildWing(name, root, rootFL, size, baseBar, startSlot, columns, btnSize, isLeft)
    local wing = CreateFrame("Frame", name, root)
    wing:SetSize(size, size)
    wing:SetPoint("CENTER", root, "CENTER", 0, 0)
    wing:SetFrameLevel(rootFL + 6)
    wing._orbSize = size

    local buttons = {}
    -- Tessellation ◁▷ : dans chaque bande, alternance triangle base-gauche /
    -- base-droite (décalés d'une demi-base) → ils s'emboîtent.
    -- Aile droite (pointe à droite) : j pair = ▷ (base gauche, tri_left),
    --   j impair = ◁ (base droite, tri_right). Aile gauche = miroir.
    local idx = 1
    for c = 1, #columns do
        local count = columns[c]
        for j = 1, count do
            local even = ((j - 1) % 2 == 0)
            local triPath
            if isLeft then triPath = even and TRI_RIGHT or TRI_LEFT
            else            triPath = even and TRI_LEFT  or TRI_RIGHT end
            local slot = _absSlot(baseBar, startSlot, idx)
            local btn  = _createButton(wing, slot, triPath, btnSize, name .. "B" .. idx)
            if btn then buttons[idx] = btn end
            idx = idx + 1
        end
    end
    _layoutWing(wing, buttons, columns, btnSize, isLeft)
    return wing, buttons
end

-- ─── Init ──────────────────────────────────────────────────────────────────────
function ActionBars:Init()
    local data = SUF.player
    if not data or not data.root then return end
    local cfg = SUF.db
    if not cfg or cfg.actionbars_enabled == false then return end
    if InCombatLockdown() then return end
    if self._leftWing then return end

    local root    = data.root
    local rootFL  = root:GetFrameLevel() or 100
    local size    = cfg.orbSize or 160
    local btnSize = cfg.actionbar_tri_size or 40

    local rCols = _parseColumns(cfg.actionbar_right_columns or "7,5,3,1")
    local lCols = _parseColumns(cfg.actionbar_left_columns  or "7,5,3,1")

    self._rightWing, self._rightButtons = _buildWing(
        "SUFRightWing", root, rootFL, size,
        cfg.actionbar_right_bar or 6, cfg.actionbar_right_start or 1,
        rCols, btnSize, false)

    self._leftWing, self._leftButtons = _buildWing(
        "SUFLeftWing", root, rootFL, size,
        cfg.actionbar_left_bar or 2, cfg.actionbar_left_start or 1,
        lCols, btnSize, true)

    self:SetVisible(cfg.actionbars_enabled ~= false)
    self:_ensureEvents()
    self:UpdateAll()
end

function ActionBars:Prewarm()
    if not self._leftWing then self:Init() end
    self:HideBlizzardUI()
end

-- ─── Masquer l'UI Blizzard remplacée par SUF ─────────────────────────────────
function ActionBars:HideBlizzardUI()
    local cfg = SUF.db
    if not cfg then return end
    local hide = SUF._blizzHidden
    if not hide then
        hide = CreateFrame("Frame", nil, UIParent)
        hide:Hide()
        SUF._blizzHidden = hide
    end
    local function kill(name)
        local f = _G[name]
        if not f then return end
        pcall(function()
            f:UnregisterAllEvents()
            f:Hide()
            f:SetParent(hide)
            if f.HookScript then
                f:HookScript("OnShow", function(self) self:Hide() end)
            end
        end)
    end
    if cfg.hide_blizzard_action_bars then
        for _, n in ipairs({
            "MainMenuBar","MainMenuBarArtFrame","OverrideActionBar",
            "MultiBarBottomLeft","MultiBarBottomRight",
            "MultiBarLeft","MultiBarRight",
            "MultiBar5","MultiBar6","MultiBar7",
            "StanceBarFrame","PossessBarFrame","PetActionBarFrame",
        }) do kill(n) end
    end
    if cfg.hide_blizzard_xp_bar then
        for _, n in ipairs({
            "StatusTrackingBarManager",
            "MainStatusTrackingBarContainer",
            "SecondaryStatusTrackingBarContainer",
            "ExpBar",
        }) do kill(n) end
    end
    if cfg.hide_blizzard_micromenu then
        for _, n in ipairs({
            "MicroButtonAndBagsBar","MicroMenuContainer","BagsBar",
        }) do kill(n) end
    end
end

-- ─── Pilotage icône / cooldown / état ─────────────────────────────────────────
-- ActionButtonTemplate ne met PAS à jour l'icône tout seul : on la pilote via
-- GetActionTexture / GetActionCooldown sur events.
local function _updateButton(btn)
    if not btn or not btn._actionSlot then return end
    local slot    = btn._actionSlot
    local iconTex = btn.icon or btn.Icon
    local tex
    local ok = pcall(function() tex = GetActionTexture(slot) end)
    if iconTex then
        if ok and tex then
            iconTex:SetTexture(tex)
            iconTex:SetAlpha(1)
            iconTex:Show()
            -- Force le ré-anchorage triangulaire (le template tente de le réécrire)
            iconTex:ClearAllPoints()
            iconTex:SetPoint("CENTER", btn, "CENTER", btn._centroidX or 0, btn._centroidY or 0)
            iconTex:SetSize((btn._btnSize or 40) * 0.72, (btn._btnSize or 40) * 0.72)
            iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            if btn._triMask then pcall(iconTex.AddMaskTexture, iconTex, btn._triMask) end
            -- Fade intérieur couleur dominante : camoufle les coins du triangle
            -- (en l'absence de cast en cours).
            if btn._fillTex and not btn._castTint then
                local r, g, b = unpack(_guessSpellColor(tex))
                btn._fillTex:SetVertexColor(r * 0.50, g * 0.50, b * 0.50, 0.62)
            end
        else
            iconTex:SetTexture(nil)
            iconTex:SetAlpha(0)
            if btn._fillTex and not btn._castTint then
                btn._fillTex:SetVertexColor(0.03, 0.03, 0.05, 0.55)
            end
        end
    end
    -- Count (charges / consommables)
    if btn.Count then
        local cnt
        pcall(function() cnt = GetActionCount(slot) end)
        local has
        pcall(function() has = IsConsumableAction(slot) or IsStackableAction(slot) end)
        btn.Count:SetText((has and cnt and cnt > 0) and tostring(cnt) or "")
    end
    -- Cooldown
    if btn.cooldown then
        pcall(function()
            local start, dur, enable = GetActionCooldown(slot)
            if start and dur and dur > 0 and enable and enable ~= 0 then
                btn.cooldown:SetCooldown(start, dur)
            else
                btn.cooldown:Clear()
            end
        end)
    end
    -- Range check + tint
    if iconTex and SUF.db and SUF.db.actionbar_range_check ~= false then
        local _, inRange = pcall(IsActionInRange, slot)
        if inRange == false then
            iconTex:SetVertexColor(1, 0.35, 0.35, 1)   -- rouge = hors portée
            return
        end
    end
    -- Usable check
    if iconTex then
        local ok, usable, nomana = pcall(IsUsableAction, slot)
        if ok and usable then
            iconTex:SetVertexColor(1, 1, 1, 1)
        elseif ok and nomana then
            iconTex:SetVertexColor(0.5, 0.5, 1.0, 1)   -- bleu = mana insuffisant
        else
            iconTex:SetVertexColor(0.4, 0.4, 0.4, 1)   -- gris = inutilisable
        end
    end
    -- Proc glow (overlay natif Blizzard)
    if SUF.db and SUF.db.actionbar_glow_procs ~= false and ActionButton_ShowOverlayGlow then
        local hasProc = false
        pcall(function()
            local id = btn.action and select(2, GetActionInfo(slot))
            if id and IsSpellOverlayed then hasProc = IsSpellOverlayed(id) end
        end)
        if hasProc then pcall(ActionButton_ShowOverlayGlow, btn)
        elseif ActionButton_HideOverlayGlow then pcall(ActionButton_HideOverlayGlow, btn) end
    end
end

function ActionBars:UpdateAll()
    if self._leftButtons  then for _, b in ipairs(self._leftButtons)  do _updateButton(b) end end
    if self._rightButtons then for _, b in ipairs(self._rightButtons) do _updateButton(b) end end
end

-- ─── Cast progression (orange→vert sur le triangle du sort) ──────────────────
-- Match du spellID au slot (gère sort + macro).
local function _matchSpell(b, spellID)
    if not b or not b._actionSlot then return false end
    local ok, atype, id = pcall(GetActionInfo, b._actionSlot)
    if not ok then return false end
    if atype == "spell" and id == spellID then return true end
    if atype == "macro" and id then
        local okM, macroSpellID = pcall(GetMacroSpell, id)
        if okM and macroSpellID == spellID then return true end
    end
    return false
end

function ActionBars:_StartCastProgress(spellID, duration)
    if not spellID then return end
    local function check(b) if _matchSpell(b, spellID) then _startCastTint(b, duration) end end
    if self._leftButtons  then for _, b in ipairs(self._leftButtons)  do check(b) end end
    if self._rightButtons then for _, b in ipairs(self._rightButtons) do check(b) end end
end

function ActionBars:_SucceededSpell(spellID)
    if not spellID then return end
    local function check(b)
        if _matchSpell(b, spellID) then
            if b._castTint then
                _completeCastTint(b)        -- cast time : snap au vert et fade
            else
                _startCastTint(b, 0.30)     -- instant : mini transition orange→vert
            end
        end
    end
    if self._leftButtons  then for _, b in ipairs(self._leftButtons)  do check(b) end end
    if self._rightButtons then for _, b in ipairs(self._rightButtons) do check(b) end end
end

function ActionBars:_StopSpell(spellID)
    if not spellID then return end
    local function check(b) if _matchSpell(b, spellID) then _stopCastTint(b) end end
    if self._leftButtons  then for _, b in ipairs(self._leftButtons)  do check(b) end end
    if self._rightButtons then for _, b in ipairs(self._rightButtons) do check(b) end end
end

-- Frame d'events (créé une fois)
function ActionBars:_ensureEvents()
    if self._evt then return end
    local e = CreateFrame("Frame")
    e:RegisterEvent("PLAYER_ENTERING_WORLD")
    e:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
    e:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
    e:RegisterEvent("ACTIONBAR_UPDATE_USABLE")
    e:RegisterEvent("ACTIONBAR_UPDATE_STATE")
    e:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
    e:RegisterEvent("ACTIONBAR_UPDATE_RANGE")
    e:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
    e:RegisterEvent("SPELL_UPDATE_USABLE")
    e:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    e:RegisterEvent("SPELL_ACTIVATION_OVERLAY_SHOW")
    e:RegisterEvent("SPELL_ACTIVATION_OVERLAY_HIDE")
    e:RegisterEvent("PLAYER_REGEN_ENABLED")
    -- Progression de cast (orange → vert) sur le triangle du sort
    e:RegisterUnitEvent("UNIT_SPELLCAST_START",           "player")
    e:RegisterUnitEvent("UNIT_SPELLCAST_STOP",            "player")
    e:RegisterUnitEvent("UNIT_SPELLCAST_FAILED",          "player")
    e:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED",     "player")
    e:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED",       "player")
    e:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START",   "player")
    e:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP",    "player")
    e:SetScript("OnEvent", function(_, ev, arg1, _, arg3)
        if ev == "UNIT_SPELLCAST_START" then
            -- récupère la durée du cast
            local dur
            pcall(function()
                local _, _, _, sMS, eMS = UnitCastingInfo("player")
                if sMS and eMS then dur = (eMS - sMS) / 1000 end
            end)
            if SUF.ActionBars then SUF.ActionBars:_StartCastProgress(arg3, dur) end
        elseif ev == "UNIT_SPELLCAST_CHANNEL_START" then
            local dur
            pcall(function()
                local _, _, _, sMS, eMS = UnitChannelInfo("player")
                if sMS and eMS then dur = (eMS - sMS) / 1000 end
            end)
            if SUF.ActionBars then SUF.ActionBars:_StartCastProgress(arg3, dur) end
        elseif ev == "UNIT_SPELLCAST_SUCCEEDED" then
            if SUF.ActionBars then SUF.ActionBars:_SucceededSpell(arg3) end
        elseif ev == "UNIT_SPELLCAST_STOP"
            or ev == "UNIT_SPELLCAST_FAILED"
            or ev == "UNIT_SPELLCAST_INTERRUPTED"
            or ev == "UNIT_SPELLCAST_CHANNEL_STOP" then
            if SUF.ActionBars then SUF.ActionBars:_StopSpell(arg3) end
        elseif ev == "ACTIONBAR_SLOT_CHANGED" then
            if SUF.ActionBars then SUF.ActionBars:UpdateAll() end
        else
            if SUF.ActionBars then SUF.ActionBars:UpdateAll() end
        end
    end)
    self._evt = e
end

-- ─── Visibilité ──────────────────────────────────────────────────────────────
function ActionBars:SetVisible(visible)
    if self._rightWing then if visible then self._rightWing:Show() else self._rightWing:Hide() end end
    if self._leftWing  then if visible then self._leftWing:Show()  else self._leftWing:Hide()  end end
end

-- ─── Proc glow / range tint ────────────────────────────────────────────────────
function ActionBars:UpdateProcGlow()
    local cfg = SUF.db
    if not cfg or cfg.actionbar_glow_procs == false then return end

    local function glowBtn(btn)
        if not btn or not btn._actionSlot then return end
        local slot = btn._actionSlot
        local ok, usable = pcall(IsUsableAction, slot)
        if not ok then return end
        local okR, inRange = pcall(IsActionInRange, slot)
        local iconTex = btn.icon or btn.Icon
        if not iconTex then return end
        local ready = usable and (not okR or inRange ~= false)
        if ready then iconTex:SetVertexColor(1, 1, 1, 1)
        else          iconTex:SetVertexColor(0.5, 0.5, 0.5, 1) end
    end

    if self._leftButtons  then for _, b in ipairs(self._leftButtons)  do glowBtn(b) end end
    if self._rightButtons then for _, b in ipairs(self._rightButtons) do glowBtn(b) end end
end

-- ─── Rebuild (après changement layout/taille) ─────────────────────────────────
function ActionBars:Rebuild()
    if InCombatLockdown() then return end
    if self._rightWing then self._rightWing:Hide(); self._rightWing = nil end
    if self._leftWing  then self._leftWing:Hide();  self._leftWing  = nil end
    self._rightButtons = nil
    self._leftButtons  = nil
    self:Init()
end
