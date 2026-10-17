-- ap1le_mechanicjob: shared server helpers (global Mechanic table) and the shared cancel callback.
-- Every other server file relies on these helpers; nothing here trusts client input.

Mechanic = Mechanic or {}

-- One pending action (repair or swap) per player: { kind, netId, startedAt, minMs, expiresAt, ... }
Mechanic.Pending = {}

-- Per-player, per-key timestamps for Mechanic.RateLimit
local rateLimits = {}

-- A pending action older than its expected length plus this grace is considered abandoned
local PENDING_GRACE_MS = 120000

-- Longest string Mechanic.Trim accepts. The trim pattern is quadratic on whitespace-heavy input,
-- so client strings are capped before it runs (plates are <= 8 chars, invoice labels <= 192 bytes).
local MAX_TRIM_LENGTH = 256

-- Max distance (m) between a vehicle and its online owner for performance swaps / cosmetic saves
local MAX_OWNER_DISTANCE = 30.0

---Trim leading/trailing whitespace from a plate (or short label).
---Returns nil for non-strings and strings longer than MAX_TRIM_LENGTH.
---@param plate any
---@return string|nil
function Mechanic.Trim(plate)
    if type(plate) ~= 'string' or #plate > MAX_TRIM_LENGTH then return nil end
    return (string.gsub(plate, '^%s*(.-)%s*$', '%1'))
end

---True if v is a finite integral number within [min, max].
---@param v any
---@param min number
---@param max number
---@return boolean
function Mechanic.IsInt(v, min, max)
    if type(v) ~= 'number' or v ~= v or v == math.huge or v == -math.huge then return false end
    if v % 1 ~= 0 then return false end
    return v >= min and v <= max
end

---Log a suspicious call.
---@param source number
---@param reason string
function Mechanic.Flag(source, reason)
    local name = GetPlayerName(source) or 'unknown'
    print(('[ap1le_mechanicjob] suspicious: %s (%s): %s'):format(name, tostring(source), tostring(reason)))
end

---Simple per-player rate limit. Returns true if the call is allowed (and records it).
---@param source number
---@param key string
---@param ms number
---@return boolean
function Mechanic.RateLimit(source, key, ms)
    local now = GetGameTimer()
    local list = rateLimits[source]

    if not list then
        list = {}
        rateLimits[source] = list
    end

    local last = list[key]
    if last and now - last < ms then
        return false
    end

    list[key] = now
    return true
end

---Returns the xPlayer if the player exists and has the mechanic job.
---@param source number
---@return table|nil
function Mechanic.GetMechanic(source)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer or not xPlayer.job or xPlayer.job.name ~= Config.Job then
        return nil
    end
    return xPlayer
end

---Returns the workshop table the coords are inside, or nil.
---@param coords vector3
---@return table|nil
function Mechanic.InWorkshop(coords)
    if not coords then return nil end

    for i = 1, #Config.Workshops do
        local ws = Config.Workshops[i]
        if #(coords - ws.coords) <= ws.radius then
            return ws
        end
    end

    return nil
end

---Workshop the player's ped is currently in (server-side ped position), or nil.
---@param source number
---@return table|nil
function Mechanic.PlayerWorkshop(source)
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end
    return Mechanic.InWorkshop(GetEntityCoords(ped))
end

---Resolve a client-supplied network id to a vehicle entity close to the player.
---Second return value is a locale error key when the lookup fails.
---@param source number
---@param netId any
---@return number|nil entity
---@return string|nil err
function Mechanic.GetVehicle(source, netId)
    if not Mechanic.IsInt(netId, 1, 0xFFFFFF) then
        return nil, 'error'
    end

    local entity = NetworkGetEntityFromNetworkId(math.tointeger(netId))
    if not entity or entity == 0 or not DoesEntityExist(entity) or GetEntityType(entity) ~= 2 then
        return nil, 'error'
    end

    local ped = GetPlayerPed(source)
    if not ped or ped == 0 or not DoesEntityExist(ped) then
        return nil, 'error'
    end

    if GetEntityRoutingBucket(ped) ~= GetEntityRoutingBucket(entity) then
        return nil, 'too_far'
    end

    if #(GetEntityCoords(ped) - GetEntityCoords(entity)) > Config.MaxVehicleDistance then
        return nil, 'too_far'
    end

    return entity
