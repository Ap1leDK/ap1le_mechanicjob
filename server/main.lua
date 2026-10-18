-- ap1le_mechanicjob: shared server helpers (global Mechanic table) and the shared cancel callback.
-- Every other server file relies on these helpers; nothing here trusts client input.
-- Time values stored in the database by this resource are unix seconds (os.time()).

Mechanic = Mechanic or {}

-- One pending action (repair, swap, unpack or wash) per player: { kind, startedAt, minMs, expiresAt, ... }
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

-- Longest ESX identifier accepted from a client (users.identifier is VARCHAR(60) in ESX Legacy)
local MAX_IDENTIFIER_LENGTH = 64

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

---True if v looks like an ESX identifier (e.g. "char1:abc123", "license:abc123").
---Only letters, digits, ':', '_' and '-' are allowed, so it can never smuggle anything into a query or the UI.
---@param v any
---@return boolean
function Mechanic.IsIdentifier(v)
    return type(v) == 'string' and #v >= 1 and #v <= MAX_IDENTIFIER_LENGTH and v:match('^[%w:_%-]+$') ~= nil
end

---True if t is a plain array (keys 1..n, no holes, no extra keys) with 1..max entries.
---@param t any
---@param max integer
---@return boolean
function Mechanic.IsArray(t, max)
    if type(t) ~= 'table' then return false end
    local n = #t
    if n < 1 or n > max then return false end
    local count = 0
    for k in pairs(t) do
        count = count + 1
        if math.type(k) ~= 'integer' or k < 1 or k > n or count > n then return false end
    end
    return count == n
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

---Rate-limit check that does not record the call (pair with Mechanic.RateLimitMark after a success),
---so a failed attempt is never punished with a cooldown.
---@param source number
---@param key string
---@param ms number
---@return boolean allowed
function Mechanic.RateLimitCheck(source, key, ms)
    local list = rateLimits[source]
    local last = list and list[key]
    return not (last and GetGameTimer() - last < ms)
end

---Record a successful call for Mechanic.RateLimitCheck.
---@param source number
---@param key string
function Mechanic.RateLimitMark(source, key)
    local list = rateLimits[source]
    if not list then
        list = {}
        rateLimits[source] = list
    end
    list[key] = GetGameTimer()
end

---Clean a short user-provided text (preset names, labels): control characters become spaces,
---markup characters are removed, whitespace is collapsed and trimmed.
---Returns nil if the result is empty or longer than maxLen UTF-8 characters.
---@param text any
---@param maxLen integer
---@return string|nil
function Mechanic.SanitiseText(text, maxLen)
    if type(text) ~= 'string' or #text > maxLen * 4 then return nil end

    text = text:gsub('%c', ' '):gsub('[<>"\'`\\]', ''):gsub('%s%s+', ' ')
    text = Mechanic.Trim(text)

    local len = text and utf8.len(text)
    if not len or len < 1 or len > maxLen then return nil end

    return text
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

---Job grade of an xPlayer as an integer (0 if unreadable).
---@param xPlayer table
---@return integer
function Mechanic.GetGrade(xPlayer)
    local grade = xPlayer and xPlayer.job and tonumber(xPlayer.job.grade)
    return grade and math.tointeger(math.floor(grade)) or 0
end

---True if the xPlayer is a mechanic with grade >= Config.BossGrade.
---@param xPlayer table|nil
---@return boolean
function Mechanic.IsBoss(xPlayer)
    if not xPlayer or not xPlayer.job or xPlayer.job.name ~= Config.Job then return false end
    return Mechanic.GetGrade(xPlayer) >= Config.BossGrade
end

---Workshop config entry by id, or nil.
---@param id any
---@return table|nil
function Mechanic.WorkshopById(id)
    if type(id) ~= 'string' then return nil end
    for i = 1, #Config.Workshops do
        if Config.Workshops[i].id == id then return Config.Workshops[i] end
    end
    return nil
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

---Server-side position of the player's ped, or nil.
---@param source number
---@return vector3|nil coords
---@return number|nil ped
function Mechanic.PedCoords(source)
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end
    return GetEntityCoords(ped), ped
