-------------------------------------------------------------------------------
--  SphereUnitFrames · PSUI.lua
--  Panneau de configuration — chargé EN DERNIER (après tous les modules).
--  Commande : /suf ui   ou   /sufui
--
--  Architecture : frame principal + tabs + content frames par section.
--  Widgets : Sliders, Checkboxes, Dropdowns basiques (natifs WoW, sans AceGUI).
-------------------------------------------------------------------------------

local ADDON = "SphereUnitFrames"
local SUF   = _G[ADDON]
if not SUF then return end

SUF.PSUI = SUF.PSUI or {}
local PSUI = SUF.PSUI

PSUI._frame   = nil
PSUI._tabs    = {}
PSUI._pages   = {}
PSUI._curTab  = nil

-- ─── Widget helpers ──────────────────────────────────────────────────────────
local WHITE = "Interface\\Buttons\\WHITE8X8"

local function _font(fs, size, outline)
    fs:SetFont("Fonts\\FRIZQT__.TTF", size or 12, outline or "OUTLINE")
end

local function _label(parent, text, x, y, size)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    _font(fs, size or 11)
    fs:SetTextColor(1, 0.9, 0.7, 1)
    fs:SetText(text)
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    return fs
end

local function _divider(parent, y)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetTexture("Interface\\Common\\UI-TooltipDivider-Transparent")
    t:SetSize(260, 2)
    t:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, y)
    return t
end

-- Slider avec label + valeur
local function _slider(parent, label, key, min, max, step, x, y, onChange)
    local lbl = _label(parent, label, x, y)

    local sl = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    sl:SetSize(180, 16)
    sl:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 4, y - 14)
    sl:SetMinMaxValues(min, max)
    sl:SetValueStep(step or 1)

    if SUF.db and SUF.db[key] ~= nil then
        sl:SetValue(SUF.db[key])
    end
    sl.Low:SetText(tostring(min))
    sl.High:SetText(tostring(max))

    local valLabel = parent:CreateFontString(nil, "OVERLAY")
    _font(valLabel, 10)
    valLabel:SetPoint("LEFT", sl, "RIGHT", 4, 0)
    valLabel:SetTextColor(1, 1, 0.8, 1)
    valLabel:SetText(tostring(SUF.db and SUF.db[key] or ""))

    sl:SetScript("OnValueChanged", function(self, val)
        if step and step < 1 then
            val = math.floor(val / step + 0.5) * step
        end
        valLabel:SetText(string.format(step and step < 1 and "%.2f" or "%d", val))
        if SUF.db then
            SUF.db[key] = val
            if onChange then onChange(val)
            elseif SUF.RefreshAll then pcall(SUF.RefreshAll, SUF) end
        end
    end)

    return sl, lbl, valLabel
end

-- Checkbox
local function _check(parent, label, key, x, y, onChange)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(20, 20)
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)

    local lbl = parent:CreateFontString(nil, "OVERLAY")
    _font(lbl, 11)
    lbl:SetText(label)
    lbl:SetTextColor(1, 1, 1, 1)
    lbl:SetPoint("LEFT", cb, "RIGHT", 2, 0)

    if SUF.db and SUF.db[key] ~= nil then
        cb:SetChecked(SUF.db[key] == true)
    end
    cb:SetScript("OnClick", function(self)
        local val = self:GetChecked() and true or false
        if SUF.db then
            SUF.db[key] = val
            if onChange then onChange(val)
            elseif SUF.RefreshAll then pcall(SUF.RefreshAll, SUF) end
        end
    end)
    return cb, lbl
end

