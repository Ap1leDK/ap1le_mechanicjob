-- ap1le_mechanicjob: the workshop computers and customer terminals (client side).
-- Computer: a laptop prop per workshop (local, non-networked, only while the player is near) with an
-- ox_target "use computer" option. Opening: server check -> Anim.Laptop (walk up and type) -> scripted
-- camera on the screen -> NUI focus -> 'laptop:open'. The laptop NUI talks to the server only through
-- 'laptop:request', which forwards a whitelist of callbacks (the server re-checks job, grade and distance
-- on every call). The society deposit/withdraw go through the standard esx_society events (see
-- societyTransfer below).
-- Terminal: a kiosk per workshop (ox_target for everyone) that opens the tuning screen in design mode
-- on the player's own nearby vehicle (Tuning.OpenDesign).

Computer = {}

local LAPTOP_MODEL = `prop_laptop_01a`
local PROP_RANGE = 50.0                       -- the laptop prop exists within this distance
local WALK_AWAY = math.max(2.5, Config.Computer.serverDistance - 0.5)
local WATCH_MS = 400

-- The screen faces the laptop's local -Y side (see LAPTOP_STAND in anims.lua); camera sits behind the typist
local CAM_OFFSET = vec3(0.0, -1.15, 0.8)
local CAM_TARGET = vec3(0.0, 0.0, 0.2)
local CAM_FOV = 42.0

-- Callbacks the laptop NUI may reach
local METHODS = {
    ['stock:get'] = true,
    ['order:place'] = true,
    ['order:list'] = true,
    ['computer:catalog'] = true,
    ['computer:staff'] = true,
    ['computer:nearby'] = true,
    ['computer:hire'] = true,
    ['computer:setGrade'] = true,
    ['computer:fire'] = true,
    ['computer:economy'] = true,
    ['computer:deposit'] = true,
    ['computer:withdraw'] = true,
    ['computer:prices'] = true,
    ['computer:setPrices'] = true,
}

local GROUPS = { [Config.Job] = 0 }

local entries = {}      -- per workshop: { workshop, prop, point, zone }
local session = nil     -- the open computer: { workshop, coords, prop, cam, typing }
local opening = false
local stopped = false

-- ---------------------------------------------------------------------------
-- Camera
-- ---------------------------------------------------------------------------

local function startCamera(prop)
    if not prop or not DoesEntityExist(prop) then return nil end

    local pos = GetOffsetFromEntityInWorldCoords(prop, CAM_OFFSET.x, CAM_OFFSET.y, CAM_OFFSET.z)
    local target = GetOffsetFromEntityInWorldCoords(prop, CAM_TARGET.x, CAM_TARGET.y, CAM_TARGET.z)

    local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(cam, pos.x, pos.y, pos.z)
    PointCamAtCoord(cam, target.x, target.y, target.z)
    SetCamFov(cam, CAM_FOV)
    SetCamActive(cam, true)
    RenderScriptCams(true, true, 700, true, false)

    return cam
end

local function stopCamera(cam, instant)
    if not cam then return end

    RenderScriptCams(false, not instant, instant and 0 or 500, true, false)

    if DoesCamExist(cam) then
        DestroyCam(cam, false)
    end
end

-- ---------------------------------------------------------------------------
-- Open / close
-- ---------------------------------------------------------------------------

---@return boolean
function Computer.IsOpen()
    return session ~= nil
end

---Close the computer: release the mouse, hide the NUI, leave the camera and stop typing.
function Computer.Close()
    local s = session
    if not s then return end

    session = nil

    SetNuiFocus(false, false)
    UI.BlockPauseMenu()
    SendNUIMessage({ action = 'laptop:close', data = {} })

    stopCamera(s.cam, stopped)

    if s.typing then
        Anim.StopLaptop()
    end
end

