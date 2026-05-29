-------------------------------------------------------------------------------
--  SphereUnitFrames · Core.lua
--  Initialisation, events joueur, OnUpdate global, slash commands.
--
--  Différences vs SphereNameplates :
--    • Un seul SUF.player (pas de SP.Plates[unit])
--    • Pas de NAME_PLATE_UNIT_ADDED/REMOVED
--    • RegisterUnitEvent("UNIT_*", "player") au lieu d'events globaux
--    • Pas de pooling de frames (frame joueur permanente)
-------------------------------------------------------------------------------

local ADDON = "SphereUnitFrames"
local SUF = _G[ADDON]
if not SUF then return end

-- ─── Frame d'events ──────────────────────────────────────────────────────────
local eventFrame = CreateFrame("Frame", "SUFEventFrame", UIParent)

-- ─── Accumulateurs OnUpdate ──────────────────────────────────────────────────
local accAnim   = 0   -- 30 FPS : AnimTick, TickPanel
local accCast   = 0   -- 60 FPS : CastBar Tick
local accLerp   = 0   -- 60 FPS : lerp HP
local accSlow   = 0   -- 0.5s   : auras, power, minimap evaluate

-- ─── Initialize ──────────────────────────────────────────────────────────────
local function Initialize()
    -- AceDB
    local AceDB = LibStub and LibStub("AceDB-3.0", true)
    if AceDB then
        SUF.db = AceDB:New("SUFDB", SUF.defaults, true).profile
    else
        -- Fallback sans AceDB (deep copy des defaults)
        SUFDB = SUFDB or {}
        local function deepMerge(dst, src)
            for k, v in pairs(src) do
                if type(v) == "table" then
                    dst[k] = dst[k] or {}
                    deepMerge(dst[k], v)
                elseif dst[k] == nil then
                    dst[k] = v
                end
            end
        end
        deepMerge(SUFDB, SUF.defaults.profile)
        SUF.db = SUFDB
    end

    -- Créer la frame joueur
    if SUF.Orb then
        pcall(SUF.Orb.CreatePlayer, SUF.Orb)
    end

    -- Modules init (ordre : après CreatePlayer pour que data existe)
    local _d = SUF.player
    if _d then
        if SUF.Auras       then pcall(SUF.Auras.Init,       SUF.Auras,       _d) end
        if SUF.Power       then pcall(SUF.Power.Init,       SUF.Power,       _d) end
        if SUF.CastBar     then pcall(SUF.CastBar.Init,     SUF.CastBar,     _d) end
        if SUF.Interaction then pcall(SUF.Interaction.Init, SUF.Interaction, _d) end
    end
    if SUF.ActionBars then pcall(SUF.ActionBars.Init, SUF.ActionBars) end
    if SUF.Minimap    then pcall(SUF.Minimap.Init,    SUF.Minimap) end
    if SUF.Profiler   then pcall(SUF.Profiler.RestorePanelState, SUF.Profiler) end

    -- Events joueur (RegisterUnitEvent = plus précis qu'events globaux)
    pcall(function()
        eventFrame:RegisterUnitEvent("UNIT_HEALTH",          "player")
        eventFrame:RegisterUnitEvent("UNIT_MAXHEALTH",        "player")
        eventFrame:RegisterUnitEvent("UNIT_POWER_UPDATE",     "player")
        eventFrame:RegisterUnitEvent("UNIT_DISPLAYPOWER",     "player")
        eventFrame:RegisterUnitEvent("UNIT_AURA",             "player")
        eventFrame:RegisterUnitEvent("UNIT_ABSORB_AMOUNT_CHANGED", "player")
    end)
    pcall(function()
        eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        eventFrame:RegisterEvent("PLAYER_LEAVING_WORLD")
        eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
        eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        eventFrame:RegisterEvent("PLAYER_DEAD")
        eventFrame:RegisterEvent("PLAYER_ALIVE")
        eventFrame:RegisterEvent("PLAYER_UNGHOST")
        eventFrame:RegisterEvent("PLAYER_LEVEL_UP")
        eventFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
        eventFrame:RegisterEvent("UNIT_PORTRAIT_UPDATE")
    end)

    -- OnUpdate global
    eventFrame:SetScript("OnUpdate", Core_OnUpdate)

    SUF:Debug("Initialize OK — " .. SUF.version)
end

-- ─── OnUpdate global ─────────────────────────────────────────────────────────
-- Un seul OnUpdate, accumulateurs instrumentés.
function Core_OnUpdate(self, elapsed)
    local data = SUF.player
    if not data then return end

    local now = GetTime()

    -- 60 FPS : lerp HP (targetHP → displayHP)
    if SUF.db and SUF.db.modules_hplerp_enabled ~= false then
        accLerp = accLerp + elapsed
        if accLerp >= 0.0167 then
            accLerp = 0
            if data.targetHP and data.displayHP ~= data.targetHP then
                local diff  = data.targetHP - (data.displayHP or data.targetHP)
                local delta = 2.5 * 0.0167
                if math.abs(diff) < delta then
                    data.displayHP = data.targetHP
                else
                    data.displayHP = (data.displayHP or data.targetHP) + (diff > 0 and delta or -delta)
                end
                if SUF.Orb then
                    pcall(SUF.Orb.UpdateFill, SUF.Orb, data, data.displayHP)
                end
            end
        end
    end

    -- 60 FPS : CastBar tick
    if SUF.db and SUF.db.modules_castbar_enabled ~= false and SUF.CastBar then
        accCast = accCast + elapsed
        if accCast >= 0.0167 then
            local dt = accCast; accCast = 0
            local t0 = debugprofilestop()
            pcall(SUF.CastBar.Tick, SUF.CastBar, data, now)
            if SUF.Profiler then pcall(SUF.Profiler.Track, SUF.Profiler, "CastBar", debugprofilestop() - t0) end
        end
    end

    -- 30 FPS : AnimTick + panneau perf
    if SUF.db and SUF.db.modules_orbanim_enabled ~= false and SUF.Orb then
        accAnim = accAnim + elapsed
        if accAnim >= 0.0333 then
            local dt = accAnim; accAnim = 0
            local t0 = debugprofilestop()
            pcall(SUF.Orb.AnimTick, SUF.Orb, data, dt)
            if SUF.Profiler then pcall(SUF.Profiler.Track, SUF.Profiler, "AnimTick", debugprofilestop() - t0) end
            if SUF.Profiler then pcall(SUF.Profiler.TickPanel, SUF.Profiler, now) end
        end
    end

    -- 0.5s : auras, power, minimap evaluate, HP poll secours
    accSlow = accSlow + elapsed
    if accSlow >= 0.5 then
        accSlow = 0

        -- HP secours (si UNIT_HEALTH pas reçu)
        pcall(UpdateHealth)

        -- Auras
        if SUF.db and SUF.db.modules_auras_enabled ~= false and SUF.Auras and data.auraIcons then
            pcall(SUF.Auras.UpdateUnit, SUF.Auras, data, "player", nil)
        end

        -- Power
        if SUF.db and SUF.db.modules_power_enabled ~= false and SUF.Power then
            pcall(SUF.Power.Update, SUF.Power, data)
        end

        -- Minimap evaluate (hors combat seulement)
        if SUF.Minimap and SUF.db and SUF.db.minimap_mode ~= "disabled" then
            pcall(SUF.Minimap.Evaluate, SUF.Minimap)
        end
    end
end

-- ─── UpdateHealth ────────────────────────────────────────────────────────────
function UpdateHealth()
    local data = SUF.player
    if not data or not data.hpBar then return end

    -- Pilote C-side prioritaire (UnitHealthPercent sur min/max 0..100)
    local ok = pcall(function()
        data.hpBar:SetMinMaxValues(0, 100)
        if CurveConstants and CurveConstants.ScaleTo100 then
            data.hpBar:SetValue(
                UnitHealthPercent("player", false, CurveConstants.ScaleTo100),
                Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate or nil)
            data._hpDriver = "pct_curve"
        else
            data.hpBar:SetValue(UnitHealthPercent("player") or 100)
            data._hpDriver = "pct_raw"
        end
    end)
    if not ok then
        -- Fallback absolu
        pcall(function()
            local h = UnitHealth("player")
            local m = UnitHealthMax("player")
            data.hpBar:SetMinMaxValues(0, m or 100)
            data.hpBar:SetValue(h or 100)
            data._hpDriver = "abs_fallback"
        end)
    end

    -- Ratio Lua pour texte + lerp
    local ratio = SUF:GetHPRatio()
    data.targetHP = ratio

    -- Texte HP
    if SUF.Orb then pcall(SUF.Orb.UpdateHPText, SUF.Orb, data) end

    -- Couleur fill : réévaluer pour TOUS les modes (class / progressive / fixed).
    -- Pour "class" à 100% HP le lerp ne déclenche jamais → UpdateFill doit être
    -- appelé ici explicitement pour que la couleur de classe apparaisse immédiatement.
    if SUF.Orb then
        pcall(SUF.Orb.UpdateFill, SUF.Orb, data, data.displayHP or ratio)
    end
end

-- ─── Handlers d'events ───────────────────────────────────────────────────────
local function OnEvent(self, event, arg1, ...)
    local data = SUF.player

    if event == "ADDON_LOADED" and arg1 == ADDON then
        Initialize()
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        if data then
            -- Réinitialiser l'état
            pcall(UpdateHealth)
            if SUF.Power  then pcall(SUF.Power.Update,  SUF.Power,  data) end
            if SUF.Auras  then pcall(SUF.Auras.PrewarmPool, SUF.Auras, 24) end
            if SUF.CastBar then pcall(SUF.CastBar.Reset, SUF.CastBar, data) end
            if SUF.ActionBars then pcall(SUF.ActionBars.Prewarm, SUF.ActionBars) end
            if SUF.Minimap then pcall(SUF.Minimap.Evaluate, SUF.Minimap) end
        end
        return
    end

    if event == "PLAYER_REGEN_DISABLED" then
        SUF.InCombat = true
        if data then data._inCombat = true end
        -- Forcer mode sphère HP si minimap intégrée
        if SUF.Minimap then pcall(SUF.Minimap.OnEnterCombat, SUF.Minimap) end
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        SUF.InCombat = false
        if data then data._inCombat = false end
        -- Évaluer retour minimap après combat
        if SUF.Minimap then pcall(SUF.Minimap.OnExitCombat, SUF.Minimap) end
        return
    end

    if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
        pcall(UpdateHealth)
        return
    end

    if event == "UNIT_POWER_UPDATE" or event == "UNIT_DISPLAYPOWER" then
        if data and SUF.Power then
            pcall(SUF.Power.Update, SUF.Power, data)
        end
        return
    end

    if event == "UNIT_AURA" then
        if data and SUF.Auras and data.auraIcons then
            local updateInfo = ...
            pcall(SUF.Auras.UpdateUnit, SUF.Auras, data, "player", updateInfo)
        end
        return
    end

    if event == "PLAYER_DEAD" then
        if data and data.hpBar then
            pcall(function()
                data.hpBar:SetMinMaxValues(0, 100)
                data.hpBar:SetValue(0)
                data.targetHP  = 0
                data.displayHP = 0
                if SUF.Orb then SUF.Orb:UpdateFill(data, 0) end
            end)
        end
        return
    end

    if event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
        pcall(UpdateHealth)
        return
    end

    if event == "PLAYER_LEVEL_UP" then
        pcall(UpdateHealth)
        return
    end

    if event == "ACTIVE_TALENT_GROUP_CHANGED" then
        -- Changement de spécialisation : power type change possible
        if data and SUF.Power then pcall(SUF.Power.Update, SUF.Power, data) end
        return
    end

    if event == "UNIT_PORTRAIT_UPDATE" then
        -- Portrait joueur mis à jour (changement de forme, race)
        if data and SUF.Orb then pcall(SUF.Orb.SoftUpdate, SUF.Orb, data) end
        return
    end
end

eventFrame:SetScript("OnEvent", OnEvent)
eventFrame:RegisterEvent("ADDON_LOADED")

-- ─── RefreshAll ───────────────────────────────────────────────────────────────
function SUF:RefreshAll()
    local data = SUF.player
    if not data then return end
    local cfg = SUF.db

    -- Si taille a changé → rebuild complet
    if cfg.orbSize ~= data.orbSize then
        if SUF.Orb then
            pcall(SUF.Orb.RebuildPlayer, SUF.Orb)
        end
        return
    end

    -- Sinon SoftUpdate
    data._lastFillR = nil
    data._lastFillG = nil
    data._lastFillB = nil
    if SUF.Orb then pcall(SUF.Orb.SoftUpdate, SUF.Orb, data) end
    pcall(UpdateHealth)
    if SUF.Power  then pcall(SUF.Power.Update, SUF.Power, data) end
    if SUF.Minimap then pcall(SUF.Minimap.UpdateScale, SUF.Minimap) end
end

-- ─── Slash commands ──────────────────────────────────────────────────────────
SLASH_SUF1 = "/suf"
SLASH_SUF2 = "/sufui"
SlashCmdList["SUF"] = function(msg)
    msg = msg and msg:lower():match("^%s*(.-)%s*$") or ""

    if msg == "" or msg == "ui" then
        if SUF.PSUI then
            pcall(SUF.PSUI.Toggle, SUF.PSUI)
        else
            SUF:Print("Interface de config non chargée.")
        end

    elseif msg == "layers" then
        local data = SUF.player
        if not data then SUF:Print("Frame joueur non créée.") return end
        local lines = {
            "=== SUF Layers ===",
            ("root alpha=%.2f  strata=%s  level=%d"):format(
                data.root and data.root:GetAlpha() or -1,
                data.root and data.root:GetFrameStrata() or "?",
                data.root and data.root:GetFrameLevel() or -1),
            ("hpBar driver=%s  value=%.1f"):format(
                data._hpDriver or "?",
                data.hpBar and (pcall(data.hpBar.GetValue, data.hpBar) and data.hpBar:GetValue() or -1) or -1),
            ("displayHP=%.3f  targetHP=%.3f"):format(data.displayHP or -1, data.targetHP or -1),
            ("minimapIntegrated=%s  inCombat=%s"):format(
                tostring(SUF.Minimap and SUF.Minimap._integrated or false),
                tostring(SUF.InCombat)),
        }
        for _, l in ipairs(lines) do SUF:Print(l) end

    elseif msg == "perf" then
        if SUF.Profiler then pcall(SUF.Profiler.TogglePanel, SUF.Profiler)
        else SUF:Print("Profiler non chargé.") end

    elseif msg == "logs" then
        if SUF.Log then
            local entries = SUF.Log:GetEntries({ max = 20 })
            if #entries == 0 then SUF:Print("(aucun log)") return end
            for _, e in ipairs(entries) do
                local col = SUF.Log.LEVEL_COLORS[e.level] or ""
                DEFAULT_CHAT_FRAME:AddMessage(
                    string.format("[%s] %s[%s]|r [%s] %s", e.date, col, e.level, e.module, e.msg))
            end
        else
            SUF:Print("Logger non chargé.")
        end

    elseif msg == "lock" then
        if SUF.db then
            SUF.db.locked = not SUF.db.locked
            SUF:Print("Frame " .. (SUF.db.locked and "|cFF44FF44verrouillée|r" or "|cFFFF8800déverrouillée|r"))
        end

    elseif msg == "minimap" then
        if SUF.Minimap then
            if SUF.Minimap._integrated then
                pcall(SUF.Minimap.Release, SUF.Minimap)
                SUF:Print("Minimap relâchée.")
            else
                pcall(SUF.Minimap.Integrate, SUF.Minimap)
                SUF:Print("Minimap intégrée.")
            end
        end

    elseif msg == "reset" then
        if SUF.db then
            SUF.db.posX = 0
            SUF.db.posY = 200
        end
        local data = SUF.player
        if data and data.root then
            data.root:ClearAllPoints()
            data.root:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 200)
        end
        SUF:Print("Position réinitialisée.")

    else
        SUF:Print("Commandes : /suf [ui | layers | perf | logs | lock | minimap | reset]")
    end
end
