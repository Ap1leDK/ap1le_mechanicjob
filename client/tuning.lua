-- ap1le_mechanicjob: tuning (client).
--  * Tuning screen: NUI + scripted camera + local preview of cosmetic changes.
--  * Cosmetic install: native animation per distinct anim type, apply, save, then invoice.
--  * Performance swap: the old part is physically taken OUT, then the new part is put IN.

Tuning = {}

-- Active tuning session (nil when closed)
-- { vehicle, netId, original, owned, wasFrozen, cams = {}, cam, hoodOpen, lightsForced, installing }
local state = nil
local opening = false
local swapping = false

-- ---------------------------------------------------------------------------
-- Static data
-- ---------------------------------------------------------------------------

local CAMERA_FOCUS = { default = true, front = true, rear = true, wheel = true, engine = true, side = true }

local ANIM_TYPES = { body = true, under = true, interior = true, hood = true, paint = true, wheel = true }

local PAINT_KEYS = { color1 = true, color2 = true, pearlescentColor = true, wheelColor = true }

-- Vanilla window tint / plate style names (GTA has no label for them in the mod menu API)
local WINDOW_TINTS = { [0] = 'None', 'Pure Black', 'Dark Smoke', 'Light Smoke', 'Stock', 'Limo', 'Green' }
local PLATE_STYLES = {
    [0] = 'Blue on White 1', 'Yellow on Black', 'Yellow on Blue', 'Blue on White 2', 'Blue on White 3', 'San Andreas',
}

local XENON_DEFAULT = 255
local NEON_KEYS = { 'l', 'r', 'f', 'b' }

local MAX_CHANGES = 40

