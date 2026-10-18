-- ap1le_mechanicjob: workshop stash targets and delivery crates (client side).
-- Stash: one ox_target sphere per workshop opens the shared ox_inventory stash.
-- Crates: arrived orders are published by the server in GlobalState['ap1le_mechanicjob:crates']. They are
-- drawn as local (non-networked) props, only while the player is within CRATE_RANGE, and unpacked into the
-- stash with ox_target (server begin -> Anim.Unpack -> server finish).

Stock = {}

local CRATES_KEY = 'ap1le_mechanicjob:crates'
local CRATE_RANGE = 60.0       -- spawn distance for crate props
local STASH_RADIUS = 1.0
local SPAWN_TIMEOUT = 3000     -- ms to wait for the model and the ground collision

local stashZones = {}          -- zone ids from ox_target
local crates = {}              -- [orderId] = { id, coords, point, entity, spawning, gone }
local unpacking = false
local started = false
local stopped = false

local GROUPS = { [Config.Job] = 0 }

-- ---------------------------------------------------------------------------
-- Stash
-- ---------------------------------------------------------------------------

---Open the stash of a workshop.
---@param workshop table Config.Workshops entry
function Stock.OpenStash(workshop)
    if not Mechanic.IsMechanic() then
        Ap1le.Notify(locale('not_mechanic'), 'error')
        return
    end

    if Anim.IsBusy() then return end

    -- Same id as the server (Mechanic.StashId); ox_inventory re-checks the group and the distance
    exports.ox_inventory:openInventory('stash', 'ap1le_mechanicjob_' .. workshop.id)
end

local function registerStashZones()
    for i = 1, #Config.Workshops do
        local ws = Config.Workshops[i]

        if ws.stash and ws.stash.coords then
            stashZones[#stashZones + 1] = exports.ox_target:addSphereZone({
                name = 'ap1le_mechanicjob:stash:' .. ws.id,
                coords = ws.stash.coords,
                radius = STASH_RADIUS,
                debug = false,
                options = {
                    {
                        name = 'ap1le_mechanicjob:stash:' .. ws.id,
                        icon = 'fa-solid fa-boxes-stacked',
                        label = locale('target_stash'),
                        groups = GROUPS,
                        distance = 2.0,
                        canInteract = function()
                            return Mechanic.IsMechanic() and not Anim.IsBusy() and not cache.vehicle
                        end,
                        onSelect = function()
                            Stock.OpenStash(ws)
                        end,
                    },
                },
            })
        end
    end
end

local function removeStashZones()
    for i = 1, #stashZones do
        pcall(function() exports.ox_target:removeZone(stashZones[i], true) end)
    end
    stashZones = {}
end

-- ---------------------------------------------------------------------------
-- Crates
-- ---------------------------------------------------------------------------

---Delete the prop of a crate (and its target). Safe to call at any time.
local function despawn(crate)
    crate.spawning = false

    local entity = crate.entity
    crate.entity = nil

    if entity and DoesEntityExist(entity) then
        pcall(function() exports.ox_target:removeLocalEntity(entity) end)
        DeleteEntity(entity)
    end
end

---Remove a crate completely: its point and its prop.
local function removeCrate(crate)
    crate.gone = true

    if crate.point then
        crate.point:remove()
        crate.point = nil
    end

    despawn(crate)
    crates[crate.id] = nil
end

---Unpack a crate into the workshop stash.
---@param orderId integer
function Stock.Unpack(orderId)
    if unpacking or Anim.IsBusy() then return end

    if not Mechanic.IsMechanic() then
        Ap1le.Notify(locale('not_mechanic'), 'error')
        return
    end

    local crate = crates[orderId]
    if not crate or not crate.entity or not DoesEntityExist(crate.entity) then return end

    unpacking = true

    CreateThread(function()
        local ok, data = lib.callback.await('ap1le_mechanicjob:order:unpackBegin', false, orderId)

        if not ok then
            Ap1le.Notify(Mechanic.ErrorText(data), 'error')
            unpacking = false
            return
        end

        local current = crates[orderId]
        local entity = current and current.entity
        local time = type(data) == 'table' and tonumber(data.time) or Config.Shop.unpackTime

        -- Anim.Unpack drives the ped and shows the ap1le_core progress bars; false = cancelled or interrupted
        local completed = entity and DoesEntityExist(entity) and Anim.Unpack(entity, time)

        if not completed then
            lib.callback.await('ap1le_mechanicjob:cancel', false)
            Ap1le.Notify(locale('cancelled'), 'info')
            unpacking = false
            return
        end

        local finished, result = lib.callback.await('ap1le_mechanicjob:order:unpackFinish', false)

        if not finished then
            -- e.g. stock_full: the order stays at the delivery point
            Ap1le.Notify(Mechanic.ErrorText(result), 'error')
            unpacking = false
            return
        end

        local lines = 0
        if type(result) == 'table' and type(result.items) == 'table' then
            for i = 1, #result.items do
                lines = lines + (math.tointeger(tonumber(result.items[i].count)) or 0)
            end
        end

        Ap1le.Notify(locale('order_unpacked', lines), 'success')
        unpacking = false
    end)