---Close the computer when the mechanic dies, loses the job, gets into a vehicle or walks away.
local function watch(s)
    CreateThread(function()
        while session == s do
            Wait(WATCH_MS)

            if session ~= s then return end

            local ped = cache.ped

            if not Mechanic.IsMechanic()
                or IsEntityDead(ped)
                or IsPedRagdoll(ped)
                or IsPedInAnyVehicle(ped, false)
                or #(GetEntityCoords(ped) - s.coords) > WALK_AWAY then
                Computer.Close()
                return
            end
        end
    end)
end

---Open the computer of a workshop.
---@param workshop table Config.Workshops entry
---@param prop? integer the laptop prop (nil when the workshop has no prop)
function Computer.Open(workshop, prop)
    if session or opening or Anim.IsBusy() then return end

    if not Mechanic.IsMechanic() then
        Ap1le.Notify(locale('not_mechanic'), 'error')
        return
    end

    opening = true

    CreateThread(function()
        local ok, data = lib.callback.await('ap1le_mechanicjob:computer:open', false)

        if not ok or type(data) ~= 'table' then
            Ap1le.Notify(Mechanic.ErrorText(data), 'error')
            opening = false
            return
        end

        local typing = false

        if prop and DoesEntityExist(prop) then
            -- Blocks while the ped walks up to the laptop; false = busy or could not get there
            typing = Anim.Laptop(prop) == true

            if not typing then
                Ap1le.Notify(locale('busy'), 'error')
                opening = false
                return
            end
        end

        -- Things can change while walking
        if stopped or not Mechanic.IsMechanic() or IsEntityDead(cache.ped) then
            if typing then Anim.StopLaptop() end
            opening = false
            return
        end

        local c = workshop.computer.coords
        local s = { workshop = workshop, coords = vec3(c.x, c.y, c.z), prop = prop, typing = typing }
        session = s
        opening = false

        s.cam = startCamera(prop)

        local payload = {}
        for key, value in pairs(data) do payload[key] = value end
        -- The server sends this player's order limits (smaller below chef grade); config as fallback
        local limits = type(data.orderLimits) == 'table' and data.orderLimits or {}
        payload.orderLimits = nil
        payload.shop = {
            deliveryMinutes = Config.Shop.deliveryMinutes,
            maxPerLine = tonumber(limits.maxPerLine) or Config.Shop.maxPerLine,
            maxLines = tonumber(limits.maxLines) or Config.Shop.maxLines,
            maxTransfer = Config.Computer.maxTransfer,
            maxPrice = Config.Cosmetic.maxPrice,
        }

        SetNuiFocus(true, true)
        SendNUIMessage({ action = 'laptop:open', data = payload })

        watch(s)
    end)
end

-- ---------------------------------------------------------------------------
-- NUI callbacks
-- ---------------------------------------------------------------------------

---Whole-number floats from the JSON bridge (5.0) become integers so the server's integer checks pass.
---Functions and other non-JSON values are dropped.
local function normalise(value, depth)
    local kind = type(value)

    if kind == 'number' then
        if value == math.floor(value) and value >= -2 ^ 53 and value <= 2 ^ 53 then
            return math.tointeger(value) or value
        end
        return value
    end

    if kind == 'string' or kind == 'boolean' then return value end

    if kind == 'table' and depth < 4 then
        local out = {}
        for k, v in pairs(value) do
            if type(k) == 'string' or type(k) == 'number' then
                local clean = normalise(v, depth + 1)
                if clean ~= nil then out[k] = clean end
            end
        end
        return out
    end

    return nil
end

-- ---------------------------------------------------------------------------
-- Society deposit / withdraw (standard esx_society)
-- ---------------------------------------------------------------------------
-- Why: our own society code failed on deposits (v2). The money is now moved by esx_society's own server
-- events (esx_society:depositMoney / withdrawMoney), which only exist as net events, so the chef's client
-- has to trigger them. Because a client could skip our checks, the flow is guarded by the server:
--   1. computer:deposit / computer:withdraw (amount) -> chef at the computer, amount, cash / society
--      balance, esx_society's boss rule. Returns { kind, society, amount } and remembers the intent.
--   2. TriggerServerEvent('esx_society:depositMoney' | 'esx_society:withdrawMoney', society, amount)
--      with the amount the SERVER returned.
--   3. computer:transferResult (kind) -> the server waits until esx_addonaccount reported the matching
--      change of the society account, logs it, and returns the balance.
--   4. The new balance is read with the standard esx_society callback (esx_society:getSocietyMoney); when
--      that answers 0 for a grade that esx_society does not count as boss, the server's balance is used.

