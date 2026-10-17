-- ap1le_mechanicjob: cosmetic tuning (open check + saving cosmetic props).
-- Saving merges only whitelisted cosmetic keys into the stored JSON; performance keys always stay as stored.

-- Value checks, matching what lib.getVehicleProperties produces and the game setters accept.
-- Each returns a clean copy of the value, or nil if it is not allowed.

---Integer (or integral float) within [min, max].
local function int(v, min, max)
    if type(v) ~= 'number' then return nil end
    local i = math.tointeger(v)
    if not i or i < min or i > max then return nil end
    return i
end

---Plain array (keys 1..n, no holes, no extra keys) with exactly n entries.
local function isArray(v, n)
    if type(v) ~= 'table' then return false end
    local count = 0
    for k in pairs(v) do
        count = count + 1
        if math.type(k) ~= 'integer' or k < 1 or k > n or count > n then return false end
    end
    return count == n
end

local function bool(v)
    if type(v) == 'boolean' then return v end
    return nil
end

local function rgb(v)
    if not isArray(v, 3) then return nil end
    local r, g, b = int(v[1], 0, 255), int(v[2], 0, 255), int(v[3], 0, 255)
    if not (r and g and b) then return nil end
    return { r, g, b }
end

local function modIndex(v) return int(v, -1, 255) end
local function colourIndex(v) return int(v, 0, 255) end

-- Primary/secondary paint: a palette index or a custom RGB colour
local function paint(v)
    if type(v) == 'table' then return rgb(v) end
    return colourIndex(v)
end

local validators = {
    color1 = paint,
    color2 = paint,
    pearlescentColor = colourIndex,
    wheelColor = colourIndex,
    wheels = function(v) return int(v, 0, 12) end,
    -- Upper bounds leave room for added tints/plate styles (the client lists GetNum* options)
    windowTint = function(v) return int(v, -1, 12) end,
    plateIndex = function(v) return int(v, 0, 12) end,
    xenonColor = function(v) return int(v, -1, 255) end, -- 0..12 colours, 255 = default
    neonEnabled = function(v)
        if not isArray(v, 4) then return nil end
        local copy = {}
        for i = 1, 4 do
            if type(v[i]) ~= 'boolean' then return nil end
            copy[i] = v[i]
        end
        return copy
    end,
    neonColor = rgb,
    modXenon = bool,
    modCustomTiresF = bool,
    modCustomTiresR = bool,
    modLivery = modIndex,
}

-- Every configured cosmetic mod id is a GTA mod index
for i = 1, #Config.Cosmetic.mods do
    validators[Config.Cosmetic.mods[i].id] = modIndex
end

-- Performance keys are never writable from here, even if a config edit puts one in the cosmetic list
for _, cfg in pairs(Config.Performance) do
    validators[cfg.propKey] = nil
end

---Shared checks for both callbacks. Returns vehicle entity + trimmed plate, or nil + error key.
local function checkAccess(source, netId, action)
    if not Mechanic.GetMechanic(source) then return nil, 'not_mechanic' end

    local vehicle, err = Mechanic.GetVehicle(source, netId)
    if not vehicle then
        if err == 'error' then Mechanic.Flag(source, ('%s with invalid vehicle netId'):format(action)) end
        return nil, err or 'too_far'
    end

    if not Mechanic.PlayerWorkshop(source) then return nil, 'not_in_workshop' end

    return vehicle, Mechanic.EntityPlate(vehicle)
end

lib.callback.register('ap1le_mechanicjob:tuning:canOpen', function(source, netId)
    if not Mechanic.RateLimit(source, 'tuning:canOpen', 1000) then return false, 'too_fast' end

    local vehicle, plate = checkAccess(source, netId, 'tuning:canOpen')
    if not vehicle then return false, plate end

    local levels = {}
    local owned = plate and Mechanic.FetchOwned(plate)

    if owned == false then return false, 'error' end

    if owned then
        for category, cfg in pairs(Config.Performance) do
            levels[category] = (Mechanic.LevelFromProps(cfg, owned.props))
        end
    end

    return true, { owned = owned ~= nil, levels = levels }
end)

lib.callback.register('ap1le_mechanicjob:tuning:save', function(source, netId, props)
    if not Mechanic.RateLimit(source, 'tuning:save', 3000) then return false, 'too_fast' end

    local vehicle, plate = checkAccess(source, netId, 'tuning:save')
    if not vehicle then return false, plate end

    if type(props) ~= 'table' then
        Mechanic.Flag(source, 'tuning:save with non-table props')
        return false, 'error'
    end

    if type(props.plate) ~= 'string' or #props.plate > 16 then
        Mechanic.Flag(source, 'tuning:save with invalid props.plate')
        return false, 'error'
    end

    local propsPlate = Mechanic.Trim(props.plate)
    if not plate or not propsPlate or propsPlate ~= plate then
        Mechanic.Flag(source, ('tuning:save plate mismatch (entity %s, props %s)'):format(tostring(plate), tostring(propsPlate)))
        return false, 'error'
    end

    -- Sanitise before touching the DB; anything malformed is dropped, not saved
    local changes, rejected = {}, 0
    for key, validate in pairs(validators) do
        local value = props[key]
        if value ~= nil then
            local clean = validate(value)
            if clean ~= nil then
                changes[key] = clean
            else
                rejected = rejected + 1
            end
        end
    end

    if rejected > 0 then
        Mechanic.Flag(source, ('tuning:save dropped %d malformed cosmetic value(s)'):format(rejected))
    end

    if not Mechanic.LockPlate(plate) then return false, 'busy' end

    local ok, success, data = pcall(function()
        local owned = Mechanic.FetchOwned(plate)
        if owned == false then return false, 'error' end
        if not owned then return true, { saved = false } end

        -- The plate is client-controlled: the entity must really be the stored car
        local access, accessErr = Mechanic.CheckOwnedVehicle(source, vehicle, owned)
        if not access then return false, accessErr end

        local stored = owned.props
        for key, value in pairs(changes) do
            stored[key] = value
        end

        local affected = MySQL.update.await('UPDATE owned_vehicles SET vehicle = ? WHERE plate = ?', {
            json.encode(stored), owned.plate,
        })

        -- 0 affected rows is fine here: the stored JSON may already be identical
        if type(affected) ~= 'number' then return false, 'error' end
        return true, { saved = true }
    end)

    Mechanic.UnlockPlate(plate)

    if not ok then
        print(('[ap1le_mechanicjob] tuning save error for plate "%s": %s'):format(plate, tostring(success)))
        return false, 'error'
    end

    return success, data
end)
