-- ap1le_mechanicjob: client core.
-- Global `Mechanic` helpers, job tracking, workshop blips, ox_target registration, F6 menu,
-- notify event and the NUI locale callback. Feature handlers live in repair/tuning/billing/towing.lua.

Mechanic = {}

local MENU_ID = 'ap1le_mechanicjob_menu'

local blips = {}
local targetsRegistered = false

-- Names of every ox_target option this resource registers (needed for removal)
local VEHICLE_OPTIONS = {
    'ap1le_mechanicjob:repair_engine',
    'ap1le_mechanicjob:repair_body',
    'ap1le_mechanicjob:repair_tyre',
    'ap1le_mechanicjob:repair_field',
    'ap1le_mechanicjob:tuning',
    'ap1le_mechanicjob:tow_load',
}
local MODEL_OPTIONS = { 'ap1le_mechanicjob:tow_unload' }

-- ---------------------------------------------------------------------------
-- Job tracking
-- ---------------------------------------------------------------------------

if ESX.IsPlayerLoaded() then
    ESX.PlayerData = ESX.GetPlayerData()
end

RegisterNetEvent('esx:playerLoaded', function(xPlayer)
    ESX.PlayerData = xPlayer
end)

RegisterNetEvent('esx:onPlayerLogout', function()
    ESX.PlayerData = {}
    if Tuning and Tuning.Close then Tuning.Close(true) end
end)

RegisterNetEvent('esx:setJob', function(job)
    ESX.PlayerData = ESX.PlayerData or {}
    ESX.PlayerData.job = job

    -- Lost the job while the tuning screen was open: close it and revert the preview
    if job and job.name ~= Config.Job and Tuning and Tuning.Close then
        Tuning.Close(true)
    end
end)

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

---@return boolean
function Mechanic.IsMechanic()
    local data = ESX.PlayerData
    return data ~= nil and data.job ~= nil and data.job.name == Config.Job
end

---@return vector3
function Mechanic.Coords()
    return GetEntityCoords(cache.ped)
end

---Returns the workshop config entry the given coords (default: the player) are inside, or nil.
---@param coords? vector3
---@return table?
function Mechanic.InWorkshop(coords)
    coords = coords or GetEntityCoords(cache.ped)

    for i = 1, #Config.Workshops do
        local ws = Config.Workshops[i]
        if #(coords - ws.coords) <= ws.radius then
            return ws
        end
    end

    return nil
end

---Nearest vehicle in front of the player within 5 m, or nil. The player's own vehicle is ignored.
---@return integer?
function Mechanic.GetTargetVehicle()
    local ped = cache.ped
    local pedCoords = GetEntityCoords(ped)
    local front = GetOffsetFromEntityInWorldCoords(ped, 0.0, 1.5, 0.0)

    local nearby = lib.getNearbyVehicles(pedCoords, 5.0, false)
    local best, bestDist

    for i = 1, #nearby do
        local entry = nearby[i]
        local dist = #(front - entry.coords)

        if not bestDist or dist < bestDist then
            best, bestDist = entry.vehicle, dist
        end
    end

    return best
end

---Take network control of an entity. Must run inside a thread (it waits).
---@param entity integer
---@param timeout? integer ms, default 2000
---@return boolean
function Mechanic.RequestControl(entity, timeout)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return false end

    -- Local-only entities are always ours
    if not NetworkGetEntityIsNetworked(entity) then return true end
    if NetworkHasControlOfEntity(entity) then return true end

    local deadline = GetGameTimer() + (timeout or 2000)

    while not NetworkHasControlOfEntity(entity) do
        if not DoesEntityExist(entity) or GetGameTimer() > deadline then
            return false
        end

        NetworkRequestControlOfEntity(entity)
        Wait(0)
    end

    return true
end

-- ---------------------------------------------------------------------------
-- Notify
-- ---------------------------------------------------------------------------

RegisterNetEvent('ap1le_mechanicjob:notify', function(msg, nType)
    if type(msg) ~= 'string' then return end
    UI.Notify(msg, nType or 'inform')
end)

-- ---------------------------------------------------------------------------
-- NUI locale
-- ---------------------------------------------------------------------------

RegisterNUICallback('locale', function(_, cb)
    local out = {}

    for key, text in pairs(lib.getLocales()) do
        if type(key) == 'string' and key:sub(1, 3) == 'ui_' then
            out[key] = text
        end
    end

    cb(out)
end)

-- ---------------------------------------------------------------------------
-- Blips
-- ---------------------------------------------------------------------------