local TRANSFERS = {
    ['computer:deposit'] = { kind = 'deposit', event = 'esx_society:depositMoney' },
    ['computer:withdraw'] = { kind = 'withdraw', event = 'esx_society:withdrawMoney' },
}

local BALANCE_TIMEOUT_MS = 3000
local transferring = false

---Society balance through esx_society's own callback, or nil when it does not answer.
---@param society string
---@return number?
local function societyBalance(society)
    local answer = promise.new()
    local settled = false

    local function settle(value)
        if settled then return end
        settled = true
        answer:resolve(value)
    end

    local called = pcall(function()
        if ESX.TriggerServerCallback then
            ESX.TriggerServerCallback('esx_society:getSocietyMoney', settle, society)
        else
            settle(nil)
        end
    end)
    if not called then settle(nil) end

    SetTimeout(BALANCE_TIMEOUT_MS, function() settle(nil) end)

    return tonumber(Citizen.Await(answer))
end

---Run one deposit or withdrawal. Returns ok, data ({ kind, amount, balance }) or false, locale key.
---@param method string 'computer:deposit' | 'computer:withdraw'
---@param args table
---@return boolean, any
local function societyTransfer(method, args)
    local transfer = TRANSFERS[method]

    if transferring then return false, 'too_fast' end
    transferring = true

    local ok, success, result = pcall(function()
        local allowed, intent = lib.callback.await('ap1le_mechanicjob:' .. method, false, args[1])
        if not allowed then return false, intent end

        local amount = type(intent) == 'table' and math.tointeger(tonumber(intent.amount))
        if not amount or amount < 1 then return false, 'error' end

        local society = (type(intent) == 'table' and type(intent.society) == 'string') and intent.society or Config.Job

        TriggerServerEvent(transfer.event, society, amount)

        local confirmed, outcome = lib.callback.await('ap1le_mechanicjob:computer:transferResult', false, transfer.kind)
        if not confirmed then return false, outcome end

        local serverBalance = type(outcome) == 'table' and tonumber(outcome.balance) or nil
        local balance = societyBalance(society)

        -- esx_society answers 0 for grades that are not in its boss list: trust the server's number then
        if balance == nil or (balance == 0 and serverBalance and serverBalance > 0) then
            balance = serverBalance
        end

        return true, { kind = transfer.kind, amount = amount, balance = balance }
    end)

    transferring = false

    if not ok then
        print(('^1[ap1le_mechanicjob] society %s failed: %s^0'):format(transfer.kind, tostring(success)))
        return false, 'error'
    end

    return success, result
end

-- Success notification of the mutating methods: method -> function(args, data) -> text
local SUCCESS = {
    ['order:place'] = function(_, data)
        local total = type(data) == 'table' and data.total or 0
        local eta = type(data) == 'table' and tonumber(data.eta) or Config.Shop.deliveryMinutes * 60
        return locale('order_placed', Mechanic.FormatMoney(total), math.max(1, math.ceil(eta / 60)))
    end,
    ['computer:hire'] = function() return locale('pc_hired') end,
    ['computer:setGrade'] = function() return locale('pc_grade_set') end,
    ['computer:fire'] = function() return locale('pc_fired') end,
    -- The amount the server confirmed (data.amount), not the one typed in the NUI
    ['computer:deposit'] = function(args, data)
        return locale('pc_deposited', Mechanic.FormatMoney(type(data) == 'table' and data.amount or args[1]))
    end,
    ['computer:withdraw'] = function(args, data)
        return locale('pc_withdrawn', Mechanic.FormatMoney(type(data) == 'table' and data.amount or args[1]))
    end,
    ['computer:setPrices'] = function() return locale('pc_prices_saved') end,
}

