-- ap1le_mechanicjob: repairs (engine, body, tyre, field).
-- Flow: server begin -> animation -> server finish (item is removed there) -> repair applied locally.

Repair = {}

local working = false

-- Wheel indexes for cars (0-5) and bikes (45, 47)
local WHEELS = { 0, 1, 2, 3, 4, 5, 45, 47 }

local function failText(err)
    if type(err) == 'string' and err ~= '' then return locale(err) end
    return locale('error')
end

local function cancelPending()
    lib.callback.await('ap1le_mechanicjob:cancel', false)
end

---Apply the repair to the vehicle. Runs after the server confirmed the finish.
local function applyRepair(vehicle, kind, result)
    if not DoesEntityExist(vehicle) then return end

    if not Mechanic.RequestControl(vehicle) then
        Ap1le.Notify(locale('error'), 'error')
        return
    end

    if kind == 'engine' then
        SetVehicleEngineHealth(vehicle, 1000.0)
        SetVehiclePetrolTankHealth(vehicle, 1000.0)
        SetVehicleUndriveable(vehicle, false)
    elseif kind == 'body' then
        -- SetVehicleFixed also repairs engine and tyres, so remember them and put them back
        local engine = GetVehicleEngineHealth(vehicle)
        local tank = GetVehiclePetrolTankHealth(vehicle)
        local burst = {}

        for i = 1, #WHEELS do
            local wheel = WHEELS[i]
            if IsVehicleTyreBurst(vehicle, wheel, true) then
                burst[#burst + 1] = { wheel = wheel, onRim = true }
            elseif IsVehicleTyreBurst(vehicle, wheel, false) then
                burst[#burst + 1] = { wheel = wheel, onRim = false }
            end
        end

        SetVehicleFixed(vehicle)
        SetVehicleDeformationFixed(vehicle)
        SetVehicleBodyHealth(vehicle, 1000.0)
        SetVehicleEngineHealth(vehicle, engine)
        SetVehiclePetrolTankHealth(vehicle, tank)

        for i = 1, #burst do
            SetVehicleTyreBurst(vehicle, burst[i].wheel, burst[i].onRim, 1000.0)
        end
    elseif kind == 'tyre' then
        for i = 1, #WHEELS do
            SetVehicleTyreFixed(vehicle, WHEELS[i])
        end
    elseif kind == 'field' then
        local maxHealth = type(result) == 'table' and tonumber(result.maxEngineHealth)
            or Config.Repair.field.maxEngineHealth
        local current = GetVehicleEngineHealth(vehicle)

        -- A field repair never lowers a healthier engine
        if current < maxHealth then
            SetVehicleEngineHealth(vehicle, maxHealth + 0.0)
        end

        SetVehicleUndriveable(vehicle, false)
    end

    Ap1le.Notify(locale(('repair_%s_done'):format(kind)), 'success')
end

---Start a repair on a vehicle. kind = engine|body|tyre|field.
---@param vehicle integer
---@param kind string
function Repair.Start(vehicle, kind)
    local cfg = Config.Repair[kind]
    if not cfg or working or Anim.IsBusy() then return end
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end

    if not Mechanic.IsMechanic() then
        Ap1le.Notify(locale('not_mechanic'), 'error')
        return
    end

    if IsPedInAnyVehicle(cache.ped, false) then
        Ap1le.Notify(locale('busy'), 'error')
        return
    end

    if cfg.workshopOnly and not Mechanic.InWorkshop() then
        Ap1le.Notify(locale('not_in_workshop'), 'error')
        return
    end

    if not NetworkGetEntityIsNetworked(vehicle) then
        Ap1le.Notify(locale('error'), 'error')
        return
    end

    working = true

    CreateThread(function()
        local netId = NetworkGetNetworkIdFromEntity(vehicle)
        local ok, data = lib.callback.await('ap1le_mechanicjob:repair:begin', false, netId, kind)

        if not ok then
            Ap1le.Notify(failText(data), 'error')
            working = false
            return
        end

        if not Mechanic.RequestControl(vehicle) then
            cancelPending()
            Ap1le.Notify(locale('error'), 'error')
            working = false
            return
        end

        local time = type(data) == 'table' and tonumber(data.time) or cfg.time
        local completed = Anim.Repair(vehicle, kind, time)

        if not completed then
            cancelPending()
            Ap1le.Notify(locale('cancelled'), 'info')
            working = false
            return
        end

        local finished, result = lib.callback.await('ap1le_mechanicjob:repair:finish', false)

        if not finished then
            Ap1le.Notify(failText(result), 'error')
            working = false
            return
        end

        applyRepair(vehicle, kind, result)
        working = false
    end)
end
