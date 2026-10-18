-- ap1le_mechanicjob: presets, customer work orders and "Indlæs sidste" (client).
--
-- Used by client/tuning.lua (mechanic tuning screen and the customer design mode at a terminal).
-- This file only talks to the server and to the local KVP store; turning preset data into tuning
-- nodes (and back) is done in tuning.lua, which owns the node registry of the open vehicle.
--
-- Preset / work order data (server/presets.lua validates it again, strictly):
--   { cosmetic = { [ox_lib vehicle property key] = value }, performance = { [category] = level } }
-- Cosmetic keys and value shapes must pass the tuning save whitelist (server/tuning.lua): one bad
-- value rejects the whole preset, so Presets.CleanProps applies the same rules here first.
--
-- "Indlæs sidste": closing the tuning screen without installing stores the cart for that plate in
-- this resource's client KVP (SetResourceKvp). Only the newest LAST_MAX vehicles are kept.

Presets = {}

local LAST_PREFIX = 'lastcart:'
local LAST_INDEX = 'lastcart:index'
local LAST_MAX = 20                -- vehicles kept (newest first)
local LAST_MAX_CHANGES = 80        -- same cap as tuning.lua MAX_CHANGES
local LAST_MAX_BYTES = 16000       -- JSON size cap per stored cart

local MAX_NAME = math.tointeger(Config.Presets and Config.Presets.maxNameLength) or 32
local LIST_CACHE_MS = 1500         -- preset:list answers are reused this long (server rate limit 500 ms)

-- ---------------------------------------------------------------------------
-- Whitelist mirror (server/tuning.lua validators). Returns a clean copy or nil.
-- ---------------------------------------------------------------------------

local function int(v, min, max)
    if type(v) ~= 'number' then return nil end
    local i = math.tointeger(v)
    if not i or i < min or i > max then return nil end
    return i
end

local function rgbArray(v)
    if type(v) ~= 'table' then return nil end
    local r, g, b = v[1] or v.r, v[2] or v.g, v[3] or v.b
    r, g, b = int(r, 0, 255), int(g, 0, 255), int(b, 0, 255)
    if not (r and g and b) then return nil end
    return { r, g, b }
end

local function bool(v)
    if type(v) == 'boolean' then return v end
    return nil
end

local function colourIndex(v) return int(v, 0, 255) end
local function modIndex(v) return int(v, -1, 255) end

local function paint(v)
    if type(v) == 'table' then return rgbArray(v) end
    return colourIndex(v)
end

local RULES = {
    color1 = paint,
    color2 = paint,
    pearlescentColor = colourIndex,
    wheelColor = colourIndex,
    interiorColor = colourIndex,
    dashboardColor = colourIndex,
    wheels = function(v) return int(v, 0, 12) end,
    windowTint = function(v) return int(v, -1, 12) end,
    plateIndex = function(v) return int(v, 0, 12) end,
    xenonColor = function(v) return int(v, -1, 255) end,
    neonEnabled = function(v)
        if type(v) ~= 'table' then return nil end
        local copy = {}
        for i = 1, 4 do
            if type(v[i]) ~= 'boolean' then return nil end
            copy[i] = v[i]
        end
        return copy
    end,
    neonColor = rgbArray,
    tyreSmokeColor = rgbArray,
    modSmokeEnabled = bool,
    modXenon = bool,
    modCustomTiresF = bool,
    modCustomTiresR = bool,
    modLivery = modIndex,
    livery = function(v) return int(v, -1, 255) end,
}

for i = 1, #Config.Cosmetic.mods do
    RULES[Config.Cosmetic.mods[i].id] = modIndex
end

-- Performance keys are never cosmetic (the server drops them too)
for _, cfg in pairs(Config.Performance) do
    RULES[cfg.propKey] = nil
end

---Clean copy of a cosmetic props table: only whitelisted keys with valid values.
---@param props table|nil
---@return table
function Presets.CleanProps(props)
    local out = {}
    if type(props) ~= 'table' then return out end

    for key, rule in pairs(RULES) do
        local value = props[key]
        if value ~= nil then
            local clean = rule(value)
            if clean ~= nil then out[key] = clean end
        end
    end

    return out
end

