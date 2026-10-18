-- ap1le_mechanicjob: the workshop computers (client side).
-- A laptop prop per workshop (local, non-networked, only while the player is near) with an ox_target
-- "use computer" option. Opening: server check -> Anim.Laptop (walk up and type) -> scripted camera on the
-- screen -> NUI focus -> 'laptop:open'. The laptop NUI talks to the server only through 'laptop:request',
-- which forwards a whitelist of callbacks (the server re-checks job, grade and distance on every call).

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
    ['computer:deposit'] = function(args) return locale('pc_deposited', Mechanic.FormatMoney(args[1])) end,
    ['computer:withdraw'] = function(args) return locale('pc_withdrawn', Mechanic.FormatMoney(args[1])) end,
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

    local ok, result = lib.callback.await('ap1le_mechanicjob:' .. method, false, table.unpack(args, 1, 4))

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
end)
