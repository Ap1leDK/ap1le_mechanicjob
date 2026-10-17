-- ap1le_mechanicjob: performance part swaps (engine, brakes, transmission, suspension, armor, turbo).
-- A swap is two physical steps on the client (remove old part, install new part). The server reads the
-- current level from owned_vehicles, enforces the combined minimum time, moves the items and saves the level.

---True if another player already has a pending swap on this plate (prevents parallel swaps that
---would both return the same old part).
local function plateBusy(source, plate)
    for src, pending in pairs(Mechanic.Pending) do
        if src ~= source and pending.kind == 'perf' and pending.plate == plate then
            if Mechanic.GetPending(src) then return true end
        end
    end
    return false
end

local function hasItem(source, item)
    local count = exports.ox_inventory:Search(source, 'count', item)
    return type(count) == 'number' and count >= 1
end

lib.callback.register('ap1le_mechanicjob:perf:begin', function(source, netId, category, level)
    if not Mechanic.GetMechanic(source) then return false, 'not_mechanic' end
    if not Mechanic.RateLimit(source, 'perf:begin', 1000) then return false, 'too_fast' end

    local cfg = type(category) == 'string' and Config.Performance[category]
    if not cfg then
        Mechanic.Flag(source, ('perf:begin with invalid category %s'):format(tostring(category)))
        return false, 'error'
    end

    if not Mechanic.IsInt(level, 0, #cfg.levels) then
        Mechanic.Flag(source, ('perf:begin with invalid level %s for %s'):format(tostring(level), category))
        return false, 'error'
    end
    level = math.tointeger(level)

    if Mechanic.GetPending(source) then return false, 'busy' end

    local vehicle, err = Mechanic.GetVehicle(source, netId)
    if not vehicle then
        if err == 'error' then Mechanic.Flag(source, 'perf:begin with invalid vehicle netId') end
        return false, err or 'too_far'
    end

    if not Mechanic.PlayerWorkshop(source) then return false, 'not_in_workshop' end

    local plate = Mechanic.EntityPlate(vehicle)
    if not plate then return false, 'not_owned' end

    local owned = Mechanic.FetchOwned(plate)
    if owned == false then return false, 'error' end
    if not owned then return false, 'not_owned' end

    -- The plate is client-controlled: the entity must really be the stored car
    local access, accessErr = Mechanic.CheckOwnedVehicle(source, vehicle, owned)
    if not access then return false, accessErr end

    local oldLevel, inRange = Mechanic.LevelFromProps(cfg, owned.props)
    if level == oldLevel then return false, 'not_available' end

    local newItem = level > 0 and cfg.levels[level] or nil

    -- The stored JSON is also written by other resources (garages, LSC) from client data, so the old
    -- part is only returned when this resource recorded installing exactly that level. Otherwise
    -- (out-of-range value, no record, or a different record) the swap is allowed without an item.
    local oldItem = nil
    if oldLevel > 0 and inRange then
        local recorded = Mechanic.GetInstalledLevel(plate, category)
        if recorded == oldLevel then
            oldItem = cfg.levels[oldLevel]
        elseif recorded ~= nil then
            Mechanic.Flag(source, ('perf:begin on "%s": stored %s level %d does not match installed level %d, no part returned')
                :format(plate, category, oldLevel, recorded))
        end
    end

    if newItem and not hasItem(source, newItem) then return false, 'missing_item' end
    if oldItem and not exports.ox_inventory:CanCarryItem(source, oldItem, 1) then return false, 'cant_carry' end

    -- The DB query yielded: re-check state that may have changed meanwhile
    if Mechanic.GetPending(source) then return false, 'busy' end
    if plateBusy(source, plate) then return false, 'busy' end

    local removeTime = oldLevel > 0 and cfg.removeTime or 0
    local installTime = level > 0 and cfg.installTime or 0
    local expected = removeTime + installTime

    Mechanic.SetPending(source, {
        kind = 'perf',
        netId = math.tointeger(netId),
        category = category,
        level = level,
        oldLevel = oldLevel,
        oldItem = oldItem,
        newItem = newItem,
        plate = plate,
        minMs = math.floor(expected * Config.MinTimeFactor),
        expectedMs = expected,
    })

    return true, {
        oldLevel = oldLevel,
        level = level,
        removeTime = cfg.removeTime,
        installTime = cfg.installTime,
    }
end)

---Give the old part back; if it no longer fits, drop it next to the mechanic instead of losing it.
local function giveOldPart(source, pending, state)
    if not pending.oldItem or state.gaveOld then return end
    state.gaveOld = true

    local added = exports.ox_inventory:AddItem(source, pending.oldItem, 1)
    if added then return end

    local ped = GetPlayerPed(source)
    if ped and ped ~= 0 and DoesEntityExist(ped) then
        local coords = GetEntityCoords(ped)
        local dropId = exports.ox_inventory:CustomDrop('Mechanic', { { pending.oldItem, 1 } },
            vec3(coords.x, coords.y, coords.z - 0.2), nil, nil, Player(source).state.instance)
        if dropId then return end
    end

    print(('[ap1le_mechanicjob] could not return %s to player %s (plate "%s")'):format(pending.oldItem, tostring(source), pending.plate))
end

---Undo whatever a failed swap already did, so nothing is lost or duplicated.
---Before the DB save: refund the new part. After the DB save: the swap stands, so make sure the
---old part is handed out.
local function rollback(source, pending, state)
    if state.saved then
        giveOldPart(source, pending, state)
        return
    end
    if state.removedNew then
        exports.ox_inventory:AddItem(source, pending.newItem, 1)
        state.removedNew = false
    end
end

---Moves the items and saves the new level. Runs while the plate is locked.
---Order: take the new part, save the DB, record the install, then give the old part. Nothing is
---handed out before the save succeeds, so a failed or yielding save can never duplicate a part.
---@return boolean ok
---@return any data
local function applySwap(source, cfg, pending, state, vehicle)
    -- Re-read the stored level: it must still be the one the swap started from
    local owned = Mechanic.FetchOwned(pending.plate)
    if owned == false then return false, 'error' end
    if not owned then return false, 'not_owned' end

    local currentLevel = Mechanic.LevelFromProps(cfg, owned.props)
    if currentLevel ~= pending.oldLevel then return false, 'error' end

    -- The DB query yielded: the player must still be connected and a mechanic
    if not Mechanic.GetMechanic(source) then return false, 'not_mechanic' end
    if not DoesEntityExist(vehicle) then return false, 'error' end

    -- Same ownership checks as begin, on the fresh row
    local access, accessErr = Mechanic.CheckOwnedVehicle(source, vehicle, owned)
    if not access then return false, accessErr end

    -- 1) Take the new part (synchronous)
    if pending.newItem then
        local removed = exports.ox_inventory:RemoveItem(source, pending.newItem, 1)
        if removed ~= true then return false, 'missing_item' end
        state.removedNew = true
    end

    -- 2) Save the new level, keeping every other stored property
    owned.props[cfg.propKey] = Mechanic.PropsValueForLevel(cfg, pending.level)

    local affected = MySQL.update.await('UPDATE owned_vehicles SET vehicle = ? WHERE plate = ?', {
        json.encode(owned.props), owned.plate,
    })

    if not affected or affected < 1 then
        rollback(source, pending, state)
        print(('[ap1le_mechanicjob] failed to save %s level for plate "%s"'):format(pending.category, pending.plate))
        return false, 'error'
    end
    state.saved = true

    -- 3) Server-only install record, used to decide whether a later removal returns a part
    Mechanic.SetInstalledLevel(pending.plate, pending.category, pending.level)

    -- 4) Give back the old part (dropped on the ground if it no longer fits)
    giveOldPart(source, pending, state)

    return true, { category = pending.category, level = pending.level }
