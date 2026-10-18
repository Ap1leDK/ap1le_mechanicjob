-- ap1le_mechanicjob: tuning presets and customer work orders (v3 section C).
--
-- Preset data = { cosmetic = { [ox_lib prop key] = value }, performance = { [category] = level } }.
-- Cosmetic keys and values are validated with the tuning save whitelist (Mechanic.CleanCosmetic from
-- server/tuning.lua); performance categories must be Config.Performance keys with a level 0..#levels.
-- Cosmetic mod indices differ per model, so a player's own presets belong to one model; the built-in
-- presets (Config.Presets.builtin) work on every model.
--
-- Work orders: a customer designs the car at a workshop terminal and sends it "to the mechanic". It is
-- stored per plate (one per vehicle) and expires after Config.Presets.workOrderHours.
--
-- Times in both tables are unix seconds (os.time()), like every other table of this resource.

local presetsCfg = Config.Presets or {}
local MAX_PER_PLAYER = math.tointeger(presetsCfg.maxPerPlayer) or 30
local MAX_NAME = math.tointeger(presetsCfg.maxNameLength) or 32
local WORKORDER_SECONDS = math.floor((tonumber(presetsCfg.workOrderHours) or 72) * 3600)
local MAX_DATA_BYTES = 16384                 -- encoded JSON size cap for one preset / work order
local CLEANUP_INTERVAL_MS = 30 * 60000       -- expired work orders are deleted this often
local WORKORDER_COOLDOWN_MS = 5000           -- between two saved work orders of one player

-- ---------------------------------------------------------------------------------------------
-- Validation
-- ---------------------------------------------------------------------------------------------

