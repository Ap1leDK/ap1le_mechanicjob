-- ap1le_mechanicjob: car wash ("Rens bil").
-- Mechanic only; anywhere unless Config.Wash.workshopOnly. Needs Config.Wash.item in the mechanic's own
-- inventory; one is removed when the wash finishes. The server owns the timing, the item and the price
-- (price list id 'wash', default Config.Wash.price); the client only plays the animation and opens the
-- invoice dialog with the returned price.

local function hasItem(source, item)
    local count = exports.ox_inventory:Search(source, 'count', item)
    return type(count) == 'number' and count >= 1
end

---Current wash price (price list override or Config.Wash.price).
---@return integer
local function washPrice()
    local price = Mechanic.GetPrices().wash
    return math.tointeger(price) or math.tointeger(Config.Wash.price) or 0
end

lib.callback.register('ap1le_mechanicjob:wash:begin', function(source, netId)
    if not Mechanic.GetMechanic(source) then return false, 'not_mechanic' end
    if not Mechanic.RateLimit(source, 'wash:begin', 1000) then return false, 'too_fast' end

    local cfg = Config.Wash
    if type(cfg) ~= 'table' or type(cfg.item) ~= 'string' or not Mechanic.IsInt(cfg.time, 1, 600000) then
        print('[ap1le_mechanicjob] Config.Wash is missing or invalid')
        return false, 'error'
    end

    if Mechanic.GetPending(source) then return false, 'busy' end

    local vehicle, err = Mechanic.GetVehicle(source, netId)
    if not vehicle then
        if err == 'error' then Mechanic.Flag(source, 'wash:begin with invalid vehicle netId') end
        return false, err or 'too_far'
    end

    if cfg.workshopOnly and not Mechanic.PlayerWorkshop(source) then return false, 'not_in_workshop' end

    if not hasItem(source, cfg.item) then return false, 'missing_item' end

    Mechanic.SetPending(source, {
        kind = 'wash',
        netId = math.tointeger(netId),
        plate = Mechanic.EntityPlate(vehicle),
        minMs = math.floor(cfg.time * Config.MinTimeFactor),
        expectedMs = cfg.time,
    })

    return true, { time = cfg.time }
end)

lib.callback.register('ap1le_mechanicjob:wash:finish', function(source)
    if not Mechanic.RateLimit(source, 'wash:finish', 500) then return false, 'too_fast' end

    local pending = Mechanic.GetPending(source)
    if not pending or pending.kind ~= 'wash' then
        -- Log at most once per 10 s per player so spam cannot flood the console
        if Mechanic.RateLimit(source, 'flag:wash:finish', 10000) then
            Mechanic.Flag(source, 'wash:finish without a pending wash')
        end
        return false, 'error'
    end

    -- Any outcome below ends this pending action
    Mechanic.Pending[source] = nil

    if not Mechanic.GetMechanic(source) then return false, 'not_mechanic' end

    if not Mechanic.ElapsedOk(pending) then
        Mechanic.Flag(source, ('wash:finish too fast (%d ms < %d ms)'):format(GetGameTimer() - pending.startedAt, pending.minMs))
        return false, 'too_fast'
    end

    local vehicle, err = Mechanic.GetVehicle(source, pending.netId)
    if not vehicle then return false, err == 'error' and 'error' or 'too_far' end

    if pending.plate and Mechanic.EntityPlate(vehicle) ~= pending.plate then
        Mechanic.Flag(source, 'wash:finish plate changed during the wash')
        return false, 'error'
    end

    if Config.Wash.workshopOnly and not Mechanic.PlayerWorkshop(source) then return false, 'not_in_workshop' end

    local removed = exports.ox_inventory:RemoveItem(source, Config.Wash.item, 1)
    if removed ~= true then return false, 'missing_item' end

    return true, { netId = pending.netId, price = washPrice(), label = locale('wash_invoice_label') }
end)
