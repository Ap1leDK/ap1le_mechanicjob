-- ap1le_mechanicjob: flatbed towing (load / unload).
-- The loaded vehicle is physically attached to the truck. The truck's state bag remembers
-- which vehicle is on the bed so any mechanic (not only the one who loaded it) can unload it.

Towing = {}

local STATE_KEY = 'ap1le_mechanicjob:loaded'

local working = false

-- Set of tow truck model hashes
local truckModels = {}
for i = 1, #Config.Towing.trucks do
    truckModels[Config.Towing.trucks[i]] = true
end

-- Short cache for FindTruck: ox_target polls canInteract while the player is aiming at a vehicle
local findCache = { vehicle = 0, at = 0, truck = nil }
local FIND_CACHE_MS = 750

---@param entity integer
---@return boolean
function Towing.IsTruck(entity)
    return truckModels[GetEntityModel(entity)] == true
end

---Vehicle currently loaded on the given truck, or nil.
---@param truck integer
---@return integer?
function Towing.GetLoaded(truck)
    if not truck or truck == 0 or not DoesEntityExist(truck) then return nil end
    if not NetworkGetEntityIsNetworked(truck) then return nil end

    local netId = Entity(truck).state[STATE_KEY]
    if type(netId) ~= 'number' or not NetworkDoesEntityExistWithNetworkId(netId) then return nil end

    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return nil end
    if not IsEntityAttachedToEntity(vehicle, truck) then return nil end

    return vehicle
end

---Nearest free (nothing loaded) tow truck within Config.Towing.maxDistance of the vehicle.
---@param vehicle integer
---@return integer?
function Towing.FindTruck(vehicle)
    local now = GetGameTimer()
    if findCache.vehicle == vehicle and now - findCache.at < FIND_CACHE_MS then
        if findCache.truck and DoesEntityExist(findCache.truck) then
            return findCache.truck
        elseif findCache.truck == nil then
            return nil
        end
    end

    local coords = GetEntityCoords(vehicle)
    local nearby = lib.getNearbyVehicles(coords, Config.Towing.maxDistance, true)
    local best, bestDist

    for i = 1, #nearby do
        local entry = nearby[i]
        local candidate = entry.vehicle

        if candidate ~= vehicle and Towing.IsTruck(candidate) and not Towing.GetLoaded(candidate) then
            local dist = #(coords - entry.coords)
            if not bestDist or dist < bestDist then
                best, bestDist = candidate, dist
            end
        end
    end

    findCache.vehicle, findCache.at, findCache.truck = vehicle, now, best

    return best
end

---Load a vehicle onto the nearest free flatbed.
---@param vehicle integer
function Towing.Load(vehicle)
    if working or Anim.IsBusy() then return end
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end

    if not Mechanic.IsMechanic() then
        UI.Notify(locale('not_mechanic'), 'error')
        return
    end

    if Towing.IsTruck(vehicle) or IsEntityAttached(vehicle) then
        UI.Notify(locale('tow_no_vehicle'), 'error')
        return
    end

    local truck = Towing.FindTruck(vehicle)
    if not truck then
        UI.Notify(locale('tow_no_truck'), 'error')
        return
    end

    if not NetworkGetEntityIsNetworked(vehicle) or not NetworkGetEntityIsNetworked(truck) then
        UI.Notify(locale('error'), 'error')
        return
    end

    -- Never winch a vehicle somebody is sitting in
    if not IsVehicleSeatFree(vehicle, -1) or GetVehicleNumberOfPassengers(vehicle) > 0 then
        UI.Notify(locale('busy'), 'error')
        return
    end

    working = true

    CreateThread(function()
        if not Mechanic.RequestControl(truck) or not Mechanic.RequestControl(vehicle) then
            UI.Notify(locale('error'), 'error')
            working = false
            return
        end

        local completed = Anim.Winch(truck, vehicle, Config.Towing.winchTime)

        if not completed then
            UI.Notify(locale('cancelled'), 'inform')
            working = false
            return
        end

        if not DoesEntityExist(vehicle) or not DoesEntityExist(truck)
            or #(GetEntityCoords(vehicle) - GetEntityCoords(truck)) > Config.Towing.maxDistance + 5.0 then
            UI.Notify(locale('tow_no_truck'), 'error')
            working = false
            return
        end

        -- Another mechanic may have loaded the truck while we were winching
        if Towing.GetLoaded(truck) then
            UI.Notify(locale('busy'), 'error')
            working = false
            return
        end

        local offset = Config.Towing.attachOffset
        local bone = GetEntityBoneIndexByName(truck, 'bodyshell')
        if not bone or bone < 0 then bone = 0 end

        SetEntityVelocity(vehicle, 0.0, 0.0, 0.0)

        AttachEntityToEntity(
            vehicle, truck, bone,
            offset.x, offset.y, offset.z,
            0.0, 0.0, 0.0,
            false, false, true, false, 20, true
        )

        Entity(truck).state:set(STATE_KEY, NetworkGetNetworkIdFromEntity(vehicle), true)
        findCache.vehicle = 0

        UI.Notify(locale('tow_loaded'), 'success')
        working = false
    end)
end

---Unload the vehicle from a flatbed and drop it behind the truck.
---@param truck integer
function Towing.Unload(truck)
    if working or Anim.IsBusy() then return end
    if not truck or truck == 0 or not DoesEntityExist(truck) then return end

    if not Mechanic.IsMechanic() then
        UI.Notify(locale('not_mechanic'), 'error')
        return
    end

    local vehicle = Towing.GetLoaded(truck)
    if not vehicle then
        UI.Notify(locale('tow_no_vehicle'), 'error')
        return
    end

    working = true

    CreateThread(function()
        if not Mechanic.RequestControl(truck) or not Mechanic.RequestControl(vehicle) then
            UI.Notify(locale('error'), 'error')
            working = false
            return
        end

        local completed = Anim.Winch(truck, vehicle, Config.Towing.winchTime)

        if not completed then
            UI.Notify(locale('cancelled'), 'inform')
            working = false
            return
        end

        if not DoesEntityExist(vehicle) or not DoesEntityExist(truck) then
            working = false
            return
        end

        DetachEntity(vehicle, true, true)

        local target = GetOffsetFromEntityInWorldCoords(
            truck,
            Config.Towing.unloadOffset.x,
            Config.Towing.unloadOffset.y,
            Config.Towing.unloadOffset.z
        )

        -- Find the ground below the drop point (probe from above)
        local found, groundZ = GetGroundZFor_3dCoord(target.x, target.y, target.z + 3.0, false)
        local z = found and groundZ or target.z

        SetEntityCoordsNoOffset(vehicle, target.x, target.y, z + 0.5, false, false, false)
        SetEntityHeading(vehicle, GetEntityHeading(truck))
        SetVehicleOnGroundProperly(vehicle)
        SetEntityVelocity(vehicle, 0.0, 0.0, 0.0)

        Entity(truck).state:set(STATE_KEY, nil, true)
        findCache.vehicle = 0

        UI.Notify(locale('tow_unloaded'), 'success')
        working = false
    end)
end