end

---Server-side position of the player's ped for workshop and computer checks, or nil.
---Workshops, stashes, laptops and crates only exist in the default routing bucket, so a player in
---another bucket (instanced interior, housing, race lobby) at the same coordinates is never inside one.
---@param source number
---@return vector3|nil
local function workshopCoords(source)
    local coords, ped = Mechanic.PedCoords(source)
    if not coords or GetEntityRoutingBucket(ped) ~= 0 then return nil end
    return coords
end

---Workshop the player's ped is currently in (server-side ped position), or nil.
---@param source number
---@return table|nil
function Mechanic.PlayerWorkshop(source)
    return Mechanic.InWorkshop(workshopCoords(source))
end

---vector3 from a vec3/vec4 or {x, y, z} table.
---@param c table
---@return vector3
function Mechanic.ToVec3(c)
    return vec3(c.x, c.y, c.z)
end

---Workshop whose computer is within Config.Computer.serverDistance of the player, or nil.
---@param source number
---@return table|nil
function Mechanic.ComputerWorkshop(source)
    local coords = workshopCoords(source)
    if not coords then return nil end

    for i = 1, #Config.Workshops do
        local ws = Config.Workshops[i]
        if ws.computer and ws.computer.coords
            and #(coords - Mechanic.ToVec3(ws.computer.coords)) <= Config.Computer.serverDistance then
            return ws
        end
    end

    return nil
end

-- Max distance (m) between a player and a workshop's customer terminal (server-checked)
local TERMINAL_DISTANCE = 3.0

---Workshop whose customer terminal is within TERMINAL_DISTANCE of the player, or nil.
---Anyone may use a terminal (no job check here).
---@param source number
---@return table|nil
function Mechanic.TerminalWorkshop(source)
    local coords = workshopCoords(source)
    if not coords then return nil end

    for i = 1, #Config.Workshops do
        local ws = Config.Workshops[i]
        if ws.terminal and #(coords - Mechanic.ToVec3(ws.terminal)) <= TERMINAL_DISTANCE then
            return ws
        end
    end

    return nil
end

---Workshop context for calls that work both in a workshop and at its computer
---(stock, orders): the computer's workshop first, then the workshop sphere.
---@param source number
---@return table|nil
function Mechanic.ContextWorkshop(source)
    return Mechanic.ComputerWorkshop(source) or Mechanic.PlayerWorkshop(source)
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

    -- Indexed lookup first: the trimmed plate, and the plate padded to 8 characters the way GTA
    -- returns it (ESX garages store either). TRIM() on the column cannot use the primary key, so the
    -- full-scan query only runs as a fallback for unusual spellings.
    local row = MySQL.single.await('SELECT plate, owner, vehicle FROM owned_vehicles WHERE plate IN (?, ?) LIMIT 1',
        { plate, ('%-8s'):format(plate) })
    if not row then
        row = MySQL.single.await('SELECT plate, owner, vehicle FROM owned_vehicles WHERE TRIM(plate) = ? LIMIT 1', { plate })
    end
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

---True if the entity's model matches the model stored in the owned_vehicles props
---(true as well when no model is stored).
---@param vehicle number entity
---@param owned table row from Mechanic.FetchOwned
---@return boolean
function Mechanic.ModelMatches(vehicle, owned)
    local storedModel = tonumber(owned.props and owned.props.model)
    if not storedModel then return true end
    storedModel = math.tointeger(math.floor(storedModel))
    -- Mask both sides: one may be a signed and the other an unsigned 32-bit hash
    return storedModel ~= nil and (GetEntityModel(vehicle) & 0xFFFFFFFF) == (storedModel & 0xFFFFFFFF)
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
    if not Mechanic.ModelMatches(vehicle, owned) then
        Mechanic.Flag(source, ('vehicle model does not match the stored model for plate "%s"'):format(tostring(owned.plate)))
        return false, 'not_owned'
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

-- True once sql/install.sql added the `model` column to ap1le_mechanicjob_parts. Without it, install
-- records are matched by plate only (v1 behaviour) until the file is run again.
local partsHasModel = false

