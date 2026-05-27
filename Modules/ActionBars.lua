-------------------------------------------------------------------------------
--  SphereUnitFrames · ActionBars.lua
--  Barres d'action triangulaires autour de la sphère joueur.
--
--  Aile droite : bar cfg.actionbar_right_bar  (12 boutons)
--  Aile gauche : bar cfg.actionbar_left_bar   (12 boutons)
--  Layout      : 3 rangées (5-4-3) → triangle pointant vers l'extérieur
--  Masques     : SUF.MEDIA/tri_right.png + tri_left.png (CLAMPTOBLACKADDITIVE)
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

-- ─── Constantes de layout ─────────────────────────────────────────────────────
-- Triangle 5-4-3 (outer → inner, left to right for right wing)
-- Chaque rangée est centrée verticalement sur l'orbe.
-- xFactor = décalage X par rangée (exprimé en unités de taille bouton)
-- yOffset = décalages Y relatifs au centre pour les boutons de la rangée

local TRIANGLE_ROWS_RIGHT = {
    { count=5, xFactor=1.6 },  -- rangée extérieure
    { count=4, xFactor=1.0 },  -- rangée médiane
    { count=3, xFactor=0.4 },  -- rangée intérieure
}

-- Les slots d'action bar WoW : bar N slot S → slot absolu (N-1)*12 + S
local function _actionSlot(bar, startSlot, buttonIndex)
    local baseSlot = (bar - 1) * 12 + (startSlot - 1)
    return baseSlot + buttonIndex
end