-- Performance categories in a stable order (Config.Performance is a hash table)
local PERF_ORDER = {}
for category in pairs(Config.Performance) do
    PERF_ORDER[#PERF_ORDER + 1] = category
end
table.sort(PERF_ORDER, function(a, b)
    return Config.Performance[a].modType < Config.Performance[b].modType
end)

local cosmeticById = {}
for i = 1, #Config.Cosmetic.mods do
    cosmeticById[Config.Cosmetic.mods[i].id] = Config.Cosmetic.mods[i]
end

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------

local function failText(err)
    if type(err) == 'string' and err ~= '' then return locale(err) end
    return locale('error')
end

local function trim(s)
    return (tostring(s or ''):gsub('^%s*(.-)%s*$', '%1'))
end

---Truncate to at most `max` UTF-8 characters.
local function truncate(s, max)
    if utf8.len(s) and utf8.len(s) <= max then return s end
    local cut = utf8.offset(s, max + 1)
    return cut and s:sub(1, cut - 1) or s:sub(1, max)
end

local function toInt(v)
    local n = tonumber(v)
    if not n or n ~= n then return nil end
    return math.floor(n)
end

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

---ox_inventory item check (client export).
local function hasItem(item)
    local ok, count = pcall(function()
        return exports.ox_inventory:Search('count', item)
    end)

    return ok and type(count) == 'number' and count > 0
end

---Label of a mod option; falls back to "<label> <n>" when GTA has no text for it.
local function modOptionLabel(vehicle, modType, index, fallbackLabel)
    local label = GetModTextLabel(vehicle, modType, index)

    if label and label ~= '' then
        local text = GetLabelText(label)
        if text and text ~= '' and text ~= 'NULL' then
            return text
        end
    end

    return ('%s %d'):format(fallbackLabel, index + 1)
end

---Visually set a performance category to a level (0 = stock). Needs network control to sync.
local function setPerformanceMod(vehicle, cfg, level)
    SetVehicleModKit(vehicle, 0)

    if cfg.toggle then
        ToggleVehicleMod(vehicle, cfg.modType, level > 0)
    else
        SetVehicleMod(vehicle, cfg.modType, level - 1, false)
    end
end

local function liveLevel(vehicle, cfg)
    if cfg.toggle then
        return IsToggleModOn(vehicle, cfg.modType) and 1 or 0
    end

    return GetVehicleMod(vehicle, cfg.modType) + 1
end

-- ---------------------------------------------------------------------------
-- Value parsing (xenon / neon). Accepts the shapes the NUI is expected to send.
-- ---------------------------------------------------------------------------

---@return boolean enabled, integer colour
local function parseXenon(value)
    local enabled, colour = false, XENON_DEFAULT

    if type(value) == 'table' then
        enabled = value.enabled == true or value.enabled == 1
        colour = toInt(value.colour or value.color) or XENON_DEFAULT
    elseif type(value) == 'boolean' then
        enabled = value
    elseif type(value) == 'number' then
        enabled = true
        colour = toInt(value) or XENON_DEFAULT
    end

    if colour < 0 or colour > 12 then colour = XENON_DEFAULT end

    return enabled, colour
end

---@return boolean[] enabled (index 1..4 = left, right, front, back)
local function parseNeonEnabled(value)
    local out = { false, false, false, false }

    if type(value) == 'boolean' then
        return { value, value, value, value }
    end

    if type(value) ~= 'table' then return out end

    for i = 1, 4 do
        local v = value[NEON_KEYS[i]]
        if v == nil then v = value[i] end
        out[i] = v == true or v == 1
    end

    return out
end

---@return integer r, integer g, integer b
local function parseNeonColour(value)
    if type(value) ~= 'table' then return 255, 255, 255 end

    local r = toInt(value.r or value[1]) or 255
    local g = toInt(value.g or value[2]) or 255
    local b = toInt(value.b or value[3]) or 255

    return clamp(r, 0, 255), clamp(g, 0, 255), clamp(b, 0, 255)
end

---Neon value from the NUI: { enabled = {l,r,f,b}, colour = {r,g,b} }
local function parseNeon(value)
    if type(value) ~= 'table' then return parseNeonEnabled(value), 255, 255, 255 end

    local enabled = parseNeonEnabled(value.enabled)
    local r, g, b = parseNeonColour(value.colour or value.color)

    return enabled, r, g, b
end

-- ---------------------------------------------------------------------------
-- Applying a single cosmetic change to the vehicle (preview and install)
-- ---------------------------------------------------------------------------

---@param vehicle integer
---@param cType string 'mod'|'paint'|'extra'
---@param id string
---@param value any
---@return boolean applied
local function applyChange(vehicle, cType, id, value)
    if not DoesEntityExist(vehicle) then return false end

    SetVehicleModKit(vehicle, 0)

    if cType == 'mod' then
        local cfg = cosmeticById[id]
        local index = toInt(value)
        if not cfg or not index then return false end

        local count = GetNumVehicleMods(vehicle, cfg.modType)
        if index < -1 or index >= count then return false end

        -- Keep the custom tyre variation when swapping wheels
        local variation = false
        if cfg.modType == 23 then
            variation = GetVehicleModVariation(vehicle, 23)
        end

        SetVehicleMod(vehicle, cfg.modType, index, variation)

        -- Bikes have a separate rear wheel mod
        if cfg.modType == 23 and IsThisModelABike(GetEntityModel(vehicle)) then
            SetVehicleMod(vehicle, 24, index, variation)
        end

        return true
    end

    if cType == 'paint' then
        -- Either one colour per call (id = colour key) or a table of colours (id = 'paint')
        local values = {}

        if PAINT_KEYS[id] then
            values[id] = toInt(value)
        elseif id == 'paint' and type(value) == 'table' then
            for key in pairs(PAINT_KEYS) do
                values[key] = toInt(value[key])
            end
        else
            return false
        end

        local color1, color2 = GetVehicleColours(vehicle)
        local pearl, wheel = GetVehicleExtraColours(vehicle)

        if values.color1 then
            color1 = clamp(values.color1, 0, 255)
            ClearVehicleCustomPrimaryColour(vehicle)
        end
        if values.color2 then
            color2 = clamp(values.color2, 0, 255)
            ClearVehicleCustomSecondaryColour(vehicle)
        end
        if values.pearlescentColor then pearl = clamp(values.pearlescentColor, 0, 255) end
        if values.wheelColor then wheel = clamp(values.wheelColor, 0, 255) end

        SetVehicleColours(vehicle, color1, color2)
        SetVehicleExtraColours(vehicle, pearl, wheel)

        return true
    end

    if cType == 'extra' then
        if id == 'windowTint' then
            local tint = toInt(value)
            if not tint or tint < 0 or tint >= math.max(GetNumVehicleWindowTints(), 1) then return false end

            SetVehicleWindowTint(vehicle, tint)
            return true
        end

        if id == 'plate' then
            local style = toInt(value)
            if not style or style < 0 or style >= math.max(GetNumberOfVehicleNumberPlates(), 1) then return false end

            SetVehicleNumberPlateTextIndex(vehicle, style)
            return true
        end

        if id == 'xenon' then
            local enabled, colour = parseXenon(value)

            ToggleVehicleMod(vehicle, 22, enabled)
            if enabled then
                SetVehicleXenonLightsColor(vehicle, colour)

                -- Xenon is only visible with the lights on
                if state and state.vehicle == vehicle and not state.lightsForced then
                    state.lightsForced = true
                    SetVehicleLights(vehicle, 2)
                end
            end

            return true
        end

        if id == 'neon' then
            local enabled, r, g, b = parseNeon(value)

            for i = 0, 3 do
                SetVehicleNeonLightEnabled(vehicle, i, enabled[i + 1])
            end
            SetVehicleNeonLightsColour(vehicle, r, g, b)

            return true
        end
    end

    return false
end

---True when the change would not alter the vehicle compared to the original props.
local function isUnchanged(original, cType, id, value)
    if cType == 'mod' then
        return toInt(value) == original[id]
    end

    if cType == 'paint' then
        local key = PAINT_KEYS[id] and id
        if key then
            -- Custom (RGB) paint is stored as a table: always counts as a change
            return type(original[key]) == 'number' and toInt(value) == original[key]
        end
        return false
    end

    if cType == 'extra' then
        if id == 'windowTint' then return toInt(value) == original.windowTint end
        if id == 'plate' then return toInt(value) == original.plateIndex end

        if id == 'xenon' then
            local enabled, colour = parseXenon(value)
            local oldEnabled, oldColour = parseXenon({ enabled = original.modXenon, colour = original.xenonColor })

            if not enabled and not oldEnabled then return true end
            return enabled == oldEnabled and colour == oldColour
        end

        if id == 'neon' then
            local enabled, r, g, b = parseNeon(value)
            local oldEnabled = parseNeonEnabled(original.neonEnabled)
            local oldR, oldG, oldB = parseNeonColour(original.neonColor)

            local anyOn = false
            for i = 1, 4 do
                if enabled[i] ~= oldEnabled[i] then return false end
                if enabled[i] then anyOn = true end
            end

            if not anyOn then return true end
            return r == oldR and g == oldG and b == oldB
        end
    end

    return false
end

-- ---------------------------------------------------------------------------
-- Camera
-- ---------------------------------------------------------------------------

---Camera position / look-at (both in vehicle-local offsets) for a focus preset.
local function cameraPreset(vehicle, focus)
    local minDim, maxDim = GetModelDimensions(GetEntityModel(vehicle))
    local width = maxDim.x - minDim.x
    local length = maxDim.y - minDim.y
    local height = maxDim.z - minDim.z

    local dist = length * 0.85 + 2.5
    local midZ = minDim.z + height * 0.45
    local fov = 45.0

    local pos, look

    if focus == 'front' then
        pos = vec3(0.0, maxDim.y + dist * 0.75, midZ + height * 0.35)
        look = vec3(0.0, 0.0, midZ)
    elseif focus == 'rear' then
        pos = vec3(0.0, minDim.y - dist * 0.75, midZ + height * 0.35)
        look = vec3(0.0, 0.0, midZ)
    elseif focus == 'side' then
        pos = vec3(-(width * 0.5 + dist * 0.85), 0.0, midZ + height * 0.25)
        look = vec3(0.0, 0.0, midZ)
    elseif focus == 'wheel' then
        local axleY = maxDim.y * 0.62
        pos = vec3(minDim.x - 1.9, axleY + 0.9, minDim.z + 0.75)
        look = vec3(minDim.x + 0.1, axleY, minDim.z + 0.4)
        fov = 40.0
    elseif focus == 'engine' then
        pos = vec3(0.0, maxDim.y + 1.5, maxDim.z + 1.2)
        look = vec3(0.0, maxDim.y - 0.8, midZ + 0.1)
    else -- default: front-left three-quarter view
        pos = vec3(-dist * 0.72, dist * 0.78, maxDim.z + 0.5)
        look = vec3(0.0, 0.0, midZ)
    end

    return pos, look, fov
end

local function setHood(open)
    if not state then return end
    if open == state.hoodOpen then return end

    state.hoodOpen = open

    if open then
        SetVehicleDoorOpen(state.vehicle, 4, false, false)
    else
        SetVehicleDoorShut(state.vehicle, 4, false)
    end
end

local function setCamera(focus, instant)
    if not state or not CAMERA_FOCUS[focus] then return end

    local vehicle = state.vehicle
    local pos, look, fov = cameraPreset(vehicle, focus)
    local world = GetOffsetFromEntityInWorldCoords(vehicle, pos.x, pos.y, pos.z)

    local cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', world.x, world.y, world.z, 0.0, 0.0, 0.0, fov, false, 2)
    PointCamAtEntity(cam, vehicle, look.x, look.y, look.z, true)

    local previous = state.cam
    state.cams[#state.cams + 1] = cam
    state.cam = cam

    if previous then
        -- Smoothly fly from the previous preset to the new one
        SetCamActiveWithInterp(cam, previous, 700, 1, 1)

        SetTimeout(900, function()
            if previous and DoesCamExist(previous) then
                -- Only destroy it if it is not the active one any more
                if not state or state.cam ~= previous then
                    DestroyCam(previous, false)
                end
            end
        end)
    else
        SetCamActive(cam, true)
        RenderScriptCams(true, not instant, instant and 0 or 900, true, false)
    end

    -- Open the hood for the engine view, close it again for every other view
    setHood(focus == 'engine')
end

-- ---------------------------------------------------------------------------
-- Closing
-- ---------------------------------------------------------------------------

function Tuning.IsOpen()
    return state ~= nil
end

---Close the tuning screen. `revert` restores the vehicle to the props it had when it was opened.
---@param revert boolean
function Tuning.Close(revert)
    if not state then return end

    local s = state
    state = nil -- stops the watch thread and blocks late NUI callbacks

    local exists = DoesEntityExist(s.vehicle)

    if exists then
        if revert then
            lib.setVehicleProperties(s.vehicle, s.original)
        end

        if s.hoodOpen then SetVehicleDoorShut(s.vehicle, 4, false) end
        if s.lightsForced then SetVehicleLights(s.vehicle, 0) end

        FreezeEntityPosition(s.vehicle, s.wasFrozen)
    end

    RenderScriptCams(false, true, 600, true, false)

    for i = 1, #s.cams do
        if DoesCamExist(s.cams[i]) then
            DestroyCam(s.cams[i], false)
        end
    end

    SendNUIMessage({ action = 'closeTuning', data = {} })

    if not (Billing and Billing.IsOpen and Billing.IsOpen()) then
        SetNuiFocus(false, false)
    end
end

-- ---------------------------------------------------------------------------
-- Opening
-- ---------------------------------------------------------------------------

local function vehicleLabel(vehicle)
    local name = GetDisplayNameFromVehicleModel(GetEntityModel(vehicle))
    local text = GetLabelText(name)

    if text and text ~= '' and text ~= 'NULL' then return text end
    return name
end

local function buildPerformance(vehicle, serverData)
    local list = {}
    local levels = serverData.owned and serverData.levels or {}

    for i = 1, #PERF_ORDER do
        local category = PERF_ORDER[i]
        local cfg = Config.Performance[category]
        local available = #cfg.levels

        if not cfg.toggle then
            available = math.min(available, GetNumVehicleMods(vehicle, cfg.modType))
        end

        if available > 0 then
            local options = { { level = 0, label = locale('ui_stock') } }

            for level = 1, available do
                local item = cfg.levels[level]

                options[#options + 1] = {
                    level = level,
                    label = cfg.toggle and cfg.label or locale('ui_level', level),
                    item = item,
                    hasItem = hasItem(item),
                }
            end

            local current = serverData.owned and (tonumber(levels[category]) or 0) or liveLevel(vehicle, cfg)

            list[#list + 1] = {
                id = category,
                label = cfg.label,
                current = math.tointeger(current) or 0,
                options = options,
            }
        end
    end

    return list
end

local function buildCosmetic(vehicle)
    local list = {}

    for i = 1, #Config.Cosmetic.mods do
        local cfg = Config.Cosmetic.mods[i]
        local count = GetNumVehicleMods(vehicle, cfg.modType)

        if count > 0 then
            local options = { { value = -1, label = locale('ui_stock') } }

            for index = 0, count - 1 do
                options[#options + 1] = {
                    value = index,
                    label = modOptionLabel(vehicle, cfg.modType, index, cfg.label),
                }
            end

            list[#list + 1] = {
                id = cfg.id,
                label = cfg.label,
                price = cfg.price,
                current = GetVehicleMod(vehicle, cfg.modType),
                options = options,
            }
        end
    end

    return list
end

local function buildPaint(vehicle)
    local color1, color2 = GetVehicleColours(vehicle)
    local pearl, wheel = GetVehicleExtraColours(vehicle)

    return {
        colours = Config.Colours,
        current = {
            color1 = color1,
            color2 = color2,
            pearlescentColor = pearl,
            wheelColor = wheel,
        },
        price = Config.Cosmetic.extras.paint.price,
    }
end

local function buildExtras(vehicle)
    local extras = Config.Cosmetic.extras

    -- Window tint
    local tints = {}
    for value = 0, math.max(GetNumVehicleWindowTints(), 1) - 1 do
        tints[#tints + 1] = { value = value, label = WINDOW_TINTS[value] or ('Tint %d'):format(value) }
    end

    -- Plate styles
    local plates = {}
    for value = 0, math.max(GetNumberOfVehicleNumberPlates(), 1) - 1 do
        plates[#plates + 1] = { value = value, label = PLATE_STYLES[value] or ('Plate %d'):format(value) }
    end

    -- Xenon
    local xenonColour = GetVehicleXenonLightsColor(vehicle)
    if xenonColour < 0 or xenonColour > 12 then xenonColour = XENON_DEFAULT end

    -- Neon
    local nr, ng, nb = GetVehicleNeonLightsColour(vehicle)

    return {
        windowTint = {
            current = math.max(GetVehicleWindowTint(vehicle), 0),
            price = extras.windowTint.price,
            options = tints,
        },
        xenon = {
            enabled = IsToggleModOn(vehicle, 22) == true,
            colour = xenonColour,
            price = extras.xenon.price,
        },
        neon = {
            enabled = {
                l = IsVehicleNeonLightEnabled(vehicle, 0) == true,
                r = IsVehicleNeonLightEnabled(vehicle, 1) == true,
                f = IsVehicleNeonLightEnabled(vehicle, 2) == true,
                b = IsVehicleNeonLightEnabled(vehicle, 3) == true,
            },
            colour = { r = nr, g = ng, b = nb },
            price = extras.neon.price,
        },
        plate = {
            current = GetVehicleNumberPlateTextIndex(vehicle),
            price = extras.plate.price,
            options = plates,
        },
    }
end

---Open the tuning screen on a vehicle (workshop only).
---@param vehicle integer
function Tuning.Open(vehicle)
    if state or opening or swapping or Anim.IsBusy() then return end
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end

    if not Mechanic.IsMechanic() then
        UI.Notify(locale('not_mechanic'), 'error')
        return
    end

    if not Mechanic.InWorkshop() then
        UI.Notify(locale('not_in_workshop'), 'error')
        return
    end

    if IsPedInAnyVehicle(cache.ped, false) or not NetworkGetEntityIsNetworked(vehicle) then
        UI.Notify(locale('busy'), 'error')
        return
    end

    opening = true

    CreateThread(function()
        local netId = NetworkGetNetworkIdFromEntity(vehicle)
        local ok, data = lib.callback.await('ap1le_mechanicjob:tuning:canOpen', false, netId)

        if not ok or type(data) ~= 'table' then
            UI.Notify(failText(data), 'error')
            opening = false
            return
        end

        if not DoesEntityExist(vehicle) or not Mechanic.RequestControl(vehicle) then
            UI.Notify(locale('error'), 'error')
            opening = false
            return
        end

        local original = lib.getVehicleProperties(vehicle)
        SetVehicleModKit(vehicle, 0)

        local plate = trim(GetVehicleNumberPlateText(vehicle))
        local owned = data.owned == true

        local payload = {
            vehicle = { label = vehicleLabel(vehicle), plate = plate, owned = owned },
            performance = buildPerformance(vehicle, { owned = owned, levels = data.levels }),
            cosmetic = buildCosmetic(vehicle),
            paint = buildPaint(vehicle),
            extras = buildExtras(vehicle),
        }

        state = {
            vehicle = vehicle,
            netId = netId,
            original = original,
            owned = owned,
            -- No native getter exists for the freeze state; vehicles are normally unfrozen in a workshop
            wasFrozen = false,
            cams = {},
            cam = nil,
            hoodOpen = false,
            lightsForced = false,
            installing = false,
        }
        opening = false

        FreezeEntityPosition(vehicle, true)
        setCamera('default', false)

        SetNuiFocus(true, true)
        SendNUIMessage({ action = 'openTuning', data = payload })

        -- Light watchdog: close if the mechanic dies, walks away, loses the job or the car disappears
        local session = state
        CreateThread(function()
            while state == session do
                Wait(500)

                if state ~= session then return end

                if not DoesEntityExist(session.vehicle)
                    or IsEntityDead(cache.ped)
                    or not Mechanic.IsMechanic()
                    or #(GetEntityCoords(cache.ped) - GetEntityCoords(session.vehicle)) > 15.0 then
                    Tuning.Close(true)
                    return
                end
            end
        end)
    end)
end

-- ---------------------------------------------------------------------------
-- NUI callbacks: preview, camera, close
-- ---------------------------------------------------------------------------

RegisterNUICallback('tuning:preview', function(data, cb)
    if not state or state.installing or type(data) ~= 'table' or type(data.id) ~= 'string' then
        cb({ ok = false })
        return
    end

    local cType = data.type
    if cType ~= 'mod' and cType ~= 'paint' and cType ~= 'extra' then
        cb({ ok = false })
        return
    end

    cb({ ok = applyChange(state.vehicle, cType, data.id, data.value) })
end)

RegisterNUICallback('tuning:camera', function(data, cb)
    local focus = type(data) == 'table' and data.focus

    if not state or not CAMERA_FOCUS[focus] then
        cb({ ok = false })
        return
    end

    setCamera(focus, false)
    cb({ ok = true })
end)

RegisterNUICallback('tuning:close', function(_, cb)
    Tuning.Close(true)
    cb({ ok = true })
end)

-- ---------------------------------------------------------------------------
-- Cosmetic install
-- ---------------------------------------------------------------------------

---Group the NUI changes into billing entries: one per mod / extra, one for all paint colours.
---Unchanged values (compared to the original props) and unknown ids are dropped.
local function buildEntries(changes, original)
    local entries, byKey = {}, {}

    for i = 1, math.min(#changes, MAX_CHANGES) do
        local change = changes[i]

        if type(change) == 'table' and type(change.id) == 'string' then
            local cType, id = change.type, change.id
            local entry

            if cType == 'mod' and cosmeticById[id] then
                local cfg = cosmeticById[id]
                entry = { key = 'mod:' .. id, anim = cfg.anim, price = cfg.price, label = cfg.label }
            elseif cType == 'paint' and (PAINT_KEYS[id] or id == 'paint') then
                local cfg = Config.Cosmetic.extras.paint
                entry = { key = 'paint', anim = cfg.anim, price = cfg.price, label = cfg.label }
            elseif cType == 'extra' and Config.Cosmetic.extras[id] and id ~= 'paint' then
                local cfg = Config.Cosmetic.extras[id]
                entry = { key = 'extra:' .. id, anim = cfg.anim, price = cfg.price, label = cfg.label }
            end

            if entry and ANIM_TYPES[entry.anim] then
                -- NUI may name the exact option (e.g. "Spoiler: Carbon"); the price always comes from config
                if cType == 'mod' and type(change.label) == 'string' and trim(change.label) ~= '' then
                    entry.label = trim(change.label)
                end

                local existing = byKey[entry.key]
                if not existing then
                    entry.items = {}
                    byKey[entry.key] = entry
                    entries[#entries + 1] = entry
                    existing = entry
                end

                -- Same mod/extra twice: last value wins; paint keeps one item per colour key
                local replaced = false
                for n = 1, #existing.items do
                    local item = existing.items[n]
                    if item.type == cType and item.id == id then
                        item.value = change.value
                        replaced = true
                        break
                    end
                end

                if not replaced then
                    existing.items[#existing.items + 1] = { type = cType, id = id, value = change.value }
                end
            end
        end
    end

    -- Drop everything that would not actually change the car
    local result = {}

    for i = 1, #entries do
        local entry = entries[i]
        local items = {}

        for n = 1, #entry.items do
            local item = entry.items[n]
            if not isUnchanged(original, item.type, item.id, item.value) then
                items[#items + 1] = item
            end
        end

        if #items > 0 then
            entry.items = items
            result[#result + 1] = entry
        end
    end

    return result
end

---Invoice lines from the installed entries. Overflow beyond Config.Invoice.maxLines is merged.
local function buildInvoiceLines(entries)
    local lines = {}

    for i = 1, #entries do
        local entry = entries[i]
        local amount = clamp(math.floor(tonumber(entry.price) or 0), 0, Config.Invoice.maxTotal)

        if amount > 0 then
            lines[#lines + 1] = { label = truncate(entry.label, 48), amount = amount }
        end
    end

    local maxLines = Config.Invoice.maxLines

    if #lines > maxLines then
        local last = lines[maxLines]
        local extra = #lines - maxLines

        for i = maxLines + 1, #lines do
            last.amount = last.amount + lines[i].amount
            lines[i] = nil
        end

        last.label = truncate(last.label, 40) .. (' +%d'):format(extra)
        last.amount = math.min(last.amount, Config.Invoice.maxTotal)
    end

    return lines
end

local function runInstall(session, changes)
    local vehicle = session.vehicle
    local entries = buildEntries(changes, session.original)

    -- Back to the original look: the parts only appear once their animation is done
    Tuning.Close(true)

    if #entries == 0 then return end

    if not DoesEntityExist(vehicle) or not Mechanic.RequestControl(vehicle) then
        UI.Notify(locale('error'), 'error')
        return
    end

    -- One animation per distinct anim type, in order of first appearance
    local order, groups = {}, {}
    for i = 1, #entries do
        local anim = entries[i].anim
        if not groups[anim] then
            groups[anim] = {}
            order[#order + 1] = anim
        end
        groups[anim][#groups[anim] + 1] = entries[i]
    end

    local applied = {}

    for i = 1, #order do
        local group = groups[order[i]]
        local labels = {}

        for n = 1, #group do labels[n] = group[n].label end
        UI.Notify(locale('tuning_installing', table.concat(labels, ', ')), 'inform')

        if not Anim.Cosmetic(vehicle, order[i], Config.Cosmetic.animTime) then
            UI.Notify(locale('cancelled'), 'inform')
            break
        end

        if not DoesEntityExist(vehicle) then return end

        for n = 1, #group do
            local entry = group[n]
            local ok = false

            for m = 1, #entry.items do
                local item = entry.items[m]
                if applyChange(vehicle, item.type, item.id, item.value) then ok = true end
            end

            if ok then applied[#applied + 1] = entry end
        end
    end

    if #applied == 0 then return end

    -- Persist (owned vehicles only; the server merges cosmetic keys)
    local props = lib.getVehicleProperties(vehicle)
    local saved, result = lib.callback.await('ap1le_mechanicjob:tuning:save', false, session.netId, props)

    if not saved then
        UI.Notify(failText(result), 'error')
    elseif type(result) == 'table' and result.saved == false then
        UI.Notify(locale('tuning_not_saved'), 'inform')
    else
        UI.Notify(locale('tuning_saved'), 'success')
    end

    local lines = buildInvoiceLines(applied)
    if #lines > 0 then
        Billing.OpenCreate(lines)
    end
end

RegisterNUICallback('tuning:install', function(data, cb)
    if not state or state.installing or type(data) ~= 'table' or type(data.changes) ~= 'table' or #data.changes == 0 then
        cb({ ok = false })
        return
    end

    local session = state
    session.installing = true

    cb({ ok = true })

    CreateThread(function()
        runInstall(session, data.changes)
    end)
end)

-- ---------------------------------------------------------------------------
-- Performance swap (contract section 7): take the old part OUT, then put the new one IN
-- ---------------------------------------------------------------------------

local function runSwap(vehicle, category, level)
    local cfg = Config.Performance[category]
    if not cfg or not DoesEntityExist(vehicle) then return end

    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    local ok, data = lib.callback.await('ap1le_mechanicjob:perf:begin', false, netId, category, level)

    if not ok or type(data) ~= 'table' then
        UI.Notify(failText(data), 'error')
        return
    end

    local function cancel()
        lib.callback.await('ap1le_mechanicjob:cancel', false)
    end

    if not Mechanic.RequestControl(vehicle) then
        cancel()
        UI.Notify(locale('error'), 'error')
        return
    end

    local oldLevel = math.tointeger(data.oldLevel) or 0
    local newLevel = math.tointeger(data.level) or level

    -- Step 1: old part out (engine: hood open, hoist, unbolt, lift out)
    if oldLevel > 0 then
        UI.Notify(locale('swap_removing', cfg.label), 'inform')

        if not Anim.Swap(vehicle, category, 'remove', data.removeTime) then
            cancel()
            UI.Notify(locale('cancelled'), 'inform')
            return
        end

        -- The old part is out: show the car without it
        setPerformanceMod(vehicle, cfg, 0)
    end

    -- Step 2: new part in (fetch, lift in, bolt down, close up)
    if newLevel > 0 then
        UI.Notify(locale('swap_installing', cfg.label), 'inform')

        if not Anim.Swap(vehicle, category, 'install', data.installTime) then
            cancel()
            setPerformanceMod(vehicle, cfg, oldLevel) -- the old part goes back on visually
            UI.Notify(locale('cancelled'), 'inform')
            return
        end
    end

    local finished, result = lib.callback.await('ap1le_mechanicjob:perf:finish', false)

    if not finished then
        setPerformanceMod(vehicle, cfg, oldLevel)
        UI.Notify(failText(result), 'error')
        return
    end

    local finalLevel = type(result) == 'table' and math.tointeger(result.level) or newLevel

    if DoesEntityExist(vehicle) then
        Mechanic.RequestControl(vehicle)
        setPerformanceMod(vehicle, cfg, finalLevel)
    end

    if finalLevel > 0 then
        local levelLabel = cfg.toggle and cfg.label or locale('ui_level', finalLevel)
        UI.Notify(locale('swap_done', cfg.label, levelLabel), 'success')
    else
        UI.Notify(locale('swap_removed', cfg.label), 'success')
    end
end

RegisterNUICallback('tuning:swap', function(data, cb)
    if not state or state.installing or swapping or type(data) ~= 'table' then
        cb({ ok = false })
        return
    end

    local category = data.category
    local cfg = type(category) == 'string' and Config.Performance[category]
    local level = toInt(data.level)

    if not cfg or not level or level < 0 or level > #cfg.levels then
        cb({ ok = false })
        return
    end

    local vehicle = state.vehicle
    swapping = true

    -- Discard any cosmetic preview, close the screen, then do the physical work
    Tuning.Close(true)
    cb({ ok = true })

    CreateThread(function()
        runSwap(vehicle, category, level)
        swapping = false
    end)
end)

-- ---------------------------------------------------------------------------
-- Cleanup
-- ---------------------------------------------------------------------------

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    if state then
        Tuning.Close(true)
    end

    -- Make sure no scripted camera survives the restart
    RenderScriptCams(false, false, 0, true, false)
end)
