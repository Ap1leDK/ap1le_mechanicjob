-- ap1le_mechanicjob: car wash ("Rens bil"), client side.
-- Flow: server wash:begin (item, time, distance) -> Anim.Wash (bucket + sponge, the dirt level goes down
-- during the sequence) -> server wash:finish (removes one cleaning kit, returns the price list price)
-- -> final clean state applied to the car -> Billing.OpenCreate prefilled with the wash line.
-- Mechanics only; anywhere unless Config.Wash.workshopOnly.

Wash = {}

local OPTION = 'ap1le_mechanicjob:wash'
local GROUPS = { [Config.Job] = 0 }

local working = false
local registered = false

local function cancelPending()
    lib.callback.await('ap1le_mechanicjob:cancel', false)
end

---Leave the car completely clean once the server confirmed the wash. Anim.Wash already tweens the dirt
---level to 0 while it runs, but the car may be owned by another client, so it is applied again with
---network control (a failed request is harmless: the animation has already shown the result).
---@param vehicle integer
local function applyClean(vehicle)
    if not DoesEntityExist(vehicle) then return end
    if not Mechanic.RequestControl(vehicle, 1500) then return end

    SetVehicleDirtLevel(vehicle, 0.0)
    WashDecalsFromVehicle(vehicle, 1.0)
end

---Start washing a vehicle. Must be callable from ox_target and from the F6 menu.
---@param vehicle integer
function Wash.Start(vehicle)
    if working or Anim.IsBusy() then return end
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end

    if not Mechanic.IsMechanic() then
        Ap1le.Notify(locale('not_mechanic'), 'error')
        return
    end

    if IsPedInAnyVehicle(cache.ped, false) then
        Ap1le.Notify(locale('busy'), 'error')
        return
    end

    if Config.Wash.workshopOnly and not Mechanic.InWorkshop() then
        Ap1le.Notify(locale('not_in_workshop'), 'error')
        return
    end

    if not NetworkGetEntityIsNetworked(vehicle) then
        Ap1le.Notify(locale('error'), 'error')
        return
    end

    if #(GetEntityCoords(cache.ped) - GetEntityCoords(vehicle)) > Config.MaxVehicleDistance then
        Ap1le.Notify(locale('too_far'), 'error')
        return
    end

    working = true

    CreateThread(function()
        local netId = NetworkGetNetworkIdFromEntity(vehicle)
        local ok, data = lib.callback.await('ap1le_mechanicjob:wash:begin', false, netId)

        if not ok then
            Ap1le.Notify(Mechanic.ErrorText(data), 'error')
            working = false
            return
        end

        if not Mechanic.RequestControl(vehicle) then
            cancelPending()
            Ap1le.Notify(locale('error'), 'error')
            working = false
            return
        end

        local time = type(data) == 'table' and tonumber(data.time) or Config.Wash.time
        local completed = Anim.Wash(vehicle, time)

        if not completed then
            -- Anim.Wash puts the original dirt level back when it is cancelled
            cancelPending()
            Ap1le.Notify(locale('cancelled'), 'info')
            working = false
            return
        end

        local finished, result = lib.callback.await('ap1le_mechanicjob:wash:finish', false)

        if not finished then
            Ap1le.Notify(Mechanic.ErrorText(result), 'error')
            working = false
            return
        end

        applyClean(vehicle)
        Ap1le.Notify(locale('wash_done'), 'success')
        working = false

        -- Bill the customer: the wash line comes from the server (price list id 'wash'). A price of 0 is a
        -- free service, so no invoice is offered.
        local price = type(result) == 'table' and math.tointeger(tonumber(result.price)) or 0

        if price and price > 0 then
            local label = type(result.label) == 'string' and result.label or locale('wash_invoice_label')
            Billing.OpenCreate({ { label = label, price = price } })
        end
    end)
end

-- ---------------------------------------------------------------------------
-- ox_target: global vehicle option
-- ---------------------------------------------------------------------------

local function register()
    if registered then return end
    registered = true

    exports.ox_target:addGlobalVehicle({
        {
            name = OPTION,
            icon = 'fa-solid fa-soap',
            label = locale('target_wash'),
            groups = GROUPS,
            distance = 2.5,
            canInteract = function()
                if not Mechanic.IsMechanic() or working or Anim.IsBusy() or cache.vehicle then return false end
                if Config.Wash.workshopOnly and not Mechanic.InWorkshop() then return false end

                return Mechanic.HasItem(Config.Wash.item)
            end,
            onSelect = function(data)
                Wash.Start(data.entity)
            end,
        },
    })
end

CreateThread(register)

-- ox_target forgets everything when it restarts
AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= 'ox_target' then return end

    CreateThread(function()
        Wait(500)
        registered = false
        register()
    end)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    pcall(function() exports.ox_target:removeGlobalVehicle({ OPTION }) end)
    registered = false
end)