local function createBlips()
    for i = 1, #Config.Workshops do
        local ws = Config.Workshops[i]
        local blip = AddBlipForCoord(ws.coords.x, ws.coords.y, ws.coords.z)
        local cfg = ws.blip or {}

        SetBlipSprite(blip, cfg.sprite or 446)
        SetBlipColour(blip, cfg.colour or 5)
        SetBlipScale(blip, cfg.scale or 0.8)
        SetBlipDisplay(blip, 4)
        SetBlipAsShortRange(blip, true)

        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(ws.label or locale('blip_workshop'))
        EndTextCommandSetBlipName(blip)

        blips[#blips + 1] = blip
    end
end

-- ---------------------------------------------------------------------------
-- ox_target
-- ---------------------------------------------------------------------------

-- ox_inventory item check with a short cache: canInteract is polled while targeting
local itemCache = {}

local function hasItem(name)
    local now = GetGameTimer()
    local cached = itemCache[name]
    if cached and now - cached.at < 1000 then return cached.value end

    local ok, count = pcall(function()
        return exports.ox_inventory:Search('count', name)
    end)

    local value = ok and type(count) == 'number' and count > 0 or false
    itemCache[name] = { at = now, value = value }

    return value
end

---Common gate for every option: mechanic, not busy, on foot.
local function canUse()
    return Mechanic.IsMechanic() and not Anim.IsBusy() and not cache.vehicle
end

local function registerTargets()
    if targetsRegistered then return end
    targetsRegistered = true

    local groups = { [Config.Job] = 0 }

    local function repairOption(kind, labelKey, icon)
        return {
            name = 'ap1le_mechanicjob:repair_' .. kind,
            icon = icon,
            label = locale(labelKey),
            groups = groups,
            distance = 2.5,
            canInteract = function()
                return canUse() and Mechanic.InWorkshop() ~= nil
            end,
            onSelect = function(data)
                Repair.Start(data.entity, kind)
            end,
        }
    end

    exports.ox_target:addGlobalVehicle({
        repairOption('engine', 'target_repair_engine', 'fa-solid fa-screwdriver-wrench'),
        repairOption('body', 'target_repair_body', 'fa-solid fa-car-burst'),
        repairOption('tyre', 'target_change_tyre', 'fa-solid fa-circle-dot'),
        {
            name = 'ap1le_mechanicjob:repair_field',
            icon = 'fa-solid fa-wrench',
            label = locale('target_field_repair'),
            groups = groups,
            distance = 2.5,
            canInteract = function()
                return canUse() and hasItem(Config.Repair.field.item)
            end,
            onSelect = function(data)
                Repair.Start(data.entity, 'field')
            end,
        },
        {
            name = 'ap1le_mechanicjob:tuning',
            icon = 'fa-solid fa-sliders',
            label = locale('target_tuning'),
            groups = groups,
            distance = 2.5,
            canInteract = function()
                return canUse() and Mechanic.InWorkshop() ~= nil
            end,
            onSelect = function(data)
                Tuning.Open(data.entity)
            end,
        },
        {
            name = 'ap1le_mechanicjob:tow_load',
            icon = 'fa-solid fa-truck-ramp-box',
            label = locale('target_tow_load'),
            groups = groups,
            distance = 3.0,
            canInteract = function(entity)
                return canUse()
                    and not Towing.IsTruck(entity)
                    and not IsEntityAttached(entity)
                    and Towing.FindTruck(entity) ~= nil
            end,
            onSelect = function(data)
                Towing.Load(data.entity)
            end,
        },
    })

    exports.ox_target:addModel(Config.Towing.trucks, {
        {
            name = 'ap1le_mechanicjob:tow_unload',
            icon = 'fa-solid fa-truck-ramp-box',
            label = locale('target_tow_unload'),
            groups = groups,
            distance = 4.0,
            canInteract = function(entity)
                return canUse() and Towing.GetLoaded(entity) ~= nil
            end,
            onSelect = function(data)
                Towing.Unload(data.entity)
            end,
        },
    })
end

-- ---------------------------------------------------------------------------
-- F6 job menu
-- ---------------------------------------------------------------------------

function Mechanic.OpenMenu()
    if not Mechanic.IsMechanic() or Anim.IsBusy() then return end

    lib.registerContext({
        id = MENU_ID,
        title = locale('menu_title'),
        options = {
            {
                title = locale('menu_invoice'),
                icon = 'file-invoice-dollar',
                onSelect = function()
                    Billing.OpenCreate()
                end,
            },
            {
                title = locale('menu_field_repair'),
                icon = 'wrench',
                onSelect = function()
                    local vehicle = Mechanic.GetTargetVehicle()

                    if not vehicle then
                        UI.Notify(locale('too_far'), 'error')
                        return
                    end

                    Repair.Start(vehicle, 'field')
                end,
            },
        },
    })

    lib.showContext(MENU_ID)
end

lib.addKeybind({
    name = 'mechanic_menu',
    description = locale('menu_title'),
    defaultKey = 'F6',
    onPressed = function()
        Mechanic.OpenMenu()
    end,
})

-- ---------------------------------------------------------------------------
-- Start / stop
-- ---------------------------------------------------------------------------

CreateThread(function()
    createBlips()
    registerTargets()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    pcall(function() exports.ox_target:removeGlobalVehicle(VEHICLE_OPTIONS) end)
    pcall(function() exports.ox_target:removeModel(Config.Towing.trucks, MODEL_OPTIONS) end)

    for i = 1, #blips do
        if DoesBlipExist(blips[i]) then RemoveBlip(blips[i]) end
    end
    blips = {}

    pcall(function() lib.hideContext(false) end)

    -- Camera, freeze state and preview are cleaned by Tuning's own stop handler;
    -- make sure the mouse is never left captured by a dead NUI.
    SetNuiFocus(false, false)
end)