end

---Trimmed plate of a vehicle entity, read server-side.
---@param entity number
---@return string|nil
function Mechanic.EntityPlate(entity)
    local plate = Mechanic.Trim(GetVehicleNumberPlateText(entity))
    if not plate or plate == '' then return nil end
    return plate
end

---Load an owned vehicle by trimmed plate.
---Returns nil if not owned, false if the row exists but its JSON is unreadable.
---@param plate string trimmed plate
---@return table|nil|false row { plate = <stored plate>, owner = <identifier>, props = <decoded table> }
function Mechanic.FetchOwned(plate)
    if type(plate) ~= 'string' or plate == '' or #plate > 16 then return nil end

    local row = MySQL.single.await('SELECT plate, owner, vehicle FROM owned_vehicles WHERE TRIM(plate) = ? LIMIT 1', { plate })
    if not row then return nil end

    local props = {}
    if type(row.vehicle) == 'string' and row.vehicle ~= '' then
        local ok, decoded = pcall(json.decode, row.vehicle)
        if not ok or type(decoded) ~= 'table' then
            print(('[ap1le_mechanicjob] owned_vehicles.vehicle JSON for plate "%s" is unreadable'):format(plate))
            return false
        end
        props = decoded
    end

    return { plate = row.plate, owner = row.owner, props = props }
end

---The entity's plate is set by the client that owns it, so a matching plate alone does not prove
---this is the stored car. Checks that the entity model matches the stored model (when stored) and
---that the stored owner is the mechanic, or is online and close to the vehicle.
---Returns true, or false + locale error key. Run before any item or DB change.
---@param source number
---@param vehicle number entity
---@param owned table row from Mechanic.FetchOwned
---@return boolean ok
---@return string|nil err
function Mechanic.CheckOwnedVehicle(source, vehicle, owned)
    local storedModel = tonumber(owned.props and owned.props.model)
    if storedModel then
        storedModel = math.tointeger(math.floor(storedModel))
        -- Mask both sides: one may be a signed and the other an unsigned 32-bit hash
        if not storedModel or (GetEntityModel(vehicle) & 0xFFFFFFFF) ~= (storedModel & 0xFFFFFFFF) then
            Mechanic.Flag(source, ('vehicle model does not match the stored model for plate "%s"'):format(tostring(owned.plate)))
            return false, 'not_owned'
        end
    end

    local owner = owned.owner
    if type(owner) ~= 'string' or owner == '' then return false, 'not_available' end

    local xMechanic = ESX.GetPlayerFromId(source)
    if xMechanic and xMechanic.identifier == owner then return true end

    local xOwner = ESX.GetPlayerFromIdentifier(owner)
    if not xOwner then return false, 'not_available' end

    local ownerPed = GetPlayerPed(xOwner.source)
    if not ownerPed or ownerPed == 0 or not DoesEntityExist(ownerPed) then return false, 'not_available' end

    if GetEntityRoutingBucket(ownerPed) ~= GetEntityRoutingBucket(vehicle)
        or #(GetEntityCoords(ownerPed) - GetEntityCoords(vehicle)) > MAX_OWNER_DISTANCE then
        return false, 'not_available'
    end

    return true
end

---Level of a part this resource installed on a plate (server-only record), or nil if none.
---@param plate string trimmed plate
---@param category string Config.Performance key
---@return integer|nil
function Mechanic.GetInstalledLevel(plate, category)
    local ok, level = pcall(MySQL.scalar.await, 'SELECT `level` FROM `ap1le_mechanicjob_parts` WHERE `plate` = ? AND `category` = ?', { plate, category })
    if not ok then
        print(('[ap1le_mechanicjob] reading ap1le_mechanicjob_parts failed (was sql/install.sql run?): %s'):format(tostring(level)))
        return nil
    end
    return math.tointeger(tonumber(level))
end