-- Dropdown simple
local function _dropdown(parent, label, options, key, x, y, onChange)
    _label(parent, label, x, y)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(140, 22)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 16)
    pcall(function()
        btn:SetBackdrop({bgFile=WHITE, edgeFile=WHITE, edgeSize=1})
        btn:SetBackdropColor(0.1, 0.1, 0.15, 0.9)
        btn:SetBackdropBorderColor(0.5, 0.5, 0.6, 1)
    end)

    local lbl = btn:CreateFontString(nil, "OVERLAY")
    _font(lbl, 10)
    lbl:SetPoint("LEFT", btn, "LEFT", 6, 0)
    lbl:SetTextColor(1, 0.9, 0.5, 1)
    if SUF.db and SUF.db[key] ~= nil then
        local displayText = tostring(SUF.db[key])
        for _, opt in ipairs(options) do
            if (opt.value or opt) == SUF.db[key] then
                displayText = tostring(opt.label or opt); break
            end
        end
        lbl:SetText(displayText)
    end

    btn._isOpen = false
    btn._dropdown = nil

    btn:SetScript("OnClick", function(self)
        if self._isOpen and self._dropdown then
            self._dropdown:Hide(); self._dropdown = nil; self._isOpen = false; return
        end
        self._isOpen = true
        local menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        menu:SetSize(140, #options * 20 + 6)
        menu:SetFrameStrata("DIALOG")
        menu:SetFrameLevel(500)
        pcall(function()
            menu:SetBackdrop({bgFile=WHITE, edgeFile=WHITE, edgeSize=1})
            menu:SetBackdropColor(0.08, 0.08, 0.12, 0.97)
            menu:SetBackdropBorderColor(0.5, 0.5, 0.65, 1)
        end)
        local bx, by = self:GetCenter()
        local s = UIParent:GetEffectiveScale() or 1
        menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", bx/s - 70/s, by/s + 2/s)
        menu:ClearAllPoints()
        menu:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -2)

        for i, opt in ipairs(options) do
            local row = CreateFrame("Button", nil, menu)
            row:SetSize(136, 20)
            row:SetPoint("TOPLEFT", menu, "TOPLEFT", 2, -2 - (i-1)*20)
            local rLabel = row:CreateFontString(nil, "OVERLAY")
            _font(rLabel, 10)
            rLabel:SetAllPoints(row)
            rLabel:SetJustifyH("LEFT")
            rLabel:SetText("  " .. tostring(opt.label or opt))
            local val = opt.value or opt
            row:SetScript("OnClick", function()
                if SUF.db then
                    SUF.db[key] = val
                    lbl:SetText(tostring(opt.label or opt))
                    if onChange then onChange(val)
                    elseif SUF.RefreshAll then pcall(SUF.RefreshAll, SUF) end
                end
                menu:Hide(); self._dropdown = nil; self._isOpen = false
            end)
            row:SetScript("OnEnter", function() rLabel:SetTextColor(1, 0.85, 0.1) end)
            row:SetScript("OnLeave", function() rLabel:SetTextColor(1, 1, 1) end)
        end
        self._dropdown = menu
        menu:Show()
    end)
    return btn
end

-- ─── Construction principale ──────────────────────────────────────────────────
local function _buildMain()
    if PSUI._frame then return end

    local f = CreateFrame("Frame", "SUFConfigPanel", UIParent, "BackdropTemplate")
    f:SetSize(320, 480)
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel(100)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:SetPoint("CENTER", UIParent, "CENTER", 250, 0)
    pcall(function()
        f:SetBackdrop({
            bgFile   = WHITE,
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile=true, tileSize=16, edgeSize=12,
            insets={left=3, right=3, top=3, bottom=3},
        })
        f:SetBackdropColor(0.06, 0.06, 0.10, 0.97)
        f:SetBackdropBorderColor(0.55, 0.55, 0.75, 0.9)
    end)

    -- Titre
    local titleFS = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleFS:SetPoint("TOP", f, "TOP", 0, -8)
    titleFS:SetText("|cFF88CCFFSphereUnit|cFFFFFFFFFrames|r — Configuration")

    -- Fermer
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetSize(22, 22)
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -3)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Séparateur
    local sep = f:CreateTexture(nil, "ARTWORK")
    sep:SetTexture("Interface\\Common\\UI-TooltipDivider-Transparent")
    sep:SetSize(294, 2)
    sep:SetPoint("TOP", f, "TOP", 0, -22)

    -- Zone de tabs
    local tabRow = CreateFrame("Frame", nil, f)
    tabRow:SetSize(310, 26)
    tabRow:SetPoint("TOPLEFT", f, "TOPLEFT", 5, -28)

    -- Zone de contenu
    local content = CreateFrame("Frame", nil, f)
    content:SetSize(306, 420)
    content:SetPoint("TOPLEFT", f, "TOPLEFT", 7, -58)
    content:SetClipsChildren(true)

    PSUI._frame   = f
    PSUI._tabRow  = tabRow
    PSUI._content = content
    PSUI._tabs    = {}
    PSUI._pages   = {}

    -- ── Créer les onglets ────────────────────────────────────────────────────
    local tabDefs = {
        "Sphère", "Couleurs", "Castbar", "Auras", "Minimap", "Modules"
    }

    for i, name in ipairs(tabDefs) do
        local tab = CreateFrame("Button", nil, tabRow, "BackdropTemplate")
        tab:SetSize(46, 22)
        tab:SetPoint("LEFT", tabRow, "LEFT", (i-1)*48, 0)
        pcall(function()
            tab:SetBackdrop({bgFile=WHITE, edgeFile=WHITE, edgeSize=1})
            tab:SetBackdropColor(0.1, 0.1, 0.15, 0.9)
            tab:SetBackdropBorderColor(0.4, 0.4, 0.5, 1)
        end)
        local tLbl = tab:CreateFontString(nil, "OVERLAY")
        _font(tLbl, 9)
        tLbl:SetAllPoints(tab)
        tLbl:SetJustifyH("CENTER")
        tLbl:SetText(name)
        tLbl:SetTextColor(0.85, 0.85, 0.85, 1)
        tab._label = tLbl
        tab._name  = name
        tab:SetScript("OnClick", function() PSUI:ShowTab(name) end)
        PSUI._tabs[name] = tab
    end

    -- ── Créer les pages ──────────────────────────────────────────────────────
    PSUI:_BuildSpherePage()
    PSUI:_BuildColorsPage()
    PSUI:_BuildCastbarPage()
    PSUI:_BuildAurasPage()
    PSUI:_BuildMinimapPage()
    PSUI:_BuildModulesPage()

    PSUI:ShowTab("Sphère")
    f:Hide()
