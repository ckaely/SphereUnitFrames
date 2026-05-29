-------------------------------------------------------------------------------
--  SphereUnitFrames · Interaction.lua
--  Drag/lock de la frame joueur + menu contextuel clic-droit.
--  Interaction:Init(data) appelé depuis Initialize() après CreatePlayer.
-------------------------------------------------------------------------------

local ADDON = "SphereUnitFrames"
local SUF   = _G[ADDON]
if not SUF then return end

SUF.Interaction = SUF.Interaction or {}
local Interaction = SUF.Interaction

-- ─── Init ────────────────────────────────────────────────────────────────────
function Interaction:Init(data)
    local root = data and data.root
    if not root then return end

    root:SetMovable(true)
    root:SetClampedToScreen(true)   -- empêche le drag de sortir de l'écran
    root:EnableMouse(true)
    root:RegisterForDrag("LeftButton")

    root:SetScript("OnDragStart", function(self)
        if SUF.db and SUF.db.locked then return end
        if InCombatLockdown() then
            SUF:Print("Impossible de déplacer en combat.")
            return
        end
        self:StartMoving()
    end)

    root:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if not SUF.db then return end
        -- Coordonnées pour SetPoint("BOTTOM", UIParent, "BOTTOM", posX, posY) :
        --   posX = offset depuis le centre horizontal de UIParent
        --   posY = bas de la frame depuis le bas de UIParent
        -- On utilise GetLeft/GetBottom (coordonnées absolues post-drag)
        -- et NON GetCenter−(screenCenter), qui donnait un Y relatif au centre écran
        -- (incorrect pour l'ancre BOTTOM → frame sautait au prochain RefreshAll).
        local left  = self:GetLeft()
        local bot   = self:GetBottom()
        if not left then return end
        local uw    = UIParent:GetWidth() or 1024
        local rootW = self:GetWidth() or 0
        local x = (left + rootW * 0.5) - uw * 0.5
        local y = math.max(0, bot)
        if SUF.ClampPos then x, y = SUF:ClampPos(x, y) end
        SUF.db.posX = x
        SUF.db.posY = y
    end)

    root:SetScript("OnMouseUp", function(self, btn)
        if btn == "RightButton" then
            Interaction:ShowContextMenu()
        end
    end)
end

-- ─── Context menu ─────────────────────────────────────────────────────────────
local _menu     = nil
local _lockLabel = nil

local function _menuBtn(parent, yOff, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(148, 22)
    btn:SetPoint("TOP", parent, "TOP", 0, yOff)
    btn:EnableMouse(true)
    local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("LEFT", btn, "LEFT", 8, 0)
    fs:SetJustifyH("LEFT")
    btn._label = fs
    btn:SetScript("OnClick",  onClick)
    btn:SetScript("OnEnter",  function() fs:SetTextColor(1, 0.82, 0.1, 1) end)
    btn:SetScript("OnLeave",  function() fs:SetTextColor(1, 1, 1, 1) end)
    return btn
end

local function _buildMenu()
    if _menu then return end
    local f = CreateFrame("Frame", "SUFContextMenu", UIParent, "BackdropTemplate")
    f:SetSize(160, 112)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(300)
    f:EnableMouse(true)
    pcall(function()
        f:SetBackdrop({
            bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile=true, tileSize=16, edgeSize=12,
            insets={ left=3, right=3, top=3, bottom=3 },
        })
        f:SetBackdropColor(0.05, 0.05, 0.09, 0.96)
        f:SetBackdropBorderColor(0.55, 0.55, 0.75, 0.9)
    end)

    _menuBtn(f, -12, function()
        f:Hide()
        if SUF.PSUI then pcall(SUF.PSUI.Toggle, SUF.PSUI)
        else SUF:Print("Interface de config non chargée.") end
    end)._label:SetText("|cFF88CCFFOuvrir config|r")

    local lockBtn = _menuBtn(f, -36, function()
        f:Hide()
        if SUF.db then
            SUF.db.locked = not SUF.db.locked
            local msg = SUF.db.locked and "|cFF44FF44verrouillée|r" or "|cFFFF8800déverrouillée|r"
            SUF:Print("Frame " .. msg)
        end
    end)
    _lockLabel = lockBtn._label

    _menuBtn(f, -60, function()
        f:Hide()
        if SUF.db then SUF.db.posX = 0; SUF.db.posY = 200 end
        local data = SUF.player
        if data and data.root then
            data.root:ClearAllPoints()
            data.root:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 200)
        end
        SUF:Print("Position réinitialisée.")
    end)._label:SetText("|cFFAAAAFFRéinitialiser position|r")

    _menuBtn(f, -84, function() f:Hide() end)._label:SetText("|cFF888888Fermer|r")

    -- Fermeture auto quand la souris quitte
    f:SetScript("OnLeave", function()
        if not f:IsMouseOver() then f:Hide() end
    end)

    _menu = f
end

function Interaction:ShowContextMenu()
    _buildMenu()
    if not _menu then return end

    -- Mettre à jour le label lock
    if _lockLabel then
        local locked = SUF.db and SUF.db.locked
        _lockLabel:SetText(locked and "|cFF44FF44Déverrouiller|r" or "|cFFFF8800Verrouiller|r")
    end

    local x, y = GetCursorPosition()
    local s = UIParent:GetEffectiveScale() or 1
    _menu:ClearAllPoints()
    _menu:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x / s, y / s)
    _menu:Show()
end
