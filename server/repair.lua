-- ap1le_mechanicjob: repair callbacks (engine, body, tyre, field).
-- Server owns the item check, the timing and the item removal; the client only plays the animation.

local function hasItem(source, item)
    local count = exports.ox_inventory:Search(source, 'count', item)
    return type(count) == 'number' and count >= 1
end

lib.callback.register('ap1le_mechanicjob:repair:begin', function(source, netId, kind)
    if not Mechanic.GetMechanic(source) then return false, 'not_mechanic' end
    if not Mechanic.RateLimit(source, 'repair:begin', 1000) then return false, 'too_fast' end

    local cfg = type(kind) == 'string' and Config.Repair[kind]
    if not cfg then
        Mechanic.Flag(source, ('repair:begin with invalid kind %s'):format(tostring(kind)))
        return false, 'error'
    end

    if Mechanic.GetPending(source) then return false, 'busy' end

    local vehicle, err = Mechanic.GetVehicle(source, netId)
    if not vehicle then
        if err == 'error' then Mechanic.Flag(source, 'repair:begin with invalid vehicle netId') end
        return false, err or 'too_far'
    end

    if cfg.workshopOnly and not Mechanic.PlayerWorkshop(source) then
        return false, 'not_in_workshop'
    end

    if not hasItem(source, cfg.item) then return false, 'missing_item' end

    Mechanic.SetPending(source, {
        kind = 'repair',
        repair = kind,
        netId = math.tointeger(netId),
        minMs = math.floor(cfg.time * Config.MinTimeFactor),
        expectedMs = cfg.time,
    })

    return true, { time = cfg.time }
end)

lib.callback.register('ap1le_mechanicjob:repair:finish', function(source)
    if not Mechanic.RateLimit(source, 'repair:finish', 500) then return false, 'too_fast' end

    local pending = Mechanic.GetPending(source)

    if not pending or pending.kind ~= 'repair' then
        -- Log at most once per 10 s per player so spam cannot flood the console
        if Mechanic.RateLimit(source, 'flag:repair:finish', 10000) then
            Mechanic.Flag(source, 'repair:finish without a pending repair')
        end
        return false, 'error'
    end

    -- Any outcome below ends this pending action
    Mechanic.Pending[source] = nil

    if not Mechanic.GetMechanic(source) then return false, 'not_mechanic' end

    local cfg = Config.Repair[pending.repair]
    if not cfg then return false, 'error' end

    if not Mechanic.ElapsedOk(pending) then
        Mechanic.Flag(source, ('repair:finish too fast (%d ms < %d ms)'):format(GetGameTimer() - pending.startedAt, pending.minMs))
        return false, 'too_fast'
    end

    local vehicle, err = Mechanic.GetVehicle(source, pending.netId)
    if not vehicle then return false, err == 'error' and 'error' or 'too_far' end

    if cfg.workshopOnly and not Mechanic.PlayerWorkshop(source) then
        return false, 'not_in_workshop'
    end

    local removed = exports.ox_inventory:RemoveItem(source, cfg.item, 1)
    if removed ~= true then return false, 'missing_item' end

    return true, { kind = pending.repair, maxEngineHealth = cfg.maxEngineHealth }
end)