end

-- ─── Tabs ─────────────────────────────────────────────────────────────────────
function PSUI:ShowTab(name)
    for n, tab in pairs(self._tabs) do
        local active = (n == name)
        pcall(function()
            tab:SetBackdropColor(active and 0.18 or 0.10, active and 0.18 or 0.10,
                active and 0.28 or 0.15, 0.97)
            tab:SetBackdropBorderColor(active and 0.7 or 0.4, active and 0.7 or 0.4,
                active and 0.9 or 0.5, 1)
        end)
        tab._label:SetTextColor(active and 1 or 0.75, active and 0.9 or 0.75,
            active and 0.5 or 0.75, 1)
    end
    for n, page in pairs(self._pages) do
        if n == name then page:Show() else page:Hide() end
    end
    self._curTab = name
end

local function _newPage(content)
    local p = CreateFrame("Frame", nil, content)
    p:SetAllPoints(content)
    p:Hide()
    return p
end

-- ─── Page Sphère ─────────────────────────────────────────────────────────────
function PSUI:_BuildSpherePage()
    local p = _newPage(self._content)
    self._pages["Sphère"] = p

    _slider(p, "Taille de la sphère (px)", "orbSize", 80, 300, 2, 8, -10, function(v)
        if SUF.Orb then pcall(SUF.Orb.RebuildPlayer, SUF.Orb) end
    end)
    _slider(p, "Scale globale", "scale", 0.5, 2.0, 0.05, 8, -52)
    _slider(p, "Fond — Opacité", "bgAlpha", 0.0, 1.0, 0.01, 8, -94)
    _slider(p, "Gloss — Opacité", "orb_gloss_alpha", 0.0, 1.0, 0.01, 8, -136)
    _slider(p, "Verre — Opacité", "orb_glass_alpha", 0.0, 1.0, 0.01, 8, -178)
    _divider(p, -215)
    _check(p, "Galaxy (fond)", "orb_galaxy_enabled", 8, -222)
    _check(p, "Shimmer (reflet)", "orb_shimmer_enabled", 8, -244)
    _check(p, "Wave (vague)", "orb_wave_enabled", 8, -266)
    _check(p, "Midnight Star", "orb_midnight_star", 8, -288)
    _divider(p, -310)
    _check(p, "Zone vide — effacement (clear)", "orb_empty_clear_enabled", 8, -317)
    _check(p, "Zone vide — ombrage", "orb_empty_shade_enabled", 8, -339)
    _slider(p, "Zone vide — Opacité ombre", "orb_empty_shade_alpha", 0.0, 1.0, 0.01, 8, -361)
end

