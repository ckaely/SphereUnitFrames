-------------------------------------------------------------------------------
--  SphereUnitFrames · Logs.lua
--  Module de journalisation interne — adapté de SphereNameplates/Logs.lua.
--  Namespace remplacé : SP → SUF. Logique identique (validée en jeu SNP).
-------------------------------------------------------------------------------

local ADDON = "SphereUnitFrames"
local SUF   = _G[ADDON]
if not SUF then return end

SUF.Log = SUF.Log or {}
local Log = SUF.Log

Log.THROTTLE_SAME_MSG = 2.0
Log.LEVELS = { INFO=1, WARN=2, ERROR=3, PERF=4, DEBUG=5 }
Log.LEVEL_COLORS = {
    INFO  = "|cFF88CCFF",
    WARN  = "|cFFFFCC44",
    ERROR = "|cFFFF4444",
    PERF  = "|cFFFF8800",
    DEBUG = "|cFFAAAAAA",
}

Log._entries  = Log._entries  or {}
Log._head     = Log._head     or 0
Log._count    = Log._count    or 0
Log._capacity = 0
Log._throttle = {}

local function _db()       return SUF.db end
local function _capacity() local db = _db(); return (db and db.logs_max_entries) or 200 end

local function _levelEnabled(level)
    local db = _db()
    if not db then return level == "ERROR" end
    if level == "INFO"  then return db.logs_level_info  ~= false end
    if level == "WARN"  then return db.logs_level_warn  ~= false end
    if level == "ERROR" then return true end
    if level == "PERF"  then return db.logs_level_perf  ~= false end
    if level == "DEBUG" then return db.logs_level_debug == true  end
    return false
end

function Log:IsEnabled()
    local db = _db()
    return db and db.logs_enabled == true
end

function Log:SetEnabled(bool)
    local db = _db()
    if db then db.logs_enabled = bool == true end
end

local function _write(level, module, msg)
    if not Log:IsEnabled() then return end
    if not _levelEnabled(level) then return end
    if level == "DEBUG" and SUF.InCombat then return end

    if level ~= "ERROR" then
        local key  = (module or "?") .. ":" .. tostring(msg):sub(1, 40)
        local now  = GetTime()
        local last = Log._throttle[key]
        if last and (now - last) < Log.THROTTLE_SAME_MSG then return end
        Log._throttle[key] = now
    end

    local cap = _capacity()
    if cap ~= Log._capacity then
        Log._entries  = {}
        Log._head     = 0
        Log._count    = 0
        Log._capacity = cap
    end
    if cap <= 0 then return end

    Log._head = (Log._head % cap) + 1
    Log._entries[Log._head] = {
        t      = GetTime(),
        date   = date("%H:%M:%S"),
        level  = level,
        module = module or "?",
        msg    = tostring(msg),
    }
    if Log._count < cap then Log._count = Log._count + 1 end
end

function Log:Info (m, msg) _write("INFO",  m, msg) end
function Log:Warn (m, msg) _write("WARN",  m, msg) end
function Log:Error(m, msg) _write("ERROR", m, msg) end
function Log:Perf (m, msg) _write("PERF",  m, msg) end
function Log:Debug(m, msg) _write("DEBUG", m, msg) end

function Log:Clear()
    Log._entries  = {}
    Log._head     = 0
    Log._count    = 0
    Log._throttle = {}
end

function Log:Count() return Log._count end

function Log:GetEntries(opts)
    opts = opts or {}
    local cap = _capacity()
    if cap <= 0 or Log._count == 0 then return {} end
    local filterLevel  = opts.level
    local filterModule = opts.module
    local maxOut = opts.max or Log._count
    local out = {}
    local head = Log._head
    for i = 1, Log._count do
        local idx = ((head - i) % cap) + 1
        local e   = Log._entries[idx]
        if e then
            local ok = true
            if filterLevel  and e.level  ~= filterLevel  then ok = false end
            if filterModule and e.module ~= filterModule  then ok = false end
            if ok then
                out[#out + 1] = e
                if #out >= maxOut then break end
            end
        end
    end
    return out
end

-- Intégration SUF:Debug → ring buffer
local _origDebug = SUF.Debug
function SUF:Debug(msg)
    if SUF.db and SUF.db.logs_enabled then
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00CCFF[SUF-DBG]|r " .. tostring(msg))
    end
    Log:Debug("Core", msg)
end