---Validate preset / work order data.
---strict = true (client data): any unknown key or malformed value rejects the whole table, and at
---least one entry is required. strict = false (data read back from the DB): invalid entries are
---dropped, so a config change can never break loading an older preset.
---@param data any
---@param strict boolean
---@return table|nil clean { cosmetic = {}, performance = {} }
local function sanitiseData(data, strict)
    if type(data) ~= 'table' then return nil end

    for key in pairs(data) do
        if key ~= 'cosmetic' and key ~= 'performance' and strict then return nil end
    end

    local cosmetic, performance, entries = {}, {}, 0

    local rawCosmetic = data.cosmetic
    if rawCosmetic ~= nil then
        if type(rawCosmetic) ~= 'table' then
            if strict then return nil end
        else
            local count, maxKeys = 0, Mechanic.CosmeticKeyCount()
            for key, value in pairs(rawCosmetic) do
                count = count + 1
                if count > maxKeys then
                    if strict then return nil end
                    break
                end
                local clean = Mechanic.CleanCosmetic(key, value)
                if clean ~= nil then
                    cosmetic[key] = clean
                    entries = entries + 1
                elseif strict then
                    return nil
                end
            end
        end
    end

    local rawPerformance = data.performance
    if rawPerformance ~= nil then
        if type(rawPerformance) ~= 'table' then
            if strict then return nil end
        else
            for category, level in pairs(rawPerformance) do
                local cfg = type(category) == 'string' and Config.Performance[category]
                if cfg and Mechanic.IsInt(level, 0, #cfg.levels) then
                    performance[category] = math.tointeger(level)
                    entries = entries + 1
                elseif strict then
                    return nil
                end
            end
        end
    end

    if strict and entries == 0 then return nil end

    local clean = { cosmetic = cosmetic, performance = performance }
    if #json.encode(clean) > MAX_DATA_BYTES then return nil end
    return clean
end

---Decode stored JSON data and re-validate it leniently.
---@param raw any
---@return table|nil
local function decodeData(raw)
    if type(raw) ~= 'string' or raw == '' then return nil end
    local ok, decoded = pcall(json.decode, raw)
    if not ok then return nil end
    return sanitiseData(decoded, false)
end

---Unsigned 32-bit model hash from a client value (signed or unsigned), or nil.
---@param model any
---@return integer|nil
local function cleanModel(model)
    if not Mechanic.IsInt(model, -2147483648, 4294967295) then return nil end
    local hash = math.tointeger(model) & 0xFFFFFFFF
    if hash == 0 then return nil end
    return hash
end

-- ---------------------------------------------------------------------------------------------
-- Built-in presets
-- ---------------------------------------------------------------------------------------------

local builtinList, builtinById = {}, {}

for i = 1, #(presetsCfg.builtin or {}) do
    local b = presetsCfg.builtin[i]
    if type(b) == 'table' and type(b.id) == 'string' and not builtinById[b.id] then
        local data = { cosmetic = {}, performance = {} }
        if b.performance == 'max' then
            -- Every performance category at its highest level, no cosmetics
            for category, cfg in pairs(Config.Performance) do
                data.performance[category] = #cfg.levels
            end
        end
        local entry = { id = b.id, label = tostring(b.label or b.id), data = data }
        builtinById[b.id] = entry
        builtinList[#builtinList + 1] = { id = b.id, label = entry.label, builtin = true }
    end
end

---Deep copy of a preset data table (built-ins are shared and must never be changed by a caller).
local function copyData(data)
    local copy = { cosmetic = {}, performance = {} }
    for k, v in pairs(data.cosmetic) do
        if type(v) == 'table' then
            local t = {}
            for i, x in pairs(v) do t[i] = x end
            copy.cosmetic[k] = t
        else
            copy.cosmetic[k] = v
        end
    end
    for k, v in pairs(data.performance) do copy.performance[k] = v end
    return copy
end

-- ---------------------------------------------------------------------------------------------
-- Access
-- ---------------------------------------------------------------------------------------------

---A player who may use presets: a mechanic inside a workshop, or anyone at a customer terminal.
---Returns xPlayer, or nil + locale key.
local function presetUser(source, key, ms)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer or not Mechanic.IsIdentifier(xPlayer.identifier) then return nil, 'error' end
    if not Mechanic.RateLimit(source, key, ms) then return nil, 'too_fast' end

    if Mechanic.TerminalWorkshop(source) then return xPlayer end
    if Mechanic.GetMechanic(source) and Mechanic.PlayerWorkshop(source) then return xPlayer end

    return nil, 'preset_no_access'
end

---The player's own vehicle near them: owned_vehicles.owner must be the player and the entity model
---must match the stored model. Returns vehicle, plate, owned row, or nil + locale key.
local function ownVehicle(source, xPlayer, netId, action)
    local vehicle, err = Mechanic.GetVehicle(source, netId)
    if not vehicle then
        if err == 'error' then Mechanic.Flag(source, ('%s with invalid vehicle netId'):format(action)) end
        return nil, err or 'too_far'
    end

    local plate = Mechanic.EntityPlate(vehicle)
    if not plate then return nil, 'workorder_not_owned' end

    local owned = Mechanic.FetchOwned(plate)
    if owned == false then return nil, 'error' end
    if not owned or owned.owner ~= xPlayer.identifier then return nil, 'workorder_not_owned' end

    -- The plate is client-controlled: the entity must really be the stored car
    if not Mechanic.ModelMatches(vehicle, owned) then
        Mechanic.Flag(source, ('%s: vehicle model does not match the stored model for plate "%s"'):format(action, plate))
        return nil, 'workorder_not_owned'
    end

    return vehicle, plate, owned
end

---Mechanic inside a workshop with a vehicle close by. Returns vehicle, plate, workshop or nil + key.
local function mechanicVehicle(source, netId, key, ms)
    if not Mechanic.GetMechanic(source) then return nil, 'not_mechanic' end
    if not Mechanic.RateLimit(source, key, ms) then return nil, 'too_fast' end

    local workshop = Mechanic.PlayerWorkshop(source)
    if not workshop then return nil, 'not_in_workshop' end

    local vehicle, err = Mechanic.GetVehicle(source, netId)
    if not vehicle then
        if err == 'error' then Mechanic.Flag(source, ('%s with invalid vehicle netId'):format(key)) end
        return nil, err or 'too_far'
    end

    local plate = Mechanic.EntityPlate(vehicle)
    if not plate then return nil, 'error' end

    return vehicle, plate, workshop
end

-- ---------------------------------------------------------------------------------------------
-- Presets
-- ---------------------------------------------------------------------------------------------

lib.callback.register('ap1le_mechanicjob:preset:list', function(source, model)
    local xPlayer, err = presetUser(source, 'preset:list', 500)
    if not xPlayer then return false, err end

    local hash = cleanModel(model)
    if not hash then
        Mechanic.Flag(source, 'preset:list with an invalid model')
        return false, 'error'
    end

    -- MAX_PER_PLAYER is a validated integer from config, so it is formatted in (some MySQL versions reject a bound LIMIT)
    local ok, rows = pcall(MySQL.query.await, ([[
        SELECT `id`, `name`, `created_at` FROM `ap1le_mechanicjob_presets`
        WHERE `owner` = ? AND `model` = ? ORDER BY `name` LIMIT %d]]):format(MAX_PER_PLAYER), { xPlayer.identifier, hash })
    if not ok or type(rows) ~= 'table' then
        print(('[ap1le_mechanicjob] preset:list failed (was sql/install.sql run?): %s'):format(tostring(rows)))
        return false, 'error'
    end

    local mine = {}
    for i = 1, #rows do
        mine[i] = { id = math.tointeger(tonumber(rows[i].id)), name = tostring(rows[i].name or ''), created_at = tonumber(rows[i].created_at) or 0 }
    end

    local builtin = {}
    for i = 1, #builtinList do
        builtin[i] = { id = builtinList[i].id, label = builtinList[i].label, builtin = true }
    end

    return true, { builtin = builtin, mine = mine }
end)

lib.callback.register('ap1le_mechanicjob:preset:get', function(source, id)
    local xPlayer, err = presetUser(source, 'preset:get', 300)
    if not xPlayer then return false, err end

    if type(id) == 'string' then
        local b = #id <= 64 and builtinById[id]
        if not b then return false, 'preset_not_found' end
        return true, { id = b.id, name = b.label, builtin = true, data = copyData(b.data) }
    end

    if not Mechanic.IsInt(id, 1, 4294967295) then
        Mechanic.Flag(source, 'preset:get with an invalid id')
        return false, 'error'
    end

    local ok, row = pcall(MySQL.single.await,
        'SELECT `id`, `name`, `model`, `data` FROM `ap1le_mechanicjob_presets` WHERE `id` = ? AND `owner` = ?',
        { math.tointeger(id), xPlayer.identifier })
    if not ok then
        print(('[ap1le_mechanicjob] preset:get failed: %s'):format(tostring(row)))
        return false, 'error'
    end
    if not row then return false, 'preset_not_found' end

    local data = decodeData(row.data)
    if not data then
        print(('[ap1le_mechanicjob] preset %s has unreadable data'):format(tostring(row.id)))
        return false, 'error'
    end

    return true, {
        id = math.tointeger(tonumber(row.id)),
        name = tostring(row.name or ''),
        model = math.tointeger(tonumber(row.model)),
        builtin = false,
        data = data,
    }
end)

-- Owners with a save in progress (the count check and the insert yield)
local saving = {}

---Body of preset:save, runs while the owner is locked.
local function savePreset(xPlayer, hash, name, clean)
    local identifier = xPlayer.identifier
    local encoded = json.encode(clean)

    -- Same name on the same model: overwrite (does not count against the limit)
    local okFind, existing = pcall(MySQL.scalar.await,
        'SELECT `id` FROM `ap1le_mechanicjob_presets` WHERE `owner` = ? AND `model` = ? AND `name` = ? LIMIT 1',
        { identifier, hash, name })
    if not okFind then
        print(('[ap1le_mechanicjob] preset:save failed (was sql/install.sql run?): %s'):format(tostring(existing)))
        return false, 'error'
    end

    existing = math.tointeger(tonumber(existing))
    if existing then
        local okUpd, affected = pcall(MySQL.update.await,
            'UPDATE `ap1le_mechanicjob_presets` SET `data` = ?, `owner_name` = ? WHERE `id` = ? AND `owner` = ?',
            { encoded, Mechanic.PlayerName(xPlayer), existing, identifier })
        if not okUpd or type(affected) ~= 'number' then return false, 'error' end
        return true, { id = existing, name = name, updated = true }
    end

    local okCount, count = pcall(MySQL.scalar.await,
        'SELECT COUNT(*) FROM `ap1le_mechanicjob_presets` WHERE `owner` = ?', { identifier })
    if not okCount then return false, 'error' end
    if (tonumber(count) or 0) >= MAX_PER_PLAYER then return false, 'preset_limit' end

    local okIns, id = pcall(MySQL.insert.await, [[
        INSERT INTO `ap1le_mechanicjob_presets` (`owner`, `owner_name`, `name`, `model`, `data`, `created_at`)
        VALUES (?, ?, ?, ?, ?, ?)
    ]], { identifier, Mechanic.PlayerName(xPlayer), name, hash, encoded, os.time() })
    if not okIns or not id or id == 0 then
        print(('[ap1le_mechanicjob] saving a preset failed: %s'):format(tostring(id)))
        return false, 'error'
    end

    return true, { id = id, name = name, updated = false }
end

lib.callback.register('ap1le_mechanicjob:preset:save', function(source, model, name, data)
    local xPlayer, err = presetUser(source, 'preset:save', 2000)
    if not xPlayer then return false, err end

    local hash = cleanModel(model)
    if not hash then
        Mechanic.Flag(source, 'preset:save with an invalid model')
        return false, 'error'
    end

    local cleanName = Mechanic.SanitiseText(name, MAX_NAME)
    if not cleanName then return false, 'preset_name_invalid' end

    local clean = sanitiseData(data, true)
    if not clean then
        Mechanic.Flag(source, 'preset:save with invalid data')
        return false, 'preset_invalid'
    end

    local identifier = xPlayer.identifier
    if saving[identifier] then return false, 'busy' end
    saving[identifier] = true

    local ok, success, result = pcall(savePreset, xPlayer, hash, cleanName, clean)
    saving[identifier] = nil

    if not ok then
        print(('[ap1le_mechanicjob] preset:save error: %s'):format(tostring(success)))
        return false, 'error'
    end

    return success, result
end)

lib.callback.register('ap1le_mechanicjob:preset:delete', function(source, id)
    local xPlayer, err = presetUser(source, 'preset:delete', 1000)
    if not xPlayer then return false, err end

    if type(id) == 'string' and builtinById[id] then return false, 'preset_builtin' end
    if not Mechanic.IsInt(id, 1, 4294967295) then
        Mechanic.Flag(source, 'preset:delete with an invalid id')
        return false, 'error'
    end

    -- Own presets only: the owner is part of the WHERE clause
    local ok, affected = pcall(MySQL.update.await,
        'DELETE FROM `ap1le_mechanicjob_presets` WHERE `id` = ? AND `owner` = ?', { math.tointeger(id), xPlayer.identifier })
    if not ok or type(affected) ~= 'number' then
        print(('[ap1le_mechanicjob] preset:delete failed: %s'):format(tostring(affected)))
        return false, 'error'
    end
    if affected < 1 then return false, 'preset_not_found' end

    return true, { id = math.tointeger(id) }
end)

-- ---------------------------------------------------------------------------------------------
-- Customer terminal and work orders
-- ---------------------------------------------------------------------------------------------

-- Data the design mode needs for the customer's own vehicle: price estimates and current levels.
lib.callback.register('ap1le_mechanicjob:terminal:open', function(source, netId)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer or not Mechanic.IsIdentifier(xPlayer.identifier) then return false, 'error' end
    if not Mechanic.RateLimit(source, 'terminal:open', 1000) then return false, 'too_fast' end

    local workshop = Mechanic.TerminalWorkshop(source)
    if not workshop then return false, 'terminal_too_far' end

    local vehicle, plate, owned = ownVehicle(source, xPlayer, netId, 'terminal:open')
    if not vehicle then return false, plate end

    -- The DB query yielded: still at the same terminal
    if Mechanic.TerminalWorkshop(source) ~= workshop then return false, 'terminal_too_far' end

    return true, {
        workshop = workshop.id,
        plate = plate,
        owned = true,
        levels = Mechanic.PerformanceLevels(owned),
        prices = Mechanic.GetPrices(),
    }
end)

---Notify the mechanics who are inside a workshop right now.
-- [plate] = GetGameTimer() of the last 'new work order' notification
local workOrderNotifiedAt = {}
local WORKORDER_NOTIFY_MS = 60000

local function notifyWorkshop(workshop, msg)
    local ok, players = pcall(ESX.GetExtendedPlayers, 'job', Config.Job)
    if not ok or type(players) ~= 'table' then return end
    for i = 1, #players do
        local src = players[i].source
        if Mechanic.PlayerWorkshop(src) == workshop then
            Mechanic.Notify(src, msg, 'info')
        end
    end
end

lib.callback.register('ap1le_mechanicjob:workorder:save', function(source, netId, data)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer or not Mechanic.IsIdentifier(xPlayer.identifier) then return false, 'error' end
    -- Short anti-spam window for every attempt; the longer cooldown only after a saved work order
    if not Mechanic.RateLimit(source, 'workorder:save:attempt', 1000) then return false, 'too_fast' end
    if not Mechanic.RateLimitCheck(source, 'workorder:save', WORKORDER_COOLDOWN_MS) then return false, 'too_fast' end

    local workshop = Mechanic.TerminalWorkshop(source)
    if not workshop then return false, 'terminal_too_far' end

    local clean = sanitiseData(data, true)
    if not clean then
        Mechanic.Flag(source, 'workorder:save with invalid data')
        return false, 'preset_invalid'
    end

    local vehicle, plate = ownVehicle(source, xPlayer, netId, 'workorder:save')
    if not vehicle then return false, plate end

    -- The DB query yielded: still at the same terminal with the same car close by
    if Mechanic.TerminalWorkshop(source) ~= workshop then return false, 'terminal_too_far' end
    local again = Mechanic.GetVehicle(source, netId)
    if again ~= vehicle or Mechanic.EntityPlate(vehicle) ~= plate then return false, 'too_far' end

    local now = os.time()
    local expiresAt = now + WORKORDER_SECONDS
    -- update.await: affected rows = 1 for a new row, 2 for a replaced one (the key is the plate, not an id)
    local ok, result = pcall(MySQL.update.await, [[
        INSERT INTO `ap1le_mechanicjob_workorders`
            (`plate`, `workshop`, `model`, `data`, `owner`, `owner_name`, `created_at`, `expires_at`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE `workshop` = VALUES(`workshop`), `model` = VALUES(`model`), `data` = VALUES(`data`),
            `owner` = VALUES(`owner`), `owner_name` = VALUES(`owner_name`), `created_at` = VALUES(`created_at`),
            `expires_at` = VALUES(`expires_at`)
    ]], { plate, workshop.id, Mechanic.ModelHash(vehicle), json.encode(clean), xPlayer.identifier,
          Mechanic.PlayerName(xPlayer), now, expiresAt })
    if not ok or type(result) ~= 'number' then
        print(('[ap1le_mechanicjob] saving the work order for plate "%s" failed (was sql/install.sql run?): %s'):format(plate, tostring(result)))
        return false, 'error'
    end

    Mechanic.RateLimitMark(source, 'workorder:save')
    -- Tell the mechanics about a new work order, but at most once a minute per plate, so a customer
    -- re-sending (or a script spamming) workorder:save cannot flood every mechanic with notifications
    local now = GetGameTimer()
    if now - (workOrderNotifiedAt[plate] or -WORKORDER_NOTIFY_MS) >= WORKORDER_NOTIFY_MS then
        workOrderNotifiedAt[plate] = now
        notifyWorkshop(workshop, locale('workorder_new', plate))
    end

    return true, { plate = plate, expires_at = expiresAt }
end)

lib.callback.register('ap1le_mechanicjob:workorder:get', function(source, netId)
    local vehicle, plate = mechanicVehicle(source, netId, 'workorder:get', 500)
    if not vehicle then return false, plate end

    local ok, row = pcall(MySQL.single.await, [[
        SELECT `plate`, `workshop`, `model`, `data`, `owner`, `owner_name`, `created_at`, `expires_at`
        FROM `ap1le_mechanicjob_workorders` WHERE `plate` = ? AND `expires_at` > ?
    ]], { plate, os.time() })
    if not ok then
        print(('[ap1le_mechanicjob] workorder:get failed (was sql/install.sql run?): %s'):format(tostring(row)))
        return false, 'error'
    end
    if not row then return true, nil end

    -- A work order is for exactly this car: same model, and the customer who sent it still owns it
    local model = math.tointeger(tonumber(row.model))
    if not DoesEntityExist(vehicle) or not model or (model & 0xFFFFFFFF) ~= Mechanic.ModelHash(vehicle) then return true, nil end

    local owned = Mechanic.FetchOwned(plate)
    if owned == false then return false, 'error' end
    if not owned or owned.owner ~= row.owner then return true, nil end

    local data = decodeData(row.data)
    if not data then return true, nil end

    return true, {
        plate = plate,
        workshop = row.workshop,
        owner_name = tostring(row.owner_name or ''),
        created_at = tonumber(row.created_at) or 0,
        expires_at = tonumber(row.expires_at) or 0,
        data = data,
    }
end)

lib.callback.register('ap1le_mechanicjob:workorder:clear', function(source, netId)
    local vehicle, plate = mechanicVehicle(source, netId, 'workorder:clear', 1000)
    if not vehicle then return false, plate end

    local ok, affected = pcall(MySQL.update.await, 'DELETE FROM `ap1le_mechanicjob_workorders` WHERE `plate` = ?', { plate })
    if not ok or type(affected) ~= 'number' then
        print(('[ap1le_mechanicjob] workorder:clear failed: %s'):format(tostring(affected)))
        return false, 'error'
    end

    return true, { cleared = affected > 0 }
end)

-- ---------------------------------------------------------------------------------------------
-- Expiry cleanup
-- ---------------------------------------------------------------------------------------------

local function cleanupWorkOrders()
    local ok, err = pcall(MySQL.update.await, 'DELETE FROM `ap1le_mechanicjob_workorders` WHERE `expires_at` <= ?', { os.time() })
    if not ok then
        print(('[ap1le_mechanicjob] deleting expired work orders failed (was sql/install.sql run?): %s'):format(tostring(err)))
    end
end

-- Exposed for the mocked tests
Mechanic.CleanupWorkOrders = cleanupWorkOrders
Mechanic.SanitisePresetData = sanitiseData

MySQL.ready(function()
    cleanupWorkOrders()

    CreateThread(function()
        while true do
            Wait(CLEANUP_INTERVAL_MS)
            cleanupWorkOrders()
        end
    end)
end)