-- ─── Page Couleurs ────────────────────────────────────────────────────────────
function PSUI:_BuildColorsPage()
    local p = _newPage(self._content)
    self._pages["Couleurs"] = p

    _dropdown(p, "Mode de couleur HP", {
        {label="Classe",      value="class"},
        {label="Fixe",        value="fixed"},
        {label="Progressive", value="progressive"},
    }, "fill_color_mode", 8, -10, function(v)
        if SUF.RefreshAll then pcall(SUF.RefreshAll, SUF) end
    end)

    _divider(p, -52)
    _label(p, "Couleur fixe (R / G / B)", 8, -58, 11)
    _slider(p, "R", "fill_r", 0.0, 1.0, 0.01, 8,  -72)
    _slider(p, "G", "fill_g", 0.0, 1.0, 0.01, 8, -114)
    _slider(p, "B", "fill_b", 0.0, 1.0, 0.01, 8, -156)

    _divider(p, -194)
    _label(p, "Bordure décorative", 8, -200, 11)
    _dropdown(p, "Style", {
        {label="Solide",       value="solide"},
        {label="Horde",        value="wow_horde"},
        {label="Alliance",     value="wow_alliance"},
        {label="Horde Fer",    value="ns_horde"},
        {label="Alliance Or",  value="ns_alliance"},
    }, "borderStyle", 8, -216)
    _slider(p, "Opacité", "borderA", 0.0, 1.0, 0.01, 8, -256)

    _divider(p, -294)
    _label(p, "HP Fill visible (0 = moteur C seul)", 8, -300, 11)
    _slider(p, "Alpha HP fill (layer Lua)", "orb_hp_fill_alpha", 0.0, 1.0, 0.01, 8, -314)
end

-- ─── Page Castbar ─────────────────────────────────────────────────────────────
function PSUI:_BuildCastbarPage()
    local p = _newPage(self._content)
    self._pages["Castbar"] = p

    _check(p, "Activer la castbar", "castbar_enabled", 8, -10, function(v)
        if not v and SUF.player and SUF.CastBar then
            pcall(SUF.CastBar.Reset, SUF.CastBar, SUF.player)
        end
    end)
    _dropdown(p, "Style", {
        {label="Circulaire", value="circular"},
        {label="Classique",  value="classic"},
    }, "castbar_style", 8, -36)
    _check(p, "Afficher l'icône du sort", "castbar_show_icon", 8, -76)
    _check(p, "Afficher le temps restant", "castbar_show_time",  8, -98)
    _slider(p, "Taille police temps", "castbar_time_font_size", 8, 24, 1, 8, -124)
end

-- ─── Page Auras ───────────────────────────────────────────────────────────────
function PSUI:_BuildAurasPage()
    local p = _newPage(self._content)
    self._pages["Auras"] = p

    local arcDirOpts = {
        {label="Haut",   value="top"},
        {label="Bas",    value="bottom"},
        {label="Gauche", value="left"},
        {label="Droite", value="right"},
    }
    local function refreshAuras()
        local data = SUF.player
        if data and SUF.Auras then
            pcall(SUF.Auras.UpdateUnit, SUF.Auras, data, "player", nil)
        end
    end

    _check(p, "Activer les auras", "auras_enabled", 8, -10)
    _dropdown(p, "Mode", {
        {label="Anneau (ring)", value="ring"},
        {label="Arc",           value="arc"},
    }, "auras_mode", 8, -36, refreshAuras)
    _slider(p, "Taille des icônes (px)", "auras_size", 16, 48, 1, 8, -76, refreshAuras)
    _slider(p, "Rayon (×orbRadius)", "auras_offset_radius", 1.0, 2.0, 0.05, 8, -118, refreshAuras)
    _slider(p, "Max debuffs", "auras_max_debuffs", 1, 16, 1, 8, -160)
    _slider(p, "Max buffs",   "auras_max_buffs",   1, 16, 1, 8, -202)
    _dropdown(p, "Arc — position buffs",   arcDirOpts, "auras_buff_arc_dir",   8, -238, refreshAuras)
    _dropdown(p, "Arc — position debuffs", arcDirOpts, "auras_debuff_arc_dir", 8, -274, refreshAuras)
    _slider(p, "Arc — spread (°)", "auras_arc_spread", 20, 340, 10, 8, -314, refreshAuras)
    _check(p, "Timers",                "auras_show_timers",      8, -354)
    _check(p, "Seulement mes debuffs", "auras_debuff_mine_only", 8, -376)
    _check(p, "Seulement mes buffs",   "auras_buff_mine_only",   8, -398)