MySQL.ready(function()
    local ok, count = pcall(MySQL.scalar.await, [[
        SELECT COUNT(*) FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'ap1le_mechanicjob_parts' AND COLUMN_NAME = 'model'
    ]])
    partsHasModel = ok and (tonumber(count) or 0) > 0
    if not partsHasModel then
        print('[ap1le_mechanicjob] ap1le_mechanicjob_parts has no `model` column; run sql/install.sql again so install records are tied to the vehicle model')
    end
end)

---Unsigned 32-bit model hash of a vehicle entity (the form stored in ap1le_mechanicjob_parts.model).
---@param entity number
---@return integer
function Mechanic.ModelHash(entity)
    return GetEntityModel(entity) & 0xFFFFFFFF
end

---Level of a part this resource installed on a plate (server-only record), or nil if none.
---A record written for a different vehicle model (plate reused after the car was sold, scrapped or
---given a new plate) counts as no record. Records without a model (written before v2) still count.
---@param plate string trimmed plate
---@param category string Config.Performance key
---@param model? integer Mechanic.ModelHash of the vehicle
---@return integer|nil
function Mechanic.GetInstalledLevel(plate, category, model)
    if partsHasModel then
        local ok, row = pcall(MySQL.single.await,
            'SELECT `level`, `model` FROM `ap1le_mechanicjob_parts` WHERE `plate` = ? AND `category` = ?', { plate, category })
        if not ok then
            print(('[ap1le_mechanicjob] reading ap1le_mechanicjob_parts failed: %s'):format(tostring(row)))
            return nil
        end
        if not row then return nil end
        local stored = math.tointeger(tonumber(row.model))
        if stored and model and (stored & 0xFFFFFFFF) ~= model then
            print(('[ap1le_mechanicjob] install record for plate "%s" (%s) belongs to another model, ignored'):format(plate, category))
            return nil
        end
        return math.tointeger(tonumber(row.level))
    end

    local ok, level = pcall(MySQL.scalar.await, 'SELECT `level` FROM `ap1le_mechanicjob_parts` WHERE `plate` = ? AND `category` = ?', { plate, category })
    if not ok then
        print(('[ap1le_mechanicjob] reading ap1le_mechanicjob_parts failed (was sql/install.sql run?): %s'):format(tostring(level)))
        return nil
    end
    return math.tointeger(tonumber(level))
end

---Save a performance swap atomically: the owned_vehicles props and the install record are written in
---one transaction, so the record can never disagree with the stored level after a partial failure.
---@param storedPlate string owned_vehicles.plate exactly as stored
---@param props table props to save
---@param plate string trimmed plate (install record key)
---@param category string
---@param level integer
---@param model integer Mechanic.ModelHash of the vehicle
---@return boolean saved
function Mechanic.SaveSwap(storedPlate, props, plate, category, level, model)
    local record
    if partsHasModel then
        record = {
            query = 'INSERT INTO `ap1le_mechanicjob_parts` (`plate`, `category`, `level`, `model`) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE `level` = ?, `model` = ?',
            values = { plate, category, level, model, level, model },
        }
    else
        record = {
            query = 'INSERT INTO `ap1le_mechanicjob_parts` (`plate`, `category`, `level`) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE `level` = ?',
            values = { plate, category, level, level },
        }
    end

    local ok, result = pcall(MySQL.transaction.await, {
        { query = 'UPDATE owned_vehicles SET vehicle = ? WHERE plate = ?', values = { json.encode(props), storedPlate } },
        record,
    })
    if not ok or result ~= true then
        print(('[ap1le_mechanicjob] saving %s level for plate "%s" failed (was sql/install.sql run?): %s'):format(category, plate, tostring(result)))
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

-- v1 used ox_lib's 'inform'; ap1le_core calls it 'info'
local NOTIFY_TYPES = { success = 'success', error = 'error', warning = 'warning', info = 'info', inform = 'info' }

---Notify a player through ap1le_core.
---@param target number
---@param msg string
---@param nType? string success|error|warning|info (v1 'inform' is mapped to 'info')
function Mechanic.Notify(target, msg, nType)
    Ap1le.Notify(target, msg, NOTIFY_TYPES[nType] or 'info')