-- ─── Création d'un bouton d'action ────────────────────────────────────────────
local _btnCount = 0
local function _createButton(parent, actionSlot, name)
    if InCombatLockdown() then return nil end
    _btnCount = _btnCount + 1
    local btnName = name or ("SUFActionBtn" .. _btnCount)

    -- SecureActionButtonTemplate : cliquable en combat
    local btn = CreateFrame("CheckButton", btnName, parent,
        "SecureActionButtonTemplate, ActionButtonTemplate")
    btn:SetSize(36, 36)
    btn:SetAttribute("type",   "action")
    btn:SetAttribute("action", actionSlot)
    btn:SetAttribute("checkselfcast",   true)
    btn:SetAttribute("checkfocuscast",  true)

    -- Masque triangulaire (si la texture existe)
    local triMaskPath = parent._triMaskPath
    if triMaskPath then
        local mask = btn:CreateMaskTexture()
        pcall(function()
            mask:SetTexture(triMaskPath, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            mask:SetAllPoints(btn)
        end)
        -- Appliquer le masque sur les textures du bouton
        pcall(function()
            local iconTex = btn.icon or btn.Icon or btn:GetNormalTexture()
            if iconTex then iconTex:AddMaskTexture(mask) end
        end)
    end

    -- Keybind text (KEY_BINDING tag)
    if btn.HotKey then
        btn.HotKey:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
        btn.HotKey:SetTextColor(1, 1, 1, 0.85)
    end

    -- Proc glow si activé
    btn._actionSlot = actionSlot

    return btn
end

-- ─── Layout d'une aile ────────────────────────────────────────────────────────
local function _layoutWing(wing, buttons, btnSize, isLeft)
    if not wing then return end
    local idx = 1
    local rows = TRIANGLE_ROWS_RIGHT
    local rootSize = wing._orbSize or 160
    local xBase = rootSize * 0.5 + btnSize * 0.3  -- bord de l'orbe + marge

    for _, row in ipairs(rows) do
        local count   = row.count
        local xOffset = xBase + row.xFactor * btnSize
        local totalH  = (count - 1) * btnSize
        for j = 1, count do
            local btn = buttons[idx]
            if btn then
                local yOffset = totalH * 0.5 - (j - 1) * btnSize
                btn:ClearAllPoints()
                if isLeft then
                    btn:SetPoint("RIGHT", wing, "CENTER", -xOffset, yOffset)
                else
                    btn:SetPoint("LEFT",  wing, "CENTER",  xOffset, yOffset)
                end
            end
            idx = idx + 1
        end
    end
end

-- ─── Init / Prewarm ──────────────────────────────────────────────────────────
function ActionBars:Init()
    local data = SUF.player
    if not data or not data.root then return end
    local cfg = SUF.db
    if not cfg or cfg.actionbars_enabled == false then return end
    if InCombatLockdown() then return end
    if self._leftWing then return end  -- déjà initialisé

    local root   = data.root
    local rootFL = root:GetFrameLevel() or 100
    local size   = cfg.orbSize or 160
    local btnSize = cfg.actionbar_tri_size or 44

    -- ── Aile droite ──────────────────────────────────────────────────────────
    local rightWing = CreateFrame("Frame", "SUFRightWing", root)
    rightWing:SetSize(size, size)
    rightWing:SetPoint("CENTER", root, "CENTER", 0, 0)
    rightWing:SetFrameLevel(rootFL + 6)
    rightWing._orbSize     = size
    rightWing._triMaskPath = (function()
        local p = SUF.MEDIA and (SUF.MEDIA .. "tri_right.png") or nil
        if p then
            local f = CreateFrame("Frame"); f:Hide()
            local t = f:CreateTexture()
            local ok = pcall(t.SetTexture, t, p)
            return ok and p or nil
        end
    end)()

    self._rightButtons = {}
    local rBar   = cfg.actionbar_right_bar   or 3
    local rStart = cfg.actionbar_right_start or 1
    local rCount = cfg.actionbar_right_count or 12
    for i = 1, rCount do
        local slot = _actionSlot(rBar, rStart, i)
        local btn  = _createButton(rightWing, slot, "SUFRightBtn" .. i)
        if btn then
            btn:SetSize(btnSize, btnSize)
            self._rightButtons[i] = btn
        end
    end
    _layoutWing(rightWing, self._rightButtons, btnSize, false)
    self._rightWing = rightWing

    -- ── Aile gauche ──────────────────────────────────────────────────────────
    local leftWing = CreateFrame("Frame", "SUFLeftWing", root)
    leftWing:SetSize(size, size)
    leftWing:SetPoint("CENTER", root, "CENTER", 0, 0)
    leftWing:SetFrameLevel(rootFL + 6)
    leftWing._orbSize     = size
    leftWing._triMaskPath = (function()
        local p = SUF.MEDIA and (SUF.MEDIA .. "tri_left.png") or nil
        if p then
            local f = CreateFrame("Frame"); f:Hide()
            local t = f:CreateTexture()
            local ok = pcall(t.SetTexture, t, p)
            return ok and p or nil
        end
    end)()

    self._leftButtons = {}
    local lBar   = cfg.actionbar_left_bar   or 2
    local lStart = cfg.actionbar_left_start or 1
    local lCount = cfg.actionbar_left_count or 12
    for i = 1, lCount do
        local slot = _actionSlot(lBar, lStart, i)
        local btn  = _createButton(leftWing, slot, "SUFLeftBtn" .. i)
        if btn then
            btn:SetSize(btnSize, btnSize)
            self._leftButtons[i] = btn
        end
    end
    _layoutWing(leftWing, self._leftButtons, btnSize, true)
    self._leftWing = leftWing

    self:SetVisible(cfg.actionbars_enabled ~= false)
end

function ActionBars:Prewarm()
    -- Appelé sur PLAYER_ENTERING_WORLD (hors combat, post-DB)
    if not self._leftWing then
        self:Init()
    end
end

-- ─── Visibilité ──────────────────────────────────────────────────────────────
function ActionBars:SetVisible(visible)
    if self._rightWing then
        if visible then self._rightWing:Show() else self._rightWing:Hide() end
    end
    if self._leftWing then
        if visible then self._leftWing:Show() else self._leftWing:Hide() end
    end
end

-- ─── Proc glow (LibCustomGlow ou NATIVE_RING pulse) ──────────────────────────
function ActionBars:UpdateProcGlow()
    local cfg = SUF.db
    if not cfg or cfg.actionbar_glow_procs == false then return end

    local function glowBtn(btn)
        if not btn or not btn._actionSlot then return end
        local slot = btn._actionSlot
        local ok, usable, nomana = pcall(IsUsableAction, slot)
        if not ok then return end
        local okReady, ready = pcall(IsActionInRange, slot)

        -- Glow simple : teinter l'icône si utilisable + en portée
        local iconTex = btn.icon or btn.Icon
        if not iconTex then return end
        local isReady = usable and (not okReady or ready ~= false)
        if isReady then
            iconTex:SetVertexColor(1, 1, 1, 1)
        else
            iconTex:SetVertexColor(0.5, 0.5, 0.5, 1)
        end
    end

    if self._leftButtons then
        for _, b in ipairs(self._leftButtons) do glowBtn(b) end
    end
    if self._rightButtons then
        for _, b in ipairs(self._rightButtons) do glowBtn(b) end
    end
end

-- ─── Rebuild (après changement de taille orbe) ────────────────────────────────
function ActionBars:Rebuild()
    if InCombatLockdown() then return end
    -- Détruire les ailes existantes
    if self._rightWing then self._rightWing:Hide(); self._rightWing = nil end
    if self._leftWing  then self._leftWing:Hide();  self._leftWing  = nil end
    self._rightButtons = nil
    self._leftButtons  = nil
    self:Init()
end