end

-- ─── Page Minimap ─────────────────────────────────────────────────────────────
function PSUI:_BuildMinimapPage()
    local p = _newPage(self._content)
    self._pages["Minimap"] = p

    _check(p, "Activer minimap", "minimap_enabled", 8, -10)
    _dropdown(p, "Mode minimap", {
        {label="Désactivé",  value="disabled"},
        {label="Intégrée",   value="integrated"},
    }, "minimap_mode", 8, -36, function(v)
        if SUF.Minimap then pcall(SUF.Minimap.Evaluate, SUF.Minimap) end
    end)
    _slider(p, "Seuil HP min (%) pour affichage", "minimap_hp_threshold", 0, 100, 5, 8, -80)
    _check(p, "Masquer boutons zoom/tracking", "minimap_hide_buttons", 8, -118)

    -- Bouton intégrer/relâcher manuellement
    local manBtn = CreateFrame("Button", nil, p, "BackdropTemplate")
    manBtn:SetSize(160, 24)
    manBtn:SetPoint("TOPLEFT", p, "TOPLEFT", 8, -148)
    pcall(function()
        manBtn:SetBackdrop({bgFile=WHITE, edgeFile=WHITE, edgeSize=1})
        manBtn:SetBackdropColor(0.12, 0.12, 0.20, 0.95)
        manBtn:SetBackdropBorderColor(0.6, 0.6, 0.8, 1)
    end)
    local manLbl = manBtn:CreateFontString(nil, "OVERLAY")
    _font(manLbl, 10)
    manLbl:SetAllPoints(manBtn)
    manLbl:SetJustifyH("CENTER")
    manLbl:SetText("Intégrer / Relâcher minimap")
    manBtn:SetScript("OnClick", function()
        if not SUF.Minimap then return end
        if SUF.Minimap._integrated then
            pcall(SUF.Minimap.Release, SUF.Minimap)
        else
            pcall(SUF.Minimap.Integrate, SUF.Minimap)
        end
    end)
end

-- ─── Page Modules ─────────────────────────────────────────────────────────────
function PSUI:_BuildModulesPage()
    local p = _newPage(self._content)
    self._pages["Modules"] = p

    _label(p, "|cFFFFCC44Modules ON/OFF (FPS isolation)|r", 8, -8, 11)
    _divider(p, -24)
    _check(p, "Animation orbe",   "modules_orbanim_enabled",  8,  -30)
    _check(p, "Castbar",          "modules_castbar_enabled",  8,  -52)
    _check(p, "Auras",            "modules_auras_enabled",    8,  -74)
    _check(p, "Lerp HP",          "modules_hplerp_enabled",   8,  -96)
    _check(p, "Power bar",        "modules_power_enabled",    8, -118)
    _check(p, "Barres d'action",  "actionbars_enabled",       8, -140)

    _divider(p, -162)
    _label(p, "|cFF88CCFFLogs|r", 8, -168, 11)
    _check(p, "Activer les logs", "logs_enabled", 8, -178)
    _slider(p, "Capacité (entrées)", "logs_max_entries", 50, 500, 50, 8, -202)
    _check(p, "Niveau INFO",  "logs_level_info",  8, -240)
    _check(p, "Niveau WARN",  "logs_level_warn",  8, -262)
    _check(p, "Niveau PERF",  "logs_level_perf",  8, -284)
    _check(p, "Niveau DEBUG", "logs_level_debug", 8, -306)

    _divider(p, -328)
    _label(p, "|cFFFF8800Performance Monitor|r", 8, -334, 11)
    _check(p, "Activer le profiler", "perf_enabled", 8, -344)
    _slider(p, "Seuil d'alerte (ms)", "perf_seuil_ms", 1.0, 30.0, 0.5, 8, -368)
end

-- ─── API publique ─────────────────────────────────────────────────────────────
function PSUI:Open()
    _buildMain()
    if self._frame then self._frame:Show() end
end

function PSUI:Close()
    if self._frame then self._frame:Hide() end
end

function PSUI:Toggle()
    _buildMain()
    if not self._frame then return end
    if self._frame:IsShown() then self:Close() else self:Open() end
end

function PSUI:IsOpen()
    return self._frame and self._frame:IsShown() or false
end