---Clean { [category] = level } (levels 0..#levels of Config.Performance).
---@param perf table|nil
---@return table
function Presets.CleanPerformance(perf)
    local out = {}
    if type(perf) ~= 'table' then return out end

    for category, level in pairs(perf) do
        local cfg = type(category) == 'string' and Config.Performance[category]
        local lvl = cfg and int(level, 0, #cfg.levels)
        if lvl then out[category] = lvl end
    end

    return out
end

---Preset name as the server will accept it (control/markup characters removed), or nil.
---@param name any
---@return string|nil
function Presets.CleanName(name)
    if type(name) ~= 'string' then return nil end
    name = name:gsub('%c', ' '):gsub('[<>"\'`\\]', ''):gsub('%s%s+', ' ')
    name = name:gsub('^%s+', ''):gsub('%s+$', '')

    local len = utf8.len(name)
    if not len or len < 1 then return nil end
    if len > MAX_NAME then
        name = name:sub(1, (utf8.offset(name, MAX_NAME + 1) or (#name + 1)) - 1)
    end

    return name
end

Presets.MaxNameLength = MAX_NAME

-- ---------------------------------------------------------------------------
-- Server calls (every one returns ok, data like lib.callback; data = locale key on failure)
-- ---------------------------------------------------------------------------

-- Minimum gap (ms) between two calls of one callback, a little above the server's rate limits in
-- server/presets.lua, so a quick second click waits instead of failing with 'too_fast'.
-- successGap: longer cooldown the server applies after a successful call.
local GAP = {
    ['preset:list'] = { gap = 550 },
    ['preset:get'] = { gap = 350 },
    ['preset:save'] = { gap = 2100 },
    ['preset:delete'] = { gap = 1100 },
    ['terminal:open'] = { gap = 1100 },
    ['workorder:get'] = { gap = 550 },
    ['workorder:save'] = { gap = 1100, successGap = 5100 },
    ['workorder:clear'] = { gap = 1100 },
}
local nextAllowed = {}

local function await(name, ...)
    local rule = GAP[name]
    local readyAt = nextAllowed[name]
    if readyAt then
        while GetGameTimer() < readyAt do Wait(50) end
    end

    local ok, data = lib.callback.await('ap1le_mechanicjob:' .. name, false, ...)

    if rule then
        nextAllowed[name] = GetGameTimer() + ((ok == true and rule.successGap) or rule.gap)
    end

    if ok == nil then return false, 'error' end -- no answer (timeout / resource restart)
    return ok == true, data
end

local listCache = { model = nil, at = 0, data = nil }

---Built-in and own presets for a model. Answers are cached briefly so a quick re-open of the list
---never hits the server's rate limit.
---@param model integer
---@param force? boolean bypass the cache (after a save or delete)
---@return boolean ok, table|string data { builtin = { {id,label} }, mine = { {id,name,created_at} } }
function Presets.List(model, force)
    local now = GetGameTimer()
    if not force and listCache.data and listCache.model == model and now - listCache.at < LIST_CACHE_MS then
        return true, listCache.data
    end

    local ok, data = await('preset:list', model)
    if not ok or type(data) ~= 'table' then return false, data end

    local clean = { builtin = {}, mine = {} }
    for i = 1, #(type(data.builtin) == 'table' and data.builtin or {}) do
        local b = data.builtin[i]
        if type(b) == 'table' and type(b.id) == 'string' then
            clean.builtin[#clean.builtin + 1] = { id = b.id, label = tostring(b.label or b.id), builtin = true }
        end
    end
    for i = 1, #(type(data.mine) == 'table' and data.mine or {}) do
        local m = data.mine[i]
        local id = type(m) == 'table' and math.tointeger(m.id)
        if id then
            clean.mine[#clean.mine + 1] = { id = id, name = tostring(m.name or ''), created_at = tonumber(m.created_at) or 0 }
        end
    end

    listCache = { model = model, at = now, data = clean }
    return true, clean
end

function Presets.InvalidateList()
    listCache = { model = nil, at = 0, data = nil }
end

---@param id string|integer builtin id (string) or own preset id
---@return boolean ok, table|string data { id, name, builtin, data = { cosmetic, performance } }
function Presets.Get(id)
    if type(id) ~= 'string' then
        id = math.tointeger(tonumber(id))
        if not id then return false, 'preset_not_found' end
    end

    local ok, data = await('preset:get', id)
    if not ok or type(data) ~= 'table' or type(data.data) ~= 'table' then
        return false, ok and 'error' or data
    end

    return true, data
end

---@return boolean ok, table|string data { id, name, updated }
function Presets.Save(model, name, data)
    local ok, result = await('preset:save', model, name, data)
    if ok then Presets.InvalidateList() end
    return ok, result
end

---@return boolean ok, table|string data
function Presets.Delete(id)
    id = math.tointeger(tonumber(id))
    if not id then return false, 'preset_not_found' end

    local ok, result = await('preset:delete', id)
    if ok then Presets.InvalidateList() end
    return ok, result
end

---Data for the customer design mode (terminal): { workshop, plate, owned, levels, prices }.
function Presets.TerminalOpen(netId)
    return await('terminal:open', netId)
end

---The vehicle's open work order, or nil (ok = true, data = nil when there is none).
function Presets.WorkOrderGet(netId)
    local ok, data = await('workorder:get', netId)
    if not ok then return false, data end
    if type(data) ~= 'table' or type(data.data) ~= 'table' then return true, nil end
    return true, data
end

function Presets.WorkOrderSave(netId, data)
    return await('workorder:save', netId, data)
end

function Presets.WorkOrderClear(netId)
    return await('workorder:clear', netId)
end

-- ---------------------------------------------------------------------------
-- "Indlæs sidste": the last cancelled cart per plate (client KVP, newest LAST_MAX vehicles)
-- ---------------------------------------------------------------------------

---KVP key part for a plate: trimmed, upper case, only A-Z 0-9 (other characters become '_').
local function plateKey(plate)
    plate = tostring(plate or ''):gsub('^%s+', ''):gsub('%s+$', ''):upper()
    if plate == '' then return nil end
    return (plate:gsub('[^%w]', '_'))
end

local function readIndex()
    local raw = GetResourceKvpString(LAST_INDEX)
    if type(raw) ~= 'string' or raw == '' then return {} end

    local ok, list = pcall(json.decode, raw)
    if not ok or type(list) ~= 'table' then return {} end

    local clean = {}
    for i = 1, #list do
        if type(list[i]) == 'string' and list[i] ~= '' then clean[#clean + 1] = list[i] end
    end
    return clean
end

local function writeIndex(list)
    SetResourceKvp(LAST_INDEX, json.encode(list))
end

---Store the cancelled cart of a vehicle.
---@param plate string
---@param model integer
---@param changes { id: string, value: any }[]
---@param swaps? { category: string, level: integer }[]
---@return boolean stored
function Presets.SaveLast(plate, model, changes, swaps)
    local key = plateKey(plate)
    if not key or type(changes) ~= 'table' then return false end

    local cleanChanges = {}
    for i = 1, math.min(#changes, LAST_MAX_CHANGES) do
        local c = changes[i]
        if type(c) == 'table' and type(c.id) == 'string' and #c.id <= 64 and c.value ~= nil
            and (type(c.value) ~= 'table' or #json.encode(c.value) <= 64) then
            cleanChanges[#cleanChanges + 1] = { id = c.id, value = c.value }
        end
    end

    local cleanSwaps = {}
    for i = 1, #(type(swaps) == 'table' and swaps or {}) do
        local s = swaps[i]
        local cfg = type(s) == 'table' and type(s.category) == 'string' and Config.Performance[s.category]
        local level = cfg and int(s.level, 0, #cfg.levels)
        if level then cleanSwaps[#cleanSwaps + 1] = { category = s.category, level = level } end
    end

    if #cleanChanges == 0 and #cleanSwaps == 0 then return false end

    local encoded = json.encode({
        model = math.tointeger(model) or 0,
        at = GetCloudTimeAsInt(),
        changes = cleanChanges,
        swaps = cleanSwaps,
    })
    if #encoded > LAST_MAX_BYTES then return false end

    SetResourceKvp(LAST_PREFIX .. key, encoded)

    -- Newest first; drop the oldest beyond LAST_MAX
    local list = readIndex()
    local out = { key }
    for i = 1, #list do
        if list[i] ~= key then out[#out + 1] = list[i] end
    end
    for i = #out, LAST_MAX + 1, -1 do
        DeleteResourceKvp(LAST_PREFIX .. out[i])
        out[i] = nil
    end
    writeIndex(out)

    return true
end

---The stored cart of a vehicle, or nil. Only for the same model (mod indices differ per model).
---@param plate string
---@param model integer
---@return { at: integer, changes: table[], swaps: table[] }|nil
function Presets.GetLast(plate, model)
    local key = plateKey(plate)
    if not key then return nil end

    local raw = GetResourceKvpString(LAST_PREFIX .. key)
    if type(raw) ~= 'string' or raw == '' then return nil end

    local ok, data = pcall(json.decode, raw)
    if not ok or type(data) ~= 'table' or type(data.changes) ~= 'table' then return nil end

    local stored = math.tointeger(data.model)
    model = math.tointeger(model)
    if stored and model and stored ~= 0 and (stored & 0xFFFFFFFF) ~= (model & 0xFFFFFFFF) then return nil end

    local swaps = type(data.swaps) == 'table' and data.swaps or {}
    if #data.changes == 0 and #swaps == 0 then return nil end

    return { at = tonumber(data.at) or 0, changes = data.changes, swaps = swaps }
end

---Forget the stored cart of a vehicle (after it was installed).
---@param plate string
function Presets.ClearLast(plate)
    local key = plateKey(plate)
    if not key then return end

    DeleteResourceKvp(LAST_PREFIX .. key)

    local list = readIndex()
    local out = {}
    for i = 1, #list do
        if list[i] ~= key then out[#out + 1] = list[i] end
    end
    writeIndex(out)
end
