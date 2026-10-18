-- ap1le_mechanicjob: tuning (client).
--  * Tuning screen: NUI + free orbit camera + local preview of cosmetic changes.
--  * Every cosmetic option GTA offers for the vehicle, grouped as Config.Cosmetic.groups / sub, plus
--    client-built sub-categories (wheel types, tyre smoke, neon, interior colours).
--  * Cosmetic install: one native animation per distinct anim type, apply, save, then invoice.
--  * Performance swap: the old part is physically taken OUT, then the new part is put IN. Parts come
--    from the workshop stash (server-checked); missing parts can be ordered from the menu.

Tuning = {}

-- Active tuning session (nil when closed). See Tuning.Open for the fields.
local state = nil
local opening = false
local swapping = false

-- ---------------------------------------------------------------------------
-- Static data
-- ---------------------------------------------------------------------------

local ANIM_TYPES = { body = true, under = true, interior = true, hood = true, paint = true, wheel = true }

local MAX_CHANGES = 80
local MAX_ORBIT_PX = 400
local MAX_ZOOM_DELTA = 3          -- wheel notches per tuning:zoom (the NUI sends at most +-3)

-- Vehicle classes without a mod shop (boats, helicopters, planes, trains)
local NO_TUNING_CLASS = { [14] = true, [15] = true, [16] = true, [21] = true }
local CLASS_OPEN_WHEEL = 22

-- eVehicleWheelType (citizenfx/natives GET_VEHICLE_WHEEL_TYPE). 11/12 need newer game builds; a
-- type is only offered when GetNumVehicleMods(23) > 0 after switching to it.
local WHEEL_TYPES = {
    { type = 0,  label = 'Sport' },
    { type = 1,  label = 'Muscle' },
    { type = 2,  label = 'Lowrider' },
    { type = 3,  label = 'SUV' },
    { type = 4,  label = 'Terræn' },
    { type = 5,  label = 'Tuner' },
    { type = 7,  label = 'Luksus' },
    { type = 8,  label = "Benny's Original" },
    { type = 9,  label = "Benny's Bespoke" },
    { type = 10, label = 'Formel (åbne hjul)' },
    { type = 11, label = 'Gade' },
    { type = 12, label = 'Bane' },
}
local WHEEL_TYPE_BIKE = 6
local WHEEL_TYPE_OPEN = 10

local wheelTypeLabel = { [WHEEL_TYPE_BIKE] = 'Motorcykel' }
for i = 1, #WHEEL_TYPES do wheelTypeLabel[WHEEL_TYPES[i].type] = WHEEL_TYPES[i].label end

-- Xenon: -1 = off (normal headlights), 255 = xenon with the default colour, 0..12 = colours.
-- Colours: citizenfx/natives _GET_VEHICLE_XENON_LIGHTS_COLOR, hex from DurtyFree vehicleColors.json.
local XENON_OFF = -1
local XENON_DEFAULT = 255
local XENON_OPTIONS = {
    { value = XENON_OFF,     label = 'Fra' },
    { value = XENON_DEFAULT, label = 'Standard', hex = '#F2F4FF' },
    { value = 0,  label = 'Hvid',          hex = '#DEDEFF' },
    { value = 1,  label = 'Blå',           hex = '#0215FF' },
    { value = 2,  label = 'Elektrisk blå', hex = '#0353FF' },
    { value = 3,  label = 'Mintgrøn',      hex = '#00FF8C' },
    { value = 4,  label = 'Limegrøn',      hex = '#5EFF01' },
    { value = 5,  label = 'Gul',           hex = '#FFFF00' },
    { value = 6,  label = 'Guldregn',      hex = '#FF9605' },
    { value = 7,  label = 'Orange',        hex = '#FF3E00' },
    { value = 8,  label = 'Rød',           hex = '#FF0101' },
    { value = 9,  label = 'Ponypink',      hex = '#FF3264' },
    { value = 10, label = 'Hot pink',      hex = '#FF05BE' },
    { value = 11, label = 'Lilla',         hex = '#2301FF' },
    { value = 12, label = 'Sort lys',      hex = '#0F03FF' },
}

-- Window tints (citizenfx/natives SET_VEHICLE_WINDOW_TINT), listed clearest to darkest
local WINDOW_TINT_ORDER = { 0, 4, 3, 2, 5, 1, 6 }
local WINDOW_TINT_LABELS = {
    [0] = 'Ingen', [1] = 'Helt sort', [2] = 'Mørk røg', [3] = 'Lys røg', [4] = 'Standard', [5] = 'Limousine', [6] = 'Grøn',
}

-- Plate styles (citizenfx/natives GET_VEHICLE_NUMBER_PLATE_TEXT_INDEX; 6+ need build 3095)
local PLATE_LABELS = {
    [0] = 'Blå på hvid 1', [1] = 'Gul på sort', [2] = 'Gul på blå', [3] = 'Blå på hvid 2', [4] = 'Blå på hvid 3',
    [5] = 'North Yankton', [6] = 'eCola', [7] = 'Las Venturas', [8] = 'Liberty City', [9] = 'LS Car Meet',
    [10] = 'LS Panic', [11] = 'LS Pounders', [12] = 'Sprunk',
}

-- Neon layout = bit mask of the four tubes (neon index 0 left, 1 right, 2 front, 3 back)
local NEON_BITS = { 1, 2, 4, 8 }
local NEON_LAYOUTS = {
    { value = 0,  label = 'Ingen' },
    { value = 4,  label = 'Front' },
    { value = 8,  label = 'Bag' },
    { value = 3,  label = 'Sider' },
    { value = 12, label = 'Front og bag' },
    { value = 7,  label = 'Front og sider' },
    { value = 11, label = 'Bag og sider' },
    { value = 15, label = 'Hele vejen rundt' },
}

-- Horns have no GetModTextLabel; the mod shop maps the horn's sound hash to a text key
-- (table from TomGrobbe/vMenu VehicleHornLabels.cs)
local HORN_SOUNDS = {
    INDEP_HORN_1 = 'HORN_INDI_1', INDEP_HORN_2 = 'HORN_INDI_2', INDEP_HORN_3 = 'HORN_INDI_3', INDEP_HORN_4 = 'HORN_INDI_4',
    HIPSTER_HORN_1 = 'HORN_HIPS1', HIPSTER_HORN_2 = 'HORN_HIPS2', HIPSTER_HORN_3 = 'HORN_HIPS3', HIPSTER_HORN_4 = 'HORN_HIPS4',
    DLC_BUSI2_C_MAJOR_NOTES_C0 = 'HORN_CNOTE_C0', DLC_BUSI2_C_MAJOR_NOTES_D0 = 'HORN_CNOTE_D0',
    DLC_BUSI2_C_MAJOR_NOTES_E0 = 'HORN_CNOTE_E0', DLC_BUSI2_C_MAJOR_NOTES_F0 = 'HORN_CNOTE_F0',
    DLC_BUSI2_C_MAJOR_NOTES_G0 = 'HORN_CNOTE_G0', DLC_BUSI2_C_MAJOR_NOTES_A0 = 'HORN_CNOTE_A0',
    DLC_BUSI2_C_MAJOR_NOTES_B0 = 'HORN_CNOTE_B0', DLC_BUSI2_C_MAJOR_NOTES_C1 = 'HORN_CNOTE_C1',
    MUSICAL_HORN_BUSINESS_1 = 'HORN_CLAS1', MUSICAL_HORN_BUSINESS_2 = 'HORN_CLAS2', MUSICAL_HORN_BUSINESS_3 = 'HORN_CLAS3',
    MUSICAL_HORN_BUSINESS_4 = 'HORN_CLAS4', MUSICAL_HORN_BUSINESS_5 = 'HORN_CLAS5', MUSICAL_HORN_BUSINESS_6 = 'HORN_CLAS6',
    MUSICAL_HORN_BUSINESS_7 = 'HORN_CLAS7',
    LUXE_HORN_2 = 'HORN_LUXE1', LUXE_HORN_1 = 'HORN_LUXE2', LUXE_HORN_3 = 'HORN_LUXE3',
    LOWRIDER_HORN_1 = 'HORN_LOWRDER1', LOWRIDER_HORN_2 = 'HORN_LOWRDER2',
    ORGAN_HORN_LOOP_01 = 'HORN_HWEEN1', ORGAN_HORN_LOOP_02 = 'HORN_HWEEN2',
    XM15_HORN_01 = 'HORN_XM15_1', XM15_HORN_02 = 'HORN_XM15_2', XM15_HORN_03 = 'HORN_XM15_3',
    HORN_CLOWN = 'CMOD_HRN_CLO', HORN_COP = 'CMOD_HRN_COP', HORN_TRUCK = 'CMOD_HRN_TRK',
    HORN_MUSICAL_1 = 'CMOD_HRN_MUS1', HORN_MUSICAL_2 = 'CMOD_HRN_MUS2', HORN_MUSICAL_3 = 'CMOD_HRN_MUS3',
    HORN_MUSICAL_4 = 'CMOD_HRN_MUS4', HORN_MUSICAL_5 = 'CMOD_HRN_MUS5', HORN_SAD_TROMBONE = 'CMOD_HRN_SAD',
    DLC_AW_AIRHORN_01 = 'CMOD_AIRHORN_01', DLC_AW_AIRHORN_02 = 'CMOD_AIRHORN_02', DLC_AW_AIRHORN_03 = 'CMOD_AIRHORN_03',
}
local hornTextByHash = nil