end

---Money as shown in notifications, e.g. $17,300 (digit grouping follows the ESX locale).
---@param n number
---@return string
function Mechanic.FormatMoney(n)
    local ok, grouped = pcall(function() return ESX.Math.GroupDigits(n) end)
    return '$' .. ((ok and type(grouped) == 'string') and grouped or tostring(n))
end

---Display name of an xPlayer (falls back to the FiveM name).
---@param xPlayer table
---@return string
function Mechanic.PlayerName(xPlayer)
    local ok, name = pcall(xPlayer.getName)
    if ok and type(name) == 'string' and name ~= '' then return name end
    return GetPlayerName(xPlayer.source) or 'unknown'
end

-- ---------------------------------------------------------------------------------------------
-- Society account: the standard ESX pattern (esx_addonaccount:getSharedAccount, check
-- account.money >= amount, then removeMoney/addMoney), and the society registered with esx_society.
--
-- v2 bug (A1/A3): TriggerEvent msgpack-serialises its arguments, so the account table handed to our
-- callback is a COPY: account.money is a snapshot and never changes when esx_addonaccount's
-- removeMoney/addMoney (function references into the real object) run. v2 compared account.money
-- with the expected new balance after the call, which always failed: deposits were refunded after
-- the money had already reached the society, and orders failed after the society had already paid.
-- The result of the call itself is the only thing checked now (false = rejected by esx_addonaccount;
-- older versions return nothing, which counts as success, exactly like esx_society/esx_billing do).
-- ---------------------------------------------------------------------------------------------

-- > 0 while this resource itself moves society money, so the esx_addonaccount:addMoney/removeMoney
-- events that esx_addonaccount fires synchronously from inside the call are not mistaken for a
-- chef's esx_society deposit/withdraw (see server/computer.lua)
local internalMoves = 0

---True while this resource is moving society money itself.
---@return boolean
function Mechanic.SocietyInternalMove()
    return internalMoves > 0
end

---The society shared account object (a copy with function references), or nil.
---@return table|nil
function Mechanic.GetSociety()
    local account
    TriggerEvent('esx_addonaccount:getSharedAccount', Config.Invoice.society, function(acc)
        account = acc
    end)
    if type(account) ~= 'table' or type(account.money) ~= 'number' then return nil end
    return account
end

---Society balance, or nil if the account is unavailable.
---@return number|nil
function Mechanic.SocietyBalance()
    local account = Mechanic.GetSociety()
    return account and account.money
end

---Call removeMoney/addMoney on the account. Only the call's own result is checked (see above).
---@return boolean
local function societyCall(account, fn, amount)
    internalMoves = internalMoves + 1
    local ok, result = pcall(account[fn], amount)
    internalMoves = internalMoves - 1

    if not ok or result == false then
        print(('[ap1le_mechanicjob] %s(%d) on society "%s" failed (%s)'):format(fn, amount, Config.Invoice.society, tostring(result)))
        return false
    end
    return true
end

---Remove money from the society. Returns true on success, or false + locale key.
---@param amount integer > 0
---@return boolean ok
---@return string|nil err
function Mechanic.SocietyRemove(amount)
    if not Mechanic.IsInt(amount, 1, 2147483647) then return false, 'error' end

    local account = Mechanic.GetSociety()
    if not account then
        print(('[ap1le_mechanicjob] society account "%s" not found (run sql/install.sql, then restart esx_addonaccount and esx_society)')
            :format(Config.Invoice.society))
        return false, 'error'
    end

    if account.money < amount then return false, 'order_no_money' end
    if not societyCall(account, 'removeMoney', amount) then return false, 'error' end

    return true
end

---Add money to the society. Returns true on success.
---@param amount integer > 0
---@return boolean
function Mechanic.SocietyAdd(amount)
    if not Mechanic.IsInt(amount, 1, 2147483647) then return false end

    local account = Mechanic.GetSociety()
    if not account then
        print(('[ap1le_mechanicjob] society account "%s" not found (run sql/install.sql, then restart esx_addonaccount and esx_society)')
            :format(Config.Invoice.society))
        return false
    end

    return societyCall(account, 'addMoney', amount)