---Record the level this resource installed on a plate. Returns true on success.
---@param plate string trimmed plate
---@param category string
---@param level integer
---@return boolean
function Mechanic.SetInstalledLevel(plate, category, level)
    local ok, affected = pcall(MySQL.update.await,
        'INSERT INTO `ap1le_mechanicjob_parts` (`plate`, `category`, `level`) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE `level` = ?',
        { plate, category, level, level })
    if not ok or type(affected) ~= 'number' then
        print(('[ap1le_mechanicjob] saving ap1le_mechanicjob_parts for plate "%s" failed: %s'):format(plate, tostring(affected)))
        return false
    end
    return true
end

-- Plates whose owned_vehicles row is in a read-modify-write right now
local plateLocks = {}

---Lock a plate for a read-modify-write of its DB row. Returns false if already locked.
---Locks auto-expire after 10 s so a failed query can never block a plate forever.
---@param plate string trimmed plate
---@return boolean
function Mechanic.LockPlate(plate)
    local now = GetGameTimer()
    local lockedAt = plateLocks[plate]
    if lockedAt and now - lockedAt < 10000 then
        return false
    end
    plateLocks[plate] = now
    return true
end

---@param plate string trimmed plate
function Mechanic.UnlockPlate(plate)
    plateLocks[plate] = nil
end

---Performance level (0 = stock .. #levels) from stored vehicle props.
---Second return value is false if the stored value is outside the configured range
---(the level is then clamped and no item should be returned for it).
---@param cfg table Config.Performance entry
---@param props table
---@return integer level
---@return boolean inRange
function Mechanic.LevelFromProps(cfg, props)
    local value = props[cfg.propKey]
    local maxLevel = #cfg.levels

    if cfg.toggle then
        local on = value == true or value == 1
        return on and 1 or 0, true
    end

    if type(value) ~= 'number' or value ~= value or value % 1 ~= 0 then
        return 0, true
    end

    local level = math.tointeger(value + 1) or 0
    if level < 0 then
        return 0, false
    elseif level > maxLevel then
        return maxLevel, false
    end

    return level, true
end

---Stored props value for a performance level (inverse of LevelFromProps).
---@param cfg table
---@param level integer
---@return integer|boolean
function Mechanic.PropsValueForLevel(cfg, level)
    if cfg.toggle then
        return level > 0
    end
    return level - 1
end

---Notify a player through the shared client event.
---@param target number
---@param msg string
---@param nType? string success|error|inform
function Mechanic.Notify(target, msg, nType)
    TriggerClientEvent('ap1le_mechanicjob:notify', target, msg, nType or 'inform')
end

---Return the player's current pending action, dropping it first if it has been abandoned.
---@param source number
---@return table|nil
function Mechanic.GetPending(source)
    local pending = Mechanic.Pending[source]
    if pending and pending.expiresAt and GetGameTimer() > pending.expiresAt then
        Mechanic.Pending[source] = nil
        return nil
    end
    return pending
end

---Store a pending action for the player.
---@param source number
---@param data table must contain kind, netId, minMs; expectedMs is used for the abandon timeout
function Mechanic.SetPending(source, data)
    local now = GetGameTimer()
    data.startedAt = now
    data.expiresAt = now + math.floor((data.expectedMs or data.minMs or 0) * 2) + PENDING_GRACE_MS
    Mechanic.Pending[source] = data
end

---Elapsed-time check against pending.minMs.
---@param pending table
---@return boolean
function Mechanic.ElapsedOk(pending)
    return GetGameTimer() - pending.startedAt >= pending.minMs
end

-- Shared cancel for repair and swap
lib.callback.register('ap1le_mechanicjob:cancel', function(source)
    Mechanic.Pending[source] = nil
    return true
end)

AddEventHandler('playerDropped', function()
    local src = source
    Mechanic.Pending[src] = nil
    rateLimits[src] = nil
end)

-- A player who loses the job mid-action loses the pending action too
-- (the job is re-read from ESX, so a forged trigger of this event cannot clear someone else's action)
AddEventHandler('esx:setJob', function(playerId)
    if type(playerId) ~= 'number' or not Mechanic.Pending[playerId] then return end
    if not Mechanic.GetMechanic(playerId) then
        Mechanic.Pending[playerId] = nil
    end
end)