-- Extras (Config.Cosmetic.extras is a hash table): fixed build order
local EXTRA_ORDER = {
    'customTires', 'tyreSmoke', 'wheelColor', 'color1', 'color2', 'pearlescent', 'interiorColor', 'dashboardColor',
    'xenon', 'neon', 'plateIndex', 'oldLivery', 'windowTint',
}

-- Performance categories in a stable order (Config.Performance is a hash table)
local PERF_ORDER = {}
for category in pairs(Config.Performance) do
    PERF_ORDER[#PERF_ORDER + 1] = category
end
table.sort(PERF_ORDER, function(a, b)
    return Config.Performance[a].modType < Config.Performance[b].modType
end)

-- Item -> { category, level } for ordering labels
local PERF_ITEM = {}
for category, cfg in pairs(Config.Performance) do
    for level = 1, #cfg.levels do
        PERF_ITEM[cfg.levels[level]] = { category = category, level = level }
    end
end

local cosmeticById = {}
for i = 1, #Config.Cosmetic.mods do
    cosmeticById[Config.Cosmetic.mods[i].id] = Config.Cosmetic.mods[i]
end

local GAME_BUILD = GetGameBuildNumber()

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------

local function notify(msg, notifyType)
    Ap1le.Notify(msg, notifyType or 'info')
end

local function failText(err)
    if type(err) == 'string' and err ~= '' then return locale(err) end
    return locale('error')
end

local function trim(s)
    return (tostring(s or ''):gsub('^%s*(.-)%s*$', '%1'))
end

---Truncate to at most `max` UTF-8 characters.
local function truncate(s, max)
    local len = utf8.len(s)
    if len and len <= max then return s end
    local cut = utf8.offset(s, max + 1)
    return cut and s:sub(1, cut - 1) or s:sub(1, max)
end

---Integer from a number (or numeric string), nil otherwise.
local function toInt(v)
    local n = tonumber(v)
    if not n or n ~= n or n == math.huge or n == -math.huge then return nil end
    return math.floor(n)
end

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function toBool(v)
    if v == true or v == 1 then return true end
    if v == false or v == 0 then return false end
    return nil
end

---{ r, g, b } (0..255) from { r=, g=, b= } or { r, g, b }; nil when malformed.
local function toRgb(v)
    if type(v) ~= 'table' then return nil end
    local r, g, b = toInt(v.r or v[1]), toInt(v.g or v[2]), toInt(v.b or v[3])
    if not (r and g and b) then return nil end
    return { clamp(r, 0, 255), clamp(g, 0, 255), clamp(b, 0, 255) }
end

local function rgbEqual(a, b)
    a, b = toRgb(a), toRgb(b)
    if not a or not b then return false end
    return a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
end

local function rgbHex(v)
    local c = toRgb(v)
    if not c then return '' end
    return ('#%02X%02X%02X'):format(c[1], c[2], c[3])
end

---GXT text for a label key, or nil when the game has none.
local function gameText(key)
    if type(key) ~= 'string' or key == '' or key == 'NULL' then return nil end
    local text = GetLabelText(key)
    if text and text ~= '' and text ~= 'NULL' then return text end
    return nil
end

local function u32(n)
    n = math.tointeger(n)
    if not n then return nil end
    return n & 0xFFFFFFFF
end

local function hornLabel(vehicle, index)
    if not hornTextByHash then
        hornTextByHash = {}
        for sound, key in pairs(HORN_SOUNDS) do
            local hash = u32(GetHashKey(sound))
            if hash then hornTextByHash[hash] = key end
        end
    end

    local hash = u32(GetVehicleModIdentifierHash(vehicle, 14, index))
    return hash and gameText(hornTextByHash[hash]) or nil
end

---Label of a mod option; falls back to "<label> <n>" when GTA has no text for it.
local function modOptionLabel(vehicle, modType, index, fallbackLabel)
    local text

    if modType == 14 then
        text = hornLabel(vehicle, index)
    end

    text = text or gameText(GetModTextLabel(vehicle, modType, index))

    return text or ('%s %d'):format(fallbackLabel, index + 1)
end

local function vehicleLabel(vehicle)
    local name = GetDisplayNameFromVehicleModel(GetEntityModel(vehicle))
    return gameText(name) or name
end

---Colour index allowed for this game build (chameleon paints need build 2944+).
local function validColour(index)
    local colour = Colours.byIndex[index]
    if not colour then return false end
    if colour.group == 'chameleon' and GAME_BUILD < 2944 then return false end
    return true
end

local function neonMask(vehicle)
    local mask = 0
    for i = 0, 3 do
        if IsVehicleNeonLightEnabled(vehicle, i) then mask = mask | NEON_BITS[i + 1] end
    end
    return mask
end

local function neonMaskFromProps(enabled)
    local mask = 0
    if type(enabled) ~= 'table' then return 0 end
    for i = 1, 4 do
        if enabled[i] == true or enabled[i] == 1 then mask = mask | NEON_BITS[i] end
    end
    return mask
end

local function normaliseXenon(enabled, colour)
    if not enabled then return XENON_OFF end
    colour = toInt(colour)
    if not colour or colour < 0 or colour > 12 then return XENON_DEFAULT end
    return colour
end

local function normaliseTint(tint)
    tint = toInt(tint) or 0
    if tint < 0 then return 0 end
    return tint
end

local function priceOf(id)
    local prices = state and state.prices
    local price = prices and tonumber(prices[id])

    if not price then
        local cfg = cosmeticById[id] or Config.Cosmetic.extras[id]
        price = cfg and tonumber(cfg.price) or 0
    end

    return math.max(0, math.floor(price))
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

local function itemLabel(item)
    local perf = PERF_ITEM[item]
    if perf then
        local cfg = Config.Performance[perf.category]
        if cfg.toggle then return cfg.label end
        return ('%s %s'):format(cfg.label, locale('ui_level', perf.level))
    end

    local ok, data = pcall(function() return exports.ox_inventory:Items(item) end)
    if ok and type(data) == 'table' and type(data.label) == 'string' then return data.label end

    return item
end

-- ---------------------------------------------------------------------------
-- Node registry
-- Every node the NUI can preview is registered in state.nodes[id]:
--   { id, priceId, anim, label, order, apply(vehicle, value) -> bool,
--     unchanged(value, final, original) -> bool, valueLabel(value) -> string }
-- `order` sorts items inside one install animation (rims before custom tyres, colour before toggle).
-- ---------------------------------------------------------------------------

---Index option labels by value for a list/mod node.
local function optionLabels(options)
    local map = {}
    for i = 1, #options do map[options[i].value] = options[i].label end
    return map
end

local function colourLabel(index)
    return Colours.Label(index)
end

---Rim node: `wheelType` is switched to before the rim is fitted. modType 23 = front, 24 = rear (bikes).
local function rimNode(cfg, wheelType, modType, labels, count)
    local id = ('%s:%d'):format(cfg.id, wheelType)
    local typeLabel = wheelTypeLabel[wheelType] or tostring(wheelType)

    return {
        id = id,
        priceId = cfg.id,
        anim = cfg.anim,
        label = cfg.label,
        order = 1,
        rim = true,
        apply = function(veh, value)
            local index = toInt(value)
            if not index or index < -1 or index >= count then return false end

            SetVehicleModKit(veh, 0)
            if GetVehicleWheelType(veh) ~= wheelType then
                SetVehicleWheelType(veh, wheelType)
            end

            -- Keep the custom tyre state of the slot
            SetVehicleMod(veh, modType, index, GetVehicleModVariation(veh, modType))
            return true
        end,
        unchanged = function(value, _, original)
            local index = toInt(value)
            local key = modType == 24 and 'modBackWheels' or 'modFrontWheels'
            if index == -1 and original[key] == -1 then return true end
            return index == original[key] and (modType == 24 or original.wheels == wheelType)
        end,
        valueLabel = function(value)
            local index = toInt(value)
            local text = labels[index] or tostring(value)
            if modType == 24 then return text end
            return ('%s - %s'):format(typeLabel, text)
        end,
    }
end

-- ---------------------------------------------------------------------------
-- Payload (contract section 6) + registry
-- ---------------------------------------------------------------------------

local function buildPerformance(vehicle, data)
    local list = {}
    local levels = data.owned and type(data.levels) == 'table' and data.levels or {}
    local stock = type(data.stock) == 'table' and data.stock or {}

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
                    stock = math.max(0, toInt(stock[item]) or 0),
                    price = toInt(Config.Shop.items[item]) or 0,
                }
            end

            local current = data.owned and (toInt(levels[category]) or 0) or liveLevel(vehicle, cfg)

            list[#list + 1] = {
                type = 'performance',
                id = category,
                label = cfg.label,
                current = clamp(current, 0, available),
                options = options,
            }
        end
    end

    return list