end

---Register Config.Job as a society with esx_society (the standard ESX job setup, as esx_mechanicjob
---does), so the chef can use esx_society's deposit/withdraw/balance. Skipped when another resource
---(e.g. esx_mechanicjob) already registered it.
local function registerSociety()
    local existing
    TriggerEvent('esx_society:getSociety', Config.Job, function(society) existing = society end)
    if existing then return end

    local label = Config.Job
    local ok, jobs = pcall(ESX.GetJobs)
    if ok and type(jobs) == 'table' and type(jobs[Config.Job]) == 'table' and type(jobs[Config.Job].label) == 'string' then
        label = jobs[Config.Job].label
    end

    -- registerSociety(name, label, account, datastore, inventory, data)
    local society = Config.Invoice.society
    TriggerEvent('esx_society:registerSociety', Config.Job, label, society, society, society, { type = 'private' })
end

-- Exposed for the mocked tests
Mechanic.RegisterSociety = registerSociety

registerSociety()

-- esx_society forgets registered societies when it restarts
AddEventHandler('onResourceStart', function(resource)
    if resource == 'esx_society' then
        SetTimeout(1000, registerSociety)
    end
end)

---Move money on a player's ESX account and verify the new balance.
---@param xPlayer table
---@param accountName string
---@param amount integer > 0
---@param add boolean true = add, false = remove (only if the balance covers it)
---@param reason string
---@return boolean
function Mechanic.MovePlayerMoney(xPlayer, accountName, amount, add, reason)
    if not Mechanic.IsInt(amount, 1, 2147483647) then return false end

    local account = xPlayer.getAccount(accountName)
    if not account or type(account.money) ~= 'number' then return false end

    local before = account.money
    if not add and before < amount then return false end

    local fn = add and xPlayer.addAccountMoney or xPlayer.removeAccountMoney
    local ok, result = pcall(fn, accountName, amount, reason)

    local after = xPlayer.getAccount(accountName)
    after = after and after.money

    if not ok or result == false or after ~= (add and before + amount or before - amount) then
        print(('[ap1le_mechanicjob] %s %d %s %s account "%s" failed (%s)'):format(add and 'adding' or 'removing', amount,
            add and 'to' or 'from', tostring(xPlayer.identifier), accountName, tostring(result)))
        return false
    end

    return true
end

---Log a society transfer (deposit/withdraw) for the computer's economy app. Never throws.
---@param workshop string|nil
---@param kind string 'deposit'|'withdraw'
---@param amount integer
---@param xPlayer table
function Mechanic.LogTransaction(workshop, kind, amount, xPlayer)
    local ok, err = pcall(MySQL.insert.await,
        'INSERT INTO `ap1le_mechanicjob_transactions` (`workshop`, `type`, `amount`, `identifier`, `name`, `created_at`) VALUES (?, ?, ?, ?, ?, ?)',
        { workshop, kind, amount, xPlayer.identifier, Mechanic.PlayerName(xPlayer), os.time() })
    if not ok then
        print(('[ap1le_mechanicjob] logging %s of %d failed (was sql/install.sql run?): %s'):format(kind, amount, tostring(err)))
    end
end

-- ---------------------------------------------------------------------------------------------
-- Pending actions
-- ---------------------------------------------------------------------------------------------

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
---@param data table must contain kind and minMs; expectedMs is used for the abandon timeout,
---or timeoutMs (ms from now) when the action has no predictable length (manual swaps)
function Mechanic.SetPending(source, data)
    local now = GetGameTimer()
    data.startedAt = now
    if data.timeoutMs then
        data.expiresAt = now + math.floor(data.timeoutMs)
    else
        data.expiresAt = now + math.floor((data.expectedMs or data.minMs or 0) * 2) + PENDING_GRACE_MS
    end
    Mechanic.Pending[source] = data
end

---Elapsed-time check against pending.minMs.
---@param pending table
---@return boolean
function Mechanic.ElapsedOk(pending)
    return GetGameTimer() - pending.startedAt >= pending.minMs
end

-- Shared cancel for repair, swap, unpack and wash
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