end

---Create the prop of a crate (runs in a thread: it waits for the model and the ground).
local function spawn(crate)
    if crate.entity or crate.spawning or crate.gone then return end
    crate.spawning = true

    CreateThread(function()
        local model = Config.Shop.crateModel
        local loaded = pcall(lib.requestModel, model, SPAWN_TIMEOUT)

        if not loaded or crate.gone or not crate.spawning then
            crate.spawning = false
            return
        end

        local c = crate.coords
        local entity = CreateObject(model, c.x, c.y, c.z, false, false, false)
        SetModelAsNoLongerNeeded(model)

        if not entity or entity == 0 then
            crate.spawning = false
            return
        end

        SetEntityHeading(entity, c.w)
        FreezeEntityPosition(entity, true)

        -- Let the ground stream in before snapping the crate onto it
        RequestCollisionAtCoord(c.x, c.y, c.z)
        local deadline = GetGameTimer() + SPAWN_TIMEOUT
        while not HasCollisionLoadedAroundEntity(entity) and GetGameTimer() < deadline do
            Wait(50)
        end

        -- The crate may have been removed (collected, out of range, resource stop) while waiting
        if crate.gone or not crate.spawning or not DoesEntityExist(entity) then
            if DoesEntityExist(entity) then DeleteEntity(entity) end
            crate.spawning = false
            return
        end

        PlaceObjectOnGroundProperly(entity)
        crate.entity = entity
        crate.spawning = false

        exports.ox_target:addLocalEntity(entity, {
            {
                name = 'ap1le_mechanicjob:unpack',
                icon = 'fa-solid fa-box-open',
                label = locale('target_unpack'),
                groups = GROUPS,
                distance = 2.0,
                canInteract = function()
                    return Mechanic.IsMechanic() and not Anim.IsBusy() and not unpacking and not cache.vehicle
                end,
                onSelect = function()
                    Stock.Unpack(crate.id)
                end,
            },
        })
    end)
end

---Bring the local crates in line with the published list.
---@param list any
local function syncCrates(list)
    local wanted = {}

    if type(list) == 'table' then
        for i = 1, #list do
            local entry = list[i]
            local id = type(entry) == 'table' and math.tointeger(tonumber(entry.id))
            local c = type(entry) == 'table' and type(entry.coords) == 'table' and entry.coords

            if id and c and tonumber(c.x) and tonumber(c.y) and tonumber(c.z) then
                wanted[id] = { x = c.x + 0.0, y = c.y + 0.0, z = c.z + 0.0, w = (tonumber(c.w) or 0.0) + 0.0 }
            end
        end
    end

    -- Collected or cancelled
    for id, crate in pairs(crates) do
        if not wanted[id] then
            removeCrate(crate)
        end
    end

    for id, c in pairs(wanted) do
        local crate = crates[id]

        -- New crate, or its position moved (positions are re-indexed when another crate is collected)
        if crate and (crate.coords.x ~= c.x or crate.coords.y ~= c.y or crate.coords.z ~= c.z or crate.coords.w ~= c.w) then
            removeCrate(crate)
            crate = nil
        end

        if not crate then
            crate = { id = id, coords = c }
            crates[id] = crate

            -- lib.points calls onEnter on its next tick when the player is already in range
            crate.point = lib.points.new({
                coords = vec3(c.x, c.y, c.z),
                distance = CRATE_RANGE,
                onEnter = function()
                    spawn(crate)
                end,
                onExit = function()
                    despawn(crate)
                end,
            })
        end
    end
end

-- Global state bag: fires for every change, including the first publish after joining
AddStateBagChangeHandler(CRATES_KEY, 'global', function(_, _, value)
    if stopped then return end
    syncCrates(value)
end)

-- ---------------------------------------------------------------------------
-- Start / stop
-- ---------------------------------------------------------------------------

local function start()
    if started then return end
    started = true

    registerStashZones()
    syncCrates(GlobalState[CRATES_KEY])
end

CreateThread(function()
    start()
end)

-- ox_target forgets its zones and entity targets when it restarts
AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= 'ox_target' then return end

    CreateThread(function()
        Wait(500)
        removeStashZones()
        registerStashZones()

        -- Re-create the crate props so they get their targets again
        local here = GetEntityCoords(cache.ped)

        for _, crate in pairs(crates) do
            despawn(crate)

            if #(here - vec3(crate.coords.x, crate.coords.y, crate.coords.z)) <= CRATE_RANGE then
                spawn(crate)
            end
        end
    end)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    stopped = true
    removeStashZones()

    local list = {}
    for _, crate in pairs(crates) do list[#list + 1] = crate end
    for i = 1, #list do removeCrate(list[i]) end
end)