RegisterNUICallback('laptop:request', function(data, cb)
    if not session or type(data) ~= 'table' or type(data.method) ~= 'string' or not METHODS[data.method] then
        cb({ ok = false, error = locale('error') })
        return
    end

    local method = data.method
    local args = type(data.args) == 'table' and normalise(data.args, 0) or {}
    if type(args) ~= 'table' then args = {} end

    local ok, result

    if TRANSFERS[method] then
        ok, result = societyTransfer(method, args)
    else
        ok, result = lib.callback.await('ap1le_mechanicjob:' .. method, false, table.unpack(args, 1, 4))
    end

    local success = SUCCESS[method]

    if success then
        if ok then
            Ap1le.Notify(success(args, result), 'success')
        else
            Ap1le.Notify(Mechanic.ErrorText(result), 'error')
        end
    end

    cb({
        ok = ok == true,
        data = result,
        error = (not ok) and Mechanic.ErrorText(result) or nil,
        -- The locale key of a failure (e.g. 'too_fast'), so the NUI can retry a rate-limited read
        code = (not ok and type(result) == 'string') and result or nil,
    })
end)

RegisterNUICallback('laptop:close', function(_, cb)
    Computer.Close()
    cb({ ok = true })
end)

-- ---------------------------------------------------------------------------
-- Job offers (the chef hires from the laptop; the player must accept first)
-- ---------------------------------------------------------------------------

local CONFIRM_BUSY_MS = 300   -- a Confirm that returns false faster than this never reached the player
local hireAsk = nil           -- the offer on screen right now: { closeAt }

-- Server -> this player: returns 'accepted', 'declined', 'timeout' or 'busy' (another dialog was open)
lib.callback.register('ap1le_mechanicjob:hire:ask', function(workshopLabel, chefName, seconds)
    if hireAsk then return 'busy' end

    seconds = math.floor(math.max(5, math.min(tonumber(seconds) or 30, 60)))
    local ask = {}
    hireAsk = ask

    -- The offer closes by itself; only our own dialog is closed (Confirm resolved = hireAsk cleared)
    SetTimeout(seconds * 1000, function()
        if hireAsk == ask then
            ask.timedOut = true
            Ap1le.CloseDialog()
        end
    end)

    local askedAt = GetGameTimer()
    local accepted = Ap1le.Confirm({
        title = locale('pc_hire_offer_title'),
        content = locale('pc_hire_offer', tostring(chefName or '?'), tostring(workshopLabel or '?'), seconds),
        confirmLabel = locale('pc_hire_accept'),
        cancelLabel = locale('pc_hire_decline'),
    })
    hireAsk = nil

    if accepted == true then return 'accepted' end
    if ask.timedOut then return 'timeout' end
    if GetGameTimer() - askedAt < CONFIRM_BUSY_MS then return 'busy' end
    return 'declined'
end)

-- ---------------------------------------------------------------------------
-- Props and targets
-- ---------------------------------------------------------------------------

local function targetOption(entry)
    return {
        name = 'ap1le_mechanicjob:computer:' .. entry.workshop.id,
        icon = 'fa-solid fa-laptop',
        label = locale('target_computer'),
        groups = GROUPS,
        distance = Config.Computer.useDistance,
        canInteract = function()
            return Mechanic.IsMechanic() and not Anim.IsBusy() and not session and not opening and not cache.vehicle
        end,
        onSelect = function()
            Computer.Open(entry.workshop, entry.prop)
        end,
    }
end

local function spawnProp(entry)
    if entry.prop or entry.spawning or stopped then return end
    entry.spawning = true

    CreateThread(function()
        local loaded = pcall(lib.requestModel, LAPTOP_MODEL, 3000)

        -- Left the range or the resource stopped while the model streamed in
        if not loaded or stopped or not entry.spawning then
            entry.spawning = false
            return
        end

        local c = entry.workshop.computer.coords
        local prop = CreateObject(LAPTOP_MODEL, c.x, c.y, c.z, false, false, false)
        SetModelAsNoLongerNeeded(LAPTOP_MODEL)
        entry.spawning = false

        if not prop or prop == 0 then return end

        SetEntityHeading(prop, c.w or 0.0)
        FreezeEntityPosition(prop, true)
        entry.prop = prop

        exports.ox_target:addLocalEntity(prop, { targetOption(entry) })
    end)