end

---Builds the cosmetic groups. Fills `nodes` (registry) and returns { [groupId] = { node, ... } }.
local function buildCosmetic(vehicle, nodes)
    local model = GetEntityModel(vehicle)
    local isBike = IsThisModelABike(model)
    local class = GetVehicleClass(vehicle)
    local colourGroups = Colours.GroupsForBuild(GAME_BUILD)
    local extras = Config.Cosmetic.extras

    local byGroup = {}
    local subIndex = {}

    local function groupList(groupId)
        local list = byGroup[groupId]
        if not list then
            list = {}
            byGroup[groupId] = list
        end
        return list
    end

    ---Add a NUI node (and its registry entry) to a group, optionally inside a sub-category.
    local function add(groupId, sub, node, entry)
        local list = groupList(groupId)

        if sub then
            local key = groupId .. '\0' .. sub
            local subNode = subIndex[key]
            if not subNode then
                subNode = { type = 'sub', id = ('sub:%s:%s'):format(groupId, sub), label = sub, items = {} }
                subIndex[key] = subNode
                list[#list + 1] = subNode
            end
            list = subNode.items
        end

        list[#list + 1] = node
        if entry then nodes[entry.id] = entry end
    end

    -- Standard mod slots -------------------------------------------------------

    local function addMod(cfg)
        local count = GetNumVehicleMods(vehicle, cfg.modType)
        if count <= 0 then return end

        local options = { { value = -1, label = locale('ui_stock') } }
        for index = 0, count - 1 do
            options[#options + 1] = { value = index, label = modOptionLabel(vehicle, cfg.modType, index, cfg.label) }
        end
        local labels = optionLabels(options)

        add(cfg.group, cfg.sub, {
            type = 'mod', id = cfg.id, label = cfg.label, price = priceOf(cfg.id), priceId = cfg.id,
            current = GetVehicleMod(vehicle, cfg.modType), options = options,
        }, {
            id = cfg.id, priceId = cfg.id, anim = cfg.anim, label = cfg.label, order = 1,
            apply = function(veh, value)
                local index = toInt(value)
                if not index or index < -1 or index >= count then return false end
                SetVehicleModKit(veh, 0)
                SetVehicleMod(veh, cfg.modType, index, false)
                return true
            end,
            unchanged = function(value, _, original) return toInt(value) == original[cfg.id] end,
            valueLabel = function(value) return labels[toInt(value)] or tostring(value) end,
        })
    end

    -- Wheels: rims per wheel type ------------------------------------------------

    local function addRims(cfg)
        if class == 13 then return end -- bicycles have no wheel mods

        local originalType = GetVehicleWheelType(vehicle)
        local originalMod = GetVehicleMod(vehicle, 23)
        local originalVariation = GetVehicleModVariation(vehicle, 23)

        local types = {}
        if isBike then
            types[1] = WHEEL_TYPE_BIKE
        elseif class == CLASS_OPEN_WHEEL then
            types[1] = WHEEL_TYPE_OPEN
        else
            for i = 1, #WHEEL_TYPES do
                if WHEEL_TYPES[i].type ~= WHEEL_TYPE_OPEN then types[#types + 1] = WHEEL_TYPES[i].type end
            end
        end

        -- Count and label the rims of every type (all in this frame, nothing is rendered in between)
        local found = {}
        for i = 1, #types do
            local wheelType = types[i]
            SetVehicleWheelType(vehicle, wheelType)

            local count = GetNumVehicleMods(vehicle, 23)
            if count > 0 then
                local options = { { value = -1, label = locale('ui_stock') } }
                for index = 0, count - 1 do
                    options[#options + 1] = {
                        value = index,
                        label = modOptionLabel(vehicle, 23, index, wheelTypeLabel[wheelType] or cfg.label),
                    }
                end
                found[#found + 1] = { wheelType = wheelType, count = count, options = options }
            end
        end

        SetVehicleWheelType(vehicle, originalType)
        SetVehicleMod(vehicle, 23, originalMod, originalVariation)

        if #found == 0 then return end

        for i = 1, #found do
            local f = found[i]
            local entry = rimNode(cfg, f.wheelType, 23, optionLabels(f.options), f.count)
            local node = {
                type = 'mod', id = entry.id, label = isBike and cfg.label or (wheelTypeLabel[f.wheelType] or cfg.label),
                price = priceOf(cfg.id), priceId = cfg.id, wheelType = f.wheelType, options = f.options,
                -- current only on the type the vehicle has now (others: none of their rims is fitted)
                current = f.wheelType == originalType and originalMod or nil,
            }

            -- Cars: one sub-category "Fælge" with a list per wheel type. Bikes: the rims directly.
            add(cfg.group, not isBike and cfg.label or nil, node, entry)
        end
    end

    local function addBackRims(cfg)
        if not isBike then return end

        local count = GetNumVehicleMods(vehicle, 24)
        if count <= 0 then return end

        local options = { { value = -1, label = locale('ui_stock') } }
        for index = 0, count - 1 do
            options[#options + 1] = { value = index, label = modOptionLabel(vehicle, 24, index, cfg.label) }
        end

        local entry = rimNode(cfg, WHEEL_TYPE_BIKE, 24, optionLabels(options), count)
        add(cfg.group, nil, {
            type = 'mod', id = entry.id, label = cfg.label, price = priceOf(cfg.id), priceId = cfg.id,
            wheelType = WHEEL_TYPE_BIKE, current = GetVehicleMod(vehicle, 24), options = options,
        }, entry)
    end

    for i = 1, #Config.Cosmetic.mods do
        local cfg = Config.Cosmetic.mods[i]

        if cfg.modType == 23 then
            addRims(cfg)
        elseif cfg.modType == 24 then
            addBackRims(cfg)
        else
            addMod(cfg)
        end
    end

    -- Extras -------------------------------------------------------------------

    local function colourNode(id, sub, current, apply, unchanged)
        local cfg = extras[id]
        if not cfg then return end

        add(cfg.group, sub, {
            type = 'colour', id = id, label = cfg.label, price = priceOf(id), priceId = id,
            current = current, groups = colourGroups,
        }, {
            id = id, priceId = id, anim = cfg.anim, label = cfg.label, order = 1,
            apply = function(veh, value)
                local index = toInt(value)
                if not index or not validColour(index) then return false end
                apply(veh, index)
                return true
            end,
            unchanged = function(value, _, original) return unchanged(toInt(value), original) end,
            valueLabel = function(value) return colourLabel(toInt(value)) end,
        })
    end

    local builders = {}

    builders.customTires = function(cfg)
        if class == 13 or (GetNumVehicleMods(vehicle, 23) <= 0 and not isBike) then return end

        add(cfg.group, nil, {
            type = 'toggle', id = 'customTires', label = cfg.label, price = priceOf('customTires'), priceId = 'customTires',
            current = GetVehicleModVariation(vehicle, 23) == true,
        }, {
            id = 'customTires', priceId = 'customTires', anim = cfg.anim, label = cfg.label, order = 2,
            apply = function(veh, value)
                local on = toBool(value)
                if on == nil then return false end
                SetVehicleModKit(veh, 0)
                SetVehicleMod(veh, 23, GetVehicleMod(veh, 23), on)
                if IsThisModelABike(GetEntityModel(veh)) then
                    SetVehicleMod(veh, 24, GetVehicleMod(veh, 24), on)
                end
                return true
            end,
            unchanged = function(value, _, original) return toBool(value) == (original.modCustomTiresF == true) end,
            valueLabel = function(value) return toBool(value) and locale('tuning_on') or locale('tuning_off') end,
        })
    end

    builders.tyreSmoke = function(cfg)
        if class == 13 then return end

        local r, g, b = GetVehicleTyreSmokeColor(vehicle)

        -- Toggle and colour share one price and one invoice line
        add(cfg.group, cfg.label, {
            type = 'toggle', id = 'tyreSmoke', label = cfg.label, price = priceOf('tyreSmoke'), priceId = 'tyreSmoke',
            current = IsToggleModOn(vehicle, 20) == true,
        }, {
            id = 'tyreSmoke', priceId = 'tyreSmoke', anim = cfg.anim, label = cfg.label, order = 3,
            apply = function(veh, value)
                local on = toBool(value)
                if on == nil then return false end
                SetVehicleModKit(veh, 0)
                ToggleVehicleMod(veh, 20, on)
                return true
            end,
            unchanged = function(value, _, original) return toBool(value) == (original.modSmokeEnabled == true) end,
            valueLabel = function(value) return toBool(value) and locale('tuning_on') or locale('tuning_off') end,
        })

        add(cfg.group, cfg.label, {
            type = 'rgb', id = 'tyreSmokeColor', label = locale('tuning_smoke_colour'), price = priceOf('tyreSmoke'),
            priceId = 'tyreSmoke', current = { r = r, g = g, b = b },
        }, {
            id = 'tyreSmokeColor', priceId = 'tyreSmoke', anim = cfg.anim, label = cfg.label, order = 2,
            apply = function(veh, value, ctx)
                local c = toRgb(value)
                if not c then return false end
                SetVehicleModKit(veh, 0)
                -- Picking a smoke colour turns tyre smoke on, unless it was switched off on purpose
                if not (ctx and toBool(ctx.tyreSmoke) == false) then ToggleVehicleMod(veh, 20, true) end
                SetVehicleTyreSmokeColor(veh, c[1], c[2], c[3])
                return true
            end,
            unchanged = function(value, final, original)
                local smokeOn = final.tyreSmoke
                if smokeOn == nil then smokeOn = true end -- a colour change switches it on
                if not smokeOn and not original.modSmokeEnabled then return true end
                return original.modSmokeEnabled == true and rgbEqual(value, original.tyreSmokeColor)
            end,
            valueLabel = function(value) return rgbHex(value) end,
        })
    end

    builders.wheelColor = function()
        if class == 13 then return end
        local _, wheel = GetVehicleExtraColours(vehicle)
        colourNode('wheelColor', nil, wheel, function(veh, index)
            local p = GetVehicleExtraColours(veh)
            SetVehicleExtraColours(veh, p, index)
        end, function(index, original) return index == original.wheelColor end)
    end

    builders.color1 = function()
        local c1 = GetVehicleColours(vehicle)
        colourNode('color1', nil, c1, function(veh, index)
            local _, c2 = GetVehicleColours(veh)
            ClearVehicleCustomPrimaryColour(veh)
            SetVehicleColours(veh, index, c2)
        end, function(index, original)
            return type(original.color1) == 'number' and index == original.color1
        end)
    end

    builders.color2 = function()
        local _, c2 = GetVehicleColours(vehicle)
        colourNode('color2', nil, c2, function(veh, index)
            local c1 = GetVehicleColours(veh)
            ClearVehicleCustomSecondaryColour(veh)
            SetVehicleColours(veh, c1, index)
        end, function(index, original)
            return type(original.color2) == 'number' and index == original.color2
        end)
    end

    builders.pearlescent = function()
        local pearl = GetVehicleExtraColours(vehicle)
        colourNode('pearlescent', nil, pearl, function(veh, index)
            local _, w = GetVehicleExtraColours(veh)
            SetVehicleExtraColours(veh, index, w)
        end, function(index, original) return index == original.pearlescentColor end)
    end

    builders.interiorColor = function()
        if isBike then return end
        colourNode('interiorColor', locale('tuning_colours'), GetVehicleInteriorColor(vehicle), function(veh, index)
            SetVehicleInteriorColor(veh, index)
        end, function(index, original) return index == original.interiorColor end)
    end

    builders.dashboardColor = function()
        if isBike then return end
        colourNode('dashboardColor', locale('tuning_colours'), GetVehicleDashboardColor(vehicle), function(veh, index)
            SetVehicleDashboardColor(veh, index)
        end, function(index, original) return index == original.dashboardColor end)
    end

    builders.xenon = function(cfg)
        local current = normaliseXenon(IsToggleModOn(vehicle, 22), GetVehicleXenonLightsColor(vehicle))
        local values = {}
        for i = 1, #XENON_OPTIONS do values[XENON_OPTIONS[i].value] = XENON_OPTIONS[i].label end

        add(cfg.group, nil, {
            type = 'list', id = 'xenon', label = cfg.label, price = priceOf('xenon'), priceId = 'xenon',
            current = current, options = XENON_OPTIONS,
        }, {
            id = 'xenon', priceId = 'xenon', anim = cfg.anim, label = cfg.label, order = 1,
            apply = function(veh, value)
                local v = toInt(value)
                if not v or not values[v] then return false end
                SetVehicleModKit(veh, 0)
                ToggleVehicleMod(veh, 22, v ~= XENON_OFF)
                if v ~= XENON_OFF then
                    SetVehicleXenonLightsColor(veh, v)
                    -- Xenon is only visible with the lights on (preview only, restored on close)
                    if state and state.vehicle == veh and not state.lightsForced then
                        state.lightsForced = true
                        SetVehicleLights(veh, 2)
                    end
                end
                return true
            end,
            unchanged = function(value, _, original)
                return toInt(value) == normaliseXenon(original.modXenon, original.xenonColor)
            end,
            valueLabel = function(value) return values[toInt(value)] or tostring(value) end,
        })
    end

    builders.neon = function(cfg)
        if isBike or class == 13 then return end

        local mask = neonMask(vehicle)
        local options = NEON_LAYOUTS
        local known = false
        for i = 1, #NEON_LAYOUTS do
            if NEON_LAYOUTS[i].value == mask then known = true break end
        end
        if not known then
            -- An odd layout (e.g. one side only) stays selectable as the current one
            options = { { value = mask, label = locale('tuning_neon_current') } }
            for i = 1, #NEON_LAYOUTS do options[#options + 1] = NEON_LAYOUTS[i] end
        end
        local labels = optionLabels(options)

        local r, g, b = GetVehicleNeonLightsColour(vehicle)

        add(cfg.group, cfg.label, {
            type = 'list', id = 'neonLayout', label = locale('tuning_neon_layout'), price = priceOf('neon'), priceId = 'neon',
            current = mask, options = options,
        }, {
            id = 'neonLayout', priceId = 'neon', anim = cfg.anim, label = cfg.label, order = 1,
            apply = function(veh, value)
                local v = toInt(value)
                if not v or not labels[v] then return false end
                for i = 0, 3 do
                    SetVehicleNeonLightEnabled(veh, i, v & NEON_BITS[i + 1] ~= 0)
                end
                return true
            end,
            unchanged = function(value, _, original) return toInt(value) == neonMaskFromProps(original.neonEnabled) end,
            valueLabel = function(value) return labels[toInt(value)] or tostring(value) end,
        })

        add(cfg.group, cfg.label, {
            type = 'rgb', id = 'neonColor', label = locale('tuning_neon_colour'), price = priceOf('neon'), priceId = 'neon',
            current = { r = r, g = g, b = b },
        }, {
            id = 'neonColor', priceId = 'neon', anim = cfg.anim, label = cfg.label, order = 2,
            apply = function(veh, value)
                local c = toRgb(value)
                if not c then return false end
                SetVehicleNeonLightsColour(veh, c[1], c[2], c[3])
                return true
            end,
            unchanged = function(value, final, original)
                local layout = final.neonLayout
                if layout == nil then layout = neonMaskFromProps(original.neonEnabled) end
                if toInt(layout) == 0 then return true end
                return rgbEqual(value, original.neonColor)
            end,
            valueLabel = function(value) return rgbHex(value) end,
        })
    end

    builders.windowTint = function(cfg)
        if isBike then return end

        local count = GetNumVehicleWindowTints()
        if count <= 0 then return end

        local options, values = {}, {}
        for i = 1, #WINDOW_TINT_ORDER do
            local v = WINDOW_TINT_ORDER[i]
            if v < count then
                options[#options + 1] = { value = v, label = WINDOW_TINT_LABELS[v] }
                values[v] = WINDOW_TINT_LABELS[v]
            end
        end
        for v = #WINDOW_TINT_ORDER, count - 1 do
            options[#options + 1] = { value = v, label = ('%s %d'):format(cfg.label, v) }
            values[v] = options[#options].label
        end

        add(cfg.group, nil, {
            type = 'list', id = 'windowTint', label = cfg.label, price = priceOf('windowTint'), priceId = 'windowTint',
            current = normaliseTint(GetVehicleWindowTint(vehicle)), options = options,
        }, {
            id = 'windowTint', priceId = 'windowTint', anim = cfg.anim, label = cfg.label, order = 1,
            apply = function(veh, value)
                local v = toInt(value)
                if not v or not values[v] then return false end
                SetVehicleWindowTint(veh, v)
                return true
            end,
            unchanged = function(value, _, original) return normaliseTint(value) == normaliseTint(original.windowTint) end,
            valueLabel = function(value) return values[toInt(value)] or tostring(value) end,
        })
    end

    builders.plateIndex = function(cfg)
        local count = GetNumberOfVehicleNumberPlates()
        if count <= 0 then return end

        local options, values = {}, {}
        for v = 0, count - 1 do
            local label = PLATE_LABELS[v] or ('%s %d'):format(cfg.label, v + 1)
            options[#options + 1] = { value = v, label = label }
            values[v] = label
        end

        add(cfg.group, nil, {
            type = 'list', id = 'plateIndex', label = cfg.label, price = priceOf('plateIndex'), priceId = 'plateIndex',
            current = GetVehicleNumberPlateTextIndex(vehicle), options = options,
        }, {
            id = 'plateIndex', priceId = 'plateIndex', anim = cfg.anim, label = cfg.label, order = 1,
            apply = function(veh, value)
                local v = toInt(value)
                if not v or not values[v] then return false end
                SetVehicleNumberPlateTextIndex(veh, v)
                return true
            end,
            unchanged = function(value, _, original) return toInt(value) == original.plateIndex end,
            valueLabel = function(value) return values[toInt(value)] or tostring(value) end,
        })
    end

    builders.oldLivery = function(cfg)
        local count = GetVehicleLiveryCount(vehicle)
        if not count or count <= 0 then return end

        local options, values = {}, {}
        for v = 0, count - 1 do
            local label = gameText(GetLiveryName(vehicle, v)) or ('%s %d'):format(cfg.label, v + 1)
            options[#options + 1] = { value = v, label = label }
            values[v] = label
        end

        add(cfg.group, nil, {
            type = 'list', id = 'oldLivery', label = cfg.label, price = priceOf('oldLivery'), priceId = 'oldLivery',
            current = GetVehicleLivery(vehicle), options = options,
        }, {
            id = 'oldLivery', priceId = 'oldLivery', anim = cfg.anim, label = cfg.label, order = 1,
            apply = function(veh, value)
                local v = toInt(value)
                if not v or not values[v] then return false end
                SetVehicleLivery(veh, v)
                return true
            end,
            unchanged = function(value, _, original) return toInt(value) == original.livery end,
            valueLabel = function(value) return values[toInt(value)] or tostring(value) end,
        })
    end

    for i = 1, #EXTRA_ORDER do
        local id = EXTRA_ORDER[i]
        local cfg = extras[id]
        local build = builders[id]

        if cfg and build then build(cfg) end
    end

    return byGroup
end

---Full openTuning payload + registry.
local function buildPayload(vehicle, data, nodes)
    local groups = {}

    local performance = buildPerformance(vehicle, data)
    if #performance > 0 then
        groups[1] = { id = 'performance', label = locale('ui_performance'), icon = 'gauge-high', items = performance }
    end

    local byGroup = buildCosmetic(vehicle, nodes)

    for i = 1, #Config.Cosmetic.groups do
        local g = Config.Cosmetic.groups[i]
        local items = byGroup[g.id]

        if items and #items > 0 then
            groups[#groups + 1] = { id = g.id, label = g.label, icon = g.icon, items = items }
        end
    end

    return {
        vehicle = { label = vehicleLabel(vehicle), plate = trim(GetVehicleNumberPlateText(vehicle)), owned = data.owned == true },
        groups = groups,
    }
end

-- ---------------------------------------------------------------------------
-- Orbit camera
-- Yaw/pitch/radius around a focus point given in vehicle-local coordinates. Yaw 0 = in front of
-- the car (+Y), 90 = right side (+X), 180 = behind. Presets ease to their targets; dragging and the
-- wheel change the targets. The camera never goes inside the car's bounding box (pushed out along
-- the view ray), below the floor or through walls (LOS probe).
-- ---------------------------------------------------------------------------

local PITCH_MIN, PITCH_MAX = -10.0, 60.0
local ORBIT_DEG_PER_PX = 0.3
local PITCH_DEG_PER_PX = 0.22
local ZOOM_M_PER_UNIT = 0.35     -- metres per wheel notch
local BOX_MARGIN = 0.25
local EASE_RATE = 9.0

local function dims(vehicle)
    local min, max = GetModelDimensions(GetEntityModel(vehicle))
    local halfW = (max.x - min.x) * 0.5
    local halfL = (max.y - min.y) * 0.5
    local height = max.z - min.z
    local hull = math.sqrt(halfW * halfW + halfL * halfL)

    return {
        min = min,
        max = max,
        height = height,
        halfW = halfW,
        centre = vec3((min.x + max.x) * 0.5, (min.y + max.y) * 0.5, min.z + height * 0.45),
        base = hull * 1.25 + 2.6,
        minR = 1.2,
        maxR = hull * 2.6 + 4.0,
    }
end

---Vehicle-local position of a wheel bone, or a guess from the model dimensions.
local function wheelOffset(vehicle, d)
    local bone = GetEntityBoneIndexByName(vehicle, 'wheel_lf')
    if bone and bone ~= -1 then
        local world = GetWorldPositionOfEntityBone(vehicle, bone)
        local localPos = GetOffsetFromEntityGivenWorldCoords(vehicle, world.x, world.y, world.z)
        return vec3(localPos.x - 0.1, localPos.y, localPos.z)
    end
    return vec3(d.min.x + 0.15, d.max.y * 0.62, d.min.z + 0.4)
end

-- doors: door indices opened for the preset (4 hood, 5 trunk, 0 driver)
local function cameraPreset(vehicle, d, focus)
    local c = d.centre

    if focus == 'front' then
        return { offset = c, yaw = 0.0, pitch = 12.0, radius = d.base * 0.95, fov = 45.0 }
    elseif focus == 'rear' then
        return { offset = c, yaw = 180.0, pitch = 12.0, radius = d.base * 0.95, fov = 45.0 }
    elseif focus == 'side' then
        return { offset = c, yaw = -90.0, pitch = 6.0, radius = d.base * 0.95, fov = 45.0 }
    elseif focus == 'top' then
        return { offset = c, yaw = -30.0, pitch = 55.0, radius = d.base * 1.1, fov = 45.0 }
    elseif focus == 'wheel' then
        return { offset = wheelOffset(vehicle, d), yaw = -70.0, pitch = 4.0, radius = 2.2, fov = 40.0 }
    elseif focus == 'engine' then
        return { offset = vec3(0.0, d.max.y - 0.9, c.z + 0.15), yaw = 0.0, pitch = 38.0, radius = 2.8, fov = 45.0, doors = { 4 } }
    elseif focus == 'interior' then
        return { offset = vec3(0.0, c.y + 0.1, d.min.z + d.height * 0.6), yaw = -90.0, pitch = 22.0, radius = d.halfW + 1.4, fov = 50.0, doors = { 0 } }
    elseif focus == 'trunk' then
        return { offset = vec3(0.0, d.min.y + 0.6, c.z + 0.2), yaw = 180.0, pitch = 30.0, radius = 2.6, fov = 45.0, doors = { 5 } }
    elseif focus == 'plate' then
        return { offset = vec3(0.0, d.min.y + 0.1, d.min.z + 0.5), yaw = 180.0, pitch = 8.0, radius = 2.0, fov = 40.0 }
    end

    -- default: front-left three-quarter view
    return { offset = c, yaw = -45.0, pitch = 15.0, radius = d.base, fov = 45.0 }
end

local CAMERA_FOCUS = {
    default = true, front = true, rear = true, side = true, top = true, wheel = true,
    engine = true, interior = true, trunk = true, plate = true,
}

local function angleDiff(target, current)
    return (target - current + 180.0) % 360.0 - 180.0
end

local function direction(yaw, pitch)
    local y, p = math.rad(yaw), math.rad(pitch)
    local cp = math.cos(p)
    return vec3(math.sin(y) * cp, math.cos(y) * cp, math.sin(p))
end

---Distance along the ray (origin + dir * t) where it leaves the (expanded) vehicle box, or 0 when
---the camera at `radius` is not inside the box.
local function boxPushOut(d, origin, dir, radius)
    local lo = d.min - vec3(BOX_MARGIN, BOX_MARGIN, BOX_MARGIN)
    local hi = d.max + vec3(BOX_MARGIN, BOX_MARGIN, BOX_MARGIN)
    local tmin, tmax = -math.huge, math.huge

    for _, axis in ipairs({ 'x', 'y', 'z' }) do
        local o, v = origin[axis], dir[axis]
        if math.abs(v) < 1e-6 then
            if o < lo[axis] or o > hi[axis] then return 0 end
        else
            local t1, t2 = (lo[axis] - o) / v, (hi[axis] - o) / v
            if t1 > t2 then t1, t2 = t2, t1 end
            if t1 > tmin then tmin = t1 end
            if t2 < tmax then tmax = t2 end
        end
    end

    if tmax < tmin or tmax <= 0 then return 0 end
    if radius > tmin and radius < tmax then return tmax end
    return 0
end

---World camera position and focus for the current orbit values.
local function cameraWorld(vehicle, cam)
    local d = cam.dims
    local dir = direction(cam.yaw, cam.pitch)
    local radius = cam.radius

    local pushed = boxPushOut(d, cam.offset, dir, radius)
    if pushed > 0 then radius = pushed + 0.05 end

    local localPos = cam.offset + dir * radius
    local focus = GetOffsetFromEntityInWorldCoords(vehicle, cam.offset.x, cam.offset.y, cam.offset.z)
    local pos = GetOffsetFromEntityInWorldCoords(vehicle, localPos.x, localPos.y, localPos.z)

    -- Floor
    local found, groundZ = GetGroundZFor_3dCoord(pos.x, pos.y, pos.z + 1.0, false)
    if found and pos.z < groundZ + 0.3 then
        pos = vec3(pos.x, pos.y, groundZ + 0.3)
    end

    -- Walls and props between the focus point and the camera (the vehicle itself is ignored)
    local probe = StartExpensiveSynchronousShapeTestLosProbe(focus.x, focus.y, focus.z, pos.x, pos.y, pos.z, 1 | 16, vehicle, 7)
    local status, hit, hitPos = GetShapeTestResult(probe)
    if status == 2 and (hit == true or hit == 1) and hitPos then
        local toHit = #(hitPos - focus)
        -- Never pull the camera back inside the car
        if toHit > (pushed > 0 and pushed or 0.6) then
            local back = pos - focus
            local len = #back
            if len > 0.001 then
                pos = focus + back / len * math.max(0.4, toHit - 0.25)
            end
        end
    end

    return pos, focus
end

local function setDoors(open)
    if not state then return end

    local wanted = {}
    for i = 1, #(open or {}) do wanted[open[i]] = true end

    for door in pairs(state.doorsOpen) do
        if not wanted[door] then
            SetVehicleDoorShut(state.vehicle, door, false)
            state.doorsOpen[door] = nil
        end
    end

    for door in pairs(wanted) do
        if not state.doorsOpen[door] then
            SetVehicleDoorOpen(state.vehicle, door, false, false)
            state.doorsOpen[door] = true
        end
    end
end

---Ease the camera to a preset (instant = jump, used when opening).
local function applyPreset(focus, instant)
    if not state or not state.cam then return end

    local cam = state.cam
    local preset = cameraPreset(state.vehicle, cam.dims, focus)

    cam.focus = focus
    cam.target = {
        offset = preset.offset,
        yaw = preset.yaw,
        pitch = clamp(preset.pitch, PITCH_MIN, PITCH_MAX),
        radius = clamp(preset.radius, cam.dims.minR, cam.dims.maxR),
        fov = preset.fov,
    }

    if instant then
        cam.offset, cam.yaw, cam.pitch, cam.radius, cam.fov =
            cam.target.offset, cam.target.yaw, cam.target.pitch, cam.target.radius, cam.target.fov
    end

    cam.dirty = true
    setDoors(preset.doors)
end

local function updateCamera(session, dt)
    local cam = session.cam
    local t = cam.target
    local k = 1.0 - math.exp(-dt * EASE_RATE)

    local dy = angleDiff(t.yaw, cam.yaw)
    local dp = t.pitch - cam.pitch
    local dr = t.radius - cam.radius
    local df = t.fov - cam.fov
    local doff = t.offset - cam.offset

    local moving = math.abs(dy) > 0.01 or math.abs(dp) > 0.01 or math.abs(dr) > 0.001
        or math.abs(df) > 0.01 or #doff > 0.001

    if moving then
        cam.yaw = (cam.yaw + dy * k) % 360.0
        cam.pitch = cam.pitch + dp * k
        cam.radius = cam.radius + dr * k
        cam.fov = cam.fov + df * k
        cam.offset = cam.offset + doff * k
    elseif cam.dirty then
        cam.yaw, cam.pitch, cam.radius, cam.fov, cam.offset = t.yaw % 360.0, t.pitch, t.radius, t.fov, t.offset
    end

    if moving or cam.dirty then
        cam.dirty = false
        local pos, focus = cameraWorld(session.vehicle, cam)
        SetCamCoord(cam.handle, pos.x, pos.y, pos.z)
        PointCamAtCoord(cam.handle, focus.x, focus.y, focus.z)
        SetCamFov(cam.handle, cam.fov)
    end

    return moving
end

local function startCamera(session)
    local d = dims(session.vehicle)
    local handle = CreateCam('DEFAULT_SCRIPTED_CAMERA', false)

    session.cam = {
        handle = handle, dims = d, focus = 'default',
        offset = d.centre, yaw = -45.0, pitch = 15.0, radius = d.base, fov = 45.0, dirty = true,
    }

    applyPreset('default', true)
    updateCamera(session, 0.0)

    SetCamActive(handle, true)
    RenderScriptCams(true, true, 900, true, false)

    CreateThread(function()
        while state == session and session.cam do
            local moving = updateCamera(session, GetFrameTime())
            -- Per frame only while the camera moves; input arrives via NUI callbacks
            Wait(moving and 0 or 30)
        end
    end)
end

local function stopCamera(session, ease)
    local cam = session.cam
    session.cam = nil

    RenderScriptCams(false, ease == true, ease and 600 or 0, true, false)

    if cam and DoesCamExist(cam.handle) then
        DestroyCam(cam.handle, false)
    end
end

-- ---------------------------------------------------------------------------
-- Closing
-- ---------------------------------------------------------------------------

function Tuning.IsOpen()
    return state ~= nil
end

---Close the tuning screen. `revert` restores the vehicle to the props it had when it was opened.
---@param revert boolean
---@param ease? boolean ease the camera back (default true)
function Tuning.Close(revert, ease)
    if not state then return end

    local s = state
    state = nil -- stops the camera/watch threads and blocks late NUI callbacks

    if DoesEntityExist(s.vehicle) then
        if revert then
            pcall(lib.setVehicleProperties, s.vehicle, s.original)
        end

        for door in pairs(s.doorsOpen) do
            SetVehicleDoorShut(s.vehicle, door, false)
        end
        if s.lightsForced then SetVehicleLights(s.vehicle, 0) end

        FreezeEntityPosition(s.vehicle, s.wasFrozen)
    end

    stopCamera(s, ease ~= false)

    SendNUIMessage({ action = 'closeTuning', data = {} })

    if not (Billing and Billing.IsOpen and Billing.IsOpen()) then
        SetNuiFocus(false, false)
        UI.BlockPauseMenu()
    end
end

-- ---------------------------------------------------------------------------
-- Opening
-- ---------------------------------------------------------------------------

---Open the tuning screen on a vehicle (workshop only).
---@param vehicle integer
function Tuning.Open(vehicle)
    if state or opening or swapping or Anim.IsBusy() then return end
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end

    if not Mechanic.IsMechanic() then
        notify(locale('not_mechanic'), 'error')
        return
    end

    if not Mechanic.InWorkshop() then
        notify(locale('not_in_workshop'), 'error')
        return
    end

    if IsPedInAnyVehicle(cache.ped, false) or not NetworkGetEntityIsNetworked(vehicle) then
        notify(locale('busy'), 'error')
        return
    end

    if NO_TUNING_CLASS[GetVehicleClass(vehicle)] then
        notify(locale('not_available'), 'error')
        return
    end

    opening = true

    CreateThread(function()
        local netId = NetworkGetNetworkIdFromEntity(vehicle)
        local ok, data = lib.callback.await('ap1le_mechanicjob:tuning:canOpen', false, netId)

        if not ok or type(data) ~= 'table' then
            notify(failText(data), 'error')
            opening = false
            return
        end

        if not DoesEntityExist(vehicle) or not Mechanic.RequestControl(vehicle) then
            notify(locale('error'), 'error')
            opening = false
            return
        end

        local original = lib.getVehicleProperties(vehicle)
        SetVehicleModKit(vehicle, 0)

        local prices = {}
        if type(data.prices) == 'table' then
            for id, price in pairs(data.prices) do
                if type(id) == 'string' and tonumber(price) then prices[id] = math.max(0, math.floor(tonumber(price))) end
            end
        end

        local stock = {}
        if type(data.stock) == 'table' then
            for item, count in pairs(data.stock) do
                if type(item) == 'string' then stock[item] = math.max(0, toInt(count) or 0) end
            end
        end

        local session = {
            vehicle = vehicle,
            netId = netId,
            original = original,
            owned = data.owned == true,
            prices = prices,
            stock = stock,
            workshop = data.workshop,
            nodes = {},
            pending = {},     -- node id -> last previewed value (context for dependent previews)
            lastRim = nil,    -- id of the rim node previewed last
            -- No native getter exists for the freeze state; vehicles are normally unfrozen in a workshop
            wasFrozen = false,
            doorsOpen = {},
            lightsForced = false,
            installing = false,
            ordering = false,
            cam = nil,
        }

        -- priceOf reads state.prices while the payload is built
        state = session
        local built, payload = pcall(buildPayload, vehicle, { owned = session.owned, levels = data.levels, stock = stock }, session.nodes)
        opening = false

        if not built then
            print(('[ap1le_mechanicjob] building the tuning menu failed: %s'):format(tostring(payload)))
            state = nil
            pcall(lib.setVehicleProperties, vehicle, original)
            notify(locale('error'), 'error')
            return
        end

        FreezeEntityPosition(vehicle, true)
        startCamera(session)

        SetNuiFocus(true, true)
        SendNUIMessage({ action = 'openTuning', data = payload })

        -- Light watchdog: close if the mechanic dies, walks away, loses the job or the car disappears
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

    local node = state.nodes[data.id]
    if not node or not DoesEntityExist(state.vehicle) then
        cb({ ok = false })
        return
    end

    local ok = node.apply(state.vehicle, data.value, state.pending) == true

    if ok then
        state.pending[node.id] = data.value
        if node.rim then state.lastRim = node.id end
    end

    cb({ ok = ok })
end)

RegisterNUICallback('tuning:camera', function(data, cb)
    local focus = type(data) == 'table' and data.focus

    if not state or not state.cam or type(focus) ~= 'string' or not CAMERA_FOCUS[focus] then
        cb({ ok = false })
        return
    end

    applyPreset(focus, false)
    cb({ ok = true })
end)

RegisterNUICallback('tuning:orbit', function(data, cb)
    local cam = state and state.cam
    local dx = type(data) == 'table' and tonumber(data.dx)
    local dy = type(data) == 'table' and tonumber(data.dy)

    if not cam or not dx or not dy or dx ~= dx or dy ~= dy then
        cb({ ok = false })
        return
    end

    dx = clamp(dx, -MAX_ORBIT_PX, MAX_ORBIT_PX)
    dy = clamp(dy, -MAX_ORBIT_PX, MAX_ORBIT_PX)

    local t = cam.target
    -- Drag right = the car turns right (camera moves left around it); drag down = look from higher
    t.yaw = (t.yaw - dx * ORBIT_DEG_PER_PX) % 360.0
    t.pitch = clamp(t.pitch + dy * PITCH_DEG_PER_PX, PITCH_MIN, PITCH_MAX)
    cam.dirty = true

    cb({ ok = true })
end)

RegisterNUICallback('tuning:zoom', function(data, cb)
    local cam = state and state.cam
    local delta = type(data) == 'table' and tonumber(data.delta)

    if not cam or not delta or delta ~= delta then
        cb({ ok = false })
        return
    end

    delta = clamp(delta, -MAX_ZOOM_DELTA, MAX_ZOOM_DELTA)

    local t = cam.target
    local radius = clamp(t.radius + delta * ZOOM_M_PER_UNIT, cam.dims.minR, cam.dims.maxR)

    -- Do not let the target sink into the car: zooming out again would take ages
    local pushed = boxPushOut(cam.dims, t.offset, direction(t.yaw, t.pitch), radius)
    if pushed > 0 then radius = math.min(pushed + 0.05, cam.dims.maxR) end

    t.radius = radius
    cam.dirty = true

    cb({ ok = true })
end)

RegisterNUICallback('tuning:close', function(_, cb)
    Tuning.Close(true)
    cb({ ok = true })
end)

-- ---------------------------------------------------------------------------
-- Ordering a missing part (Society pays; the crate arrives at the delivery point)
-- ---------------------------------------------------------------------------

RegisterNUICallback('tuning:order', function(data, cb)
    local item = type(data) == 'table' and data.item

    if not state or state.ordering or type(item) ~= 'string' or Config.Shop.items[item] == nil then
        cb({ ok = false, error = locale('error') })
        return
    end

    local session = state
    session.ordering = true

    CreateThread(function()
        local ok, result = lib.callback.await('ap1le_mechanicjob:order:place', false, { { item = item, count = 1 } })
        session.ordering = false

        if ok and type(result) == 'table' then
            local eta = math.max(0, toInt(result.eta) or 0)
            notify(locale('order_placed', itemLabel(item), math.max(1, math.ceil(eta / 60))), 'success')
            cb({ ok = true, eta = eta })
        else
            local text = failText(result)
            notify(text, 'error')
            cb({ ok = false, error = text })
        end
    end)
end)

-- ---------------------------------------------------------------------------
-- Cosmetic install
-- ---------------------------------------------------------------------------

---Group the NUI changes into billing entries (one per price id). Unknown ids, invalid values and
---values that would not change the car (compared to the original props) are dropped.
local function buildEntries(session, changes)
    -- Last value per node id; for rims only the type previewed last (they replace each other)
    local values, orderIds = {}, {}
    local lastRimChange = nil

    for i = 1, math.min(#changes, MAX_CHANGES) do
        local change = changes[i]
        local node = type(change) == 'table' and type(change.id) == 'string' and session.nodes[change.id]

        if node and change.value ~= nil then
            if values[node.id] == nil then orderIds[#orderIds + 1] = node.id end
            values[node.id] = change.value
            if node.rim and node.priceId == 'modFrontWheels' then lastRimChange = node.id end
        end
    end

    local keepRim = session.lastRim and values[session.lastRim] ~= nil and session.lastRim or lastRimChange

    -- Final values (context for dependent "unchanged" checks, e.g. neon colour with layout "none")
    local final = {}
    for id, value in pairs(values) do final[id] = value end
    if final.tyreSmoke ~= nil then final.tyreSmoke = toBool(final.tyreSmoke) end
    if final.neonLayout ~= nil then final.neonLayout = toInt(final.neonLayout) end

    local entries, byPrice = {}, {}

    for i = 1, #orderIds do
        local id = orderIds[i]
        local node = session.nodes[id]
        local value = values[id]
        local skip = node.rim and node.priceId == 'modFrontWheels' and id ~= keepRim

        if not skip and ANIM_TYPES[node.anim] and not node.unchanged(value, final, session.original) then
            local entry = byPrice[node.priceId]
            if not entry then
                local cfg = cosmeticById[node.priceId] or Config.Cosmetic.extras[node.priceId]
                entry = {
                    priceId = node.priceId,
                    anim = node.anim,
                    label = cfg and cfg.label or node.label,
                    price = priceOf(node.priceId),
                    items = {},
                }
                byPrice[node.priceId] = entry
                entries[#entries + 1] = entry
            end

            entry.items[#entry.items + 1] = { node = node, value = value }
        end
    end

    for i = 1, #entries do
        table.sort(entries[i].items, function(a, b) return (a.node.order or 1) < (b.node.order or 1) end)
    end

    return entries
end

---"Spoiler: Carbon", "Dækrøg: Til, #FF0000"
local function entryLabel(entry)
    local parts = {}
    for i = 1, #entry.items do
        local item = entry.items[i]
        local ok, text = pcall(item.node.valueLabel, item.value)
        if ok and type(text) == 'string' and text ~= '' then parts[#parts + 1] = text end
    end

    if #parts == 0 then return entry.label end
    return ('%s: %s'):format(entry.label, table.concat(parts, ', '))
end

---Invoice lines from the installed entries. Overflow beyond Config.Invoice.maxLines is merged.
local function buildInvoiceLines(entries)
    local lines = {}

    for i = 1, #entries do
        local entry = entries[i]
        local amount = clamp(math.floor(tonumber(entry.price) or 0), 0, Config.Invoice.maxTotal)

        if amount > 0 then
            local label = truncate(entryLabel(entry), 48)
            lines[#lines + 1] = { label = label, amount = amount, price = amount }
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
        last.price = last.amount
    end

    return lines
end

local function runInstall(session, changes)
    local vehicle = session.vehicle
    local ok, entries = pcall(buildEntries, session, changes)
    if not ok then
        print(('[ap1le_mechanicjob] tuning install: %s'):format(tostring(entries)))
        entries = {}
    end

    -- Back to the original look: the parts only appear once their animation is done
    Tuning.Close(true)

    if #entries == 0 then
        notify(locale('tuning_no_changes'), 'info')
        return
    end

    if not DoesEntityExist(vehicle) or not Mechanic.RequestControl(vehicle) then
        notify(locale('error'), 'error')
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
        notify(locale('tuning_installing', table.concat(labels, ', ')), 'info')

        if not Anim.Cosmetic(vehicle, order[i], Config.Cosmetic.animTime) then
            notify(locale('cancelled'), 'info')
            break
        end

        if not DoesEntityExist(vehicle) then return end
        Mechanic.RequestControl(vehicle)
        SetVehicleModKit(vehicle, 0)

        for n = 1, #group do
            local entry = group[n]
            local context = {}
            for m = 1, #entry.items do context[entry.items[m].node.id] = entry.items[m].value end
            if context.tyreSmoke ~= nil then context.tyreSmoke = toBool(context.tyreSmoke) end

            local any = false
            for m = 1, #entry.items do
                local item = entry.items[m]
                local done, result = pcall(item.node.apply, vehicle, item.value, context)
                if done and result then any = true end
            end

            if any then applied[#applied + 1] = entry end
        end
    end

    if #applied == 0 then return end

    -- Persist (owned vehicles only; the server merges whitelisted cosmetic keys)
    local props = lib.getVehicleProperties(vehicle)
    local saved, result = lib.callback.await('ap1le_mechanicjob:tuning:save', false, session.netId, props)

    if not saved then
        notify(failText(result), 'error')
    elseif type(result) == 'table' and result.saved == false then
        notify(locale('tuning_not_saved'), 'info')
    else
        notify(locale('tuning_saved'), 'success')
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
-- Performance swap: take the old part OUT, then put the new one IN (parts from the workshop stash)
-- ---------------------------------------------------------------------------

local function runSwap(vehicle, category, level)
    local cfg = Config.Performance[category]
    if not cfg or not DoesEntityExist(vehicle) then return end

    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    local ok, data = lib.callback.await('ap1le_mechanicjob:perf:begin', false, netId, category, level)

    if not ok or type(data) ~= 'table' then
        notify(failText(data), 'error')
        return
    end

    local function cancel()
        lib.callback.await('ap1le_mechanicjob:cancel', false)
    end

    if not Mechanic.RequestControl(vehicle) then
        cancel()
        notify(locale('error'), 'error')
        return
    end

    local oldLevel = math.tointeger(data.oldLevel) or 0
    local newLevel = math.tointeger(data.level) or level

    -- Step 1: old part out (engine: hood open, hoist, unbolt, lift out)
    if oldLevel > 0 then
        notify(locale('swap_removing', cfg.label), 'info')

        if not Anim.Swap(vehicle, category, 'remove', data.removeTime) then
            cancel()
            notify(locale('cancelled'), 'info')
            return
        end

        -- The old part is out: show the car without it
        Mechanic.RequestControl(vehicle)
        setPerformanceMod(vehicle, cfg, 0)
    end

    -- Step 2: new part in (fetch, lift in, bolt down, close up)
    if newLevel > 0 then
        notify(locale('swap_installing', cfg.label), 'info')

        if not Anim.Swap(vehicle, category, 'install', data.installTime) then
            cancel()
            Mechanic.RequestControl(vehicle)
            setPerformanceMod(vehicle, cfg, oldLevel) -- the old part goes back on visually
            notify(locale('cancelled'), 'info')
            return
        end
    end

    local finished, result = lib.callback.await('ap1le_mechanicjob:perf:finish', false)

    if not finished then
        if DoesEntityExist(vehicle) then
            Mechanic.RequestControl(vehicle)
            setPerformanceMod(vehicle, cfg, oldLevel)
        end
        notify(failText(result), 'error')
        return
    end

    local finalLevel = type(result) == 'table' and math.tointeger(result.level) or newLevel

    if DoesEntityExist(vehicle) then
        Mechanic.RequestControl(vehicle)
        setPerformanceMod(vehicle, cfg, finalLevel)
    end

    if finalLevel > 0 then
        local levelLabel = cfg.toggle and cfg.label or locale('ui_level', finalLevel)
        notify(locale('swap_done', cfg.label, levelLabel), 'success')
    else
        notify(locale('swap_removed', cfg.label), 'success')
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

    if not state.owned then
        local text = locale('not_owned')
        notify(text, 'error')
        cb({ ok = false, error = text })
        return
    end

    -- Quick client-side stock check (the server checks the stash again in perf:begin)
    local item = level > 0 and cfg.levels[level]
    if item and (state.stock[item] or 0) < 1 then
        local text = locale('stock_missing')
        notify(text, 'error')
        cb({ ok = false, error = text })
        return
    end

    local vehicle = state.vehicle
    swapping = true

    -- Discard any cosmetic preview, close the screen, then do the physical work
    Tuning.Close(true)
    cb({ ok = true })

    CreateThread(function()
        local done, err = pcall(runSwap, vehicle, category, level)
        if not done then
            print(('[ap1le_mechanicjob] swap error: %s'):format(tostring(err)))
        end
        swapping = false
    end)
end)

-- ---------------------------------------------------------------------------
-- Cleanup
-- ---------------------------------------------------------------------------

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    if state then
        Tuning.Close(true, false)
    end

    -- Make sure no scripted camera survives the restart
    RenderScriptCams(false, false, 0, true, false)
end)
