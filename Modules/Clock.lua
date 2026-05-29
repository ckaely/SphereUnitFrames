-------------------------------------------------------------------------------
--  SphereUnitFrames · Clock.lua
--  Horloge intégrée style capsule fantasy.
--  Affiche heure locale, heure serveur, FPS/MS — tout togglable.
-------------------------------------------------------------------------------

local ADDON = "SphereUnitFrames"
local SUF   = _G[ADDON]
if not SUF then return end

SUF.Clock = SUF.Clock or {}
local Clock = SUF.Clock

local WHITE = "Interface\\Buttons\\WHITE8X8"
local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

Clock._frame  = nil
Clock._tick   = 0
Clock._fpsTick = 0

local function _fmt12_24(h, m, fmt24)
    if fmt24 then return string.format("%02d:%02d", h, m) end
    local ampm = h >= 12 and "PM" or "AM"
    local h12  = (h % 12); if h12 == 0 then h12 = 12 end
    return string.format("%d:%02d %s", h12, m, ampm)
end

function Clock:Build()
    if self._frame then return self._frame end
    local cfg = SUF.db
    if not cfg or cfg.clock_enabled == false then return nil end

    local data = SUF.player
    local parent = (data and data.root) or UIParent

    local f = CreateFrame("Frame", "SUFClock", parent, "BackdropTemplate")
    f:SetSize(120, 38)
    f:SetFrameStrata("MEDIUM")
    f:SetFrameLevel(((data and data.root and data.root:GetFrameLevel()) or 100) + 10)
    pcall(function()
        f:SetBackdrop({
            bgFile   = WHITE,
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile=true, tileSize=16, edgeSize=10,
            insets={left=2, right=2, top=2, bottom=2},
        })
        f:SetBackdropColor(0.05, 0.04, 0.07, 0.85)
        f:SetBackdropBorderColor(0.55, 0.45, 0.18, 0.95)
    end)

    -- Position : par défaut, au-dessus de l'orbe
    local pos = cfg.clock_position or "orb_top"
    if pos == "screen_corner" then
        f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -20)
    elseif pos == "orb_bottom" then
        f:SetPoint("TOP", (data and data.orb) or UIParent, "BOTTOM", 0, -10)
    else
        f:SetPoint("BOTTOM", (data and data.orb) or UIParent, "TOP", 0, 10)
    end
    f:SetAlpha(cfg.clock_alpha or 0.95)

    -- Lignes texte
    local mainFS = f:CreateFontString(nil, "OVERLAY")
    mainFS:SetFont("Fonts\\FRIZQT__.TTF", cfg.clock_font_size or 14, "OUTLINE")
    mainFS:SetTextColor(1, 0.90, 0.65, 1)
    mainFS:SetPoint("TOP", f, "TOP", 0, -4)
    f._main = mainFS

    local subFS = f:CreateFontString(nil, "OVERLAY")
    subFS:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    subFS:SetTextColor(0.85, 0.85, 0.85, 0.9)
    subFS:SetPoint("BOTTOM", f, "BOTTOM", 0, 4)
    f._sub = subFS

    f:SetScript("OnUpdate", function(self, elapsed)
        Clock._tick    = (Clock._tick    or 0) + elapsed
        Clock._fpsTick = (Clock._fpsTick or 0) + elapsed

        if Clock._tick >= 1.0 then
            Clock._tick = 0
            Clock:UpdateTime()
        end
        if Clock._fpsTick >= 0.5 then
            Clock._fpsTick = 0
            Clock:UpdatePerf()
        end
    end)

    self._frame = f
    self:UpdateTime()
    self:UpdatePerf()
    return f
end

function Clock:UpdateTime()
    if not self._frame then return end
    local cfg = SUF.db
    local fmt24 = (cfg.clock_format or "24h") == "24h"

    -- Heure locale
    local now = date("*t")
    local localStr = _fmt12_24(now.hour, now.min, fmt24)
    self._frame._main:SetText(localStr)

    -- Heure serveur (sub)
    if cfg.clock_show_server then
        local h, m = GetGameTime()
        if h then
            self._frame._sub:SetText("Srv " .. _fmt12_24(h, m, fmt24))
            return
        end
    end
    -- Sinon laisser la sub pour FPS/MS
end

function Clock:UpdatePerf()
    if not self._frame then return end
    local cfg = SUF.db
    if cfg.clock_show_server then return end   -- la sub affiche déjà l'heure serveur

    local parts = {}
    if cfg.clock_show_fps then
        local fps = math.floor(GetFramerate() or 0)
        parts[#parts+1] = fps .. " fps"
    end
    if cfg.clock_show_ms then
        local _, _, latencyHome, latencyWorld = GetNetStats()
        local ms = math.floor((latencyWorld or latencyHome or 0) + 0.5)
        parts[#parts+1] = ms .. " ms"
    end
    self._frame._sub:SetText(table.concat(parts, "  "))
end

function Clock:Init()
    local cfg = SUF.db
    if not cfg then return end
    if cfg.clock_enabled ~= false then
        C_Timer.After(0.2, function() Clock:Build() end)
    end
end

function Clock:Refresh()
    if self._frame then self._frame:Hide(); self._frame = nil end
    if SUF.db and SUF.db.clock_enabled ~= false then self:Build() end
end

function Clock:SetVisible(v)
    if self._frame then self._frame:SetShown(v) end
end