end

local function despawnProp(entry)
    entry.spawning = false

    local prop = entry.prop
    entry.prop = nil

    if prop and DoesEntityExist(prop) then
        pcall(function() exports.ox_target:removeLocalEntity(prop) end)
        DeleteEntity(prop)
    end
end

local function registerZone(entry)
    local c = entry.workshop.computer.coords

    entry.zone = exports.ox_target:addSphereZone({
        name = 'ap1le_mechanicjob:computer:' .. entry.workshop.id,
        coords = vec3(c.x, c.y, c.z),
        radius = 0.8,
        debug = false,
        options = { targetOption(entry) },
    })
end

local function setup()
    for i = 1, #Config.Workshops do
        local ws = Config.Workshops[i]
        local c = ws.computer and ws.computer.coords

        if c then
            local entry = { workshop = ws }
            entries[#entries + 1] = entry

            if ws.computer.spawnProp then
                -- lib.points runs onEnter on its next tick when the player already stands in range
                entry.point = lib.points.new({
                    coords = vec3(c.x, c.y, c.z),
                    distance = PROP_RANGE,
                    onEnter = function() spawnProp(entry) end,
                    onExit = function() despawnProp(entry) end,
                })
            else
                registerZone(entry)
            end
        end
    end
end

CreateThread(setup)

-- ---------------------------------------------------------------------------
-- Customer terminals (design mode)
-- ---------------------------------------------------------------------------
-- One kiosk per workshop (Config.Workshops[i].terminal = vec4, w = heading of the kiosk). Everybody can use
-- it (no job check): it opens the tuning screen in design mode on the player's OWN vehicle. The client only
-- picks the vehicle in reach; the server (terminal:open) checks the terminal distance and that the vehicle
-- belongs to the player.
-- The kiosk prop is optional and local (non-networked). prop_parknmeter_02 is the pay-and-display ticket
-- machine; it is NOT an ATM model on purpose, so banking scripts that add ox_target options to ATM models
-- never attach their "use ATM" options to it. Set KIOSK_MODEL to nil to use the invisible target only.
-- coords.z of the terminal is the floor level: the prop is lifted by the model's lowest point.

local KIOSK_MODEL = `prop_parknmeter_02`
local KIOSK_RANGE = 50.0                    -- the prop exists within this distance
local TERMINAL_RADIUS = 1.1                 -- target sphere
local TERMINAL_CENTER_Z = 1.0               -- the target sphere sits this high above the floor
local TERMINAL_DISTANCE = 2.0               -- ox_target use distance (server limit is 3.0 m)
local TERMINAL_OPTION = 'ap1le_mechanicjob:terminal:'

local terminals = {}                        -- per workshop: { workshop, prop, spawning, point, zone }

---Open the design mode on the player's own vehicle: the one they sit in, else the closest one in reach.
local function useTerminal()
    if Tuning.IsOpen() or Anim.IsBusy() then return end

    local vehicle = cache.vehicle

    if not vehicle then
        vehicle = lib.getClosestVehicle(GetEntityCoords(cache.ped), Config.MaxVehicleDistance, false)
    end

    -- Tell the player what to do instead of failing silently. Whether it is THEIR vehicle is checked by the
    -- server, which answers with its own message (workorder_not_owned).
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        Ap1le.Notify(locale('terminal_no_vehicle'), 'error')
        return
    end

    Tuning.OpenDesign(vehicle)
end

local function terminalOption(entry)
    return {
        name = TERMINAL_OPTION .. entry.workshop.id,
        icon = 'fa-solid fa-pen-ruler',
        label = locale('target_terminal'),
        distance = TERMINAL_DISTANCE,
        canInteract = function()
            return not Anim.IsBusy() and not Tuning.IsOpen() and not Computer.IsOpen()
        end,
        onSelect = useTerminal,
    }
end

local function registerTerminalZone(entry)
    local c = entry.workshop.terminal

    entry.zone = exports.ox_target:addSphereZone({
        name = TERMINAL_OPTION .. entry.workshop.id,
        coords = vec3(c.x, c.y, c.z + TERMINAL_CENTER_Z),
        radius = TERMINAL_RADIUS,
        debug = false,
        options = { terminalOption(entry) },
    })
end

local function removeTerminalZone(entry)
    if entry.zone then
        pcall(function() exports.ox_target:removeZone(entry.zone, true) end)
        entry.zone = nil
    end
end

local function spawnKiosk(entry)
    if not KIOSK_MODEL or entry.prop or entry.spawning or stopped then return end
    entry.spawning = true

    CreateThread(function()
        local loaded = pcall(lib.requestModel, KIOSK_MODEL, 3000)

        -- Left the range or the resource stopped while the model streamed in
        if not loaded or stopped or not entry.spawning then
            entry.spawning = false
            return
        end

        local c = entry.workshop.terminal
        local low = GetModelDimensions(KIOSK_MODEL)
        local prop = CreateObject(KIOSK_MODEL, c.x, c.y, c.z - low.z, false, false, false)
        SetModelAsNoLongerNeeded(KIOSK_MODEL)
        entry.spawning = false

        if not prop or prop == 0 then return end

        SetEntityHeading(prop, c.w or 0.0)
        FreezeEntityPosition(prop, true)
        entry.prop = prop
    end)
end

local function despawnKiosk(entry)
    entry.spawning = false

    local prop = entry.prop
    entry.prop = nil

    if prop and DoesEntityExist(prop) then
        DeleteEntity(prop)
    end
end

local function setupTerminals()
    for i = 1, #Config.Workshops do
        local ws = Config.Workshops[i]
        local c = ws.terminal

        if c then
            local entry = { workshop = ws }
            terminals[#terminals + 1] = entry

            registerTerminalZone(entry)

            if KIOSK_MODEL then
                -- lib.points runs onEnter on its next tick when the player already stands in range
                entry.point = lib.points.new({
                    coords = vec3(c.x, c.y, c.z),
                    distance = KIOSK_RANGE,
                    onEnter = function() spawnKiosk(entry) end,
                    onExit = function() despawnKiosk(entry) end,
                })
            end
        end
    end
end

CreateThread(setupTerminals)

-- ox_target forgets zones and entity targets when it restarts
AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= 'ox_target' then return end

    CreateThread(function()
        Wait(500)

        local here = GetEntityCoords(cache.ped)

        for i = 1, #entries do
            local entry = entries[i]
            local c = entry.workshop.computer.coords

            if entry.workshop.computer.spawnProp then
                despawnProp(entry)
                if #(here - vec3(c.x, c.y, c.z)) <= PROP_RANGE then spawnProp(entry) end
            else
                if entry.zone then pcall(function() exports.ox_target:removeZone(entry.zone, true) end) end
                registerZone(entry)
            end
        end

        for i = 1, #terminals do
            removeTerminalZone(terminals[i])
            registerTerminalZone(terminals[i])
        end
    end)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    stopped = true
    opening = false

    -- Close releases focus, the NUI, the camera (immediately, because stopped is set) and the typing loop
    Computer.Close()

    pcall(Anim.StopLaptop)

    for i = 1, #entries do
        local entry = entries[i]

        if entry.point then
            entry.point:remove()
            entry.point = nil
        end

        despawnProp(entry)

        if entry.zone then
            pcall(function() exports.ox_target:removeZone(entry.zone, true) end)
            entry.zone = nil
        end
    end

    entries = {}

    for i = 1, #terminals do
        local entry = terminals[i]

        if entry.point then
            entry.point:remove()
            entry.point = nil
        end

        despawnKiosk(entry)
        removeTerminalZone(entry)
    end

    terminals = {}
end)
