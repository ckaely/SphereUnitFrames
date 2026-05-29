-------------------------------------------------------------------------------
--  SphereUnitFrames · ProfileManager.lua
--  Gestion des profils AceDB (créer/charger/dupliquer/supprimer/reset).
--  S'appuie sur SUF.dbroot (objet AceDB-3.0) défini dans Core:Initialize.
-------------------------------------------------------------------------------

local ADDON = "SphereUnitFrames"
local SUF   = _G[ADDON]
if not SUF then return end

SUF.Profiles = SUF.Profiles or {}
local P = SUF.Profiles

local function _root() return SUF.dbroot end

function P:List()
    local r = _root(); if not r then return {} end
    local ok, list = pcall(function() return r:GetProfiles() end)
    return (ok and type(list) == "table") and list or {}
end

function P:Current()
    local r = _root(); if not r then return nil end
    local ok, name = pcall(function() return r:GetCurrentProfile() end)
    return ok and name or nil
end

function P:SwitchTo(name)
    local r = _root(); if not r or not name or name == "" then return false end
    local ok = pcall(function() r:SetProfile(name) end)
    if ok then
        SUF.db = r.profile
        if SUF.Orb       then pcall(SUF.Orb.RebuildPlayer, SUF.Orb) end
        if SUF.PSUI      then pcall(SUF.PSUI.Refresh, SUF.PSUI) end
        if SUF.RefreshAll then pcall(SUF.RefreshAll, SUF) end
        if SUF.Clock     then pcall(SUF.Clock.Refresh, SUF.Clock) end
    end
    return ok
end

function P:Create(name)
    if not name or name == "" then return false end
    return self:SwitchTo(name)   -- AceDB crée le profil à la volée s'il n'existe pas
end

function P:Duplicate(sourceName)
    local r = _root(); if not r or not sourceName then return false end
    return pcall(function() r:CopyProfile(sourceName) end)
end

function P:Delete(name)
    local r = _root(); if not r or not name or name == self:Current() then return false end
    return pcall(function() r:DeleteProfile(name) end)
end

function P:Reset()
    local r = _root(); if not r then return false end
    local ok = pcall(function() r:ResetProfile() end)
    if ok then
        SUF.db = r.profile
        if SUF.Orb       then pcall(SUF.Orb.RebuildPlayer, SUF.Orb) end
        if SUF.RefreshAll then pcall(SUF.RefreshAll, SUF) end
    end
    return ok
end
