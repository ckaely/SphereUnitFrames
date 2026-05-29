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
local _btnCount = 0
local function _createButton(parent, actionSlot, triPath, btnSize, name)
    if InCombatLockdown() then return nil end
    _btnCount = _btnCount + 1
    local btnName = name or ("SUFActionBtn" .. _btnCount)
    local cfg = SUF.db

    local btn = CreateFrame("CheckButton", btnName, parent,
        "SecureActionButtonTemplate, ActionButtonTemplate")
    btn:SetSize(btnSize, btnSize)
    btn:SetAttribute("type",   "action")
    btn:SetAttribute("action", actionSlot)
    btn:SetAttribute("checkselfcast",  true)
    btn:SetAttribute("checkfocuscast", true)
    btn._actionSlot = actionSlot

    -- Masque triangulaire appliqué à l'icône
    local mask = btn:CreateMaskTexture()
    pcall(function()
        mask:SetTexture(triPath, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(btn)
    end)
    btn._triMask = mask

    -- Cadre (bordure) : triangle plein teinté, légèrement plus grand, derrière.
    if cfg and cfg.actionbar_show_frames ~= false then
        local frame = btn:CreateTexture(nil, "BACKGROUND")
        frame:SetTexture(triPath)
        frame:SetPoint("CENTER", btn, "CENTER", 0, 0)
        frame:SetSize(btnSize, btnSize)
        frame:SetVertexColor(0.85, 0.68, 0.20, cfg.actionbar_frame_alpha or 0.95)
        btn._frameTex = frame

        -- Fond sombre interne (laisse apparaître le cadre or sur les bords)
        local fill = btn:CreateTexture(nil, "BORDER")
        fill:SetTexture(triPath)
        fill:SetPoint("CENTER", btn, "CENTER", 0, 0)
        fill:SetSize(btnSize * 0.88, btnSize * 0.88)
        fill:SetVertexColor(0.05, 0.05, 0.07, 0.92)
        btn._fillTex = fill
    end

    -- Icône d'action : masquée triangle, insérée à l'intérieur du cadre
    local iconTex = btn.icon or btn.Icon
    if iconTex then
        iconTex:ClearAllPoints()
        iconTex:SetPoint("CENTER", btn, "CENTER", 0, 0)
        iconTex:SetSize(btnSize * 0.80, btnSize * 0.80)
        iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        pcall(iconTex.AddMaskTexture, iconTex, mask)
    end

    -- Masquer la bordure carrée native de l'ActionButtonTemplate
    local nrm = btn.GetNormalTexture and btn:GetNormalTexture()
    if nrm then nrm:SetAlpha(0) end
    if btn.SetNormalTexture then pcall(btn.SetNormalTexture, btn, "") end
    -- Highlight / pushed : teinter sans casser la forme
    if btn.GetHighlightTexture and btn:GetHighlightTexture() then
        pcall(function()
            local h = btn:GetHighlightTexture()
            h:SetAllPoints(btn)
            pcall(h.AddMaskTexture, h, mask)
        end)
    end
    if btn.GetPushedTexture and btn:GetPushedTexture() then
        pcall(function()
            local pT = btn:GetPushedTexture()
            pT:SetAllPoints(btn)
            pcall(pT.AddMaskTexture, pT, mask)
        end)
    end

    -- Cooldown : masquer en triangle si possible
    if btn.cooldown then
        pcall(function() btn.cooldown:SetAllPoints(btn) end)
    end

    -- Keybind
    if btn.HotKey then
        btn.HotKey:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
        btn.HotKey:SetTextColor(1, 1, 1, 0.85)
        btn.HotKey:ClearAllPoints()
        btn.HotKey:SetPoint("TOP", btn, "TOP", 0, up and -2 or -8)
    end
    if btn.Count then
        btn.Count:ClearAllPoints()
        btn.Count:SetPoint("BOTTOM", btn, "BOTTOM", 0, up and 6 or 2)
    end

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
end

-- ─── Pilotage icône / cooldown / état ─────────────────────────────────────────
-- ActionButtonTemplate ne met PAS à jour l'icône tout seul : on la pilote via
-- GetActionTexture / GetActionCooldown sur events.
local function _updateButton(btn)
    if not btn or not btn._actionSlot then return end
    local slot   = btn._actionSlot
    local iconTex = btn.icon or btn.Icon
    local tex
    local ok = pcall(function() tex = GetActionTexture(slot) end)
    if iconTex then
        if ok and tex then
            iconTex:SetTexture(tex)
            iconTex:SetAlpha(1)
            if btn._fillTex then btn._fillTex:SetAlpha(0.35) end
        else
            iconTex:SetTexture(nil)
            iconTex:SetAlpha(0)
            if btn._fillTex then btn._fillTex:SetAlpha(1) end  -- triangle plein si slot vide
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
end

function ActionBars:UpdateAll()
    if self._leftButtons  then for _, b in ipairs(self._leftButtons)  do _updateButton(b) end end
    if self._rightButtons then for _, b in ipairs(self._rightButtons) do _updateButton(b) end end
end

-- Frame d'events (créé une fois)
function ActionBars:_ensureEvents()
    if self._evt then return end
    local e = CreateFrame("Frame")
    e:RegisterEvent("PLAYER_ENTERING_WORLD")
    e:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
    e:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
    e:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
    e:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
    e:RegisterEvent("PLAYER_REGEN_ENABLED")
    e:SetScript("OnEvent", function(_, ev, arg1)
        if ev == "ACTIONBAR_SLOT_CHANGED" then
            -- maj ciblée si possible
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