end

lib.callback.register('ap1le_mechanicjob:perf:finish', function(source)
    if not Mechanic.RateLimit(source, 'perf:finish', 500) then return false, 'too_fast' end

    local pending = Mechanic.GetPending(source)

    if not pending or pending.kind ~= 'perf' then
        -- Log at most once per 10 s per player so spam cannot flood the console
        if Mechanic.RateLimit(source, 'flag:perf:finish', 10000) then
            Mechanic.Flag(source, 'perf:finish without a pending swap')
        end
        return false, 'error'
    end

    -- Any outcome below ends this pending action
    Mechanic.Pending[source] = nil

    if not Mechanic.GetMechanic(source) then return false, 'not_mechanic' end

    local cfg = Config.Performance[pending.category]
    if not cfg then return false, 'error' end

    if not Mechanic.ElapsedOk(pending) then
        Mechanic.Flag(source, ('perf:finish too fast (%d ms < %d ms)'):format(GetGameTimer() - pending.startedAt, pending.minMs))
        return false, 'too_fast'
    end

    local vehicle, err = Mechanic.GetVehicle(source, pending.netId)
    if not vehicle then return false, err == 'error' and 'error' or 'too_far' end

    if not Mechanic.PlayerWorkshop(source) then return false, 'not_in_workshop' end

    if Mechanic.EntityPlate(vehicle) ~= pending.plate then
        Mechanic.Flag(source, 'perf:finish plate changed during swap')
        return false, 'error'
    end

    if not Mechanic.LockPlate(pending.plate) then return false, 'busy' end

    local state = {}
    local ok, success, data = pcall(applySwap, source, cfg, pending, state, vehicle)
    Mechanic.UnlockPlate(pending.plate)

    if not ok then
        rollback(source, pending, state)
        print(('[ap1le_mechanicjob] swap error for plate "%s": %s'):format(pending.plate, tostring(success)))
        return false, 'error'
    end

    return success, data
end)
